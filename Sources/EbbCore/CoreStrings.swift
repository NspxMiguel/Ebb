import Foundation

/// Strings owned by EbbCore (errors and shared labels). The app and the CLI
/// register their own tables.
enum CoreStrings {
    static let table: [String: Localized] = [
        "error.connection": Localized(
            "Não deu para conectar ao servidor: %@", "Could not connect to the server: %@"),
        "error.auth": Localized(
            "O servidor recusou o login. Confira o e-mail e a senha de app. (%@)",
            "The server rejected the login. Check the address and the app password. (%@)"),
        "error.insecure": Localized(
            "Conexão sem TLS recusada: a senha iria em texto claro.",
            "Refused a connection without TLS: the password would travel in clear text."),
        "error.refused": Localized(
            "O servidor recusou %@: %@", "The server refused %@: %@"),
        "error.protocol": Localized(
            "Resposta inesperada do servidor: %@", "Unexpected server response: %@"),
        "error.timeout": Localized(
            "O servidor parou de responder.", "The server stopped responding."),
        "error.missing_password": Localized(
            "Sem senha de app salva para esta conta.", "No app password saved for this account."),
        "error.account_not_found": Localized(
            "Conta não encontrada: %@", "Account not found: %@"),

        "provider.gmail": Localized("Gmail", "Gmail"),
        "provider.icloud": Localized("iCloud Mail", "iCloud Mail"),
        "provider.custom": Localized("Outro servidor IMAP", "Other IMAP server"),

        "role.inbox": Localized("Entrada", "Inbox"),
        "role.all": Localized("Todos os e-mails", "All Mail"),
        "role.archive": Localized("Arquivo", "Archive"),
        "role.sent": Localized("Enviados", "Sent"),
        "role.drafts": Localized("Rascunhos", "Drafts"),
        "role.junk": Localized("Spam", "Junk"),
        "role.trash": Localized("Lixeira", "Trash"),
        "role.other": Localized("Pasta", "Folder"),
    ]
}
