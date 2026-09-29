import Testing
@testable import MeData

// Task 43/57 — Decision 17 (supersedes Decision 8). Four-tier threshold + icon
// mapping for the shared `ConfidencePill`. Boundaries:
//   High      σ ≥ 0.75
//   Moderate  0.50 ≤ σ < 0.75
//   Low       0.20 ≤ σ < 0.50
//   Very Low  σ < 0.20
@Suite("ConfidencePill four-tier icon + label mapping")
struct ConfidencePillTests {

    @Test(
        "icon name per band (four tiers)",
        arguments: [
            (sigma: Float(0.0), iconName: "minus.circle.fill"),
            (sigma: Float(0.19), iconName: "minus.circle.fill"),
            (sigma: Float(0.20), iconName: "xmark.octagon.fill"),
            (sigma: Float(0.49), iconName: "xmark.octagon.fill"),
            (sigma: Float(0.50), iconName: "exclamationmark.triangle.fill"),
            (sigma: Float(0.74), iconName: "exclamationmark.triangle.fill"),
            (sigma: Float(0.75), iconName: "checkmark.seal.fill"),
            (sigma: Float(1.0), iconName: "checkmark.seal.fill"),
        ] as [(sigma: Float, iconName: String)]
    )
    func iconAtBoundary(sigma: Float, iconName: String) {
        #expect(ConfidenceLevel.forSigma(sigma).iconName == iconName)
    }

    @Test(
        "label per band (four tiers)",
        arguments: [
            (sigma: Float(0.0), label: "Very Low"),
            (sigma: Float(0.19), label: "Very Low"),
            (sigma: Float(0.20), label: "Low"),
            (sigma: Float(0.49), label: "Low"),
            (sigma: Float(0.50), label: "Moderate"),
            (sigma: Float(0.74), label: "Moderate"),
            (sigma: Float(0.75), label: "High"),
            (sigma: Float(1.0), label: "High"),
        ] as [(sigma: Float, label: String)]
    )
    func labelAtBoundary(sigma: Float, label: String) {
        #expect(ConfidenceLevel.forSigma(sigma).label == label)
    }

    @Test("accessibility token differs per band (anchors UI test queries)")
    func accessibilityTokenPerBand() {
        #expect(ConfidenceLevel.high.accessibilityToken == "high")
        #expect(ConfidenceLevel.moderate.accessibilityToken == "moderate")
        #expect(ConfidenceLevel.low.accessibilityToken == "low")
        #expect(ConfidenceLevel.veryLow.accessibilityToken == "veryLow")
    }
}
