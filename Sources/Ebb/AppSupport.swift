import EbbCore
import Foundation
import SwiftUI

enum AppSettingKey {
    static let autoCleanup = "autoCleanup"
    static let intervalMinutes = "intervalMinutes"
}

enum EbbAccent {
    /// Calm sea teal — the only accent color in the app.
    static let color = Color(red: 0.20, green: 0.55, blue: 0.58)
}

enum AgeOption: TimeInterval, CaseIterable, Identifiable {
    case oneHour = 3_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case threeDays = 259_200
    case sevenDays = 604_800
    case thirtyDays = 2_592_000

    var id: TimeInterval { rawValue }

    var key: String {
        switch self {
        case .oneHour: return "app.age.1h"
        case .twelveHours: return "app.age.12h"
        case .oneDay: return "app.age.1d"
        case .threeDays: return "app.age.3d"
        case .sevenDays: return "app.age.7d"
        case .thirtyDays: return "app.age.30d"
        }
    }

    static func matching(_ interval: TimeInterval) -> AgeOption {
        allCases.first { $0.rawValue == interval } ?? .oneDay
    }
}

enum RelativeTime {
    static func string(from date: Date, language: Language) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale(for: language)
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func absolute(from date: Date, language: Language) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(for: language)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func locale(for language: Language) -> Locale {
        Locale(identifier: language == .pt ? "pt_BR" : "en_US")
    }
}

enum SidebarItem: Hashable {
    case account(UUID)
    case general
}
