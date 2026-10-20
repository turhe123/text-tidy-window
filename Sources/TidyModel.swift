import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A named, saved set of enabled cleaners in execution order.
struct Preset: Codable, Identifiable, Hashable {
    var name: String
    var pipeline: [String]
    var id: String { name }
}

/// Loads and saves presets as JSON in Application Support.
enum PresetStore {
    static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("TextTidyWindow", isDirectory: true).appendingPathComponent("presets.json")
    }

    static func load() -> [Preset] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }

    static func save(_ presets: [Preset]) {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(presets).write(to: url, options: .atomic)
        } catch {
            NSLog("TextTidyWindow: could not save presets: \(error)")
        }
    }
}

/// Text statistics shown in the footer.
struct TextStats {
    let chars: Int, words: Int, lines: Int
    init(_ s: String) {
        chars = s.count
        words = s.split(whereSeparator: { $0.isWhitespace }).count
        lines = s.isEmpty ? 0 : s.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
    }
}

/// Central app state: original text, cleaner pipeline, presets and the debounced live result.
@MainActor
final class TidyModel: ObservableObject {
    static let shared = TidyModel()
    static let largeThreshold = 2_000_000
    nonisolated static let pipelineKey = "currentPipeline"

    @Published var input = "" { didSet { scheduleRecompute() } }
    @Published private(set) var output = ""
    @Published private(set) var isWorking = false
    @Published var pipeline: [String] { didSet { persistPipeline(); scheduleRecompute() } }
    @Published var findText = "" { didSet { scheduleRecompute() } }
    @Published var replaceText = "" { didSet { scheduleRecompute() } }
    @Published var useRegex = false { didSet { scheduleRecompute() } }
    @Published var presets: [Preset] = PresetStore.load()
    @Published var selectedPreset: String?

    /// The editable text view of the original pane, used so programmatic edits are undoable.
    weak var inputTextView: NSTextView?
    private var task: Task<Void, Never>?

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.pipelineKey)
        pipeline = saved ?? ["zeroWidth", "trimLines", "collapseSpaces", "collapseBlank"]
        let defaultName = UserDefaults.standard.string(forKey: "defaultPreset") ?? ""
        if let preset = presets.first(where: { $0.name == defaultName }) { apply(preset) }
    }

    var findReplace: FindReplace { FindReplace(find: findText, replace: replaceText, isRegex: useRegex) }
    var findError: String? { findReplace.validationError }
    var isLarge: Bool { input.utf8.count > Self.largeThreshold }

    var diffSummary: String {
        let delta = output.count - input.count
        if input == output { return "No changes" }
        if delta == 0 { return "Text changed, same length" }
        return "\(abs(delta)) character\(abs(delta) == 1 ? "" : "s") \(delta < 0 ? "removed" : "added")"
    }

    // MARK: Pipeline

    func isEnabled(_ id: String) -> Bool { pipeline.contains(id) }

    /// Enables a cleaner at its default position relative to the current pipeline, or disables it.
    func setEnabled(_ id: String, _ on: Bool) {
        if !on { pipeline.removeAll { $0 == id }; return }
        guard !pipeline.contains(id) else { return }
        let idx = Cleaners.defaultIndex(id)
        let pos = pipeline.firstIndex { Cleaners.defaultIndex($0) > idx } ?? pipeline.count
        pipeline.insert(id, at: pos)
    }

    func resetOrder() { pipeline.sort { Cleaners.defaultIndex($0) < Cleaners.defaultIndex($1) } }

    private func persistPipeline() { UserDefaults.standard.set(pipeline, forKey: Self.pipelineKey) }

    /// Debounces recomputation and runs the pipeline off the main thread.
    private func scheduleRecompute() {
        task?.cancel()
        let text = input, steps = pipeline
        let fr: FindReplace? = findError == nil ? findReplace : nil
        let delay: UInt64 = text.utf8.count > 200_000 ? 350_000_000 : 120_000_000
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.isWorking = true
            let result = await Task.detached(priority: .userInitiated) {
                Cleaners.run(text, pipeline: steps, find: fr)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.output = result
            self.isWorking = false
        }
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        pipeline = preset.pipeline.filter { Cleaners.byID[$0] != nil }
        selectedPreset = preset.name
    }

    func savePreset(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets.removeAll { $0.name == name }
        presets.append(Preset(name: name, pipeline: pipeline))
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selectedPreset = name
        PresetStore.save(presets)
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0 == preset }
        if selectedPreset == preset.name { selectedPreset = nil }
        PresetStore.save(presets)
    }

    // MARK: Actions

    /// Replaces the original text through the text view so the change can be undone.
    func replaceInput(with text: String) {
        if let tv = inputTextView {
            let range = NSRange(location: 0, length: (tv.string as NSString).length)
            if tv.shouldChangeText(in: range, replacementString: text) {
                tv.replaceCharacters(in: range, with: text)
                tv.didChangeText()
            }
        } else {
            input = text
        }
    }

    func pasteAndFocus() {
        if let s = NSPasteboard.general.string(forType: .string) { replaceInput(with: s) }
        if let tv = inputTextView { tv.window?.makeFirstResponder(tv) }
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    func swapResultIntoOriginal() { replaceInput(with: output) }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .html, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let text = Self.readText(url) { replaceInput(with: text) } else { NSSound.beep() }
    }

    /// Reads a text file, trying to detect its encoding and falling back to UTF-8 / Latin-1.
    nonisolated static func readText(_ url: URL) -> String? {
        var enc = String.Encoding.utf8
        if let s = try? String(contentsOf: url, usedEncoding: &enc) { return s }
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
