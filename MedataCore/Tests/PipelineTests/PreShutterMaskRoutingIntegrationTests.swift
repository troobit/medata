import CaptureKit
import CardDetection
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import Pipeline

// Req 8.7: integration test asserting the pre-shutter mask placed into
// `CaptureResult.preShutterFoodMask` reaches `SupportPlaneFitter.fit` byte-
// identical to what was set. The probe captures the mask argument synchronously
// inside `fit(...)` before any downstream stage can mutate or replace it, then
// the test compares pixel buffers against the original.
@Suite("Pre-shutter mask routing (Req 8.7)")
struct PreShutterMaskRoutingIntegrationTests {

    @Test("preShutterFoodMask reaches SupportPlaneFitter.fit byte-identical")
    func preShutterMaskReachesFoodRegionMaskInputs() async throws {
        let probe = ProbeFitter()
        let pipeline = try Pipeline.makeForDevice(
            store: NoOpPersistenceStore(),
            cardDetector: LocalNoOpCardDetector(),
            supportPlaneFitter: probe
        )

        let maskWidth = 1920
        let maskHeight = 1440
        let mask = makeSyntheticPlateMask(width: maskWidth, height: maskHeight)
        let nadir = RawFrame.fixture(
            timestampMonotonicNs: 1,
            depth: makeMinimalDepthMap()
        )
        let captureResult = CaptureResult(
            capturePath: .singleViewLidar,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 0),
            nadirFrame: nadir,
            obliqueFrame: nil,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v0",
            preShutterFoodMask: mask
        )

        // Downstream stages (MetricScale onwards) may throw on the synthetic
        // RawFrame; the probe records the mask before the fit() body returns,
        // so the byte-identity assertion is independent of that failure.
        _ = try? await pipeline.estimate(captureResult: captureResult, mode: .single)

        let captured = probe.lastFoodMask
        #expect(captured != nil, "probe.fit must be invoked by Pipeline.estimate")
        #expect(captured?.width == maskWidth)
        #expect(captured?.height == maskHeight)
        #expect(captured?.pixels == mask.pixels,
                "mask bytes must reach SupportPlaneFitter.fit unchanged")
    }
}

// MARK: - Test doubles

// Records the mask argument and returns a finite plane so callers downstream
// of `fitSupportPlane` still see a successful support-plane stage.
private final class ProbeFitter: SupportPlaneFitter, @unchecked Sendable {
    var lastFoodMask: BinaryMask?

    func fitOutcome(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) -> SupportPlaneFitOutcome {
        lastFoodMask = preShutterFoodMask
        let plane = SupportPlane(
            normal: Vec3(0, -1, 0),
            distanceMm: 300,
            residualMm: 1,
            convergedIterations: nil
        )
        return SupportPlaneFitOutcome(
            plane: plane, stats: SupportPlaneFitStats(), refusal: nil
        )
    }
}

private struct LocalNoOpCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
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
    func estimationOutcomes(limit: Int) async throws -> [EstimationOutcome] {
        fatalError("unused")
    }
    func saveBenchmarkMeal(
        _ meal: BenchmarkMeal, carbsPer100g: (String, String) -> Double?
    ) async throws {
        fatalError("unused")
    }
    func saveDoseSuggestion(_ row: DoseSuggestionRecord) async throws {
        fatalError("unused")
    }
    func linkDose(
        suggestionID: UUID, insulinEventID: UUID, givenUnits: Double
    ) async throws {
        fatalError("unused")
    }
    func doseSuggestions(limit: Int) async throws -> [DoseSuggestionRecord] {
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

// MARK: - Fixture helpers

// Centred-rectangle silhouette over a black background. Byte buffer matches
// the BinaryMask invariant (`pixels.count == width * height`).
private func makeSyntheticPlateMask(width: Int, height: Int) -> BinaryMask {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let plateXRange = (width / 4)..<(3 * width / 4)
    let plateYRange = (height / 4)..<(3 * height / 4)
    for y in plateYRange {
        for x in plateXRange {
            pixels[y * width + x] = 1
        }
    }
    return BinaryMask(pixels: pixels, width: width, height: height)
}

private func makeMinimalDepthMap() -> DepthMap {
    let w = 4
    let h = 4
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
        depthFromColour: .identity
    )
}
