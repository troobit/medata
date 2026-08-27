import Foundation
import GRDB
import XCTest
@testable import Persistence

// Dropping the dose-suggestion ledger (specs/data/insulin-dosing Decision 18,
// Req 6.11, 10.5).
//
// The dose is a pure function of recorded events and the settings in force, so
// a stored copy of its output was a cache with migration obligations, not a
// record. The table goes; everything it was derived from — the events — is
// untouched.
final class DoseSuggestionsDropTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DoseSuggestionsDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private let eventRows: [(id: UUID, type: String, value: Double, metadata: String)] = [
        (UUID(), EventType.meal, 42.0, #"{"v":1}"#),
        (UUID(), EventType.bsl, 5.5, "{}"),
        (UUID(), EventType.insulin, 7.5,
         #"{"kind":"bolus","insulin_type":"NovoRapid","schema_version":1}"#),
        (UUID(), EventType.intake, 30.0,
         #"{"subtype":"carb","schema_version":1,"source":"manual"}"#),
        (UUID(), EventType.activity, 45.0,
         #"{"schema_version":1,"kind":"gym","provenance":"manual"}"#)
    ]

    private func writeEvents(_ db: Database) throws {
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
    }

    private func tableExists(_ db: Database, _ name: String) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            arguments: [name]
        ) ?? 0 > 0
    }

    private func schemaVersion(_ db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT v FROM meta WHERE k = 'schema_version'")
    }

    // MARK: - The one surviving migration

    // A database stamped at the ledger's own version, carrying rows, is what
    // the developer device actually holds. Opening it must leave no table, no
    // rows, and a stamp that has moved exactly one step.
    func testSchemaElevenDatabaseWithLedgerRowsMigratesClean() async throws {
        let legacyURL = tempDir.appendingPathComponent("meals.sqlite")
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
                CREATE TABLE dose_suggestions (
                    id                TEXT    PRIMARY KEY,
                    timestamp         INTEGER NOT NULL,
                    meal_timestamp    INTEGER NOT NULL,
                    outcome           TEXT    NOT NULL,
                    carbs_g           REAL,
                    cr_g_per_u        REAL    NOT NULL
                );
                CREATE INDEX dose_suggestions_timestamp ON dose_suggestions(timestamp);
                """)
            try self.writeEvents(db)
            for index in 0..<3 {
                try db.execute(
                    sql: """
                        INSERT INTO dose_suggestions
                            (id, timestamp, meal_timestamp, outcome, carbs_g, cr_g_per_u)
                        VALUES (?, ?, ?, 'suggested', 60.0, 5.0)
                        """,
                    arguments: [
                        UUID().uuidString,
                        1_751_000_000_000 + Int64(index) * 1000,
                        1_751_000_000_000 + Int64(index) * 1000
                    ]
                )
            }
            try db.execute(sql: "INSERT INTO meta (k, v) VALUES ('schema_version', '11')")
        }

        _ = try GRDBPersistenceStore(dbURL: legacyURL, artefactsBaseURL: tempDir)

        let check = try DatabaseQueue(path: legacyURL.path)
        try await check.read { db in
            XCTAssertFalse(try self.tableExists(db, "dose_suggestions"),
                           "the ledger table is dropped, rows and all")
            XCTAssertEqual(try self.schemaVersion(db), "12",
                           "the stamp bumps exactly once")

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, self.eventRows.count,
                           "no event is lost to the drop (Req 10.5)")
        }
    }

    // Opening twice must be a no-op the second time: the drop is
    // DROP ... IF EXISTS and the stamp is already current.
    func testMigrationIsIdempotentAcrossReopens() async throws {
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        _ = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
        _ = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)

        let check = try DatabaseQueue(path: dbURL.path)
        try await check.read { db in
            XCTAssertFalse(try self.tableExists(db, "dose_suggestions"))
            XCTAssertEqual(try self.schemaVersion(db), "12")
        }
    }

    // A fresh database never creates the table in the first place.
    func testFreshDatabaseHasNoLedgerTable() async throws {
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        _ = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)

        let check = try DatabaseQueue(path: dbURL.path)
        try await check.read { db in
            XCTAssertFalse(try self.tableExists(db, "dose_suggestions"))
            XCTAssertTrue(try self.tableExists(db, "protected_outcomes"),
                          "the other side tables are untouched by the drop")
        }
    }

    // MARK: - Upgrade from schema 7 (Req 10.5)

    // The oldest database the drop has to cross. Every event survives, and the
    // table the version-8 code path once created is never created here.
    func testUpgradeFromSchemaSevenKeepsEveryExistingEvent() async throws {
        let legacyDir = tempDir.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyURL = legacyDir.appendingPathComponent("meals.sqlite")

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
            try self.writeEvents(db)
            try db.execute(sql: "INSERT INTO meta (k, v) VALUES ('schema_version', '7')")
        }

        _ = try GRDBPersistenceStore(dbURL: legacyURL, artefactsBaseURL: legacyDir)

        let check = try DatabaseQueue(path: legacyURL.path)
        try await check.read { db in
            XCTAssertEqual(try self.schemaVersion(db), "12",
                           "the upgrade re-stamps the version")
            XCTAssertFalse(try self.tableExists(db, "dose_suggestions"))

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, self.eventRows.count, "no event is lost")

            for row in self.eventRows {
                let stored = try Row.fetchOne(
                    db, sql: "SELECT * FROM events WHERE id = ?", arguments: [row.id.uuidString]
                )
                XCTAssertNotNil(stored, "event \(row.type) survives the upgrade")
                XCTAssertEqual(stored?["event_type"], row.type)
                XCTAssertEqual(stored?["value"], row.value)
                XCTAssertEqual(stored?["metadata"], row.metadata,
                               "metadata is untouched in meaning and shape")
            }
        }
    }
}
