import EbbCore
import Foundation

/// User-facing strings owned by the menu bar app. Portuguese first, English second.
enum AppStrings {
    static let table: [String: Localized] = [
        "app.name": Localized("Ebb", "Ebb"),

        "app.never_ran": Localized("nunca correu", "never ran"),
        "app.last_run": Localized("%d apagados · %@", "%d deleted · %@"),
        "app.pending_short": Localized("%d pendentes", "%d pending"),

        "app.clean_now": Localized("Limpar agora", "Clean now"),
        "app.preview": Localized("Prévia", "Preview"),
        "app.preview_result": Localized("%d seriam apagados", "%d would be deleted"),
        "app.open_ebb": Localized("Abrir Ebb…", "Open Ebb…"),
        "app.quit": Localized("Sair", "Quit"),
        "app.no_accounts": Localized("Nenhuma conta. Abra o Ebb para adicionar uma.", "No accounts. Open Ebb to add one."),

        "app.accounts": Localized("Contas", "Accounts"),
        "app.general": Localized("Geral", "General"),
        "app.add_account": Localized("Adicionar conta", "Add account"),
        "app.select_account": Localized("Selecione uma conta.", "Select an account."),
        "app.cancel": Localized("Cancelar", "Cancel"),
        "app.save": Localized("Guardar", "Save"),

        "app.provider": Localized("Servidor", "Provider"),
        "app.username": Localized("Utilizador", "Username"),
        "app.username.hint.gmail": Localized("Endereço Gmail", "Gmail address"),
        "app.username.hint.icloud": Localized("Apple ID", "Apple ID"),
        "app.username.hint.custom": Localized("Nome de utilizador IMAP", "IMAP username"),
        "app.password": Localized("Senha de app", "App password"),
        "app.password.link": Localized("Criar senha de app", "Create app password"),
        "app.password.howto.gmail": Localized("Precisa da verificação em duas etapas.", "Needs 2-Step Verification."),
        "app.password.howto.icloud": Localized(
            "Início de sessão e segurança > Senhas de app.",
            "Sign-In and Security > App-Specific Passwords."),
        "app.password.howto.custom": Localized(
            "Use uma senha de app se o servidor exigir.",
            "Use an app password if the server requires one."),
        "app.host": Localized("Servidor", "Host"),
        "app.port": Localized("Porta", "Port"),
        "app.test_login": Localized("Testar login", "Test login"),
        "app.test_login.ok": Localized("Login correto.", "Login succeeded."),

        "app.enabled": Localized("Ativa", "Enabled"),
        "app.delete_older_than": Localized("Apagar mensagens com mais de", "Delete messages older than"),
        "app.age.1h": Localized("1 hora", "1 hour"),
        "app.age.12h": Localized("12 horas", "12 hours"),
        "app.age.1d": Localized("1 dia", "1 day"),
        "app.age.3d": Localized("3 dias", "3 days"),
        "app.age.7d": Localized("7 dias", "7 days"),
        "app.age.30d": Localized("30 dias", "30 days"),
        "app.keep_flagged": Localized("Preservar com estrela ou bandeira", "Keep starred or flagged"),
        "app.permanent": Localized("Apagar em definitivo", "Permanent delete"),
        "app.permanent.on": Localized(
            "Apagadas de vez; a Lixeira é esvaziada.",
            "Gone for good; Trash is emptied."),
        "app.permanent.off": Localized(
            "Só são movidas para a Lixeira.",
            "Only moved to Trash."),

        "app.folders": Localized("Pastas", "Folders"),
        "app.folders.load": Localized("Carregar pastas", "Load folders"),
        "app.folders.loading": Localized("A carregar…", "Loading…"),
        "app.folders.include": Localized("Incluir na limpeza", "Include in cleanup"),
        "app.folders.drafts_note": Localized("sempre preservados", "always kept"),

        "app.last_run_details": Localized("Última execução", "Last run"),
        "app.last_run.deleted": Localized("Apagadas", "Deleted"),
        "app.last_run.pending": Localized("Pendentes", "Pending"),
        "app.last_run.mailboxes": Localized("Pastas tocadas", "Mailboxes touched"),
        "app.last_run.when": Localized("Quando", "When"),

        "app.remove_account": Localized("Remover conta", "Remove account"),
        "app.remove_confirm": Localized(
            "Remover esta conta? A senha de app sai do porta-chaves.",
            "Remove this account? The app password is deleted from the keychain."),

        "app.danger": Localized("Zona perigosa", "Danger zone"),
        "app.danger.delete_now": Localized("Apagar tudo agora", "Delete everything now"),
        "app.danger.plan_result": Localized("%d mensagens serão apagadas.", "%d messages will be deleted."),
        "app.danger.confirm_prompt": Localized(
            "Escreva o nome da conta (%@) para confirmar.",
            "Type the account username (%@) to confirm."),
        "app.danger.type_username": Localized("Nome da conta", "Account username"),
        "app.danger.result": Localized("%d mensagens apagadas.", "%d messages deleted."),
        "app.danger.busy": Localized("Já há uma limpeza a correr.", "A cleanup is already running."),

        "app.auto_cleanup": Localized("Limpeza automática", "Automatic cleanup"),
        "app.interval": Localized("Intervalo", "Interval"),
        "app.interval.minutes": Localized("%d minutos", "%d minutes"),
        "app.open_at_login": Localized("Abrir ao iniciar sessão", "Open at login"),
        "app.login.error": Localized("Não foi possível alterar o início automático: %@", "Could not change open at login: %@"),
        "app.language": Localized("Idioma", "Language"),
        "app.language.system": Localized("Sistema", "System"),
        "app.language.pt": Localized("Português", "Português"),
        "app.language.en": Localized("English", "English"),
    ]
}
