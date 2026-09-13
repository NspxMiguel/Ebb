import XCTest

@testable import EbbCore

final class TriagePromptTests: XCTestCase {
    private func message(_ uid: UInt32) -> DigestMessage {
        DigestMessage(
            uid: uid, date: Date(), from: "a@b", subject: "s", snippet: "", kind: nil, flagged: false,
            important: false)
    }

    func testParsesNumbersIntoUIDsAndIgnoresOutOfRange() {
        let messages = [message(40), message(41), message(42)]
        XCTAssertEqual(TriagePrompt.parse(#"{"disposable": [1, 3, 9, 0]}"#, messages: messages), [40, 42])
        XCTAssertEqual(TriagePrompt.parse(#"Sure: {"disposable": ["2"]} done"#, messages: messages), [41])
    }

    func testGarbageKeepsEverything() {
        let messages = [message(1)]
        XCTAssertEqual(TriagePrompt.parse("I think message 1 is spam", messages: messages), [])
        XCTAssertEqual(TriagePrompt.parse(#"{"keep": [1]}"#, messages: messages), [])
    }

    func testCacheKeyPrefersMessageID() {
        let id = UUID()
        let key = Cleaner.triageKey(
            account: id, rawHeaders: "Subject: hi\r\nMessage-ID: <abc@example.com>\r\n\r\n", mailbox: "INBOX", uid: 7)
        XCTAssertEqual(key, "\(id.uuidString)|<abc@example.com>")
        XCTAssertEqual(
            Cleaner.triageKey(account: id, rawHeaders: "Subject: hi\r\n", mailbox: "INBOX", uid: 7),
            "\(id.uuidString)|INBOX|7")
    }

    func testOldRuleJSONDecodesWithDefaults() throws {
        let json = #"{"maxAge": 259200, "keepFlagged": false, "permanent": true, "excludedMailboxes": []}"#
        let rule = try JSONDecoder().decode(CleanupRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.maxAge, 259_200)
        XCTAssertEqual(rule.disposableAge, 3_600)
        XCTAssertEqual(rule.disposableKinds, [.codes, .bulk])
        XCTAssertFalse(rule.keepFlagged)
        XCTAssertTrue(rule.keepImportant)
        XCTAssertFalse(rule.aiTriage)
    }
}
