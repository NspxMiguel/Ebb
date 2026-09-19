import Darwin
import Foundation
import XCTest

@testable import EbbCore

/// A deliberately small, synchronous IMAP peer. State and the command transcript
/// are protected separately from blocking socket reads, so tests can inspect it.
final class FakeIMAPServer: @unchecked Sendable {
    enum Profile { case gmail, icloud }

    struct Message: Equatable {
        let id: Int
        let internalDate: Date
        var flags: Set<String>
        var labels: Set<String>
        var rawHeaders: String = ""
        var rawBody: String = ""
    }

    private struct View {
        let name: String
        let attributes: String
        var nextUID: UInt32 = 1
        var messages: [UInt32: Int] = [:]
        var deleted: Set<UInt32> = []
    }

    let profile: Profile
    private let lock = NSLock()
    private let workers = DispatchGroup()
    private var listener: Int32 = -1
    private var client: Int32 = -1
    private var storedPort = 0
    private var transcript: [String] = []
    private var messages: [Int: Message] = [:]
    private var views: [View]
    private var nextID = 1
    private var configuredUIDPlus = true
    private var configuredDeferExpunge = false
    private var configuredPassword = "test-password"

    var port: Int { locked { storedPort } }
    var commandLog: [String] { locked { transcript } }
    var uidplus: Bool {
        get { locked { configuredUIDPlus } }
        set { locked { configuredUIDPlus = newValue } }
    }
    var deferExpunge: Bool {
        get { locked { configuredDeferExpunge } }
        set { locked { configuredDeferExpunge = newValue } }
    }
    var password: String {
        get { locked { configuredPassword } }
        set { locked { configuredPassword = newValue } }
    }
    var mailboxNames: [String] { locked { views.map(\.name) } }

    init(profile: Profile) {
        self.profile = profile
        let definitions: [(String, String)] =
            profile == .gmail
            ? [
                ("INBOX", "\\HasNoChildren"), ("[Gmail]", "\\Noselect"),
                ("[Gmail]/All Mail", "\\All"), ("[Gmail]/Drafts", "\\Drafts"),
                ("[Gmail]/Sent Mail", "\\Sent"), ("[Gmail]/Spam", "\\Junk"),
                ("[Gmail]/Starred", "\\Flagged"), ("[Gmail]/Trash", "\\Trash"), ("Work", ""),
            ]
            : [
                ("INBOX", ""), ("Archive", "\\Archive"), ("Drafts", "\\Drafts"),
                ("Sent Messages", "\\Sent"), ("Junk", "\\Junk"),
                ("Deleted Messages", "\\Trash"), ("Receipts", ""), ("Itens Exclu&AO0-dos", ""),
            ]
        views = definitions.map { View(name: $0.0, attributes: $0.1) }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func start() throws {
        try locked {
            guard listener < 0 else { return }
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { throw socketError() }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0, Darwin.listen(socket, 8) == 0 else {
                let error = socketError()
                Darwin.close(socket)
                throw error
            }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let result = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(socket, $0, &length)
                }
            }
            guard result == 0 else {
                let error = socketError()
                Darwin.close(socket)
                throw error
            }
            storedPort = Int(UInt16(bigEndian: address.sin_port))
            listener = socket
            workers.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { workers.leave() }
                acceptConnections(socket)
            }
        }
    }

    func stop() {
        locked {
            if client >= 0 { shutdown(client, SHUT_RDWR) }
            if listener >= 0 {
                shutdown(listener, SHUT_RDWR)
                Darwin.close(listener)
                listener = -1
            }
        }
        workers.wait()
    }

    private func socketError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    private func acceptConnections(_ socket: Int32) {
        while locked({ listener == socket }) {
            let connection = accept(socket, nil, nil)
            guard connection >= 0 else { return }
            let active = locked {
                guard listener == socket else { return false }
                client = connection
                return true
            }
            guard active else {
                Darwin.close(connection)
                return
            }
            var noSignal: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            serve(connection)
            locked {
                client = -1
                Darwin.close(connection)
            }
        }
    }

    private func send(_ text: String, to socket: Int32) -> Bool {
        send(Data(text.utf8), to: socket)
    }

    private func send(_ bytes: Data, to socket: Int32) -> Bool {
        return bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.send(socket, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    private func serve(_ socket: Int32) {
        guard send("* OK Fake IMAP ready\r\n", to: socket) else { return }
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        var selected: Int?
        var authenticated = false
        while true {
            let count = recv(socket, &bytes, bytes.count, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return }
            buffer.append(contentsOf: bytes.prefix(count))
            while let end = buffer.range(of: Data([13, 10])) {
                let line = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<end.upperBound)
                let tokens = Self.tokens(line)
                guard tokens.count >= 2 else {
                    if !send("* BAD Missing command\r\n", to: socket) { return }
                    continue
                }
                let tag = tokens[0]
                let arguments = Array(tokens.dropFirst())
                let reply = locked {
                    transcript.append(
                        arguments[0].uppercased() == "LOGIN"
                            ? "LOGIN \(arguments.count > 1 ? Self.quote(arguments[1]) : "") <redacted>"
                            : line.drop(while: { $0.isWhitespace }).dropFirst(tag.count)
                                .trimmingCharacters(in: .whitespaces))
                    if authenticated, let view = selected, arguments.count >= 4,
                        arguments[0].uppercased() == "UID", arguments[1].uppercased() == "FETCH"
                    {
                        return fetch(arguments, request: line, tag: tag, view: view)
                    }
                    return Data(respond(arguments, tag: tag, selected: &selected, authenticated: &authenticated).utf8)
                }
                guard send(reply, to: socket), arguments[0].uppercased() != "LOGOUT" else { return }
            }
        }
    }

    /// Quoted strings retain spaces and unescape IMAP backslash escapes.
    private static func tokens(_ line: String) -> [String] {
        var result: [String] = []
        var token = ""
        var quoted = false
        var escaped = false
        var started = false
        for character in line {
            if escaped {
                token.append(character)
                escaped = false
                continue
            }
            if quoted && character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                quoted.toggle()
                started = true
                continue
            }
            if !quoted && (character.isWhitespace || character == "(" || character == ")") {
                if started {
                    result.append(token)
                    token = ""
                    started = false
                }
            } else {
                token.append(character)
                started = true
            }
        }
        if started { result.append(token) }
        return result
    }

    private static func quote(_ value: String) -> String {
        "\""
            + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    @discardableResult
    func addMessage(
        to mailbox: String, internalDate: Date, flags: Set<String> = [], labels: Set<String> = [],
        rawHeaders: String = "", rawBody: String = ""
    ) -> Int {
        locked {
            guard let view = viewIndex(mailbox), !views[view].attributes.contains("\\Noselect") else {
                preconditionFailure("Unknown or unselectable mailbox: \(mailbox)")
            }
            let id = nextID
            nextID += 1
            let normalizedFlags = Set(flags.map(Self.canonicalFlag))
            var message = Message(
                id: id, internalDate: internalDate,
                flags: normalizedFlags.subtracting(["\\Deleted"]), labels: labels, rawHeaders: rawHeaders,
                rawBody: rawBody)
            if profile == .gmail {
                message.labels = Set(message.labels.map(canonicalLabel))
                if mailbox != "[Gmail]/All Mail" { message.labels.insert(canonicalLabel(mailbox)) }
                if message.labels.contains("\\Drafts") || message.flags.contains("\\Draft") {
                    message.flags.insert("\\Draft")
                    message.labels.insert("\\Drafts")
                }
                if message.flags.contains("\\Flagged") { message.labels.insert("\\Starred") }
                if message.labels.contains("\\Starred") { message.flags.insert("\\Flagged") }
                messages[id] = message
                synchronizeGmail(id)
            } else {
                if mailbox == "Drafts" { message.flags.insert("\\Draft") }
                messages[id] = message
                insert(id, into: view)
            }
            if normalizedFlags.contains("\\Deleted") {
                for index in views.indices {
                    if let uid = views[index].messages.first(where: { $0.value == id })?.key {
                        views[index].deleted.insert(uid)
                    }
                }
            }
            return id
        }
    }

    func contents(of mailbox: String) -> [Message] {
        locked {
            guard let view = viewIndex(mailbox) else { return [] }
            return views[view].messages.keys.sorted().compactMap { uid in
                guard var message = messages[views[view].messages[uid]!] else { return nil }
                if views[view].deleted.contains(uid) { message.flags.insert("\\Deleted") }
                return message
            }
        }
    }

    func messageIDs(in mailbox: String) -> Set<Int> { Set(contents(of: mailbox).map(\.id)) }

    private func viewIndex(_ name: String) -> Int? {
        views.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func canonicalLabel(_ name: String) -> String {
        switch name.lowercased() {
        case "\\important": return "\\Important"
        case "inbox", "\\inbox": return "\\Inbox"
        case "[gmail]/sent mail", "\\sent": return "\\Sent"
        case "[gmail]/drafts", "\\drafts": return "\\Drafts"
        case "[gmail]/starred", "\\starred": return "\\Starred"
        case "[gmail]/spam", "\\spam": return "\\Spam"
        case "[gmail]/trash", "\\trash": return "\\Trash"
        default: return name
        }
    }

    private static func canonicalFlag(_ flag: String) -> String {
        ["\\Seen", "\\Answered", "\\Flagged", "\\Deleted", "\\Draft", "\\Recent"]
            .first { $0.caseInsensitiveCompare(flag) == .orderedSame } ?? flag
    }

    private func insert(_ id: Int, into view: Int) {
        guard !views[view].messages.values.contains(id) else { return }
        let uid = views[view].nextUID
        views[view].nextUID += 1
        views[view].messages[uid] = id
    }

    private func synchronizeGmail(_ id: Int) {
        guard let message = messages[id] else { return }
        let special = message.labels.contains("\\Trash") || message.labels.contains("\\Spam")
        for view in views.indices {
            let name = views[view].name
            let visible: Bool
            if name == "[Gmail]" {
                visible = false
            } else if name == "[Gmail]/All Mail" {
                visible = !special
            } else if special {
                visible =
                    (name == "[Gmail]/Trash" || name == "[Gmail]/Spam")
                    && message.labels.contains(canonicalLabel(name))
            } else {
                visible = message.labels.contains(canonicalLabel(name))
            }
            if visible { insert(id, into: view) } else { remove(id, from: view) }
        }
    }

    private func remove(_ id: Int, from view: Int) {
        for uid in views[view].messages.keys.filter({ views[view].messages[$0] == id }) {
            views[view].messages.removeValue(forKey: uid)
            views[view].deleted.remove(uid)
        }
    }

    private func erase(_ id: Int) {
        for view in views.indices { remove(id, from: view) }
        messages.removeValue(forKey: id)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    /// Substring match on one raw header line, which is what IMAP's HEADER key
    /// specifies and all the cleaner relies on.
    private func headerContains(_ field: String, _ value: String, uid: UInt32, in view: Int) -> Bool {
        guard let id = views[view].messages[uid], let raw = messages[id]?.rawHeaders else { return false }
        // The client sends the value quoted; the quotes are syntax, not content.
        let wanted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
        let needle = field.lowercased() + ":"
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        where line.lowercased().hasPrefix(needle) {
            if line.lowercased().contains(wanted) { return true }
        }
        return false
    }

    private func uidSet(_ text: String, in view: Int) -> Set<UInt32>? {
        let maximum = views[view].messages.keys.max() ?? 0
        func number(_ value: Substring) -> UInt32? { value == "*" ? maximum : UInt32(value) }
        var result: Set<UInt32> = []
        for piece in text.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = piece.split(separator: ":", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let first = number(bounds[0]),
                let last = number(bounds.last!)
            else { return nil }
            result.formUnion(views[view].messages.keys.filter { min(first, last)...max(first, last) ~= $0 })
        }
        return result
    }

    fileprivate func fetch(_ args: [String], request: String, tag: String, view: Int) -> Data {
        guard let uids = uidSet(args[2], in: view) else { return Data("\(tag) BAD Invalid UID set\r\n".utf8) }
        let pattern = #"BODY(\.PEEK)?\[(HEADER\.FIELDS\s*\(([^)]*)\)|TEXT)\](?:<0\.([0-9]+)>)?"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let source = request as NSString
        let sections = regex.matches(in: request, range: NSRange(location: 0, length: source.length))
        let ordered = views[view].messages.keys.sorted()
        var response = Data()
        func append(_ text: String) { response.append(contentsOf: text.utf8) }
        for uid in uids.sorted() {
            let id = views[view].messages[uid]!
            if sections.contains(where: { $0.range(at: 1).location == NSNotFound }) {
                messages[id]!.flags.insert("\\Seen")
            }
            let message = messages[id]!
            var flags = message.flags
            if views[view].deleted.contains(uid) { flags.insert("\\Deleted") }
            append(
                "* \(ordered.firstIndex(of: uid)! + 1) FETCH (UID \(uid) INTERNALDATE \(Self.quote(Self.formatter("dd-MMM-yyyy HH:mm:ss Z").string(from: message.internalDate))) FLAGS (\(flags.sorted().joined(separator: " ")))"
            )
            if profile == .gmail && args.map({ $0.uppercased() }).contains("X-GM-LABELS") {
                append(" X-GM-LABELS (\(message.labels.sorted().map(Self.quote).joined(separator: " ")))")
            }
            for section in sections {
                let data: Data
                let item: String
                if section.range(at: 3).location != NSNotFound {
                    let fields = source.substring(with: section.range(at: 3))
                    let names = Set(fields.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() })
                    var lines: [String] = []
                    var include = false
                    for line in message.rawHeaders.replacingOccurrences(of: "\r\n", with: "\n").components(
                        separatedBy: "\n")
                    {
                        if line.isEmpty { break }
                        if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                            include = line.firstIndex(of: ":").map { names.contains(line[..<$0].lowercased()) } ?? false
                        }
                        if include { lines.append(line) }
                    }
                    data = Data((lines.joined(separator: "\r\n") + (lines.isEmpty ? "\r\n" : "\r\n\r\n")).utf8)
                    item = "BODY[HEADER.FIELDS (\(fields))]"
                } else {
                    let body = Data(message.rawBody.utf8)
                    if section.range(at: 4).location != NSNotFound {
                        let count = Int(source.substring(with: section.range(at: 4))) ?? 0
                        data = Data(body.prefix(count))
                        item = "BODY[TEXT]<0>"
                    } else {
                        data = body
                        item = "BODY[TEXT]"
                    }
                }
                append(" \(item) {\(data.count)}\r\n")
                response.append(data)
            }
            append(")\r\n")
        }
        append("\(tag) OK Completed\r\n")
        return response
    }

    private func respond(_ args: [String], tag: String, selected: inout Int?, authenticated: inout Bool) -> String {
        let upper = args.map { $0.uppercased() }
        func ok(_ text: String = "Completed") -> String { "\(tag) OK \(text)\r\n" }
        func bad() -> String { "\(tag) BAD Unsupported command\r\n" }
        switch upper[0] {
        case "CAPABILITY":
            let capabilities =
                "IMAP4rev1" + (configuredUIDPlus ? " UIDPLUS" : "")
                + (profile == .gmail ? " MOVE X-GM-EXT-1" : "") + " SPECIAL-USE"
            return "* CAPABILITY \(capabilities)\r\n" + ok()
        case "LOGIN":
            guard args.count == 3 else { return bad() }
            guard args[2] == configuredPassword else { return "\(tag) NO [AUTHENTICATIONFAILED] Invalid password\r\n" }
            authenticated = true
            return ok("Logged in")
        case "LOGOUT": return "* BYE Logging out\r\n" + ok()
        case "NOOP": return ok()
        default: break
        }
        guard authenticated else { return "\(tag) NO Authenticate first\r\n" }
        if upper[0] == "LIST" {
            guard args.count == 3, args[1] == "", args[2] == "*" else { return bad() }
            return views.map { "* LIST (\($0.attributes)) \"/\" \(Self.quote($0.name))\r\n" }.joined() + ok()
        }
        if upper[0] == "SELECT" {
            guard args.count == 2, let view = viewIndex(args[1]), !views[view].attributes.contains("\\Noselect") else {
                return "\(tag) NO No such selectable mailbox\r\n"
            }
            selected = view
            return "* FLAGS (\\Seen \\Flagged \\Draft \\Deleted)\r\n* \(views[view].messages.count) EXISTS\r\n"
                + "* OK [UIDVALIDITY 1] Stable UIDs\r\n* OK [UIDNEXT \(views[view].nextUID)] Next UID\r\n"
                + ok("[READ-WRITE] Selected")
        }
        guard let view = selected else { return bad() }
        if upper == ["EXPUNGE"] { return expunge(view, uids: Set(views[view].messages.keys)) + ok() }
        guard args.count >= 3, upper[0] == "UID" else { return bad() }
        if upper[1] == "SEARCH" {
            var matches = Set(views[view].messages.keys)
            var index = 2
            while index < args.count {
                switch upper[index] {
                case "ALL": break
                case "UNFLAGGED":
                    matches = matches.filter { !messages[views[view].messages[$0]!]!.flags.contains("\\Flagged") }
                case "UNDELETED": matches.subtract(views[view].deleted)
                case "BEFORE":
                    index += 1
                    guard index < args.count, let date = Self.formatter("dd-MMM-yyyy").date(from: args[index]) else {
                        return bad()
                    }
                    matches = matches.filter { messages[views[view].messages[$0]!]!.internalDate < date }
                case "UID":
                    index += 1
                    guard index < args.count, let subset = uidSet(args[index], in: view) else { return bad() }
                    matches.formIntersection(subset)
                case "HEADER":
                    guard index + 2 < args.count else { return bad() }
                    let field = args[index + 1]
                    let value = args[index + 2]
                    index += 2
                    matches = matches.filter { headerContains(field, value, uid: $0, in: view) }
                default: return bad()
                }
                index += 1
            }
            return "* SEARCH" + matches.sorted().map { " \($0)" }.joined() + "\r\n" + ok()
        }
        guard let uids = uidSet(args[2], in: view) else { return bad() }
        switch upper[1] {
        case "STORE":
            guard args.count >= 5, upper[3] == "+FLAGS.SILENT" else { return bad() }
            for uid in uids {
                let id = views[view].messages[uid]!
                for flag in args.dropFirst(4).map(Self.canonicalFlag) {
                    if flag == "\\Deleted" {
                        views[view].deleted.insert(uid)
                    } else {
                        messages[id]!.flags.insert(flag)
                        if profile == .gmail {
                            if flag == "\\Flagged" { messages[id]!.labels.insert("\\Starred") }
                            if flag == "\\Draft" { messages[id]!.labels.insert("\\Drafts") }
                        }
                    }
                }
                if profile == .gmail { synchronizeGmail(id) }
            }
            return ok()
        case "MOVE", "COPY":
            guard args.count == 4, let destination = viewIndex(args[3]),
                !views[destination].attributes.contains("\\Noselect"),
                upper[1] != "MOVE" || profile == .gmail
            else { return bad() }
            var destinations: [UInt32] = []
            for uid in uids.sorted() {
                let id = views[view].messages[uid]!
                if profile == .gmail {
                    if views[destination].name == "[Gmail]/Trash" {
                        messages[id]!.labels = ["\\Trash"]
                    } else {
                        messages[id]!.labels.insert(canonicalLabel(views[destination].name))
                    }
                    if upper[1] == "MOVE", views[destination].name != "[Gmail]/Trash" {
                        messages[id]!.labels.remove(canonicalLabel(views[view].name))
                    }
                    synchronizeGmail(id)
                    destinations.append(views[destination].messages.first { $0.value == id }!.key)
                } else {
                    let copyID = nextID
                    nextID += 1
                    let original = messages[id]!
                    messages[copyID] = Message(
                        id: copyID, internalDate: original.internalDate, flags: original.flags, labels: [],
                        rawHeaders: original.rawHeaders, rawBody: original.rawBody)
                    insert(copyID, into: destination)
                    destinations.append(views[destination].messages.first { $0.value == copyID }!.key)
                }
            }
            if configuredUIDPlus && !uids.isEmpty {
                return ok(
                    "[COPYUID 1 \(uids.sorted().map(String.init).joined(separator: ",")) \(destinations.map(String.init).joined(separator: ","))] Completed"
                )
            }
            return ok()
        case "EXPUNGE":
            guard args.count == 3, configuredUIDPlus else { return bad() }
            return expunge(view, uids: uids) + ok()
        default: return bad()
        }
    }

    private func expunge(_ view: Int, uids: Set<UInt32>) -> String {
        guard !configuredDeferExpunge else { return "" }
        var response = ""
        for uid in views[view].deleted.intersection(uids).sorted() {
            guard let id = views[view].messages[uid] else { continue }
            let sequence = views[view].messages.keys.sorted().firstIndex(of: uid)! + 1
            if profile == .gmail {
                switch views[view].name {
                case "[Gmail]/All Mail":
                    views[view].deleted.remove(uid)
                    continue
                case "[Gmail]/Trash", "[Gmail]/Spam": erase(id)
                default:
                    messages[id]!.labels.remove(canonicalLabel(views[view].name))
                    synchronizeGmail(id)
                }
            } else {
                erase(id)
            }
            response += "* \(sequence) EXPUNGE\r\n"
        }
        return response
    }
}

/// Exercise the fake independently so a broken test peer cannot masquerade as
/// a Cleaner regression. This client only frames lines; it has no IMAP parser.
final class FakeIMAPServerTests: XCTestCase {
    private final class Client {
        private let socket: Int32
        private var counter = 0
        private var buffer = Data()

        init(port: Int) throws {
            socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connected == 0 else {
                let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                Darwin.close(socket)
                throw error
            }
            do { _ = try readLine() } catch {
                Darwin.close(socket)
                throw error
            }
        }

        deinit { Darwin.close(socket) }

        private func readLine() throws -> String {
            while true {
                if let end = buffer.range(of: Data([13, 10])) {
                    let line = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                    buffer.removeSubrange(..<end.upperBound)
                    return line
                }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = recv(socket, &bytes, bytes.count, 0)
                guard count > 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(count == 0 ? ECONNRESET : errno))
                }
                buffer.append(contentsOf: bytes.prefix(count))
            }
        }

        @discardableResult
        func command(_ command: String) throws -> String {
            counter += 1
            let tag = "T\(counter)"
            let bytes = Array("\(tag) \(command)\r\n".utf8)
            try bytes.withUnsafeBytes { data in
                var offset = 0
                while offset < data.count {
                    let sent = Darwin.send(socket, data.baseAddress!.advanced(by: offset), data.count - offset, 0)
                    guard sent > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    offset += sent
                }
            }
            var lines: [String] = []
            while true {
                let line = try readLine()
                lines.append(line)
                if line.hasPrefix(tag + " ") { return lines.joined(separator: "\n") }
            }
        }
    }

    private func server(_ profile: FakeIMAPServer.Profile) throws -> FakeIMAPServer {
        let server = FakeIMAPServer(profile: profile)
        try server.start()
        addTeardownBlock { server.stop() }
        return server
    }

    func testFetchLiteralBytesWithoutSocketTransport() {
        let server = FakeIMAPServer(profile: .gmail)
        server.addMessage(
            to: "INBOX", internalDate: Date(), labels: ["\\Important"],
            rawHeaders: "X-Hidden: secret\nSubject: Olá\n\tfolded\nFrom: sender\n",
            rawBody: "A😀Z")
        let response = server.fetch(
            ["UID", "FETCH", "1", "X-GM-LABELS"],
            request: "T1 UID FETCH 1 (X-GM-LABELS BODY.PEEK[HEADER.FIELDS (From Subject)] BODY.PEEK[TEXT]<0.3>)",
            tag: "T1", view: 0)
        let headers = "Subject: Olá\r\n\tfolded\r\nFrom: sender\r\n\r\n"
        XCTAssertNotNil(
            response.range(of: Data("BODY[HEADER.FIELDS (From Subject)] {\(headers.utf8.count)}\r\n\(headers)".utf8)))
        var partial = Data("BODY[TEXT]<0> {3}\r\n".utf8)
        partial.append(contentsOf: [0x41, 0xF0, 0x9F])
        partial.append(contentsOf: ")\r\nT1 OK Completed\r\n".utf8)
        XCTAssertTrue(response.suffix(partial.count).elementsEqual(partial))
        XCTAssertNil(response.range(of: Data("X-Hidden".utf8)))
        XCTAssertNotNil(response.range(of: Data("Important".utf8)))
        XCTAssertFalse(server.contents(of: "INBOX")[0].flags.contains("\\Seen"))
        _ = server.fetch(
            ["UID", "FETCH", "1", "BODY[TEXT]"],
            request: "T2 UID FETCH 1 BODY[TEXT]", tag: "T2", view: 0)
        XCTAssertTrue(server.contents(of: "INBOX")[0].flags.contains("\\Seen"))
    }

    func testHeaderAndPartialBodyLiteralsPreserveStoredOrderAndPeekFlags() throws {
        for profile in [FakeIMAPServer.Profile.icloud, .gmail] {
            let server = try server(profile)
            server.addMessage(
                to: "INBOX", internalDate: Date(), labels: ["\\Important"],
                rawHeaders:
                    "X-Ignored: private\r\nSubject: Olá\r\n\tfolded\r\nFrom: person@example.com\r\nSubject: duplicate\r\nContent-Type: text/plain\r\n",
                rawBody: "Hello world")
            let client = try Client(port: server.port)
            try client.command("LOGIN test test-password")
            try client.command("SELECT INBOX")
            let response = try client.command(
                "UID FETCH 1 (UID FLAGS X-GM-LABELS BODY.PEEK[HEADER.FIELDS (From sUbJeCt)] BODY.PEEK[TEXT]<0.5>)")
            let headers = "Subject: Olá\r\n\tfolded\r\nFrom: person@example.com\r\nSubject: duplicate\r\n\r\n"
            XCTAssertTrue(
                response.contains(
                    "BODY[HEADER.FIELDS (From sUbJeCt)] {\(headers.utf8.count)}\n"
                        + headers.replacingOccurrences(of: "\r\n", with: "\n")))
            XCTAssertTrue(response.contains("BODY[TEXT]<0> {5}\nHello"))
            XCTAssertFalse(response.contains("X-Ignored"))
            XCTAssertFalse(response.contains("Content-Type:"))
            XCTAssertFalse(server.contents(of: "INBOX")[0].flags.contains("\\Seen"))
            if profile == .gmail { XCTAssertTrue(response.contains("Important")) }
            let empty = try client.command("UID FETCH 1 (BODY.PEEK[HEADER.FIELDS (Missing)])")
            XCTAssertTrue(empty.contains("BODY[HEADER.FIELDS (Missing)] {2}\n\n"))
            try client.command("UID FETCH 1 (BODY[TEXT]<0.5>)")
            XCTAssertTrue(server.contents(of: "INBOX")[0].flags.contains("\\Seen"))
            try client.command("LOGOUT")
            server.stop()
        }
    }

    func testGmailLabelExpungeArchiveMoveAndPermanentDeletion() throws {
        let server = try server(.gmail)
        let date = Date(timeIntervalSince1970: 1_789_214_400)
        let id = server.addMessage(to: "INBOX", internalDate: date, labels: ["Work"])
        // Reserve Trash UID 1 so the move must return a different destination UID.
        server.addMessage(to: "[Gmail]/Trash", internalDate: date)
        let client = try Client(port: server.port)
        try client.command("LOGIN test test-password")
        XCTAssertTrue(try client.command("CAPABILITY").contains("IMAP4rev1 UIDPLUS MOVE X-GM-EXT-1 SPECIAL-USE"))
        try client.command("SELECT Work")
        try client.command("UID STORE 1 +FLAGS.SILENT (\\Deleted)")
        try client.command("EXPUNGE")
        XCTAssertTrue(server.contents(of: "Work").isEmpty)
        XCTAssertEqual(server.messageIDs(in: "INBOX"), [id])
        try client.command("SELECT \"[Gmail]/All Mail\"")
        try client.command("UID STORE 1 +FLAGS.SILENT (\\Deleted)")
        try client.command("EXPUNGE")
        XCTAssertTrue(try client.command("UID SEARCH ALL").contains("* SEARCH 1\n"))
        let fetch = try client.command("UID FETCH 1 (UID INTERNALDATE FLAGS X-GM-LABELS)")
        XCTAssertTrue(fetch.contains("12-Sep-2026 12:00:00 +0000"))
        XCTAssertTrue(fetch.contains("X-GM-LABELS"))
        XCTAssertTrue(try client.command("UID MOVE 1 \"[Gmail]/Trash\"").contains("[COPYUID 1 1 2]"))
        XCTAssertTrue(server.contents(of: "INBOX").isEmpty)
        XCTAssertTrue(server.contents(of: "[Gmail]/All Mail").isEmpty)
        try client.command("SELECT \"[Gmail]/Trash\"")
        try client.command("UID STORE 2 +FLAGS.SILENT (\\Deleted)")
        try client.command("UID EXPUNGE 2")
        for mailbox in server.mailboxNames { XCTAssertFalse(server.messageIDs(in: mailbox).contains(id)) }
        try client.command("LOGOUT")
    }

    func testSearchSetsWhitespaceFlagsAndSequentialConnections() throws {
        let server = try server(.icloud)
        let date = Date(timeIntervalSince1970: 1_789_214_400)
        for offset in 0..<5 {
            server.addMessage(
                to: "INBOX", internalDate: date.addingTimeInterval(Double(offset) * 86_400),
                flags: offset == 1 ? ["\\Flagged"] : [])
        }
        for _ in 0..<2 {
            let client = try Client(port: server.port)
            XCTAssertTrue(try client.command("  lOgIn   \"test user\"   \"test-password\"  ").contains(" OK "))
            XCTAssertTrue(try client.command("list  \"\"  \"*\"").contains("Itens Exclu&AO0-dos"))
            try client.command("select inbox")
            try client.command("uid store 3 +flags.silent (\\Deleted)")
            XCTAssertTrue(
                try client.command("uid search ALL UID 1:3,5 UNFLAGGED UNDELETED BEFORE 16-Sep-2026")
                    .contains("* SEARCH 1\n"))
            XCTAssertTrue(try client.command("UID SEARCH UID 4:*").contains("* SEARCH 4 5\n"))
            XCTAssertTrue(try client.command("UID MOVE 1 Archive").contains(" BAD "))
            XCTAssertTrue(try client.command("UNKNOWN").contains(" BAD "))
            try client.command("NOOP")
            try client.command("LOGOUT")
        }
        XCTAssertEqual(server.commandLog.filter { $0.hasPrefix("LOGIN ") }.count, 2)
        XCTAssertFalse(server.commandLog.joined().contains(server.password))
        XCTAssertFalse(server.commandLog.contains { $0.hasPrefix("T1 ") })
    }

    func testICloudCopyDeferredAndPlainExpunge() throws {
        let server = try server(.icloud)
        server.uidplus = false
        server.deferExpunge = true
        server.addMessage(to: "INBOX", internalDate: Date(timeIntervalSince1970: 1_789_214_400))
        let client = try Client(port: server.port)
        XCTAssertTrue(try client.command("LOGIN test wrong").contains("NO [AUTHENTICATIONFAILED]"))
        try client.command("LOGIN test test-password")
        XCTAssertTrue(try client.command("CAPABILITY").contains("* CAPABILITY IMAP4rev1 SPECIAL-USE\n"))
        try client.command("SELECT INBOX")
        try client.command("UID COPY 1 \"Deleted Messages\"")
        try client.command("UID STORE 1 +FLAGS.SILENT (\\Deleted)")
        XCTAssertTrue(try client.command("UID EXPUNGE 1").contains(" BAD "))
        try client.command("EXPUNGE")
        XCTAssertEqual(server.contents(of: "INBOX").count, 1)
        XCTAssertEqual(server.contents(of: "Deleted Messages").count, 1)
        server.deferExpunge = false
        try client.command("EXPUNGE")
        XCTAssertTrue(server.contents(of: "INBOX").isEmpty)
        XCTAssertEqual(server.contents(of: "Deleted Messages").count, 1)
        try client.command("LOGOUT")
    }
}
