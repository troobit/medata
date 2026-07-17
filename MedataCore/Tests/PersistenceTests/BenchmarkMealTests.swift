import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the benchmark-meal store (specs/estimation/snaq-parity Req
// 1.2/1.3, design lane B + Data Models). Ground-truth carbs are derived AT
// SAVE as grams × carbs_per_100g / 100 through the injected lookup — the same
// FoodDatabase.entry(for:) surface Macros.compute uses — with no volume and
// no β, so truth isolates the estimation pipeline. An unresolvable class
// throws rather than silently contributing 0 g (the Macros.swift:110-113
// skip must not leak into truth), grams are bounded 1...5000, and a meal
// becomes immutable once estimation attempts reference it.

final class BenchmarkMealTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenchmarkMealTests-\(UUID().uuidString)", isDirectory: true)
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

    // Fixture lookup standing in for FoodDatabase.entry(for:)?.carbsMonoG —
    // carbs per 100 g by palette class; nil = class absent at this edition.
    private static let carbsPer100g: [String: Double] = [
        "white_rice": 30.9,
        "bread_white": 46.1,
        "chips_fries": 30.0,
        "lemon": 3.2
    ]

    private func lookup(_ classID: String) -> Double? {
        Self.carbsPer100g[classID]
    }

    private func makeMeal(
        id: UUID = UUID(),
        name: String = "rice + bread",
        createdAtMs: Int64 = 1_750_000_000_000,
        items: [BenchmarkMealItem] = [
            BenchmarkMealItem(classID: "white_rice", grams: 200),
            BenchmarkMealItem(classID: "bread_white", grams: 40)
        ],
        truthCarbsG: Double = 0,
        dbEdition: String = "cofid_2021_afcd_2022",
        fidelity: BenchmarkFidelity = .weighed
    ) -> BenchmarkMeal {
        BenchmarkMeal(
            id: id,
            name: name,
            createdAtMs: createdAtMs,
            items: items,
            truthCarbsG: truthCarbsG,
            dbEdition: dbEdition,
            fidelity: fidelity
        )
    }

    // MARK: - Truth derivation (Req 1.2)

    func testSaveDerivesTruthFromGramsTimesCarbsPer100g() async throws {
        // 200 g white_rice at 30.9/100 g = 61.8 g; 40 g bread_white at
        // 46.1/100 g = 18.44 g; truth = 80.24 g. No volume, no β.
        let meal = makeMeal()
        try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].truthCarbsG, 80.24, accuracy: 1e-9)
    }

    func testSaveIgnoresCallerSuppliedTruth() async throws {
        // Truth is derived at save; a caller-supplied figure is never stored.
        let meal = makeMeal(
            items: [BenchmarkMealItem(classID: "lemon", grams: 100)],
            truthCarbsG: 999
        )
        try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched[0].truthCarbsG, 3.2, accuracy: 1e-9)
    }

    // MARK: - Round trip (Req 1.3)

    func testRoundTripPersistsAllFields() async throws {
        let id = UUID()
        let meal = makeMeal(
            id: id,
            name: "chip shop",
            createdAtMs: 1_750_000_000_123,
            items: [BenchmarkMealItem(classID: "chips_fries", grams: 150)],
            dbEdition: "edition_x",
            fidelity: .package
        )
        try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 1)
        let f = fetched[0]
        XCTAssertEqual(f.id, id)
        XCTAssertEqual(f.name, "chip shop")
        XCTAssertEqual(f.createdAtMs, 1_750_000_000_123)
        XCTAssertEqual(f.items, [BenchmarkMealItem(classID: "chips_fries", grams: 150)])
        XCTAssertEqual(f.truthCarbsG, 45.0, accuracy: 1e-9)
        XCTAssertEqual(f.dbEdition, "edition_x")
        XCTAssertEqual(f.fidelity, .package)
    }

    func testItemsPersistAsClassIdGramsJSON() async throws {
        // The items column is the export-facing [{class_id, grams}] shape
        // (design Data Models) — pin the snake_case key, not the Swift name.
        let meal = makeMeal(items: [BenchmarkMealItem(classID: "white_rice", grams: 200)])
        try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)

        let queue = try DatabaseQueue(path: dbURL.path)
        let itemsJSON = try await queue.read { db in
            try String.fetchOne(db, sql: "SELECT items FROM benchmark_meals")
        }
        XCTAssertNotNil(itemsJSON)
        XCTAssertTrue(itemsJSON!.contains(#""class_id":"white_rice""#))
        XCTAssertFalse(itemsJSON!.contains("classID"))
    }

    func testMealsReturnNewestFirst() async throws {
        let older = makeMeal(name: "older", createdAtMs: 1_000)
        let newer = makeMeal(name: "newer", createdAtMs: 2_000)
        try await store.saveBenchmarkMeal(older, carbsPer100g: lookup)
        try await store.saveBenchmarkMeal(newer, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.map(\.name), ["newer", "older"])
    }

    // MARK: - Grams bounds

    func testGramsBelowRangeThrows() async throws {
        let meal = makeMeal(items: [BenchmarkMealItem(classID: "white_rice", grams: 0.5)])
        do {
            try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)
            XCTFail("expected benchmarkGramsOutOfRange")
        } catch let error as Persistence.PersistenceError {
            XCTAssertEqual(error, .benchmarkGramsOutOfRange(0.5))
        }
        let fetched = try await store.benchmarkMeals()
        XCTAssertTrue(fetched.isEmpty, "a rejected meal must not be stored")
    }

    func testGramsAboveRangeThrows() async throws {
        let meal = makeMeal(items: [
            BenchmarkMealItem(classID: "white_rice", grams: 100),
            BenchmarkMealItem(classID: "bread_white", grams: 5001)
        ])
        do {
            try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)
            XCTFail("expected benchmarkGramsOutOfRange")
        } catch let error as Persistence.PersistenceError {
            XCTAssertEqual(error, .benchmarkGramsOutOfRange(5001))
        }
    }

    func testGramsBoundsAreInclusive() async throws {
        let meal = makeMeal(items: [
            BenchmarkMealItem(classID: "white_rice", grams: 1),
            BenchmarkMealItem(classID: "bread_white", grams: 5000)
        ])
        try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)
        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 1)
    }

    // MARK: - Class resolvability (no silent 0 g truth)

    func testUnresolvableClassThrowsAndStoresNothing() async throws {
        let meal = makeMeal(items: [
            BenchmarkMealItem(classID: "white_rice", grams: 200),
            BenchmarkMealItem(classID: "not_in_db", grams: 50)
        ])
        do {
            try await store.saveBenchmarkMeal(meal, carbsPer100g: lookup)
            XCTFail("expected benchmarkClassUnresolvable")
        } catch let error as Persistence.PersistenceError {
            XCTAssertEqual(error, .benchmarkClassUnresolvable("not_in_db"))
        }
        let fetched = try await store.benchmarkMeals()
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Immutability once attempts exist

    private func attempt(on mealID: UUID, timestampMs: Int64 = 1) -> EstimationOutcome {
        EstimationOutcome(
            timestampMs: timestampMs,
            outcome: "refused",
            failureJSON: #"{"domain":"estimation","case":"noFoodPixels"}"#,
            measurementsJSON: #"{"v":1}"#,
            mealID: nil,
            modelVersion: "coreml_abc123def456",
            benchmarkMealID: mealID
        )
    }

    func testUpdateBeforeAnyAttemptReplacesAndRederivesTruth() async throws {
        let id = UUID()
        let original = makeMeal(id: id, items: [BenchmarkMealItem(classID: "white_rice", grams: 200)])
        try await store.saveBenchmarkMeal(original, carbsPer100g: lookup)

        let corrected = makeMeal(
            id: id,
            name: "corrected",
            items: [BenchmarkMealItem(classID: "white_rice", grams: 150)]
        )
        try await store.saveBenchmarkMeal(corrected, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "corrected")
        XCTAssertEqual(fetched[0].truthCarbsG, 46.35, accuracy: 1e-9)
    }

    func testUpdateAfterAttemptExistsThrowsAndLeavesRowUntouched() async throws {
        let id = UUID()
        let original = makeMeal(id: id)
        try await store.saveBenchmarkMeal(original, carbsPer100g: lookup)
        try await store.saveEstimationOutcome(attempt(on: id))

        let edited = makeMeal(id: id, name: "edited")
        do {
            try await store.saveBenchmarkMeal(edited, carbsPer100g: lookup)
            XCTFail("expected benchmarkMealImmutable")
        } catch let error as Persistence.PersistenceError {
            XCTAssertEqual(error, .benchmarkMealImmutable(id))
        }

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "rice + bread")
    }

    func testNewMealInsertsWhileAnotherMealHasAttempts() async throws {
        let locked = makeMeal(name: "locked")
        try await store.saveBenchmarkMeal(locked, carbsPer100g: lookup)
        try await store.saveEstimationOutcome(attempt(on: locked.id))

        let fresh = makeMeal(name: "fresh")
        try await store.saveBenchmarkMeal(fresh, carbsPer100g: lookup)

        let fetched = try await store.benchmarkMeals()
        XCTAssertEqual(fetched.count, 2)
    }
}
