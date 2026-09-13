import EbbCore
import SwiftUI

struct AccountDetailView: View {
    let accountID: UUID

    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var scheduler: Scheduler
    @ObservedObject private var l10n = L10n.shared

    @State private var mailboxes: [MailboxInfo]?
    @State private var foldersError: String?
    @State private var loadingFolders = false
    @State private var confirmRemove = false

    @State private var plannedCount: Int?
    @State private var planError: String?
    @State private var planning = false
    @State private var confirmName = ""
    @State private var deletingAll = false
    @State private var progressDone = 0
    @State private var progressTotal = 0
    @State private var progressIndeterminate = false
    @State private var dangerResult: RunSummary?
    @State private var dangerBusy = false

    private var account: Account? { store.account(id: accountID) }

    var body: some View {
        Group {
            if let account {
                form(account)
            } else {
                Text(l10n("app.select_account"))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: accountID) { _, _ in
            mailboxes = nil
            foldersError = nil
            resetDanger()
        }
    }

    @ViewBuilder
    private func form(_ account: Account) -> some View {
        Form {
            Section {
                Button {
                    AppDelegate.shared?.showSummaryWindow(accountID: account.id)
                } label: {
                    Label(l10n("app.summary.action"), systemImage: "text.badge.star")
                }

                Toggle(
                    l10n("app.enabled"),
                    isOn: Binding(
                        get: { account.isEnabled },
                        set: { value in mutate { $0.isEnabled = value } }
                    )
                )

                Picker(
                    l10n("app.disposable_age"),
                    selection: Binding(
                        get: { DisposableAgeOption.matching(account.rule.disposableAge).rawValue },
                        set: { value in mutate { $0.rule.disposableAge = value } }
                    )
                ) {
                    ForEach(DisposableAgeOption.allCases) { option in
                        Text(l10n(option.key)).tag(option.rawValue)
                    }
                }
                Text(l10n("app.disposable_what"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(DisposableKind.allCases) { kind in
                    Toggle(
                        l10n("kind.\(kind.rawValue)"),
                        isOn: Binding(
                            get: { account.rule.disposableKinds.contains(kind) },
                            set: { on in
                                mutate { current in
                                    if on {
                                        current.rule.disposableKinds.insert(kind)
                                    } else {
                                        current.rule.disposableKinds.remove(kind)
                                    }
                                }
                            }
                        )
                    )
                }

                if !account.rule.usesDisposableTier {
                    Text(l10n("app.disposable_tier_off"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    l10n("app.max_age"),
                    selection: Binding(
                        get: { MaxAgeOption.matching(account.rule.maxAge).rawValue },
                        set: { value in mutate { $0.rule.maxAge = value } }
                    )
                ) {
                    ForEach(MaxAgeOption.allCases) { option in
                        Text(l10n(option.key)).tag(option.rawValue)
                    }
                }

                Toggle(
                    l10n("app.keep_flagged"),
                    isOn: Binding(
                        get: { account.rule.keepFlagged },
                        set: { value in mutate { $0.rule.keepFlagged = value } }
                    )
                )

                if account.provider == .gmail {
                    Toggle(
                        l10n("app.keep_important"),
                        isOn: Binding(
                            get: { account.rule.keepImportant },
                            set: { value in mutate { $0.rule.keepImportant = value } }
                        )
                    )
                }

                Toggle(
                    l10n("app.ai_triage"),
                    isOn: Binding(
                        get: { account.rule.aiTriage },
                        set: { value in mutate { $0.rule.aiTriage = value } }
                    )
                )
                Text(aiTriageCaption(account))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    l10n("app.permanent"),
                    isOn: Binding(
                        get: { account.rule.permanent },
                        set: { value in mutate { $0.rule.permanent = value } }
                    )
                )
                Text(account.rule.permanent ? l10n("app.permanent.on") : l10n("app.permanent.off"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            foldersSection(account)
            lastRunSection(account)

            Section {
                Button(l10n("app.remove_account"), role: .destructive) {
                    confirmRemove = true
                }
            }

            dangerSection(account)
        }
        .formStyle(.grouped)
        .navigationTitle(account.username)
        .confirmationDialog(l10n("app.remove_confirm"), isPresented: $confirmRemove) {
            Button(l10n("app.remove_account"), role: .destructive) {
                try? store.remove(id: account.id)
            }
            Button(l10n("app.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func foldersSection(_ account: Account) -> some View {
        Section(l10n("app.folders")) {
            if loadingFolders {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n("app.folders.loading"))
                        .foregroundStyle(.secondary)
                }
            } else if let mailboxes {
                ForEach(mailboxes, id: \.rawName) { box in
                    mailboxRow(box, account: account)
                }
            } else {
                Button(l10n("app.folders.load")) {
                    Task { await loadFolders(account) }
                }
                .disabled(scheduler.isRunning)
                if let foldersError {
                    Text(foldersError)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func mailboxRow(_ box: MailboxInfo, account: Account) -> some View {
        let isDrafts = box.role == .drafts
        return Toggle(
            isOn: Binding(
                get: {
                    if isDrafts { return false }
                    return !account.rule.excludedMailboxes.contains(box.rawName)
                },
                set: { included in
                    mutate { current in
                        if included {
                            current.rule.excludedMailboxes.removeAll { $0 == box.rawName }
                        } else if !current.rule.excludedMailboxes.contains(box.rawName) {
                            current.rule.excludedMailboxes.append(box.rawName)
                        }
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(box.displayName)
                if isDrafts {
                    Text(l10n("app.folders.drafts_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isDrafts || !box.selectable)
    }

    @ViewBuilder
    private func lastRunSection(_ account: Account) -> some View {
        Section(l10n("app.last_run_details")) {
            if let run = account.lastRun {
                LabeledContent(l10n("app.last_run.when")) {
                    Text(RelativeTime.absolute(from: run.date, language: l10n.resolved))
                }
                LabeledContent(l10n("app.last_run.deleted")) {
                    Text("\(run.deleted)")
                }
                LabeledContent(l10n("app.last_run.pending")) {
                    Text("\(run.pending)")
                }
                LabeledContent(l10n("app.last_run.mailboxes")) {
                    Text("\(run.mailboxesTouched)")
                }
                if let error = run.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                if let warning = run.warning {
                    Text(warning)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(l10n("app.never_ran"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func dangerSection(_ account: Account) -> some View {
        Section(l10n("app.danger")) {
            if plannedCount == nil {
                Button(l10n("app.danger.delete_now"), role: .destructive) {
                    Task { await planEverything(account) }
                }
                .disabled(planning || scheduler.isRunning)
                if planning {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if let count = plannedCount {
                Text(l10n("app.danger.plan_result", count))
                Text(l10n("app.danger.confirm_prompt", account.username))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField(l10n("app.danger.type_username"), text: $confirmName)
                Button(l10n("app.danger.delete_now"), role: .destructive) {
                    Task { await deleteEverything(account) }
                }
                .disabled(confirmName != account.username || deletingAll || scheduler.isRunning)

                if deletingAll {
                    if progressIndeterminate || progressTotal == 0 {
                        ProgressView()
                    } else {
                        ProgressView(value: Double(progressDone), total: Double(progressTotal))
                    }
                }
            }

            if let planError {
                Text(planError)
                    .foregroundStyle(.red)
            }
            if dangerBusy {
                Text(l10n("app.danger.busy"))
                    .foregroundStyle(.secondary)
            }
            if let dangerResult {
                if let error = dangerResult.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                } else {
                    Text(l10n("app.danger.result", dangerResult.deleted))
                }
            }
        }
    }

    private func mutate(_ body: (inout Account) -> Void) {
        guard var current = store.account(id: accountID) else { return }
        body(&current)
        try? store.update(current)
    }

    private func loadFolders(_ account: Account) async {
        loadingFolders = true
        foldersError = nil
        defer { loadingFolders = false }
        guard let password = CredentialStore.password(for: account.id) else {
            foldersError = L10n.shared("error.missing_password")
            return
        }
        do {
            mailboxes = try await Cleaner(account: account, password: password).mailboxes()
        } catch {
            foldersError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func planEverything(_ account: Account) async {
        planning = true
        planError = nil
        dangerResult = nil
        dangerBusy = false
        defer { planning = false }
        guard let password = CredentialStore.password(for: account.id) else {
            planError = L10n.shared("error.missing_password")
            return
        }
        do {
            let plan = try await Cleaner(account: account, password: password).plan(mode: .everything)
            plannedCount = plan.totalMessages
            confirmName = ""
        } catch {
            planError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteEverything(_ account: Account) async {
        planError = nil
        dangerResult = nil
        dangerBusy = false
        guard let password = CredentialStore.password(for: account.id) else {
            planError = L10n.shared("error.missing_password")
            return
        }
        deletingAll = true
        progressDone = 0
        progressTotal = 0
        progressIndeterminate = true
        defer { deletingAll = false }

        do {
            let result = try await scheduler.runExclusive {
                let cleaner = Cleaner(account: account, password: password)
                return try await cleaner.run(mode: .everything, dryRun: false) { event in
                    Task { @MainActor in
                        switch event {
                        case .connecting, .scanning:
                            progressIndeterminate = true
                        case .deleting(_, let done, let total):
                            progressIndeterminate = false
                            progressDone = done
                            progressTotal = total
                        case .finished:
                            break
                        }
                    }
                }
            }
            if let result {
                try? store.recordRun(result, for: account.id)
                dangerResult = result
            } else {
                dangerBusy = true
            }
        } catch {
            let failed = RunSummary(
                mode: .everything,
                dryRun: false,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            try? store.recordRun(failed, for: account.id)
            dangerResult = failed
        }
    }

    private func resetDanger() {
        plannedCount = nil
        planError = nil
        confirmName = ""
        dangerResult = nil
        dangerBusy = false
        deletingAll = false
    }

    /// Says where the triage would run, so turning it on is an informed choice.
    private func aiTriageCaption(_ account: Account) -> String {
        guard let engine = SummaryEngine.preferred() else { return l10n("app.ai_triage.none") }
        return engine.sendsMailOffDevice ? l10n("app.ai_triage.groq") : l10n("app.ai_triage.on_device")
    }
}
