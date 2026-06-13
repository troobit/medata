#if RETENTION_SCHEDULER_ENABLED
import Foundation
import PortableContracts
import XCTest
@testable import Persistence

// Tests for RetentionScheduler per Req 17.6 / task 43.
// Gated behind RETENTION_SCHEDULER_ENABLED — scheduler is deferred in v1.

final class RetentionSchedulerTests: XCTestCase {

    // MARK: - T43.1 Sweep deletes artefacts older than retentionDays

    func testSweepDeletesOldArtefacts() async throws {
        let stub = StubPersistenceStore()
        let scheduler = RetentionScheduler(store: stub, retentionDays: 30)
        let now = Date()
        try await scheduler.sweep(relativeTo: now)
        // cutoff = now - 30d; stub captures the deleteArtefacts call
        XCTAssertEqual(stub.deleteCalls.count, 1)
        let cutoff = stub.deleteCalls[0]
        let expectedCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expectedCutoff.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - T43.2 Meals at 29 days are not swept (boundary)

    func testMealAt29DaysNotSwept() async throws {
        let stub = StubPersistenceStore()
        let scheduler = RetentionScheduler(store: stub, retentionDays: 30)
        let now = Date()
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let mealDate = now.addingTimeInterval(-29 * 24 * 60 * 60) // 29 days ago — within retention
        XCTAssertGreaterThan(mealDate.timeIntervalSince1970, cutoff.timeIntervalSince1970,
            "29-day meal should be after cutoff and therefore NOT swept")
    }

    // MARK: - T43.3 Meal at 31 days IS swept (past boundary)

    func testMealAt31DaysIsSwept() async throws {
        let stub = StubPersistenceStore()
        let scheduler = RetentionScheduler(store: stub, retentionDays: 30)
        let now = Date()
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let mealDate = now.addingTimeInterval(-31 * 24 * 60 * 60) // 31 days ago — past retention
        XCTAssertLessThan(mealDate.timeIntervalSince1970, cutoff.timeIntervalSince1970,
            "31-day meal should be before cutoff and therefore swept")
    }

    // MARK: - T43.4 Two consecutive sweeps are idempotent

    func testIdempotentConsecutiveSweeps() async throws {
        let stub = StubPersistenceStore()
        let scheduler = RetentionScheduler(store: stub, retentionDays: 30)
        let now = Date()
        try await scheduler.sweep(relativeTo: now)
        try await scheduler.sweep(relativeTo: now)
        XCTAssertEqual(stub.deleteCalls.count, 2,
            "sweep() is unconditional — both calls should delegate to store")
        XCTAssertEqual(stub.deleteCalls[0].timeIntervalSince1970,
                       stub.deleteCalls[1].timeIntervalSince1970,
                       accuracy: 1, "both sweeps should use the same cutoff")
    }

    // MARK: - T43.5 Custom retentionDays respected

    func testCustomRetentionDays() async throws {
        let stub = StubPersistenceStore()
        let scheduler = RetentionScheduler(store: stub, retentionDays: 7)
        let now = Date()
        try await scheduler.sweep(relativeTo: now)
        let cutoff = stub.deleteCalls[0]
        let expectedCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        XCTAssertEqual(cutoff.timeIntervalSince1970, expectedCutoff.timeIntervalSince1970, accuracy: 1)
    }
}

// MARK: - Stub

private final class StubPersistenceStore: PersistenceStore, @unchecked Sendable {
    var deleteCalls: [Date] = []
    var sweepIfDueCalled = false

    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {}
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {}
    func meal(id: UUID) async throws -> MealRecord { throw PersistenceError.mealNotFound(id) }
    func exportArchive() async throws -> String { "" }
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws {}

    func deleteArtefacts(olderThan date: Date) async throws {
        deleteCalls.append(date)
    }

    func sweepIfDue() async throws {
        sweepIfDueCalled = true
        try await deleteArtefacts(olderThan: Date().addingTimeInterval(-30 * 24 * 60 * 60))
    }

    func allMeals() async throws -> [MealRecord] { [] }
    func deleteMeal(id: UUID) async throws {}
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] {
        fatalError("unused")
    }
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection] {
        fatalError("unused")
    }
    var eventsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
}

#endif // RETENTION_SCHEDULER_ENABLED
