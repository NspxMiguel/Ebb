import Foundation
import XCTest

@testable import EbbCore

final class CleanerTierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private func server(_ profile: FakeIMAPServer.Profile) throws -> FakeIMAPServer {
        let server = FakeIMAPServer(profile: profile)
        try server.start()
        addTeardownBlock { server.stop() }
        return server
    }

    private func cleaner(_ server: FakeIMAPServer, rule: CleanupRule = .default) -> Cleaner {
        var cleaner = Cleaner(
            account: Account(
                provider: server.profile == .gmail ? .gmail : .icloud,
                username: "test@example.com",
                endpoint: ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false), rule: rule),
            password: server.password)
        cleaner.responseTimeout = 3
        return cleaner
    }

    @discardableResult
    private func seed(
        _ server: FakeIMAPServer, hours: Double, headers: String, flags: Set<String> = [], labels: Set<String> = []
    ) -> Int {
        server.addMessage(
            to: "INBOX", internalDate: now.addingTimeInterval(-hours * 3600),
            flags: flags, labels: labels, rawHeaders: headers)
    }

    func testDefaultTiersAndFlagProtectionForBothProfiles() async throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            let server = try server(profile)
            seed(server, hours: 2, headers: "Subject: Your verification code\r\n")
            seed(server, hours: 2, headers: "Subject: Weekly news\r\nList-Unsubscribe: <mailto:leave@example.com>\r\n")
            let personal = seed(server, hours: 2, headers: "Subject: Dinner tonight?\r\n")
            let freshCode = seed(server, hours: 0.5, headers: "Subject: Your code\r\n")
            seed(server, hours: 25, headers: "Subject: Personal conversation\r\n")
            let flaggedCode = seed(server, hours: 2, headers: "Subject: Your code\r\n", flags: ["\\Flagged"])
            let summary = try await cleaner(server).run(mode: .expired, dryRun: false, now: now)
            XCTAssertEqual(summary.deleted, 3)
            XCTAssertEqual(summary.pending, 0)
            XCTAssertEqual(server.messageIDs(in: "INBOX"), [personal, freshCode, flaggedCode])
            server.stop()
        }
    }

    func testNeverMaxAgeCleansOnlyDisposableMail() async throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            let server = try server(profile)
            seed(server, hours: 2, headers: "Subject: Your verification code\r\n")
            let oldPersonal = seed(server, hours: 24 * 400, headers: "Subject: A letter from years ago\r\n")
            let recentPersonal = seed(server, hours: 30, headers: "Subject: Dinner tonight?\r\n")
            let rule = CleanupRule(maxAge: CleanupRule.neverAge)
            XCTAssertFalse(rule.usesLongTier)
            let summary = try await cleaner(server, rule: rule).run(mode: .expired, dryRun: false, now: now)
            XCTAssertEqual(summary.deleted, 1)
            XCTAssertEqual(server.messageIDs(in: "INBOX"), [oldPersonal, recentPersonal])
            server.stop()
        }
    }

    func testNeverMaxAgeWithoutDisposableKindsDeletesNothing() async throws {
        let server = try server(.icloud)
        let code = seed(server, hours: 2, headers: "Subject: Your verification code\r\n")
        let old = seed(server, hours: 24 * 400, headers: "Subject: A letter from years ago\r\n")
        let rule = CleanupRule(maxAge: CleanupRule.neverAge, disposableKinds: [])
        let summary = try await cleaner(server, rule: rule).run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 0)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [code, old])
    }

    func testCodesOnlyLeavesYoungNewsletterForBothProfiles() async throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            let server = try server(profile)
            let newsletter = seed(server, hours: 2, headers: "List-Unsubscribe: <https://example.com/unsubscribe>\n")
            seed(server, hours: 2, headers: "Subject: Your code\n")
            let summary = try await cleaner(server, rule: CleanupRule(disposableKinds: [.codes]))
                .run(mode: .expired, dryRun: false, now: now)
            XCTAssertEqual(summary.deleted, 1)
            XCTAssertEqual(server.messageIDs(in: "INBOX"), [newsletter])
            server.stop()
        }
    }

    func testDisposableAgeAtOrAboveMaxAgeDisablesShortTier() async throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            for age in [86_400.0, 172_800.0] {
                let server = try server(profile)
                let code = seed(server, hours: 2, headers: "Subject: Your code\n")
                let newsletter = seed(server, hours: 23, headers: "List-ID: news.example.com\n")
                seed(server, hours: 25, headers: "Subject: Personal\n")
                let summary = try await cleaner(server, rule: CleanupRule(disposableAge: age))
                    .run(mode: .expired, dryRun: false, now: now)
                XCTAssertEqual(summary.deleted, 1)
                XCTAssertEqual(server.messageIDs(in: "INBOX"), [code, newsletter])
                server.stop()
            }
        }
    }

    func testGmailImportantProtectionCanBeDisabled() async throws {
        let server = try server(.gmail)
        let important = seed(server, hours: 72, headers: "Subject: Personal\n", labels: ["\\Important"])
        let protected = try await cleaner(server).run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(protected.deleted, 0)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [important])
        let unprotected = try await cleaner(server, rule: CleanupRule(keepImportant: false))
            .run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(unprotected.deleted, 1)
        XCTAssertTrue(server.contents(of: "INBOX").isEmpty)
    }
}
