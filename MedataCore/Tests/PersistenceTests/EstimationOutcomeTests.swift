import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the estimation-outcome store (specs/estimation/snaq-parity Req
// 2.1/2.5, design "Persistence" + Data Models). One `estimation_outcomes` row
// per attempt; millisecond timestamps (last_sweep_at_ms precedent); split
// eviction bounds applied inside the insert's write transaction — 500
// non-benchmark rows, 10 attempts per (benchmark_meal_id, model_version) —
// with "newest" ordered by (timestamp, id) so eviction and latest-attempt
// scoring stay deterministic under equal timestamps, and the group's latest
// completed attempt exempt from eviction so a refusal run can never drop a
// meal's scoring attempt.

final class EstimationOutcomeTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EstimationOutcomeTests-\(UUID().uuidString)", isDirectory: true)
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

    // Fabricates a UUID whose uuidString sorts by `ordinal` so tests can pin
    // the (timestamp, id) tie-break deterministically.
    private func orderedUUID(_ ordinal: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", ordinal))!
    }

    private func makeOutcome(
        id: UUID = UUID(),
        timestampMs: Int64 = 1_750_000_000_000,
        outcome: String = "refused",
        failureJSON: String? = #"{"domain":"estimation","case":"noFoodPixels"}"#,
        measurementsJSON: String = #"{"v":1}"#,
        mealID: UUID? = nil,
        modelVersion: String = "coreml_abc123def456",
        benchmarkMealID: UUID? = nil
    ) -> EstimationOutcome {
        EstimationOutcome(
            id: id,
            timestampMs: timestampMs,
            outcome: outcome,
            failureJSON: failureJSON,
            measurementsJSON: measurementsJSON,
            mealID: mealID,
            modelVersion: modelVersion,
            benchmarkMealID: benchmarkMealID
        )
    }

    // MARK: - Round trip

    func testSaveAndFetchRoundTripsAllFields() async throws {
        let mealID = UUID()
        let benchmarkMealID = UUID()
        let success = makeOutcome(
            timestampMs: 1_750_000_000_001,
            outcome: "success",
            failureJSON: nil,
            measurementsJSON: #"{"v":1,"outcome":"success"}"#,
            mealID: mealID,
            benchmarkMealID: benchmarkMealID
        )
        let refused = makeOutcome(timestampMs: 1_750_000_000_002)
        try await store.saveEstimationOutcome(success)
        try await store.saveEstimationOutcome(refused)

        let outcomes = try await store.estimationOutcomes(limit: 10)
        XCTAssertEqual(outcomes.count, 2)

        let savedSuccess = try XCTUnwrap(outcomes.first { $0.id == success.id })
        XCTAssertEqual(savedSuccess, success, "every column round-trips")
        XCTAssertEqual(savedSuccess.mealID, mealID)
        XCTAssertEqual(savedSuccess.benchmarkMealID, benchmarkMealID)
        XCTAssertNil(savedSuccess.failureJSON, "success rows carry no failure JSON")

        let savedRefused = try XCTUnwrap(outcomes.first { $0.id == refused.id })
        XCTAssertEqual(savedRefused, refused)
        XCTAssertNil(savedRefused.mealID, "refusals persist no meal reference")
        XCTAssertNil(savedRefused.benchmarkMealID)
    }

    func testFetchOrdersNewestFirstWithIdTieBreakAndHonoursLimit() async throws {
        // Two rows share a timestamp: the id must break the tie ((timestamp,
        // id) DESC), and `limit` truncates after ordering.
        let oldest = makeOutcome(id: orderedUUID(1), timestampMs: 1_000)
        let tieLow = makeOutcome(id: orderedUUID(2), timestampMs: 2_000)
        let tieHigh = makeOutcome(id: orderedUUID(3), timestampMs: 2_000)
        try await store.saveEstimationOutcome(tieLow)
        try await store.saveEstimationOutcome(oldest)
        try await store.saveEstimationOutcome(tieHigh)

        let all = try await store.estimationOutcomes(limit: 10)
        XCTAssertEqual(all.map(\.id), [tieHigh.id, tieLow.id, oldest.id],
                       "newest first; equal timestamps ordered by id descending")

        let limited = try await store.estimationOutcomes(limit: 2)
        XCTAssertEqual(limited.map(\.id), [tieHigh.id, tieLow.id])
    }

    // MARK: - Storage shape

    func testTimestampColumnStoresMilliseconds() async throws {
        // Store precedent: last_sweep_at_ms. The column must hold the exact
        // millisecond integer, not seconds.
        let outcome = makeOutcome(timestampMs: 1_750_123_456_789)
        try await store.saveEstimationOutcome(outcome)

        let q = try DatabaseQueue(path: dbURL.path)
        let raw: Int64? = try await q.read { db in
            try Int64.fetchOne(
                db, sql: "SELECT timestamp FROM estimation_outcomes WHERE id = ?",
                arguments: [outcome.id.uuidString]
            )
        }
        XCTAssertEqual(raw, 1_750_123_456_789)
    }

    func testSchemaVersionIsStampedEight() async throws {
        let q = try DatabaseQueue(path: dbURL.path)
        let version: String? = try await q.read { db in
            try String.fetchOne(db, sql: "SELECT v FROM meta WHERE k = 'schema_version'")
        }
        XCTAssertEqual(version, "8", "dose_suggestions lands with schema_version 8")
    }

    func testOutcomeIndexesExist() async throws {
        let q = try DatabaseQueue(path: dbURL.path)
        let names: [String] = try await q.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'index' AND tbl_name = 'estimation_outcomes'
                    """
            )
        }
        XCTAssertTrue(names.contains("outcomes_timestamp"))
        XCTAssertTrue(names.contains("outcomes_benchmark"))
    }

    // MARK: - Non-benchmark eviction (500-row bound, Req 2.5)

    func testNonBenchmarkEvictionKeepsNewest500AndIgnoresBenchmarkRows() async throws {
        // Two benchmark rows OLDER than everything else: the non-benchmark
        // bound must neither count them nor evict them.
        let benchmarkMealID = UUID()
        for ordinal in 0..<2 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal),
                timestampMs: Int64(ordinal),
                benchmarkMealID: benchmarkMealID
            ))
        }
        // 505 non-benchmark rows with strictly increasing timestamps.
        for ordinal in 100..<605 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal),
                timestampMs: Int64(ordinal)
            ))
        }

        let outcomes = try await store.estimationOutcomes(limit: 1_000)
        let nonBenchmark = outcomes.filter { $0.benchmarkMealID == nil }
        let benchmark = outcomes.filter { $0.benchmarkMealID != nil }

        XCTAssertEqual(nonBenchmark.count, 500, "non-benchmark population bounded at 500")
        XCTAssertEqual(benchmark.count, 2, "benchmark rows are outside the 500 bound")
        XCTAssertEqual(
            nonBenchmark.map(\.timestampMs).min(), 105,
            "the five oldest non-benchmark rows were evicted, oldest first"
        )
    }

    // MARK: - Benchmark eviction (10 per meal per lineage, Req 2.5)

    func testBenchmarkEvictionCapsAttemptsPerMealPerLineage() async throws {
        let mealA = UUID()
        let mealB = UUID()

        // 12 attempts for meal A under lineage L1 → the 2 oldest evicted.
        for ordinal in 0..<12 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal),
                timestampMs: Int64(ordinal),
                modelVersion: "L1",
                benchmarkMealID: mealA
            ))
        }
        // Same meal, different lineage: its own cap, untouched by L1 inserts.
        for ordinal in 100..<103 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal),
                timestampMs: Int64(ordinal),
                modelVersion: "L2",
                benchmarkMealID: mealA
            ))
        }
        // Different meal, same lineage: also untouched.
        try await store.saveEstimationOutcome(makeOutcome(
            id: orderedUUID(200), timestampMs: 200,
            modelVersion: "L1", benchmarkMealID: mealB
        ))
        // A non-benchmark row must survive benchmark eviction entirely.
        let diagnostic = makeOutcome(id: orderedUUID(300), timestampMs: 0)
        try await store.saveEstimationOutcome(diagnostic)

        let outcomes = try await store.estimationOutcomes(limit: 100)
        let mealAL1 = outcomes.filter { $0.benchmarkMealID == mealA && $0.modelVersion == "L1" }
        XCTAssertEqual(mealAL1.count, 10, "capped at 10 attempts per meal per lineage")
        XCTAssertEqual(mealAL1.map(\.timestampMs).min(), 2, "the two oldest attempts were evicted")

        XCTAssertEqual(outcomes.filter { $0.benchmarkMealID == mealA && $0.modelVersion == "L2" }.count, 3)
        XCTAssertEqual(outcomes.filter { $0.benchmarkMealID == mealB }.count, 1)
        XCTAssertTrue(outcomes.contains { $0.id == diagnostic.id },
                      "benchmark eviction never touches non-benchmark rows")
    }

    func testBenchmarkEvictionNeverEvictsTheLatestCompletedAttempt() async throws {
        // One early success followed by a run of refusals long enough to push
        // it out under plain oldest-first eviction: the group's latest
        // completed attempt is exempt — it survives as the meal's scoring
        // attempt while the group stays at the bound.
        let meal = UUID()
        let success = makeOutcome(
            id: orderedUUID(0), timestampMs: 0,
            outcome: "success", failureJSON: nil, mealID: UUID(),
            modelVersion: "L1", benchmarkMealID: meal
        )
        try await store.saveEstimationOutcome(success)
        for ordinal in 1...12 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal), timestampMs: Int64(ordinal),
                modelVersion: "L1", benchmarkMealID: meal
            ))
        }

        let outcomes = try await store.estimationOutcomes(limit: 100)
        let group = outcomes.filter { $0.benchmarkMealID == meal }
        XCTAssertEqual(group.count, 10, "the exempt row occupies a bound slot; still ≤ 10")
        XCTAssertTrue(group.contains { $0.id == success.id },
                      "the meal's only completed attempt survives the refusal run")
        XCTAssertEqual(
            group.filter { $0.outcome == "refused" }.map(\.timestampMs).min(), 4,
            "the oldest non-exempt rows are the ones evicted"
        )
    }

    func testBenchmarkEvictionBreaksTimestampTiesById() async throws {
        // Eleven attempts, all at the SAME timestamp: (timestamp, id) ordering
        // makes the lowest id the oldest, so it is the one evicted.
        let meal = UUID()
        for ordinal in 0..<11 {
            try await store.saveEstimationOutcome(makeOutcome(
                id: orderedUUID(ordinal),
                timestampMs: 5_000,
                modelVersion: "L1",
                benchmarkMealID: meal
            ))
        }

        let outcomes = try await store.estimationOutcomes(limit: 100)
        XCTAssertEqual(outcomes.count, 10)
        XCTAssertFalse(outcomes.contains { $0.id == orderedUUID(0) },
                       "lowest id at the tied timestamp is the oldest attempt")
        XCTAssertTrue(outcomes.contains { $0.id == orderedUUID(10) })
    }
}
