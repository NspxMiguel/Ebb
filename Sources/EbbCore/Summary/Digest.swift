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
        []  // TODO(lead)
    }
}
