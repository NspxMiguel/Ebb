import Combine
import Foundation

/// The list of accounts, persisted as JSON in Application Support so the app
/// and the CLI read the same file. Passwords are not in it (see CredentialStore).
@MainActor
public final class AccountStore: ObservableObject {
    @Published public private(set) var accounts: [Account] = []

    public let fileURL: URL

    /// EBB_ACCOUNTS_FILE points both the app and the CLI at another accounts
    /// file — for trying things out without touching the real one.
    public nonisolated static var defaultFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["EBB_ACCOUNTS_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ebb", isDirectory: true).appendingPathComponent("accounts.json")
    }

    public init(fileURL: URL = AccountStore.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    /// Re-reads the file; the other process (app or CLI) may have changed it.
    public func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            accounts = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        accounts = (try? decoder.decode([Account].self, from: data)) ?? []
    }

    public func account(id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    /// Matches by id, by an unambiguous id prefix of at least 8 characters (the
    /// short id `ebb accounts` prints) or, case-insensitively, by username.
    public func account(matching query: String) -> Account? {
        if let id = UUID(uuidString: query), let found = account(id: id) { return found }
        if let found = accounts.first(where: { $0.username.caseInsensitiveCompare(query) == .orderedSame }) {
            return found
        }
        guard query.count >= 8 else { return nil }
        let prefixed = accounts.filter { $0.id.uuidString.lowercased().hasPrefix(query.lowercased()) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    public func add(_ account: Account) throws {
        accounts.append(account)
        try save()
    }

    public func update(_ account: Account) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw EbbError.accountNotFound(account.username)
        }
        accounts[index] = account
        try save()
    }

    /// Removes the account and its keychain password.
    public func remove(id: UUID) throws {
        accounts.removeAll { $0.id == id }
        CredentialStore.removePassword(for: id)
        try save()
    }

    public func recordRun(_ summary: RunSummary, for id: UUID) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].lastRun = summary
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(accounts)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
