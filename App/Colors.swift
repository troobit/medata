import SwiftUI

// Design tokens per `design-system/MASTER.md` §"Colour tokens" (UI Req §20.1 /
// Decision 16). Views read from these named accessors only — inline
// `Color(red:green:blue:)` or hex strings in view bodies is an anti-pattern
// guarded by the CI assertion in `ColourTokenUsageTests`.
extension Color {

    // MARK: - Brand

    static let medataAccent = Color(red: 0x63 / 255, green: 0xFF / 255, blue: 0x00 / 255)

    // MARK: - Capture / Result (OLED)

    static let captureBackground = Color.black
    static let captureChromeText = Color.white
    static let captureChromeBG = Color.white.opacity(0.10)
    static let captureScrim = Color.black.opacity(0.45)

    // MARK: - Surfaces (Meals / Settings — system Grouped)

    static let surfacePrimary = Color(uiColor: .systemGroupedBackground)
    static let surfaceElevated = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let separatorSubtle = Color(uiColor: .separator)

    // MARK: - Confidence pill

    static let confidenceHigh = medataAccent
    static let confidenceModerate = Color(uiColor: .systemOrange)
    static let confidenceLow = Color(uiColor: .systemRed)
    // Decision 17: desaturated greyscale — "use with skepticism" rather than
    // alarm. The Low tier already owns systemRed, so Very Low needs a tone
    // that draws the eye to the surrounding explanation copy instead.
    static let confidenceVeryLow = Color(white: 0.35)

    // MARK: - Placeholder chip (research Req 23.3)

    static let placeholderBG = Color(uiColor: .systemYellow)
    static let placeholderFG = Color.black

    // MARK: - Trends chart (Decision 12, design-handoff-00)

    // Glucose line series on the Trends chart.
    static let seriesGlucose = Color(uiColor: .systemOrange)
    // 3.9–10.0 mmol/L target range band fill.
    static let bandTarget = medataAccent.opacity(0.10)
}
