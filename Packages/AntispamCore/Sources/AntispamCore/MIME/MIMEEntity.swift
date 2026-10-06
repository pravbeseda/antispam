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

    /// Explicit `attachment`, or any part carrying a file name, which is how many clients mark attachments.
    var isAttachment: Bool {
        let disposition = value(of: "Content-Disposition").map(HeaderValue.init)
        let named = { (value: HeaderValue?, key: String) in value?.parameters.keys.contains { $0.hasPrefix(key) } ?? false }
        return disposition?.mediaType == "attachment" || named(disposition, "filename") || named(contentType, "name")
    }

    var multipartChildren: [MIMEEntity]? {
        let type = contentType
        guard type.mediaType.hasPrefix("multipart/"), let boundary = type.parameters["boundary"] else { return nil }
        let delimiter = "--" + boundary
        var parts: [Substring] = []
        var partStart: String.Index?
        var lineStart = body.startIndex
        while lineStart < body.endIndex {
            let lineEnd = body.utf8[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? body.endIndex
            let next = lineEnd < body.endIndex ? body.utf8.index(after: lineEnd) : lineEnd
            if let kind = DelimiterLine(body[lineStart..<lineEnd], delimiter: delimiter) {
                if let partStart {
                    // The line break before a delimiter belongs to the delimiter.
                    parts.append(body[partStart..<max(partStart, body.utf8.index(before: lineStart))])
                }
                guard kind == .part else {
                    partStart = nil
                    break
                }
                partStart = next
            }
            lineStart = next
        }
        if let partStart { parts.append(body[partStart...]) }
        return parts.map { MIMEEntity(parsing: String($0)) }
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

private enum DelimiterLine {
    case part, close

    /// A delimiter starts the line; only trailing padding is allowed (RFC 2046).
    init?(_ line: Substring, delimiter: String) {
        guard line.utf8.starts(with: delimiter.utf8) else { return nil }
        var suffix = line.utf8.dropFirst(delimiter.utf8.count)
        while let last = suffix.last, last == UInt8(ascii: " ") || last == UInt8(ascii: "\t") {
            suffix = suffix.dropLast()
        }
        if suffix.isEmpty {
            self = .part
        } else if suffix.elementsEqual("--".utf8) {
            self = .close
        } else {
            return nil
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
