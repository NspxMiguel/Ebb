import Foundation
import XCTest

@testable import EbbCore

final class CleanerICloudTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)
    private var server: FakeIMAPServer!
    private let cleanedMailboxes = [
        "INBOX", "Archive", "Sent Messages", "Junk", "Deleted Messages", "Receipts", "Itens Exclu&AO0-dos",
    ]

    override func setUpWithError() throws {
        server = FakeIMAPServer(profile: .icloud)
        try server.start()
        addTeardownBlock { [server = server!] in server.stop() }
    }

    private func cleaner(rule: CleanupRule = .default, password: String? = nil, endpoint: ServerEndpoint? = nil)
        -> Cleaner
    {
        var cleaner = Cleaner(
            account: Account(
                provider: .icloud, username: "test@example.com",
                endpoint: endpoint ?? ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false), rule: rule),
            password: password ?? server.password)
        cleaner.responseTimeout = 3
        return cleaner
    }

    @discardableResult
    private func seed(_ mailbox: String, hours: Double = 48, flags: Set<String> = []) -> Int {
        server.addMessage(to: mailbox, internalDate: now.addingTimeInterval(-hours * 3600), flags: flags)
    }

    private func assertNoMove(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(server.commandLog.contains { $0.uppercased().hasPrefix("UID MOVE") }, file: file, line: line)
    }

    func testExpiredDeletesFromEveryFolderExceptDrafts() async throws {
        var recent: [String: Int] = [:]
        for mailbox in cleanedMailboxes {
            seed(mailbox, hours: 25)
            recent[mailbox] = seed(mailbox, hours: 23)
        }
        let draft = seed("Drafts")
        let summary = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, cleanedMailboxes.count)
        XCTAssertEqual(summary.pending, 0)
        for mailbox in cleanedMailboxes {
            XCTAssertEqual(server.messageIDs(in: mailbox), [recent[mailbox]!], mailbox)
        }
        XCTAssertEqual(server.messageIDs(in: "Drafts"), [draft])
        assertNoMove()
    }

    func testNonPermanentUsesCopyAndLeavesOldMessagesInDeletedMessages() async throws {
        let sources = cleanedMailboxes.filter { $0 != "Deleted Messages" }
        for mailbox in sources { seed(mailbox) }
        seed("Deleted Messages")
        let recent = seed("INBOX", hours: 1)
        let draft = seed("Drafts")
        _ = try await cleaner(rule: CleanupRule(permanent: false)).run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(server.contents(of: "Deleted Messages").count, sources.count + 1)
        XCTAssertTrue(
            server.contents(of: "Deleted Messages").allSatisfy { $0.internalDate == now.addingTimeInterval(-48 * 3600) }
        )
        for mailbox in sources {
            XCTAssertEqual(server.messageIDs(in: mailbox), mailbox == "INBOX" ? [recent] : [], mailbox)
        }
        XCTAssertEqual(server.messageIDs(in: "Drafts"), [draft])
        XCTAssertTrue(
            server.commandLog.contains { $0.uppercased().hasPrefix("UID COPY ") && $0.contains("Deleted Messages") })
        assertNoMove()
    }

    func testDeferredExpungeReportsPendingRatherThanDeleted() async throws {
        server.deferExpunge = true
        for mailbox in cleanedMailboxes { seed(mailbox) }
        let recent = seed("INBOX", hours: 1)
        let summary = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 0)
        XCTAssertEqual(summary.pending, cleanedMailboxes.count)
        for mailbox in cleanedMailboxes {
            XCTAssertEqual(server.contents(of: mailbox).count, mailbox == "INBOX" ? 2 : 1)
        }
        XCTAssertTrue(server.messageIDs(in: "INBOX").contains(recent))
        assertNoMove()
    }

    func testWithoutUIDPlusFallsBackToPlainExpunge() async throws {
        server.uidplus = false
        seed("INBOX")
        let recent = seed("INBOX", hours: 1)
        let summary = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [recent])
        XCTAssertTrue(server.commandLog.contains { $0.uppercased() == "EXPUNGE" })
        XCTAssertFalse(server.commandLog.contains { $0.uppercased().hasPrefix("UID EXPUNGE") })
        assertNoMove()
    }

    func testFlaggedAndDraftMessagesStayProtected() async throws {
        let flagged = seed("INBOX", flags: ["\\Flagged"])
        let draftFlag = seed("Archive", flags: ["\\Draft"])
        let draftFolder = seed("Drafts")
        let protected = try await cleaner().run(mode: .everything, dryRun: false, now: now)
        XCTAssertEqual(protected.deleted, 0)
        let unprotected = try await cleaner(rule: CleanupRule(keepFlagged: false))
            .run(mode: .everything, dryRun: false, now: now)
        XCTAssertEqual(unprotected.deleted, 1)
        XCTAssertFalse(server.messageIDs(in: "INBOX").contains(flagged))
        XCTAssertEqual(server.messageIDs(in: "Archive"), [draftFlag])
        XCTAssertEqual(server.messageIDs(in: "Drafts"), [draftFolder])
        assertNoMove()
    }

    func testWrongPasswordThrowsAuthenticationFailedAndIsRedacted() async throws {
        do {
            _ = try await cleaner(password: "incorrect-secret").run(mode: .expired, dryRun: false, now: now)
            XCTFail("Expected authentication failure")
        } catch EbbError.authenticationFailed {} catch { XCTFail("Expected authenticationFailed, got \(error)") }
        XCTAssertTrue(server.commandLog.contains { $0.uppercased().hasPrefix("LOGIN ") })
        XCTAssertFalse(server.commandLog.joined().contains("incorrect-secret"))
        XCTAssertFalse(server.commandLog.contains { $0.uppercased().hasPrefix("SELECT ") })
    }

    func testNonLoopbackPlaintextIsRejectedBeforeConnecting() async throws {
        do {
            _ = try await cleaner(endpoint: ServerEndpoint(host: "imap.example.com", port: 143, useTLS: false))
                .run(mode: .expired, dryRun: false, now: now)
            XCTFail("Expected insecure connection failure")
        } catch EbbError.insecureConnection {} catch { XCTFail("Expected insecureConnection, got \(error)") }
        XCTAssertTrue(server.commandLog.isEmpty)
    }
}
