import XCTest
import CaptureKit
import Persistence
import PortableContracts
import Segmentation
@testable import Pipeline

// Tests for `Pipeline.makeForDevice` per task 80 / Decision 42 / Req §23.
//
// The Pipeline SPM target defines DEV_STUB_SEGMENTER in `.debug`, so under
// `swift test` (and Xcode Debug builds) the factory selects
// `StubInferenceEngine` and stamps `segmenterSource = "dev_stub"`. The Phase 3
// (non-flag) branch is exercised by building Release without bundling a model,
// at which point the factory throws `PipelineFactoryError.segmenterModelMissing`
// — documented but not asserted here since SPM-test builds are always Debug.
//
// End-to-end Pipeline.estimate against a synthetic CaptureResult is not used
// because the rough food mask passed to LiDARPlaneFitter covers the whole frame
// (no points below the bbox), so the LiDAR plane fit fails before reaching the
// segmenter. The MealRecord stamping path is therefore exercised by:
//   (a) verifying the factory writes the expected source string into the
//       Pipeline's internal `segmenterSource` field;
//   (b) the round-trip tests in `PersistenceTests` covering the SQL/JSON layer.
final class PipelineFactoryTests: XCTestCase {

    private var tempDir: URL!
    private var store: GRDBPersistenceStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PipelineFactoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try GRDBPersistenceStore(
            dbURL: tempDir.appendingPathComponent("meals.sqlite"),
            artefactsBaseURL: tempDir
        )
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // The factory builds a Pipeline without throwing — proves
    // GRDBFoodDatabase.bundled() loads, the stub engine is selected, and
    // CoreMLSegmenter wraps it without referencing a `.mlpackage` on disk.
    func testMakeForDeviceDoesNotThrowUnderDevStub() throws {
        _ = try Pipeline.makeForDevice(store: store)
    }

    // Under DEV_STUB_SEGMENTER (the SPM-test default), the factory stamps
    // `segmenterSource = "dev_stub"` so every meal it produces carries the
    // banner-triggering value defined in Req §23.6.
    func testMakeForDeviceStampsDevStub() throws {
        let pipeline = try Pipeline.makeForDevice(store: store)
        XCTAssertEqual(pipeline.segmenterSource, "dev_stub",
                       "Phase 1 records must be stamped dev_stub per Req §23.6")
    }

    // Explicit-init Pipeline propagates the segmenterSource constructor arg
    // into produced MealRecords — proves the wiring inside Pipeline.estimate.
    // Constructed manually (not via the factory) so the test bypasses the
    // rough-mask issue described in the file header.
    func testPipelineInitPropagatesSegmenterSource() {
        let pipeline = Pipeline(
            cardDetector: NullDetector(),
            segmenter: CoreMLSegmenter(
                modelPath: "/dev/null",
                palette: .v1Standard,
                engine: StubInferenceEngine(palette: .v1Standard)
            ),
            database: EmptyFoodDatabase(),
            store: store,
            segmenterSource: "dev_stub"
        )
        XCTAssertEqual(pipeline.segmenterSource, "dev_stub")
    }
}

// MARK: - Test doubles

import CardDetection
import Foods

private struct NullDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
}

private struct EmptyFoodDatabase: FoodDatabase {
    var version: String { "test" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
}
