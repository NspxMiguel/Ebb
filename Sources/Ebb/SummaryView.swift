import AppKit
import EbbCore
import SwiftUI

struct SummaryView: View {
    let accountID: UUID?

    @EnvironmentObject private var store: AccountStore
    @ObservedObject private var l10n = L10n.shared

    @State private var refreshID = 0
    @State private var working = false
    @State private var unavailable = false
    @State private var engineName: String?
    @State private var usedGroq = false
    @State private var rows: [AccountSummaryRow] = []

    var body: some View {
        NavigationStack {
            Group {
                if working {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if unavailable {
                    unavailablePane
                } else {
                    resultsPane
                }
            }
            .navigationTitle(l10n("app.summary"))
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(l10n("app.summary.copy")) { copy() }
                        .disabled(working || copyText.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(l10n("app.summary.refresh")) { refreshID += 1 }
                        .disabled(working)
                }
            }
        }
        .task(id: refreshID) { await load() }
    }

    private var unavailablePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EbbError.summaryUnavailable.localizedDescription)
                .foregroundStyle(.secondary)
            Button(l10n("app.summary.open_general")) {
                AppDelegate.shared?.showMainWindow(selecting: .general)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private var resultsPane: some View {
        Form {
            ForEach(rows) { row in
                Section(row.username) {
                    if let error = row.error {
                        Text(error)
                            .foregroundStyle(.red)
                    } else if let summary = row.summary {
                        ScrollView {
                            Text(markdownText(summary))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 280)
                    }
                }
            }

            if engineName != nil || usedGroq {
                Section {
                    if let engineName {
                        Text(l10n("app.summary.by", engineName))
                            .foregroundStyle(.secondary)
                    }
                    if usedGroq {
                        Text(l10n("app.summary.groq_privacy"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var targets: [Account] {
        if let accountID {
            if let account = store.account(id: accountID) { return [account] }
            return []
        }
        return store.accounts.filter(\.isEnabled)
    }

    private var copyText: String {
        var parts: [String] = []
        for row in rows {
            parts.append(row.username)
            if let error = row.error {
                parts.append(error)
            } else if let summary = row.summary {
                parts.append(summary)
            }
            parts.append("")
        }
        if let engineName {
            parts.append(L10n.shared("app.summary.by", engineName))
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownText(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: raw, options: options) {
            return parsed
        }
        return AttributedString(raw)
    }

    private func copy() {
        let text = copyText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func load() async {
        working = true
        unavailable = false
        engineName = nil
        usedGroq = false
        rows = []
        defer { working = false }

        guard let summarizer = SummaryEngine.preferred() else {
            unavailable = true
            return
        }
        engineName = summarizer.displayName
        usedGroq = summarizer is GroqSummarizer

        var collected: [AccountSummaryRow] = []
        for account in targets {
            if Task.isCancelled { return }
            guard let password = CredentialStore.password(for: account.id) else {
                collected.append(
                    AccountSummaryRow(
                        id: account.id, username: account.username,
                        error: L10n.shared("error.missing_password")))
                continue
            }
            do {
                let messages = try await Cleaner(account: account, password: password).recentMessages(limit: 50)
                let text = try await summarizer.summarize(
                    messages, account: account.username, language: L10n.shared.resolved)
                collected.append(
                    AccountSummaryRow(id: account.id, username: account.username, summary: text))
            } catch {
                collected.append(
                    AccountSummaryRow(
                        id: account.id, username: account.username,
                        error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
        }
        if Task.isCancelled { return }
        rows = collected
    }
}

private struct AccountSummaryRow: Identifiable {
    var id: UUID
    var username: String
    var summary: String?
    var error: String?
}
