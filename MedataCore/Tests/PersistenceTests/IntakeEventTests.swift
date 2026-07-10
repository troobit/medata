import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the manual carb intake event surface (specs/data/manual-carb-intake,
// Phase 1). One `events` row per entry, mirroring the insulin convention
// (EventType.insulin / InsulinEventTests.swift): value = carbs (g),
// timestamp = the user-set time, metadata = {subtype, schema_version, source,
// preset_id?, protein_g?, fat_g?, fibre_g?}.

final class IntakeEventTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntakeEventTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeEntry(
        id: UUID = UUID(),
        timestamp: Date = Date(timeIntervalSince1970: 1_751_000_000.25),
        carbsG: Double = 45.0,
        macros: IntakeMacros = IntakeMacros(),
        source: IntakeSource = .manual,
        presetID: UUID? = nil
    ) -> IntakeEntry {
        IntakeEntry(
            id: id, timestamp: timestamp, carbsG: carbsG,
            macros: macros, source: source, presetID: presetID
        )
    }

    // MARK: - Raw-row shape

    func testSaveWritesOneRawRowPerConvention() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_751_000_000.25)
        let entry = makeEntry(timestamp: timestamp, carbsG: 45.0)
        try await store.saveIntakeEntry(entry)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM events")
            XCTAssertEqual(rows.count, 1, "exactly one events row per entry")
            let row = rows[0]
            let id: String = row["id"]
            XCTAssertEqual(id, entry.id.uuidString)
            let timestampMs: Int64 = row["timestamp"]
            XCTAssertEqual(timestampMs, 1_751_000_000_250, "timestamp is UTC ms")
            let eventType: String = row["event_type"]
            XCTAssertEqual(eventType, EventType.intake)
            let value: Double = row["value"]
            XCTAssertEqual(value, 45.0, accuracy: 1e-9, "value carries carbs")
        }
    }

    func testMetadataShapeWithoutMacros() async throws {
        let entry = makeEntry(source: .manual)
        try await store.saveIntakeEntry(entry)

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["subtype", "schema_version", "source"],
                       "macro keys must be ABSENT — not null — when not provided")
        XCTAssertEqual(parsed["subtype"] as? String, "carb")
        XCTAssertEqual(parsed["source"] as? String, "manual")
        XCTAssertEqual(parsed["schema_version"] as? Int, 1)
        XCTAssertTrue(metadata.contains("\"schema_version\":1"),
                      "schema_version must be a bare JSON integer, got: \(metadata)")
    }

    func testMetadataShapeWithMacros() async throws {
        let macros = IntakeMacros(proteinG: 12.0, fatG: 8.0, fibreG: 3.0)
        let entry = makeEntry(macros: macros, source: .manual)
        try await store.saveIntakeEntry(entry)

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys),
                       ["subtype", "schema_version", "source", "protein_g", "fat_g", "fibre_g"])
        XCTAssertEqual(parsed["protein_g"] as? Double, 12.0)
        XCTAssertEqual(parsed["fat_g"] as? Double, 8.0)
        XCTAssertEqual(parsed["fibre_g"] as? Double, 3.0)
    }

    func testMetadataShapeWithPartialMacros() async throws {
        // Only protein set — fat_g and fibre_g must be absent, not null.
        let macros = IntakeMacros(proteinG: 20.0)
        let entry = makeEntry(macros: macros, source: .manual)
        try await store.saveIntakeEntry(entry)

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["subtype", "schema_version", "source", "protein_g"])
        XCTAssertEqual(parsed["protein_g"] as? Double, 20.0)
    }

    func testMetadataShapeQuickaddIncludesPresetID() async throws {
        let presetID = UUID()
        let entry = makeEntry(source: .quickadd, presetID: presetID)
        try await store.saveIntakeEntry(entry)

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["subtype", "schema_version", "source", "preset_id"])
        XCTAssertEqual(parsed["source"] as? String, "quickadd")
        XCTAssertEqual(parsed["preset_id"] as? String, presetID.uuidString)
    }

    func testMetadataShapeManualOmitsPresetID() async throws {
        let entry = makeEntry(source: .manual, presetID: nil)
        try await store.saveIntakeEntry(entry)

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertFalse(parsed.keys.contains("preset_id"),
                       "preset_id must be ABSENT — not null — for a manual entry")
    }

    // MARK: - events(in:type:) filter includes intake

    func testEventsInRangeFiltersByIntakeType() async throws {
        let t = Date(timeIntervalSince1970: 1_751_000_000)
        let entry = makeEntry(timestamp: t)
        try await store.saveIntakeEntry(entry)

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
        let intakeOnly = try await store.events(in: range, type: EventType.intake)
        XCTAssertEqual(intakeOnly.map(\.id), [entry.id],
                       "intake filter returns saved entries and excludes meal/bsl rows")
        XCTAssertEqual(intakeOnly[0].eventType, EventType.intake)
        XCTAssertEqual(intakeOnly[0].value ?? -1, entry.carbsG, accuracy: 1e-9)

        let mealOnly = try await store.events(in: range, type: EventType.meal)
        XCTAssertEqual(mealOnly.map(\.id), [mealId], "meal filter excludes intake rows")

        let all = try await store.events(in: range, type: nil)
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - updateIntakeEntry

    func testUpdateChangesSameRowID() async throws {
        let entry = makeEntry(carbsG: 30.0, macros: IntakeMacros())
        try await store.saveIntakeEntry(entry)

        let updated = IntakeEntry(
            id: entry.id,
            timestamp: entry.timestamp.addingTimeInterval(3600),
            carbsG: 55.0,
            macros: IntakeMacros(proteinG: 10.0),
            source: entry.source,
            presetID: entry.presetID
        )
        try await store.updateIntakeEntry(updated)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM events")
            XCTAssertEqual(rows.count, 1, "update must not add a row")
            let row = rows[0]
            let id: String = row["id"]
            XCTAssertEqual(id, entry.id.uuidString, "update keeps the same row id")
            let value: Double = row["value"]
            XCTAssertEqual(value, 55.0, accuracy: 1e-9)
            let timestampMs: Int64 = row["timestamp"]
            XCTAssertEqual(timestampMs, Int64(updated.timestamp.timeIntervalSince1970 * 1000))
        }

        let metadata = try await fetchMetadata(id: entry.id)
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(parsed["protein_g"] as? Double, 10.0)
    }

    func testUpdateCannotTouchOtherEventTypeRows() async throws {
        // A row that is NOT event_type=intake sharing the same id must survive
        // an updateIntakeEntry aimed at it (mirrors the delete-scoping gate).
        let sharedId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, 0, ?, 5.5, '{}')
                    """,
                arguments: [sharedId.uuidString, EventType.bsl]
            )
        }

        let entry = makeEntry(id: sharedId, carbsG: 20.0)
        try? await store.updateIntakeEntry(entry)

        try await q.read { db in
            let eventType: String = try XCTUnwrap(
                String.fetchOne(db, sql: "SELECT event_type FROM events WHERE id = ?",
                                arguments: [sharedId.uuidString]))
            XCTAssertEqual(eventType, EventType.bsl, "non-intake row must survive")
            let value: Double = try XCTUnwrap(
                Double.fetchOne(db, sql: "SELECT value FROM events WHERE id = ?",
                                arguments: [sharedId.uuidString]))
            XCTAssertEqual(value, 5.5, accuracy: 1e-9, "non-intake row's value must be untouched")
        }
    }

    // MARK: - deleteIntakeEntry scoping

    func testDeleteRemovesOnlyTheTargetIntakeRow() async throws {
        let first = makeEntry()
        let second = makeEntry()
        try await store.saveIntakeEntry(first)
        try await store.saveIntakeEntry(second)

        try await store.deleteIntakeEntry(id: first.id)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM events")
            XCTAssertEqual(ids, [second.id.uuidString])
        }
    }

    func testDeleteCannotTouchMealInsulinOrBslRowsSharingID() async throws {
        // A same-id meal/insulin/bsl row must survive deleteIntakeEntry.
        let mealId = UUID()
        let insulinId = UUID()
        let bslId = UUID()
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, 0, ?, 42.0, '{}'), (?, 0, ?, 7.5, '{}'), (?, 0, ?, 5.5, '{}')
                    """,
                arguments: [
                    mealId.uuidString, EventType.meal,
                    insulinId.uuidString, EventType.insulin,
                    bslId.uuidString, EventType.bsl
                ]
            )
        }

        try await store.deleteIntakeEntry(id: mealId)
        try await store.deleteIntakeEntry(id: insulinId)
        try await store.deleteIntakeEntry(id: bslId)

        try await q.read { db in
            let eventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(eventCount, 3, "meal, insulin, and bsl rows must survive")
        }
    }

    // MARK: - eventsDidChange ticks

    func testSaveFiresEventsDidChangeOnce() async throws {
        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        try await store.saveIntakeEntry(makeEntry())

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "one tick per save")
    }

    func testUpdateFiresEventsDidChangeOnce() async throws {
        let entry = makeEntry()
        try await store.saveIntakeEntry(entry)

        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        let updated = IntakeEntry(
            id: entry.id, timestamp: entry.timestamp, carbsG: 60.0,
            macros: entry.macros, source: entry.source, presetID: entry.presetID
        )
        try await store.updateIntakeEntry(updated)

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "one tick per update")
    }

    func testDeleteFiresEventsDidChangeOnce() async throws {
        let entry = makeEntry()
        try await store.saveIntakeEntry(entry)

        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        try await store.deleteIntakeEntry(id: entry.id)

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 1, "one tick per delete")
    }

    // MARK: - Store-layer bounds (Req 1.4)

    func testSaveRejectsCarbsBelowOne() async throws {
        do {
            try await store.saveIntakeEntry(makeEntry(carbsG: 0.5))
            XCTFail("expected intakeCarbsOutOfRange")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError,
                           .intakeCarbsOutOfRange(0.5))
        }
    }

    func testSaveRejectsCarbsAboveNineNineNine() async throws {
        do {
            try await store.saveIntakeEntry(makeEntry(carbsG: 999.5))
            XCTFail("expected intakeCarbsOutOfRange")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError,
                           .intakeCarbsOutOfRange(999.5))
        }
    }

    func testSaveAcceptsOneAndNineNineNine() async throws {
        let low = makeEntry(carbsG: 1)
        let high = makeEntry(carbsG: 999)
        try await store.saveIntakeEntry(low)
        try await store.saveIntakeEntry(high)

        let range = low.timestamp.addingTimeInterval(-60)...low.timestamp.addingTimeInterval(60)
        let saved = try await store.events(in: range, type: EventType.intake)
        XCTAssertEqual(saved.count, 2)
    }

    func testRejectedSaveWritesNoRow() async throws {
        try? await store.saveIntakeEntry(makeEntry(carbsG: 1000))
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, 0)
        }
    }

    func testUpdateRejectsCarbsOutOfRange() async throws {
        let entry = makeEntry(carbsG: 45.0)
        try await store.saveIntakeEntry(entry)

        let tooLow = IntakeEntry(
            id: entry.id, timestamp: entry.timestamp, carbsG: 0.0,
            macros: entry.macros, source: entry.source, presetID: entry.presetID
        )
        do {
            try await store.updateIntakeEntry(tooLow)
            XCTFail("expected intakeCarbsOutOfRange")
        } catch {
            XCTAssertEqual(error as? Persistence.PersistenceError,
                           .intakeCarbsOutOfRange(0.0))
        }

        // Original row must be untouched by the rejected update.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let value: Double = try XCTUnwrap(
                Double.fetchOne(db, sql: "SELECT value FROM events WHERE id = ?",
                                arguments: [entry.id.uuidString]))
            XCTAssertEqual(value, 45.0, accuracy: 1e-9)
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
