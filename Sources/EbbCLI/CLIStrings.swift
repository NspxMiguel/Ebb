import EbbCore
import Foundation

/// Strings owned by the CLI. Registered into L10n by main.swift as its first
/// statement; the core table (errors, roles, providers) is already loaded.
enum CLIStrings {
    static let table: [String: Localized] = [
        // General usage.
        "cli.usage_short": Localized(
            "uso: ebb <comando> [opções]", "usage: ebb <command> [options]"),
        "cli.commands": Localized("comandos:", "commands:"),
        "cli.unknown_command": Localized(
            "comando desconhecido: %@", "unknown command: %@"),
        "cli.bad_flag": Localized(
            "opção desconhecida: %@", "unknown option: %@"),
        "cli.missing_argument": Localized(
            "argumento faltando: %@", "missing argument: %@"),

        // Command descriptions for `ebb help`.
        "cli.cmd.accounts": Localized("Lista as contas", "List accounts"),
        "cli.cmd.add": Localized("Adiciona uma conta", "Add an account"),
        "cli.cmd.remove": Localized("Remove uma conta", "Remove an account"),
        "cli.cmd.mailboxes": Localized(
            "Lista as pastas de uma conta", "List an account's mailboxes"),
        "cli.cmd.scan": Localized(
            "Mostra o que a limpeza vai apagar", "Preview what a cleanup would delete"),
        "cli.cmd.inbox": Localized(
            "Lista as mensagens recentes da Entrada (só leitura)", "List recent Inbox messages (read-only)"),
        "cli.cmd.run": Localized("Roda a limpeza automática", "Run the automatic cleanup"),
        "cli.cmd.summary": Localized(
            "Resume as mensagens recentes de cada conta", "Summarize recent messages per account"),
        "cli.cmd.purge": Localized(
            "Apaga tudo de uma conta", "Delete everything from an account"),
        "cli.cmd.set": Localized("Edita a regra de uma conta", "Edit an account's rule"),
        "cli.cmd.lang": Localized("Mostra ou define o idioma", "Show or set the language"),
        "cli.cmd.groq_key": Localized(
            "Salva ou remove a chave da API da Groq", "Save or remove the Groq API key"),
        "cli.cmd.version": Localized("Mostra a versão", "Print the version"),
        "cli.cmd.help": Localized("Mostra esta ajuda", "Show this help"),

        // Shared values.
        "cli.on": Localized("sim", "on"),
        "cli.off": Localized("não", "off"),
        "cli.never": Localized("nunca", "never"),

        // Accounts table.
        "cli.col.id": Localized("id", "id"),
        "cli.col.provider": Localized("provedor", "provider"),
        "cli.col.username": Localized("usuário", "username"),
        "cli.col.enabled": Localized("ativo", "enabled"),
        "cli.col.max_age": Localized("idade máx.", "max age"),
        "cli.col.disposable": Localized("descartável", "disposable"),
        "cli.col.keep_flagged": Localized("marcadas", "keep flagged"),
        "cli.col.keep_important": Localized("importantes", "keep important"),
        "cli.col.permanent": Localized("permanente", "permanent"),
        "cli.col.last_run": Localized("última execução", "last run"),
        "cli.no_accounts": Localized(
            "Nenhuma conta. Adicione uma com 'ebb add'.",
            "No accounts. Add one with 'ebb add'."),
        "cli.last_run_ok": Localized(
            "%d apagadas, %d pendentes, %@", "%d deleted, %d pending, %@"),
        "cli.last_run_error": Localized("erro, %@", "error, %@"),
        "cli.rel.just_now": Localized("agora", "just now"),
        "cli.rel.ago": Localized("há %@", "%@ ago"),

        // add.
        "cli.add_prompt": Localized("Senha de app para %@: ", "App password for %@: "),
        "cli.add_no_password": Localized(
            "Nenhuma senha foi recebida.", "No password received."),
        "cli.add_bad_provider": Localized(
            "provedor desconhecido: %@", "unknown provider: %@"),
        "cli.add_custom_host": Localized(
            "conta 'custom' exige --host <servidor>", "custom accounts require --host <server>"),
        "cli.bad_port": Localized("porta inválida: %@", "invalid port: %@"),
        "cli.add_ok": Localized("Conta adicionada.", "Account added."),

        // remove.
        "cli.remove_ok": Localized("Conta removida.", "Account removed."),

        // mailboxes.
        "cli.col.mailbox": Localized("pasta", "mailbox"),
        "cli.col.display": Localized("nome", "name"),
        "cli.col.role": Localized("função", "role"),
        "cli.col.notes": Localized("notas", "notes"),
        "cli.mailboxes.skipped_drafts": Localized(
            "pulada (rascunhos)", "skipped (drafts)"),
        "cli.mailboxes.skipped_excluded": Localized(
            "pulada (excluída)", "skipped (excluded)"),

        // inbox.
        "cli.inbox.col.age": Localized("idade", "age"),
        "cli.inbox.col.kind": Localized("tipo", "kind"),
        "cli.inbox.col.flags": Localized("marcas", "flags"),
        "cli.inbox.col.from": Localized("de", "from"),
        "cli.inbox.col.subject": Localized("assunto", "subject"),
        "cli.inbox.limit_bad": Localized(
            "limite inválido: %@ (use um número > 0)", "invalid limit: %@ (use a number > 0)"),

        // scan.
        "cli.scan_account": Localized("%@:", "%@:"),
        "cli.scan_total": Localized("total: %d (%@)", "total: %d (%@)"),
        "cli.account_error": Localized("%@: %@", "%@: %@"),
        "cli.mode.expired": Localized("vencidas", "expired"),
        "cli.mode.everything": Localized("tudo", "everything"),

        // run.
        "cli.run_none": Localized("Nenhuma conta ativa.", "No enabled accounts."),
        "cli.run_summary": Localized(
            "%@: %d apagadas, %d pendentes, %@", "%@: %d deleted, %d pending, %@"),

        // summary.
        "cli.summary.header": Localized("%@:", "%@:"),
        "cli.summary.footer": Localized("— %@", "— %@"),
        "cli.summary.progress": Localized("%@: resumindo…", "%@: summarizing…"),
        "cli.summary.privacy": Localized(
            "Privacidade: remetente, assunto e as primeiras linhas de cada e-mail vão para a Groq.",
            "Privacy: the sender, subject and first lines of each email are sent to Groq."),

        // purge.
        "cli.purge_warn": Localized(
            "Isto vai apagar %d mensagens de %@, permanentemente.",
            "This will permanently delete %d messages from %@."),
        "cli.purge_confirm": Localized(
            "Para confirmar, rode: ebb purge %@ --yes-delete-everything",
            "To confirm, run: ebb purge %@ --yes-delete-everything"),
        "cli.purge_ok": Localized(
            "%@: %d apagadas, %d pendentes.",
            "%@: %d deleted, %d pending."),
        "cli.progress.connecting": Localized("Conectando…", "Connecting…"),
        "cli.progress.scanning": Localized("Vasculhando %@…", "Scanning %@…"),
        "cli.progress.deleting": Localized("Apagando %@… (%d/%d)", "Deleting %@… (%d/%d)"),

        // groq-key.
        "cli.groq.prompt": Localized("Chave da API da Groq: ", "Groq API key: "),
        "cli.groq.saved_ok": Localized("Chave da Groq salva.", "Groq key saved."),
        "cli.groq.removed": Localized("Chave da Groq removida.", "Groq key removed."),
        "cli.groq.no_key": Localized("Nenhuma chave recebida.", "No key received."),
        "cli.groq.save_failed": Localized(
            "Não deu para salvar a chave: %@", "Could not save the key: %@"),
        "cli.groq.status": Localized("chave da Groq: %@", "Groq key: %@"),
        "cli.groq.value_saved": Localized("salva", "saved"),
        "cli.groq.value_none": Localized("nenhuma", "none"),
        "cli.groq.ondevice_available": Localized(
            "modelo local: disponível", "on-device model: available"),
        "cli.groq.ondevice_unavailable": Localized(
            "modelo local: %@", "on-device model: %@"),

        // set.
        "cli.set.max_age": Localized("idade máx.: %@", "max age: %@"),
        "cli.set.disposable_age": Localized("idade descartável: %@", "disposable age: %@"),
        "cli.set.kinds": Localized("tipos descartáveis: %@", "disposable kinds: %@"),
        "cli.set.keep_flagged": Localized("manter marcadas: %@", "keep flagged: %@"),
        "cli.set.keep_important": Localized("manter importantes: %@", "keep important: %@"),
        "cli.set.permanent": Localized("permanente: %@", "permanent: %@"),
        "cli.set.enabled": Localized("ativo: %@", "enabled: %@"),
        "cli.set.excluded": Localized("excluídas: %@", "excluded: %@"),
        "cli.set.excluded_none": Localized("nenhuma", "none"),
        "cli.set.bad_age": Localized(
            "idade inválida: %@ (use 15m, 12h, 3d ou 30d)",
            "invalid age: %@ (use 15m, 12h, 3d or 30d)"),
        "cli.set.bad_on_off": Localized(
            "%@ deve ser 'on' ou 'off'.", "%@ must be 'on' or 'off'."),

        // lang.
        "cli.lang_current": Localized("idioma: %@", "language: %@"),
        "cli.lang_bad": Localized(
            "idioma inválido: %@ (use pt, en ou system)",
            "invalid language: %@ (use pt, en or system)"),
        "cli.set.ai": Localized("triagem por IA: %@", "AI triage: %@"),
]
}
