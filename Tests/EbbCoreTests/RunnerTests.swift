import Foundation
import XCTest

@testable import EbbCore

final class RunnerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    @MainActor
    private func fixture(enabled: Bool = true, lastRun: RunSummary? = nil) throws -> (
        FakeIMAPServer, AccountStore, Account
    ) {
        let server = FakeIMAPServer(profile: .icloud)
        try server.start()
        addTeardownBlock { server.stop() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "EbbRunnerTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let account = Account(
            provider: .icloud, username: "test@example.com",
            endpoint: ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false),
            isEnabled: enabled, lastRun: lastRun)
        try store.add(account)
        server.addMessage(to: "INBOX", internalDate: now.addingTimeInterval(-48 * 3600))
        return (server, store, account)
    }

    @MainActor
    func testRunRecordsLastRunInMemoryAndOnDisk() async throws {
        let (server, store, account) = try fixture()
        let results = await Runner.run(
            store: store, mode: .expired, dryRun: false, now: now,
            passwordLookup: { id in
                XCTAssertEqual(id, account.id)
                return server.password
            })
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.accountID, account.id)
        XCTAssertEqual(result.username, account.username)
        XCTAssertNil(result.summary.errorMessage)
        XCTAssertEqual(result.summary.deleted, 1)
        XCTAssertEqual(result.summary.date, now)
        XCTAssertFalse(result.summary.dryRun)
        XCTAssertEqual(result.summary.mode, .expired)
        XCTAssertEqual(store.account(id: account.id)?.lastRun, result.summary)
        let reloaded = AccountStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.account(id: account.id)?.lastRun, result.summary)
        XCTAssertTrue(server.contents(of: "INBOX").isEmpty)
    }

    @MainActor
    func testDryRunDoesNotCreateLastRun() async throws {
        let (server, store, account) = try fixture()
        let original = try Data(contentsOf: store.fileURL)
        let results = await Runner.run(
            store: store, mode: .expired, dryRun: true, now: now, passwordLookup: { _ in server.password })
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results.first?.summary.errorMessage)
        XCTAssertEqual(results.first?.summary.deleted, 1)
        XCTAssertEqual(results.first?.summary.dryRun, true)
        XCTAssertNil(store.account(id: account.id)?.lastRun)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        XCTAssertEqual(server.contents(of: "INBOX").count, 1)
    }

    @MainActor
    func testDryRunDoesNotOverwritePreviousRun() async throws {
        let previous = RunSummary(date: now.addingTimeInterval(-3600), mode: .everything, dryRun: false, deleted: 7)
        let (server, store, account) = try fixture(lastRun: previous)
        let original = try Data(contentsOf: store.fileURL)
        let results = await Runner.run(
            store: store, mode: .expired, dryRun: true, now: now, passwordLookup: { _ in server.password })
        XCTAssertNil(results.first?.summary.errorMessage)
        XCTAssertEqual(store.account(id: account.id)?.lastRun, previous)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    @MainActor
    func testDisabledAccountIsSkippedWithoutPasswordLookupOrConnection() async throws {
        let (server, store, account) = try fixture(enabled: false)
        var lookups = 0
        let results = await Runner.run(
            store: store, mode: .expired, dryRun: false, now: now,
            passwordLookup: { _ in
                lookups += 1
                return server.password
            })
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(lookups, 0)
        XCTAssertTrue(server.commandLog.isEmpty)
        XCTAssertNil(store.account(id: account.id)?.lastRun)
        XCTAssertEqual(server.contents(of: "INBOX").count, 1)
    }

    @MainActor
    func testMissingPasswordReportsErrorWithoutConnecting() async throws {
        let (server, store, account) = try fixture()
        let results = await Runner.run(
            store: store, mode: .expired, dryRun: false, now: now, passwordLookup: { _ in nil })
        XCTAssertEqual(results.count, 1)
        let summary = try XCTUnwrap(results.first?.summary)
        XCTAssertEqual(summary.errorMessage, EbbError.missingPassword.errorDescription)
        XCTAssertFalse(summary.succeeded)
        XCTAssertEqual(summary.deleted, 0)
        XCTAssertEqual(summary.date, now)
        XCTAssertEqual(store.account(id: account.id)?.lastRun, summary)
        XCTAssertTrue(server.commandLog.isEmpty)
        XCTAssertEqual(server.contents(of: "INBOX").count, 1)
    }
}
