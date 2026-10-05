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
    static func normalize(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.replacing(/[ \t\u{00A0}]+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum LinkDomains {
    static func extract(from texts: [String]) -> [String] {
        var seen: Set<String> = []
        return texts.flatMap { text in
            // Skip `user@` so `https://paypal.com@evil.example` yields the real host.
            text.matches(of: /(?i)https?:\/\/(?:[^\s\/?#@"'<>]*@)?([a-z0-9.-]+)/).map { $0.output.1.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
