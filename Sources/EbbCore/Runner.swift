import Foundation

public struct AccountRunResult: Sendable {
    public let accountID: UUID
    public let username: String
    public let summary: RunSummary
}

/// Runs cleanups for the accounts in a store and records each outcome in it.
/// Shared by the menu bar app (timer) and the CLI (`ebb run`).
@MainActor
public enum Runner {
    /// - Parameters:
    ///   - only: restrict to one account; nil means every enabled account.
    ///   - passwordLookup: injectable for tests; defaults to the keychain.
    public static func run(
        store: AccountStore,
        mode: CleanupMode,
        dryRun: Bool,
        only: UUID? = nil,
        now: Date = Date(),
        passwordLookup: (UUID) -> String? = CredentialStore.password(for:),
        progress: (@Sendable (UUID, CleanerEvent) -> Void)? = nil
    ) async -> [AccountRunResult] {
        let targets = store.accounts.filter { account in
            if let only { return account.id == only }
            return account.isEnabled
        }
        var results: [AccountRunResult] = []
        for account in targets {
            var summary: RunSummary
            if let password = passwordLookup(account.id) {
                let cleaner = Cleaner(account: account, password: password)
                let id = account.id
                do {
                    summary = try await cleaner.run(
                        mode: mode, dryRun: dryRun, now: now,
                        progress: progress.map { callback in { event in callback(id, event) } })
                } catch {
                    summary = RunSummary(
                        date: now, mode: mode, dryRun: dryRun,
                        errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            } else {
                summary = RunSummary(
                    date: now, mode: mode, dryRun: dryRun,
                    errorMessage: EbbError.missingPassword.errorDescription)
            }
            // A dry run is a preview; it must not overwrite the real last result.
            if !dryRun {
                try? store.recordRun(summary, for: account.id)
            }
            results.append(AccountRunResult(accountID: account.id, username: account.username, summary: summary))
        }
        return results
    }
}
