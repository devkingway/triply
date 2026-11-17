import SwiftUI

/// The user's choice of light / dark look. Stored in the App Group so the Share screen matches.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    static let storageKey = "appearance"
    static var store: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    var label: String {
        switch self {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// `nil` follows the iPhone's setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
