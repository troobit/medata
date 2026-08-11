import Foundation
import GRDB
import PortableContracts
import XCTest
@testable import Persistence

// Tests for GRDBPersistenceStore against the event-log schema
// (specs/data/event-log-schema/design.md). Each meal is one row in `events` with
// event_type='meal'. `meals` and `meal_classes` are gone.

final class PersistenceTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Schema created on first launch

    func testSchemaCreatedOnFirstLaunch() throws {
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("events"), "events table must exist")
            XCTAssertTrue(tables.contains("meal_artefacts"))
            XCTAssertTrue(tables.contains("corrections"))
            XCTAssertTrue(tables.contains("meta"))
            XCTAssertFalse(tables.contains("meals"), "legacy meals table must not be created")
            XCTAssertFalse(tables.contains("meal_classes"), "legacy meal_classes table must not be created")
        }
    }

    func testEventsTableColumns() throws {
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(columns.contains("id"))
            XCTAssertTrue(columns.contains("timestamp"))
            XCTAssertTrue(columns.contains("event_type"))
            XCTAssertTrue(columns.contains("value"))
            XCTAssertTrue(columns.contains("metadata"))
        }
    }

    func testEventsTimestampIndexExists() throws {
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let indices = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='events'"
            )
            XCTAssertTrue(indices.contains("events_timestamp"),
                          "events_timestamp index must exist")
        }
    }

    // Version 6 adds estimation_outcomes (specs/estimation/snaq-parity,
    // design "Data Models"); version 5 added quick_presets
    // (specs/data/manual-carb-intake), matching the processed_images/v4
    // precedent (specs/data/libre-ingestion Decision 4).
    func testSchemaVersionIsSix() throws {
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let version = try String.fetchOne(
                db,
                sql: "SELECT v FROM meta WHERE k = 'schema_version'"
            )
            XCTAssertEqual(version, "7")
        }
    }

    // MARK: - Save → reload round-trip

    func testSaveAndReloadRoundTrip() async throws {
        let original = makeMealRecord()
        try await store.save(original, artefacts: [])
        let reloaded = try await store.meal(id: original.id)
        XCTAssertEqual(reloaded.id, original.id)
        XCTAssertEqual(reloaded.capturePath, original.capturePath)
        XCTAssertEqual(reloaded.databaseEdition, original.databaseEdition)
        XCTAssertEqual(reloaded.paletteVersion, original.paletteVersion)
        XCTAssertEqual(reloaded.photoAssetID, original.photoAssetID)
        XCTAssertEqual(reloaded.segmenterSource, original.segmenterSource)
        XCTAssertEqual(reloaded.macros.totalCarbsG, original.macros.totalCarbsG, accuracy: 1e-4)
        XCTAssertEqual(reloaded.confidence.sigmaMeal, original.confidence.sigmaMeal, accuracy: 1e-6)
    }

    // MARK: - value and timestamp columns populated at write time

    func testValueAndTimestampPopulated() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = makeMealRecord(createdAt: createdAt, totalCarbsG: 42.5)
        try await store.save(record, artefacts: [])

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT event_type, value, timestamp FROM events WHERE id = ?",
                arguments: [record.id.uuidString]
            ) else { return XCTFail("event row not found") }
            let eventType: String = row["event_type"]
            XCTAssertEqual(eventType, EventType.meal)
            let value: Double = row["value"]
            XCTAssertEqual(value, Double(record.macros.totalCarbsG), accuracy: 1e-4)
            let timestamp: Int64 = row["timestamp"]
            XCTAssertEqual(timestamp, Int64(createdAt.timeIntervalSince1970 * 1000))
        }
    }

    // MARK: - metadata column carries verbatim record + palette_version

    func testMetadataColumnCarriesVerbatimRecordAndPalette() async throws {
        let original = makeMealRecord()
        try await store.save(original, artefacts: [])

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [original.id.uuidString]
            ) else { return XCTFail("event row not found") }
            let metadata: String = row["metadata"]
            // Decision 31 invariant: the inner `record` JSON string is
            // byte-identical to original.pb.jsonString().
            let parsed = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
            )
            let recordJSON = try XCTUnwrap(parsed["record"] as? String)
            let palette = try XCTUnwrap(parsed["palette_version"] as? String)
            XCTAssertEqual(palette, original.paletteVersion)
            XCTAssertEqual(Data(recordJSON.utf8),
                           Data(try original.pb.jsonString().utf8))
        }
    }

    // MARK: - allMeals ordering

    func testAllMealsReturnsRowsSortedByTimestampDescending() async throws {
        let now = Date()
        let older = makeMealRecord(createdAt: now.addingTimeInterval(-3600))
        let newer = makeMealRecord(createdAt: now)
        try await store.save(older, artefacts: [])
        try await store.save(newer, artefacts: [])

        let result = try await store.allMeals()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, newer.id)
        XCTAssertEqual(result[1].id, older.id)
    }

    func testAllMealsSecondarySortByIdAscending() async throws {
        // Same timestamp → fall back to id ASC for determinism.
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        // Build two UUIDs and find their natural ordering by uuidString.
        let a = makeMealRecord(createdAt: t)
        let b = makeMealRecord(createdAt: t)
        try await store.save(a, artefacts: [])
        try await store.save(b, artefacts: [])

        let result = try await store.allMeals()
        XCTAssertEqual(result.count, 2)
        // Both rows share `timestamp`, so the order is id ASC.
        let expectedFirst = a.id.uuidString < b.id.uuidString ? a.id : b.id
        let expectedSecond = expectedFirst == a.id ? b.id : a.id
        XCTAssertEqual(result[0].id, expectedFirst)
        XCTAssertEqual(result[1].id, expectedSecond)
    }

    func testAllMealsReturnsEmptyForFreshContainer() async throws {
        let result = try await store.allMeals()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Correction append never mutates original meal event

    func testCorrectionAppendNeverMutatesOriginal() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])

        var correction = PbUserCorrection()
        correction.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        correction.correctedTotalCarbsG = 99.0
        try await store.appendCorrection(mealId: record.id, correction: correction)

        let reloaded = try await store.meal(id: record.id)
        XCTAssertNil(reloaded.userCorrection)
        XCTAssertEqual(reloaded.macros.totalCarbsG, record.macros.totalCarbsG, accuracy: 1e-4)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM corrections WHERE meal_id = ?",
                arguments: [record.id.uuidString]
            ) ?? 0
            XCTAssertEqual(count, 1)
        }
    }

    // MARK: - meal(id:) event_type filter

    func testMealForMissingIdThrowsMealNotFound() async throws {
        let missing = UUID()
        do {
            _ = try await store.meal(id: missing)
            XCTFail("expected mealNotFound")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError, .mealNotFound(missing))
        }
    }

    func testMealRejectsRowWithWrongEventType() async throws {
        // Hand-insert an event row with a non-meal event_type and the same
        // UUID. meal(id:) must report mealNotFound — the row exists but is
        // not a meal (Decision 10).
        let otherId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, 'other', NULL, '{}')
                    """,
                arguments: [otherId.uuidString, Int64(0)]
            )
        }
        do {
            _ = try await store.meal(id: otherId)
            XCTFail("expected mealNotFound for non-meal event_type")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError, .mealNotFound(otherId))
        }
    }

    // MARK: - photoAssetID round-trip

    func testPhotoAssetIDRoundTrips() async throws {
        let record = makeMealRecord(photoAssetID: "0F1A2B3C-DEAD-BEEF-CAFE-001/L0/001")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, record.photoAssetID)
    }

    func testMealWithoutPhotoAssetIDStoresEmptyString() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, "")
    }

    // MARK: - segmenterSource round-trip

    func testSegmenterSourceRoundTripsDevStub() async throws {
        let record = makeMealRecord(segmenterSource: "dev_stub")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.segmenterSource, "dev_stub")
    }

    func testSegmenterSourceRoundTripsCoreML() async throws {
        let record = makeMealRecord(segmenterSource: "coreml_v0.1")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.segmenterSource, "coreml_v0.1")
    }

    // MARK: - PbMealRecord round-trips segmenter_source through protobuf-JSON

    func testProtobufJsonRoundTripsSegmenterSource() throws {
        let record = makeMealRecord(segmenterSource: "dev_stub")
        let json = try record.jsonString()
        let reloaded = try MealRecord.from(jsonString: json, paletteVersion: record.paletteVersion)
        XCTAssertEqual(reloaded.segmenterSource, "dev_stub")
    }

    // MARK: - deleteMeal cascade

    func testDeleteMealCascadesAcrossSideTablesAndDirectory() async throws {
        let record = makeMealRecord()
        let artefact = MealArtefact(
            kind: "image", viewId: "nadir",
            filename: "nadir.image", bytesSize: 12, sha256Hex: "abc"
        )
        try await store.save(record, artefacts: [artefact])

        var correction = PbUserCorrection()
        correction.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        correction.correctedTotalCarbsG = 50.0
        try await store.appendCorrection(mealId: record.id, correction: correction)

        // Create the meals/{id} directory on disk so deleteMeal removes it.
        let artefactDir = tempDir
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(record.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artefactDir, withIntermediateDirectories: true)
        try Data([0xAA]).write(to: artefactDir.appendingPathComponent("blob.bin"))

        try await store.deleteMeal(id: record.id)

        // events row gone.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let eventCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM events WHERE id = ?",
                arguments: [record.id.uuidString]
            ) ?? -1
            XCTAssertEqual(eventCount, 0)
            let artefactCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM meal_artefacts WHERE meal_id = ?",
                arguments: [record.id.uuidString]
            ) ?? -1
            XCTAssertEqual(artefactCount, 0)
            let correctionCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM corrections WHERE meal_id = ?",
                arguments: [record.id.uuidString]
            ) ?? -1
            XCTAssertEqual(correctionCount, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: artefactDir.path))
    }

    func testDeleteMealLeavesNonMealRowsAlone() async throws {
        // Hand-insert a non-meal event with id X. deleteMeal(id: X) must not
        // delete it because the WHERE clause is gated on event_type=meal.
        let otherId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, 'other', NULL, '{}')
                    """,
                arguments: [otherId.uuidString, Int64(0)]
            )
        }
        try await store.deleteMeal(id: otherId)
        try await q.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM events WHERE id = ?",
                arguments: [otherId.uuidString]
            ) ?? -1
            XCTAssertEqual(count, 1, "non-meal row must survive deleteMeal")
        }
    }

    // MARK: - deleteArtefacts(olderThan:) derives path from event id

    func testDeleteArtefactsRemovesMealsDirectoryForOldEvents() async throws {
        let now = Date()
        let oldRecord = makeMealRecord(createdAt: now.addingTimeInterval(-60 * 24 * 60 * 60))
        let freshRecord = makeMealRecord(createdAt: now)
        try await store.save(oldRecord, artefacts: [])
        try await store.save(freshRecord, artefacts: [])

        // Build meals/{id} directories on disk for both.
        let mealsRoot = tempDir.appendingPathComponent("meals", isDirectory: true)
        for record in [oldRecord, freshRecord] {
            let dir = mealsRoot.appendingPathComponent(record.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([0xCC]).write(to: dir.appendingPathComponent("artefact.bin"))
        }

        // Sweep with a 30-day cutoff.
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        try await store.deleteArtefacts(olderThan: cutoff)

        let oldDir = mealsRoot.appendingPathComponent(oldRecord.id.uuidString)
        let freshDir = mealsRoot.appendingPathComponent(freshRecord.id.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path),
                       "old meal directory should be swept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDir.path),
                      "fresh meal directory must survive")
    }

    func testDeleteArtefactsDoesNotReadArtefactsDirColumn() async throws {
        // Sanity: the new schema has no `artefacts_dir` column. Confirm by
        // PRAGMA — if a future change reintroduces it this test fails loudly.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(events)")
                .compactMap { $0["name"] as String? }
            XCTAssertFalse(columns.contains("artefacts_dir"))
        }
    }

    // MARK: - updatePhotoAssetID byte-identity + eventsDidChange tick

    func testUpdatePhotoAssetIDPreservesAllOtherFieldsByteIdentical() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])

        let q = try DatabaseQueue(path: dbURL.path)
        // Capture metadata before update.
        let before: String = try await q.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [record.id.uuidString]
            )!["metadata"]
        }

        try await store.updatePhotoAssetID(
            mealId: record.id,
            photoAssetID: "PHASSET-NEW-XYZ"
        )

        let after: String = try await q.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [record.id.uuidString]
            )!["metadata"]
        }

        // Extract inner `record` from both and decode through PbMealRecord.
        let beforeRecord = try extractInnerRecord(from: before)
        let afterRecord = try extractInnerRecord(from: after)
        let beforePb = try PbMealRecord(jsonString: beforeRecord)
        let afterPb = try PbMealRecord(jsonString: afterRecord)

        XCTAssertEqual(afterPb.photoAssetID, "PHASSET-NEW-XYZ")
        XCTAssertNotEqual(beforePb.photoAssetID, afterPb.photoAssetID)

        // Every other PbMealRecord field must be equal — explicit check rather
        // than a byte diff because the JSON-string round-trip via PbMealRecord
        // is the canonical encoder.
        XCTAssertEqual(beforePb.id, afterPb.id)
        XCTAssertEqual(beforePb.createdAtMs, afterPb.createdAtMs)
        XCTAssertEqual(beforePb.capturePath, afterPb.capturePath)
        XCTAssertEqual(beforePb.databaseEdition, afterPb.databaseEdition)
        XCTAssertEqual(beforePb.segmenterSource, afterPb.segmenterSource)
        XCTAssertEqual(beforePb.frames, afterPb.frames)
        XCTAssertEqual(beforePb.calibration, afterPb.calibration)
        XCTAssertEqual(beforePb.supportPlane, afterPb.supportPlane)
        XCTAssertEqual(beforePb.scale, afterPb.scale)
        XCTAssertEqual(beforePb.volumes, afterPb.volumes)
        XCTAssertEqual(beforePb.macros, afterPb.macros)
        XCTAssertEqual(beforePb.confidence, afterPb.confidence)
        XCTAssertEqual(beforePb.perClassCalibration, afterPb.perClassCalibration)

        // palette_version is preserved in the outer envelope.
        let beforeOuter = try JSONSerialization.jsonObject(with: Data(before.utf8)) as? [String: Any]
        let afterOuter = try JSONSerialization.jsonObject(with: Data(after.utf8)) as? [String: Any]
        XCTAssertEqual(beforeOuter?["palette_version"] as? String,
                       afterOuter?["palette_version"] as? String)
    }

    func testUpdatePhotoAssetIDIsVisibleViaMeal() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])
        try await store.updatePhotoAssetID(
            mealId: record.id,
            photoAssetID: "PHASSET-LOCAL-ID-12345"
        )
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, "PHASSET-LOCAL-ID-12345")
    }

    func testUpdatePhotoAssetIDFiresEventsDidChange() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])

        let stream = store.eventsDidChange
        let received = Task<Bool, Never> {
            for await _ in stream { return true }
            return false
        }
        await Task.yield()
        try await store.updatePhotoAssetID(mealId: record.id, photoAssetID: "PHASSET-AB")
        let got = try await awaitWithTimeout(seconds: 2, received)
        XCTAssertTrue(got, "eventsDidChange must fire after updatePhotoAssetID")
    }

    func testUpdatePhotoAssetIDThrowsForUnknownId() async throws {
        let missing = UUID()
        do {
            try await store.updatePhotoAssetID(mealId: missing, photoAssetID: "X")
            XCTFail("expected mealNotFound")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError, .mealNotFound(missing))
        }
    }

    // MARK: - events(in:type:)

    func testEventsInRangeIsBothBoundsInclusiveAndSortedAscendingByTimestampThenId() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let early = makeMealRecord(createdAt: t.addingTimeInterval(-3600))
        let middle = makeMealRecord(createdAt: t)
        let late = makeMealRecord(createdAt: t.addingTimeInterval(3600))
        try await store.save(early, artefacts: [])
        try await store.save(middle, artefacts: [])
        try await store.save(late, artefacts: [])

        // Query [t-1h, t+1h] — both endpoints inclusive.
        let allInRange = try await store.events(
            in: t.addingTimeInterval(-3600)...t.addingTimeInterval(3600),
            type: nil
        )
        XCTAssertEqual(allInRange.count, 3)
        XCTAssertEqual(allInRange.map { $0.id }, [early.id, middle.id, late.id])

        // Tight range [t-30m, t+30m] — only `middle`.
        let middleOnly = try await store.events(
            in: t.addingTimeInterval(-1800)...t.addingTimeInterval(1800),
            type: nil
        )
        XCTAssertEqual(middleOnly.count, 1)
        XCTAssertEqual(middleOnly[0].id, middle.id)
    }

    func testEventsInRangeSecondarySortByIdAscending() async throws {
        // Two rows at the exact same timestamp → fall back to id ASC.
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeMealRecord(createdAt: t)
        let b = makeMealRecord(createdAt: t)
        try await store.save(a, artefacts: [])
        try await store.save(b, artefacts: [])

        let result = try await store.events(in: t...t, type: nil)
        XCTAssertEqual(result.count, 2)
        let expectedFirst = a.id.uuidString < b.id.uuidString ? a.id : b.id
        let expectedSecond = expectedFirst == a.id ? b.id : a.id
        XCTAssertEqual(result[0].id, expectedFirst)
        XCTAssertEqual(result[1].id, expectedSecond)
    }

    func testEventsInRangeFiltersByTypeWhenNonNil() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = makeMealRecord(createdAt: t)
        try await store.save(meal, artefacts: [])

        // Hand-insert a synthetic non-meal row inside the range.
        let otherId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, 'other', NULL, '{}')
                    """,
                arguments: [otherId.uuidString, Int64(t.timeIntervalSince1970 * 1000)]
            )
        }

        let mealOnly = try await store.events(
            in: t.addingTimeInterval(-3600)...t.addingTimeInterval(3600),
            type: EventType.meal
        )
        XCTAssertEqual(mealOnly.count, 1)
        XCTAssertEqual(mealOnly[0].id, meal.id)

        let all = try await store.events(
            in: t.addingTimeInterval(-3600)...t.addingTimeInterval(3600),
            type: nil
        )
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == meal.id })
        XCTAssertTrue(all.contains { $0.id == otherId })
    }

    func testEventsInRangeFailsFastOnCorruptMetadata() async throws {
        // Hand-insert a row with malformed JSON metadata. The fail-fast
        // contract says the whole call throws corruptRecord (not "skip the
        // bad row").
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, 'meal', 0.0, '{not-json')
                    """,
                arguments: [UUID().uuidString, Int64(t.timeIntervalSince1970 * 1000)]
            )
        }
        do {
            _ = try await store.events(
                in: t.addingTimeInterval(-3600)...t.addingTimeInterval(3600),
                type: nil
            )
            XCTFail("expected corruptRecord")
        } catch let err as Persistence.PersistenceError {
            guard case .corruptRecord = err else {
                return XCTFail("expected corruptRecord, got \(err)")
            }
        }
    }

    func testEventsInRangePopulatesValueAndTypeFromRow() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = makeMealRecord(createdAt: t, totalCarbsG: 42.5)
        try await store.save(meal, artefacts: [])

        let result = try await store.events(in: t...t, type: EventType.meal)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].eventType, EventType.meal)
        XCTAssertEqual(result[0].value ?? -1, 42.5, accuracy: 1e-4)
        XCTAssertEqual(result[0].id, meal.id)
    }

    // MARK: - corrections(for:) — Req 4.4

    func testCorrectionsForReturnsAppendLogOrderedByCreatedAtAscending() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])

        var first = PbUserCorrection()
        first.createdAtMs = 1_000
        first.correctedTotalCarbsG = 10.0
        var second = PbUserCorrection()
        second.createdAtMs = 2_000
        second.correctedTotalCarbsG = 20.0
        // Append out of chronological order — the query MUST re-sort by created_at.
        try await store.appendCorrection(mealId: record.id, correction: second)
        try await store.appendCorrection(mealId: record.id, correction: first)

        let result = try await store.corrections(for: record.id)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].createdAtMs, 1_000)
        XCTAssertEqual(result[0].correctedTotalCarbsG, 10.0, accuracy: 1e-4)
        XCTAssertEqual(result[1].createdAtMs, 2_000)
        XCTAssertEqual(result[1].correctedTotalCarbsG, 20.0, accuracy: 1e-4)
    }

    func testCorrectionsForReturnsEmptyArrayWhenNone() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])
        let result = try await store.corrections(for: record.id)
        XCTAssertTrue(result.isEmpty)
    }

    func testAppendCorrectionLeavesMealEventValueUnchanged() async throws {
        let record = makeMealRecord(totalCarbsG: 33.6)
        try await store.save(record, artefacts: [])

        var correction = PbUserCorrection()
        correction.createdAtMs = 1_000
        correction.correctedTotalCarbsG = 99.0
        try await store.appendCorrection(mealId: record.id, correction: correction)

        // Meal event's value column is untouched.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let value: Double? = try Double.fetchOne(
                db,
                sql: "SELECT value FROM events WHERE id = ?",
                arguments: [record.id.uuidString]
            )
            XCTAssertEqual(value ?? -1, 33.6, accuracy: 1e-4,
                           "meal event value must remain the uncorrected estimate (Req 4.4)")
        }
        // And meal(id:) still reflects the original macros.
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.macros.totalCarbsG, 33.6, accuracy: 1e-4)
    }

    // UI Design Handoff 00, Decision 18: appendCorrection now emits exactly one
    // eventsDidChange tick so Data rows and Meal overview learn a correction
    // landed without polling. This reverses the event-log-schema-era behaviour.
    func testAppendCorrectionYieldsEventsDidChange() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])

        // Count ticks via an actor. Subscribing after the save means the save's
        // own tick is not seen; only the correction's should register.
        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        var correction = PbUserCorrection()
        correction.createdAtMs = 1_000
        correction.correctedTotalCarbsG = 50.0
        try await store.appendCorrection(mealId: record.id, correction: correction)

        // Give the broadcaster ample time to fire.
        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "appendCorrection must emit exactly one eventsDidChange tick (Decision 18)")
    }

    // MARK: - meal_artefacts rows written for each artefact

    func testArtefactsWrittenToTable() async throws {
        let record = makeMealRecord()
        let artefacts = [
            MealArtefact(kind: "image", viewId: "nadir", filename: "nadir.image", bytesSize: 12345, sha256Hex: "abc"),
            MealArtefact(kind: "mask", viewId: "nadir", filename: "nadir.mask", bytesSize: 6789, sha256Hex: "def")
        ]
        try await store.save(record, artefacts: artefacts)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM meal_artefacts WHERE meal_id = ?",
                arguments: [record.id.uuidString]
            )
            XCTAssertEqual(rows.count, 2)
        }
    }
}

// MARK: - Helpers

private func extractInnerRecord(from metadata: String) throws -> String {
    guard let outer = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any],
          let record = outer["record"] as? String else {
        throw NSError(domain: "PersistenceTestsHelpers", code: 1)
    }
    return record
}

private enum TimeoutError: Error { case timeout }

private actor TickCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}

private func awaitWithTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ task: Task<T, Never>
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await task.value }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            task.cancel()
            throw TimeoutError.timeout
        }
        guard let first = try await group.next() else { throw TimeoutError.timeout }
        group.cancelAll()
        return first
    }
}

// MARK: - Fixtures

private func makeMealRecord(
    createdAt: Date = Date(),
    classId: String = "white_rice",
    betaStatus: PbBetaCalibrationStatus = .calibrated,
    totalCarbsG: Float = 33.6,
    sigmaMeal: Float = 0.82,
    photoAssetID: String = "",
    segmenterSource: String = ""
) -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = sigmaMeal
    confidence.sigmaScale = 0.90
    confidence.sigmaSeg = 0.85

    var perClassEntry = PbPerClassMacros()
    perClassEntry.volumeCm3 = 100.0
    perClassEntry.massG = 105.0
    perClassEntry.carbsG = totalCarbsG
    perClassEntry.betaUsed = 0.9
    perClassEntry.betaStatus = betaStatus

    var macros = PbMacroResult()
    macros.totalCarbsG = totalCarbsG
    macros.perClass = [classId: perClassEntry]

    var volumes = PbVolumeResult()
    volumes.perClassVolumesCm3 = [classId: 100.0]

    return MealRecord(
        createdAt: createdAt,
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v0",
        photoAssetID: photoAssetID,
        segmenterSource: segmenterSource,
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: volumes,
        macros: macros,
        confidence: confidence,
        perClassCalibration: [classId: betaStatus]
    )
}
