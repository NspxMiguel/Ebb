import EbbCore
import Foundation

/// Command-line parsing and one implementation function per subcommand. Every
/// user-visible line goes through L10n with a `cli.…` key.
@MainActor
enum CLI {

    // MARK: Dispatch

    static func run(arguments: [String]) async -> Int32 {
        let t = L10n.shared
        guard let command = arguments.first else {
            Terminal.err(t("cli.usage_short"))
            return 2
        }
        let args = Array(arguments.dropFirst())
        switch command {
        case "accounts": return accounts()
        case "add": return await add(args)
        case "remove": return remove(args)
        case "mailboxes": return await mailboxes(args)
        case "inbox": return await inbox(args)
        case "scan": return await scan(args)
        case "run": return await runCleanup(args)
        case "summary": return await summary(args)
        case "purge": return await purge(args)
        case "set": return setRule(args)
        case "groq-key": return groqKey(args)
        case "lang": return lang(args)
        case "version":
            Terminal.out(EbbVersion.current)
            return 0
        case "help", "-h", "--help":
            help()
            return 0
        default:
            Terminal.err(t("cli.unknown_command", command))
            Terminal.err(t("cli.usage_short"))
            return 2
        }
    }

    // MARK: accounts

    static func accounts() -> Int32 {
        let t = L10n.shared
        let store = AccountStore()
        guard !store.accounts.isEmpty else {
            Terminal.out(t("cli.no_accounts"))
            return 0
        }
        let headers = [
            t("cli.col.id"), t("cli.col.provider"), t("cli.col.username"),
            t("cli.col.enabled"), t("cli.col.max_age"), t("cli.col.disposable"),
            t("cli.col.keep_flagged"), t("cli.col.keep_important"),
            t("cli.col.permanent"), t("cli.col.last_run"),
        ]
        let rows = store.accounts.map { account in
            [
                String(account.id.uuidString.prefix(8)),
                t("provider.\(account.provider.rawValue)"),
                account.username,
                enabled(account.isEnabled),
                Terminal.age(account.rule.maxAge),
                disposable(account.rule),
                enabled(account.rule.keepFlagged),
                enabled(account.rule.keepImportant),
                enabled(account.rule.permanent),
                lastRun(account.lastRun),
            ]
        }
        Terminal.table(headers: headers, rows: rows)
        return 0
    }

    /// The disposable tier column: "1h codes,bulk", or "off" when it does not
    /// apply (no kinds selected, or the short age is not shorter than maxAge).
    private static func disposable(_ rule: CleanupRule) -> String {
        let t = L10n.shared
        guard rule.usesDisposableTier else { return t("cli.off") }
        let kinds = rule.disposableKinds.sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue).joined(separator: ",")
        return "\(Terminal.age(rule.disposableAge)) \(kinds)"
    }

    private static func enabled(_ value: Bool) -> String {
        L10n.shared(value ? "cli.on" : "cli.off")
    }

    private static func lastRun(_ summary: RunSummary?) -> String {
        let t = L10n.shared
        guard let summary else { return t("cli.never") }
        let ago = Terminal.agoPhrase(summary.date)
        if summary.errorMessage != nil { return t("cli.last_run_error", ago) }
        return t("cli.last_run_ok", summary.deleted, summary.pending, ago)
    }

    // MARK: add

    static func add(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        guard let providerToken = args.first, let kind = ProviderKind(rawValue: providerToken) else {
            Terminal.err(t("cli.add_bad_provider", args.first ?? ""))
            return usageHint("ebb add <gmail|icloud|custom> <username> [--no-test]")
        }
        let parsed: ParsedArgs
        switch parse(Array(args.dropFirst()), value: kind == .custom ? ["host", "port"] : [], bool: ["no-test"]) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count == 1 else {
            return usageHint("ebb add <gmail|icloud|custom> <username> [--no-test]")
        }
        let username = parsed.positionals[0]

        let endpoint: ServerEndpoint
        switch kind {
        case .gmail, .icloud:
            endpoint = Provider.preset(kind)?.endpoint ?? ServerEndpoint(host: "")
        case .custom:
            guard let host = parsed.values["host"]?.last, !host.isEmpty else {
                Terminal.err(t("cli.add_custom_host"))
                return usageHint("ebb add custom <username> --host <server> [--port 993] [--no-test]")
            }
            let port: Int
            if let raw = parsed.values["port"]?.last {
                guard let value = Int(raw), value > 0 else {
                    Terminal.err(t("cli.bad_port", raw))
                    return 2
                }
                port = value
            } else {
                port = 993
            }
            endpoint = ServerEndpoint(host: host, port: port, useTLS: true)
        }

        guard let password = Terminal.readPassword(prompt: t("cli.add_prompt", username)),
            !password.isEmpty
        else {
            Terminal.err(t("cli.add_no_password"))
            return 2
        }

        let account = Account(id: UUID(), provider: kind, username: username, endpoint: endpoint)
        if !parsed.present.contains("no-test") {
            let cleaner = Cleaner(account: account, password: password)
            do {
                try await cleaner.testLogin()
            } catch {
                Terminal.err(errorText(error))
                return 1
            }
        }
        do {
            try CredentialStore.setPassword(password, for: account.id)
            let store = AccountStore()
            try store.add(account)
        } catch {
            Terminal.err(errorText(error))
            return 1
        }
        Terminal.out(t("cli.add_ok"))
        return 0
    }

    // MARK: remove

    static func remove(_ args: [String]) -> Int32 {
        guard args.count == 1 else { return usageHint("ebb remove <account>") }
        let store = AccountStore()
        guard let account = store.account(matching: args[0]) else {
            Terminal.err(errorText(EbbError.accountNotFound(args[0])))
            return 1
        }
        do {
            try store.remove(id: account.id)
        } catch {
            Terminal.err(errorText(error))
            return 1
        }
        Terminal.out(L10n.shared("cli.remove_ok"))
        return 0
    }

    // MARK: mailboxes

    static func mailboxes(_ args: [String]) async -> Int32 {
        guard args.count == 1 else { return usageHint("ebb mailboxes <account>") }
        let t = L10n.shared
        let store = AccountStore()
        guard let account = store.account(matching: args[0]) else {
            Terminal.err(errorText(EbbError.accountNotFound(args[0])))
            return 1
        }
        guard let password = CredentialStore.password(for: account.id) else {
            Terminal.err(errorText(EbbError.missingPassword))
            return 1
        }
        let cleaner = Cleaner(account: account, password: password)
        let boxes: [MailboxInfo]
        do {
            boxes = try await cleaner.mailboxes()
        } catch {
            Terminal.err(errorText(error))
            return 1
        }
        let excluded = account.rule.excludedMailboxes
        let headers = [t("cli.col.mailbox"), t("cli.col.display"), t("cli.col.role"), t("cli.col.notes")]
        let rows = boxes.map { box in
            var notes: [String] = []
            if box.role == .drafts { notes.append(t("cli.mailboxes.skipped_drafts")) }
            if excluded.contains(box.rawName) { notes.append(t("cli.mailboxes.skipped_excluded")) }
            return [
                box.rawName,
                box.displayName,
                t("role.\(box.role.rawValue)"),
                notes.joined(separator: ", "),
            ]
        }
        Terminal.table(headers: headers, rows: rows)
        return 0
    }

    // MARK: inbox

    /// Lists the newest Inbox messages per account. Read-only: never STARs,
    /// never flags, never marks-as-read, never deletes.
    static func inbox(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: ["limit"], bool: []) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count <= 1 else { return usageHint("ebb inbox [<account>] [--limit 20]") }
        var limit = 20
        if let raw = parsed.values["limit"]?.last {
            guard let value = Int(raw), value > 0 else {
                Terminal.err(t("cli.inbox.limit_bad", raw))
                return 2
            }
            limit = value
        }

        let store = AccountStore()
        let targets: [Account]
        if let query = parsed.positionals.first {
            guard let account = store.account(matching: query) else {
                Terminal.err(errorText(EbbError.accountNotFound(query)))
                return 1
            }
            targets = [account]
        } else {
            targets = store.accounts.filter(\.isEnabled)
        }
        guard !targets.isEmpty else {
            Terminal.out(t("cli.run_none"))
            return 0
        }

        var failed = false
        for account in targets {
            guard let password = CredentialStore.password(for: account.id) else {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(EbbError.missingPassword)))
                continue
            }
            let cleaner = Cleaner(account: account, password: password)
            do {
                let messages = try await cleaner.recentMessages(limit: limit)
                Terminal.out(t("cli.scan_account", account.username))
                inboxTable(messages: messages)
            } catch {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(error)))
            }
        }
        return failed ? 1 : 0
    }

    /// Relative age, kind (codes/bulk/-), flags (★ flagged, ! important), from,
    /// subject. The row is trimmed to about 100 columns by truncating `from`
    /// (cap 30) and the subject (whatever the grid leaves).
    private static func inboxTable(messages: [DigestMessage], now: Date = Date()) {
        let t = L10n.shared
        let headers = [
            t("cli.inbox.col.age"), t("cli.inbox.col.kind"), t("cli.inbox.col.flags"),
            t("cli.inbox.col.from"), t("cli.inbox.col.subject"),
        ]
        let rows = messages.map { message in
            var flags = ""
            if message.flagged { flags += "★" }
            if message.important { flags += "!" }
            return [
                Terminal.age(now.timeIntervalSince(message.date)),
                message.kind?.rawValue ?? "-",
                flags,
                message.from,
                message.subject,
            ]
        }
        let all = [headers] + rows
        var widths = headers.indices.map { column in
            all.map { $0[column].count }.max() ?? 0
        }
        widths[3] = min(widths[3], 30)
        let prefix = widths[0] + 2 + widths[1] + 2 + widths[2] + 2 + widths[3] + 2
        let subjectWidth = max(10, 100 - prefix)
        let visible = rows.map { row in
            [
                row[0], row[1], row[2],
                Terminal.truncate(row[3], to: widths[3]),
                Terminal.truncate(row[4], to: subjectWidth),
            ]
        }
        Terminal.table(headers: headers, rows: visible)
    }

    // MARK: scan

    static func scan(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: [], bool: ["all"]) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count <= 1 else { return usageHint("ebb scan [<account>] [--all]") }
        let mode: CleanupMode = parsed.present.contains("all") ? .everything : .expired

        let store = AccountStore()
        let targets: [Account]
        if let query = parsed.positionals.first {
            guard let account = store.account(matching: query) else {
                Terminal.err(errorText(EbbError.accountNotFound(query)))
                return 1
            }
            targets = [account]
        } else {
            targets = store.accounts.filter(\.isEnabled)
        }
        guard !targets.isEmpty else {
            Terminal.out(t("cli.run_none"))
            return 0
        }

        var failed = false
        for account in targets {
            guard let password = CredentialStore.password(for: account.id) else {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(EbbError.missingPassword)))
                continue
            }
            let cleaner = Cleaner(account: account, password: password)
            do {
                let plan = try await cleaner.plan(mode: mode)
                Terminal.out(t("cli.scan_account", account.username))
                for mailboxPlan in plan.mailboxes {
                    let name = mailboxPlan.mailbox.displayName
                    let count = String(mailboxPlan.uids.count)
                    Terminal.out("  " + name.padding(toLength: 24, withPad: " ", startingAt: 0) + " " + count)
                }
                let modeName = mode == .everything ? t("cli.mode.everything") : t("cli.mode.expired")
                Terminal.out(t("cli.scan_total", plan.totalMessages, modeName))
            } catch {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(error)))
            }
        }
        return failed ? 1 : 0
    }

    // MARK: run

    static func runCleanup(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: [], bool: []) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count <= 1 else { return usageHint("ebb run [<account>]") }

        let store = AccountStore()
        var only: UUID?
        if let query = parsed.positionals.first {
            guard let account = store.account(matching: query) else {
                Terminal.err(errorText(EbbError.accountNotFound(query)))
                return 1
            }
            only = account.id
        }

        let results = await Runner.run(store: store, mode: .expired, dryRun: false, only: only)
        guard !results.isEmpty else {
            Terminal.out(t("cli.run_none"))
            return 0
        }
        var failed = false
        for result in results {
            if result.summary.errorMessage == nil {
                Terminal.out(
                    t(
                        "cli.run_summary", result.username, result.summary.deleted,
                        result.summary.pending, Terminal.agoPhrase(result.summary.date)))
            } else {
                failed = true
                Terminal.err(t("cli.account_error", result.username, result.summary.errorMessage ?? ""))
            }
        }
        return failed ? 1 : 0
    }

    // MARK: summary

    static func summary(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: [], bool: []) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count <= 1 else { return usageHint("ebb summary [<account>]") }

        guard let summarizer = SummaryEngine.preferred() else {
            Terminal.err(errorText(EbbError.summaryUnavailable))
            return 1
        }
        if summarizer is GroqSummarizer {
            Terminal.err(t("cli.summary.privacy"))
        }

        let store = AccountStore()
        let targets: [Account]
        if let query = parsed.positionals.first {
            guard let account = store.account(matching: query) else {
                Terminal.err(errorText(EbbError.accountNotFound(query)))
                return 1
            }
            targets = [account]
        } else {
            targets = store.accounts.filter(\.isEnabled)
        }
        guard !targets.isEmpty else {
            Terminal.out(t("cli.run_none"))
            return 0
        }

        var failed = false
        for account in targets {
            guard let password = CredentialStore.password(for: account.id) else {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(EbbError.missingPassword)))
                continue
            }
            let cleaner = Cleaner(account: account, password: password)
            Terminal.err(t("cli.summary.progress", account.username))
            do {
                let messages = try await cleaner.recentMessages(limit: 50)
                let text = try await summarizer.summarize(
                    messages, account: account.username, language: L10n.shared.resolved)
                Terminal.out(t("cli.summary.header", account.username))
                Terminal.out(text)
                Terminal.out(t("cli.summary.footer", summarizer.displayName))
            } catch {
                failed = true
                Terminal.err(t("cli.account_error", account.username, errorText(error)))
            }
        }
        return failed ? 1 : 0
    }

    // MARK: purge

    static func purge(_ args: [String]) async -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: [], bool: ["yes-delete-everything"]) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.count == 1 else {
            return usageHint("ebb purge <account> [--yes-delete-everything]")
        }
        let query = parsed.positionals[0]
        let store = AccountStore()
        guard let account = store.account(matching: query) else {
            Terminal.err(errorText(EbbError.accountNotFound(query)))
            return 1
        }
        guard let password = CredentialStore.password(for: account.id) else {
            Terminal.err(errorText(EbbError.missingPassword))
            return 1
        }
        let cleaner = Cleaner(account: account, password: password)

        guard parsed.present.contains("yes-delete-everything") else {
            do {
                let plan = try await cleaner.plan(mode: .everything)
                Terminal.out(t("cli.purge_warn", plan.totalMessages, account.username))
                Terminal.out(t("cli.purge_confirm", query))
            } catch {
                Terminal.err(errorText(error))
                return 1
            }
            return 2
        }

        do {
            let summary = try await cleaner.run(
                mode: .everything, dryRun: false,
                progress: { event in Terminal.progress(event) })
            Terminal.finishProgress()
            try store.recordRun(summary, for: account.id)
            Terminal.out(t("cli.purge_ok", account.username, summary.deleted, summary.pending))
        } catch {
            Terminal.finishProgress()
            Terminal.err(errorText(error))
            return 1
        }
        return 0
    }

    // MARK: set

    static func setRule(_ args: [String]) -> Int32 {
        let t = L10n.shared
        guard let query = args.first else { return usageHint("ebb set <account> [flags]") }
        let parsed: ParsedArgs
        switch parse(
            Array(args.dropFirst()),
            value: [
                "max-age", "disposable-age", "keep-flagged", "keep-important", "codes", "bulk",
                "permanent", "enabled", "exclude", "include",
            ],
            bool: [])
        {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.isEmpty else { return usageHint("ebb set <account> [flags]") }

        let store = AccountStore()
        guard var account = store.account(matching: query) else {
            Terminal.err(errorText(EbbError.accountNotFound(query)))
            return 1
        }
        var rule = account.rule
        if let raw = parsed.values["max-age"]?.last {
            guard let interval = Terminal.parseAge(raw) else {
                Terminal.err(t("cli.set.bad_age", raw))
                return 2
            }
            rule.maxAge = interval
        }
        if let raw = parsed.values["disposable-age"]?.last {
            guard let interval = Terminal.parseAge(raw) else {
                Terminal.err(t("cli.set.bad_age", raw))
                return 2
            }
            rule.disposableAge = interval
        }
        if let raw = parsed.values["codes"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--codes"))
                return 2
            }
            if value { rule.disposableKinds.insert(.codes) } else { rule.disposableKinds.remove(.codes) }
        }
        if let raw = parsed.values["bulk"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--bulk"))
                return 2
            }
            if value { rule.disposableKinds.insert(.bulk) } else { rule.disposableKinds.remove(.bulk) }
        }
        if let raw = parsed.values["keep-flagged"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--keep-flagged"))
                return 2
            }
            rule.keepFlagged = value
        }
        if let raw = parsed.values["keep-important"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--keep-important"))
                return 2
            }
            rule.keepImportant = value
        }
        if let raw = parsed.values["permanent"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--permanent"))
                return 2
            }
            rule.permanent = value
        }
        if let raw = parsed.values["enabled"]?.last {
            guard let value = Terminal.yesNo(raw) else {
                Terminal.err(t("cli.set.bad_on_off", "--enabled"))
                return 2
            }
            account.isEnabled = value
        }
        for name in parsed.values["exclude"] ?? [] {
            if !rule.excludedMailboxes.contains(name) {
                rule.excludedMailboxes.append(name)
            }
        }
        for name in parsed.values["include"] ?? [] {
            rule.excludedMailboxes.removeAll { $0 == name }
        }
        account.rule = rule
        do {
            try store.update(account)
        } catch {
            Terminal.err(errorText(error))
            return 1
        }

        Terminal.out(t("cli.set.max_age", Terminal.age(account.rule.maxAge)))
        Terminal.out(t("cli.set.disposable_age", Terminal.age(account.rule.disposableAge)))
        let kinds =
            account.rule.disposableKinds.isEmpty
            ? t("cli.off")
            : account.rule.disposableKinds.sorted { $0.rawValue < $1.rawValue }
                .map(\.rawValue).joined(separator: ",")
        Terminal.out(t("cli.set.kinds", kinds))
        Terminal.out(t("cli.set.keep_flagged", enabled(account.rule.keepFlagged)))
        Terminal.out(t("cli.set.keep_important", enabled(account.rule.keepImportant)))
        Terminal.out(t("cli.set.permanent", enabled(account.rule.permanent)))
        Terminal.out(t("cli.set.enabled", enabled(account.isEnabled)))
        let excluded =
            account.rule.excludedMailboxes.isEmpty
            ? t("cli.set.excluded_none")
            : account.rule.excludedMailboxes.joined(separator: ", ")
        Terminal.out(t("cli.set.excluded", excluded))
        return 0
    }

    // MARK: groq-key

    static func groqKey(_ args: [String]) -> Int32 {
        let t = L10n.shared
        let parsed: ParsedArgs
        switch parse(args, value: [], bool: ["status", "remove"]) {
        case .success(let value): parsed = value
        case .failure(let error): return flagError(error)
        }
        guard parsed.positionals.isEmpty else { return usageHint("ebb groq-key [--status|--remove]") }

        if parsed.present.contains("status") {
            let saved = SummaryEngine.groqKey().map { !$0.isEmpty } ?? false
            Terminal.out(t("cli.groq.status", t(saved ? "cli.groq.value_saved" : "cli.groq.value_none")))
            if let reason = SummaryEngine.onDeviceUnavailableReason {
                Terminal.out(t("cli.groq.ondevice_unavailable", reason))
            } else {
                Terminal.out(t("cli.groq.ondevice_available"))
            }
            return 0
        }

        if parsed.present.contains("remove") {
            SummaryEngine.removeGroqKey()
            Terminal.out(t("cli.groq.removed"))
            return 0
        }

        guard let key = Terminal.readPassword(prompt: t("cli.groq.prompt")), !key.isEmpty else {
            Terminal.err(t("cli.groq.no_key"))
            return 2
        }
        do {
            try SummaryEngine.setGroqKey(key)
        } catch {
            Terminal.err(t("cli.groq.save_failed", errorText(error)))
            return 1
        }
        Terminal.out(t("cli.groq.saved_ok"))
        return 0
    }

    // MARK: lang

    static func lang(_ args: [String]) -> Int32 {
        let t = L10n.shared
        guard args.isEmpty else {
            guard args.count == 1, let language = Language(rawValue: args[0]) else {
                Terminal.err(t("cli.lang_bad", args.first ?? ""))
                return 2
            }
            L10n.shared.set(language)
            return 0
        }
        Terminal.out(t("cli.lang_current", L10n.shared.language.rawValue))
        return 0
    }

    // MARK: help

    static func help() {
        let t = L10n.shared
        Terminal.out(t("cli.usage_short"))
        Terminal.out("")
        Terminal.out(t("cli.commands"))
        for entry in commandsHelp {
            Terminal.out("  \(entry.name)")
            Terminal.out("    \(t(entry.description))")
            for usage in entry.usages {
                Terminal.out("    \(usage)")
            }
        }
    }

    private static let commandsHelp: [(name: String, usages: [String], description: String)] = [
        ("accounts", ["ebb accounts"], "cli.cmd.accounts"),
        (
            "add",
            [
                "ebb add <gmail|icloud|custom> <username> [--no-test]",
                "ebb add custom <username> --host <server> [--port 993] [--no-test]",
            ], "cli.cmd.add"
        ),
        ("remove", ["ebb remove <account>"], "cli.cmd.remove"),
        ("mailboxes", ["ebb mailboxes <account>"], "cli.cmd.mailboxes"),
        ("inbox", ["ebb inbox [<account>] [--limit 20]"], "cli.cmd.inbox"),
        ("scan", ["ebb scan [<account>] [--all]"], "cli.cmd.scan"),
        ("run", ["ebb run [<account>]"], "cli.cmd.run"),
        ("summary", ["ebb summary [<account>]"], "cli.cmd.summary"),
        ("purge", ["ebb purge <account> [--yes-delete-everything]"], "cli.cmd.purge"),
        (
            "set",
            [
                "ebb set <account> [--max-age 30m|12h|1d|3d|14d|30d]",
                "         [--disposable-age 15m|1h|3h|12h] [--codes on|off] [--bulk on|off]",
                "         [--keep-flagged on|off] [--keep-important on|off]",
                "         [--permanent on|off] [--enabled on|off]",
                "         [--exclude <mailbox>]... [--include <mailbox>]...",
            ], "cli.cmd.set"
        ),
        ("groq-key", ["ebb groq-key [--status|--remove]"], "cli.cmd.groq_key"),
        ("lang", ["ebb lang [pt|en|system]"], "cli.cmd.lang"),
        ("version", ["ebb version"], "cli.cmd.version"),
        ("help", ["ebb help"], "cli.cmd.help"),
    ]

    // MARK: Parsing

    private struct ParsedArgs {
        var positionals: [String] = []
        var values: [String: [String]] = [:]
        var present: Set<String> = []
    }

    private enum ArgError: Error, Equatable {
        case unknownFlag(String)
        case missingValue(String)
    }

    /// Splits a command's arguments into positionals and options. `value` lists
    /// options that take a value (repeatable), `bool` options that are
    /// presence-only. Values are read as the next argument or inline with `=`.
    private static func parse(
        _ args: [String], value: Set<String>, bool: Set<String>
    ) -> Result<ParsedArgs, ArgError> {
        var parsed = ParsedArgs()
        var index = 0
        var positionalOnly = false
        while index < args.count {
            let arg = args[index]
            if positionalOnly {
                parsed.positionals.append(arg)
                index += 1
            } else if arg == "--" {
                positionalOnly = true
                index += 1
            } else if arg.hasPrefix("--") {
                let rest = arg.dropFirst(2)
                let name: String
                var inline: String?
                if let equals = rest.firstIndex(of: "=") {
                    name = String(rest[..<equals])
                    inline = String(rest[rest.index(after: equals)...])
                } else {
                    name = String(rest)
                }
                if bool.contains(name) {
                    guard inline == nil else { return .failure(ArgError.unknownFlag(name)) }
                    parsed.present.insert(name)
                    index += 1
                } else if value.contains(name) {
                    if let inline {
                        parsed.values[name, default: []].append(inline)
                        index += 1
                    } else {
                        guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                            return .failure(ArgError.missingValue(name))
                        }
                        index += 2
                        parsed.values[name, default: []].append(args[index - 1])
                    }
                } else {
                    return .failure(ArgError.unknownFlag(name))
                }
            } else {
                parsed.positionals.append(arg)
                index += 1
            }
        }
        return .success(parsed)
    }

    // MARK: Errors

    /// Prints a localized LocalizedError / localizedDescription to stderr.
    private static func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Prints a short usage hint for a usage error (exit 2).
    private static func usageHint(_ synopsis: String) -> Int32 {
        Terminal.err(L10n.shared("cli.usage_short"))
        Terminal.err("  " + synopsis)
        return 2
    }

    /// Prints the offending option plus the usage hint (exit 2).
    private static func flagError(_ error: ArgError) -> Int32 {
        let t = L10n.shared
        switch error {
        case .unknownFlag(let name):
            Terminal.err(t("cli.bad_flag", "--" + name))
        case .missingValue(let name):
            Terminal.err(t("cli.missing_argument", "--" + name))
        }
        Terminal.err(t("cli.usage_short"))
        return 2
    }
}
