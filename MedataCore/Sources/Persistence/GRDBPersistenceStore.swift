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
        // Decision 18 (UI Design Handoff 00): notify so Data rows and Meal
        // overview learn a correction landed without polling. This reverses the
        // event-log-schema-era behaviour, which deliberately did not emit.
        changeBroadcaster.notify()
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

    public func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws {
        // File first (Decision 15): a crash between the write and the insert
        // leaves an orphan file, never a dangling row that the fallback cannot
        // satisfy.
        let mealDir = artefactsBaseURL
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(mealId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: mealDir, withIntermediateDirectories: true)
        let fileURL = mealDir.appendingPathComponent(artefact.filename)
        try data.write(to: fileURL, options: .atomic)

        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO meal_artefacts
                        (meal_id, kind, view_id, filename, bytes_size)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mealId.uuidString,
                    artefact.kind,
                    artefact.viewId,
                    artefact.filename,
                    artefact.bytesSize
                ]
            )
        }
    }

    public func artefactData(mealId: UUID, kind: String) async throws -> Data? {
        let filename: String? = try await queue.read { db in
            try String.fetchOne(db,
                sql: """
                    SELECT filename FROM meal_artefacts
                    WHERE meal_id = ? AND kind = ?
                    ORDER BY view_id ASC
                    LIMIT 1
                    """,
                arguments: [mealId.uuidString, kind])
        }
        guard let filename else { return nil }
        let fileURL = artefactsBaseURL
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(mealId.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        // Absent/unreadable file is the fallback signal, not an error.
        return try? Data(contentsOf: fileURL)
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

    // Keep-first merge shared by ingestBsl and ingestLiveBsl (specs/data/
    // cgm-connect design "Persistence: extract the keep-first helper").
    // Runs inside an open write transaction. `covered` is seeded from
    // committed rows via a BETWEEN range query over the batch's min/max
    // timestamps — three bound variables regardless of batch size, so a
    // large backfill never hits SQLite's 32,766 bound-variable ceiling.
    // Extra committed rows inside the range are harmless: the map is only
    // probed at incoming timestamps. Each freshly inserted timestampMs is
    // then added to `covered` as it happens, so two rows in the same batch
    // landing on the same timestampMs cannot both insert — the store-level
    // guard behind Phase 2's intra-batch collapse.
    private func mergeBslKeepFirst(
        _ db: Database, _ rows: [(timestampMs: Int64, value: Double, metadataJSON: String)]
    ) throws -> (stored: Int, agreeing: Int, discrepant: [BslIngestSummary.Discrepancy]) {
        var covered: [Int64: Double] = [:]
        if let minTimestamp = rows.map(\.timestampMs).min(),
            let maxTimestamp = rows.map(\.timestampMs).max() {
            let existing = try Row.fetchAll(
                db,
                sql: """
                    SELECT timestamp, value FROM events
                    WHERE event_type = ? AND timestamp BETWEEN ? AND ?
                    """,
                arguments: [EventType.bsl, minTimestamp, maxTimestamp]
            )
            for row in existing {
                let timestamp: Int64 = row["timestamp"]
                let value: Double = row["value"]
                covered[timestamp] = value
            }
        }

        var stored = 0
        var agreeing = 0
        var discrepant: [BslIngestSummary.Discrepancy] = []
        for row in rows {
            if let kept = covered[row.timestampMs] {
                if abs(kept - row.value)
                    > Self.discrepancyLimitMmol + Self.floatTolerance {
                    discrepant.append(.init(
                        timestampMs: row.timestampMs,
                        kept: kept, new: row.value))
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
                    UUID().uuidString, row.timestampMs, EventType.bsl,
                    row.value, row.metadataJSON,
                ]
            )
            covered[row.timestampMs] = row.value
            stored += 1
        }
        return (stored: stored, agreeing: agreeing, discrepant: discrepant)
    }

    public func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
        // GRDB's serialised writer gives the reference's BEGIN IMMEDIATE
        // guarantee: the coverage snapshot and the inserts are one unit; two
        // concurrent ingests cannot both see a timestamp as uncovered.
        let summary = try await queue.write { db -> BslIngestSummary in
            let rows = readings.map {
                (timestampMs: $0.timestampMs, value: $0.value, metadataJSON: metadataJSON)
            }
            let merged = try self.mergeBslKeepFirst(db, rows)
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
                stored: merged.stored,
                skippedExisting: merged.agreeing + merged.discrepant.count,
                agreeing: merged.agreeing,
                discrepant: merged.discrepant
            )
        }
        // Req 4.4: one tick per batch, and only when the event log changed.
        if summary.stored > 0 {
            changeBroadcaster.notify()
        }
        return summary
    }

    public func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary {
        guard !readings.isEmpty else {
            return BslIngestSummary(
                extracted: 0, stored: 0, skippedExisting: 0, agreeing: 0, discrepant: [])
        }
        let summary = try await queue.write { db -> BslIngestSummary in
            let rows = try readings.map {
                (
                    timestampMs: $0.timestampMs, value: $0.mmolL,
                    metadataJSON: try Self.liveBslMetadataJSON(for: $0)
                )
            }
            let merged = try self.mergeBslKeepFirst(db, rows)
            return BslIngestSummary(
                extracted: readings.count,
                stored: merged.stored,
                skippedExisting: merged.agreeing + merged.discrepant.count,
                agreeing: merged.agreeing,
                discrepant: merged.discrepant
            )
        }
        // Req 4.4: one tick per batch, and only when the event log changed.
        if summary.stored > 0 {
            changeBroadcaster.notify()
        }
        return summary
    }

    // Builds the `metadata` JSON object for a live reading: `source_id`,
    // `native_instant_ms`, and `native_id` only when provided — the key is
    // absent, never null, when nil (mirrors insulinMetadataJSON below).
    private static func liveBslMetadataJSON(for reading: LiveBslReading) throws -> String {
        var payload: [String: Any] = [
            "source_id": reading.sourceID,
            "native_instant_ms": reading.nativeInstantMs,
        ]
        if let nativeID = reading.nativeID {
            payload["native_id"] = nativeID
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Insulin doses (PRD regression-suggestion-integration Core 2–4)

    // Bounds accepted at the store layer. The UI enforces its own floor of
    // 1 U; 0 and 60 are valid here.
    private static let insulinUnitsRange = 0.0...60.0

    public func saveInsulinDose(_ dose: InsulinDose) async throws {
        guard Self.insulinUnitsRange.contains(dose.units) else {
            throw PersistenceError.insulinUnitsOutOfRange(dose.units)
        }
        let metadata = try Self.insulinMetadataJSON(for: dose)
        let timestampMs = Int64(dose.timestamp.timeIntervalSince1970 * 1000)
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    dose.id.uuidString, timestampMs, EventType.insulin,
                    dose.units, metadata
                ]
            )
        }
        changeBroadcaster.notify()
    }

    public func deleteInsulinEvent(id: UUID) async throws {
        try await queue.write { db in
            // Gated on event_type so a meal/bsl row sharing the id survives.
            // Insulin events have no side tables — nothing else to cascade.
            try db.execute(
                sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                arguments: [id.uuidString, EventType.insulin]
            )
        }
        changeBroadcaster.notify()
    }

    // Builds the `metadata` JSON object per medreg's convention: exactly
    // `kind`, `insulin_type`, and `schema_version` (integer), plus `note`
    // only when provided — the key is absent, never null, when nil.
    private static func insulinMetadataJSON(for dose: InsulinDose) throws -> String {
        var payload: [String: Any] = [
            "kind": dose.kind.rawValue,
            "insulin_type": dose.insulinType,
            "schema_version": InsulinDose.metadataSchemaVersion
        ]
        if let note = dose.note {
            payload["note"] = note
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Manual carb intake (specs/data/manual-carb-intake Phase 1)

    // Bounds accepted at the store layer (Req 1.4).
    private static let intakeCarbsRange = 1.0...999.0

    public func saveIntakeEntry(_ entry: IntakeEntry) async throws {
        guard Self.intakeCarbsRange.contains(entry.carbsG) else {
            throw PersistenceError.intakeCarbsOutOfRange(entry.carbsG)
        }
        let metadata = try Self.intakeMetadataJSON(for: entry)
        let timestampMs = Int64(entry.timestamp.timeIntervalSince1970 * 1000)
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    entry.id.uuidString, timestampMs, EventType.intake,
                    entry.carbsG, metadata
                ]
            )
        }
        changeBroadcaster.notify()
    }

    public func updateIntakeEntry(_ entry: IntakeEntry) async throws {
        guard Self.intakeCarbsRange.contains(entry.carbsG) else {
            throw PersistenceError.intakeCarbsOutOfRange(entry.carbsG)
        }
        let metadata = try Self.intakeMetadataJSON(for: entry)
        let timestampMs = Int64(entry.timestamp.timeIntervalSince1970 * 1000)
        try await queue.write { db in
            // Gated on event_type so a meal/insulin/bsl row sharing the id
            // is untouched.
            try db.execute(
                sql: """
                    UPDATE events SET timestamp = ?, value = ?, metadata = ?
                    WHERE id = ? AND event_type = ?
                    """,
                arguments: [
                    timestampMs, entry.carbsG, metadata,
                    entry.id.uuidString, EventType.intake
                ]
            )
        }
        changeBroadcaster.notify()
    }

    public func deleteIntakeEntry(id: UUID) async throws {
        try await queue.write { db in
            // Gated on event_type so a meal/insulin/bsl row sharing the id
            // survives. Intake events have no side tables — nothing else to
            // cascade.
            try db.execute(
                sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                arguments: [id.uuidString, EventType.intake]
            )
        }
        changeBroadcaster.notify()
    }

    // Builds the `metadata` JSON object per design.md "Event type and
    // storage": `subtype`, `schema_version`, `source`, plus `preset_id`
    // (only when source = quickadd) and macro keys — all omitted, never
    // null, when absent.
    private static func intakeMetadataJSON(for entry: IntakeEntry) throws -> String {
        var payload: [String: Any] = [
            "subtype": entry.subtype.rawValue,
            "schema_version": IntakeEntry.metadataSchemaVersion,
            "source": entry.source.rawValue
        ]
        if let presetID = entry.presetID {
            payload["preset_id"] = presetID.uuidString
        }
        if let proteinG = entry.macros.proteinG {
            payload["protein_g"] = proteinG
        }
        if let fatG = entry.macros.fatG {
            payload["fat_g"] = fatG
        }
        if let fibreG = entry.macros.fibreG {
            payload["fibre_g"] = fibreG
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(decoding: data, as: UTF8.self)
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

// MARK: - DEBUG demo glucose seeding (Decision 13)
//
// Trends reads `bsl` rows exclusively (Req 11.1) but no ingestion path ships in
// this spec, so on-device verification needs synthetic rows in the real store.
// This extension is DEBUG-only and never links into a Release build; there is
// deliberately no public event-write API — that belongs to a future importer.
#if DEBUG
public extension GRDBPersistenceStore {

    // Seeds 24 h of synthetic `bsl` readings at 15-minute spacing (96 rows),
    // ending at `now`. Values are mmol/L. Triggered from a DEBUG-only Settings
    // row.
    func seedDemoBslEvents(now: Date = Date()) async throws {
        let spacing: TimeInterval = 15 * 60
        let count = 96 // 24 h / 15 min
        let start = now.addingTimeInterval(-Double(count - 1) * spacing)
        try await queue.write { db in
            for i in 0..<count {
                let t = start.addingTimeInterval(Double(i) * spacing)
                let mmolL = GRDBPersistenceStore.demoGlucose(at: t)
                let ms = Int64(t.timeIntervalSince1970 * 1000)
                try db.execute(
                    sql: """
                        INSERT INTO events (id, timestamp, event_type, value, metadata)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, ms, EventType.bsl, mmolL, "{}"]
                )
            }
        }
        changeBroadcaster.notify()
    }

    // Wipes every event (meals, bsl, insulin), the meal side tables, and the
    // processed-image ledger, then removes the on-disk artefact tree. Keeps the
    // `meta` row so `schema_version` survives — the DB stays valid, just empty.
    // DEBUG-only reset for the developer test loop; there is no undo.
    func deleteAllData() async throws {
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM meal_artefacts")
            try db.execute(sql: "DELETE FROM corrections")
            try db.execute(sql: "DELETE FROM processed_images")
        }
        let mealsRoot = artefactsBaseURL.appendingPathComponent("meals", isDirectory: true)
        try? FileManager.default.removeItem(at: mealsRoot)
        changeBroadcaster.notify()
    }

    // A plausible daily curve: a diurnal baseline with three post-meal
    // excursions, clamped to a sane physiological window.
    private static func demoGlucose(at time: Date) -> Double {
        let minutesOfDay = (time.timeIntervalSince1970 / 60)
            .truncatingRemainder(dividingBy: 24 * 60)
        let diurnal = 6.2 + 1.0 * sin(2 * Double.pi * (minutesOfDay - 300) / (24 * 60))
        let meals: [(peakMin: Double, amplitude: Double)] = [
            (8 * 60, 2.6), (13 * 60, 3.0), (19 * 60, 2.8)
        ]
        let bumps = meals.reduce(0.0) { acc, meal in
            let delta = minutesOfDay - meal.peakMin
            return acc + meal.amplitude * exp(-(delta * delta) / (2 * 45 * 45))
        }
        return max(3.6, min(11.5, diurnal + bumps))
    }
}
#endif

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
