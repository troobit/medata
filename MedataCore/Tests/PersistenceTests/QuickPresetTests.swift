import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the quick-add preset surface (specs/data/manual-carb-intake,
// design.md "Quick-add presets — new table"). One `quick_presets` row per
// preset: id, name, carbs_g (required), protein_g/fat_g/fibre_g (NULL when
// absent), sort_order (insertion order, flat list — Decision 6).

final class QuickPresetTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickPresetTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makePreset(
        id: UUID = UUID(),
        name: String = "Toast",
        carbsG: Double = 20,
        macros: IntakeMacros = IntakeMacros(),
        sortOrder: Int = 0
    ) -> QuickPreset {
        QuickPreset(id: id, name: name, carbsG: carbsG, macros: macros, sortOrder: sortOrder)
    }

    // MARK: - First-launch seeding (Req 3.3)

    func testFirstInitSeedsExactlyThreeAuthoredDefaults() async throws {
        // `store` was already constructed in setUp() against a brand-new,
        // empty DB — that init is the "first store-init" under test.
        let presets = try await store.quickPresets()

        XCTAssertEqual(presets.count, 3, "exactly the three authored defaults")
        XCTAssertEqual(presets.map(\.name), ["A pint", "Bagel", "Chips"],
                       "seeded in sort_order ASC, matching insertion order")
        XCTAssertEqual(presets.map(\.carbsG), [17, 45, 40])

        for preset in presets {
            XCTAssertEqual(preset.macros, IntakeMacros(),
                           "authored defaults carry carbohydrate values only, no macros")
        }
    }

    func testSecondInitDoesNotReseed() async throws {
        // Re-open a GRDBPersistenceStore against the SAME db file the
        // already-seeded `store` from setUp() created.
        let second = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
        let presets = try await second.quickPresets()

        XCTAssertEqual(presets.count, 3, "re-init on a non-empty table must not reseed")
        XCTAssertEqual(presets.map(\.name), ["A pint", "Bagel", "Chips"])
    }

    func testSeedingIsSkippedWhenPresetsAlreadyExist() async throws {
        // Simulate a DB that already has user presets (e.g. defaults deleted,
        // one custom preset created) before a fresh store re-init runs.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(sql: "DELETE FROM quick_presets")
            try db.execute(
                sql: """
                    INSERT INTO quick_presets (id, name, carbs_g, sort_order)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, "Custom", 30.0, 0]
            )
        }

        let reopened = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
        let presets = try await reopened.quickPresets()

        XCTAssertEqual(presets.count, 1, "table is non-empty, so seeding must not run")
        XCTAssertEqual(presets.map(\.name), ["Custom"])
    }

    // MARK: - saveQuickPreset: insert + update-by-id

    func testSaveInsertsNewPreset() async throws {
        let preset = makePreset(name: "Toast", carbsG: 20, sortOrder: 99)
        try await store.saveQuickPreset(preset)

        let presets = try await store.quickPresets()
        XCTAssertTrue(presets.contains { $0.id == preset.id && $0.name == "Toast" })
    }

    func testSaveUpdatesExistingPresetByID() async throws {
        let id = UUID()
        let original = makePreset(id: id, name: "Toast", carbsG: 20, sortOrder: 50)
        try await store.saveQuickPreset(original)

        let updated = makePreset(id: id, name: "Toast (large)", carbsG: 35, sortOrder: 50)
        try await store.saveQuickPreset(updated)

        let presets = try await store.quickPresets()
        let matches = presets.filter { $0.id == id }
        XCTAssertEqual(matches.count, 1, "update-by-id must not create a duplicate row")
        XCTAssertEqual(matches[0].name, "Toast (large)")
        XCTAssertEqual(matches[0].carbsG, 35)
    }

    // MARK: - deleteQuickPreset

    func testDeleteRemovesOnlyTheTargetPreset() async throws {
        let first = makePreset(name: "First", sortOrder: 10)
        let second = makePreset(name: "Second", sortOrder: 11)
        try await store.saveQuickPreset(first)
        try await store.saveQuickPreset(second)

        try await store.deleteQuickPreset(id: first.id)

        let presets = try await store.quickPresets()
        XCTAssertFalse(presets.contains { $0.id == first.id })
        XCTAssertTrue(presets.contains { $0.id == second.id })
    }

    // MARK: - quickPresets() sort_order ASC

    func testQuickPresetsReturnsRowsSortedBySortOrderAscending() async throws {
        // Clear the seeded defaults so ordering is unambiguous.
        for preset in try await store.quickPresets() {
            try await store.deleteQuickPreset(id: preset.id)
        }

        let low = makePreset(name: "Low", sortOrder: 1)
        let high = makePreset(name: "High", sortOrder: 5)
        let mid = makePreset(name: "Mid", sortOrder: 3)
        // Insert out of order to prove the store sorts, not the caller.
        try await store.saveQuickPreset(high)
        try await store.saveQuickPreset(low)
        try await store.saveQuickPreset(mid)

        let presets = try await store.quickPresets()
        XCTAssertEqual(presets.map(\.name), ["Low", "Mid", "High"])
    }

    // MARK: - Macro fields NULL when absent

    func testMacroFieldsAreNullInStorageWhenAbsent() async throws {
        let preset = makePreset(name: "Carbs only", carbsG: 25, macros: IntakeMacros(), sortOrder: 42)
        try await store.saveQuickPreset(preset)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT * FROM quick_presets WHERE id = ?",
                arguments: [preset.id.uuidString]
            ) else {
                XCTFail("expected a row for the saved preset")
                return
            }
            let proteinG: Double? = row["protein_g"]
            let fatG: Double? = row["fat_g"]
            let fibreG: Double? = row["fibre_g"]
            XCTAssertNil(proteinG, "absent macro must be NULL, not 0")
            XCTAssertNil(fatG, "absent macro must be NULL, not 0")
            XCTAssertNil(fibreG, "absent macro must be NULL, not 0")
        }
    }

    func testMacroFieldsRoundTripWhenPresent() async throws {
        let macros = IntakeMacros(proteinG: 12.0, fatG: 8.0, fibreG: 3.0)
        let preset = makePreset(name: "Full macros", carbsG: 30, macros: macros, sortOrder: 43)
        try await store.saveQuickPreset(preset)

        let presets = try await store.quickPresets()
        let saved = try XCTUnwrap(presets.first { $0.id == preset.id })
        XCTAssertEqual(saved.macros.proteinG, 12.0)
        XCTAssertEqual(saved.macros.fatG, 8.0)
        XCTAssertEqual(saved.macros.fibreG, 3.0)
    }

    func testMacroFieldsCanBePartiallyPresent() async throws {
        let macros = IntakeMacros(proteinG: 5.0, fatG: nil, fibreG: nil)
        let preset = makePreset(name: "Protein only", carbsG: 10, macros: macros, sortOrder: 44)
        try await store.saveQuickPreset(preset)

        let presets = try await store.quickPresets()
        let saved = try XCTUnwrap(presets.first { $0.id == preset.id })
        XCTAssertEqual(saved.macros.proteinG, 5.0)
        XCTAssertNil(saved.macros.fatG)
        XCTAssertNil(saved.macros.fibreG)
    }
}
