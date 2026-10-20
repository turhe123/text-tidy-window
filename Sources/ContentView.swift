import AppKit
import SwiftUI

/// Opens the project's donation page.
func openDonationPage() {
    if let url = URL(string: "https://ko-fi.com/leodavidai") { NSWorkspace.shared.open(url) }
}

/// The main document-style window: cleaner sidebar, original/result panes, find & replace and footer.
struct ContentView: View {
    @EnvironmentObject var model: TidyModel
    @AppStorage("fontSize") private var fontSize = 13.0
    @State private var showSavePreset = false
    @State private var presetName = ""

    var body: some View {
        NavigationSplitView {
            CleanerSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if model.isLarge {
                    Label("Large text (over 2 MB) — cleaning runs in the background and may take a moment.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                }
                HSplitView {
                    pane(title: "Original") {
                        TextPane(text: $model.input, editable: true, fontSize: fontSize) { model.inputTextView = $0 }
                            .overlay(alignment: .topLeading) {
                                if model.input.isEmpty {
                                    Text("Paste or drop text here")
                                        .font(.system(size: fontSize)).foregroundStyle(.tertiary)
                                        .padding(.horizontal, 11).padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    pane(title: model.isWorking ? "Result (updating…)" : "Result") {
                        TextPane(text: .constant(model.output), editable: false, fontSize: fontSize)
                    }
                }
                Divider()
                FindReplaceRow()
                Divider()
                footer
            }
        }
        .toolbar { toolbarContent }
        .alert("Save Preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") { model.savePreset(named: presetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the enabled cleaners and their order.")
        }
        .frame(minWidth: 860, minHeight: 480)
    }

    private func pane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
            content()
        }
        .frame(minWidth: 220, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        let a = TextStats(model.input), b = TextStats(model.output)
        return HStack {
            Text("Original: \(a.chars) chars · \(a.words) words · \(a.lines) lines")
            Spacer()
            Text(model.diffSummary).fontWeight(.medium)
            Spacer()
            Text("Result: \(b.chars) chars · \(b.words) words · \(b.lines) lines")
        }
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.pasteAndFocus() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .help("Replace the original with clipboard text (⇧⌘V)")
            Button { model.copyResult() } label: { Label("Copy Result", systemImage: "doc.on.doc") }
                .help("Copy the cleaned result (⇧⌘C)")
            Button { model.swapResultIntoOriginal() } label: { Label("Swap Result Into Original", systemImage: "arrow.left.arrow.right") }
                .help("Replace the original with the result (undoable)")
            Button { presetName = model.selectedPreset ?? ""; showSavePreset = true } label: {
                Label("Save Preset", systemImage: "square.and.arrow.down")
            }
            .help("Save the current cleaners as a named preset")
            presetMenu
            Button { openDonationPage() } label: { Label("Support / Donate ❤️", systemImage: "heart.fill") }
                .help("Support / Donate ❤️")
        }
    }

    private var presetMenu: some View {
        Menu {
            if model.presets.isEmpty { Text("No saved presets") }
            ForEach(model.presets) { preset in
                Button { model.apply(preset) } label: {
                    if preset.name == model.selectedPreset { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                }
            }
            if !model.presets.isEmpty {
                Divider()
                Menu("Delete Preset") {
                    ForEach(model.presets) { preset in Button(preset.name) { model.deletePreset(preset) } }
                }
            }
        } label: {
            Label(model.selectedPreset ?? "Presets", systemImage: "slider.horizontal.3")
        }
        .help("Apply a saved preset")
    }
}

/// Grouped cleaner toggles plus the reorderable pipeline list.
struct CleanerSidebar: View {
    @EnvironmentObject var model: TidyModel

    var body: some View {
        List {
            ForEach(Cleaners.groups, id: \.self) { group in
                Section(group) {
                    ForEach(Cleaners.all.filter { $0.group == group }) { cleaner in
                        Toggle(cleaner.title, isOn: Binding(
                            get: { model.isEnabled(cleaner.id) },
                            set: { model.setEnabled(cleaner.id, $0) }))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Section {
                if model.pipeline.isEmpty {
                    Text("No cleaners enabled").foregroundStyle(.secondary)
                }
                ForEach(Array(model.pipeline.enumerated()), id: \.element) { index, id in
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(Cleaners.byID[id]?.title ?? id)
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                    }
                }
                .onMove { model.pipeline.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Pipeline (drag to reorder)")
                    Spacer()
                    Button("Reset Order") { model.resetOrder() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// The custom final cleaner: find & replace with optional regular expressions.
struct FindReplaceRow: View {
    @EnvironmentObject var model: TidyModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $model.findText).textFieldStyle(.roundedBorder)
            TextField("Replace with", text: $model.replaceText).textFieldStyle(.roundedBorder)
            Toggle("Regex", isOn: $model.useRegex).toggleStyle(.checkbox)
            if let error = model.findError {
                Text("\(error) — skipped").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}
