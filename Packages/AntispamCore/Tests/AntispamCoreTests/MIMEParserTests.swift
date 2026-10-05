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

    @Test func lfLineEndingsAreAccepted() {
        let message = MIMEParser.parse(Data("Subject: Hi\n\nBody line\n".utf8))
        #expect(message.values(of: "Subject") == ["Hi"])
        #expect(message.bodyText == "Body line")
    }
}
