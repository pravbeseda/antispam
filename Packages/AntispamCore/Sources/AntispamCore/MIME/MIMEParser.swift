import Foundation

public struct ParsedMessage: Sendable {
    public let headers: [(name: String, value: String)]
    public let bodyText: String
    public let linkDomains: [String]

    public func values(of name: String) -> [String] {
        headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
}

public enum MIMEParser {
    static let maxNestingDepth = 16
    /// HTML cleanup is regex-based and slow on huge parts; Jev reads far less, and filler that pushes
    /// the real text past this limit is costly and conspicuous.
    static let maxTextLength = 512 * 1024

    public static func parse(_ data: Data) -> ParsedMessage {
        // ISO Latin-1 maps every byte to one character, so the structure can be parsed as text
        // and each part's bytes recovered losslessly for its own charset.
        let raw = String(data: data, encoding: .isoLatin1)!.replacingOccurrences(of: "\r\n", with: "\n")
        let root = MIMEEntity(parsing: raw)

        var plain: [String] = []
        var html: [String] = []
        collectText(from: root, depth: 0, plain: &plain, html: &html)

        // Spam often pairs an empty plain part with the real HTML to slip past text-only filters.
        let body = plain.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? html.first.map(HTMLText.plainText(fromHTML:)) ?? ""
        return ParsedMessage(
            headers: root.headers.map { ($0.name, EncodedWords.decode(Charset.decodeHeader($0.value))) },
            bodyText: TextNormalizer.normalize(body),
            // One pass over all parts: each regex run has a fixed cost that adds up over thousands of tiny parts.
            linkDomains: LinkDomains.extract(from: (plain + html).joined(separator: "\n"))
        )
    }

    private static func collectText(from entity: MIMEEntity, depth: Int, plain: inout [String], html: inout [String]) {
        guard !entity.isAttachment else { return }
        // Parsing cost grows with depth × size, and crafted mail can nest hundreds of levels; real mail stays a few deep.
        if depth < maxNestingDepth, let parts = entity.multipartChildren {
            parts.forEach { collectText(from: $0, depth: depth + 1, plain: &plain, html: &html) }
            return
        }
        let text = { truncated(entity.decodedText) }
        switch entity.contentType.mediaType {
        case "text/plain": plain.append(text())
        case "text/html": html.append(text())
        default: break
        }
    }

    /// Cuts at a whitespace so a link straddling the limit is dropped rather than left with a truncated host;
    /// text with no whitespace at all is cut at the limit, so it cannot empty the part.
    private static func truncated(_ text: String) -> String {
        let head = text.prefix(maxTextLength)
        guard head.endIndex < text.endIndex else { return text }
        return String(head[..<(head.lastIndex(where: \.isWhitespace) ?? head.endIndex)])
    }
}
