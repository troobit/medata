import XCTest
import CardDetection
import CaptureKit
import Foods
import Persistence
import Pipeline
import PortableContracts
import Segmentation

// XCTest on-device performance assertions for the full estimation pipeline
// (tasks 65–66, Req 16.1, 16.7). Both tests skip on macOS — CI runs on a
// tethered iPhone 12 Pro per Req 16.7.
final class PipelinePerformanceTests: XCTestCase {

    // MARK: - Task 65: Single-view P95 ≤ 1000 ms (Req 16.1, 16.2)

    func testSingleViewP95LessThan1000ms() async throws {
        #if !os(iOS)
        throw XCTSkip("Performance tests are device-only (tethered iPhone 12 Pro, Req 16.7)")
        #endif

        let pipeline = makePerformancePipeline()
        let fixture   = makeSingleViewFixture()
        var durationsMs: [Double] = []

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            let t0   = Date.now
            let sema = DispatchSemaphore(value: 0)
            Task {
                _ = try? await pipeline.estimate(captureResult: fixture)
                sema.signal()
            }
            sema.wait()
            durationsMs.append(Date.now.timeIntervalSince(t0) * 1000)
        }

        let p95 = p95ms(durationsMs)
        XCTAssertLessThanOrEqual(
            p95, 1000,
            "Single-view P95 \(String(format: "%.0f", p95)) ms exceeds 1000 ms budget (Req 16.1)"
        )
    }

    // MARK: - Task 66: Two-view P95 ≤ 1800 ms (Req 16.1, 16.3)

    func testTwoViewP95LessThan1800ms() async throws {
        #if !os(iOS)
        throw XCTSkip("Performance tests are device-only (tethered iPhone 12 Pro, Req 16.7)")
        #endif

        let pipeline = makePerformancePipeline()
        let fixture   = makeTwoViewFixture()
        var durationsMs: [Double] = []

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTClockMetric()], options: options) {
            let t0   = Date.now
            let sema = DispatchSemaphore(value: 0)
            Task {
                _ = try? await pipeline.estimate(captureResult: fixture)
                sema.signal()
            }
            sema.wait()
            durationsMs.append(Date.now.timeIntervalSince(t0) * 1000)
        }

        let p95 = p95ms(durationsMs)
        XCTAssertLessThanOrEqual(
            p95, 1800,
            "Two-view P95 \(String(format: "%.0f", p95)) ms exceeds 1800 ms budget (Req 16.1)"
        )
    }

    // MARK: - Helpers

    // P95 of n samples = sorted[ceil(0.95 × n) − 1].
    // With n = 10 this equals sorted[9] = the maximum value.
    private func p95ms(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int(ceil(0.95 * Double(sorted.count))) - 1))
        return sorted[idx]
    }

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
            databaseEdition: "CoFID 2024",
            paletteVersion: "v1"
        )
    }

    private func makeTwoViewFixture() -> CaptureResult {
        CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: .fixture(timestampMonotonicNs: 2, depth: makeFlatDepthMap()),
            obliqueFrame: .fixture(timestampMonotonicNs: 3),
            databaseEdition: "CoFID 2024",
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
    func allMeals() async throws -> [MealRecord] { [] }
    func deleteMeal(id: UUID) async throws {}
    var mealsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
}

// Returns FP32 logits that make foodClasses[0] ("bread") dominate every pixel,
// so the pipeline does not throw noFoodPixels during performance measurement.
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
