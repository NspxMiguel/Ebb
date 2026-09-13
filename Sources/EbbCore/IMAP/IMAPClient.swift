import Foundation

struct MessageMeta: Equatable {
    var internalDate: Date
    /// Uppercased system and keyword flags, e.g. "\SEEN", "\FLAGGED".
    var flags: Set<String>
    /// Uppercased Gmail labels (X-GM-LABELS), empty elsewhere.
    var labels: Set<String>
}

/// The subset of IMAP4rev1 Ebb needs. One instance is one session; it is used
/// from a single task at a time and is not shared.
final class IMAPClient {
    private let connection: IMAPConnection
    private var nextTag = 1
    private(set) var capabilities: Set<String> = []

    init(endpoint: ServerEndpoint, timeout: TimeInterval) {
        connection = IMAPConnection(endpoint: endpoint, timeout: timeout)
    }

    var isGmail: Bool { capabilities.contains("X-GM-EXT-1") }
    var supportsMove: Bool { capabilities.contains("MOVE") }
    var supportsUIDPlus: Bool { capabilities.contains("UIDPLUS") }

    // MARK: - Session

    func connect() async throws {
        try await connection.open()
        let greeting = try await connection.readResponse()
        if greeting.uppercased().hasPrefix("* BYE") {
            throw EbbError.connectionFailed(greeting)
        }
        guard greeting.hasPrefix("*") else {
            throw EbbError.protocolError(greeting)
        }
        if let caps = IMAPParser.capabilities(greeting) {
            capabilities = caps
        }
    }

    func login(username: String, password: String) async throws {
        let result = try await send(
            "LOGIN \(IMAPParser.quote(username)) \(IMAPParser.quote(password))", logAs: "LOGIN")
        switch result.status {
        case "OK":
            break
        case "NO":
            throw EbbError.authenticationFailed(result.text)
        default:
            throw EbbError.serverRefused(command: "LOGIN", message: result.text)
        }
        // Servers commonly advertise more (MOVE, X-GM-EXT-1) once authenticated.
        let caps = try await command("CAPABILITY")
        for line in caps {
            if let parsed = IMAPParser.capabilities(line) { capabilities = parsed }
        }
        if let parsed = IMAPParser.capabilities(result.text) {
            capabilities.formUnion(parsed)
        }
    }

    func logout() async {
        _ = try? await send("LOGOUT", logAs: "LOGOUT")
        await connection.close()
    }

    func close() async {
        await connection.close()
    }

    // MARK: - Mailboxes

    func list() async throws -> [MailboxInfo] {
        let lines = try await command(#"LIST "" "*""#)
        let entries = lines.compactMap(IMAPParser.listEntry).map {
            (name: $0.name, flags: Set($0.flags.map { $0.uppercased() }))
        }
        return Self.mailboxes(from: entries)
    }

    /// Roles from SPECIAL-USE flags first. A name only decides a role that no
    /// flagged mailbox already claims: with iCloud's "Deleted Messages" flagged
    /// \Trash, a user folder called "Itens Excluídos" is just a folder, and
    /// guessing otherwise would pick the wrong Trash.
    static func mailboxes(from entries: [(name: String, flags: Set<String>)]) -> [MailboxInfo] {
        let flagged = entries.map { role(flags: $0.flags, name: nil) }
        let claimed = Set(flagged.filter { $0 != .other && $0 != .inbox })
        return zip(entries, flagged).map { entry, flagRole in
            let display = ModifiedUTF7.decode(entry.name)
            var detected = flagRole
            if detected == .other {
                let guess = role(flags: [], name: display)
                detected = claimed.contains(guess) ? .other : guess
            }
            return MailboxInfo(
                rawName: entry.name,
                displayName: display,
                role: detected,
                selectable: !entry.flags.contains("\\NOSELECT") && !entry.flags.contains("\\NONEXISTENT")
            )
        }
    }

    /// Returns the EXISTS count.
    @discardableResult
    func select(_ rawName: String) async throws -> Int {
        let lines = try await command("SELECT \(IMAPParser.quote(rawName))")
        return lines.compactMap(IMAPParser.exists).last ?? 0
    }

    // MARK: - Messages

    func uidSearch(_ criteria: String) async throws -> [UInt32] {
        let lines = try await command("UID SEARCH \(criteria)")
        return lines.compactMap(IMAPParser.searchResults).flatMap { $0 }
    }

    /// UIDs from `uids` that still exist in the selected mailbox.
    func existing(_ uids: [UInt32]) async throws -> [UInt32] {
        var found: [UInt32] = []
        for chunk in UIDSet.chunks(uids) {
            found += try await uidSearch("UID \(UIDSet.string(from: chunk))")
        }
        let wanted = Set(uids)
        return found.filter { wanted.contains($0) }
    }

    func fetchMeta(_ uids: [UInt32], labels: Bool) async throws -> [UInt32: MessageMeta] {
        var result: [UInt32: MessageMeta] = [:]
        let items = labels ? "(UID INTERNALDATE FLAGS X-GM-LABELS)" : "(UID INTERNALDATE FLAGS)"
        for chunk in UIDSet.chunks(uids) {
            let lines = try await command("UID FETCH \(UIDSet.string(from: chunk)) \(items)")
            for line in lines {
                guard let attributes = IMAPParser.fetchAttributes(line),
                    let uid = attributes["UID"]?.text.flatMap(UInt32.init),
                    let dateText = attributes["INTERNALDATE"]?.text,
                    let date = Self.parseInternalDate(dateText)
                else { continue }
                let flags = Set((attributes["FLAGS"]?.items ?? []).compactMap { $0.text?.uppercased() })
                let gmLabels = Set((attributes["X-GM-LABELS"]?.items ?? []).compactMap { $0.text?.uppercased() })
                result[uid] = MessageMeta(internalDate: date, flags: flags, labels: gmLabels)
            }
        }
        return result
    }

    func move(_ uids: [UInt32], to rawName: String) async throws {
        _ = try await command("UID MOVE \(UIDSet.string(from: uids)) \(IMAPParser.quote(rawName))")
    }

    func copy(_ uids: [UInt32], to rawName: String) async throws {
        _ = try await command("UID COPY \(UIDSet.string(from: uids)) \(IMAPParser.quote(rawName))")
    }

    func markDeleted(_ uids: [UInt32]) async throws {
        _ = try await command("UID STORE \(UIDSet.string(from: uids)) +FLAGS.SILENT (\\Deleted)")
    }

    /// UID EXPUNGE when the server has UIDPLUS, so only these messages go. Without
    /// it, EXPUNGE also removes anything another client already marked \Deleted
    /// in this folder — acceptable for a tool whose job is to empty the folder.
    func expunge(_ uids: [UInt32]) async throws {
        if supportsUIDPlus {
            _ = try await command("UID EXPUNGE \(UIDSet.string(from: uids))")
        } else {
            _ = try await command("EXPUNGE")
        }
    }

    // MARK: - Plumbing

    struct TaggedResult {
        var status: String
        var text: String
        var untagged: [String]
    }

    /// Sends a command and returns its untagged lines; NO/BAD throws.
    private func command(_ line: String) async throws -> [String] {
        let name = line.split(separator: " ").prefix(line.hasPrefix("UID ") ? 2 : 1).joined(separator: " ")
        let result = try await send(line, logAs: name)
        guard result.status == "OK" else {
            throw EbbError.serverRefused(command: name, message: result.text)
        }
        return result.untagged
    }

    private func send(_ line: String, logAs name: String) async throws -> TaggedResult {
        let tag = "E\(nextTag)"
        nextTag += 1
        try await connection.send("\(tag) \(line)")
        var untagged: [String] = []
        while true {
            let response = try await connection.readResponse()
            if response.hasPrefix(tag + " ") {
                let rest = response.dropFirst(tag.count + 1)
                let status = rest.prefix { $0 != " " }.uppercased()
                let text = rest.drop { $0 != " " }.trimmingCharacters(in: .whitespaces)
                return TaggedResult(status: status, text: text, untagged: untagged)
            }
            if response.hasPrefix("+") {
                throw EbbError.protocolError("unexpected continuation after \(name)")
            }
            untagged.append(response)
        }
    }

    // MARK: - Helpers

    private static let internalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return formatter
    }()

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "d-MMM-yyyy"
        return formatter
    }()

    static func parseInternalDate(_ text: String) -> Date? {
        internalDateFormatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    static func searchDate(_ date: Date) -> String {
        searchDateFormatter.string(from: date)
    }

    private static let roleNames: [(MailboxRole, [String])] = [
        (.sent, ["sent", "sent messages", "sent mail", "sent items", "enviados", "e-mails enviados",
                 "mensagens enviadas", "itens enviados"]),
        (.drafts, ["drafts", "rascunhos"]),
        (.trash, ["trash", "deleted messages", "deleted items", "lixeira", "itens excluídos", "itens apagados"]),
        (.junk, ["junk", "spam", "junk e-mail", "lixo eletrônico", "lixo eletronico"]),
        (.all, ["all mail", "todos os e-mails"]),
        (.archive, ["archive", "arquivo"]),
    ]

    /// SPECIAL-USE flags first; when a server does not send them, the name decides.
    /// With `name == nil` only the flags are looked at.
    static func role(flags: Set<String>, name: String?) -> MailboxRole {
        let byFlag: [(String, MailboxRole)] = [
            ("\\ALL", .all), ("\\ARCHIVE", .archive), ("\\DRAFTS", .drafts),
            ("\\JUNK", .junk), ("\\SENT", .sent), ("\\TRASH", .trash),
        ]
        for (flag, role) in byFlag where flags.contains(flag) {
            return role
        }
        guard let name else { return .other }
        if name.uppercased() == "INBOX" { return .inbox }
        let lowered = name.lowercased()
        let leaf = lowered.split(separator: "/").last.map(String.init) ?? lowered
        for (role, names) in roleNames where names.contains(lowered) || names.contains(leaf) {
            return role
        }
        return .other
    }
}
