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
    /// Consulted only when `account.rule.aiTriage` is on. `Runner` fills it from
    /// `SummaryEngine.preferredTriager()`.
    public var triager: MailTriager?
    /// Where AI verdicts are remembered between runs.
    public var triageCacheURL: URL = TriageCache.defaultURL

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
            let context = RunContext(cleaner: self)
            defer { context.finish(now: now) }
            let boxes = try await client.list()
            var plans: [MailboxPlan] = []
            for box in targets(in: boxes, client: client) {
                let uids = try await candidates(in: box, client: client, mode: mode, now: now, context: context)
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
            let context = RunContext(cleaner: self)
            defer { context.finish(now: now) }
            let boxes = try await client.list()
            var tally = Tally()
            if client.isGmail {
                try await runGmail(
                    client: client, boxes: boxes, mode: mode, now: now, dryRun: dryRun,
                    context: context, tally: &tally, progress: progress)
            } else {
                try await runFolders(
                    client: client, boxes: boxes, mode: mode, now: now, dryRun: dryRun,
                    context: context, tally: &tally, progress: progress)
            }
            return RunSummary(
                date: now, mode: mode, dryRun: dryRun, deleted: tally.deleted, pending: tally.pending,
                mailboxesTouched: tally.touched, warning: context.warning)
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
        client: IMAPClient, boxes: [MailboxInfo], mode: CleanupMode, now: Date, dryRun: Bool,
        context: RunContext, tally: inout Tally, progress: (@Sendable (CleanerEvent) -> Void)?
    ) async throws {
        let trash = boxes.first { $0.role == .trash && $0.selectable }
        let selected = targets(in: boxes, client: client)
        var moved = 0

        for box in selected where box.role != .trash {
            progress?(.scanning(mailbox: box.displayName))
            let uids = try await candidates(in: box, client: client, mode: mode, now: now, context: context)
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
        let uids = try await candidates(in: trash, client: client, mode: mode, now: now, context: context)
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
        client: IMAPClient, boxes: [MailboxInfo], mode: CleanupMode, now: Date, dryRun: Bool,
        context: RunContext, tally: inout Tally, progress: (@Sendable (CleanerEvent) -> Void)?
    ) async throws {
        let trash = boxes.first { $0.role == .trash && $0.selectable }
        for box in targets(in: boxes, client: client) {
            progress?(.scanning(mailbox: box.displayName))
            let uids = try await candidates(in: box, client: client, mode: mode, now: now, context: context)
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
        in box: MailboxInfo, client: IMAPClient, mode: CleanupMode, now: Date, context: RunContext
    ) async throws -> [UInt32] {
        let exists = try await client.select(box.rawName)
        guard exists > 0 else { return [] }

        let longCutoff = now.addingTimeInterval(-rule.maxAge)
        let tiered = mode == .expired && rule.usesDisposableTier
        let shortCutoff = now.addingTimeInterval(-rule.disposableAge)

        var criteria: [String]
        if mode == .expired {
            // SEARCH dates have day granularity in the server's own time zone.
            // Two days past the cutoff is a superset in any zone; the exact
            // INTERNALDATE comparison below does the real filtering.
            let searchCutoff = tiered ? shortCutoff : longCutoff
            criteria = ["BEFORE", IMAPClient.searchDate(searchCutoff.addingTimeInterval(2 * 86_400))]
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

        var sure: [UInt32] = []
        var needsHeaders: [UInt32] = []
        for uid in found {
            guard let message = meta[uid], !isProtected(message) else { continue }
            guard mode == .expired else {
                sure.append(uid)
                continue
            }
            if message.internalDate < longCutoff {
                sure.append(uid)
            } else if tiered && message.internalDate < shortCutoff {
                needsHeaders.append(uid)
            }
        }
        guard !needsHeaders.isEmpty else { return sure }

        // Only messages in the window between the two ages need their headers
        // read, which keeps an hourly run cheap on a big mailbox.
        let fetched = try await client.fetchMessages(needsHeaders, labels: false, headers: true)
        var disposable = Set(
            needsHeaders.filter { uid in
                guard let raw = fetched[uid]?.rawHeaders,
                    let kind = MessageClassifier.kind(of: MessageHeaders.parse(raw))
                else { return false }
                return rule.disposableKinds.contains(kind)
            })
        if rule.aiTriage {
            let undecided = needsHeaders.filter { !disposable.contains($0) }
            disposable.formUnion(
                try await triage(
                    undecided, in: box, headers: fetched.compactMapValues(\.rawHeaders), client: client,
                    now: now, context: context))
        }
        return (sure + disposable).sorted()
    }

    /// Asks the model about messages the header rules left undecided. Verdicts
    /// are cached by Message-ID; a failure keeps every message it did not judge
    /// and leaves a warning on the run.
    private func triage(
        _ uids: [UInt32], in box: MailboxInfo, headers: [UInt32: String], client: IMAPClient, now: Date,
        context: RunContext
    ) async throws -> Set<UInt32> {
        guard !uids.isEmpty else { return [] }
        guard let triager else {
            context.warning = L10n.shared("warning.triage_unavailable")
            return []
        }
        var result: Set<UInt32> = []
        var unknown: [UInt32] = []
        var keys: [UInt32: String] = [:]
        for uid in uids {
            let key = Self.triageKey(account: account.id, rawHeaders: headers[uid], mailbox: box.rawName, uid: uid)
            keys[uid] = key
            switch context.cache[key] {
            case .some(true): result.insert(uid)
            case .some(false): break
            case .none: unknown.append(uid)
            }
        }
        guard !unknown.isEmpty, context.warning == nil else { return result }

        let fetched = try await client.fetchMessages(unknown, labels: false, headers: true, bodyBytes: 2048)
        let messages: [DigestMessage] = unknown.compactMap { uid in
            guard let message = fetched[uid] else { return nil }
            let parsed = MessageHeaders.parse(message.rawHeaders ?? "")
            return DigestMessage(
                uid: uid, date: message.meta.internalDate, from: parsed.from, subject: parsed.subject,
                snippet: MailText.snippet(body: message.rawBody ?? "", headers: parsed, limit: 300),
                kind: nil, flagged: false, important: false)
        }
        for start in stride(from: 0, to: messages.count, by: 25) {
            let batch = Array(messages[start..<min(start + 25, messages.count)])
            do {
                let verdict = try await triager.disposable(batch, account: account.username)
                for message in batch {
                    let isDisposable = verdict.contains(message.uid)
                    if let key = keys[message.uid] { context.cache.record(key, disposable: isDisposable, now: now) }
                    if isDisposable { result.insert(message.uid) }
                }
            } catch {
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                context.warning = L10n.shared("warning.triage_failed", detail)
                break
            }
        }
        return result
    }

    static func triageKey(account: UUID, rawHeaders: String?, mailbox: String, uid: UInt32) -> String {
        if let raw = rawHeaders {
            let unfolded = raw.replacingOccurrences(of: "\r\n", with: "\n")
            for line in unfolded.split(separator: "\n") where line.lowercased().hasPrefix("message-id:") {
                let id = line.dropFirst("message-id:".count).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { return "\(account.uuidString)|\(id)" }
            }
        }
        return "\(account.uuidString)|\(mailbox)|\(uid)"
    }

    private func isProtected(_ message: MessageMeta) -> Bool {
        if message.flags.contains("\\DRAFT") || message.labels.contains("\\DRAFT") { return true }
        if rule.keepFlagged && message.flags.contains("\\FLAGGED") { return true }
        if rule.keepImportant && message.labels.contains("\\IMPORTANT") { return true }
        return false
    }

    /// State shared by the mailboxes of one run.
    final class RunContext {
        let cache: TriageCache
        var warning: String?
        private let usesCache: Bool

        init(cleaner: Cleaner) {
            usesCache = cleaner.account.rule.aiTriage
            cache = TriageCache(fileURL: cleaner.triageCacheURL)
        }

        func finish(now: Date) {
            if usesCache { cache.save(now: now) }
        }
    }

    private func cutoffDate(mode: CleanupMode, now: Date) -> Date? {
        mode == .expired ? now.addingTimeInterval(-rule.maxAge) : nil
    }

    // MARK: - Session

    func withSession<T>(_ body: (IMAPClient) async throws -> T) async throws -> T {
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
