import Foundation
import GRDB
import PortableContracts
import XCTest
@testable import Persistence

// Tests for GRDBPersistenceStore per design §4.1 / §7.1 / task 41.

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

    // MARK: - T41.1 Schema created on first launch

    func testSchemaCreatedOnFirstLaunch() throws {
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        let q = try DatabaseQueue(path: dbURL.path)
        try q.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("meals"))
            XCTAssertTrue(tables.contains("meal_classes"))
            XCTAssertTrue(tables.contains("meal_artefacts"))
            XCTAssertTrue(tables.contains("corrections"))
            XCTAssertTrue(tables.contains("meta"))
        }
    }

    // MARK: - T41.2 Save → reload → deep-equal MealRecord (Decision 31)

    func testSaveAndReloadRoundTrip() async throws {
        let original = makeMealRecord()
        try await store.save(original, artefacts: [])
        let reloaded = try await store.meal(id: original.id)
        XCTAssertEqual(reloaded.id, original.id)
        XCTAssertEqual(reloaded.capturePath, original.capturePath)
        XCTAssertEqual(reloaded.databaseEdition, original.databaseEdition)
        XCTAssertEqual(reloaded.paletteVersion, original.paletteVersion)
        XCTAssertEqual(reloaded.macros.totalCarbsG, original.macros.totalCarbsG, accuracy: 1e-4)
        XCTAssertEqual(reloaded.confidence.sigmaMeal, original.confidence.sigmaMeal, accuracy: 1e-6)
    }

    // MARK: - T41.3 Denormalized columns populated at write time

    func testDenormalizedColumnsPopulated() async throws {
        let record = makeMealRecord(totalCarbsG: 42.5, sigmaMeal: 0.75)
        try await store.save(record, artefacts: [])

        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM meals WHERE id = ?", arguments: [record.id.uuidString]
            ) else { return XCTFail("meal row not found") }
            let capturePath: String = row["capture_path"]
            XCTAssertEqual(capturePath, record.capturePath.rawValue)
            let edition: String = row["database_edition"]
            XCTAssertEqual(edition, record.databaseEdition)
            let palette: String = row["palette_version"]
            XCTAssertEqual(palette, record.paletteVersion)
            let sigma: Double = row["sigma_meal"]
            XCTAssertEqual(sigma, Double(record.confidence.sigmaMeal), accuracy: 1e-6)
            let carbs: Double = row["total_carbs_g"]
            XCTAssertEqual(carbs, Double(record.macros.totalCarbsG), accuracy: 1e-4)
        }
    }

    // MARK: - T41.4 meal_classes join table populated per class

    func testMealClassesJoinTablePopulated() async throws {
        let record = makeMealRecord(classId: "white_rice", betaStatus: .calibrated)
        try await store.save(record, artefacts: [])

        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM meal_classes WHERE meal_id = ?",
                arguments: [record.id.uuidString]
            )
            XCTAssertEqual(rows.count, 1)
            let classId: String = rows[0]["class_id"]
            XCTAssertEqual(classId, "white_rice")
            let status: String = rows[0]["beta_status"]
            XCTAssertEqual(status, "calibrated")
        }
    }

    // MARK: - T41.5 Correction append never mutates original (Req 14.2)

    func testCorrectionAppendNeverMutatesOriginal() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])

        var correction = PbUserCorrection()
        correction.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        correction.correctedTotalCarbsG = 99.0
        try await store.appendCorrection(mealId: record.id, correction: correction)

        // Original record_json must be unchanged.
        let reloaded = try await store.meal(id: record.id)
        XCTAssertNil(reloaded.userCorrection)
        XCTAssertEqual(reloaded.macros.totalCarbsG, record.macros.totalCarbsG, accuracy: 1e-4)

        // Correction is in its own table.
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
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

    // MARK: - T73 PhotoKit asset identifier round-trips through JSON BLOB and column

    func testPhotoAssetIDRoundTrips() async throws {
        let record = makeMealRecord(photoAssetID: "0F1A2B3C-DEAD-BEEF-CAFE-00112233445/L0/001")
        try await store.save(record, artefacts: [])

        // Reload from JSON BLOB
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, record.photoAssetID)

        // Denormalised column matches
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT photo_asset_id FROM meals WHERE id = ?",
                arguments: [record.id.uuidString]
            ) else { return XCTFail("meal row not found") }
            let assetID: String = row["photo_asset_id"]
            XCTAssertEqual(assetID, record.photoAssetID)
        }
    }

    // MARK: - T73 PhotoKit denied path stores empty string and reload succeeds

    func testMealWithoutPhotoAssetIDStoresEmptyString() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, "")
    }

    // MARK: - T73 updatePhotoAssetID stamps an existing meal

    func testUpdatePhotoAssetIDStampsExistingMeal() async throws {
        let record = makeMealRecord(photoAssetID: "")
        try await store.save(record, artefacts: [])

        try await store.updatePhotoAssetID(
            mealId: record.id,
            photoAssetID: "PHASSET-LOCAL-ID-12345"
        )

        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.photoAssetID, "PHASSET-LOCAL-ID-12345")
    }

    // MARK: - T82 segmenterSource round-trips through JSON BLOB and column

    func testSegmenterSourceRoundTripsDevStub() async throws {
        let record = makeMealRecord(segmenterSource: "dev_stub")
        try await store.save(record, artefacts: [])

        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.segmenterSource, "dev_stub")

        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT segmenter_source FROM meals WHERE id = ?",
                arguments: [record.id.uuidString]
            ) else { return XCTFail("meal row not found") }
            let source: String = row["segmenter_source"]
            XCTAssertEqual(source, "dev_stub")
        }
    }

    func testSegmenterSourceRoundTripsCoreML() async throws {
        let record = makeMealRecord(segmenterSource: "coreml_v0.1")
        try await store.save(record, artefacts: [])
        let reloaded = try await store.meal(id: record.id)
        XCTAssertEqual(reloaded.segmenterSource, "coreml_v0.1")
    }

    // MARK: - T82 Existing DB without segmenter_source column gets migrated

    func testMigrationAddsSegmenterSourceColumnWithEmptyStringDefault() async throws {
        // Build a legacy DB (pre-task-82) that lacks the segmenter_source column,
        // then re-open it through GRDBPersistenceStore and verify migration runs.
        let legacyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyDB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        let legacyURL = legacyDir.appendingPathComponent("meals.sqlite")

        // Create the v2-pre-task-82 schema (no segmenter_source column) and
        // insert a representative row.
        let q = try DatabaseQueue(path: legacyURL.path)
        try await q.write { db in
            try db.execute(sql: """
                CREATE TABLE meals (
                    id               TEXT PRIMARY KEY,
                    created_at       INTEGER NOT NULL,
                    capture_path     TEXT NOT NULL,
                    database_edition TEXT NOT NULL,
                    palette_version  TEXT NOT NULL,
                    sigma_meal       REAL NOT NULL,
                    total_carbs_g    REAL NOT NULL,
                    photo_asset_id   TEXT NOT NULL DEFAULT '',
                    record_json      BLOB NOT NULL,
                    artefacts_dir    TEXT NOT NULL
                );
                """)
            try db.execute(
                sql: """
                    INSERT INTO meals
                        (id, created_at, capture_path, database_edition, palette_version,
                         sigma_meal, total_carbs_g, photo_asset_id, record_json, artefacts_dir)
                    VALUES ('legacy-meal-1', 0, 'single_view_lidar', 'CoFID 2024', 'v1',
                            0.8, 30.0, '', '{}', 'meals/legacy')
                    """
            )
        }

        // Re-open through GRDBPersistenceStore — migration runs.
        _ = try GRDBPersistenceStore(dbURL: legacyURL, artefactsBaseURL: legacyDir)

        try await q.read { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(meals)")
                .compactMap { $0["name"] as String? }
            XCTAssertTrue(columns.contains("segmenter_source"),
                          "migration should add segmenter_source column")
            // Pre-existing rows default to empty string (provenance unknown).
            let source: String? = try String.fetchOne(
                db,
                sql: "SELECT segmenter_source FROM meals WHERE id = 'legacy-meal-1'"
            )
            XCTAssertEqual(source, "")
        }
    }

    // MARK: - T82 PbMealRecord round-trips segmenter_source through protobuf-JSON

    func testProtobufJsonRoundTripsSegmenterSource() throws {
        let record = makeMealRecord(segmenterSource: "dev_stub")
        let json = try record.jsonString()
        let reloaded = try MealRecord.from(jsonString: json, paletteVersion: record.paletteVersion)
        XCTAssertEqual(reloaded.segmenterSource, "dev_stub")
    }

    // MARK: - T41.6 meal_artefacts rows written for each artefact

    func testArtefactsWrittenToTable() async throws {
        let record = makeMealRecord()
        let artefacts = [
            MealArtefact(kind: "image", viewId: "nadir", filename: "nadir.image", bytesSize: 12345, sha256Hex: "abc"),
            MealArtefact(kind: "mask", viewId: "nadir", filename: "nadir.mask", bytesSize: 6789, sha256Hex: "def")
        ]
        try await store.save(record, artefacts: artefacts)

        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
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

// MARK: - Fixtures

private func makeMealRecord(
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
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v1",
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
