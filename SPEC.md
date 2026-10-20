# TextTidyWindow — specification

**Tagline:** Paste messy text, toggle cleaners like fixing line breaks or smart quotes, and copy the tidy result.

**Category:** Text & Input

**Inspired by (paid):** TextSoap ($19.99 one-time)

**Frameworks:** SwiftUI, AppKit, Foundation, UniformTypeIdentifiers

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. TextSoap from Unmarked Software cleans up text pasted from PDFs, emails and web pages with more than a hundred built-in cleaners such as fixing hard line breaks, removing extra spaces, converting quotes and stripping markup, and it lets you stack cleaners into custom workflows. It has sold since the early days of the Mac, appeared in many bundle deals at about 19.99 dollars, and writers, editors and researchers keep recommending it for taming copied text. Our version is a focused document-style window with a live before and after, not an automatic clipboard rule engine.

Feature set for our clean-room version. A window app with two panes. The left pane is the original text, which the user can type into, paste or fill by dropping a text file. The right pane shows the cleaned result updating live. A sidebar of toggle cleaners is arranged in groups. Whitespace: trim lines, collapse multiple spaces, remove blank lines, collapse blank lines to one, convert tabs to spaces. Line breaks: join hard-wrapped lines into paragraphs, convert line endings. Characters: convert curly quotes and dashes to plain or the reverse, remove zero width and non-breaking characters, strip accents optionally, remove emoji. Structure: remove duplicate lines, sort lines ascending or descending, add or remove line numbers, add bullet prefix. Markup: strip HTML tags and decode entities. Case: lower, upper, title and sentence case. Cleaners run in a fixed sensible order, and the order can be changed by dragging in a Pipeline list. Presets can be saved by name.

UI spec. A single window with a toolbar containing Paste, Copy Result, Swap Result Into Original, Save Preset and a preset popup. A footer shows character, word and line counts for both panes and a small diff summary such as 42 characters removed. A Find and Replace row with an optional regular expression toggle acts as a final custom cleaner. Settings are small: default preset, font size and whether to auto-paste clipboard text on open. Empty state: a gray hint in the left pane reading Paste or drop text here. The app also registers a Services menu entry named Tidy Text so selected text in other apps can be cleaned in place. Keyboard: Command Shift V to paste and focus, Command Shift C to copy the result.

Technical approach. Implement each cleaner as a small pure function from String to String, collected in an array of structs with id, group, title and closure, which keeps the code short and testable. Use NSRegularExpression for patterns, NSString transformations such as applyingTransform with strip combining marks for accent removal, and a lightweight HTML stripper based on regular expressions plus decoding common entities, falling back to NSAttributedString HTML import only on the main thread if needed. Recompute the output in a debounced task so very large text stays responsive. Presets are Codable arrays of enabled cleaner identifiers saved in Application Support. Provide a Services handler by implementing an NSServices entry in the app's bundle information and a method on the app delegate that reads from and writes to the pasteboard.

Edge cases and error handling. Invalid regular expressions in Find and Replace show a red message and are skipped. Very large inputs over a few megabytes show a warning and run in a background task. Keep the original text untouched until the user chooses Swap. Preserve intentional paragraph breaks when joining wrapped lines by only joining single newlines. Handle mixed Windows and Unix line endings. Undo works on the original pane through the standard text view undo manager. Keep the code near 550 lines.
