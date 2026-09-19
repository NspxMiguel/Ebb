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

/// Mail that is only worth anything for a short while.
public enum DisposableKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Verification, login and one-time codes.
    case codes
    /// Newsletters, promotions and mass notifications (List-Unsubscribe,
    /// List-Id or Precedence: bulk/list/junk).
    case bulk

    public var id: String { rawValue }
}

/// What a cleanup is allowed to delete.
public struct CleanupRule: Codable, Hashable, Sendable {
    /// Everything that is not disposable is deleted once its INTERNALDATE (when
    /// the server received it) is older than this. Default: one day.
    public var maxAge: TimeInterval
    /// Messages of `disposableKinds` go sooner, after this age. Default: one hour.
    /// Ignored when it is not shorter than `maxAge`.
    public var disposableAge: TimeInterval
    /// Which kinds count as disposable. Empty turns the short tier off.
    public var disposableKinds: Set<DisposableKind>
    /// Starred (Gmail) / flagged (iCloud) messages are never deleted while on.
    public var keepFlagged: Bool
    /// Messages Gmail marks as Important are never deleted while on. Other
    /// servers have no such marker; there it changes nothing.
    public var keepImportant: Bool
    /// true: messages are gone for good (Trash is emptied too).
    /// false: messages only go to Trash, where the provider's own retention applies.
    public var permanent: Bool
    /// Ask a language model (Apple's on-device one, or Groq with a saved key)
    /// about messages between the two ages that the header rules did not mark
    /// disposable. Off by default: with Groq, sender, subject and the first lines
    /// of those messages leave the Mac. Any failure keeps the message.
    public var aiTriage: Bool
    /// Raw IMAP mailbox names (as LIST returns them) the cleanup never touches.
    /// Drafts are always skipped regardless of this list.
    public var excludedMailboxes: [String]
    /// An agent that writes running updates to this mailbox. Mail from this
    /// address is tidied per conversation: only each conversation's newest
    /// message stays in the Inbox. Empty turns it off. See `AgentDigest`.
    public var agentAddress: String
    /// Where a superseded agent message goes. Archived, never deleted: a run
    /// that is wrong about which message is current must be undoable.
    public var agentFolder: String
    /// How long agent mail is kept once it has been archived. This is its own
    /// age because the conversation with an agent goes stale much faster than
    /// ordinary mail, and because `agentFolder` is deliberately outside the
    /// age-based sweep — without this, archiving would mean keeping forever.
    /// `neverAge` keeps it indefinitely.
    public var agentAge: TimeInterval

    public init(
        maxAge: TimeInterval = 86_400,
        disposableAge: TimeInterval = 3_600,
        disposableKinds: Set<DisposableKind> = [.codes, .bulk],
        keepFlagged: Bool = true,
        keepImportant: Bool = true,
        permanent: Bool = true,
        aiTriage: Bool = false,
        excludedMailboxes: [String] = [],
        agentAddress: String = "",
        agentFolder: String = "Claude",
        agentAge: TimeInterval = CleanupRule.neverAge
    ) {
        self.maxAge = maxAge
        self.disposableAge = disposableAge
        self.disposableKinds = disposableKinds
        self.keepFlagged = keepFlagged
        self.keepImportant = keepImportant
        self.permanent = permanent
        self.aiTriage = aiTriage
        self.excludedMailboxes = excludedMailboxes
        self.agentAddress = agentAddress
        self.agentFolder = agentFolder
        self.agentAge = agentAge
    }

    /// Whether agent mail is tidied at all.
    public var tidiesAgentMail: Bool {
        !agentAddress.isEmpty && !agentFolder.isEmpty
    }

    /// Whether agent mail also expires on its own clock.
    public var expiresAgentMail: Bool {
        tidiesAgentMail && agentAge < Self.neverAge
    }

    public static let `default` = CleanupRule()

    /// A `maxAge` of this or more turns the long tier off: only disposable mail
    /// is cleaned and everything else stays, however old it gets. A finite value
    /// (a century) rather than `.infinity`, which JSON cannot encode.
    public static let neverAge: TimeInterval = 3_155_760_000

    /// Whether the long tier applies at all.
    public var usesLongTier: Bool { maxAge < Self.neverAge }

    /// Whether the short tier applies at all.
    public var usesDisposableTier: Bool {
        !disposableKinds.isEmpty && disposableAge < maxAge
    }

    // Accounts saved before a field existed keep decoding, with the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CleanupRule()
        maxAge = try c.decodeIfPresent(TimeInterval.self, forKey: .maxAge) ?? fallback.maxAge
        disposableAge = try c.decodeIfPresent(TimeInterval.self, forKey: .disposableAge) ?? fallback.disposableAge
        disposableKinds =
            try c.decodeIfPresent(Set<DisposableKind>.self, forKey: .disposableKinds) ?? fallback.disposableKinds
        keepFlagged = try c.decodeIfPresent(Bool.self, forKey: .keepFlagged) ?? fallback.keepFlagged
        keepImportant = try c.decodeIfPresent(Bool.self, forKey: .keepImportant) ?? fallback.keepImportant
        permanent = try c.decodeIfPresent(Bool.self, forKey: .permanent) ?? fallback.permanent
        aiTriage = try c.decodeIfPresent(Bool.self, forKey: .aiTriage) ?? fallback.aiTriage
        excludedMailboxes = try c.decodeIfPresent([String].self, forKey: .excludedMailboxes) ?? []
        agentAddress = try c.decodeIfPresent(String.self, forKey: .agentAddress) ?? fallback.agentAddress
        agentFolder = try c.decodeIfPresent(String.self, forKey: .agentFolder) ?? fallback.agentFolder
        agentAge = try c.decodeIfPresent(TimeInterval.self, forKey: .agentAge) ?? fallback.agentAge
    }
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
    /// Localized note about something that degraded without failing the run,
    /// e.g. the AI triage could not be reached and messages were kept.
    public var warning: String?
    /// Superseded agent messages filed away. Kept apart from `deleted`: they
    /// are still in the mailbox, just not in the Inbox.
    public var archived: Int

    public init(
        date: Date = Date(),
        mode: CleanupMode,
        dryRun: Bool,
        deleted: Int = 0,
        pending: Int = 0,
        mailboxesTouched: Int = 0,
        errorMessage: String? = nil,
        warning: String? = nil,
        archived: Int = 0
    ) {
        self.date = date
        self.mode = mode
        self.dryRun = dryRun
        self.deleted = deleted
        self.pending = pending
        self.mailboxesTouched = mailboxesTouched
        self.errorMessage = errorMessage
        self.warning = warning
        self.archived = archived
    }

    // Summaries written before this field existed decode with zero.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        mode = try c.decode(CleanupMode.self, forKey: .mode)
        dryRun = try c.decode(Bool.self, forKey: .dryRun)
        deleted = try c.decodeIfPresent(Int.self, forKey: .deleted) ?? 0
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
        mailboxesTouched = try c.decodeIfPresent(Int.self, forKey: .mailboxesTouched) ?? 0
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        warning = try c.decodeIfPresent(String.self, forKey: .warning)
        archived = try c.decodeIfPresent(Int.self, forKey: .archived) ?? 0
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
