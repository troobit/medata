import Foundation
import GRDB
import PortableContracts
import ZIPFoundation

// GRDB-backed PersistenceStore. Backs the long-form event log per
// specs/data/event-log-schema/design.md. Each meal is one row in `events` with
// event_type=EventType.meal; the verbatim protobuf-JSON record sits inside
// the `metadata` JSON blob (Decision 6 / Decision 31).
public final class GRDBPersistenceStore: PersistenceStore, @unchecked Sendable {

    private let queue: DatabaseQueue
    private let dbURL: URL
    private let artefactsBaseURL: URL
    private let changeBroadcaster = ChangeBroadcaster()

    // Designated init. Pass a writable URL for the SQLite file and
    // a base directory for artefact sub-directories (design §4.2).
    public init(dbURL: URL, artefactsBaseURL: URL) throws {
        self.dbURL = dbURL
        self.artefactsBaseURL = artefactsBaseURL
        queue = try DatabaseQueue(path: dbURL.path)
        try queue.write { db in
            try GRDBPersistenceStore.createSchema(db)
            try GRDBPersistenceStore.migrate(db)
        }
    }

    // MARK: - PersistenceStore

    public func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {
        let metadata = try record.metadataJSON()
        let totalCarbsG = Double(record.macros.totalCarbsG)
        let createdAtMs = Int64(record.createdAt.timeIntervalSince1970 * 1000)

        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events
                        (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString,
                    createdAtMs,
                    EventType.meal,
                    totalCarbsG,
                    metadata
                ]
            )

            for artefact in artefacts {
                try db.execute(
                    sql: """
                        INSERT INTO meal_artefacts
                            (meal_id, kind, view_id, filename, bytes_size)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        record.id.uuidString,
                        artefact.kind,
                        artefact.viewId,
                        artefact.filename,
                        artefact.bytesSize
                    ]
                )
            }
        }
        changeBroadcaster.notify()
    }

    public func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws {
        try await queue.write { db in
            // Read the outer metadata, parse it, decode the inner protobuf-JSON
            // record string, mutate only the photoAssetID, then re-emit both
            // layers. The round-trip is through PbMealRecord — the canonical
            // encoder — so unchanged sibling fields stay byte-identical to a
            // fresh save (Decision 31).
            let row = try Row.fetchOne(
                db,
                sql: "SELECT metadata FROM events WHERE id = ? AND event_type = ?",
                arguments: [mealId.uuidString, EventType.meal]
            )
            guard let row else { throw PersistenceError.mealNotFound(mealId) }
            let metadata: String = row["metadata"]

            let parsed: Any
            do {
                parsed = try JSONSerialization.jsonObject(with: Data(metadata.utf8))
            } catch {
                throw PersistenceError.corruptRecord("metadata is not valid JSON: \(error)")
            }
            guard let outer = parsed as? [String: Any],
                  let recordJSON = outer["record"] as? String,
                  let paletteVersion = outer["palette_version"] as? String else {
                throw PersistenceError.corruptRecord("metadata envelope is malformed")
            }

            var pb = try PbMealRecord(jsonString: recordJSON)
            pb.photoAssetID = photoAssetID
            let updatedRecordJSON = try pb.jsonString()

            let newOuter: [String: Any] = [
                "record": updatedRecordJSON,
                "palette_version": paletteVersion
            ]
            let newMetadataData = try JSONSerialization.data(withJSONObject: newOuter, options: [])
            let newMetadata = String(decoding: newMetadataData, as: UTF8.self)

            try db.execute(
                sql: "UPDATE events SET metadata = ? WHERE id = ? AND event_type = ?",
                arguments: [newMetadata, mealId.uuidString, EventType.meal]
            )
        }
        // Decision 7: notify so the Meals tab refreshes after the photo
        // binding is stamped. This is a deliberate behaviour change vs the
        // pre-event-log code, which updated silently.
        changeBroadcaster.notify()
    }

    public func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {
        let json = try correction.jsonString()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO corrections (meal_id, created_at, correction_json)
                    VALUES (?, ?, ?)
                    """,
                arguments: [mealId.uuidString, correction.createdAtMs, json]
            )
        }
        // Deliberately no broadcast: corrections live in their own side table,
        // and the Meals tab does not redraw on a correction (design §Change
        // broadcaster).
    }

    public func meal(id: UUID) async throws -> MealRecord {
        let row = try await queue.read { db in
            try Row.fetchOne(db,
                sql: """
                    SELECT metadata FROM events
                    WHERE id = ? AND event_type = ?
                    """,
                arguments: [id.uuidString, EventType.meal])
        }
        guard let row else { throw PersistenceError.mealNotFound(id) }
        let metadata: String = row["metadata"]
        return try MealRecord.from(metadata: metadata)
    }

    public func allMeals() async throws -> [MealRecord] {
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT metadata FROM events
                    WHERE event_type = ?
                    ORDER BY timestamp DESC, id ASC
                    """,
                arguments: [EventType.meal])
        }
        return try rows.map { row in
            let metadata: String = row["metadata"]
            return try MealRecord.from(metadata: metadata)
        }
    }

    public func deleteMeal(id: UUID) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                arguments: [id.uuidString, EventType.meal]
            )
            try db.execute(sql: "DELETE FROM meal_artefacts WHERE meal_id = ?",
                           arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM corrections WHERE meal_id = ?",
                           arguments: [id.uuidString])
        }
        // Best-effort filesystem cleanup. The path is derived from the id —
        // no `artefacts_dir` column to read (design §Pattern extension audit).
        let url = artefactsBaseURL
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        changeBroadcaster.notify()
    }

    public var eventsDidChange: AsyncStream<Void> { changeBroadcaster.subscribe() }

    public func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] {
        let startMs = Int64(range.lowerBound.timeIntervalSince1970 * 1000)
        let endMs = Int64(range.upperBound.timeIntervalSince1970 * 1000)
        let rows = try await queue.read { db -> [Row] in
            if let type {
                return try Row.fetchAll(db,
                    sql: """
                        SELECT id, timestamp, event_type, value, metadata FROM events
                        WHERE timestamp BETWEEN ? AND ? AND event_type = ?
                        ORDER BY timestamp ASC, id ASC
                        """,
                    arguments: [startMs, endMs, type])
            }
            return try Row.fetchAll(db,
                sql: """
                    SELECT id, timestamp, event_type, value, metadata FROM events
                    WHERE timestamp BETWEEN ? AND ?
                    ORDER BY timestamp ASC, id ASC
                    """,
                arguments: [startMs, endMs])
        }
        return try rows.map { row in
            let idString: String = row["id"]
            guard let uuid = UUID(uuidString: idString) else {
                throw PersistenceError.corruptRecord("invalid UUID: \(idString)")
            }
            let timestampMs: Int64 = row["timestamp"]
            let eventType: String = row["event_type"]
            let value: Double? = row["value"]
            let metadata: String = row["metadata"]
            // Fail-fast on malformed metadata JSON. Required by Req 1.5 contract
            // tested in PersistenceTests.testEventsInRangeFailsFastOnCorruptMetadata.
            do {
                _ = try JSONSerialization.jsonObject(with: Data(metadata.utf8))
            } catch {
                throw PersistenceError.corruptRecord("malformed metadata JSON: \(error)")
            }
            return Event(
                id: uuid,
                timestamp: Date(timeIntervalSince1970: Double(timestampMs) / 1000),
                eventType: eventType,
                value: value,
                metadata: metadata
            )
        }
    }

    public func corrections(for mealId: UUID) async throws -> [PbUserCorrection] {
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT correction_json FROM corrections
                    WHERE meal_id = ?
                    ORDER BY created_at ASC
                    """,
                arguments: [mealId.uuidString])
        }
        return try rows.map { row in
            let json: String = row["correction_json"]
            do {
                return try PbUserCorrection(jsonString: json)
            } catch {
                throw PersistenceError.corruptRecord("corrupt correction JSON: \(error)")
            }
        }
    }

    // MARK: - Bsl ingest (specs/data/libre-ingestion)

    public func isImageProcessed(hash: String) async throws -> Bool {
        try await queue.read { db in
            try Row.fetchOne(
                db, sql: "SELECT 1 FROM processed_images WHERE hash = ?",
                arguments: [hash]) != nil
        }
    }

    // Reference DISCREPANCY_LIMIT_MMOL / _FLOAT_TOLERANCE: values are
    // one-decimal mmol/L; the tolerance keeps a decimal difference of
    // exactly 0.3 (e.g. 9.4 vs 9.1, > 0.3 in binary floating point)
    // "agreeing".
    private static let discrepancyLimitMmol = 0.3
    private static let floatTolerance = 1e-9

    public func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
        // GRDB's serialised writer gives the reference's BEGIN IMMEDIATE
        // guarantee: the coverage snapshot and the inserts are one unit; two
        // concurrent ingests cannot both see a timestamp as uncovered.
        let summary = try await queue.write { db -> BslIngestSummary in
            var covered: [Int64: Double] = [:]
            if !readings.isEmpty {
                let placeholders = Array(repeating: "?", count: readings.count)
                    .joined(separator: ",")
                var arguments: [DatabaseValueConvertible] = [EventType.bsl]
                arguments += readings.map(\.timestampMs)
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT timestamp, value FROM events
                        WHERE event_type = ? AND timestamp IN (\(placeholders))
                        """,
                    arguments: StatementArguments(arguments)
                )
                for row in rows {
                    let timestamp: Int64 = row["timestamp"]
                    let value: Double = row["value"]
                    covered[timestamp] = value
                }
            }

            var stored = 0
            var agreeing = 0
            var discrepant: [BslIngestSummary.Discrepancy] = []
            for reading in readings {
                if let kept = covered[reading.timestampMs] {
                    if abs(kept - reading.value)
                        > Self.discrepancyLimitMmol + Self.floatTolerance {
                        discrepant.append(.init(
                            timestampMs: reading.timestampMs,
                            kept: kept, new: reading.value))
                    } else {
                        agreeing += 1
                    }
                    continue
                }
                try db.execute(
                    sql: """
                        INSERT INTO events (id, timestamp, event_type, value, metadata)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        UUID().uuidString, reading.timestampMs, EventType.bsl,
                        reading.value, metadataJSON,
                    ]
                )
                stored += 1
            }
            try db.execute(
                sql: """
                    INSERT INTO processed_images (hash, filename, processed_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    sourceHash, filename,
                    Int64(Date().timeIntervalSince1970 * 1000),
                ]
            )
            return BslIngestSummary(
                extracted: readings.count,
                stored: stored,
                skippedExisting: agreeing + discrepant.count,
                agreeing: agreeing,
                discrepant: discrepant
            )
        }
        // Req 4.4: one tick per batch, and only when the event log changed.
        if summary.stored > 0 {
            changeBroadcaster.notify()
        }
        return summary
    }

    public func deleteArtefacts(olderThan date: Date) async throws {
        let cutoffMs = Int64(date.timeIntervalSince1970 * 1000)
        let ids: [String] = try await queue.read { db in
            try String.fetchAll(db,
                sql: """
                    SELECT id FROM events
                    WHERE event_type = ? AND timestamp < ?
                    """,
                arguments: [EventType.meal, cutoffMs])
        }
        let mealsRoot = artefactsBaseURL.appendingPathComponent("meals", isDirectory: true)
        for id in ids {
            let url = mealsRoot.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func exportArchive() async throws -> String {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("medata-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Copy SQLite (checkpoint WAL first so the copy is consistent).
        try await queue.write { db in _ = try db.checkpoint(.truncate) }
        let dbCopy = tempDir.appendingPathComponent("meals.sqlite")
        try fm.copyItem(at: dbURL, to: dbCopy)

        // Copy artefact tree (meals/).
        let mealsDir = artefactsBaseURL.appendingPathComponent("meals", isDirectory: true)
        if fm.fileExists(atPath: mealsDir.path) {
            let mealsCopy = tempDir.appendingPathComponent("meals", isDirectory: true)
            try fm.copyItem(at: mealsDir, to: mealsCopy)
        }

        let archiveURL = fm.temporaryDirectory
            .appendingPathComponent("medata-export-\(UUID().uuidString).zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        let contents = (try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        for item in contents {
            try addToArchive(archive, item: item, relativeTo: tempDir)
        }
        return archiveURL.path
    }

    private func addToArchive(_ archive: Archive, item: URL, relativeTo base: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) else { return }
        // Resolve symlinks on both sides to avoid /var vs /private/var mismatch on macOS.
        let resolvedBase = base.resolvingSymlinksInPath().path
        let resolvedItem = item.resolvingSymlinksInPath().path
        let entryPath = resolvedBase.count < resolvedItem.count
            ? String(resolvedItem.dropFirst(resolvedBase.count + 1))
            : item.lastPathComponent
        if isDir.boolValue {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: item,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            for child in children {
                try addToArchive(archive, item: child, relativeTo: base)
            }
        } else {
            try archive.addEntry(with: entryPath, fileURL: item)
        }
    }

    public func sweepIfDue() async throws {
        let lastSweepMs: Int64 = try await queue.read { db in
            let v = try String.fetchOne(db,
                sql: "SELECT v FROM meta WHERE k = 'last_sweep_at_ms'")
            return v.flatMap { Int64($0) } ?? 0
        }
        let twentyFourHoursMs: Int64 = 24 * 60 * 60 * 1000
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard nowMs - lastSweepMs >= twentyFourHoursMs else { return }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        try await deleteArtefacts(olderThan: thirtyDaysAgo)

        try await queue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO meta (k, v) VALUES ('last_sweep_at_ms', ?)",
                arguments: [String(nowMs)]
            )
        }
    }

    // MARK: - Schema
    //
    // Decision 2 / Decision 5 / Decision 10: only the event-log tables are
    // created. Pre-existing dev DBs may still carry the legacy `meals` and
    // `meal_classes` tables — they are left untouched (no destructive DDL on
    // the production path; developers wipe simulator/device storage).

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS events (
                id          TEXT    PRIMARY KEY,
                timestamp   INTEGER NOT NULL,
                event_type  TEXT    NOT NULL,
                value       REAL,
                metadata    TEXT    NOT NULL
            );
            CREATE INDEX IF NOT EXISTS events_timestamp ON events(timestamp);
            CREATE TABLE IF NOT EXISTS meal_artefacts (
                meal_id    TEXT NOT NULL,
                kind       TEXT NOT NULL,
                view_id    TEXT NOT NULL,
                filename   TEXT NOT NULL,
                bytes_size INTEGER NOT NULL,
                PRIMARY KEY (meal_id, kind, view_id)
            );
            CREATE TABLE IF NOT EXISTS corrections (
                meal_id         TEXT NOT NULL,
                created_at      INTEGER NOT NULL,
                correction_json BLOB NOT NULL,
                PRIMARY KEY (meal_id, created_at)
            );
            CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS processed_images (
                hash         TEXT    PRIMARY KEY,
                filename     TEXT    NOT NULL,
                processed_at INTEGER NOT NULL
            );
            """)
        try db.execute(
            sql: "INSERT OR IGNORE INTO meta (k, v) VALUES ('schema_version', '4')"
        )
    }

    // Idempotent: re-stamps schema_version to '4' so a dev DB carried over
    // from an earlier code path is correctly labelled. Version 4 adds
    // processed_images (specs/data/libre-ingestion Decision 4); the CREATE
    // IF NOT EXISTS above retrofits it onto v3 DBs. No DDL on legacy tables
    // (Decision 10).
    private static func migrate(_ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO meta (k, v) VALUES ('schema_version', '4')"
        )
    }
}

// MARK: - Change broadcaster
//
// Per-subscriber `AsyncStream<Void>` fan-out. Each `subscribe()` returns a
// stream whose continuation is held until iteration ends; `notify()` yields on
// every active continuation. `BufferingPolicy.bufferingNewest(1)` means a slow
// consumer sees the most recent tick, not a backlog (UI Decision 15).
private final class ChangeBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    func subscribe() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func notify() {
        lock.lock()
        let snapshot = Array(continuations.values)
        lock.unlock()
        for continuation in snapshot { continuation.yield() }
    }
}
