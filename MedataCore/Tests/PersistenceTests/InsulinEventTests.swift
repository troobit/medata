import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the insulin event surface (PRD regression-suggestion-integration,
// Core events). One `events` row per dose, byte-for-byte per medreg's
// convention (medreg docs/insulin-event-convention.md): value = units,
// timestamp = UTC ms, metadata = {kind, insulin_type, schema_version, note?}.

final class InsulinEventTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InsulinEventTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeDose(
        id: UUID = UUID(),
        timestamp: Date = Date(timeIntervalSince1970: 1_751_000_000.25),
        units: Double = 10.0,
        kind: InsulinKind = .bolus,
        insulinType: String = "NovoRapid",
        note: String? = nil
    ) -> InsulinDose {
        InsulinDose(
            id: id, timestamp: timestamp, units: units,
            kind: kind, insulinType: insulinType, note: note
        )
    }

    // MARK: - Raw-row shape per the medreg convention

    func testSaveWritesOneRawRowPerConvention() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_751_000_000.25)
        let dose = makeDose(timestamp: timestamp, units: 7.5, kind: .basal,
                            insulinType: "Lantus")
        try await store.saveInsulinDose(dose)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM events")
            XCTAssertEqual(rows.count, 1, "exactly one events row per dose")
            let row = rows[0]
            let id: String = row["id"]
            XCTAssertEqual(id, dose.id.uuidString)
            let timestampMs: Int64 = row["timestamp"]
            XCTAssertEqual(timestampMs, 1_751_000_000_250, "timestamp is UTC ms")
            let eventType: String = row["event_type"]
            XCTAssertEqual(eventType, EventType.insulin)
            let value: Double = row["value"]
            XCTAssertEqual(value, 7.5, accuracy: 1e-9, "value carries units")
        }
    }

    func testMetadataShapeWithoutNote() async throws {
        let dose = makeDose(kind: .bolus, insulinType: "NovoRapid", note: nil)
        try await store.saveInsulinDose(dose)

        let metadata = try await fetchMetadata(id: dose.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["kind", "insulin_type", "schema_version"],
                       "note must be ABSENT — not null — when not provided")
        XCTAssertEqual(parsed["kind"] as? String, "bolus")
        XCTAssertEqual(parsed["insulin_type"] as? String, "NovoRapid")
        XCTAssertEqual(parsed["schema_version"] as? Int, 1)
        // schema_version must serialise as a JSON integer, not "1" or 1.0.
        XCTAssertTrue(metadata.contains("\"schema_version\":1"),
                      "schema_version must be a bare JSON integer, got: \(metadata)")
    }

    func testMetadataShapeWithNote() async throws {
        let dose = makeDose(note: "pre-run reduction")
        try await store.saveInsulinDose(dose)

        let metadata = try await fetchMetadata(id: dose.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["kind", "insulin_type", "schema_version", "note"])
        XCTAssertEqual(parsed["note"] as? String, "pre-run reduction")
    }

    func testBasalKindRoundTrips() async throws {
        let dose = makeDose(kind: .basal, insulinType: "Lantus")
        try await store.saveInsulinDose(dose)
        let metadata = try await fetchMetadata(id: dose.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(parsed["kind"] as? String, "basal")
    }

    // MARK: - events(in:type:) filter includes insulin

    func testEventsInRangeFiltersByInsulinType() async throws {
        let t = Date(timeIntervalSince1970: 1_751_000_000)
        let dose = makeDose(timestamp: t)
        try await store.saveInsulinDose(dose)

        // Hand-insert a bsl row and a meal-shaped row at the same instant.
        let bslId = UUID()
        let mealId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, 5.5, '{}'), (?, ?, ?, 42.0, '{}')
                    """,
                arguments: [
                    bslId.uuidString, Int64(t.timeIntervalSince1970 * 1000), EventType.bsl,
                    mealId.uuidString, Int64(t.timeIntervalSince1970 * 1000), EventType.meal
                ]
            )
        }

        let range = t.addingTimeInterval(-60)...t.addingTimeInterval(60)
        let insulinOnly = try await store.events(in: range, type: EventType.insulin)
        XCTAssertEqual(insulinOnly.map(\.id), [dose.id],
                       "insulin filter returns saved doses and excludes meal/bsl rows")
        XCTAssertEqual(insulinOnly[0].eventType, EventType.insulin)
        XCTAssertEqual(insulinOnly[0].value ?? -1, dose.units, accuracy: 1e-9)

        let mealOnly = try await store.events(in: range, type: EventType.meal)
        XCTAssertEqual(mealOnly.map(\.id), [mealId], "meal filter excludes insulin rows")

        let all = try await store.events(in: range, type: nil)
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - eventsDidChange ticks

    func testSaveFiresEventsDidChangeOnce() async throws {
        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        try await store.saveInsulinDose(makeDose())

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "one tick per save")
    }

    func testDeleteFiresEventsDidChangeOnce() async throws {
        let dose = makeDose()
        try await store.saveInsulinDose(dose)

        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        try await store.deleteInsulinEvent(id: dose.id)

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "one tick per delete")
    }

    // MARK: - Store-layer bounds (Core 4)

    func testSaveRejectsNegativeUnits() async throws {
        do {
            try await store.saveInsulinDose(makeDose(units: -0.5))
            XCTFail("expected insulinUnitsOutOfRange")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError,
                           .insulinUnitsOutOfRange(-0.5))
        }
    }

    func testSaveRejectsUnitsAboveSixty() async throws {
        do {
            try await store.saveInsulinDose(makeDose(units: 60.5))
            XCTFail("expected insulinUnitsOutOfRange")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError,
                           .insulinUnitsOutOfRange(60.5))
        }
    }

    func testSaveAcceptsZeroAndSixtyUnits() async throws {
        // 0 and 60 are accepted at the store; the UI enforces its own floor.
        let zero = makeDose(units: 0)
        let sixty = makeDose(units: 60)
        try await store.saveInsulinDose(zero)
        try await store.saveInsulinDose(sixty)

        let range = zero.timestamp.addingTimeInterval(-60)...zero.timestamp.addingTimeInterval(60)
        let saved = try await store.events(in: range, type: EventType.insulin)
        XCTAssertEqual(saved.count, 2)
    }

    func testRejectedSaveWritesNoRow() async throws {
        try? await store.saveInsulinDose(makeDose(units: -1))
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, 0)
        }
    }

    // MARK: - Delete scoping (Core 3)

    func testDeleteRemovesOnlyTheTargetInsulinRow() async throws {
        let first = makeDose()
        let second = makeDose()
        try await store.saveInsulinDose(first)
        try await store.saveInsulinDose(second)

        try await store.deleteInsulinEvent(id: first.id)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM events")
            XCTAssertEqual(ids, [second.id.uuidString])
        }
    }

    func testDeleteCannotTouchMealOrBslRowsOrSideTables() async throws {
        // Hand-insert a meal row (with artefact + correction side rows) and a
        // bsl row, then aim deleteInsulinEvent at both ids. The event_type
        // gate must leave everything in place.
        let mealId = UUID()
        let bslId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, 0, ?, 42.0, '{}'), (?, 0, ?, 5.5, '{}')
                    """,
                arguments: [mealId.uuidString, EventType.meal,
                            bslId.uuidString, EventType.bsl]
            )
            try db.execute(
                sql: """
                    INSERT INTO meal_artefacts (meal_id, kind, view_id, filename, bytes_size)
                    VALUES (?, 'image', 'nadir', 'nadir.image', 1)
                    """,
                arguments: [mealId.uuidString]
            )
            try db.execute(
                sql: """
                    INSERT INTO corrections (meal_id, created_at, correction_json)
                    VALUES (?, 1000, '{}')
                    """,
                arguments: [mealId.uuidString]
            )
        }

        try await store.deleteInsulinEvent(id: mealId)
        try await store.deleteInsulinEvent(id: bslId)

        try await q.read { db in
            let eventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(eventCount, 2, "meal and bsl rows must survive")
            let artefactCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM meal_artefacts") ?? -1
            XCTAssertEqual(artefactCount, 1, "side tables must be untouched")
            let correctionCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM corrections") ?? -1
            XCTAssertEqual(correctionCount, 1, "side tables must be untouched")
        }
    }

    // MARK: - Helpers

    private func fetchMetadata(id: UUID) async throws -> String {
        let q = try DatabaseQueue(path: dbURL.path)
        return try await q.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [id.uuidString]
            ) else { throw PersistenceError.corruptRecord("row not found") }
            return row["metadata"]
        }
    }
}

private actor TickCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}
