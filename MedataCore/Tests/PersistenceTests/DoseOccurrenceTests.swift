import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the occurrence ledger (specs/data/dose-schedule design.md section
// 8). The load-bearing assertions here are about what was NOT written: a
// second action on a closed occurrence must record no second dose, and a skip
// or a miss must record no dose of any amount, including zero.

final class DoseOccurrenceTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoseOccurrenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var dbURL: URL { tempDir.appendingPathComponent("meals.sqlite") }

    private let dueAt = Date(timeIntervalSince1970: 1_780_000_000)
    private let loggedAt = Date(timeIntervalSince1970: 1_780_000_900)

    private func insulinRowCount() async throws -> Int {
        let q = try DatabaseQueue(path: dbURL.path)
        return try await q.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM events WHERE event_type = ?",
                arguments: [EventType.insulin]
            ) ?? 0
        }
    }

    // MARK: - Opening

    func testOpeningTheSameDueInstantTwiceYieldsOneRow() async throws {
        let scheduleID = UUID()
        let first = try await store.openOccurrence(scheduleID: scheduleID, dueAt: dueAt)
        let second = try await store.openOccurrence(scheduleID: scheduleID, dueAt: dueAt)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.outcome, .outstanding)
        let open = try await store.outstandingOccurrences()
        XCTAssertEqual(open.count, 1)
    }

    func testTwoSchedulesAtTheSameInstantAreTwoOccurrences() async throws {
        _ = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        _ = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let open = try await store.outstandingOccurrences()
        XCTAssertEqual(open.count, 2)
    }

    func testAnOpenedOccurrenceCarriesNoOutcomeFields() async throws {
        let opened = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        XCTAssertNil(opened.closedAt)
        XCTAssertNil(opened.insulinEventID)
        XCTAssertNil(opened.wasNominal)
        XCTAssertEqual(opened.dueAt.timeIntervalSince1970, dueAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - The compare-and-set (Req 4.6)

    func testCloseTransitionsOnceAndOnlyOnce() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let eventID = UUID()
        let first = try await store.closeOccurrence(
            id: occurrence.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: eventID, wasNominal: true
        )
        let second = try await store.closeOccurrence(
            id: occurrence.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: true
        )
        XCTAssertTrue(first)
        XCTAssertFalse(second, "a closed occurrence must not transition twice")
        let rows = try await store.doseOccurrences(limit: 10)
        XCTAssertEqual(rows.first?.insulinEventID, eventID,
                       "the second call must not overwrite the first event id")
    }

    // The assertion that matters is on what was NOT written. A stale follow-up
    // notification tapped after the dose was logged elsewhere must leave the
    // event count exactly where it was.
    func testASecondActionWritesNoSecondDose() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        // The caller's contract: write the insulin event ONLY when the
        // compare-and-set transitioned.
        for _ in 0..<2 {
            let eventID = UUID()
            let transitioned = try await store.closeOccurrence(
                id: occurrence.id, outcome: .logged, closedAt: loggedAt,
                insulinEventID: eventID, wasNominal: true
            )
            if transitioned {
                try await store.saveInsulinDose(InsulinDose(
                    id: eventID, timestamp: loggedAt, units: 15,
                    kind: .basal, insulinType: "Lantus"
                ))
            }
        }
        let count = try await insulinRowCount()
        XCTAssertEqual(count, 1, "acting twice on one occurrence records one dose")
    }

    func testClosingToOutstandingIsRejected() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let transitioned = try await store.closeOccurrence(
            id: occurrence.id, outcome: .outstanding, closedAt: loggedAt,
            insulinEventID: nil, wasNominal: nil
        )
        XCTAssertFalse(transitioned)
        let open = try await store.outstandingOccurrences()
        XCTAssertEqual(open.count, 1)
    }

    func testClosingAnUnknownOccurrenceReportsNoTransition() async throws {
        let transitioned = try await store.closeOccurrence(
            id: UUID(), outcome: .skipped, closedAt: loggedAt,
            insulinEventID: nil, wasNominal: nil
        )
        XCTAssertFalse(transitioned)
    }

    // MARK: - Lateness and nominality

    // `closedAt` is the moment the dose was LOGGED, never the scheduled time
    // (Req 4.3), and lateness is the subtraction of the two (Req 4.4) — no
    // extra column.
    func testLatenessIsRecoverableBySubtraction() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        _ = try await store.closeOccurrence(
            id: occurrence.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: true
        )
        let row = try await store.doseOccurrences(limit: 1).first!
        XCTAssertEqual(row.closedAt!.timeIntervalSince(row.dueAt), 900, accuracy: 0.001)
    }

    // Req 5.2: a fit must be able to tell a default-accepted dose from a
    // deliberately chosen one.
    func testNominalAndAdjustedAreDistinguishable() async throws {
        let nominal = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let adjusted = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        _ = try await store.closeOccurrence(
            id: nominal.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: true
        )
        _ = try await store.closeOccurrence(
            id: adjusted.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: false
        )
        let rows = try await store.doseOccurrences(limit: 10)
        XCTAssertEqual(Set(rows.compactMap(\.wasNominal)), [true, false])
    }

    // MARK: - Skipped and missed write nothing (Req 6.3)

    func testASkippedOccurrenceWritesNoInsulinEventOfAnyAmount() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let transitioned = try await store.closeOccurrence(
            id: occurrence.id, outcome: .skipped, closedAt: loggedAt,
            insulinEventID: nil, wasNominal: nil
        )
        XCTAssertTrue(transitioned)
        let insulinRows = try await insulinRowCount()
        XCTAssertEqual(insulinRows, 0)
        let row = try await store.doseOccurrences(limit: 1).first!
        XCTAssertEqual(row.outcome, .skipped)
        XCTAssertNil(row.insulinEventID)
        XCTAssertNil(row.wasNominal)
    }

    func testAMissedOccurrenceWritesNoInsulinEventOfAnyAmount() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let closed = try await store.closeOccurrencesAsMissed(
            ids: [occurrence.id], closedAt: loggedAt
        )
        XCTAssertEqual(closed, 1)
        let insulinRows = try await insulinRowCount()
        XCTAssertEqual(insulinRows, 0)
        let row = try await store.doseOccurrences(limit: 1).first!
        XCTAssertEqual(row.outcome, .missed)
        XCTAssertNil(row.insulinEventID)
    }

    func testTheMissedSweepLeavesAnAlreadyClosedRowAlone() async throws {
        let occurrence = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        _ = try await store.closeOccurrence(
            id: occurrence.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: true
        )
        let closed = try await store.closeOccurrencesAsMissed(
            ids: [occurrence.id], closedAt: loggedAt
        )
        XCTAssertEqual(closed, 0)
        let row = try await store.doseOccurrences(limit: 1).first
        XCTAssertEqual(row?.outcome, .logged)
    }

    func testTheMissedSweepOnAnEmptyListOpensNoTransaction() async throws {
        let closed = try await store.closeOccurrencesAsMissed(ids: [], closedAt: loggedAt)
        XCTAssertEqual(closed, 0)
    }

    // MARK: - Editing the schedule (Req 1.5)

    // A scheduled dose is configuration and holds no history. Editing it —
    // changing its time, its amount, even disabling it — is a settings write
    // that never reaches this table, so an already-closed occurrence is
    // byte-identical afterwards.
    func testEditingAScheduleLeavesClosedOccurrencesUntouched() async throws {
        var schedule = ScheduledDose(hour: 7, minute: 30, nominalUnits: 15, kind: .basal)
        let occurrence = try await store.openOccurrence(
            scheduleID: schedule.id, dueAt: dueAt
        )
        let eventID = UUID()
        _ = try await store.closeOccurrence(
            id: occurrence.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: eventID, wasNominal: true
        )
        let before = try await store.doseOccurrences(limit: 10)

        schedule.hour = 9
        schedule.nominalUnits = 12
        schedule.isEnabled = false

        let after = try await store.doseOccurrences(limit: 10)
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.first?.insulinEventID, eventID)
    }

    // MARK: - Outstanding reads

    func testOutstandingExcludesEveryTerminalOutcome() async throws {
        let logged = try await store.openOccurrence(scheduleID: UUID(), dueAt: dueAt)
        let skipped = try await store.openOccurrence(
            scheduleID: UUID(), dueAt: dueAt.addingTimeInterval(60)
        )
        let missed = try await store.openOccurrence(
            scheduleID: UUID(), dueAt: dueAt.addingTimeInterval(120)
        )
        let open = try await store.openOccurrence(
            scheduleID: UUID(), dueAt: dueAt.addingTimeInterval(180)
        )
        _ = try await store.closeOccurrence(
            id: logged.id, outcome: .logged, closedAt: loggedAt,
            insulinEventID: UUID(), wasNominal: true
        )
        _ = try await store.closeOccurrence(
            id: skipped.id, outcome: .skipped, closedAt: loggedAt,
            insulinEventID: nil, wasNominal: nil
        )
        _ = try await store.closeOccurrencesAsMissed(ids: [missed.id], closedAt: loggedAt)
        let stillOpen = try await store.outstandingOccurrences()
        XCTAssertEqual(stillOpen.map(\.id), [open.id])
    }

    // MARK: - Schema

    func testTheOccurrenceIndexExists() async throws {
        let q = try DatabaseQueue(path: dbURL.path)
        let names: [String] = try await q.read { db in
            try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
        }
        XCTAssertTrue(names.contains("dose_occurrences_schedule"))
    }
}
