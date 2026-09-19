import Foundation
import XCTest

@testable import EbbCore

final class AgentDigestTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_789_214_400)

    private func message(_ uid: UInt32, minutes: Double, session: String? = nil, inReplyTo: String? = nil)
        -> AgentDigest.Message
    {
        var raw = "From: Claude <claude@nspx.dev>\r\nSubject: update\r\nMessage-ID: <m\(uid)@nspx.dev>\r\n"
        if let session { raw += "X-Claude-Session: \(session)\r\n" }
        if let inReplyTo { raw += "In-Reply-To: \(inReplyTo)\r\n" }
        return AgentDigest.Message(
            uid: uid, internalDate: start.addingTimeInterval(minutes * 60),
            headers: MessageHeaders.parse(raw))
    }

    func testKeepsOnlyTheNewestOfOneSession() {
        let stale = AgentDigest.superseded(in: [
            message(1, minutes: 0, session: "local_a"),
            message(2, minutes: 5, session: "local_a"),
            message(3, minutes: 10, session: "local_a"),
        ])
        XCTAssertEqual(stale, [1, 2])
    }

    func testTwoSessionsEachKeepTheirOwnNewest() {
        let stale = AgentDigest.superseded(in: [
            message(1, minutes: 0, session: "local_a"),
            message(2, minutes: 1, session: "local_b"),
            message(3, minutes: 2, session: "local_a"),
            message(4, minutes: 3, session: "local_b"),
        ])
        // Neither session's latest is touched, and no session swallows the other.
        XCTAssertEqual(stale, [1, 2])
    }

    func testOneMessagePerSessionArchivesNothing() {
        let stale = AgentDigest.superseded(in: [
            message(1, minutes: 0, session: "local_a"),
            message(2, minutes: 1, session: "local_b"),
        ])
        XCTAssertTrue(stale.isEmpty)
    }

    func testUnstampedMessageFallsBackToItsThread() {
        let stale = AgentDigest.superseded(in: [
            message(1, minutes: 0),
            message(2, minutes: 5, inReplyTo: "<m1@nspx.dev>"),
        ])
        // The reply supersedes exactly what it answered, which is uid 1.
        XCTAssertEqual(stale, [1])
    }

    func testStandaloneMessagesAreNeverArchived() {
        let stale = AgentDigest.superseded(in: [
            message(1, minutes: 0),
            message(2, minutes: 5),
            message(3, minutes: 9),
        ])
        // Nothing says which supersedes which, so all three stay.
        XCTAssertTrue(stale.isEmpty)
    }

    func testSameTimestampFallsBackToUIDOrder() {
        let stale = AgentDigest.superseded(in: [
            message(7, minutes: 3, session: "local_a"),
            message(9, minutes: 3, session: "local_a"),
        ])
        XCTAssertEqual(stale, [7])
    }
}
