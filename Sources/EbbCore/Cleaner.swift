import Foundation

/// Deletes mail from one account. Every call opens its own IMAP session and
/// logs out at the end, so a Cleaner is cheap and safe to use from any task.
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
        throw EbbError.protocolError("not implemented")
    }

    /// Every mailbox the server lists, with its detected role.
    public func mailboxes() async throws -> [MailboxInfo] {
        throw EbbError.protocolError("not implemented")
    }

    /// What `run` would delete, without changing anything.
    public func plan(mode: CleanupMode, now: Date = Date()) async throws -> CleanupPlan {
        throw EbbError.protocolError("not implemented")
    }

    /// Deletes (or, with `dryRun`, only counts) according to the account's rule.
    /// Errors are thrown; `RunSummary.errorMessage` is filled by `Runner`, not here.
    @discardableResult
    public func run(
        mode: CleanupMode,
        dryRun: Bool,
        now: Date = Date(),
        progress: (@Sendable (CleanerEvent) -> Void)? = nil
    ) async throws -> RunSummary {
        throw EbbError.protocolError("not implemented")
    }
}
