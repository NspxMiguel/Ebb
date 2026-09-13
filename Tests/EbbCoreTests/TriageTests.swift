import Foundation
import XCTest

@testable import EbbCore

/// A triager that answers from a fixed rule and counts how often it was asked.
private final class ScriptedTriager: MailTriager, @unchecked Sendable {
    let displayName = "scripted"
    let sendsMailOffDevice = false
    private let lock = NSLock()
    private var asked: [String] = []
    var fails = false

    var askedSubjects: [String] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func disposable(_ messages: [DigestMessage], account: String) async throws -> Set<UInt32> {
        lock.lock()
        asked += messages.map(\.subject)
        let shouldFail = fails
        lock.unlock()
        if shouldFail { throw EbbError.summaryFailed("rate limited") }
        return Set(messages.filter { $0.subject.contains("liked your photo") }.map(\.uid))
    }
}

final class TriageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_214_400)

    private func makeServer() throws -> FakeIMAPServer {
        let server = FakeIMAPServer(profile: .icloud)
        try server.start()
        addTeardownBlock { server.stop() }
        return server
    }

    private func cleaner(_ server: FakeIMAPServer, triager: MailTriager?, aiTriage: Bool = true) -> Cleaner {
        var cleaner = Cleaner(
            account: Account(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                provider: .icloud, username: "test@example.com",
                endpoint: ServerEndpoint(host: "127.0.0.1", port: server.port, useTLS: false),
                rule: CleanupRule(aiTriage: aiTriage)),
            password: server.password)
        cleaner.responseTimeout = 3
        cleaner.triager = triager
        cleaner.triageCacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ebb-triage-\(UUID().uuidString).json")
        return cleaner
    }

    @discardableResult
    private func seed(_ server: FakeIMAPServer, hours: Double, subject: String, id: String) -> Int {
        server.addMessage(
            to: "INBOX", internalDate: now.addingTimeInterval(-hours * 3600),
            rawHeaders: "Subject: \(subject)\r\nMessage-ID: <\(id)@example.com>\r\n", rawBody: "Hello")
    }

    func testModelVerdictDeletesInTheShortTierAndKeepsTheRest() async throws {
        let server = try makeServer()
        let social = seed(server, hours: 2, subject: "Ana liked your photo", id: "a")
        let person = seed(server, hours: 2, subject: "Dinner on Friday?", id: "b")
        let fresh = seed(server, hours: 0.5, subject: "Bob liked your photo", id: "c")
        let triager = ScriptedTriager()

        let summary = try await cleaner(server, triager: triager).run(mode: .expired, dryRun: false, now: now)

        XCTAssertEqual(summary.deleted, 1)
        XCTAssertNil(summary.warning)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [person, fresh])
        XCTAssertFalse(server.messageIDs(in: "INBOX").contains(social))
        // Only the undecided messages between the two ages were sent to the model.
        XCTAssertEqual(Set(triager.askedSubjects), ["Ana liked your photo", "Dinner on Friday?"])
    }

    func testVerdictsAreCachedByMessageID() async throws {
        let server = try makeServer()
        seed(server, hours: 2, subject: "Dinner on Friday?", id: "keep-me")
        let triager = ScriptedTriager()
        let first = cleaner(server, triager: triager)
        _ = try await first.run(mode: .expired, dryRun: false, now: now)
        var second = cleaner(server, triager: triager)
        second.triageCacheURL = first.triageCacheURL
        _ = try await second.run(mode: .expired, dryRun: false, now: now.addingTimeInterval(600))
        XCTAssertEqual(triager.askedSubjects, ["Dinner on Friday?"], "the second run must use the cached verdict")
    }

    func testFailureKeepsMailAndWarns() async throws {
        let server = try makeServer()
        let social = seed(server, hours: 2, subject: "Ana liked your photo", id: "a")
        let triager = ScriptedTriager()
        triager.fails = true
        let summary = try await cleaner(server, triager: triager).run(mode: .expired, dryRun: false, now: now)
        XCTAssertEqual(summary.deleted, 0)
        XCTAssertNotNil(summary.warning)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [social])
    }

    func testMissingTriagerWarnsAndOffNeverAsks() async throws {
        let server = try makeServer()
        seed(server, hours: 2, subject: "Ana liked your photo", id: "a")
        let withoutModel = try await cleaner(server, triager: nil).run(mode: .expired, dryRun: true, now: now)
        XCTAssertEqual(withoutModel.deleted, 0)
        XCTAssertNotNil(withoutModel.warning)

        let triager = ScriptedTriager()
        let off = try await cleaner(server, triager: triager, aiTriage: false)
            .run(mode: .expired, dryRun: true, now: now)
        XCTAssertEqual(off.deleted, 0)
        XCTAssertNil(off.warning)
        XCTAssertTrue(triager.askedSubjects.isEmpty)
    }
}
