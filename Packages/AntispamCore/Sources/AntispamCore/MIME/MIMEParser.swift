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
    /// Shared by all text parts. HTML cleanup is regex-based and slow on huge text; Jev reads far less,
    /// and filler that pushes the real text past this limit is costly and conspicuous.
    static let maxTextBytes = 512 * 1024

    public static func parse(_ data: Data) -> ParsedMessage {
        // ISO Latin-1 maps every byte to one character, so the structure can be parsed as text
        // and each part's bytes recovered losslessly for its own charset.
        let raw = String(data: data, encoding: .isoLatin1)!.replacingOccurrences(of: "\r\n", with: "\n")
        let root = MIMEEntity(parsing: raw)

        var plain: [String] = []
        var html: [String] = []
        var budget = maxTextBytes
        collectText(from: root, depth: 0, budget: &budget, plain: &plain, html: &html)

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

    private static func collectText(
        from entity: MIMEEntity, depth: Int, budget: inout Int, plain: inout [String], html: inout [String]
    ) {
        guard !entity.isAttachment, budget > 0 else { return }
        // Parsing cost grows with depth × size, and crafted mail can nest hundreds of levels; real mail stays a few deep.
        if depth < maxNestingDepth, let parts = entity.multipartChildren {
            parts.forEach { collectText(from: $0, depth: depth + 1, budget: &budget, plain: &plain, html: &html) }
            return
        }
        let type = entity.contentType.mediaType
        guard type == "text/plain" || type == "text/html" else { return }
        let decoded = entity.decodedText
        let text = truncated(decoded, toBytes: budget)
        // A cut spends the budget even if it kept less, so later parts are not decoded for a few leftover bytes.
        budget = text.utf8.count < decoded.utf8.count ? 0 : budget - text.utf8.count
        if type == "text/plain" { plain.append(text) } else { html.append(text) }
    }

    /// Cuts at the limit; a link still open there is dropped rather than left with a truncated host.
    private static func truncated(_ text: String, toBytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: limit)
        while end.samePosition(in: text.unicodeScalars) == nil { end = text.utf8.index(before: end) }
        return String(text.unicodeScalars[..<(LinkDomains.unfinishedLinkStart(in: text, cutAt: end) ?? end)])
    }
}
