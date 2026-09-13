import Combine
import Foundation

public enum Language: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case pt
    case en

    public var id: String { rawValue }
}

/// One translatable string. Portuguese first, English second.
public struct Localized: Sendable {
    public let pt: String
    public let en: String

    public init(_ pt: String, _ en: String) {
        self.pt = pt
        self.en = en
    }
}

/// Translation tables in code, not .lproj: the CLI and the app binary also run
/// outside a bundle during development, where Bundle.main lookups fail.
///
/// Each target registers its own table (`register`), so the core, the app and
/// the CLI never edit the same file.
///
/// Language order: EBB_LANG environment variable > saved choice > macOS language.
public final class L10n: ObservableObject, @unchecked Sendable {
    public static let shared = L10n()

    private let lock = NSLock()
    private var table: [String: Localized] = CoreStrings.table

    @Published public private(set) var language: Language

    private init() {
        if let forced = ProcessInfo.processInfo.environment["EBB_LANG"],
            let lang = Language(rawValue: forced.lowercased()), lang != .system
        {
            language = lang
        } else {
            language = Language(rawValue: Settings.defaults.string(forKey: Settings.languageKey) ?? "") ?? .system
        }
    }

    public func set(_ lang: Language) {
        language = lang
        Settings.defaults.set(lang.rawValue, forKey: Settings.languageKey)
    }

    /// Effective language: `.system` resolved from macOS preferences.
    public var resolved: Language {
        if language != .system { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("pt") ? .pt : .en
    }

    public func register(_ strings: [String: Localized]) {
        lock.lock()
        table.merge(strings) { _, new in new }
        lock.unlock()
    }

    public func string(_ key: String) -> String {
        lock.lock()
        let entry = table[key]
        lock.unlock()
        guard let entry else { return key }
        return resolved == .pt ? entry.pt : entry.en
    }

    /// `t("key")` or `t("key", arg1, arg2)` — arguments use String(format:) specifiers.
    public func callAsFunction(_ key: String, _ args: CVarArg...) -> String {
        let format = string(key)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
}

/// UserDefaults shared by the app and the CLI.
public enum Settings {
    public static let suiteName = "com.ebb.app"
    public static let languageKey = "language"

    /// Inside Ebb.app the suite IS the app's own domain, and AppKit refuses a
    /// suite named after the running bundle ("does not make sense and will not
    /// work"). The CLI is a separate process and reads the same plist as a suite.
    public static var defaults: UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
