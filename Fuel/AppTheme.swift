import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "Automatico"
    case light = "Chiaro"
    case dark = "Scuro"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
