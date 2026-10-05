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
    public static func parse(_ data: Data) -> ParsedMessage {
        // ISO Latin-1 maps every byte to one character, so the structure can be parsed as text
        // and each part's bytes recovered losslessly for its own charset.
        let raw = String(data: data, encoding: .isoLatin1)!.replacingOccurrences(of: "\r\n", with: "\n")
        let root = MIMEEntity(parsing: raw)

        var plain: [String] = []
        var html: [String] = []
        collectText(from: root, plain: &plain, html: &html)

        // Spam often pairs an empty plain part with the real HTML to slip past text-only filters.
        let body = plain.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? html.first.map(HTMLText.plainText(fromHTML:)) ?? ""
        return ParsedMessage(
            headers: root.headers.map { ($0.name, EncodedWords.decode(Charset.decodeHeader($0.value))) },
            bodyText: TextNormalizer.normalize(body),
            linkDomains: LinkDomains.extract(from: plain + html)
        )
    }

    private static func collectText(from entity: MIMEEntity, plain: inout [String], html: inout [String]) {
        if let parts = entity.multipartChildren {
            parts.forEach { collectText(from: $0, plain: &plain, html: &html) }
            return
        }
        guard !entity.isAttachment else { return }
        switch entity.contentType.mediaType {
        case "text/plain": plain.append(entity.decodedText)
        case "text/html": html.append(entity.decodedText)
        default: break
        }
    }
}
