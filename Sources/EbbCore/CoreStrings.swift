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
        "error.trash_not_found": Localized(
            "O servidor não mostra a Lixeira. No Gmail: Configurações > Marcadores, marque \"Mostrar no IMAP\" na Lixeira.",
            "The server does not expose Trash. In Gmail: Settings > Labels, tick \"Show in IMAP\" for Trash."),

        "error.summary_unavailable": Localized(
            "Resumo indisponível: ligue o Apple Intelligence nos Ajustes do Mac ou salve uma chave da Groq.",
            "Summary unavailable: turn on Apple Intelligence in System Settings or save a Groq key."),
        "error.summary_failed": Localized("O resumo falhou: %@", "The summary failed: %@"),

        "warning.triage_unavailable": Localized(
            "Triagem por IA ligada, mas sem Apple Intelligence nem chave da Groq: só as regras de cabeçalho valeram.",
            "AI triage is on, but there is no Apple Intelligence and no Groq key: only the header rules applied."),
        "warning.triage_failed": Localized(
            "A triagem por IA falhou e os e-mails em dúvida foram mantidos: %@",
            "AI triage failed and undecided messages were kept: %@"),

        "summary.on_device": Localized("Apple Intelligence neste Mac", "Apple Intelligence on this Mac"),
        "summary.reason.not_enabled": Localized(
            "O Apple Intelligence está desligado nos Ajustes do Mac.",
            "Apple Intelligence is turned off in System Settings."),
        "summary.reason.not_eligible": Localized(
            "Este Mac não suporta Apple Intelligence.", "This Mac does not support Apple Intelligence."),
        "summary.reason.not_ready": Localized(
            "O modelo do Apple Intelligence ainda está baixando.", "The Apple Intelligence model is still downloading."),
        "summary.reason.old_macos": Localized(
            "O resumo no próprio Mac precisa do macOS 26 com Apple Intelligence.",
            "On-device summaries need macOS 26 with Apple Intelligence."),

        "kind.codes": Localized("Códigos de verificação e login", "Verification and login codes"),
        "kind.bulk": Localized(
            "Newsletters, promoções e notificações em massa", "Newsletters, promotions and mass notifications"),

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
