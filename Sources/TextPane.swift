import AppKit
import SwiftUI

/// NSTextView subclass that accepts dropped text files and loads their contents undoably.
final class DropTextView: NSTextView {
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if isEditable,
           let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first {
            guard let text = TidyModel.readText(url) else { NSSound.beep(); return false }
            let range = NSRange(location: 0, length: (string as NSString).length)
            if shouldChangeText(in: range, replacementString: text) {
                replaceCharacters(in: range, with: text)
                didChangeText()
            }
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// A scrollable plain-text pane wrapping NSTextView (editable original or read-only result).
struct TextPane: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var fontSize: Double
    var onCreate: ((NSTextView) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let tv = DropTextView(frame: .zero)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isEditable = editable
        tv.isSelectable = true
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.registerForDraggedTypes([.fileURL])
        tv.delegate = context.coordinator
        tv.string = text
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        onCreate?(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        if tv.font != font { tv.font = font }
        if tv.string != text { tv.string = text }
    }

    /// Pushes user edits back into the SwiftUI binding.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextPane
        init(_ parent: TextPane) { self.parent = parent }
        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
