import SwiftUI

/// Design tokens. The polished SwiftUI build leans on system colors + SF
/// Symbols, but keeps the "two-accent" idea from the wireframe (success +
/// warning) so confidence states stay legible.
enum DS {
    static let ink         = Color.primary
    static let ink2        = Color.secondary
    static let ink3        = Color(.tertiaryLabel)
    static let paper       = Color(.systemBackground)
    static let paperElev   = Color(.secondarySystemBackground)
    static let separator   = Color(.separator)

    static let success     = Color(red: 0.18, green: 0.55, blue: 0.37)  // ok
    static let warning     = Color(red: 0.79, green: 0.48, blue: 0.12)  // warn
    static let successSoft = Color(red: 0.85, green: 0.92, blue: 0.88)
    static let warningSoft = Color(red: 0.94, green: 0.88, blue: 0.78)

    static let radiusS: CGFloat = 6
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 16
    static let spacingXS: CGFloat = 4
    static let spacingS:  CGFloat = 8
    static let spacingM:  CGFloat = 12
    static let spacingL:  CGFloat = 16
    static let spacingXL: CGFloat = 24
}

extension Confidence.Level {
    var displayName: String {
        switch self {
        case .high:     return "High confidence"
        case .moderate: return "Moderate"
        case .low:      return "Uncertain"
        }
    }
    var tint: Color {
        switch self {
        case .high:     return DS.success
        case .moderate: return DS.ink2
        case .low:      return DS.warning
        }
    }
    var sfSymbol: String {
        switch self {
        case .high:     return "checkmark.seal.fill"
        case .moderate: return "circle.dotted"
        case .low:      return "exclamationmark.triangle.fill"
        }
    }
}
