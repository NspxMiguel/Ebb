import XCTest

@testable import EbbCore

final class IMAPParserTests: XCTestCase {
    func testListEntryQuotedAtomAndSpecialUse() {
        let gmail = IMAPParser.listEntry(#"* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#)
        XCTAssertEqual(gmail?.flags, [#"\HasNoChildren"#, #"\Trash"#])
        XCTAssertEqual(gmail?.name, "[Gmail]/Trash")

        let atom = IMAPParser.listEntry(#"* LIST (\HasNoChildren) "/" INBOX"#)
        XCTAssertEqual(atom?.name, "INBOX")

        let escaped = IMAPParser.listEntry(#"* LIST () "/" "Say \"hi\" \\ bye""#)
        XCTAssertEqual(escaped?.name, #"Say "hi" \ bye"#)

        let nilDelimiter = IMAPParser.listEntry(#"* LIST (\Noselect) NIL "[Gmail]""#)
        XCTAssertEqual(nilDelimiter?.name, "[Gmail]")
    }

    func testRoleDetection() {
        XCTAssertEqual(IMAPClient.role(flags: [#"\ALL"#], name: "[Gmail]/Todos os e-mails"), .all)
        XCTAssertEqual(IMAPClient.role(flags: [], name: "Deleted Messages"), .trash)
        XCTAssertEqual(IMAPClient.role(flags: [], name: "Sent Messages"), .sent)
        XCTAssertEqual(IMAPClient.role(flags: [], name: "inbox"), .inbox)
        XCTAssertEqual(IMAPClient.role(flags: [], name: "Receipts"), .other)
    }

    func testNotesFoldersAreNeverTargets() {
        let notes = MailboxInfo(rawName: "Notes", displayName: "Notes", role: .other, selectable: true)
        let receipts = MailboxInfo(rawName: "Receipts", displayName: "Receipts", role: .other, selectable: true)
        XCTAssertTrue(Cleaner.isNotesFolder(notes))
        XCTAssertFalse(Cleaner.isNotesFolder(receipts))
    }

    func testSearchResults() {
        XCTAssertEqual(IMAPParser.searchResults("* SEARCH 4 8 15"), [4, 8, 15])
        XCTAssertEqual(IMAPParser.searchResults("* SEARCH"), [])
        XCTAssertNil(IMAPParser.searchResults("* SEARCHING 1"))
    }

    func testFetchAttributesInAnyOrder() throws {
        let line = #"* 12 FETCH (FLAGS (\Seen \Flagged) INTERNALDATE " 1-Sep-2026 17:12:35 -0700" UID 345 X-GM-LABELS (\Inbox "\\Draft"))"#
        let attributes = try XCTUnwrap(IMAPParser.fetchAttributes(line))
        XCTAssertEqual(attributes["UID"]?.text, "345")
        XCTAssertEqual(attributes["FLAGS"]?.items?.compactMap(\.text), [#"\Seen"#, #"\Flagged"#])
        XCTAssertEqual(attributes["X-GM-LABELS"]?.items?.compactMap(\.text), [#"\Inbox"#, #"\Draft"#])

        let date = try XCTUnwrap(IMAPClient.parseInternalDate(try XCTUnwrap(attributes["INTERNALDATE"]?.text)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(parts.day, 2)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(parts.minute, 12)
    }

    func testCapabilities() {
        XCTAssertEqual(
            IMAPParser.capabilities("* CAPABILITY IMAP4rev1 UIDPLUS move"), ["IMAP4REV1", "UIDPLUS", "MOVE"])
        XCTAssertEqual(
            IMAPParser.capabilities("* OK [CAPABILITY IMAP4rev1 X-GM-EXT-1] Gimap ready"), ["IMAP4REV1", "X-GM-EXT-1"])
        XCTAssertNil(IMAPParser.capabilities("* OK ready"))
    }

    func testExistsAndLiteralMarker() {
        XCTAssertEqual(IMAPParser.exists("* 42 EXISTS"), 42)
        XCTAssertNil(IMAPParser.exists("* 42 RECENT"))
        XCTAssertEqual(IMAPConnection.trailingLiteral(#"* LIST () "/" {12}"#)?.1, 12)
        XCTAssertEqual(IMAPConnection.trailingLiteral(#"* LIST () "/" {7+}"#)?.1, 7)
        XCTAssertNil(IMAPConnection.trailingLiteral("* OK {not a literal}"))
    }

    func testSearchDateIsUTCDay() {
        let date = Date(timeIntervalSince1970: 1_789_257_600)  // 2026-09-13 00:00:00 UTC
        XCTAssertEqual(IMAPClient.searchDate(date), "13-Sep-2026")
    }

    func testInsecureEndpointIsRefusedBeforeConnecting() async {
        let account = Account(
            provider: .custom, username: "me@example.com",
            endpoint: ServerEndpoint(host: "imap.example.com", port: 143, useTLS: false))
        do {
            try await Cleaner(account: account, password: "secret").testLogin()
            XCTFail("expected insecureConnection")
        } catch {
            XCTAssertEqual(error as? EbbError, .insecureConnection)
        }
    }

    func testAppPasswordSpacesAreStripped() {
        XCTAssertEqual(CredentialStore.normalize("abcd efgh ijkl mnop"), "abcdefghijklmnop")
    }
}

final class MailboxRoleTests: XCTestCase {
    func testNameGuessNeverOverridesAFlaggedMailbox() {
        let boxes = IMAPClient.mailboxes(from: [
            (name: "INBOX", flags: []),
            (name: "Itens Exclu&AO0-dos", flags: []),
            (name: "Deleted Messages", flags: [#"\TRASH"#]),
            (name: "Sent", flags: []),
        ])
        XCTAssertEqual(boxes.map(\.role), [.inbox, .other, .trash, .sent])
        XCTAssertEqual(boxes[1].displayName, "Itens Excluídos")
    }
}
