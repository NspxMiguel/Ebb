import Foundation
import XCTest

@testable import EbbCore

final class DigestTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private func cleaner(_ server: FakeIMAPServer) -> Cleaner {
        var cleaner = Cleaner(
            account: Account(
                provider: server.profile == .gmail ? .gmail : .icloud,
                username: "test@example.com",
                endpoint: ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false)),
            password: server.password)
        cleaner.responseTimeout = 3
        return cleaner
    }

    func testInboxDigestDecodesSortsLimitsClassifiesAndNeverMarksSeen() async throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            let server = FakeIMAPServer(profile: profile)
            try server.start()
            addTeardownBlock { server.stop() }
            // Seed out of date order to detect sorting by UID instead of INTERNALDATE.
            server.addMessage(
                to: "INBOX", internalDate: now.addingTimeInterval(-3600),
                rawHeaders: "Subject: Older personal message\r\n", rawBody: "Lunch?")
            server.addMessage(
                to: "INBOX", internalDate: now,
                flags: ["\\Flagged"], labels: profile == .gmail ? ["\\Important"] : [],
                rawHeaders:
                    "From: =?utf-8?Q?Jos=C3=A9?= <jose@example.com>\r\nSubject: =?UTF-8?B?U2V1IGPDs2RpZ28gZGUgdXNvIMO6bmljbw==?=\r\nContent-Type: multipart/alternative; boundary=b\r\n",
                rawBody:
                    "--b\r\nContent-Type: text/html\r\n\r\n<b>Wrong</b>\r\n--b\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nOl=C3=A1, seu c=C3=B3digo =C3=A9 123456.\r\n--b--\r\n"
            )
            server.addMessage(
                to: "INBOX", internalDate: now.addingTimeInterval(-1800),
                rawHeaders: "Subject: Newsletter\r\nList-Unsubscribe: <https://example.com/leave>\r\n",
                rawBody: "Weekly news")
            server.addMessage(
                to: profile == .gmail ? "Work" : "Archive", internalDate: now.addingTimeInterval(60),
                rawHeaders: "Subject: Outside inbox\r\n", rawBody: "Hidden")
            let before = Dictionary(uniqueKeysWithValues: server.mailboxNames.map { ($0, server.contents(of: $0)) })
            let digest = try await cleaner(server).recentMessages(limit: 2)
            XCTAssertEqual(digest.count, 2)
            XCTAssertEqual(digest.map(\.subject), ["Seu código de uso único", "Newsletter"])
            XCTAssertEqual(digest.map(\.date), [now, now.addingTimeInterval(-1800)])
            XCTAssertEqual(digest.map(\.kind), [.codes, .bulk])
            XCTAssertEqual(digest.first?.from, "José <jose@example.com>")
            XCTAssertEqual(digest.first?.snippet, "Olá, seu código é 123456.")
            XCTAssertEqual(digest.first?.flagged, true)
            XCTAssertEqual(digest.first?.important, profile == .gmail)
            XCTAssertEqual(digest.last?.flagged, false)
            XCTAssertEqual(digest.last?.important, false)
            let all = try await cleaner(server).recentMessages(limit: 10)
            XCTAssertEqual(all.count, 3)
            XCTAssertEqual(all.last?.subject, "Older personal message")
            XCTAssertNil(all.last?.kind)
            for mailbox in server.mailboxNames {
                XCTAssertEqual(server.contents(of: mailbox), before[mailbox])
                XCTAssertTrue(server.contents(of: mailbox).allSatisfy { !$0.flags.contains("\\Seen") })
            }
            XCTAssertTrue(server.commandLog.contains { $0.uppercased().contains("BODY.PEEK[HEADER.FIELDS") })
            XCTAssertTrue(server.commandLog.contains { $0.uppercased().contains("BODY.PEEK[TEXT]") })
            server.stop()
        }
    }

    func testEmptyInboxAndZeroLimit() async throws {
        let server = FakeIMAPServer(profile: .icloud)
        try server.start()
        defer { server.stop() }
        let empty = try await cleaner(server).recentMessages(limit: 10)
        XCTAssertTrue(empty.isEmpty)
        server.addMessage(to: "INBOX", internalDate: now, rawHeaders: "Subject: Hello\n", rawBody: "Hi")
        let zero = try await cleaner(server).recentMessages(limit: 0)
        XCTAssertTrue(zero.isEmpty)
        XCTAssertFalse(server.contents(of: "INBOX")[0].flags.contains("\\Seen"))
    }
}
