import Foundation

enum HTMLText {
    static func plainText(fromHTML html: String) -> String {
        html
            .replacing(/(?s)<!--.*?-->/, with: "")
            .replacing(/(?is)<(script|style)\b.*?<\/\1\s*>/, with: " ")
            .replacing(/\s+/, with: " ")
            .replacing(/(?i)<\/?(p|div|br|tr|li|h[1-6]|table|ul|ol|blockquote)\b[^>]*>/, with: "\n")
            .replacing(/<[^>]*>/, with: "")
            .replacing(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);/) { match in
                decodeEntity(String(match.output.1)) ?? String(match.output.0)
            }
    }

    private static func decodeEntity(_ name: String) -> String? {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        if let value = named[name.lowercased()] { return value }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let scalar = digits.lowercased().hasPrefix("x")
            ? UInt32(digits.dropFirst(), radix: 16)
            : UInt32(digits)
        return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}

enum TextNormalizer {
    /// Collapses runs of spaces, trims every line and drops empty lines.
    /// No per-line regex: its fixed cost per run made a text of many short lines take seconds.
    static func normalize(_ text: String) -> String {
        text.split(separator: "\n")
            .map { line in
                line.split { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum LinkDomains {
    /// How far around a cut `unfinishedLinkStart` looks; a real link's scheme, user info and host fit well within it.
    private static let window = 1024

    // Skip `user@` so `https://paypal.com@evil.example` yields the real host.
    private static var pattern: Regex<(Substring, Substring)> { /(?i)https?:\/\/(?:[^\s\/?#@"'<>]*@)?([a-z0-9.-]+)/ }

    static func extract(from text: String) -> [String] {
        var seen: Set<String> = []
        return text.matches(of: pattern)
            .map { $0.output.1.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Where to cut `text` instead of at `end` so that the last link before `end` keeps the host it has in the
    /// whole text; nil when no link is affected.
    static func unfinishedLinkStart(in text: String, cutAt end: String.Index) -> String.Index? {
        let scalars = text.unicodeScalars
        let from = scalars[..<end].suffix(window).startIndex
        let to = scalars.index(end, offsetBy: window, limitedBy: scalars.endIndex) ?? scalars.endIndex
        guard let cut = Substring(scalars[from..<end]).matches(of: pattern).last else { return nil }
        let whole = Substring(scalars[cut.range.lowerBound..<to]).firstMatch(of: pattern)
        return whole?.output.1 == cut.output.1 ? nil : cut.range.lowerBound
    }
}
