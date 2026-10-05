import Foundation

/// One MIME entity; header values and body are Latin-1 strings holding the raw bytes.
struct MIMEEntity {
    let headers: [(name: String, value: String)]
    let body: String

    init(parsing raw: String) {
        let headerBlock: Substring
        if raw.hasPrefix("\n") {
            headerBlock = ""
            body = String(raw.dropFirst())
        } else if let separator = raw.range(of: "\n\n") {
            headerBlock = raw[..<separator.lowerBound]
            body = String(raw[separator.upperBound...])
        } else {
            headerBlock = raw[...]
            body = ""
        }
        headers = Self.parseHeaders(headerBlock)
    }

    func value(of name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var contentType: HeaderValue {
        HeaderValue(value(of: "Content-Type") ?? "text/plain")
    }

    var isAttachment: Bool {
        value(of: "Content-Disposition").map { HeaderValue($0).mediaType == "attachment" } ?? false
    }

    var multipartChildren: [MIMEEntity]? {
        let type = contentType
        guard type.mediaType.hasPrefix("multipart/"), let boundary = type.parameters["boundary"] else { return nil }
        let delimiter = "--" + boundary
        var parts: [[Substring]] = []
        var current: [Substring]?
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == delimiter || trimmed == delimiter + "--" else {
                current?.append(line)
                continue
            }
            if let current { parts.append(current) }
            guard trimmed == delimiter else {
                current = nil
                break
            }
            current = []
        }
        if let current { parts.append(current) }
        return parts.map { MIMEEntity(parsing: $0.joined(separator: "\n")) }
    }

    var decodedText: String {
        let bytes = TransferEncoding.decode(body, encoding: value(of: "Content-Transfer-Encoding"))
        return Charset.decode(bytes, charset: contentType.parameters["charset"])
    }

    private static func parseHeaders(_ block: Substring) -> [(name: String, value: String)] {
        var unfolded: [String] = []
        for line in block.split(separator: "\n") {
            if let first = line.first, first == " " || first == "\t", let last = unfolded.popLast() {
                unfolded.append(last + " " + line.trimmingCharacters(in: .whitespaces))
            } else {
                unfolded.append(String(line))
            }
        }
        return unfolded.compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (
                line[..<colon].trimmingCharacters(in: .whitespaces),
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

/// A structured header value such as `text/plain; charset="utf-8"`.
struct HeaderValue {
    let mediaType: String
    let parameters: [String: String]

    init(_ raw: String) {
        var segments: [String] = []
        var segment = ""
        var inQuotes = false
        for character in raw {
            if character == "\"" { inQuotes.toggle() }
            if character == ";" && !inQuotes {
                segments.append(segment)
                segment = ""
            } else {
                segment.append(character)
            }
        }
        segments.append(segment)

        mediaType = segments[0].trimmingCharacters(in: .whitespaces).lowercased()
        var parameters: [String: String] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            parameters[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        self.parameters = parameters
    }
}
