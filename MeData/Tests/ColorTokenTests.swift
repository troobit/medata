import SwiftUI
import Testing
@testable import MeData

// Task 42 / Decision 16 / Req §20.1. Asserts that the design tokens added in
// `App/Colors.swift` round-trip to the right concrete `Color` values — the
// canonical `medataAccent` is asserted bit-exact at #63FF00, and the
// system-semantic tokens (which adapt under light/dark) are exercised through
// their CGColor under both colour schemes.
@Suite("Design-system colour tokens (Decision 16)")
struct ColorTokenTests {

    @Test("medataAccent resolves to #63FF00 exactly")
    func brandAccentExactHex() throws {
        let uiColor = UIColor(Color.medataAccent)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(Int((red * 255).rounded()) == 0x63)
        #expect(Int((green * 255).rounded()) == 0xFF)
        #expect(Int((blue * 255).rounded()) == 0x00)
        #expect(alpha == 1.0)
    }

    @Test("confidenceHigh aliases medataAccent (single accent budget)")
    func confidenceHighIsAccent() {
        #expect(Color.confidenceHigh == Color.medataAccent)
    }

    @Test("captureBackground is pure black for OLED contrast (Req §20.2)")
    func captureBackgroundIsBlack() {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 0
        UIColor(Color.captureBackground).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(red == 0)
        #expect(green == 0)
        #expect(blue == 0)
        #expect(alpha == 1)
    }

    @Test("placeholderFG is black so it reads on systemYellow at ≥4.5:1")
    func placeholderFGContrast() {
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 0
        UIColor(Color.placeholderFG).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(red == 0 && green == 0 && blue == 0)
    }

    @Test("surface tokens adapt across light/dark (system-semantic, not static)")
    func surfaceTokensAdaptToColorScheme() {
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        let primary = UIColor(Color.surfacePrimary)
        let light = primary.resolvedColor(with: lightTrait)
        let dark = primary.resolvedColor(with: darkTrait)
        // systemGroupedBackground differs across the two traits; if a future
        // refactor accidentally swaps it for a static colour this fails.
        #expect(light != dark)
    }
}
