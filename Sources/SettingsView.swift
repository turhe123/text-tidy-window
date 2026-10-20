import SwiftUI

/// Preferences: default preset, editor font size, auto-paste on open, and the donation link.
struct SettingsView: View {
    @EnvironmentObject var model: TidyModel
    @AppStorage("defaultPreset") private var defaultPreset = ""
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("autoPaste") private var autoPaste = false

    var body: some View {
        Form {
            Picker("Default preset:", selection: $defaultPreset) {
                Text("None (restore last session)").tag("")
                ForEach(model.presets) { Text($0.name).tag($0.name) }
            }
            Stepper(value: $fontSize, in: 9...28, step: 1) {
                Text("Font size: \(Int(fontSize)) pt")
            }
            Toggle("Paste clipboard text into the original on open", isOn: $autoPaste)
            Text("Tip: select text in any app and choose Services ▸ Tidy Text to clean it in place with the current pipeline.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button { openDonationPage() } label: { Label("Support / Donate ❤️", systemImage: "heart.fill") }
                    .controlSize(.large)
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
    }
}
