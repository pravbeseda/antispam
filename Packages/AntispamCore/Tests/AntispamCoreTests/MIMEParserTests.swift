import Foundation
import Testing
@testable import AntispamCore

private func parse(_ lines: [String], encoding: String.Encoding = .utf8) -> ParsedMessage {
    MIMEParser.parse(lines.joined(separator: "\r\n").data(using: encoding)!)
}

@Suite struct MIMEParserTests {
    @Test func plainMessage() {
        let message = parse([
            "From: Alice <alice@example.com>",
            "Subject: Hello",
            "",
            "Just a body.",
        ])
        #expect(message.values(of: "from") == ["Alice <alice@example.com>"])
        #expect(message.values(of: "Subject") == ["Hello"])
        #expect(message.bodyText == "Just a body.")
    }

    @Test func foldedHeaderIsUnfolded() {
        let message = parse([
            "Authentication-Results: mx.example.com;",
            "\tspf=pass smtp.mailfrom=example.com;",
            "  dkim=fail",
            "",
            "",
        ])
        #expect(message.values(of: "Authentication-Results") == ["mx.example.com; spf=pass smtp.mailfrom=example.com; dkim=fail"])
    }

    @Test func repeatedHeadersKeepOrder() {
        let message = parse(["Received: one", "Received: two", "", ""])
        #expect(message.values(of: "received") == ["one", "two"])
    }

    @Test func encodedWordsAreDecoded() {
        let message = parse([
            "Subject: =?windows-1251?B?z/Do4uXy?= =?UTF-8?Q?_=D0=BC=D0=B8=D1=80?=",
            "From: =?utf-8?q?Bob_Smith?= <bob@example.com>",
            "",
            "",
        ])
        #expect(message.values(of: "Subject") == ["Привет мир"])
        #expect(message.values(of: "From") == ["Bob Smith <bob@example.com>"])
    }

    @Test func rawNonASCIIInsideQEncodedWordIsKept() {
        let message = parse(["Subject: =?UTF-8?Q?Привет_мир?=", "", ""])
        #expect(message.values(of: "Subject") == ["Привет мир"])
    }

    @Test func quotedPrintableBody() {
        let message = parse([
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: quoted-printable",
            "",
            "=D0=A1=D0=BA=D0=B8=D0=B4=D0=BA=D0=B0 50% =3D =",
            "=D1=82=D0=BE=D0=BB=D1=8C=D0=BA=D0=BE =D1=81=D0=B5=D0=B3=D0=BE=D0=B4=D0=BD=D1=8F",
        ])
        #expect(message.bodyText == "Скидка 50% = только сегодня")
    }

    @Test func base64Koi8RBody() {
        let encoded = "Выигрыш!".data(using: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue))))!
            .base64EncodedString()
        let message = parse([
            "Content-Type: text/plain; charset=\"KOI8-R\"",
            "Content-Transfer-Encoding: base64",
            "",
            encoded,
        ])
        #expect(message.bodyText == "Выигрыш!")
    }

    @Test func alternativePrefersPlainText() {
        let message = parse([
            "Content-Type: multipart/alternative; boundary=\"b1\"",
            "",
            "--b1",
            "Content-Type: text/plain; charset=utf-8",
            "",
            "Plain version",
            "--b1",
            "Content-Type: text/html; charset=utf-8",
            "",
            "<p>HTML version</p>",
            "--b1--",
        ])
        #expect(message.bodyText == "Plain version")
    }

    @Test func emptyPlainPartFallsBackToHTML() {
        let message = parse([
            "Content-Type: multipart/alternative; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "  ",
            "--b",
            "Content-Type: text/html",
            "",
            "<p>Buy now https://evil.example/x</p>",
            "--b--",
        ])
        #expect(message.bodyText == "Buy now https://evil.example/x")
    }

    @Test func htmlOnlyIsConvertedToText() {
        let message = parse([
            "Content-Type: text/html; charset=utf-8",
            "",
            "<html><head><style>p { color: red }</style><script>alert(1)</script></head>",
            "<body><p>Win&nbsp;a &amp; prize</p><br>Click &#1053;&#x430;&lt;here&gt;</body></html>",
        ])
        #expect(message.bodyText == "Win a & prize\nClick На<here>")
    }

    @Test func attachmentsAreIgnoredInNestedMultipart() {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=outer",
            "",
            "preamble",
            "--outer",
            "Content-Type: multipart/alternative; boundary=inner",
            "",
            "--inner",
            "Content-Type: text/html; charset=utf-8",
            "",
            "<b>Invoice</b> attached",
            "--inner--",
            "--outer",
            "Content-Type: text/plain; name=invoice.txt",
            "Content-Disposition: attachment; filename=invoice.txt",
            "",
            "SECRET ATTACHMENT TEXT",
            "--outer--",
        ])
        #expect(message.bodyText == "Invoice attached")
    }

    @Test func attachedMultipartIsIgnored() {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=outer",
            "",
            "--outer",
            "Content-Type: text/html",
            "",
            "<p>Real body</p>",
            "--outer",
            "Content-Type: multipart/alternative; boundary=inner",
            "Content-Disposition: attachment",
            "",
            "--inner",
            "Content-Type: text/plain",
            "",
            "ATTACHED TEXT",
            "--inner--",
            "--outer--",
        ])
        #expect(message.bodyText == "Real body")
    }

    @Test func indentedBoundaryTextIsNotADelimiter() {
        let message = parse([
            "Content-Type: multipart/alternative; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "Hello",
            " --b",
            "Content-Type: text/plain",
            "",
            "Buy pills now",
            "--b-- ",
        ])
        #expect(message.bodyText == "Hello\n--b\nContent-Type: text/plain\nBuy pills now")
    }

    @Test func delimiterMayHaveTrailingPaddingOnly() {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=b",
            "",
            "--b \t",
            "--b",
            "Content-Type: text/plain",
            "",
            "https://first.example",
            "--bb",
            "--b--x",
            "--b\t",
            "Content-Type: text/plain",
            "",
            "https://second.example",
            "--b--\t ",
            "Content-Type: text/plain",
            "",
            "https://epilogue.example",
        ])
        #expect(message.bodyText == "https://first.example\n--bb\n--b--x")
        #expect(message.linkDomains == ["first.example", "second.example"])
    }

    @Test func missingCloseDelimiterKeepsTheLastPart() {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "Unterminated",
            "",
        ])
        #expect(message.bodyText == "Unterminated")
    }

    @Test func bodyWhitespaceIsNormalized() {
        let message = parse(["Content-Type: text/plain; charset=utf-8", "", "  a\t b\u{00A0}\u{00A0}c \u{2003}", " \t", "\u{3000}d"])
        #expect(message.bodyText == "a b c\nd")
    }

    @Test func textPartIsTruncated() {
        let message = parse(["Content-Type: text/plain", "", String(repeating: "x ", count: MIMEParser.maxTextBytes)])
        #expect(message.bodyText.count < MIMEParser.maxTextBytes)
        #expect(message.bodyText.hasSuffix("x x"))
    }

    @Test func partWithoutWhitespaceIsCutAtTheLimit() {
        let html = String(repeating: "<p>Buy&nbsp;now</p>", count: MIMEParser.maxTextBytes / 19 + 1)
        let message = parse(["Content-Type: text/html", "", html])
        #expect(message.bodyText.hasPrefix("Buy now\nBuy now"))
    }

    @Test func earlyWhitespaceDoesNotEmptyAnOversizedPart() {
        let html = "<html lang=en><body>https://evil.example/" + String(repeating: "x", count: MIMEParser.maxTextBytes)
        let message = parse(["Content-Type: text/html", "", html])
        #expect(message.linkDomains == ["evil.example"])
    }

    @Test func limitCountsBytesNotCharacters() {
        let cluster = "a" + String(repeating: "\u{301}", count: MIMEParser.maxTextBytes)
        let message = parse(["Content-Type: text/plain; charset=utf-8", "", cluster])
        #expect(message.bodyText.utf8.count <= MIMEParser.maxTextBytes)
    }

    @Test func limitIsSharedByAllParts() {
        let filler = String(repeating: "a ", count: MIMEParser.maxTextBytes / 4)
        let message = parse([
            "Content-Type: multipart/mixed; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "https://one.example \(filler)",
            "--b",
            "Content-Type: text/plain",
            "",
            "https://two.example \(filler) https://three.example",
            "--b--",
        ])
        #expect(message.linkDomains == ["one.example", "two.example"])
    }

    @Test func truncationDoesNotCutALink() {
        // The limit falls right after `https://paypal`.
        let filler = String(repeating: "a", count: MIMEParser.maxTextBytes - 34)
        let message = parse(["Content-Type: text/html", "", "https://ok.example \(filler) https://paypal.com/login"])
        #expect(message.linkDomains == ["ok.example"])
    }

    @Test(arguments: [
        "Content-Type: text/plain; name=secret.txt",
        "Content-Disposition: inline; filename=secret.txt",
    ])
    func namedPartIsAnAttachment(header: String) {
        let message = parse([
            "Content-Type: multipart/mixed; boundary=b",
            "",
            "--b",
            "Content-Type: text/html",
            "",
            "<p>Real body</p>",
            "--b",
            header,
            "",
            "ATTACHMENT CONTENT",
            "--b--",
        ])
        #expect(message.bodyText == "Real body")
    }

    @Test func nestingBeyondTheLimitIsNotParsed() {
        func nested(_ depth: Int) -> ParsedMessage {
            var body = "Content-Type: text/plain\r\n\r\nhello"
            for level in 0..<depth {
                body = "Content-Type: multipart/mixed; boundary=b\(level)\r\n\r\n--b\(level)\r\n\(body)\r\n--b\(level)--"
            }
            return MIMEParser.parse(Data(body.utf8))
        }
        #expect(nested(MIMEParser.maxNestingDepth).bodyText == "hello")
        #expect(nested(MIMEParser.maxNestingDepth + 1).bodyText == "")
    }

    @Test func linkDomainsAreCollectedFromAllTextParts() {
        let message = parse([
            "Content-Type: multipart/alternative; boundary=b",
            "",
            "--b",
            "Content-Type: text/plain",
            "",
            "Visit https://Shop.Example.com/sale or http://shop.example.com:8080/x",
            "--b",
            "Content-Type: text/html",
            "",
            "<a href=\"https://evil.example.net/login?u=1\">PayPal</a> <a href='http://bit.ly/abc'>x</a>",
            "--b--",
        ])
        #expect(message.linkDomains == ["shop.example.com", "evil.example.net", "bit.ly"])
    }

    @Test func userInfoDoesNotHideTheLinkHost() {
        let message = parse(["Content-Type: text/plain", "", "Log in: https://paypal.com@evil.example/login"])
        #expect(message.linkDomains == ["evil.example"])
    }

    @Test func addressInQueryOrFragmentIsNotUserInfo() {
        let message = parse([
            "Content-Type: text/plain",
            "",
            "https://shop.example.com?e=bob@gmail.com https://t.example?u=bob@mail.example&c=1 https://news.example#bob@other.example",
        ])
        #expect(message.linkDomains == ["shop.example.com", "t.example", "news.example"])
    }

    @Test func lfLineEndingsAreAccepted() {
        let message = MIMEParser.parse(Data("Subject: Hi\n\nBody line\n".utf8))
        #expect(message.values(of: "Subject") == ["Hi"])
        #expect(message.bodyText == "Body line")
    }
}
