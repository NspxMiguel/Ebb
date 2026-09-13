import Foundation

/// Server settings and the page where each provider issues app passwords.
///
/// App passwords instead of OAuth: Gmail only grants full mailbox scopes to apps
/// that went through Google's verification, and an unverified app's refresh
/// token dies after seven days. iCloud does not offer OAuth to third parties at
/// all. An app password is revocable, tied to this Mac, and does not expire.
public struct Provider: Sendable, Hashable {
    public let kind: ProviderKind
    public let displayName: String
    public let endpoint: ServerEndpoint
    /// Where the user creates the app password.
    public let appPasswordURL: URL?

    public static let gmail = Provider(
        kind: .gmail,
        displayName: "Gmail",
        endpoint: ServerEndpoint(host: "imap.gmail.com", port: 993, useTLS: true),
        appPasswordURL: URL(string: "https://myaccount.google.com/apppasswords")
    )

    public static let icloud = Provider(
        kind: .icloud,
        displayName: "iCloud Mail",
        endpoint: ServerEndpoint(host: "imap.mail.me.com", port: 993, useTLS: true),
        appPasswordURL: URL(string: "https://account.apple.com/account/manage")
    )

    public static let all: [Provider] = [.gmail, .icloud]

    public static func preset(_ kind: ProviderKind) -> Provider? {
        switch kind {
        case .gmail: return .gmail
        case .icloud: return .icloud
        case .custom: return nil
        }
    }
}
