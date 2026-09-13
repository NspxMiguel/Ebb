import Foundation

/// Deletes mail from one account. Every call opens its own IMAP session and
/// logs out at the end, so a Cleaner is cheap and safe to use from any task.
///
/// Two strategies, picked from the server's capabilities rather than from the
/// account's provider (a Google Workspace domain on a custom host is still Gmail):
///
/// - Gmail (X-GM-EXT-1): folders are labels. Expunging from INBOX only removes a
///   label and, from All Mail, "archives" — nothing is freed. The only real
///   delete is moving to Trash and expunging there. So All Mail, Spam and Trash
///   are the whole account; scanning INBOX or labels would count twice.
/// - Everything else (iCloud included): folders are real. \Deleted + EXPUNGE
///   frees the space directly. iCloud has no MOVE, so "to Trash" is COPY + delete.
public struct Cleaner: Sendable {
    public let account: Account
    let password: String
    /// Seconds to wait for any single server response.
    public var responseTimeout: TimeInterval = 120

    public init(account: Account, password: String) {
        self.account = account
        self.password = CredentialStore.normalize(password)
    }

    /// Logs in and out. Throws `EbbError.authenticationFailed` on a bad password.
    public func testLogin() async throws {
        try await withSession { _ in }
    }

    /// Every mailbox the server lists, with its detected role.
    public func mailboxes() async throws -> [MailboxInfo] {
        try await withSession { client in try await client.list() }
    }

    /// What `run` would delete, without changing anything.
    public func plan(mode: CleanupMode, now: Date = Date()) async throws -> CleanupPlan {
        try await withSession { client in
            let cutoff = cutoffDate(mode: mode, now: now)
            let boxes = try await client.list()
            var plans: [MailboxPlan] = []
            for box in targets(in: boxes, client: client) {
                let uids = try await candidates(in: box, client: client, mode: mode, cutoff: cutoff)
                plans.append(MailboxPlan(mailbox: box, uids: uids))
            }
            return CleanupPlan(mode: mode, cutoff: cutoff, mailboxes: plans)
        }
    }

    /// Deletes (or, with `dryRun`, only counts) according to the account's rule.
    @discardableResult
    public func run(
        mode: CleanupMode,
        dryRun: Bool,
        now: Date = Date(),
        progress: (@Sendable (CleanerEvent) -> Void)? = nil
    ) async throws -> RunSummary {
        progress?(.connecting)
        let summary = try await withSession { client -> RunSummary in
            let cutoff = cutoffDate(mode: mode, now: now)
            let boxes = try await client.list()
            var tally = Tally()
            if client.isGmail {
                try await runGmail(
                    client: client, boxes: boxes, mode: mode, cutoff: cutoff, dryRun: dryRun,
                    tally: &tally, progress: progress)
            } else {
                try await runFolders(
                    client: client, boxes: boxes, mode: mode, cutoff: cutoff, dryRun: dryRun,
                    tally: &tally, progress: progress)
            }
            return RunSummary(
                date: now, mode: mode, dryRun: dryRun, deleted: tally.deleted, pending: tally.pending,
                mailboxesTouched: tally.touched)
        }
        progress?(.finished(summary))
        return summary
    }

    // MARK: - Strategies

    private struct Tally {
        var deleted = 0
        var pending = 0
        var touched = 0
    }

    private var rule: CleanupRule { account.rule }

    private func runGmail(
        client: IMAPClient, boxes: [MailboxInfo], mode: CleanupMode, cutoff: Date?, dryRun: Bool,
        tally: inout Tally, progress: (@Sendable (CleanerEvent) -> Void)?
    ) async throws {
        let trash = boxes.first { $0.role == .trash && $0.selectable }
        let selected = targets(in: boxes, client: client)
        var moved = 0

        for box in selected where box.role != .trash {
            progress?(.scanning(mailbox: box.displayName))
            let uids = try await candidates(in: box, client: client, mode: mode, cutoff: cutoff)
            guard !uids.isEmpty else { continue }
            tally.touched += 1
            if dryRun {
                tally.deleted += uids.count
                continue
            }
            guard let trash else { throw EbbError.trashNotFound }
            try await inChunks(uids, mailbox: box.displayName, progress: progress) { chunk in
                try await client.move(chunk, to: trash.rawName)
            }
            // A MOVE is only a delete if the messages actually left.
            let remaining = try await client.existing(uids)
            moved += uids.count - remaining.count
            tally.pending += remaining.count
        }

        guard rule.permanent else {
            tally.deleted += moved
            return
        }
        guard let trash, selected.contains(trash) else {
            // Trash excluded by the user: messages stay there, which is still "moved".
            tally.deleted += moved
            return
        }

        // Moved messages keep their INTERNALDATE, so the same criteria find them
        // in Trash together with whatever old mail was already there.
        progress?(.scanning(mailbox: trash.displayName))
        let uids = try await candidates(in: trash, client: client, mode: mode, cutoff: cutoff)
        if dryRun {
            if !uids.isEmpty { tally.touched += 1 }
            tally.deleted += uids.count
            return
        }
        guard !uids.isEmpty else {
            tally.deleted += moved
            return
        }
        tally.touched += 1
        let removed = try await deleteForever(uids, in: trash, client: client, progress: progress)
        tally.pending += uids.count - removed
        // What left Trash is gone for good, and it includes what this run moved.
        tally.deleted += removed
    }

    private func runFolders(
        client: IMAPClient, boxes: [MailboxInfo], mode: CleanupMode, cutoff: Date?, dryRun: Bool,
        tally: inout Tally, progress: (@Sendable (CleanerEvent) -> Void)?
    ) async throws {
        let trash = boxes.first { $0.role == .trash && $0.selectable }
        for box in targets(in: boxes, client: client) {
            progress?(.scanning(mailbox: box.displayName))
            let uids = try await candidates(in: box, client: client, mode: mode, cutoff: cutoff)
            guard !uids.isEmpty else { continue }
            tally.touched += 1
            if dryRun {
                tally.deleted += uids.count
                continue
            }
            if rule.permanent {
                let removed = try await deleteForever(uids, in: box, client: client, progress: progress)
                tally.deleted += removed
                tally.pending += uids.count - removed
            } else {
                guard let trash else { throw EbbError.trashNotFound }
                try await inChunks(uids, mailbox: box.displayName, progress: progress) { chunk in
                    if client.supportsMove {
                        try await client.move(chunk, to: trash.rawName)
                    } else {
                        try await client.copy(chunk, to: trash.rawName)
                        try await client.markDeleted(chunk)
                        try await client.expunge(chunk)
                    }
                }
                let remaining = try await client.existing(uids)
                tally.deleted += uids.count - remaining.count
                tally.pending += remaining.count
            }
        }
    }

    /// \Deleted + expunge, then counts what really left: iCloud answers OK to
    /// EXPUNGE and defers it while another client has the folder open.
    private func deleteForever(
        _ uids: [UInt32], in box: MailboxInfo, client: IMAPClient,
        progress: (@Sendable (CleanerEvent) -> Void)?
    ) async throws -> Int {
        try await inChunks(uids, mailbox: box.displayName, progress: progress) { chunk in
            try await client.markDeleted(chunk)
            try await client.expunge(chunk)
        }
        let remaining = try await client.existing(uids)
        return uids.count - remaining.count
    }

    private func inChunks(
        _ uids: [UInt32], mailbox: String, progress: (@Sendable (CleanerEvent) -> Void)?,
        _ body: ([UInt32]) async throws -> Void
    ) async throws {
        var done = 0
        progress?(.deleting(mailbox: mailbox, done: 0, total: uids.count))
        for chunk in UIDSet.chunks(uids) {
            try await body(chunk)
            done += chunk.count
            progress?(.deleting(mailbox: mailbox, done: done, total: uids.count))
        }
    }

    // MARK: - Selection

    /// Mailboxes a run works on, Trash last so that what was moved there in
    /// the same run is emptied too.
    func targets(in boxes: [MailboxInfo], client: IMAPClient) -> [MailboxInfo] {
        let excluded = Set(rule.excludedMailboxes)
        var usable = boxes.filter {
            $0.selectable && $0.role != .drafts && !excluded.contains($0.rawName) && !Self.isNotesFolder($0)
        }
        if client.isGmail {
            // With All Mail hidden from IMAP the labels are all there is; moving
            // from them to Trash still deletes in Gmail, so fall back to them.
            // Checked against every mailbox, not the usable ones: excluding All
            // Mail must not widen the run to INBOX and labels.
            if boxes.contains(where: { $0.role == .all && $0.selectable }) {
                usable = usable.filter { [.all, .junk, .trash].contains($0.role) }
            }
        }
        if !rule.permanent {
            usable.removeAll { $0.role == .trash }
        }
        return usable.filter { $0.role != .trash } + usable.filter { $0.role == .trash }
    }

    /// Apple Notes and Gmail store notes as IMAP messages in a "Notes" folder;
    /// they are not email and are never touched.
    static func isNotesFolder(_ box: MailboxInfo) -> Bool {
        guard box.role == .other else { return false }
        let leaf = box.displayName.split(separator: "/").last.map { $0.lowercased() } ?? ""
        return leaf == "notes" || leaf == "notas"
    }

    private func candidates(
        in box: MailboxInfo, client: IMAPClient, mode: CleanupMode, cutoff: Date?
    ) async throws -> [UInt32] {
        let exists = try await client.select(box.rawName)
        guard exists > 0 else { return [] }

        var criteria: [String]
        if mode == .expired, let cutoff {
            // SEARCH dates have day granularity in the server's own time zone.
            // Two days past the cutoff is a superset in any zone; the exact
            // INTERNALDATE comparison below does the real filtering.
            criteria = ["BEFORE", IMAPClient.searchDate(cutoff.addingTimeInterval(2 * 86_400))]
        } else {
            criteria = ["ALL"]
        }
        if rule.keepFlagged { criteria.append("UNFLAGGED") }
        // Copying to Trash must not duplicate what another client already marked
        // deleted. A permanent delete re-selects those on purpose: a deferred
        // expunge from an earlier run is retried instead of lingering forever.
        if !rule.permanent { criteria.append("UNDELETED") }

        let found = try await client.uidSearch(criteria.joined(separator: " "))
        guard !found.isEmpty else { return [] }
        let meta = try await client.fetchMeta(found, labels: client.isGmail)
        return found.filter { uid in
            guard let message = meta[uid] else { return false }
            if message.flags.contains("\\DRAFT") || message.labels.contains("\\DRAFT") { return false }
            if rule.keepFlagged && message.flags.contains("\\FLAGGED") { return false }
            if let cutoff, mode == .expired { return message.internalDate < cutoff }
            return true
        }
    }

    private func cutoffDate(mode: CleanupMode, now: Date) -> Date? {
        mode == .expired ? now.addingTimeInterval(-rule.maxAge) : nil
    }

    // MARK: - Session

    private func withSession<T>(_ body: (IMAPClient) async throws -> T) async throws -> T {
        let endpoint = account.endpoint
        if !endpoint.useTLS && !endpoint.isLoopback {
            throw EbbError.insecureConnection
        }
        let client = IMAPClient(endpoint: endpoint, timeout: responseTimeout)
        do {
            try await client.connect()
            try await client.login(username: account.username, password: password)
            let result = try await body(client)
            await client.logout()
            return result
        } catch {
            await client.close()
            throw error
        }
    }
}
