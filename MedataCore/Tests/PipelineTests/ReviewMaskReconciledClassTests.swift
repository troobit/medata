import CaptureKit
import CardDetection
import CoreGraphics
import Foods
import Foundation
import ImageIO
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Pipeline

// Regression for bug `two-view-review-mask-class-mismatch` (2026-09-25
// outcomes 7845FF40, BB05A08C).
//
// On the two-view path both views are reconciled to one class
// (two-view-trust Decision 6) and the reconciled results are bound to a
// SHADOWED `nadirSeg` inside the `case .twoViewSfS` block. The map the review
// mask artefact is written from was never re-read from it, so a nadir the
// segmenter saw only as `unknown_food` kept class 34 in the mask while the row
// read "Bread wholemeal". The review overlay matches contours to rows BY
// CLASS, matched nothing, and drew no outline and no highlight — the estimate
// was right, the picture was empty.
//
// The property under test is that agreement: every carvable class in the
// persisted mask names a row on the record. It is asserted through a whole
// two-view `Pipeline.estimate` run — stub segmenter engine, stub support-plane
// fitter, synthetic frames — because the mask artefact is written at Stage L,
// after the carve, and nothing earlier observes the map.
@Suite("Review mask carries the reconciled class")
struct ReviewMaskReconciledClassTests {

    // 2 solids + bg(2) + unknown_food(3) + unsupported_liquid(4).
    private static let palette = ClassPalette(
        foodClasses: ["bread_wholemeal", "rice"],
        background: 2,
        unknownFood: 3,
        unsupportedLiquid: 4,
        version: "v0"
    )

    @Test("A nadir seen only as unknown_food persists the reconciled class, not class unknown")
    func maskClassesMatchTheRowsAfterReconciliation() async throws {
        let palette = Self.palette
        let namedClass = 0                       // bread_wholemeal — the oblique's read
        let store = RecordingStore()
        // Call 1 is the nadir (unknown_food only), call 2 the oblique (named):
        // `Pipeline.estimate` segments the nadir at stage F and the oblique
        // inside the two-view branch, in that order.
        let segmenter = CoreMLSegmenter(
            modelPath: "/dev/null",
            palette: palette,
            engine: ScriptedTwoViewEngine(
                classes: palette.totalClasses,
                background: palette.background,
                foodClassPerCall: [palette.unknownFood, namedClass]
            )
        )
        let pipeline = Pipeline(
            cardDetector: NoCardDetector(),
            segmenter: segmenter,
            database: OneEntryFoodDatabase(),
            store: store,
            supportPlaneFitter: FixedPlaneFitter()
        )

        let record = try await pipeline.estimate(
            captureResult: makeTwoViewCapture(), mode: .double
        )

        // The rows the review screen builds and joins the mask to, by class.
        let rowClassIds = Set(record.macros.perClass.keys)
        #expect(rowClassIds == ["bread_wholemeal"],
                "reconciliation must produce the oblique's named class as the single row")

        let png = try #require(store.maskPNG, "Stage L must persist a mask artefact")
        let maskClasses = try carvableClasses(inLabelPNG: png, palette: palette)
        #expect(!maskClasses.isEmpty, "an empty mask would satisfy the join vacuously")
        // The property: the picture and the rows agree. Before the fix the
        // mask held `unknown_food` while the row read `bread_wholemeal`, so
        // the overlay matched nothing and drew no outline.
        for classIndex in maskClasses {
            let name = try #require(palette.volumetricClassName(at: classIndex))
            #expect(rowClassIds.contains(name),
                    "mask class \(classIndex) (\(name)) names no row \(rowClassIds)")
        }
        #expect(!maskClasses.contains(palette.unknownFood),
                "the unreconciled nadir label must not survive into the review mask")
    }

    // MARK: - Capture

    // Camera at the origin looking down −Z at a table plane n̂=(0,0,1) at
    // z = −400 mm. `RawFrame.gravity` is WORLD-UP in the camera frame (bugfix
    // capture-no-flat-surface-gravity-frame), so for a nadir shot it points
    // back at the camera, (0,0,1) — the grid's vertical axis. Both frames
    // share a pose, so the oblique silhouette lands on the nadir's.
    private func makeTwoViewCapture() -> CaptureResult {
        let width = 100, height = 100
        let intrinsics = CameraIntrinsics(
            fx: 500, fy: 500, cx: 50, cy: 50,
            distortion: [], imageWidth: width, imageHeight: height
        )
        func frame(timestampNs: Int64, depth: DepthMap?) -> RawFrame {
            RawFrame(
                imageBytes: Data(count: width * height * 4),
                pixelFormat: .bgra8,
                colourSpace: .sRGB,
                orientation: 1,
                imageWidth: width, imageHeight: height,
                timestampMonotonicNs: timestampNs,
                intrinsics: intrinsics,
                gravity: Vec3(0, 0, 1),
                worldFromCamera: .identity,
                depth: depth
            )
        }
        let nadir = frame(timestampNs: 1, depth: makeDepthMap(intrinsics: intrinsics))
        return CaptureResult(
            capturePath: .twoViewSfS,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 60),
            nadirFrame: nadir,
            obliqueFrame: frame(timestampNs: 2, depth: nil),
            databaseEdition: "test",
            paletteVersion: "v0",
            nadirAngleAtCaptureDeg: 0,
            obliqueAngleAtCaptureDeg: 25
        )
    }

    // 4×4 at the table distance. Deliberately below `VoxelGridSizer`'s
    // `minHeightSampleCount`, so the grid keeps its constant vertical extent
    // and the carve does not depend on a synthetic height measurement.
    private func makeDepthMap(intrinsics: CameraIntrinsics) -> DepthMap {
        let w = 4, h = 4
        return DepthMap(
            depthBytesMm: [Float](repeating: 400, count: w * h)
                .withUnsafeBytes { Data($0) },
            confidenceBytes: Data([UInt8](repeating: 255, count: w * h)),
            width: w, height: h,
            rowStrideBytes: w * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 20, fy: 20, cx: 2, cy: 2,
                distortion: [], imageWidth: w, imageHeight: h
            ),
            depthFromColour: .identity
        )
    }

    // MARK: - Mask readback

    // The artefact is an 8-bit greyscale PNG of raw class indices
    // (MaskArtefactWriter.encodeLabelPNG); read the samples back as indices.
    private func carvableClasses(
        inLabelPNG png: Data, palette: ClassPalette
    ) throws -> Set<Int> {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = try #require(image.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)!
        var classes: Set<Int> = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let label = Int(ptr[y * image.bytesPerRow + x])
                if palette.isCarvableClass(label) { classes.insert(label) }
            }
        }
        return classes
    }
}

// MARK: - Test doubles

// Emits a centred square of one class per call over a background field: call n
// takes `foodClassPerCall[n]`. Logit 8 against 0 puts the softmax at ~0.999, so
// the square passes the silhouette test and the surround fails it.
private final class ScriptedTwoViewEngine: SegmenterInferenceEngine, @unchecked Sendable {
    // `@unchecked`: the two calls are sequential awaits inside one
    // `Pipeline.estimate`, never concurrent, and the lock covers the counter.
    private let lock = NSLock()
    private var callIndex = 0
    private let classes: Int
    private let background: Int
    private let foodClassPerCall: [Int]

    init(classes: Int, background: Int, foodClassPerCall: [Int]) {
        self.classes = classes
        self.background = background
        self.foodClassPerCall = foodClassPerCall
    }

    func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int) {
        lock.lock()
        let index = callIndex
        callIndex += 1
        lock.unlock()
        let foodClass = foodClassPerCall[min(index, foodClassPerCall.count - 1)]
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        let low = targetSize * 3 / 10
        let high = targetSize * 7 / 10
        for y in 0..<targetSize {
            let inRow = y >= low && y < high
            for x in 0..<targetSize {
                let isFood = inRow && x >= low && x < high
                logits[(y * targetSize + x) * classes + (isFood ? foodClass : background)] = 8
            }
        }
        return (logits, classes)
    }
}

// Table at z = −400 mm in the camera frame, matching the synthetic capture.
private struct FixedPlaneFitter: SupportPlaneFitter {
    func fitOutcome(
        nadir: RawFrame, cardPose: CardPose?, corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) -> SupportPlaneFitOutcome {
        SupportPlaneFitOutcome(
            plane: SupportPlane(
                normal: Vec3(0, 0, 1), distanceMm: -400,
                residualMm: 0.5, convergedIterations: nil
            ),
            stats: SupportPlaneFitStats(),
            refusal: nil
        )
    }
}

private struct NoCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [[PixelCorner]] { [] }
}

// Macros skips a class with no database row, and the review rows come from
// `macros.perClass` — so the named class needs an entry for the join under
// test to exist at all.
private struct OneEntryFoodDatabase: FoodDatabase {
    var version: String { "test" }
    func entry(for classId: String) -> FoodEntry? {
        guard classId == "bread_wholemeal" else { return nil }
        return FoodEntry(
            classId: classId, name: "Bread wholemeal",
            densityGPerCm3: 0.3, energyKJPer100g: 1000, carbsMonoG: 42,
            proteinG: 9, fatG: 3, fibreG: 7,
            beta: 1, calibrationStatus: .uncalibratedUnity,
            densitySource: "test", compositionSource: "test"
        )
    }
    func entry(for classId: String, edition: String) -> FoodEntry? { entry(for: classId) }
    func availableEditions() -> [String] { ["test"] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}

// Keeps the meal record and the bytes of the mask artefact Stage L writes.
private final class RecordingStore: PersistenceStore, @unchecked Sendable {
    // `@unchecked`: written once inside the awaited `estimate`, read after.
    private(set) var savedRecord: MealRecord?
    private(set) var maskPNG: Data?

    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {
        savedRecord = record
    }
    func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws {
        if artefact.kind == "mask" { maskPNG = data }
    }
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
    func artefactData(mealId: UUID, kind: String) async throws -> Data? {
        kind == "mask" ? maskPNG : nil
    }
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] {
        fatalError("unused")
    }
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection] {
        fatalError("unused")
    }
    func createCorrectionRecords(_ records: [PbCorrectionRecord]) async throws {
        fatalError("unused")
    }
    func updateCorrectionRecord(
        _ record: PbCorrectionRecord,
        upsertingCorrection correction: PbUserCorrection?
    ) async throws {
        fatalError("unused")
    }
    func updateCorrectionRecords(
        _ records: [PbCorrectionRecord],
        upsertingCorrection correction: PbUserCorrection?
    ) async throws {
        fatalError("unused")
    }
    func upsertCorrection(mealId: UUID, correction: PbUserCorrection) async throws {
        fatalError("unused")
    }
    func correctionRecords(for mealId: UUID) async throws -> [PbCorrectionRecord] {
        fatalError("unused")
    }
    func allCorrectionRecords() async throws -> [PbCorrectionRecord] {
        fatalError("unused")
    }
    func recentCorrectedClassIds(
        forPredictedClass classId: String, limit: Int
    ) async throws -> [String] {
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
    func recordBloodBsl(_ reading: BloodBslReading) async throws -> UUID? {
        fatalError("unused")
    }
    func saveInsulinDose(_ dose: InsulinDose) async throws {
        fatalError("unused")
    }
    func deleteInsulinEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func saveActivity(_ activity: ActivityEvent) async throws {
        fatalError("unused")
    }
    func deleteActivityEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func activities(
        before instant: Date, within interval: TimeInterval
    ) async throws -> [ActivityEvent] {
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
    func deleteBslEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func deleteRecords(mealIDs: [UUID], eventIDs: [UUID]) async throws {
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
    func markOutcomeProtected(id: UUID) async throws {
        fatalError("unused")
    }
    func markOutcomesProtected(mealID: UUID) async throws {
        fatalError("unused")
    }
    func unmarkOutcomeProtected(id: UUID) async throws {
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
    func attachWeighedTruth(
        _ meal: BenchmarkMeal, toOutcome outcomeID: UUID,
        carbsPer100g: (String, String) -> Double?
    ) async throws {
        fatalError("unused")
    }
    func openOccurrence(scheduleID: UUID, dueAt: Date) async throws -> DoseOccurrence {
        fatalError("unused")
    }
    func closeOccurrence(
        id: UUID, outcome: OccurrenceOutcome, closedAt: Date,
        insulinEventID: UUID?, wasNominal: Bool?
    ) async throws -> Bool {
        fatalError("unused")
    }
    func closeOccurrencesAsMissed(ids: [UUID], closedAt: Date) async throws -> Int {
        fatalError("unused")
    }
    func outstandingOccurrences() async throws -> [DoseOccurrence] {
        fatalError("unused")
    }
    func doseOccurrences(limit: Int) async throws -> [DoseOccurrence] {
        fatalError("unused")
    }
    func benchmarkMeals() async throws -> [BenchmarkMeal] {
        fatalError("unused")
    }
    var eventsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
}
