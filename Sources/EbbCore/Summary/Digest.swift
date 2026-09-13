import Foundation

/// One message as the summary sees it. Built from a read-only fetch
/// (BODY.PEEK): listing messages never marks them as read.
public struct DigestMessage: Sendable, Hashable, Codable {
    public var uid: UInt32
    public var date: Date
    public var from: String
    public var subject: String
    public var snippet: String
    public var kind: DisposableKind?
    public var flagged: Bool
    public var important: Bool

    public init(
        uid: UInt32, date: Date, from: String, subject: String, snippet: String, kind: DisposableKind?,
        flagged: Bool, important: Bool
    ) {
        self.uid = uid
        self.date = date
        self.from = from
        self.subject = subject
        self.snippet = snippet
        self.kind = kind
        self.flagged = flagged
        self.important = important
    }
}

extension Cleaner {
    /// The newest INBOX messages, newest first, at most `limit`. Changes nothing
    /// on the server.
    public func recentMessages(limit: Int = 50) async throws -> [DigestMessage] {
        try await withSession { client in
            let boxes = try await client.list()
            let inbox = boxes.first { $0.role == .inbox && $0.selectable }?.rawName ?? "INBOX"
            guard try await client.select(inbox) > 0, limit > 0 else { return [] }

            // UIDs grow with arrival, so the highest ones are the newest.
            let newest = Array(try await client.uidSearch("ALL").sorted().suffix(limit))
            guard !newest.isEmpty else { return [] }
            let fetched = try await client.fetchMessages(
                newest, labels: client.isGmail, headers: true, bodyBytes: 4096)

            return newest.reversed().compactMap { uid -> DigestMessage? in
                guard let message = fetched[uid] else { return nil }
                let headers = MessageHeaders.parse(message.rawHeaders ?? "")
                return DigestMessage(
                    uid: uid,
                    date: message.meta.internalDate,
                    from: headers.from,
                    subject: headers.subject,
                    snippet: MailText.snippet(body: message.rawBody ?? "", headers: headers),
                    kind: MessageClassifier.kind(of: headers),
                    flagged: message.meta.flags.contains("\\FLAGGED"),
                    important: message.meta.labels.contains("\\IMPORTANT"))
            }
        }
    }
}
