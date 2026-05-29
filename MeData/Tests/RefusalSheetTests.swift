import Pipeline
import Testing
@testable import MeData

// Task 49 / Req §20.7 / §12.2 / Decision 16. Per-case SF Symbol + title mapping
// for `RefusalSheet`. Sheet presentation + drag-down dismiss are covered by
// XCUITest in MeData/UITests/RefusalFlowUITests.swift; this suite enforces the
// per-case content contract.
@Suite("RefusalSheet — per-case symbol, title, and verbatim message")
struct RefusalSheetTests {

    @Test("each EstimationFailure case maps to a non-empty symbol")
    func everyCaseHasSymbol() {
        for failure in allFailures() {
            #expect(!failure.refusalSymbol.isEmpty)
        }
    }

    @Test("each EstimationFailure case maps to a non-empty title")
    func everyCaseHasTitle() {
        for failure in allFailures() {
            #expect(!failure.refusalTitle.isEmpty)
        }
    }

    @Test("symbols differ across the cases that produce visually distinct refusals")
    func distinctSymbolsForDistinctCauses() {
        // The seven causes the user sees most often during MVP testing must
        // each surface a distinct visual — a colour-blind reduction is OK,
        // a duplicate symbol is not.
        let distinct: [EstimationFailure] = [
            .noLidarDevice,
            .arWorldTrackingLost,
            .noScaleAvailable,
            .lidarFitResidualTooHigh,
            .noFoodPixels,
            .noFoodVolumeRecovered,
            .lidarCoverageTooLow([])
        ]
        let symbols = Set(distinct.map(\.refusalSymbol))
        #expect(symbols.count == distinct.count)
    }

    @Test("localisedMessage is surfaced verbatim (Req §12.2)")
    func messageVerbatim() {
        let failure = EstimationFailure.noScaleAvailable
        #expect(
            failure.localisedMessage
                == "Unable to determine meal scale. Please include the reference card in the image."
        )
    }
}

private func allFailures() -> [EstimationFailure] {
    [
        .noLidarDevice,
        .arWorldTrackingLost,
        .lidarUnavailableMidCapture,
        .degenerateCardPose,
        .cardTooOblique,
        .lidarFitDegenerate,
        .lidarFitResidualTooHigh,
        .iterationDiverged,
        .noScaleAvailable,
        .noFoodPixels,
        .noFoodVolumeRecovered,
        .lidarCoverageTooLow(["rice"]),
        .mealsDbCorrupt
    ]
}
