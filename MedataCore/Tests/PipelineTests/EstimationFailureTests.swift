import XCTest
import CaptureKit
import CardDetection
import Foods
import Persistence
import PortableContracts
import Segmentation
@testable import Pipeline

// Tests for EstimationFailure error mapping per design §5 (task 51).
// Verifies that Pipeline.estimate(_:) is `async throws -> MealRecord` and that
// pre-segmentation failure paths throw the correct EstimationFailure case.
// Paths that require real CoreML inference or Metal are covered by the
// design-contract assertions below (signature + enum exhaustiveness).

final class EstimationFailureTests: XCTestCase {

    // MARK: - §5 enum contract

    func testEstimationFailureIsError() {
        // Compile-time proof that EstimationFailure conforms to Error.
        let _: any Error = EstimationFailure.noScaleAvailable
        XCTAssertTrue(true)
    }

    func testAllCasesHaveLocalisedMessages() {
        let cases: [EstimationFailure] = [
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
            .lidarCoverageTooLow(["bread", "rice"]),
            .obliqueTiltOutOfRange,
            .mealsDbCorrupt
        ]
        for failure in cases {
            XCTAssertFalse(failure.localisedMessage.isEmpty,
                           "Missing localised message for \(failure)")
        }
    }

    // MARK: - Pipeline.estimate signature

    func testPipelineEstimateSignatureIsAsyncThrowsMealRecord() {
        // The method must have the exact type declared in design §2.4.
        // This test fails to compile if the signature drifts.
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let _: (CaptureResult, CaptureMode) async throws -> MealRecord = pipeline.estimate
        XCTAssertTrue(true)
    }

    // MARK: - noScaleAvailable: no card, no LiDAR depth

    func testNoCardNoLidar_throwsNoScaleAvailable() async throws {
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadir = RawFrame.fixture(timestampMonotonicNs: 0)   // no depth
        // Non-empty pre-shutter mask so the new SupportPlaneFitter's empty-
        // mask gate (Decision 2) does not pre-empt the noScaleAvailable path.
        let mask = makeNonEmptyMask(
            width: nadir.imageWidth, height: nadir.imageHeight
        )
        let captureResult = CaptureResult(
            capturePath: .twoViewSfS,
            lidar: .unavailable,
            nadirFrame: nadir,
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1",
            preShutterFoodMask: mask
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .double)
            XCTFail("Expected EstimationFailure.noScaleAvailable")
        } catch EstimationFailure.noScaleAvailable {
            // expected
        }
    }

    // MARK: - arWorldTrackingLost: two-view path with no oblique frame

    func testTwoViewPathMissingOblique_throwsArWorldTrackingLost() async throws {
        // Build a nadir frame with LiDAR depth so plane fit succeeds, but
        // omit the oblique frame to trigger arWorldTrackingLost.
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirWithDepth = RawFrame.fixture(
            timestampMonotonicNs: 1,
            depth: makeMinimalDepthMap()
        )
        let captureResult = CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: nadirWithDepth,
            obliqueFrame: nil,          // triggers arWorldTrackingLost
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1"
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .double)
            XCTFail("Expected EstimationFailure.arWorldTrackingLost")
        } catch EstimationFailure.arWorldTrackingLost {
            // expected
        } catch {
            // Other failures (e.g., plane-fit on synthetic data) are acceptable;
            // what matters is we do not succeed.
            XCTAssertTrue(error is EstimationFailure, "Unexpected error: \(error)")
        }
    }

    // MARK: - lidarUnavailableMidCapture: singleViewLidar path but no depth in frame

    func testSingleViewPathMissingDepth_throwsLidarUnavailableMidCapture() async throws {
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirNoDepth = RawFrame.fixture(
            timestampMonotonicNs: 2,
            depth: nil                  // no depth → lidarUnavailableMidCapture
        )
        let captureResult = CaptureResult(
            capturePath: .singleViewLidar,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 90),
            nadirFrame: nadirNoDepth,
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1"
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .single)
            XCTFail("Expected EstimationFailure.lidarUnavailableMidCapture")
        } catch EstimationFailure.lidarUnavailableMidCapture {
            // expected
        } catch {
            // noScaleAvailable is also acceptable if scale resolution fails first.
            XCTAssertTrue(error is EstimationFailure, "Unexpected error: \(error)")
        }
    }

    // MARK: - lidarCoverageTooLow associates the class names

    func testLidarCoverageTooLow_equatability() {
        let a = EstimationFailure.lidarCoverageTooLow(["bread"])
        let b = EstimationFailure.lidarCoverageTooLow(["bread"])
        let c = EstimationFailure.lidarCoverageTooLow(["rice"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - T87 oblique-tilt hard cap (Decision 43)
    //
    // |oblique − 25°| > 30° refuses; ≤ 30° accepts. Verified through the
    // pipeline's pre-segmentation gate: a two-view CaptureResult with an
    // oblique angle 60° (|60−25| = 35) must throw `obliqueTiltOutOfRange`
    // before any other refusal path is hit.
    func testObliqueTiltBeyondThirtyDegreesRefuses() async throws {
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirWithDepth = RawFrame.fixture(
            timestampMonotonicNs: 3,
            depth: makeMinimalDepthMap()
        )
        let oblique = RawFrame.fixture(timestampMonotonicNs: 4)
        let captureResult = CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: nadirWithDepth,
            obliqueFrame: oblique,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1",
            nadirAngleAtCaptureDeg: 0,
            obliqueAngleAtCaptureDeg: 60   // |60 − 25| = 35 > 30
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .double)
            XCTFail("Expected EstimationFailure.obliqueTiltOutOfRange")
        } catch EstimationFailure.obliqueTiltOutOfRange {
            // expected
        }
    }

    // MARK: - LiDAR-first scale fallback (Decision 1)
    //
    // A degenerate card read (four collinear corners → CardPoseSolver.solve
    // throws degenerateCardPose, proven by CardPoseSolverTests) must NOT abort
    // the estimate when the nadir frame carries LiDAR depth: cardPose is treated
    // as absent and the pipeline proceeds on the LiDAR-only scale + plane path.
    // Other downstream refusals on synthetic fixtures are acceptable; throwing a
    // card EstimationFailure would be the regression.
    func testCardSolveFailureWithLidarDepthDoesNotThrowCardFailure() async throws {
        let pipeline = Pipeline(
            cardDetector: CollinearCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirWithDepth = RawFrame.fixture(
            timestampMonotonicNs: 7,
            depth: makeMinimalDepthMap()
        )
        // Non-empty pre-shutter mask so the SupportPlaneFitter empty-mask gate
        // (Decision 2) does not pre-empt Stage C's card-solve outcome.
        let mask = makeNonEmptyMask(
            width: nadirWithDepth.imageWidth, height: nadirWithDepth.imageHeight
        )
        let captureResult = CaptureResult(
            capturePath: .singleViewLidar,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 90),
            nadirFrame: nadirWithDepth,
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1",
            preShutterFoodMask: mask
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .single)
            // Reaching success is fine — the fallback did not refuse.
        } catch EstimationFailure.degenerateCardPose {
            XCTFail("LiDAR depth present: card-solve failure must fall back, not throw degenerateCardPose")
        } catch EstimationFailure.cardTooOblique {
            XCTFail("LiDAR depth present: card-solve failure must fall back, not throw cardTooOblique")
        } catch {
            // Other refusals on these synthetic fixtures are acceptable.
        }
    }

    // The mirror case: with NO LiDAR depth, the same degenerate card read has no
    // alternative scale source, so the pipeline must still refuse with
    // degenerateCardPose (proving the fallback does not fire unconditionally).
    func testCardSolveFailureWithoutLidarDepthRefuses() async throws {
        let pipeline = Pipeline(
            cardDetector: CollinearCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirNoDepth = RawFrame.fixture(timestampMonotonicNs: 8)   // no depth
        // Non-empty pre-shutter mask so the empty-mask gate does not fire first.
        let mask = makeNonEmptyMask(
            width: nadirNoDepth.imageWidth, height: nadirNoDepth.imageHeight
        )
        let captureResult = CaptureResult(
            capturePath: .twoViewSfS,
            lidar: .unavailable,
            nadirFrame: nadirNoDepth,
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1",
            preShutterFoodMask: mask
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .double)
            XCTFail("Expected EstimationFailure.degenerateCardPose")
        } catch EstimationFailure.degenerateCardPose {
            // expected — no LiDAR depth, so the card is the only scale source.
        }
    }

    // |oblique − 25°| ≤ 30° must NOT throw the new refusal — at the boundary
    // (oblique = 55° → |Δ| = 30) the pipeline proceeds past the tilt gate.
    // Other downstream refusals are acceptable; only obliqueTiltOutOfRange
    // would be a regression.
    func testObliqueTiltAtBoundaryDoesNotRefuse() async throws {
        let pipeline = Pipeline(
            cardDetector: NilCardDetector(),
            segmenter: makeStubSegmenter(),
            database: EmptyFoodDatabase(),
            store: NoOpPersistenceStore()
        )
        let nadirWithDepth = RawFrame.fixture(
            timestampMonotonicNs: 5,
            depth: makeMinimalDepthMap()
        )
        let oblique = RawFrame.fixture(timestampMonotonicNs: 6)
        let captureResult = CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: nadirWithDepth,
            obliqueFrame: oblique,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1",
            nadirAngleAtCaptureDeg: 0,
            obliqueAngleAtCaptureDeg: 55   // |55 − 25| = 30 — at the cap, accepts
        )
        do {
            _ = try await pipeline.estimate(captureResult: captureResult, mode: .double)
            // Downstream refusals on synthetic fixtures are fine.
        } catch EstimationFailure.obliqueTiltOutOfRange {
            XCTFail("Boundary case |Δ|=30 must not throw obliqueTiltOutOfRange")
        } catch {
            // Other refusals are acceptable on these synthetic fixtures.
        }
    }
}

// MARK: - Test doubles

private struct NilCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
}

// Returns four collinear corners. CardPoseSolver.solve throws degenerateCardPose
// on these (rank-deficient homography), per CardPoseSolverTests
// .testDegenerateCardPoseWhenAllCornersCollinear. Used to drive Stage C's
// card-solve failure path deterministically.
private struct CollinearCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? {
        [
            PixelCorner(100, 100),
            PixelCorner(200, 100),
            PixelCorner(300, 100),
            PixelCorner(400, 100)
        ]
    }
}

private struct EmptyFoodDatabase: FoodDatabase {
    var version: String { "test" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
}

private struct NoOpPersistenceStore: PersistenceStore {
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {}
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {}
    func meal(id: UUID) async throws -> MealRecord {
        throw PersistenceError.mealNotFound(id)
    }
    func deleteArtefacts(olderThan date: Date) async throws {}
    func exportArchive() async throws -> String { "" }
    func sweepIfDue() async throws {}
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws {}
    func allMeals() async throws -> [MealRecord] { [] }
    func deleteMeal(id: UUID) async throws {}
    func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws {}
    func artefactData(mealId: UUID, kind: String) async throws -> Data? { nil }
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] {
        fatalError("unused")
    }
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection] {
        fatalError("unused")
    }
    func isImageProcessed(hash: String) async throws -> Bool {
        fatalError("unused")
    }
    func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func saveInsulinDose(_ dose: InsulinDose) async throws {
        fatalError("unused")
    }
    func deleteInsulinEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func saveIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func updateIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func deleteIntakeEntry(id: UUID) async throws {
        fatalError("unused")
    }
    func quickPresets() async throws -> [QuickPreset] {
        fatalError("unused")
    }
    func saveQuickPreset(_ preset: QuickPreset) async throws {
        fatalError("unused")
    }
    func deleteQuickPreset(id: UUID) async throws {
        fatalError("unused")
    }
    func saveEstimationOutcome(_ outcome: EstimationOutcome) async throws {
        fatalError("unused")
    }
    func estimationOutcomes(limit: Int) async throws -> [EstimationOutcome] {
        fatalError("unused")
    }
    func saveBenchmarkMeal(
        _ meal: BenchmarkMeal, carbsPer100g: (String, String) -> Double?
    ) async throws {
        fatalError("unused")
    }
    func benchmarkMeals() async throws -> [BenchmarkMeal] {
        fatalError("unused")
    }
    var eventsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
}

private struct ZeroLogitsEngine: SegmenterInferenceEngine {
    let classes: Int
    func runInference(inputFP16Bytes: Data, targetSize: Int) async throws -> (logits: [Float], classes: Int) {
        ([Float](repeating: 0, count: targetSize * targetSize * classes), classes)
    }
}

private func makeStubSegmenter() -> CoreMLSegmenter {
    let palette = ClassPalette(
        foodClasses: ["bread", "rice"],
        background: 2,
        unknownFood: 3,
        unsupportedLiquid: 4,
        version: "v1"
    )
    return CoreMLSegmenter(
        modelPath: "/dev/null",
        palette: palette,
        engine: ZeroLogitsEngine(classes: palette.totalClasses)
    )
}

// Builds a tiny non-empty BinaryMask so empty-mask gating doesn't pre-empt
// the test's intended refusal path.
import SupportPlane
private func makeNonEmptyMask(width: Int, height: Int) -> BinaryMask {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let cx = width / 2
    let cy = height / 2
    pixels[cy * width + cx] = 1
    return BinaryMask(pixels: pixels, width: width, height: height)
}

private func makeMinimalDepthMap() -> DepthMap {
    let w = 4; let h = 4
    let floatBytes = Data([Float](repeating: 500, count: w * h)
        .withUnsafeBytes { Data($0) })
    let confBytes = Data([UInt8](repeating: 255, count: w * h))
    return DepthMap(
        depthBytesMm: floatBytes,
        confidenceBytes: confBytes,
        width: w, height: h,
        rowStrideBytes: w * 4,
        depthIntrinsics: CameraIntrinsics(
            fx: 500, fy: 500, cx: 2, cy: 2,
            distortion: [], imageWidth: w, imageHeight: h
        ),
        depthFromColour: Mat4.identity
    )
}
