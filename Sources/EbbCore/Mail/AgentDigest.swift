import Foundation

/// Keeping a running update from an agent readable in the inbox.
///
/// The agent's address is an alias of the owner's own mailbox, and several
/// agent sessions write to it at the same time. Each session sends one update
/// after another, so the older ones are noise the moment the next arrives —
/// but only within that session: archiving "everything but the newest" would
/// throw away what another session sent in parallel, which the owner has not
/// read yet.
///
/// So messages are grouped by the conversation they belong to (the sender's
/// own `X-Claude-Session` stamp, or the mail thread when there is none) and
/// only the newest of each group stays. A message that belongs to no
/// conversation is never archived: nothing says what it would be superseding.
public enum AgentDigest {
    public struct Message: Sendable, Hashable {
        public var uid: UInt32
        /// When the server received it — the mailbox's own ordering, not the
        /// sender's clock, which a wrong `Date:` header could put anywhere.
        public var internalDate: Date
        public var headers: MessageHeaders

        public init(uid: UInt32, internalDate: Date, headers: MessageHeaders) {
            self.uid = uid
            self.internalDate = internalDate
            self.headers = headers
        }
    }

    /// The messages each conversation has already superseded, oldest first.
    /// Empty when every conversation has a single message.
    public static func superseded(in messages: [Message]) -> [UInt32] {
        var byConversation: [String: [Message]] = [:]
        for message in messages {
            guard let key = message.headers.conversationKey else { continue }
            byConversation[key, default: []].append(message)
        }

        var stale: [Message] = []
        for group in byConversation.values where group.count > 1 {
            let ordered = group.sorted { left, right in
                left.internalDate == right.internalDate
                    ? left.uid < right.uid
                    : left.internalDate < right.internalDate
            }
            stale.append(contentsOf: ordered.dropLast())
        }
        return stale.sorted { $0.uid < $1.uid }.map(\.uid)
    }
}
