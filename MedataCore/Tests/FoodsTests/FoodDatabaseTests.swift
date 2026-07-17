import Foundation
import GRDB
import XCTest
@testable import Foods

// Tests for GRDBFoodDatabase per design §3.7 / §4.1 / Decision 39.
// CoFID + AFCD are both bundled in v1; CoFID wins for class IDs in both.

final class FoodDatabaseTests: XCTestCase {

    // MARK: - helpers

    private var tempFiles: [String] = []

    override func tearDown() {
        for path in tempFiles {
            try? FileManager.default.removeItem(atPath: path)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    private func tempPath(suffix: String = ".sqlite") -> String {
        let p = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)\(suffix)").path
        tempFiles.append(p)
        return p
    }

    // Seed a CoFID + AFCD pair. CoFID supplies white_rice, chicken, potato_boiled.
    // AFCD supplies a subset overlap with different carb numbers plus an
    // AFCD-exclusive class (kumara) that CoFID does not list.
    private func makeCoFIDDB(at path: String) throws {
        let q = try DatabaseQueue(path: path)
        try q.write { db in
            try db.execute(sql: schemaSQL)
            try db.execute(sql: "INSERT INTO meta VALUES ('edition', 'CoFID 2024')")
            try db.execute(sql: "INSERT INTO meta VALUES ('palette_version', 'v1')")
            // white_rice injects a calibrated + device-verified row so the
            // beta_provenance / device_verified read path is observable
            // (nutrition5k-calibration Req 8.1 flag injection).
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('white_rice', 'White rice', 1.05, 580.0, 32.0, 2.7, 0.3, 0.1,
                     0.9, 'calibrated', 'CoFID 2024', 'CoFID 2024',
                     'n5k_single_dominant', 1)
            """)
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('chicken', 'Chicken breast', 0.9, 736.0, 0.0, 31.0, 3.6, 0.0,
                     1.0, 'uncalibrated_unity', 'FAO_DENS', 'CoFID 2024',
                     'none', 0)
            """)
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('potato_boiled', 'Boiled potato', 1.01, 318.0, 17.0, 1.8, 0.1, 1.1,
                     1.0, 'uncalibrated_pooled', 'FAO_DENS', 'CoFID 2024',
                     'none', 0)
            """)
            // Liquid class with NO solid_servings row — the serving lookup
            // must return nil so the app falls back (serving-adjust PRD).
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('water', 'Water (still)', 1.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                     1.0, 'uncalibrated_unity', 'CoFID 2024', 'CoFID 2024',
                     'none', 0)
            """)
            try db.execute(sql: """
                INSERT INTO solid_servings VALUES
                    ('potato_boiled', 'potato', 'potatoes', 58.0, 0.5,
                     'BDA Food Fact Sheet: Portion sizes')
            """)
        }
    }

    private func makeAFCDDB(at path: String) throws {
        let q = try DatabaseQueue(path: path)
        try q.write { db in
            try db.execute(sql: schemaSQL)
            try db.execute(sql: "INSERT INTO meta VALUES ('edition', 'AFCD 2024')")
            try db.execute(sql: "INSERT INTO meta VALUES ('palette_version', 'v1')")
            // Overlaps with CoFID — must be masked at lookup time.
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('white_rice', 'White rice (AU)', 1.10, 590.0, 30.5, 2.7, 0.3, 0.1,
                     0.95, 'calibrated', 'AFCD 2024', 'AFCD 2024',
                     'n5k_mixture', 0)
            """)
            // AFCD-exclusive class — surfaced when CoFID lacks the class.
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('kumara', 'Kumara', 0.92, 386.0, 17.0, 1.6, 0.1, 3.0,
                     1.0, 'uncalibrated_unity', 'AFCD 2024', 'AFCD 2024',
                     'gravimetric', 1)
            """)
        }
    }

    private let schemaSQL = """
        CREATE TABLE foods (
            class_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            density REAL NOT NULL,
            energy_kj_100 REAL NOT NULL,
            carbs_mono_100 REAL NOT NULL,
            protein_100 REAL NOT NULL,
            fat_100 REAL NOT NULL,
            fibre_100 REAL NOT NULL,
            beta REAL NOT NULL DEFAULT 1.0,
            beta_status TEXT NOT NULL DEFAULT 'uncalibrated_unity',
            density_source TEXT NOT NULL,
            composition_source TEXT NOT NULL,
            beta_provenance TEXT NOT NULL DEFAULT 'none',
            device_verified INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
        CREATE TABLE solid_servings (
            class_id TEXT PRIMARY KEY,
            unit_singular TEXT NOT NULL,
            unit_plural TEXT NOT NULL,
            grams_per_unit REAL NOT NULL,
            step REAL NOT NULL,
            source TEXT NOT NULL
        );
        """

    private func makePair() throws -> GRDBFoodDatabase {
        let c = tempPath(); let a = tempPath()
        try makeCoFIDDB(at: c); try makeAFCDDB(at: a)
        return try GRDBFoodDatabase(cofidPath: c, afcdPath: a)
    }

    // MARK: - CoFID-wins lookup priority (Decision 39)

    func testCoFIDWinsWhenClassPresentInBoth() throws {
        let db = try makePair()
        let entry = try XCTUnwrap(db.entry(for: "white_rice"))
        XCTAssertEqual(entry.densityGPerCm3, 1.05, accuracy: 1e-4)   // CoFID, not AFCD's 1.10
        XCTAssertEqual(entry.carbsMonoG, 32.0, accuracy: 1e-4)        // CoFID, not AFCD's 30.5
        XCTAssertEqual(entry.densitySource, "CoFID 2024")
    }

    // MARK: - Fallthrough to AFCD for AFCD-exclusive classes

    func testFallsThroughToAFCDWhenCoFIDLacksClass() throws {
        let db = try makePair()
        let entry = try XCTUnwrap(db.entry(for: "kumara"))
        XCTAssertEqual(entry.densityGPerCm3, 0.92, accuracy: 1e-4)
        XCTAssertEqual(entry.densitySource, "AFCD 2024")
    }

    // MARK: - Missing class returns nil in both DBs

    func testMissingClassReturnsNil() throws {
        let db = try makePair()
        XCTAssertNil(db.entry(for: "does_not_exist"))
    }

    // MARK: - database_edition string reflects the bundled pair

    func testVersionStringMatchesBundledPair() throws {
        let db = try makePair()
        XCTAssertEqual(db.version, "CoFID 2024 + AFCD 2024")
    }

    func testAvailableEditionsIncludesBothSources() throws {
        let db = try makePair()
        let editions = db.availableEditions()
        XCTAssertTrue(editions.contains("CoFID 2024"))
        XCTAssertTrue(editions.contains("AFCD 2024"))
        XCTAssertTrue(editions.contains("CoFID 2024 + AFCD 2024"))
    }

    // MARK: - Canonical units survive the join

    func testCanonicalUnits() throws {
        let db = try makePair()
        let entry = try XCTUnwrap(db.entry(for: "white_rice"))
        XCTAssertGreaterThan(entry.densityGPerCm3, 0.0)
        XCTAssertLessThanOrEqual(entry.densityGPerCm3, 5.0)
        XCTAssertGreaterThanOrEqual(entry.carbsMonoG, 0.0)
        XCTAssertLessThanOrEqual(entry.carbsMonoG, 100.0)
        XCTAssertGreaterThan(entry.beta, 0.0)
        XCTAssertLessThanOrEqual(entry.beta, 1.0)
    }

    // MARK: - BetaCalibrationStatus round-trips for all three values

    func testBetaCalibrationStatusRoundtrips() throws {
        let db = try makePair()
        let rice    = try XCTUnwrap(db.entry(for: "white_rice"))
        let chicken = try XCTUnwrap(db.entry(for: "chicken"))
        let potato  = try XCTUnwrap(db.entry(for: "potato_boiled"))
        XCTAssertEqual(rice.calibrationStatus,    .calibrated)
        XCTAssertEqual(chicken.calibrationStatus, .uncalibratedUnity)
        XCTAssertEqual(potato.calibrationStatus,  .uncalibratedPooled)
    }

    // MARK: - beta_provenance + device_verified read into FoodEntry
    //          (nutrition5k-calibration Req 5.4 / 8.1 banner plumbing)

    func testBetaProvenanceAndDeviceVerifiedReadIntoEntry() throws {
        let db = try makePair()
        let rice    = try XCTUnwrap(db.entry(for: "white_rice"))
        let chicken = try XCTUnwrap(db.entry(for: "chicken"))
        XCTAssertEqual(rice.betaProvenance, "n5k_single_dominant")
        XCTAssertTrue(rice.deviceVerified)
        XCTAssertEqual(chicken.betaProvenance, "none")
        XCTAssertFalse(chicken.deviceVerified)
    }

    func testBetaProvenanceAndDeviceVerifiedSurviveAFCDFallthrough() throws {
        let db = try makePair()
        let kumara = try XCTUnwrap(db.entry(for: "kumara"))
        XCTAssertEqual(kumara.betaProvenance, "gravimetric")
        XCTAssertTrue(kumara.deviceVerified)
    }

    // MARK: - Solid serving lookup (serving-adjust PRD, Food database Req 2)

    func testSolidServingResolvesForServedClass() throws {
        let db = try makePair()
        let serving = try XCTUnwrap(db.solidServing(for: "potato_boiled"))
        XCTAssertEqual(serving.unitSingular, "potato")
        XCTAssertEqual(serving.unitPlural, "potatoes")
        XCTAssertEqual(serving.gramsPerUnit, 58.0, accuracy: 1e-9)
        XCTAssertEqual(serving.step, 0.5, accuracy: 1e-9)
    }

    func testSolidServingIsNilForLiquidClass() throws {
        // water exists in foods but has no solid_servings row — the app
        // falls back to grams, never a dead row.
        let db = try makePair()
        XCTAssertNotNil(db.entry(for: "water"))
        XCTAssertNil(db.solidServing(for: "water"))
    }

    func testSolidServingIsNilForUnknownClass() throws {
        let db = try makePair()
        XCTAssertNil(db.solidServing(for: "does_not_exist"))
    }

    // MARK: - entry(for:edition:) returns current pair (v1 has one bundled pair)

    func testEntryForEditionReturnsCurrentPair() throws {
        let db = try makePair()
        let entry = db.entry(for: "white_rice", edition: "CoFID 2024 + AFCD 2024")
        XCTAssertNotNil(entry)
    }

    func testEntryForUnknownEditionFallsBackToCurrent() throws {
        let db = try makePair()
        let entry = db.entry(for: "white_rice", edition: "CoFID 1990")
        XCTAssertNotNil(entry, "Unknown edition string should fall back to current bundled pair")
    }
}
