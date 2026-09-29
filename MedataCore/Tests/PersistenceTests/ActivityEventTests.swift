import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the activity event surface (specs/data/activity-events Req 1.5,
// 2.2, 5.1). One `events` row per activity: value = duration in minutes and
// NULL when unrecorded, timestamp = the activity start in UTC ms, metadata =
// {schema_version, kind, provenance, note?} with `character` deliberately
// absent.

final class ActivityEventTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityEventTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var dbURL: URL { tempDir.appendingPathComponent("meals.sqlite") }

    private let epoch = Date(timeIntervalSince1970: 1_751_000_000.25)

    // MARK: - Character mapping (Req 2.2)

    func testCharacterIsDefinedForEveryKind() {
        // The switch in ActivityKind.character has no `default`, so this is a
        // build-time guarantee; the test pins the classification itself.
        let expected: [ActivityKind: ActivityCharacter] = [
            .swim: .aerobic,
            .cycle: .aerobic,
            .run: .aerobic,
            .walk: .aerobic,
            .gym: .anaerobic,
            .waterpolo: .mixed,
            .other: .mixed
        ]
        XCTAssertEqual(Set(expected.keys), Set(ActivityKind.allCases),
                       "every shipped kind must be classified")
        for kind in ActivityKind.allCases {
            XCTAssertEqual(kind.character, expected[kind], "character for \(kind.rawValue)")
        }
    }

    // MARK: - Raw-row shape

    func testSaveWritesOneRawRowWithDurationInValue() async throws {
        let activity = ActivityEvent(
            timestamp: epoch, kind: .waterpolo, durationMinutes: 75
        )
        try await store.saveActivity(activity)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM events")
            XCTAssertEqual(rows.count, 1, "exactly one events row per activity")
            let row = rows[0]
            let id: String = row["id"]
            XCTAssertEqual(id, activity.id.uuidString)
            let timestampMs: Int64 = row["timestamp"]
            XCTAssertEqual(timestampMs, 1_751_000_000_250, "timestamp is UTC ms")
            let eventType: String = row["event_type"]
            XCTAssertEqual(eventType, EventType.activity)
            let value: Double = row["value"]
            XCTAssertEqual(value, 75, accuracy: 1e-9, "value carries duration minutes")
        }
    }

    func testMetadataShapeWithoutNote() async throws {
        let activity = ActivityEvent(timestamp: epoch, kind: .swim, durationMinutes: 30)
        try await store.saveActivity(activity)

        let parsed = try await fetchMetadataObject(id: activity.id)
        XCTAssertEqual(Set(parsed.keys), ["schema_version", "kind", "provenance"],
                       "note must be ABSENT — not null — when not provided")
        XCTAssertEqual(parsed["kind"] as? String, "swim")
        XCTAssertEqual(parsed["provenance"] as? String, "manual")
        XCTAssertEqual(parsed["schema_version"] as? Int, 1)

        let metadata = try await fetchMetadata(id: activity.id)
        XCTAssertTrue(metadata.contains("\"schema_version\":1"),
                      "schema_version must be a bare JSON integer, got: \(metadata)")
    }

    func testMetadataShapeWithNote() async throws {
        let activity = ActivityEvent(
            timestamp: epoch, kind: .gym, durationMinutes: 45,
            provenance: .healthkit, note: "heavy legs"
        )
        try await store.saveActivity(activity)

        let parsed = try await fetchMetadataObject(id: activity.id)
        XCTAssertEqual(Set(parsed.keys),
                       ["schema_version", "kind", "provenance", "note"])
        XCTAssertEqual(parsed["note"] as? String, "heavy legs")
        XCTAssertEqual(parsed["provenance"] as? String, "healthkit")
    }

    func testMetadataNeverCarriesCharacter() async throws {
        // Two sources of truth for the field a later model keys on is the
        // defect this omission avoids.
        for kind in ActivityKind.allCases {
            let activity = ActivityEvent(timestamp: epoch, kind: kind)
            try await store.saveActivity(activity)
            let parsed = try await fetchMetadataObject(id: activity.id)
            XCTAssertNil(parsed["character"], "character must not be stored for \(kind.rawValue)")
        }
    }

    // MARK: - Absent duration is nil, never zero (Req 1.5)

    func testNilDurationOmitsValueAndDecodesBackToNil() async throws {
        let activity = ActivityEvent(timestamp: epoch, kind: .walk, durationMinutes: nil)
        try await store.saveActivity(activity)

        let q = try DatabaseQueue(path: dbURL.path)
        let stored = try await q.read { db -> Double? in
            try Double.fetchOne(
                db, sql: "SELECT value FROM events WHERE id = ?",
                arguments: [activity.id.uuidString]
            )
        }
        XCTAssertNil(stored, "an unrecorded duration is SQL NULL, never 0")

        let loaded = try await store.activities(
            before: epoch, within: ActivityEvent.defaultLookback
        )
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].durationMinutes, "nil duration decodes back to nil, not 0")
    }

    // MARK: - Round trip through the generic events reader

    func testRoundTripViaEventsInRange() async throws {
        let activity = ActivityEvent(
            timestamp: epoch, kind: .cycle, durationMinutes: 90, note: "commute"
        )
        try await store.saveActivity(activity)

        let range = epoch.addingTimeInterval(-60)...epoch.addingTimeInterval(60)
        let events = try await store.events(in: range, type: EventType.activity)
        XCTAssertEqual(events.map(\.id), [activity.id])
        XCTAssertEqual(events[0].value ?? -1, 90, accuracy: 1e-9)

        let loaded = try await store.activities(before: epoch, within: 3600)
        XCTAssertEqual(loaded, [activity], "save → read returns the same values")
    }

    // MARK: - Lookback boundaries (Req 5.1)

    func testLookbackExcludesLowerBoundAndIncludesUpperBound() async throws {
        let instant = Date(timeIntervalSince1970: 1_751_000_000)
        let interval: TimeInterval = 3600

        let atLowerBound = ActivityEvent(
            timestamp: instant.addingTimeInterval(-interval), kind: .run
        )
        let justInside = ActivityEvent(
            timestamp: instant.addingTimeInterval(-interval + 1), kind: .walk
        )
        let atInstant = ActivityEvent(timestamp: instant, kind: .swim)
        let afterInstant = ActivityEvent(
            timestamp: instant.addingTimeInterval(1), kind: .gym
        )
        for activity in [atLowerBound, justInside, atInstant, afterInstant] {
            try await store.saveActivity(activity)
        }

        let loaded = try await store.activities(before: instant, within: interval)
        XCTAssertEqual(loaded.map(\.id), [atInstant.id, justInside.id],
                       "(instant - interval, instant]: lower bound excluded, "
                       + "instant included, newest first")
    }

    func testLookbackReturnsNewestFirst() async throws {
        let instant = Date(timeIntervalSince1970: 1_751_000_000)
        let oldest = ActivityEvent(timestamp: instant.addingTimeInterval(-3000), kind: .run)
        let middle = ActivityEvent(timestamp: instant.addingTimeInterval(-2000), kind: .gym)
        let newest = ActivityEvent(timestamp: instant.addingTimeInterval(-1000), kind: .swim)
        for activity in [middle, oldest, newest] {
            try await store.saveActivity(activity)
        }

        let loaded = try await store.activities(before: instant, within: 3600)
        XCTAssertEqual(loaded.map(\.id), [newest.id, middle.id, oldest.id])
    }

    func testLookbackOnEmptyStoreIsAnOrdinaryEmptyResult() async throws {
        let loaded = try await store.activities(
            before: epoch, within: ActivityEvent.defaultLookback
        )
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLookbackIgnoresOtherEventTypes() async throws {
        let instant = Date(timeIntervalSince1970: 1_751_000_000)
        let activity = ActivityEvent(timestamp: instant, kind: .run, durationMinutes: 20)
        try await store.saveActivity(activity)
        try await store.saveInsulinDose(
            InsulinDose(timestamp: instant, units: 4, kind: .bolus, insulinType: "NovoRapid")
        )

        let loaded = try await store.activities(before: instant, within: 3600)
        XCTAssertEqual(loaded.map(\.id), [activity.id])
    }

    func testLookbackDropsUndecodableRows() async throws {
        let instant = Date(timeIntervalSince1970: 1_751_000_000)
        let good = ActivityEvent(timestamp: instant, kind: .run)
        try await store.saveActivity(good)

        // Hand-insert an activity row whose kind is outside the shipped
        // vocabulary and one whose metadata is not JSON at all.
        let q = try DatabaseQueue(path: dbURL.path)
        try await q.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, NULL, ?), (?, ?, ?, NULL, 'not json')
                    """,
                arguments: [
                    UUID().uuidString, Int64(instant.timeIntervalSince1970 * 1000),
                    EventType.activity,
                    #"{"schema_version":1,"kind":"kitesurf","provenance":"manual"}"#,
                    UUID().uuidString, Int64(instant.timeIntervalSince1970 * 1000),
                    EventType.activity
                ]
            )
        }

        let loaded = try await store.activities(before: instant, within: 3600)
        XCTAssertEqual(loaded.map(\.id), [good.id],
                       "undecodable rows are dropped, not thrown")
    }

    // MARK: - Delete scoping (Req 3.6)

    func testDeleteRemovesOnlyTheTargetActivityRow() async throws {
        let first = ActivityEvent(timestamp: epoch, kind: .run)
        let second = ActivityEvent(timestamp: epoch, kind: .swim)
        try await store.saveActivity(first)
        try await store.saveActivity(second)

        try await store.deleteActivityEvent(id: first.id)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT id FROM events")
            XCTAssertEqual(ids, [second.id.uuidString])
        }
    }

    func testDeleteCannotTouchOtherEventTypes() async throws {
        let dose = InsulinDose(
            timestamp: epoch, units: 3, kind: .bolus, insulinType: "NovoRapid"
        )
        try await store.saveInsulinDose(dose)

        try await store.deleteActivityEvent(id: dose.id)

        let q = try DatabaseQueue(path: dbURL.path)
        try await q.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, 1, "the event_type gate protects the insulin row")
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

    private func fetchMetadataObject(id: UUID) async throws -> [String: Any] {
        let metadata = try await fetchMetadata(id: id)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
    }
}
