import EbbCore
import Foundation

/// User-facing strings owned by the menu bar app. Brazilian Portuguese first,
/// English second.
enum AppStrings {
    static let table: [String: Localized] = [
        "app.name": Localized("Ebb", "Ebb"),

        "app.never_ran": Localized("ainda não rodou", "never ran"),
        "app.last_run": Localized("%d apagados · %@", "%d deleted · %@"),
        "app.pending_short": Localized("%d pendentes", "%d pending"),

        "app.clean_now": Localized("Limpar agora", "Clean now"),
        "app.preview": Localized("Simular", "Preview"),
        "app.preview_result": Localized("%d seriam apagados", "%d would be deleted"),
        "app.open_ebb": Localized("Abrir o Ebb…", "Open Ebb…"),
        "app.quit": Localized("Sair", "Quit"),
        "app.no_accounts": Localized(
            "Nenhuma conta. Abra o Ebb para adicionar uma.", "No accounts. Open Ebb to add one."),

        "app.accounts": Localized("Contas", "Accounts"),
        "app.general": Localized("Geral", "General"),
        "app.add_account": Localized("Adicionar conta", "Add account"),
        "app.select_account": Localized("Selecione uma conta.", "Select an account."),
        "app.cancel": Localized("Cancelar", "Cancel"),
        "app.save": Localized("Salvar", "Save"),

        "app.provider": Localized("Provedor", "Provider"),
        "app.username": Localized("Usuário", "Username"),
        "app.username.hint.gmail": Localized("Endereço do Gmail", "Gmail address"),
        "app.username.hint.icloud": Localized("Apple ID", "Apple ID"),
        "app.username.hint.custom": Localized("Usuário do IMAP", "IMAP username"),
        "app.password": Localized("Senha de app", "App password"),
        "app.password.link": Localized("Criar senha de app", "Create app password"),
        "app.password.howto.gmail": Localized(
            "Precisa da verificação em duas etapas ligada.", "Needs 2-Step Verification."),
        "app.password.howto.icloud": Localized(
            "Iniciar Sessão e Segurança > Senhas de Apps.",
            "Sign-In and Security > App-Specific Passwords."),
        "app.password.howto.custom": Localized(
            "Use uma senha de app se o servidor exigir.",
            "Use an app password if the server requires one."),
        "app.host": Localized("Servidor", "Host"),
        "app.port": Localized("Porta", "Port"),
        "app.test_login": Localized("Testar login", "Test login"),
        "app.test_login.ok": Localized("Login funcionou.", "Login succeeded."),

        "app.enabled": Localized("Ativa", "Enabled"),
        "app.delete_older_than": Localized("Apagar mensagens com mais de", "Delete messages older than"),
        "app.disposable_age": Localized("E-mails descartáveis são apagados após", "Disposable mail goes after"),
        "app.disposable_what": Localized(
            "Descartável é o que se encaixa nos tipos ligados abaixo.",
            "Disposable mail is whichever kinds are on below."),
        "app.disposable_tier_off": Localized(
            "O prazo curto está desligado; vale só o prazo do resto.",
            "The short tier is off; only the longer age applies."),
        "app.max_age": Localized("O resto é apagado após", "Everything else goes after"),
        "app.age.15m": Localized("15 minutos", "15 minutes"),
        "app.age.30m": Localized("30 minutos", "30 minutes"),
        "app.age.1h": Localized("1 hora", "1 hour"),
        "app.age.3h": Localized("3 horas", "3 hours"),
        "app.age.12h": Localized("12 horas", "12 hours"),
        "app.age.1d": Localized("1 dia", "1 day"),
        "app.age.3d": Localized("3 dias", "3 days"),
        "app.age.7d": Localized("7 dias", "7 days"),
        "app.age.14d": Localized("14 dias", "14 days"),
        "app.age.30d": Localized("30 dias", "30 days"),
        "app.keep_flagged": Localized("Nunca apagar com estrela ou bandeira", "Keep starred or flagged"),
        "app.keep_important": Localized(
            "Nunca apagar o que o Gmail marca como Importante",
            "Never delete what Gmail marks as Important"),
        "app.permanent": Localized("Apagar de vez", "Permanent delete"),
        "app.permanent.on": Localized(
            "Some de vez; a Lixeira também é esvaziada.",
            "Gone for good; Trash is emptied."),
        "app.permanent.off": Localized(
            "Só vai para a Lixeira.",
            "Only moved to Trash."),

        "app.folders": Localized("Pastas", "Folders"),
        "app.folders.load": Localized("Carregar pastas", "Load folders"),
        "app.folders.loading": Localized("Carregando…", "Loading…"),
        "app.folders.include": Localized("Incluir na limpeza", "Include in cleanup"),
        "app.folders.drafts_note": Localized("sempre mantidos", "always kept"),

        "app.last_run_details": Localized("Última limpeza", "Last run"),
        "app.last_run.deleted": Localized("Apagados", "Deleted"),
        "app.last_run.pending": Localized("Pendentes", "Pending"),
        "app.last_run.mailboxes": Localized("Pastas mexidas", "Mailboxes touched"),
        "app.last_run.when": Localized("Quando", "When"),

        "app.remove_account": Localized("Remover conta", "Remove account"),
        "app.remove_confirm": Localized(
            "Remover esta conta? A senha de app também sai do Chaveiro.",
            "Remove this account? The app password is deleted from the keychain."),

        "app.danger": Localized("Zona de perigo", "Danger zone"),
        "app.danger.delete_now": Localized("Apagar tudo agora", "Delete everything now"),
        "app.danger.plan_result": Localized("%d mensagens serão apagadas.", "%d messages will be deleted."),
        "app.danger.confirm_prompt": Localized(
            "Digite o usuário da conta (%@) para confirmar.",
            "Type the account username (%@) to confirm."),
        "app.danger.type_username": Localized("Usuário da conta", "Account username"),
        "app.danger.result": Localized("%d mensagens apagadas.", "%d messages deleted."),
        "app.danger.busy": Localized("Já tem uma limpeza rodando.", "A cleanup is already running."),

        "app.auto_cleanup": Localized("Limpeza automática", "Automatic cleanup"),
        "app.interval": Localized("Conferir a caixa a cada", "Check the mailbox every"),
        "app.interval.minutes": Localized("%d minutos", "%d minutes"),
        "app.interval.footnote": Localized(
            "Isto é de quanto em quanto tempo o Ebb confere. Quanto tempo cada e-mail fica é definido em cada conta.",
            "This is how often Ebb checks. How long mail stays is set on each account."),
        "app.open_at_login": Localized("Abrir ao iniciar o Mac", "Open at login"),
        "app.login.error": Localized(
            "Não deu para mudar a abertura automática: %@", "Could not change open at login: %@"),
        "app.language": Localized("Idioma", "Language"),
        "app.language.system": Localized("Sistema", "System"),
        "app.language.pt": Localized("Português", "Português"),
        "app.language.en": Localized("English", "English"),

        "app.summary": Localized("Resumo", "Summary"),
        "app.summary.action": Localized("Resumir o que importa", "Summarize what matters"),
        "app.summary.on_device": Localized(
            "Apple Intelligence neste Mac — nada sai do computador",
            "Apple Intelligence on this Mac — nothing leaves the computer"),
        "app.summary.groq_key": Localized("Chave da API da Groq", "Groq API key"),
        "app.summary.groq_saved": Localized("Tem uma chave da Groq salva.", "A Groq key is saved."),
        "app.summary.groq_missing": Localized("Nenhuma chave da Groq salva.", "No Groq key saved."),
        "app.summary.groq_remove": Localized("Remover", "Remove"),
        "app.summary.groq_link": Localized("Pegar uma chave na Groq", "Get a Groq key"),
        "app.summary.groq_privacy": Localized(
            "Com a Groq, o remetente, o assunto e as primeiras linhas de cada e-mail são enviados para ela. Quando o Apple Intelligence está ligado, o modelo do próprio Mac é usado no lugar.",
            "With Groq, the sender, subject and the first lines of each email are sent to Groq; the on-device model is used instead whenever Apple Intelligence is on."),
        "app.summary.open_general": Localized("Abrir Geral…", "Open General…"),
        "app.summary.by": Localized("por %@", "by %@"),
        "app.summary.refresh": Localized("Atualizar", "Refresh"),
        "app.summary.copy": Localized("Copiar", "Copy"),

        "app.ai_triage": Localized(
            "Deixar a IA decidir o que é descartável", "Let AI decide what is disposable"),
        "app.ai_triage.on_device": Localized(
            "Roda no Apple Intelligence deste Mac: nada sai do computador. Na dúvida, o e-mail fica até o prazo longo.",
            "Runs on this Mac's Apple Intelligence: nothing leaves the computer. When unsure, mail stays until the long age."),
        "app.ai_triage.groq": Localized(
            "Usa a Groq: remetente, assunto e o começo dos e-mails entre os dois prazos são enviados para ela. Na dúvida ou se falhar, o e-mail fica até o prazo longo.",
            "Uses Groq: sender, subject and the first lines of messages between the two ages are sent to it. When unsure or on failure, mail stays until the long age."),
        "app.ai_triage.none": Localized(
            "Precisa do Apple Intelligence ou de uma chave da Groq (em Geral). Sem isso, só valem as regras de cabeçalho.",
            "Needs Apple Intelligence or a Groq key (in General). Without either, only the header rules apply."),
    ]
}
