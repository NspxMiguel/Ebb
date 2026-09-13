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
        "cli.cmd.run": Localized("Roda a limpeza automática", "Run the automatic cleanup"),
        "cli.cmd.purge": Localized(
            "Apaga tudo de uma conta", "Delete everything from an account"),
        "cli.cmd.set": Localized("Edita a regra de uma conta", "Edit an account's rule"),
        "cli.cmd.lang": Localized("Mostra ou define o idioma", "Show or set the language"),
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
        "cli.col.keep_flagged": Localized("marcadas", "keep flagged"),
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

        // set.
        "cli.set.max_age": Localized("idade máx.: %@", "max age: %@"),
        "cli.set.keep_flagged": Localized("manter marcadas: %@", "keep flagged: %@"),
        "cli.set.permanent": Localized("permanente: %@", "permanent: %@"),
        "cli.set.enabled": Localized("ativo: %@", "enabled: %@"),
        "cli.set.excluded": Localized("excluídas: %@", "excluded: %@"),
        "cli.set.excluded_none": Localized("nenhuma", "none"),
        "cli.set.bad_age": Localized(
            "idade inválida: %@ (use 30m, 12h, 1d ou 7d)",
            "invalid max age: %@ (use 30m, 12h, 1d or 7d)"),
        "cli.set.bad_on_off": Localized(
            "%@ deve ser 'on' ou 'off'.", "%@ must be 'on' or 'off'."),

        // lang.
        "cli.lang_current": Localized("idioma: %@", "language: %@"),
        "cli.lang_bad": Localized(
            "idioma inválido: %@ (use pt, en ou system)",
            "invalid language: %@ (use pt, en or system)"),
    ]
}
