import Combine
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

enum DisposableAgeOption: TimeInterval, CaseIterable, Identifiable {
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case threeHours = 10_800
    case twelveHours = 43_200

    var id: TimeInterval { rawValue }

    var key: String {
        switch self {
        case .fifteenMinutes: return "app.age.15m"
        case .thirtyMinutes: return "app.age.30m"
        case .oneHour: return "app.age.1h"
        case .threeHours: return "app.age.3h"
        case .twelveHours: return "app.age.12h"
        }
    }

    static func matching(_ interval: TimeInterval) -> DisposableAgeOption {
        allCases.first { $0.rawValue == interval } ?? .oneHour
    }
}

enum MaxAgeOption: TimeInterval, CaseIterable, Identifiable {
    case twelveHours = 43_200
    case oneDay = 86_400
    case threeDays = 259_200
    case sevenDays = 604_800
    case fourteenDays = 1_209_600
    case thirtyDays = 2_592_000
    case never = 3_155_760_000

    var id: TimeInterval { rawValue }

    var key: String {
        switch self {
        case .twelveHours: return "app.age.12h"
        case .oneDay: return "app.age.1d"
        case .threeDays: return "app.age.3d"
        case .sevenDays: return "app.age.7d"
        case .fourteenDays: return "app.age.14d"
        case .thirtyDays: return "app.age.30d"
        case .never: return "app.age.never"
        }
    }

    static func matching(_ interval: TimeInterval) -> MaxAgeOption {
        allCases.first { $0.rawValue == interval } ?? .oneDay
    }
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var sidebar: SidebarItem = .general
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
