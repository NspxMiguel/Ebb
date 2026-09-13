import Foundation

public enum EbbError: Error, Equatable, LocalizedError, Sendable {
    /// TCP/TLS could not be established.
    case connectionFailed(String)
    /// The server rejected the username or app password.
    case authenticationFailed(String)
    /// Refused to send a password over plain IMAP to a non-loopback host.
    case insecureConnection
    /// The server answered NO/BAD to a command Ebb needs.
    case serverRefused(command: String, message: String)
    /// The server sent something Ebb could not parse.
    case protocolError(String)
    case timeout
    case missingPassword
    case accountNotFound(String)

    public var errorDescription: String? {
        let t = L10n.shared
        switch self {
        case .connectionFailed(let detail): return t("error.connection", detail)
        case .authenticationFailed(let detail): return t("error.auth", detail)
        case .insecureConnection: return t("error.insecure")
        case .serverRefused(let command, let message): return t("error.refused", command, message)
        case .protocolError(let detail): return t("error.protocol", detail)
        case .timeout: return t("error.timeout")
        case .missingPassword: return t("error.missing_password")
        case .accountNotFound(let name): return t("error.account_not_found", name)
        }
    }
}
