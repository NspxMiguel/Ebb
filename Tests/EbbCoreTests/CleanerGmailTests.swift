import Foundation
import XCTest

@testable import EbbCore

final class CleanerGmailTests: XCTestCase {
    // Noon UTC makes 23h and 25h land on the same calendar day: SEARCH BEFORE
    // alone cannot implement the rolling 24-hour cutoff.
    private let now = Date(timeIntervalSince1970: 1_789_214_400)
    private var server: FakeIMAPServer!

    override func setUpWithError() throws {
        server = FakeIMAPServer(profile: .gmail)
        try server.start()
        addTeardownBlock { [server = server!] in server.stop() }
    }

    private func cleaner(rule: CleanupRule = .default) -> Cleaner {
        var cleaner = Cleaner(
            account: Account(
                provider: .gmail, username: "test@example.com",
                endpoint: ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false), rule: rule),
            password: server.password)
        cleaner.responseTimeout = 3
        return cleaner
    }

    @discardableResult
    private func seed(_ mailbox: String, hours: Double = 48, flags: Set<String> = [], labels: Set<String> = []) -> Int {
        server.addMessage(
            to: mailbox, internalDate: now.addingTimeInterval(-hours * 3600), flags: flags, labels: labels)
    }

    private func assertGone(_ ids: Set<Int>, file: StaticString = #filePath, line: UInt = #line) {
        for mailbox in server.mailboxNames {
            XCTAssertTrue(
                server.messageIDs(in: mailbox).isDisjoint(with: ids), "Still in \(mailbox)", file: file, line: line)
        }
    }

    func testExpiredPermanentDeletesAcrossAllMailSpamAndTrashWithoutDoubleCountingLabels() async throws {
        let inbox = seed("INBOX", labels: ["Work", "\\Sent"])
        let archived = seed("[Gmail]/All Mail")
        let sent = seed("[Gmail]/Sent Mail")
        let spam = seed("[Gmail]/Spam")
        let trash = seed("[Gmail]/Trash")
        let recent = seed("INBOX", hours: 2)
        let recentSpam = seed("[Gmail]/Spam", hours: 2)
        let recentTrash = seed("[Gmail]/Trash", hours: 2)

        let summary = try await cleaner().run(mode: .expired, dryRun: false, now: now)

        XCTAssertEqual(summary.deleted, 5)
        XCTAssertEqual(summary.pending, 0)
        assertGone([inbox, archived, sent, spam, trash])
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [recent])
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/All Mail"), [recent])
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/Spam"), [recentSpam])
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/Trash"), [recentTrash])
    }

    func testRollingCutoffKeeps23HoursAndDeletes25Hours() async throws {
        let recent = seed("INBOX", hours: 23)
        let old = seed("INBOX", hours: 25)
        let summary = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [recent])
        assertGone([old])
    }

    func testFlaggedMessagesAreProtectedOnlyWhenRequested() async throws {
        let starred = seed("INBOX", flags: ["\\Flagged"])
        let protected = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(protected.deleted, 0)
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/Starred"), [starred])

        let removed = try await cleaner(rule: CleanupRule(keepFlagged: false))
            .run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(removed.deleted, 1)
        assertGone([starred])
    }

    func testDraftsSurviveBothModesEvenWhenFlaggedProtectionIsOff() async throws {
        let draft = seed("[Gmail]/Drafts")
        let labeledDraft = seed("INBOX", flags: ["\\Draft"], labels: ["Work"])
        for mode in [CleanupMode.expired, .everything] {
            let summary = try await cleaner(rule: CleanupRule(keepFlagged: false))
                .run(mode: mode, dryRun: false, now: now)
            XCTAssertEqual(summary.deleted, 0)
            XCTAssertEqual(server.messageIDs(in: "[Gmail]/Drafts"), [draft, labeledDraft])
            XCTAssertEqual(server.messageIDs(in: "[Gmail]/All Mail"), [draft, labeledDraft])
        }
    }

    func testEverythingDeletesEveryAgeButPreservesStarsAndDrafts() async throws {
        let old = seed("INBOX")
        let new = seed("Work", hours: 0)
        let spam = seed("[Gmail]/Spam", hours: 1)
        let trash = seed("[Gmail]/Trash", hours: 1)
        let starred = seed("INBOX", hours: 1, flags: ["\\Flagged"])
        let draft = seed("[Gmail]/Drafts", hours: 1)
        let summary = try await cleaner().run(mode: .everything, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 4)
        assertGone([old, new, spam, trash])
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/All Mail"), [starred, draft])
    }

    func testNonPermanentCleanupLeavesMessagesInTrash() async throws {
        let inbox = seed("INBOX", labels: ["Work", "\\Sent"])
        let spam = seed("[Gmail]/Spam")
        let existingTrash = seed("[Gmail]/Trash")
        let recent = seed("INBOX", hours: 1)
        _ = try await cleaner(rule: CleanupRule(permanent: false)).run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/Trash"), [inbox, spam, existingTrash])
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/All Mail"), [recent])
        XCTAssertTrue(server.contents(of: "Work").isEmpty)
        XCTAssertTrue(server.contents(of: "[Gmail]/Spam").isEmpty)
        XCTAssertTrue(server.contents(of: "[Gmail]/Sent Mail").isEmpty)
    }

    func testDryRunPreservesEveryMailboxAndPredictsRealCount() async throws {
        seed("INBOX", labels: ["Work"])
        seed("[Gmail]/Spam")
        seed("[Gmail]/Trash")
        seed("INBOX", hours: 23)
        seed("INBOX", flags: ["\\Flagged"])
        seed("[Gmail]/Drafts")
        let before = Dictionary(uniqueKeysWithValues: server.mailboxNames.map { ($0, server.contents(of: $0)) })

        let preview = try await cleaner().run(mode: .expired, dryRun: true, now: now)
        XCTAssertTrue(preview.dryRun)
        XCTAssertEqual(preview.deleted, 3)
        for mailbox in server.mailboxNames { XCTAssertEqual(server.contents(of: mailbox), before[mailbox]) }
        XCTAssertFalse(
            server.commandLog.contains { command in
                let upper = command.uppercased()
                return ["UID STORE", "UID MOVE", "UID COPY", "UID EXPUNGE", "EXPUNGE"].contains { upper.hasPrefix($0) }
            })
        let real = try await cleaner().run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(preview.deleted, real.deleted)
    }

    func testPlanOnlyScansCanonicalGmailMailboxes() async throws {
        seed("INBOX", labels: ["Work", "\\Sent"])
        seed("[Gmail]/Spam")
        seed("[Gmail]/Trash")
        seed("[Gmail]/Drafts")
        let before = Dictionary(uniqueKeysWithValues: server.mailboxNames.map { ($0, server.contents(of: $0)) })
        let plan = try await cleaner().plan(mode: .expired, now: now)
        XCTAssertEqual(
            Set(plan.mailboxes.map(\.mailbox.rawName)), ["[Gmail]/All Mail", "[Gmail]/Spam", "[Gmail]/Trash"])
        XCTAssertEqual(plan.totalMessages, 3)
        for mailbox in server.mailboxNames { XCTAssertEqual(server.contents(of: mailbox), before[mailbox]) }
    }

    func testExcludedSpamIsNotPlannedOrDeleted() async throws {
        let spam = seed("[Gmail]/Spam")
        let inbox = seed("INBOX")
        let cleaner = cleaner(rule: CleanupRule(excludedMailboxes: ["[Gmail]/Spam"]))
        let plan = try await cleaner.plan(mode: .expired, now: now)
        XCTAssertFalse(plan.mailboxes.contains { $0.mailbox.rawName == "[Gmail]/Spam" })
        let summary = try await cleaner.run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(server.messageIDs(in: "[Gmail]/Spam"), [spam])
        assertGone([inbox])
    }
}
