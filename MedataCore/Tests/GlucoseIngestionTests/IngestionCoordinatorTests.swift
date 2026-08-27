import Foundation
import Persistence
import PortableContracts
import XCTest

@testable import GlucoseIngestion

// IngestionCoordinator against a real GRDBPersistenceStore (specs/data/
// cgm-connect Req 5): grid-snap boundaries, intra-batch collapse,
// mg/dL → mmol/L conversion incl. the 0.3-threshold boundary, cross-source
// dedup + the in-session discrepancy tally, and the durable-ack rethrow.
final class IngestionCoordinatorTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var coordinator: IngestionCoordinator!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "IngestionCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
        coordinator = IngestionCoordinator(store: store)
    }

    override func tearDown() async throws {
        coordinator = nil
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // Base 2026-07-02T00:00Z — on the 5-minute grid.
    private let baseMs: Int64 = 1_782_950_400_000

    private func gridMs(_ minute: Int) -> Int64 { baseMs + Int64(minute) * 60_000 }

    private func sample(atMs instantMs: Int64, _ mmolL: Double) -> GlucoseSample {
        GlucoseSample(
            nativeInstant: Date(timeIntervalSince1970: Double(instantMs) / 1000),
            mmolL: mmolL)
    }

    // Stored bsl events in the first hour after base, ordered by timestamp,
    // as (timestampMs, value) pairs.
    private func storedBsl() async throws -> [(timestampMs: Int64, value: Double)] {
        let start = Date(timeIntervalSince1970: Double(baseMs) / 1000)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        return events.map {
            (
                timestampMs: Int64(($0.timestamp.timeIntervalSince1970 * 1000).rounded()),
                value: $0.value ?? .nan
            )
        }
    }

    // MARK: - Grid-snap boundaries (Req 5.1, Decision 4)

    func testGridSnapBoundaries() async throws {
        // Four samples at distinct marks so nothing collapses intra-batch.
        let summary = try await coordinator.ingest(
            [
                sample(atMs: gridMs(0), 5.0),  // exact mark → unchanged
                sample(atMs: gridMs(5) + 149_000, 5.1),  // +2:29 → snaps down
                sample(atMs: gridMs(10) + 150_000, 5.2),  // +2:30 → half-to-LATER
                sample(atMs: gridMs(20) - 150_000, 5.3),  // 2:30 before → snaps TO the mark
            ], from: "healthkit")

        XCTAssertEqual(summary.stored, 4)
        let stored = try await storedBsl()
        XCTAssertEqual(stored.map(\.timestampMs), [gridMs(0), gridMs(5), gridMs(15), gridMs(20)])
        XCTAssertEqual(stored.map(\.value), [5.0, 5.1, 5.2, 5.3])
    }

    // MARK: - Intra-batch collapse (Req 5.2)

    func testIntraBatchCollapseNearestToMarkWins() async throws {
        // Both snap to gridMs(0); the farther sample is listed first, so
        // "first wins" would store the wrong one.
        let summary = try await coordinator.ingest(
            [
                sample(atMs: gridMs(0) + 140_000, 6.4),
                sample(atMs: gridMs(0) - 100_000, 5.5),
            ], from: "healthkit")

        XCTAssertEqual(summary.stored, 1, "two same-mark samples collapse to one row")
        let stored = try await storedBsl()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].timestampMs, gridMs(0))
        XCTAssertEqual(stored[0].value, 5.5, "nearest-to-mark sample wins")
    }

    func testIntraBatchCollapseTieEarliestInstantWins() async throws {
        // Equidistant from gridMs(0); the later instant is listed first.
        let summary = try await coordinator.ingest(
            [
                sample(atMs: gridMs(0) + 60_000, 6.6),
                sample(atMs: gridMs(0) - 60_000, 5.5),
            ], from: "healthkit")

        XCTAssertEqual(summary.stored, 1)
        let stored = try await storedBsl()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].value, 5.5, "tie breaks to the earliest native instant")
    }

    // MARK: - mg/dL → mmol/L (Req 5.5)

    func testMgPerDlInitConvertsAt18Point0182Unrounded() {
        // The init only converts; rounding to one decimal is the
        // coordinator's single rounding point.
        XCTAssertEqual(
            GlucoseSample(nativeInstant: Date(), mgPerDl: 100).mmolL,
            100 / 18.0182, accuracy: 1e-12)
        // 180.182 / 18.0182 = 10.0 exactly
        XCTAssertEqual(
            GlucoseSample(nativeInstant: Date(), mgPerDl: 180.182).mmolL, 10.0, accuracy: 1e-12)
    }

    func testMgPerDlConversionHappensBeforeDiscrepancyCheck() async throws {
        // Stored 5.0 at the mark.
        _ = try await coordinator.ingest([sample(atMs: gridMs(0), 5.0)], from: "healthkit")

        // 95.5 mg/dL → 5.3 mmol/L: |5.0 − 5.3| = 0.3 → agreeing, not discrepant.
        let agreeing = try await coordinator.ingest(
            [
                GlucoseSample(
                    nativeInstant: Date(timeIntervalSince1970: Double(gridMs(0)) / 1000),
                    mgPerDl: 95.5)
            ], from: "librelinkup")
        XCTAssertEqual(agreeing.stored, 0)
        XCTAssertEqual(agreeing.agreeing, 1)
        XCTAssertTrue(agreeing.discrepant.isEmpty)
        let tallyAfterAgreeing = await coordinator.discrepancyCount(for: "librelinkup")
        XCTAssertEqual(tallyAfterAgreeing, 0)

        // 97.3 mg/dL → 5.4 mmol/L: |5.0 − 5.4| = 0.4 > 0.3 → discrepant.
        let discrepant = try await coordinator.ingest(
            [
                GlucoseSample(
                    nativeInstant: Date(timeIntervalSince1970: Double(gridMs(0)) / 1000),
                    mgPerDl: 97.3)
            ], from: "librelinkup")
        XCTAssertEqual(discrepant.stored, 0)
        XCTAssertEqual(discrepant.discrepant.count, 1)
        XCTAssertEqual(discrepant.discrepant[0].kept, 5.0)
        XCTAssertEqual(discrepant.discrepant[0].new, 5.4)
        let tallyAfterDiscrepant = await coordinator.discrepancyCount(for: "librelinkup")
        XCTAssertEqual(tallyAfterDiscrepant, 1)

        let stored = try await storedBsl()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].value, 5.0, "stored value never modified")
    }

    // MARK: - Cross-source dedup + discrepancy tally (Req 5.1–5.4)

    func testCrossSourceDedupKeepsStoredValueAndIncrementsTally() async throws {
        // Pre-seed a screenshot-import bsl row at a grid instant.
        _ = try await store.ingestBsl(
            readings: [BslReading(timestampMs: gridMs(0), value: 5.4)],
            metadataJSON: #"{"source_hash":"sha256:abc"}"#,
            sourceHash: "shot1", filename: "a.PNG")

        // Coordinator-ingest at the same instant, > 0.3 mmol/L apart.
        let summary = try await coordinator.ingest(
            [sample(atMs: gridMs(0), 6.0)], from: "healthkit")

        XCTAssertEqual(summary.stored, 0, "keep-first: nothing stored at a covered instant")
        XCTAssertEqual(summary.discrepant.count, 1)
        let tally = await coordinator.discrepancyCount(for: "healthkit")
        XCTAssertEqual(tally, 1, "in-session tally incremented")

        let stored = try await storedBsl()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].value, 5.4, "stored value unchanged")
    }

    // MARK: - Ack semantics (Decision 7)

    func testThrowingStoreRethrowsSoSourceKeepsItsCursor() async {
        let coordinator = IngestionCoordinator(store: ThrowingPersistenceStore())
        do {
            _ = try await coordinator.ingest([sample(atMs: gridMs(0), 5.0)], from: "healthkit")
            XCTFail("expected the store error to rethrow")
        } catch is ThrowingPersistenceStore.WriteFailed {
            // expected — the caller must not advance its cursor
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - Throwing store stub

// Minimal PersistenceStore conformance whose ingestLiveBsl always throws —
// proves the coordinator rethrows rather than swallowing write failures.
// Everything else is unreachable from the coordinator.
private struct ThrowingPersistenceStore: PersistenceStore {
    struct WriteFailed: Error {}

    func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary {
        throw WriteFailed()
    }

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
    var eventsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
    func isImageProcessed(hash: String) async throws -> Bool {
        fatalError("unused")
    }
    func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
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
}
