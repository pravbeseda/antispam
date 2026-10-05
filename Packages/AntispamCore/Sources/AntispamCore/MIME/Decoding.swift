import Foundation

enum TransferEncoding {
    static func decode(_ latin1: String, encoding: String?) -> Data {
        switch encoding?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64":
            return Data(base64Encoded: latin1, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable":
            return decodeQuotedPrintable(latin1.replacingOccurrences(of: "=\n", with: ""), underscoreIsSpace: false)
        default:
            return latin1.data(using: .isoLatin1)!
        }
    }

    static func decodeQuotedPrintable(_ text: String, underscoreIsSpace: Bool) -> Data {
        // Header text is already UTF-8-decoded, so a raw non-ASCII word does not fit Latin-1.
        let bytes = Array(text.data(using: .isoLatin1) ?? Data(text.utf8))
        var output = Data(capacity: bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "="), index + 2 < bytes.count,
               let value = UInt8(String(decoding: bytes[index + 1...index + 2], as: UTF8.self), radix: 16) {
                output.append(value)
                index += 3
                continue
            }
            output.append(underscoreIsSpace && byte == UInt8(ascii: "_") ? UInt8(ascii: " ") : byte)
            index += 1
        }
        return output
    }
}

enum Charset {
    static func decode(_ bytes: Data, charset: String?) -> String {
        if let charset, let encoding = encoding(named: charset), let text = String(data: bytes, encoding: encoding) {
            return text
        }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)!
    }

    /// Raw 8-bit header bytes are UTF-8 in modern mail (RFC 6532); keep Latin-1 otherwise.
    static func decodeHeader(_ latin1: String) -> String {
        String(data: latin1.data(using: .isoLatin1)!, encoding: .utf8) ?? latin1
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}

/// RFC 2047 `=?charset?B|Q?text?=` words in header values.
enum EncodedWords {
    static func decode(_ value: String) -> String {
        let adjacent = value.replacing(/(\?=)\s+(=\?)/) { "\($0.output.1)\($0.output.2)" }
        return adjacent.replacing(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/) { match in
            let charset = match.output.1.split(separator: "*")[0]
            let text = String(match.output.3)
            let bytes = match.output.2.lowercased() == "b"
                ? Data(base64Encoded: text, options: .ignoreUnknownCharacters)
                : TransferEncoding.decodeQuotedPrintable(text, underscoreIsSpace: true)
            guard let bytes else { return String(match.output.0) }
            return Charset.decode(bytes, charset: String(charset))
        }
    }
}
