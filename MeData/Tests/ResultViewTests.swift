import Pipeline
import PortableContracts
import Testing
@testable import MeData

@Suite("ResultView confidence pill thresholds")
struct ResultViewTests {

    @Test(
        "σ_meal maps to the correct pill label (Decision 17 four-tier boundaries)",
        arguments: [
            (sigma: Float(0.0), expected: ConfidenceLevel.veryLow),
            (sigma: Float(0.19), expected: .veryLow),
            (sigma: Float(0.20), expected: .low),
            (sigma: Float(0.49), expected: .low),
            (sigma: Float(0.50), expected: .moderate),
            (sigma: Float(0.74), expected: .moderate),
            (sigma: Float(0.75), expected: .high),
            (sigma: Float(1.0), expected: .high),
        ] as [(sigma: Float, expected: ConfidenceLevel)]
    )
    func pillLabelAtBoundary(sigma: Float, expected: ConfidenceLevel) {
        #expect(ConfidenceLevel.forSigma(sigma) == expected)
    }

    // Decision 17 / Req §9.3: the retake surface fires only at σ < 0.20.
    // The prior σ < 0.60 prompt is superseded (Decision 8 → Decision 17).
    @Test("very-low retake surface visible only below σ=0.20 (Req §9.3)")
    func veryLowSurfaceVisibility() {
        #expect(ResultFormat.showsVeryLowSurface(0.0))
        #expect(ResultFormat.showsVeryLowSurface(0.15))
        #expect(ResultFormat.showsVeryLowSurface(0.19))
        #expect(!ResultFormat.showsVeryLowSurface(0.20))
        #expect(!ResultFormat.showsVeryLowSurface(0.25))
        #expect(!ResultFormat.showsVeryLowSurface(0.55))
        #expect(!ResultFormat.showsVeryLowSurface(0.80))
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

    // The Δθ helper falls back to 0 until the research-side smolspec wires
    // `PbConfidenceResult.deltaThetaNadirDeg` / `deltaThetaObliqueDeg`
    // through PortableContracts. The Very-Low surface still renders the
    // string — it just reads "0° from target" for now.
    @Test("Δθ helper falls back to 0 pending research-side fields")
    func deltaThetaFallback() {
        let record = makeMealRecord(carbs: 0, sigma: 0.1)
        #expect(ResultFormat.maxDeltaThetaDeg(for: record) == 0)
    }

    // Req §23.3 / Decision 42: the placeholder banner is gated on the persisted
    // record value, NOT on the build flag, so Phase 1 records still surface the
    // banner when later viewed under a Phase 3 build.
    @Test("placeholder banner shown for dev_stub records")
    func placeholderBannerShownForDevStub() {
        #expect(ResultFormat.showsPlaceholderBanner(segmenterSource: "dev_stub"))
    }

    @Test("placeholder banner hidden for trained Core ML records")
    func placeholderBannerHiddenForCoreML() {
        #expect(!ResultFormat.showsPlaceholderBanner(segmenterSource: "coreml_v0.1"))
    }

    @Test("placeholder banner hidden for empty / unstamped records")
    func placeholderBannerHiddenForUnstamped() {
        #expect(!ResultFormat.showsPlaceholderBanner(segmenterSource: ""))
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

// nutrition5k-calibration Req 8.1/8.2 (Decisions 18–19): the single
// uncalibrated boolean becomes one three-state calibration-confidence signal
// evaluated over contributing solid-food classes only, plus one independent
// additive liquid over-estimate flag. The suppressed state is unreachable in
// this spec (no class can be device-verified yet) — covered by flag injection.
@Suite("Calibration banner three-state matrix (Req 8.1/8.2)")
struct CalibrationBannerTests {

    private func pcm(
        _ status: PbBetaCalibrationStatus,
        deviceVerified: Bool = false,
        isLiquid: Bool = false
    ) -> PbPerClassMacros {
        var out = PbPerClassMacros()
        out.betaStatus = status
        out.deviceVerified = deviceVerified
        out.isLiquid = isLiquid
        return out
    }

    // MARK: - full: any pooled/unity solid class

    @Test("any pooled or unity solid class → full banner")
    func anyUncalibratedSolidGivesFull() {
        #expect(ResultFormat.calibrationBanner(perClass: [
            "potato_boiled": pcm(.uncalibratedPooled)
        ]) == .full)
        #expect(ResultFormat.calibrationBanner(perClass: [
            "chicken": pcm(.uncalibratedUnity)
        ]) == .full)
        // One calibrated class does not soften a meal with an uncalibrated one.
        #expect(ResultFormat.calibrationBanner(perClass: [
            "white_rice": pcm(.calibrated, deviceVerified: true),
            "chicken": pcm(.uncalibratedUnity)
        ]) == .full)
    }

    @Test("no per-class data at all → full banner (conservative, pre-existing rule)")
    func emptyPerClassGivesFull() {
        #expect(ResultFormat.calibrationBanner(perClass: [:]) == .full)
    }

    // MARK: - softened: all calibrated, any not device-verified

    @Test("all calibrated + any not device-verified → softened")
    func calibratedNotVerifiedGivesSoftened() {
        #expect(ResultFormat.calibrationBanner(perClass: [
            "white_rice": pcm(.calibrated)
        ]) == .softened)
        #expect(ResultFormat.calibrationBanner(perClass: [
            "white_rice": pcm(.calibrated, deviceVerified: true),
            "pasta": pcm(.calibrated)
        ]) == .softened)
    }

    @Test("softened copy names the population-calibrated state")
    func softenedCopy() {
        #expect(ResultFormat.softenedBannerCopy.contains(
            "population-calibrated — not yet verified on this device"))
    }

    // MARK: - suppressed: all calibrated + all device-verified (injected —
    //          otherwise unreachable in this spec)

    @Test("all calibrated + all device-verified (injected) → suppressed")
    func allVerifiedGivesSuppressed() {
        #expect(ResultFormat.calibrationBanner(perClass: [
            "white_rice": pcm(.calibrated, deviceVerified: true),
            "pasta": pcm(.calibrated, deviceVerified: true)
        ]) == .suppressed)
    }

    // MARK: - liquid classes never enter the evaluation

    @Test("liquid classes are excluded from the calibration evaluation")
    func liquidClassesExcluded() {
        // An uncalibrated, unverified liquid cannot drag a verified solid down.
        #expect(ResultFormat.calibrationBanner(perClass: [
            "white_rice": pcm(.calibrated, deviceVerified: true),
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ]) == .suppressed)
        // Nor can a (nonsensical, injected) calibrated liquid rescue a pooled solid.
        #expect(ResultFormat.calibrationBanner(perClass: [
            "potato_boiled": pcm(.uncalibratedPooled),
            "milk": pcm(.calibrated, deviceVerified: true, isLiquid: true)
        ]) == .full)
    }

    // MARK: - standalone drink: stated rule, not vacuous suppression

    @Test("standalone drink (no contributing solid class) → no calibration banner")
    func standaloneDrinkShowsNoCalibrationBanner() {
        let state = ResultFormat.calibrationBanner(perClass: [
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ])
        #expect(state == CalibrationBannerState.none)
        #expect(state != .suppressed)
    }

    // MARK: - Req 8.2: the liquid flag is independent and additive

    @Test("liquid flag renders additively with each calibration state")
    func liquidFlagIsAdditive() {
        // The flag is a separate result-level input — it must not replace,
        // upgrade, or suppress the calibration state, and stands alone for a
        // standalone drink.
        let full: [String: PbPerClassMacros] = [
            "chicken": pcm(.uncalibratedUnity),
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ]
        let softened: [String: PbPerClassMacros] = [
            "white_rice": pcm(.calibrated),
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ]
        let suppressed: [String: PbPerClassMacros] = [
            "white_rice": pcm(.calibrated, deviceVerified: true),
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ]
        let standalone: [String: PbPerClassMacros] = [
            "milk": pcm(.uncalibratedUnity, isLiquid: true)
        ]
        #expect(ResultFormat.calibrationBanner(perClass: full) == .full)
        #expect(ResultFormat.calibrationBanner(perClass: softened) == .softened)
        #expect(ResultFormat.calibrationBanner(perClass: suppressed) == .suppressed)
        #expect(ResultFormat.calibrationBanner(perClass: standalone) == CalibrationBannerState.none)
        // The flag itself is read straight off the result, whatever the state.
        var macros = PbMacroResult()
        macros.liquidOverEstimate = true
        #expect(ResultFormat.showsLiquidOverEstimateFlag(macros))
        macros.liquidOverEstimate = false
        #expect(!ResultFormat.showsLiquidOverEstimateFlag(macros))
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
