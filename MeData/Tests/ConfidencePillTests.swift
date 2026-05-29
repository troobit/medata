import Testing
@testable import MeData

// Task 43 / Decision 16. Threshold + icon mapping for the shared
// `ConfidencePill`. The threshold fixture mirrors the v1.0 ResultView table
// (Decision 8 boundaries) so any drift between the two is caught here.
@Suite("ConfidencePill three-tier icon + label mapping")
struct ConfidencePillTests {

    @Test(
        "icon name per band",
        arguments: [
            (sigma: Float(0.0), iconName: "xmark.octagon.fill"),
            (sigma: Float(0.59), iconName: "xmark.octagon.fill"),
            (sigma: Float(0.60), iconName: "exclamationmark.triangle.fill"),
            (sigma: Float(0.74), iconName: "exclamationmark.triangle.fill"),
            (sigma: Float(0.75), iconName: "checkmark.seal.fill"),
            (sigma: Float(1.0), iconName: "checkmark.seal.fill"),
        ] as [(sigma: Float, iconName: String)]
    )
    func iconAtBoundary(sigma: Float, iconName: String) {
        #expect(ConfidenceLevel.forSigma(sigma).iconName == iconName)
    }

    @Test(
        "label per band",
        arguments: [
            (sigma: Float(0.0), label: "Low"),
            (sigma: Float(0.59), label: "Low"),
            (sigma: Float(0.60), label: "Moderate"),
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
    }
}
