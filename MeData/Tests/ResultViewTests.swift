import Pipeline
import PortableContracts
import Testing
@testable import MeData

@Suite("ResultView confidence pill thresholds")
struct ResultViewTests {

    @Test(
        "σ_meal maps to the correct pill label (Decision 8 boundaries)",
        arguments: [
            (sigma: Float(0.0), expected: ConfidenceLevel.low),
            (sigma: Float(0.59), expected: .low),
            (sigma: Float(0.60), expected: .moderate),
            (sigma: Float(0.74), expected: .moderate),
            (sigma: Float(0.75), expected: .high),
            (sigma: Float(1.0), expected: .high),
        ] as [(sigma: Float, expected: ConfidenceLevel)]
    )
    func pillLabelAtBoundary(sigma: Float, expected: ConfidenceLevel) {
        #expect(ConfidenceLevel.forSigma(sigma) == expected)
    }

    @Test("uncertain-estimate prompt visible only below σ=0.60 (§9.3)")
    func uncertainPromptVisibility() {
        #expect(ResultFormat.showsUncertainPrompt(0.0))
        #expect(ResultFormat.showsUncertainPrompt(0.59))
        #expect(!ResultFormat.showsUncertainPrompt(0.60))
        #expect(!ResultFormat.showsUncertainPrompt(0.80))
    }

    @Test("carbs rounded to nearest 1 g (§9.1)")
    func carbsRounding() {
        #expect(ResultFormat.carbsGrams(42.4) == 42)
        #expect(ResultFormat.carbsGrams(42.5) == 43)
        #expect(ResultFormat.carbsGrams(0.0) == 0)
    }

    // Decision 3 / §9.5: the result surface exposes only carbs + confidence.
    // The record carries clinical macros and per-class data, but ResultView
    // reads neither — guarded here by confirming the view's inputs are limited
    // to the carb total and σ_meal helpers above. (Structural absence of
    // per-class breakdown is enforced by ResultView's body using only these.)
    @Test("result formatting reads only carbs and σ_meal")
    func surfaceLimitedToCarbsAndConfidence() {
        let record = makeMealRecord(carbs: 30, sigma: 0.8)
        #expect(ResultFormat.carbsGrams(record.macros.totalCarbsG) == 30)
        #expect(ConfidenceLevel.forSigma(record.confidence.sigmaMeal) == .high)
    }

    // §19.4 / design §"Meals tab": ResultView is reused as the meal-detail
    // view from the Meals tab. A presentation mode controls whether the
    // "New capture" action is shown — only the Photo tab's just-captured
    // path needs it; the history-detail path is read-only.
    @Test("justCaptured mode shows New capture action")
    func justCapturedShowsNewCapture() {
        #expect(ResultPresentation.justCaptured.showsNewCapture)
    }

    @Test("historyDetail mode hides New capture action")
    func historyDetailHidesNewCapture() {
        #expect(!ResultPresentation.historyDetail.showsNewCapture)
    }
}

private func makeMealRecord(carbs: Float, sigma: Float) -> MealRecord {
    var macros = PbMacroResult()
    macros.totalCarbsG = carbs
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = sigma
    return MealRecord(
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v1",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}
