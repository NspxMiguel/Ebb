import Foundation

/// Mail providers Ebb knows how to talk to out of the box. `custom` is any other
/// IMAP server; it gets the generic (iCloud-like) deletion strategy.
public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gmail
    case icloud
    case custom

    public var id: String { rawValue }
}

public struct ServerEndpoint: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    /// Plain IMAP is only accepted for loopback hosts (the test server); a real
    /// server with `useTLS == false` is refused before the password is sent.
    public var useTLS: Bool

    public init(host: String, port: Int = 993, useTLS: Bool = true) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    public var isLoopback: Bool {
        ["127.0.0.1", "localhost", "::1"].contains(host.lowercased())
    }
}

/// What a cleanup is allowed to delete.
public struct CleanupRule: Codable, Hashable, Sendable {
    /// Messages whose INTERNALDATE (when the server received them) is older than
    /// this are deleted by the automatic cleanup. Default: one day.
    public var maxAge: TimeInterval
    /// Starred (Gmail) / flagged (iCloud) messages are never deleted while on.
    public var keepFlagged: Bool
    /// true: messages are gone for good (Trash is emptied too).
    /// false: messages only go to Trash, where the provider's own retention applies.
    public var permanent: Bool
    /// Raw IMAP mailbox names (as LIST returns them) the cleanup never touches.
    /// Drafts are always skipped regardless of this list.
    public var excludedMailboxes: [String]

    public init(
        maxAge: TimeInterval = 86_400,
        keepFlagged: Bool = true,
        permanent: Bool = true,
        excludedMailboxes: [String] = []
    ) {
        self.maxAge = maxAge
        self.keepFlagged = keepFlagged
        self.permanent = permanent
        self.excludedMailboxes = excludedMailboxes
    }

    public static let `default` = CleanupRule()
}

/// Outcome of the last cleanup of an account, persisted with the account.
public struct RunSummary: Codable, Hashable, Sendable {
    public var date: Date
    public var mode: CleanupMode
    public var dryRun: Bool
    /// Messages removed (or, in a dry run, that would be removed).
    public var deleted: Int
    /// Messages the server accepted to delete but still lists — iCloud defers
    /// EXPUNGE while another client has the folder open. The next run retries.
    public var pending: Int
    public var mailboxesTouched: Int
    /// Localized error text when the run failed; nil on success.
    public var errorMessage: String?

    public init(
        date: Date = Date(),
        mode: CleanupMode,
        dryRun: Bool,
        deleted: Int = 0,
        pending: Int = 0,
        mailboxesTouched: Int = 0,
        errorMessage: String? = nil
    ) {
        self.date = date
        self.mode = mode
        self.dryRun = dryRun
        self.deleted = deleted
        self.pending = pending
        self.mailboxesTouched = mailboxesTouched
        self.errorMessage = errorMessage
    }

    public var succeeded: Bool { errorMessage == nil }
}

public enum CleanupMode: String, Codable, Sendable {
    /// Only messages older than `CleanupRule.maxAge`.
    case expired
    /// Every message, whatever its age ("delete all").
    case everything
}

public struct Account: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var provider: ProviderKind
    /// Login name: the Gmail address, or the Apple ID for iCloud.
    public var username: String
    public var endpoint: ServerEndpoint
    public var rule: CleanupRule
    /// Disabled accounts are skipped by the automatic cleanup and `ebb run`.
    public var isEnabled: Bool
    public var lastRun: RunSummary?

    public init(
        id: UUID = UUID(),
        provider: ProviderKind,
        username: String,
        endpoint: ServerEndpoint? = nil,
        rule: CleanupRule = .default,
        isEnabled: Bool = true,
        lastRun: RunSummary? = nil
    ) {
        self.id = id
        self.provider = provider
        self.username = username
        self.endpoint = endpoint ?? Provider.preset(provider)?.endpoint ?? ServerEndpoint(host: "")
        self.rule = rule
        self.isEnabled = isEnabled
        self.lastRun = lastRun
    }
}

public enum MailboxRole: String, Codable, Sendable {
    case inbox, all, archive, sent, drafts, junk, trash, other
}

public struct MailboxInfo: Codable, Hashable, Sendable {
    /// Name exactly as the server sent it (modified UTF-7); use it in commands.
    public var rawName: String
    /// Human-readable name (decoded).
    public var displayName: String
    public var role: MailboxRole
    public var selectable: Bool

    public init(rawName: String, displayName: String, role: MailboxRole, selectable: Bool) {
        self.rawName = rawName
        self.displayName = displayName
        self.role = role
        self.selectable = selectable
    }
}

public struct MailboxPlan: Sendable, Hashable {
    public var mailbox: MailboxInfo
    public var uids: [UInt32]

    public init(mailbox: MailboxInfo, uids: [UInt32]) {
        self.mailbox = mailbox
        self.uids = uids
    }
}

public struct CleanupPlan: Sendable, Hashable {
    public var mode: CleanupMode
    public var cutoff: Date?
    public var mailboxes: [MailboxPlan]

    public init(mode: CleanupMode, cutoff: Date?, mailboxes: [MailboxPlan]) {
        self.mode = mode
        self.cutoff = cutoff
        self.mailboxes = mailboxes
    }

    public var totalMessages: Int { mailboxes.reduce(0) { $0 + $1.uids.count } }
}

public enum CleanerEvent: Sendable {
    case connecting
    case scanning(mailbox: String)
    case deleting(mailbox: String, done: Int, total: Int)
    case finished(RunSummary)
}
