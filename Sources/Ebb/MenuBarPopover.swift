import AppKit
import EbbCore
import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var scheduler: Scheduler
    @ObservedObject private var l10n = L10n.shared

    @State private var previewCount: Int?
    @State private var previewError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.accounts.isEmpty {
                Text(l10n("app.no_accounts"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                    if index > 0 { Divider() }
                    accountRow(account)
                }
            }

            HStack(spacing: 8) {
                Button(l10n("app.clean_now")) {
                    previewCount = nil
                    previewError = nil
                    Task { await scheduler.run(mode: .expired, dryRun: false) }
                }
                .disabled(scheduler.isRunning || !hasEnabledAccounts)

                Button(l10n("app.preview")) {
                    Task { await preview() }
                }
                .disabled(scheduler.isRunning || !hasEnabledAccounts)

                if scheduler.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let previewCount {
                Text(l10n("app.preview_result", previewCount))
                    .foregroundStyle(.secondary)
                if let previewError {
                    Text(previewError)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .lineLimit(3)
                }
            }

            Divider()

            Button(l10n("app.open_ebb")) {
                AppDelegate.shared?.showMainWindow()
            }

            Button(l10n("app.quit")) {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        .onAppear { store.reload() }
    }

    private var hasEnabledAccounts: Bool {
        store.accounts.contains { $0.isEnabled }
    }

    private func accountRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l10n("provider.\(account.provider.rawValue)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(account.username)
                .font(.body)
            lastRunLine(account)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lastRunLine(_ account: Account) -> some View {
        if let run = account.lastRun {
            if let error = run.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(
                    l10n(
                        "app.last_run",
                        run.deleted,
                        RelativeTime.string(from: run.date, language: l10n.resolved))
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } else {
            Text(l10n("app.never_ran"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func preview() async {
        previewError = nil
        let results = await scheduler.run(mode: .expired, dryRun: true)
        previewCount = results.reduce(0) { $0 + $1.summary.deleted }
        previewError = results.compactMap(\.summary.errorMessage).first
    }
}
