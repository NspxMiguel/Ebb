import Foundation
import XCTest

@testable import EbbCore

final class MailTextTests: XCTestCase {
    func testEncodedWords() {
        let cases = [
            ("=?UTF-8?B?U2V1IGPDs2RpZ28gZGUgdXNvIMO6bmljbw==?=", "Seu código de uso único"),
            ("=?utf-8?q?Ol=C3=A1_mundo?=", "Olá mundo"),
            ("=?ISO-8859-1?Q?caf=E9?=", "café"),
            ("=?LaTiN1?B?Y2Fm6Q==?=", "café"),
            ("=?WINDOWS-1252?Q?=80_=93Hi=94?=", "€ “Hi”"),
            ("=?US-ASCII?Q?hello_world?=", "hello world"),
            ("=?utf-8?Q?hello?= \r\n\t=?utf-8?B?IHdvcmxk?=", "hello world"),
            ("prefix =?utf-8?Q?hello?= suffix", "prefix hello suffix"),
            ("=?unknown?Q?abc?=", "=?unknown?Q?abc?="),
            ("=?utf-8?B?%%%?=", "=?utf-8?B?%%%?="),
            ("=?utf-8?X?abc?=", "=?utf-8?X?abc?="),
        ]
        for (input, expected) in cases { XCTAssertEqual(MailText.decodeEncodedWords(input), expected, input) }
    }

    func testHeadersUnfoldDecodeAndKeepFirstOccurrence() {
        for newline in ["\r\n", "\n"] {
            let raw = [
                "fRoM: First <OLD@EXAMPLE.COM>, Person <USER@EXAMPLE.COM> ",
                "SUBJECT: =?UTF-8?Q?Seu_c=C3=B3digo?=", "\t=?utf-8?Q?_de_acesso?=",
                "Subject: ignored", "List-ID: list", "List-Unsubscribe: <https://example.com>",
                " more", "Content-Type: text/plain;", " charset=utf-8", "Content-Transfer-Encoding: quoted-printable",
                "Date: today", "Precedence: bulk", "Auto-Submitted: auto-generated", "", "Subject: body",
            ].joined(separator: newline)
            let headers = MessageHeaders.parse(raw)
            XCTAssertEqual(headers.subject, "Seu código de acesso")
            XCTAssertEqual(headers.fromAddress, "user@example.com")
            XCTAssertEqual(headers.listUnsubscribe, "<https://example.com> more")
            XCTAssertEqual(headers.contentType, "text/plain; charset=utf-8")
            XCTAssertEqual(headers.contentTransferEncoding, "quoted-printable")
            XCTAssertEqual(headers.listID, "list")
            XCTAssertEqual(headers.date, "today")
            XCTAssertEqual(headers.precedence, "bulk")
            XCTAssertEqual(headers.autoSubmitted, "auto-generated")
        }
        XCTAssertEqual(MessageHeaders(from: " USER@EXAMPLE.COM \n").fromAddress, "user@example.com")
        XCTAssertEqual(MessageHeaders.parse("Subject:\nSubject: second").subject, "")
    }

    func testQuotedPrintableAndCharsets() {
        XCTAssertEqual(MailText.decodeQuotedPrintable("Ol=C3=A1=\r\n mun=\ndo=21", charset: nil), "Olá mundo!")
        for charset in [nil, "iso-8859-1", "latin1", "unknown"] {
            XCTAssertEqual(MailText.decodeQuotedPrintable("caf=E9", charset: charset), "café")
        }
        XCTAssertEqual(MailText.decodeQuotedPrintable("=80=97", charset: "WINDOWS-1252"), "€—")
        XCTAssertEqual(MailText.decodeQuotedPrintable("a=XX=+F=", charset: nil), "a=XX=+F=")
    }

    func testHTMLBlocksEntitiesAndWhitespace() {
        XCTAssertEqual(
            MailText.stripHTML(
                "<head>hidden</head><STYLE>x</STYLE><script>x</script><p>A&nbsp; &amp; &lt; &gt; &quot; &#39; &#65; &#x1F600;</p><div>B<br>C</div><tr>D</tr><li>E</li>"
            ), "A & < > \" ' A 😀\nB\nC\nD\nE")
        XCTAssertEqual(MailText.stripHTML("  a \t b<br><br><br><br>c  "), "a b\n\nc")
        XCTAssertEqual(MailText.stripHTML("<script>unfinished"), "")
        XCTAssertEqual(MailText.stripHTML("&#x110000; &#99999999;"), "&#x110000; &#99999999;")
    }

    func testMultipartPrefersQuotedPrintablePlainText() {
        let body =
            "--b\r\nContent-Type: text/html\r\n\r\n<b>Wrong</b>\r\n--b\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nOl=C3=A1=\r\n mundo!\r\n--b--"
        XCTAssertEqual(
            MailText.snippet(body: body, headers: MessageHeaders(contentType: "multipart/alternative; boundary=\"b\"")),
            "Olá mundo!")
    }

    func testNestedMultipartAndHTMLOnlyLatin1Base64() {
        let html =
            "--inner\nContent-Type: text/html; charset=latin1\nContent-Transfer-Encoding: base64\n\nPHA+Y2Fm6TwvcD4=\n--inner--"
        let body = "--outer\nContent-Type: multipart/alternative; boundary=inner\n\n" + html + "\n--outer--"
        XCTAssertEqual(
            MailText.snippet(body: body, headers: MessageHeaders(contentType: "multipart/mixed; boundary=outer")),
            "café")
        XCTAssertEqual(
            MailText.snippet(
                body: "PHA+Y2Fm6TwvcD4=",
                headers: MessageHeaders(contentType: "text/html; charset=iso-8859-1", contentTransferEncoding: "base64")
            ), "café")
    }

    func testPartialBase64AndWordBoundaryLimit() {
        let headers = MessageHeaders(contentTransferEncoding: "base64")
        XCTAssertEqual(MailText.snippet(body: "SGVs bG8g d29ybG", headers: headers), "Hello wor")
        XCTAssertEqual(MailText.snippet(body: "Hello wonderful world", headers: .init(), limit: 10), "Hello…")
        XCTAssertEqual(MailText.snippet(body: "Hello world", headers: .init(), limit: 5), "Hello…")
        XCTAssertEqual(MailText.snippet(body: "Hello", headers: .init(), limit: 5), "Hello")
        XCTAssertEqual(MailText.snippet(body: "abcdef", headers: .init(), limit: 3), "abc…")
        XCTAssertEqual(MailText.snippet(body: "Hello", headers: .init(), limit: -1), "")
    }

    func testGarbageAndUnreadableBodies() {
        XCTAssertEqual(MessageHeaders.parse("\tbad\nno colon\n").subject, "")
        for body in ["", "?=??", "\u{0}", "====", "a"] {
            _ = MailText.decodeEncodedWords(body)
            _ = MailText.stripHTML(body)
            XCTAssertEqual(MailText.snippet(body: body, headers: .init(contentTransferEncoding: "base64")), "")
        }
        XCTAssertEqual(
            MailText.snippet(body: "--b\nContent-Type:", headers: .init(contentType: "multipart/mixed; boundary=b")), ""
        )
        XCTAssertEqual(MailText.snippet(body: "binary", headers: .init(contentType: "application/octet-stream")), "")
        XCTAssertEqual(MailText.snippet(body: "garbage", headers: .init(contentType: "multipart/mixed")), "")
    }
}
