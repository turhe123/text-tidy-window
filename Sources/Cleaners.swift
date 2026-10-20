import Foundation

/// A single text transformation: a pure function from String to String plus display metadata.
struct Cleaner: Identifiable {
    let id: String
    let group: String
    let title: String
    let apply: (String) -> String
}

/// The catalogue of built-in cleaners, listed in their default (sensible) execution order.
enum Cleaners {
    static let groups = ["Markup", "Characters", "Whitespace", "Line Breaks", "Structure", "Case"]

    static let all: [Cleaner] = [
        Cleaner(id: "stripHTML", group: "Markup", title: "Strip HTML tags & decode entities", apply: stripHTML),
        Cleaner(id: "zeroWidth", group: "Characters", title: "Remove zero-width & non-breaking chars", apply: removeInvisible),
        Cleaner(id: "smartToPlain", group: "Characters", title: "Curly quotes & dashes → plain", apply: smartToPlain),
        Cleaner(id: "plainToSmart", group: "Characters", title: "Plain quotes & dashes → curly", apply: plainToSmart),
        Cleaner(id: "stripAccents", group: "Characters", title: "Strip accents", apply: {
            $0.applyingTransform(.stripCombiningMarks, reverse: false) ?? $0
        }),
        Cleaner(id: "removeEmoji", group: "Characters", title: "Remove emoji", apply: removeEmoji),
        Cleaner(id: "tabsToSpaces", group: "Whitespace", title: "Convert tabs to spaces", apply: {
            $0.replacingOccurrences(of: "\t", with: "    ")
        }),
        Cleaner(id: "trimLines", group: "Whitespace", title: "Trim lines", apply: {
            mapLines($0) { $0.trimmingCharacters(in: .whitespaces) }
        }),
        Cleaner(id: "collapseSpaces", group: "Whitespace", title: "Collapse multiple spaces", apply: {
            regex($0, " {2,}", " ")
        }),
        Cleaner(id: "joinLines", group: "Line Breaks", title: "Join hard-wrapped lines", apply: joinWrapped),
        Cleaner(id: "removeBlank", group: "Whitespace", title: "Remove blank lines", apply: {
            lines($0).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        }),
        Cleaner(id: "collapseBlank", group: "Whitespace", title: "Collapse blank lines to one", apply: {
            regex($0, "\\n[ \\t]*\\n(?:[ \\t]*\\n)+", "\n\n")
        }),
        Cleaner(id: "dedupe", group: "Structure", title: "Remove duplicate lines", apply: {
            var seen = Set<String>()
            return lines($0).filter { seen.insert($0).inserted }.joined(separator: "\n")
        }),
        Cleaner(id: "sortAsc", group: "Structure", title: "Sort lines A → Z", apply: {
            lines($0).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        }),
        Cleaner(id: "sortDesc", group: "Structure", title: "Sort lines Z → A", apply: {
            lines($0).sorted { $0.localizedStandardCompare($1) == .orderedDescending }.joined(separator: "\n")
        }),
        Cleaner(id: "removeNumbers", group: "Structure", title: "Remove line numbers", apply: {
            regex($0, "(?m)^[ \\t]*\\d+[.):][ \\t]+", "")
        }),
        Cleaner(id: "addNumbers", group: "Structure", title: "Add line numbers", apply: {
            lines($0).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }),
        Cleaner(id: "addBullets", group: "Structure", title: "Add bullet prefix", apply: {
            mapLines($0) { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : "• " + $0 }
        }),
        Cleaner(id: "lower", group: "Case", title: "lowercase", apply: { $0.lowercased() }),
        Cleaner(id: "upper", group: "Case", title: "UPPERCASE", apply: { $0.uppercased() }),
        Cleaner(id: "title", group: "Case", title: "Title Case", apply: { $0.capitalized }),
        Cleaner(id: "sentence", group: "Case", title: "Sentence case", apply: sentenceCase),
        Cleaner(id: "crlf", group: "Line Breaks", title: "Use Windows line endings (CRLF)", apply: {
            $0.replacingOccurrences(of: "\n", with: "\r\n")
        }),
    ]

    static let byID: [String: Cleaner] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func defaultIndex(_ id: String) -> Int { all.firstIndex { $0.id == id } ?? Int.max }

    /// Runs the given pipeline. Line endings are always normalised to `\n` first.
    static func run(_ text: String, pipeline: [String], find: FindReplace? = nil) -> String {
        var out = normalizeLineEndings(text)
        for id in pipeline { if let c = byID[id] { out = c.apply(out) } }
        if let find { out = find.apply(out) }
        return out
    }

    // MARK: - Helpers

    static func normalizeLineEndings(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func lines(_ s: String) -> [String] { s.components(separatedBy: "\n") }

    static func mapLines(_ s: String, _ f: (String) -> String) -> String {
        lines(s).map(f).joined(separator: "\n")
    }

    static func regex(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Joins single newlines inside paragraphs; blank-line paragraph breaks are preserved.
    static func joinWrapped(_ s: String) -> String {
        regex(regex(s, "(?<=\\S)-\\n(?=[a-z])", "-"), "([^\\n])[ \\t]*\\n(?![ \\t]*\\n)[ \\t]*(?=\\S)", "$1 ")
    }

    static func removeInvisible(_ s: String) -> String {
        let spaces = regex(s, "[\\u00A0\\u2007\\u202F]", " ")
        return regex(spaces, "[\\u200B\\u200C\\u200D\\u2060\\uFEFF\\u00AD]", "")
    }

    static func smartToPlain(_ s: String) -> String {
        let map: [(String, String)] = [("‘", "'"), ("’", "'"), ("‚", "'"), ("‛", "'"), ("“", "\""), ("”", "\""),
                                       ("„", "\""), ("‟", "\""), ("—", "--"), ("–", "-"), ("…", "..."), ("′", "'"), ("″", "\"")]
        return map.reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    static func plainToSmart(_ s: String) -> String {
        var out = regex(s, "(^|[\\s(\\[{])\"", "$1“")
        out = out.replacingOccurrences(of: "\"", with: "”")
        out = regex(out, "(^|[\\s(\\[{])'", "$1‘")
        out = out.replacingOccurrences(of: "'", with: "’")
        out = out.replacingOccurrences(of: "--", with: "—")
        return out.replacingOccurrences(of: "...", with: "…")
    }

    static func removeEmoji(_ s: String) -> String {
        String(s.filter { ch in
            let scalars = ch.unicodeScalars
            if scalars.contains(where: { $0.properties.isEmojiPresentation }) { return false }
            if let first = scalars.first, first.properties.isEmoji, first.value > 0xFF,
               scalars.contains(where: { $0.value == 0xFE0F }) { return false }
            return true
        })
    }

    static func sentenceCase(_ s: String) -> String {
        let lower = s.lowercased() as NSString
        let out = NSMutableString(string: lower)
        guard let re = try? NSRegularExpression(pattern: "(^|[.!?]\\s+|\\n\\s*)(\\p{L})") else { return s }
        for m in re.matches(in: lower as String, range: NSRange(location: 0, length: lower.length)) {
            let r = m.range(at: 2)
            out.replaceCharacters(in: r, with: lower.substring(with: r).uppercased())
        }
        return out as String
    }

    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®",
        "trade": "™", "bull": "•", "middot": "·", "deg": "°", "euro": "€", "pound": "£", "laquo": "«", "raquo": "»",
    ]

    /// Lightweight regex-based HTML stripper that keeps block-level breaks and decodes common entities.
    static func stripHTML(_ s: String) -> String {
        var out = regex(s, "(?is)<(script|style|head)[^>]*>.*?</\\1>", "")
        out = regex(out, "(?is)<!--.*?-->", "")
        out = regex(out, "(?i)<br\\s*/?>", "\n")
        out = regex(out, "(?i)</(p|div|h[1-6]|li|tr|blockquote|pre)>", "\n")
        out = regex(out, "(?i)<li[^>]*>", "• ")
        out = regex(out, "<[^>]+>", "")
        return decodeEntities(out)
    }

    static func decodeEntities(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return s }
        let ns = s as NSString
        let result = NSMutableString(string: ns)
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: m.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = entities[name.lowercased()]
            }
            if let replacement { result.replaceCharacters(in: m.range, with: replacement) }
        }
        return result as String
    }
}

/// The final, user-defined find & replace step. Invalid regexes are reported and skipped.
struct FindReplace {
    var find: String
    var replace: String
    var isRegex: Bool

    /// Returns an error message if the pattern is an invalid regular expression.
    var validationError: String? {
        guard isRegex, !find.isEmpty else { return nil }
        do { _ = try NSRegularExpression(pattern: find); return nil } catch { return "Invalid regular expression" }
    }

    func apply(_ s: String) -> String {
        guard !find.isEmpty else { return s }
        guard isRegex else { return s.replacingOccurrences(of: find, with: replace) }
        guard let re = try? NSRegularExpression(pattern: find, options: [.anchorsMatchLines]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: replace)
    }
}
