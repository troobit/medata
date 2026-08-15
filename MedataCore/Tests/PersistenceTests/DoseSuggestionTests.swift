import Foundation
import GRDB
import XCTest
@testable import Persistence

// Tests for the dose-suggestion ledger (specs/data/insulin-dosing Req 7.4,
// 7.5, 10.5). A derived side store: INSERT OR REPLACE by id, no eviction
// bound, and no `eventsDidChange` interaction on any of the three methods.

final class DoseSuggestionTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoseSuggestionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private var dbURL: URL { tempDir.appendingPathComponent("meals.sqlite") }

    private func makeRecord(
        id: UUID = UUID(),
        timestampMs: Int64 = 1_751_000_000_000,
        outcome: DoseSuggestionOutcome = .suggested,
        suppression: String? = nil,
        carbsG: Double? = 60,
        exactUnits: Double? = 12.0,
        roundedUnits: Double? = 12.0,
        crGramsPerUnit: Double = 5.0,
        crSource: RatioSource = .seed,
        fatG: Double? = nil,
        proteinG: Double? = nil,
        fpu: Double? = nil
    ) -> DoseSuggestionRecord {
        DoseSuggestionRecord(
            id: id,
            timestampMs: timestampMs,
            mealTimestampMs: timestampMs - 60_000,
            ruleID: "cr-v0",
            ruleVersion: 1,
            outcome: outcome.rawValue,
            suppression: suppression,
            carbsG: carbsG,
            carbsSource: CarbsSource.meal.rawValue,
            sourceEventID: UUID(),
            exactUnits: exactUnits,
            roundedUnits: roundedUnits,
            incrementU: 1.0,
            seedClamped: false,
            crGramsPerUnit: crGramsPerUnit,
            crSource: crSource.rawValue,
            crFitRef: nil,
            band: "breakfast",
            localHour: 8,
            utcHour: 7,
            utcOffsetS: 3600,
            iobU: 0,
            fatG: fatG,
            proteinG: proteinG,
            fpu: fpu,
            fatStale: false,
            buildStamp: "unstamped"
        )
    }

    // MARK: - Round trip

    func testSaveThenReadNewestFirst() async throws {
        let older = makeRecord(timestampMs: 1_751_000_000_000)
        let newer = makeRecord(timestampMs: 1_751_000_600_000)
        try await store.saveDoseSuggestion(older)
        try await store.saveDoseSuggestion(newer)

        let rows = try await store.doseSuggestions(limit: 10)
        XCTAssertEqual(rows.map(\.id), [newer.id, older.id], "newest first")
        XCTAssertEqual(rows[1], older, "every column round-trips unchanged")
    }

    func testLimitCapsTheResult() async throws {
        for offset in 0..<5 {
            try await store.saveDoseSuggestion(
                makeRecord(timestampMs: 1_751_000_000_000 + Int64(offset) * 60_000)
            )
        }
        let rows = try await store.doseSuggestions(limit: 2)
        XCTAssertEqual(rows.count, 2)
    }

    // The canonical direction: 60 g at 5.0 g/U is 12 U (Req 1.1, 1.4). The
    // ledger stores g/U and never its reciprocal.
    func testRatioIsStoredInGramsPerUnit() async throws {
        let record = makeRecord(carbsG: 60, exactUnits: 12.0, roundedUnits: 12.0,
                                crGramsPerUnit: 5.0)
        try await store.saveDoseSuggestion(record)

        let rows = try await store.doseSuggestions(limit: 1)
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.crGramsPerUnit, 5.0, accuracy: 1e-9)
        XCTAssertEqual((stored.carbsG ?? 0) / stored.crGramsPerUnit, 12.0, accuracy: 1e-9,
                       "carbs ÷ g/U is the unit count")
    }

    func testSuppressedRowRecordsItsContext() async throws {
        // Req 7.1 — a suppression is recorded as fully as a suggestion.
        let record = makeRecord(
            outcome: .suppressed, suppression: "belowMeaningfulDose",
            carbsG: 3, exactUnits: nil, roundedUnits: nil, crGramsPerUnit: 10.0
        )
        try await store.saveDoseSuggestion(record)

        let rows = try await store.doseSuggestions(limit: 1)
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.outcome, DoseSuggestionOutcome.suppressed.rawValue)
        XCTAssertEqual(stored.suppression, "belowMeaningfulDose")
        XCTAssertNil(stored.exactUnits)
        XCTAssertNil(stored.roundedUnits)
        XCTAssertEqual(stored.band, "breakfast", "the band is present on a suppression")
        XCTAssertEqual(stored.crGramsPerUnit, 10.0, accuracy: 1e-9)
    }

    // MARK: - Replace by id

    func testSecondSaveWithSameIdReplacesRatherThanAppends() async throws {
        let id = UUID()
        try await store.saveDoseSuggestion(makeRecord(id: id, carbsG: 60))
        try await store.saveDoseSuggestion(makeRecord(id: id, carbsG: 75))

        let rows = try await store.doseSuggestions(limit: 10)
        XCTAssertEqual(rows.count, 1, "one row per id, rewritten in place")
        XCTAssertEqual(rows[0].carbsG ?? 0, 75, accuracy: 1e-9)
    }

    // MARK: - fpu derived at write time

    func testFpuIsDerivedAtSaveAndIgnoresTheCallerSuppliedValue() async throws {
        // 20 g fat, 30 g protein → (20×9 + 30×4) / 100 = 3.0
        let record = makeRecord(fatG: 20, proteinG: 30, fpu: 999)
        try await store.saveDoseSuggestion(record)

        let rows = try await store.doseSuggestions(limit: 1)
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.fpu ?? -1, 3.0, accuracy: 1e-9)
    }

    func testFpuIsNilWhenEitherMacroIsAbsent() async throws {
        let noProtein = makeRecord(fatG: 20, proteinG: nil)
        let noFat = makeRecord(fatG: nil, proteinG: 30)
        let neither = makeRecord(fatG: nil, proteinG: nil)
        for record in [noProtein, noFat, neither] {
            try await store.saveDoseSuggestion(record)
        }

        let rows = try await store.doseSuggestions(limit: 10)
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            XCTAssertNil(row.fpu, "an absent macro is unrecorded, not zero")
        }
    }

    // MARK: - linkDose (Req 7.5)

    func testLinkDoseFillsGivenUnitsAndInsulinEventID() async throws {
        let record = makeRecord()
        try await store.saveDoseSuggestion(record)
        let eventID = UUID()

        try await store.linkDose(
            suggestionID: record.id, insulinEventID: eventID, givenUnits: 11
        )

        let rows = try await store.doseSuggestions(limit: 1)
        let stored = try XCTUnwrap(rows.first)
        XCTAssertEqual(stored.givenUnits ?? -1, 11, accuracy: 1e-9)
        XCTAssertEqual(stored.insulinEventID, eventID)
    }

    func testLinkDoseTouchesOnlyTheSideTable() async throws {
        // Req 7.3, 9.7 — the insulin event's metadata contract is medreg's.
        let dose = InsulinDose(
            timestamp: Date(timeIntervalSince1970: 1_751_000_000),
            units: 11, kind: .bolus, insulinType: "NovoRapid"
        )
        try await store.saveInsulinDose(dose)
        let record = makeRecord()
        try await store.saveDoseSuggestion(record)

        try await store.linkDose(
            suggestionID: record.id, insulinEventID: dose.id, givenUnits: 11
        )

        let q = try DatabaseQueue(path: dbURL.path)
        let metadata = try await q.read { db -> String in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT metadata FROM events WHERE id = ?",
                arguments: [dose.id.uuidString]
            ) else { throw PersistenceError.corruptRecord("row not found") }
            return row["metadata"]
        }
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(parsed.keys), ["kind", "insulin_type", "schema_version"],
                       "linkDose must not add a key to the insulin metadata contract")
    }

    // MARK: - No eventsDidChange (Req 7.4)

    func testNeitherWriteFiresEventsDidChange() async throws {
        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        let record = makeRecord()
        try await store.saveDoseSuggestion(record)
        try await store.linkDose(
            suggestionID: record.id, insulinEventID: UUID(), givenUnits: 12
        )
        _ = try await store.doseSuggestions(limit: 10)

        try await Task.sleep(nanoseconds: 200_000_000)
        let count = await counter.get()
        observer.cancel()
        XCTAssertEqual(count, 0, "suggestion rows are not events rows")
    }

    // MARK: - Upgrade from schema 7 (Req 10.5)

    func testUpgradeFromSchemaSevenKeepsEveryExistingEvent() async throws {
        // Build a schema-7 database by hand: the version-7 tables, the '7'
        // stamp, and one row of every event type. Opening it with the current
        // store must add dose_suggestions and re-stamp to 8 while leaving every
        // existing event untouched in meaning, shape and contents.
        let legacyDir = tempDir.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyURL = legacyDir.appendingPathComponent("meals.sqlite")

        let eventRows: [(id: UUID, type: String, value: Double, metadata: String)] = [
            (UUID(), EventType.meal, 42.0, #"{"v":1}"#),
            (UUID(), EventType.bsl, 5.5, "{}"),
            (UUID(), EventType.insulin, 7.5,
             #"{"kind":"bolus","insulin_type":"NovoRapid","schema_version":1}"#),
            (UUID(), EventType.intake, 30.0,
             #"{"subtype":"carb","schema_version":1,"source":"manual"}"#),
            (UUID(), EventType.activity, 45.0,
             #"{"schema_version":1,"kind":"gym","provenance":"manual"}"#)
        ]

        let legacy = try DatabaseQueue(path: legacyURL.path)
        try await legacy.write { db in
            try db.execute(sql: """
                CREATE TABLE events (
                    id          TEXT    PRIMARY KEY,
                    timestamp   INTEGER NOT NULL,
                    event_type  TEXT    NOT NULL,
                    value       REAL,
                    metadata    TEXT    NOT NULL
                );
                CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
                """)
            for (index, row) in eventRows.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO events (id, timestamp, event_type, value, metadata)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        row.id.uuidString, 1_751_000_000_000 + Int64(index) * 1000,
                        row.type, row.value, row.metadata
                    ]
                )
            }
            try db.execute(sql: "INSERT INTO meta (k, v) VALUES ('schema_version', '7')")
        }

        let upgraded = try GRDBPersistenceStore(dbURL: legacyURL, artefactsBaseURL: legacyDir)
        _ = try await upgraded.doseSuggestions(limit: 1)  // the new table exists

        let check = try DatabaseQueue(path: legacyURL.path)
        try await check.read { db in
            let version = try String.fetchOne(
                db, sql: "SELECT v FROM meta WHERE k = 'schema_version'"
            )
            XCTAssertEqual(version, "8", "the upgrade re-stamps the version")

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, eventRows.count, "no event is lost")

            for expected in eventRows {
                let row = try XCTUnwrap(
                    Row.fetchOne(db, sql: "SELECT * FROM events WHERE id = ?",
                                 arguments: [expected.id.uuidString]),
                    "event \(expected.type) survives"
                )
                let type: String = row["event_type"]
                XCTAssertEqual(type, expected.type)
                let value: Double = row["value"]
                XCTAssertEqual(value, expected.value, accuracy: 1e-9)
                let metadata: String = row["metadata"]
                XCTAssertEqual(metadata, expected.metadata,
                               "metadata is byte-for-byte unchanged")
            }
        }
    }
}

private actor TickCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}
