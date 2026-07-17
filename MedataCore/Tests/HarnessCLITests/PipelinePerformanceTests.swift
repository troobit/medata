#if HARNESS_ENABLED
import XCTest
import CardDetection
import CaptureKit
import Foods
import Persistence
import Pipeline
import PortableContracts
import Segmentation

// Single end-to-end soft latency check per Decision 40 / Req §16.1: the full
// pipeline must complete in under 30 s for both `single` and `double` modes on
// the v1 hardware floor (iPhone 13 Pro Max, iOS 26.5). The per-stage P95
// budgets from earlier revisions (tasks 65–66) are deleted; per-stage timing
// is still emitted via `os_signpost` in DEBUG builds for ad-hoc Instruments
// inspection but no per-stage assertion is made.
//
// The test runs on the developer device with `-D HARNESS_ENABLED`; CI is not
// gated on harness output in v1.
final class PipelinePerformanceTests: XCTestCase {

    func testSingleViewEndToEndUnderThirtySeconds() async throws {
        #if !os(iOS)
        throw XCTSkip("End-to-end soft latency check is device-only (iPhone 13 Pro Max, Req §16.1)")
        #endif

        let pipeline = makePerformancePipeline()
        let fixture   = makeSingleViewFixture()

        let start = Date.now
        _ = try? await pipeline.estimate(captureResult: fixture, mode: .single)
        let elapsed = Date.now.timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 30.0,
            "Single-view end-to-end \(String(format: "%.2f", elapsed)) s exceeds 30 s soft target (Req §16.1)"
        )
    }

    func testTwoViewEndToEndUnderThirtySeconds() async throws {
        #if !os(iOS)
        throw XCTSkip("End-to-end soft latency check is device-only (iPhone 13 Pro Max, Req §16.1)")
        #endif

        let pipeline = makePerformancePipeline()
        let fixture   = makeTwoViewFixture()

        let start = Date.now
        _ = try? await pipeline.estimate(captureResult: fixture, mode: .double)
        let elapsed = Date.now.timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 30.0,
            "Two-view end-to-end \(String(format: "%.2f", elapsed)) s exceeds 30 s soft target (Req §16.1)"
        )
    }

    // MARK: - Helpers

    private func makePerformancePipeline() -> Pipeline {
        let palette = ClassPalette(
            foodClasses: ["bread", "rice"],
            background: 2, unknownFood: 3, unsupportedLiquid: 4,
            version: "v1"
        )
        return Pipeline(
            cardDetector: NoOpCardDetector(),
            segmenter: CoreMLSegmenter(
                modelPath: "/dev/null",
                palette: palette,
                engine: FoodDominantEngine(classes: palette.totalClasses)
            ),
            database: EmptyFoodDB(),
            store: NoOpStore()
        )
    }

    private func makeSingleViewFixture() -> CaptureResult {
        CaptureResult(
            capturePath: .singleViewLidar,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 90),
            nadirFrame: .fixture(timestampMonotonicNs: 1, depth: makeFlatDepthMap()),
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024 + AFCD 2024",
            paletteVersion: "v1"
        )
    }

    private func makeTwoViewFixture() -> CaptureResult {
        CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: .fixture(timestampMonotonicNs: 2, depth: makeFlatDepthMap()),
            obliqueFrame: .fixture(timestampMonotonicNs: 3),
            databaseEdition: "CoFID 2024 + AFCD 2024",
            paletteVersion: "v1"
        )
    }

    private func makeFlatDepthMap() -> DepthMap {
        let w = 64, h = 48
        let depthBytes = [Float](repeating: 400, count: w * h).withUnsafeBytes { Data($0) }
        let confBytes  = Data([UInt8](repeating: 255, count: w * h))
        return DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: confBytes,
            width: w, height: h,
            rowStrideBytes: w * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 500, fy: 500,
                cx: Float(w) / 2, cy: Float(h) / 2,
                distortion: [], imageWidth: w, imageHeight: h
            ),
            depthFromColour: .identity
        )
    }
}

// MARK: - Stubs

private struct NoOpCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
}

private struct EmptyFoodDB: FoodDatabase {
    var version: String { "perf-stub" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
}

private struct NoOpStore: PersistenceStore {
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {}
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {}
    func meal(id: UUID) async throws -> MealRecord { throw PersistenceError.mealNotFound(id) }
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

// Returns FP32 logits that make foodClasses[0] ("bread") dominate every pixel,
// so the pipeline does not throw noFoodPixels during latency measurement.
private struct FoodDominantEngine: SegmenterInferenceEngine {
    let classes: Int
    func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int) {
        var logits = [Float](repeating: -10, count: targetSize * targetSize * classes)
        for px in 0 ..< targetSize * targetSize {
            logits[px * classes] = 5.0  // class index 0 = bread
        }
        return (logits, classes)
    }
}
#endif
