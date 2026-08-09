import Foundation
import GRDB
import PortableContracts
import XCTest

@testable import Persistence

// Tests for the bsl ingest surface (specs/data/libre-ingestion Reqs 4, 5):
// keep-first merge, processed_images dedup, transactional atomicity, and the
// notify-once-per-batch contract.
final class BslIngestTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BslIngestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var dbURL: URL { tempDir.appendingPathComponent("meals.sqlite") }

    private let metadataJSON = #"{"source_hash":"sha256:abc","source_file":"IMG_0570.PNG","view":"home8h","date":"2026-07-02","date_source":"asset","timezone":"Europe/Dublin","axis_range":[3,21]}"#

    private func reading(_ minute: Int, _ value: Double) -> BslReading {
        // Base 2026-07-02T00:00Z, 5-minute grid.
        BslReading(timestampMs: 1_782_950_400_000 + Int64(minute) * 60_000, value: value)
    }

    // MARK: - Schema (Req 4.5 supporting table)

    // Schema is now v5 (specs/data/manual-carb-intake adds quick_presets);
    // processed_images (v4) must still exist per the no-DDL-on-legacy-tables
    // convention (Decision 10) — only the version stamp advances.
    func testProcessedImagesTableAndSchemaVersion() throws {
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            XCTAssertTrue(tables.contains("processed_images"))
            let version = try String.fetchOne(
                db, sql: "SELECT v FROM meta WHERE k = 'schema_version'")
            XCTAssertEqual(version, "7")
        }
    }

    // MARK: - Basic ingest (Req 4.1, 4.2, 5.1)

    func testIngestStoresReadingsAndMarksProcessed() async throws {
        let readings = [reading(0, 5.4), reading(5, 5.6), reading(10, 5.9)]
        let wasProcessed = try await store.isImageProcessed(hash: "abc")
        XCTAssertFalse(wasProcessed)

        let summary = try await store.ingestBsl(
            readings: readings, metadataJSON: metadataJSON,
            sourceHash: "abc", filename: "IMG_0570.PNG")

        XCTAssertEqual(summary.extracted, 3)
        XCTAssertEqual(summary.stored, 3)
        XCTAssertEqual(summary.skippedExisting, 0)
        XCTAssertEqual(summary.agreeing, 0)
        XCTAssertTrue(summary.discrepant.isEmpty)

        let isProcessed = try await store.isImageProcessed(hash: "abc")
        XCTAssertTrue(isProcessed)

        let start = Date(timeIntervalSince1970: 1_782_950_400)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.value), [5.4, 5.6, 5.9])
        XCTAssertEqual(events[0].metadata, metadataJSON)
        // Chronological, fresh UUIDs, correct type.
        XCTAssertEqual(events.map(\.eventType), [EventType.bsl, EventType.bsl, EventType.bsl])
        XCTAssertEqual(Set(events.map(\.id)).count, 3)
    }

    // MARK: - Keep-first merge (Req 5.2, 5.3, 5.4)

    func testKeepFirstMergeClassifiesOverlaps() async throws {
        _ = try await store.ingestBsl(
            readings: [reading(0, 5.4), reading(5, 5.6), reading(10, 5.9)],
            metadataJSON: metadataJSON, sourceHash: "first", filename: "a.PNG")

        // Overlaps: minute 5 agrees (same value), minute 10 discrepant
        // (6.4 vs 5.9 > 0.3); minute 15 is new.
        let summary = try await store.ingestBsl(
            readings: [reading(5, 5.6), reading(10, 6.4), reading(15, 6.0)],
            metadataJSON: metadataJSON, sourceHash: "second", filename: "b.PNG")

        XCTAssertEqual(summary.extracted, 3)
        XCTAssertEqual(summary.stored, 1)
        XCTAssertEqual(summary.skippedExisting, 2)
        XCTAssertEqual(summary.agreeing, 1)
        XCTAssertEqual(summary.discrepant.count, 1)
        XCTAssertEqual(summary.discrepant[0].kept, 5.9)
        XCTAssertEqual(summary.discrepant[0].new, 6.4)

        // Stored values unchanged; only the new timestamp appended.
        let start = Date(timeIntervalSince1970: 1_782_950_400)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.map(\.value), [5.4, 5.6, 5.9, 6.0])
    }

    func testExactlyPointThreeDifferenceAgrees() async throws {
        // One-decimal values 9.4 vs 9.1 differ by 0.3 in binary floating
        // point slightly above 0.3; the reference float tolerance keeps them
        // "agreeing" (Req 5.3 boundary).
        _ = try await store.ingestBsl(
            readings: [reading(0, 9.4)], metadataJSON: metadataJSON,
            sourceHash: "x1", filename: "x1.PNG")
        let summary = try await store.ingestBsl(
            readings: [reading(0, 9.1)], metadataJSON: metadataJSON,
            sourceHash: "x2", filename: "x2.PNG")
        XCTAssertEqual(summary.agreeing, 1)
        XCTAssertTrue(summary.discrepant.isEmpty)
    }

    // MARK: - Atomicity (Req 4.5)

    func testDuplicateHashRollsBackWholeBatch() async throws {
        _ = try await store.ingestBsl(
            readings: [reading(0, 5.4)], metadataJSON: metadataJSON,
            sourceHash: "dup", filename: "a.PNG")

        // Calling ingest again with the same hash (a caller bug — the dedup
        // check comes first in the flow) violates the processed_images PK.
        // The whole transaction must roll back: no partial event rows.
        do {
            _ = try await store.ingestBsl(
                readings: [reading(30, 7.0), reading(35, 7.2)],
                metadataJSON: metadataJSON, sourceHash: "dup", filename: "b.PNG")
            XCTFail("expected duplicate-hash ingest to throw")
        } catch {
            // expected
        }

        let start = Date(timeIntervalSince1970: 1_782_950_400)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.count, 1, "rolled-back batch must leave no rows")
    }

    // MARK: - Notification (Req 4.4)

    func testIngestNotifiesOnceWhenRowsStored() async throws {
        let counter = TickBox()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        _ = try await store.ingestBsl(
            readings: [reading(0, 5.4), reading(5, 5.6)],
            metadataJSON: metadataJSON, sourceHash: "n1", filename: "a.PNG")
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterStore = await counter.get()
        XCTAssertEqual(afterStore, 1, "one tick per batch, not per row")

        // Fully-overlapping batch stores nothing -> no tick.
        _ = try await store.ingestBsl(
            readings: [reading(0, 5.4)],
            metadataJSON: metadataJSON, sourceHash: "n2", filename: "b.PNG")
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterOverlap = await counter.get()
        observer.cancel()
        XCTAssertEqual(afterOverlap, 1, "no tick when nothing was stored")
    }

    // MARK: - Meal isolation (Req 4.3)

    func testIngestLeavesMealRowsUntouched() async throws {
        let meal = makeBslTestMealRecord()
        try await store.save(meal, artefacts: [])
        let mealMetadataBefore: String = try await metadataOf(id: meal.id)

        _ = try await store.ingestBsl(
            readings: [reading(0, 5.4)], metadataJSON: metadataJSON,
            sourceHash: "m1", filename: "a.PNG")

        let meals = try await store.allMeals()
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].id, meal.id)
        let mealMetadataAfter: String = try await metadataOf(id: meal.id)
        XCTAssertEqual(mealMetadataAfter, mealMetadataBefore)

        // deleteMeal removes only the meal; bsl rows survive.
        try await store.deleteMeal(id: meal.id)
        let start = Date(timeIntervalSince1970: 1_782_950_400)
        let bsl = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(bsl.count, 1)
    }

    private func metadataOf(id: UUID) async throws -> String {
        let q = try DatabaseQueue(path: dbURL.path)
        return try await q.read { db in
            try String.fetchOne(
                db, sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [id.uuidString]) ?? ""
        }
    }
}

// MARK: - Helpers

private actor TickBox {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}

private func makeBslTestMealRecord() -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.82

    var perClassEntry = PbPerClassMacros()
    perClassEntry.volumeCm3 = 100.0
    perClassEntry.massG = 105.0
    perClassEntry.carbsG = 33.6
    perClassEntry.betaUsed = 0.9
    perClassEntry.betaStatus = .calibrated

    var macros = PbMacroResult()
    macros.totalCarbsG = 33.6
    macros.perClass = ["white_rice": perClassEntry]

    var volumes = PbVolumeResult()
    volumes.perClassVolumesCm3 = ["white_rice": 100.0]

    return MealRecord(
        createdAt: Date(),
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v1",
        photoAssetID: "",
        segmenterSource: "",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: volumes,
        macros: macros,
        confidence: confidence,
        perClassCalibration: ["white_rice": .calibrated]
    )
}
