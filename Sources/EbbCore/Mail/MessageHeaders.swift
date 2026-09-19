import Foundation

/// The top-level headers Ebb reads from a message. Values are unfolded and
/// RFC 2047-decoded.
public struct MessageHeaders: Sendable, Hashable {
    /// Display form, e.g. "GitHub <noreply@github.com>".
    public var from: String
    public var subject: String
    public var date: String?
    /// e.g. "multipart/alternative; boundary=\"b1\"".
    public var contentType: String?
    public var contentTransferEncoding: String?
    public var listUnsubscribe: String?
    public var listID: String?
    public var precedence: String?
    public var autoSubmitted: String?
    /// This message's own identifier, angle brackets included.
    public var messageID: String?
    /// The message this one replies to, angle brackets included.
    public var inReplyTo: String?
    /// The whole thread chain, oldest first, as the sender wrote it.
    public var references: String?
    /// Which agent conversation sent this, when the sender stamped one.
    public var claudeSession: String?

    public init(
        from: String = "", subject: String = "", date: String? = nil, contentType: String? = nil,
        contentTransferEncoding: String? = nil, listUnsubscribe: String? = nil, listID: String? = nil,
        precedence: String? = nil, autoSubmitted: String? = nil, messageID: String? = nil,
        inReplyTo: String? = nil, references: String? = nil, claudeSession: String? = nil
    ) {
        self.from = from
        self.subject = subject
        self.date = date
        self.contentType = contentType
        self.contentTransferEncoding = contentTransferEncoding
        self.listUnsubscribe = listUnsubscribe
        self.listID = listID
        self.precedence = precedence
        self.autoSubmitted = autoSubmitted
        self.messageID = messageID
        self.inReplyTo = inReplyTo
        self.references = references
        self.claudeSession = claudeSession
    }

    /// What identifies the conversation this message belongs to, preferring the
    /// sender's own stamp and falling back to the thread.
    ///
    /// The thread is named after its oldest known message, so a reply and the
    /// message it answers land on the same key — which means the root has to
    /// answer with its OWN id, not with nothing. A message with no stamp, no
    /// references and no id of its own returns nil and is left alone: there is
    /// no way to tell what it would supersede.
    public var conversationKey: String? {
        if let session = claudeSession?.trimmingCharacters(in: .whitespaces), !session.isEmpty {
            return "session:" + session
        }
        let chain = (references ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        let root =
            chain.first
            ?? inReplyTo?.trimmingCharacters(in: .whitespaces).nonEmpty
            ?? messageID?.trimmingCharacters(in: .whitespaces).nonEmpty
        guard let root, !root.isEmpty else { return nil }
        return "thread:" + root
    }

    /// Lowercased addr-spec from `from` ("noreply@github.com"); the whole value
    /// lowercased when there are no angle brackets.
    public var fromAddress: String {
        let value = from.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = value.lastIndex(of: ">"), let start = value[..<end].lastIndex(of: "<") {
            return value[value.index(after: start)..<end].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return value.lowercased()
    }

    /// Parses a raw header block: CRLF or LF line endings, folded continuation
    /// lines, case-insensitive names, first occurrence wins.
    public static func parse(_ raw: String) -> MessageHeaders {
        var fields: [String: String] = [:]
        var name: String?
        var value = ""
        func save() {
            if let name, fields[name] == nil {
                fields[name] = MailText.decodeEncodedWords(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.isEmpty { break }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if name != nil { value += " " + line.trimmingCharacters(in: .whitespaces) }
            } else {
                save()
                name = nil
                value = ""
                if let colon = line.firstIndex(of: ":") {
                    name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    value = String(line[line.index(after: colon)...])
                }
            }
        }
        save()
        return MessageHeaders(
            from: fields["from"] ?? "", subject: fields["subject"] ?? "", date: fields["date"],
            contentType: fields["content-type"], contentTransferEncoding: fields["content-transfer-encoding"],
            listUnsubscribe: fields["list-unsubscribe"], listID: fields["list-id"],
            precedence: fields["precedence"], autoSubmitted: fields["auto-submitted"],
            messageID: fields["message-id"], inReplyTo: fields["in-reply-to"],
            references: fields["references"], claudeSession: fields["x-claude-session"])
    }
}

extension String {
    /// The string itself, or nil when it holds nothing worth keying on.
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
