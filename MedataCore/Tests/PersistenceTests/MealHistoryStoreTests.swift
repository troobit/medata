import Foundation
import GRDB
import PortableContracts
import XCTest
@testable import Persistence

// Tests for the v1.1 additive PersistenceStore surface used by the Meals tab
// (UI spec Req §19.1 / §19.6 / §19.7 — task 29).
final class MealHistoryStoreTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MealHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - allMeals (Req §19.1)

    func testAllMealsReturnsRowsSortedByCreatedAtDescending() async throws {
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

    func testAllMealsRoundTripsSegmenterSourceColumn() async throws {
        let stub = makeMealRecord(segmenterSource: "dev_stub")
        let real = makeMealRecord(segmenterSource: "coreml_v0.1")
        try await store.save(stub, artefacts: [])
        try await store.save(real, artefacts: [])

        let result = try await store.allMeals().sorted { $0.id.uuidString < $1.id.uuidString }
        let stubResult = result.first { $0.id == stub.id }
        let realResult = result.first { $0.id == real.id }
        XCTAssertEqual(stubResult?.segmenterSource, "dev_stub")
        XCTAssertEqual(realResult?.segmenterSource, "coreml_v0.1")
    }

    func testAllMealsReturnsEmptyForFreshContainer() async throws {
        let result = try await store.allMeals()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - deleteMeal (Req §19.7)

    func testDeleteMealRemovesSQLiteRow() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])
        try await store.deleteMeal(id: record.id)

        let result = try await store.allMeals()
        XCTAssertTrue(result.isEmpty)
    }

    func testDeleteMealRemovesArtefactDirectory() async throws {
        let record = makeMealRecord()
        let artefactDir = tempDir
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(record.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artefactDir, withIntermediateDirectories: true)
        let artefactFile = artefactDir.appendingPathComponent("nadir.image")
        try Data([0xAA, 0xBB]).write(to: artefactFile)

        try await store.save(record, artefacts: [])
        try await store.deleteMeal(id: record.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artefactDir.path))
    }

    func testDeleteMealIsBestEffortWhenArtefactDirAlreadyGone() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])
        // No artefact directory was ever created — delete must still remove the row
        // without throwing (best-effort cleanup per design.md).
        try await store.deleteMeal(id: record.id)

        let result = try await store.allMeals()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - mealsDidChange (Req §19.6)

    func testMealsDidChangeYieldsAfterSave() async throws {
        let stream = store.mealsDidChange
        let received = Task<Bool, Never> {
            for await _ in stream { return true }
            return false
        }
        // Yield so the iterator subscribes before the save fires.
        await Task.yield()
        try await store.save(makeMealRecord(), artefacts: [])
        let got = try await awaitWithTimeout(seconds: 2, received)
        XCTAssertTrue(got, "mealsDidChange did not yield after save")
    }

    func testMealsDidChangeYieldsAfterDelete() async throws {
        let record = makeMealRecord()
        try await store.save(record, artefacts: [])

        let stream = store.mealsDidChange
        let received = Task<Bool, Never> {
            for await _ in stream { return true }
            return false
        }
        await Task.yield()
        try await store.deleteMeal(id: record.id)
        let got = try await awaitWithTimeout(seconds: 2, received)
        XCTAssertTrue(got, "mealsDidChange did not yield after delete")
    }

    func testMealsDidChangeIsPerSubscriber() async throws {
        let streamA = store.mealsDidChange
        let streamB = store.mealsDidChange
        let a = Task<Bool, Never> {
            for await _ in streamA { return true }
            return false
        }
        let b = Task<Bool, Never> {
            for await _ in streamB { return true }
            return false
        }
        await Task.yield()
        try await store.save(makeMealRecord(), artefacts: [])
        let gotA = try await awaitWithTimeout(seconds: 2, a)
        let gotB = try await awaitWithTimeout(seconds: 2, b)
        XCTAssertTrue(gotA, "subscriber A did not receive tick")
        XCTAssertTrue(gotB, "subscriber B did not receive tick")
    }
}

private enum TimeoutError: Error { case timeout }

// Races `task.value` against a sleep so a missing change-stream emission throws
// a clear timeout error instead of hanging the harness.
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
    segmenterSource: String? = nil,
    photoAssetID: String? = nil
) -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.82
    var macros = PbMacroResult()
    macros.totalCarbsG = 42

    return MealRecord(
        createdAt: createdAt,
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v1",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence,
        segmenterSource: segmenterSource,
        photoAssetID: photoAssetID
    )
}
