import AppKit
import SwiftUI

/// App entry point: the main window, settings, and keyboard-driven commands.
@main
struct TextTidyWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = TidyModel.shared

    var body: some Scene {
        Window("TextTidyWindow", id: "main") {
            ContentView().environmentObject(model)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Text File…") { model.openFile() }.keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Paste Into Original") { model.pasteAndFocus() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Copy Result") { model.copyResult() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Swap Result Into Original") { model.swapResultIntoOriginal() }
            }
            CommandGroup(replacing: .help) {
                Button("Support / Donate ❤️") { openDonationPage() }
            }
        }
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// Handles launch-time behaviour and the "Tidy Text" system service.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if UserDefaults.standard.bool(forKey: "autoPaste"),
           let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            Task { @MainActor in TidyModel.shared.replaceInput(with: text) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Services handler: cleans the selected text with the current pipeline and writes it back in place.
    @objc func tidyText(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else {
            error.pointee = "No text was provided." as NSString
            return
        }
        let pipeline = UserDefaults.standard.stringArray(forKey: TidyModel.pipelineKey) ?? []
        let cleaned = Cleaners.run(text, pipeline: pipeline)
        pboard.clearContents()
        pboard.setString(cleaned, forType: .string)
    }
}
