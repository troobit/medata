import Foundation
import GRDB
import XCTest
@testable import Foods

// Tests for GRDBFoodDatabase per design §3.7 / §4.1 / task 35.

final class FoodDatabaseTests: XCTestCase {

    // MARK: - helpers

    // Temp path that is cleaned up after each test.
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

    // Seed the main CoFID database.
    private func makeMainDB(at path: String) throws {
        let q = try DatabaseQueue(path: path)
        try q.write { db in
            try db.execute(sql: """
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
                    composition_source TEXT NOT NULL
                );
                CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
            """)
            try db.execute(sql: "INSERT INTO meta VALUES ('edition', 'CoFID 2024')")
            try db.execute(sql: "INSERT INTO meta VALUES ('palette_version', 'v1')")
            try db.execute(sql: "INSERT INTO meta VALUES ('attribution', 'Test')")
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('white_rice', 'White rice', 1.05, 580.0, 32.0, 2.7, 0.3, 0.1,
                     0.9, 'calibrated', 'CoFID 2024', 'CoFID 2024')
            """)
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('chicken', 'Chicken breast', 0.9, 736.0, 0.0, 31.0, 3.6, 0.0,
                     1.0, 'uncalibrated_unity', 'FAO_DENS', 'CoFID 2024')
            """)
            try db.execute(sql: """
                INSERT INTO foods VALUES
                    ('potato_boiled', 'Boiled potato', 1.01, 318.0, 17.0, 1.8, 0.1, 1.1,
                     1.0, 'uncalibrated_pooled', 'FAO_DENS', 'CoFID 2024')
            """)
        }
    }

    // Seed the IFCDB overlay with an updated density + carbs for white_rice only.
    private func makeOverlayDB(at path: String) throws {
        let q = try DatabaseQueue(path: path)
        try q.write { db in
            try db.execute(sql: """
                CREATE TABLE foods_overlay (
                    class_id TEXT PRIMARY KEY,
                    density REAL,
                    energy_kj_100 REAL,
                    carbs_mono_100 REAL,
                    protein_100 REAL,
                    fat_100 REAL,
                    fibre_100 REAL,
                    beta REAL,
                    beta_status TEXT,
                    density_source TEXT,
                    composition_source TEXT
                )
            """)
            // Only density and density_source overridden; all other fields NULL → use CoFID.
            try db.execute(sql: """
                INSERT INTO foods_overlay (class_id, density, density_source)
                VALUES ('white_rice', 1.12, 'IFCDB 2023')
            """)
        }
    }

    // MARK: - T35.1 CoFID-only lookup returns base values

    func testCoFIDOnlyLookupReturnsBaseValues() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        let entry = try XCTUnwrap(db.entry(for: "white_rice"))
        XCTAssertEqual(entry.densityGPerCm3,  1.05,  accuracy: 1e-4)
        XCTAssertEqual(entry.carbsMonoG,       32.0,  accuracy: 1e-4)
        XCTAssertEqual(entry.proteinG,          2.7,  accuracy: 1e-4)
        XCTAssertEqual(entry.densitySource, "CoFID 2024")
    }

    // MARK: - T35.2 ATTACH + COALESCE returns overlay-where-present, base-otherwise

    func testOverlayDensityOverridesBase() throws {
        let main = tempPath()
        let overlay = tempPath()
        try makeMainDB(at: main)
        try makeOverlayDB(at: overlay)
        let db = try GRDBFoodDatabase(mainPath: main, overlayPath: overlay)

        let entry = try XCTUnwrap(db.entry(for: "white_rice"))
        // Density from overlay
        XCTAssertEqual(entry.densityGPerCm3, 1.12, accuracy: 1e-4)
        XCTAssertEqual(entry.densitySource, "IFCDB 2023")
        // Carbs from CoFID base (overlay NULL → COALESCE picks base)
        XCTAssertEqual(entry.carbsMonoG, 32.0, accuracy: 1e-4)
        // Protein from CoFID base
        XCTAssertEqual(entry.proteinG, 2.7, accuracy: 1e-4)
    }

    func testOverlayDoesNotAffectUnlistedClass() throws {
        let main = tempPath()
        let overlay = tempPath()
        try makeMainDB(at: main)
        try makeOverlayDB(at: overlay)
        let db = try GRDBFoodDatabase(mainPath: main, overlayPath: overlay)

        // chicken is not in the overlay; all values should come from base
        let entry = try XCTUnwrap(db.entry(for: "chicken"))
        XCTAssertEqual(entry.densityGPerCm3, 0.9,  accuracy: 1e-4)
        XCTAssertEqual(entry.densitySource, "FAO_DENS")
    }

    // MARK: - T35.3 entry(for:edition:) honours per-meal edition (Decision 24)

    func testEntryForEditionReturnsCurrentWhenEditionMatches() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        // Matching edition
        let entry = db.entry(for: "white_rice", edition: "CoFID 2024")
        XCTAssertNotNil(entry)
    }

    func testEntryForEditionFallsBackWhenEditionUnavailable() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        // Unknown edition falls back to the current bundled DB (§6.12: one edition bundled in v1)
        let entry = db.entry(for: "white_rice", edition: "CoFID 1990")
        XCTAssertNotNil(entry, "Should return current edition data for unknown edition")
    }

    func testAvailableEditionsContainsCurrentEdition() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        XCTAssertTrue(db.availableEditions().contains("CoFID 2024"))
    }

    // MARK: - T35.4 Canonical units: density in g/cm³, macros in g per 100 g

    func testCanonicalUnits() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        let entry = try XCTUnwrap(db.entry(for: "white_rice"))
        // density in g/cm³ — no food has bulk density > 5 g/cm³
        XCTAssertGreaterThan(entry.densityGPerCm3, 0.0)
        XCTAssertLessThanOrEqual(entry.densityGPerCm3, 5.0)
        // carbs in g per 100 g (not fraction, not per kg)
        XCTAssertGreaterThanOrEqual(entry.carbsMonoG, 0.0)
        XCTAssertLessThanOrEqual(entry.carbsMonoG, 100.0)
        // β ∈ (0, 1]
        XCTAssertGreaterThan(entry.beta, 0.0)
        XCTAssertLessThanOrEqual(entry.beta, 1.0)
    }

    // MARK: - T35.5 Missing class returns nil

    func testMissingClassReturnsNil() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        XCTAssertNil(db.entry(for: "does_not_exist"))
    }

    // MARK: - T35.6 BetaCalibrationStatus round-trips correctly

    func testBetaCalibrationStatusCalibratedRoundtrip() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        let rice = try XCTUnwrap(db.entry(for: "white_rice"))
        XCTAssertEqual(rice.calibrationStatus, .calibrated)
    }

    func testBetaCalibrationStatusUncalibratedUnityRoundtrip() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        let chicken = try XCTUnwrap(db.entry(for: "chicken"))
        XCTAssertEqual(chicken.calibrationStatus, .uncalibratedUnity)
    }

    func testBetaCalibrationStatusUncalibratedPooledRoundtrip() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        let potato = try XCTUnwrap(db.entry(for: "potato_boiled"))
        XCTAssertEqual(potato.calibrationStatus, .uncalibratedPooled)
    }

    // MARK: - T35.7 version reflects meta table

    func testVersionReflectsMetaTable() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        XCTAssertEqual(db.version, "CoFID 2024")
    }

    // MARK: - T35.8 All numeric fields come back in g/cm³ and g/100 g

    func testAllNumericFieldsReturnedForAllFoodClasses() throws {
        let main = tempPath()
        try makeMainDB(at: main)
        let db = try GRDBFoodDatabase(mainPath: main)

        for classId in ["white_rice", "chicken", "potato_boiled"] {
            let e = try XCTUnwrap(db.entry(for: classId), "No entry for \(classId)")
            XCTAssertGreaterThan(e.densityGPerCm3, 0, "\(classId) density")
            XCTAssertGreaterThanOrEqual(e.energyKJPer100g, 0, "\(classId) energy")
            XCTAssertGreaterThanOrEqual(e.carbsMonoG, 0, "\(classId) carbs")
            XCTAssertGreaterThanOrEqual(e.proteinG, 0, "\(classId) protein")
        }
    }
}
