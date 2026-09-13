import Darwin
import EbbCore
import Foundation

/// Console I/O and small formatting helpers shared by the CLI commands. Kept
/// nonisolated so a @Sendable Cleaner progress closure can call it directly.
enum Terminal {
    // MARK: Output

    /// Prints a line to standard output.
    static func out(_ line: String) {
        print(line)
    }

    /// Prints a line to standard error.
    static func err(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8) ?? Data())
    }

    private static func write(_ text: String) {
        FileHandle.standardError.write(text.data(using: .utf8) ?? Data())
    }

    /// Redraws a single progress line on standard error. On a terminal it is
    /// cleared and overwritten in place; when piped, each update is a new line.
    static func progress(_ event: CleanerEvent) {
        let t = L10n.shared
        let text: String
        switch event {
        case .connecting:
            text = t("cli.progress.connecting")
        case .scanning(let mailbox):
            text = t("cli.progress.scanning", mailbox)
        case .deleting(let mailbox, let done, let total):
            text = t("cli.progress.deleting", mailbox, done, total)
        case .finished:
            finishProgress()
            return
        }
        if isatty(STDERR_FILENO) == 0 {
            write(text + "\n")
        } else {
            write("\r\u{1B}[K" + text)
        }
    }

    /// Ends the progress line so the next output does not overwrite it.
    static func finishProgress() {
        if isatty(STDERR_FILENO) != 0 {
            write("\n")
        }
    }

    /// Prints a simple aligned table: `headers` is the first row, every cell is
    /// padded to the widest cell of its column, columns are two spaces apart.
    static func table(headers: [String], rows: [[String]]) {
        let all = [headers] + rows
        let widths = headers.indices.map { column in
            all.map { $0[column].count }.max() ?? 0
        }
        func format(_ cells: [String]) -> String {
            cells.enumerated().map { index, cell in
                if index == cells.count - 1 { return cell }
                return cell.padding(toLength: widths[index] + 2, withPad: " ", startingAt: 0)
            }.joined()
        }
        out(format(headers))
        for row in rows { out(format(row)) }
    }

    // MARK: Password prompt

    /// Reads the app password without echoing it when stdin is a terminal;
    /// otherwise reads a single stdin line (for `… | ebb add <account>`).
    /// Returns nil when no input is available.
    static func readPassword(prompt: String) -> String? {
        if isatty(STDIN_FILENO) != 0 {
            let value = prompt.withCString { getpass($0) }
            guard let value else { return nil }
            return String(cString: value)
        }
        return readLine(strippingNewline: true)
    }

    // MARK: Values

    /// The table value for the on/off flag tokens accepted by `ebb set`.
    static func yesNo(_ text: String) -> Bool? {
        switch text {
        case "on": return true
        case "off": return false
        default: return nil
        }
    }

    // MARK: Durations

    /// Compact, neutral durations: `45s`, `30m`, `12h`, `7d`.
    static func age(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds >= 86_400 && seconds % 86_400 == 0 { return "\(seconds / 86_400)d" }
        if seconds >= 3_600 && seconds % 3_600 == 0 { return "\(seconds / 3_600)h" }
        if seconds >= 60 && seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "\(seconds)s"
    }

    /// Parses a duration token (`30m`, `12h`, `1d`) back into seconds; nil on
    /// anything else.
    static func parseAge(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let number = Int(text.dropLast()), number > 0 else { return nil }
        switch unit {
        case "m": return TimeInterval(number * 60)
        case "h": return TimeInterval(number * 3_600)
        case "d": return TimeInterval(number * 86_400)
        default: return nil
        }
    }

    /// A "how long ago" phrase for the accounts table and run summaries.
    static func agoPhrase(_ date: Date, now: Date = Date()) -> String {
        let t = L10n.shared
        var seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 { seconds = 0 }
        if seconds < 60 { return t("cli.rel.just_now") }
        if seconds < 3_600 { return t("cli.rel.ago", "\(seconds / 60)m") }
        if seconds < 86_400 { return t("cli.rel.ago", "\(seconds / 3_600)h") }
        return t("cli.rel.ago", "\(seconds / 86_400)d")
    }
}
