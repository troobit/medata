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
            try GRDBPersistenceStore.seedDefaultQuickPresetsIfNeeded(db)
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
            // `corrections` cascades — it is the meal's current display value
            // and a deleted meal has no display value. `correction_records`
            // deliberately does NOT (meal-review Req 9.10): the corpus
            // survives deletion of the meal it refers to.
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

    // MARK: - Correction records (specs/ui/meal-review)
    //
    // One row per detected food per capture, keyed by the natural
    // (meal_id, predicted_class) — so the millisecond-collision defect in
    // `corrections`' PRIMARY KEY (meal_id, created_at) cannot arise, and a
    // held stepper updates one row rather than appending per repeat. The
    // four boolean columns are denormalised copies of fields inside
    // record_json so the corpus is queryable without decoding every blob.
    //
    // No eviction, ever (Req 9.9): no delete in deleteMeal, deleteRecords
    // or deleteAllData, no count bound, no age sweep. The corpus is the
    // deliverable; this is the one store deliberately exempt from the
    // bounding estimation_outcomes applies.

    public func createCorrectionRecords(_ records: [PbCorrectionRecord]) async throws {
        guard !records.isEmpty else { return }
        // Encode before the transaction so a bad record aborts before any write.
        let rows: [(record: PbCorrectionRecord, json: String)] = try records.map {
            ($0, try $0.jsonString())
        }
        try await queue.write { db in
            for (record, json) in rows {
                // INSERT ... DO NOTHING, never a blanket upsert: the review
                // surface can re-appear for the same meal, and a second
                // creation must not reset created_at or overwrite a
                // predicted side that never changes (Req 9.2).
                try db.execute(
                    sql: """
                        INSERT INTO correction_records
                            (meal_id, predicted_class, outcome_id, created_at,
                             updated_at, class_corrected, rejected, absent,
                             amount_corrected, record_json)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT (meal_id, predicted_class) DO NOTHING
                        """,
                    arguments: [
                        record.mealID, record.predicted.classID,
                        record.outcomeID.isEmpty ? nil : record.outcomeID,
                        record.createdAtMs, record.updatedAtMs,
                        record.classCorrected, record.rejected,
                        record.absent, record.amountCorrected,
                        json
                    ]
                )
            }
        }
        // Corpus writes never tick eventsDidChange (quick_presets convention);
        // creation changes no displayed value.
    }

    public func updateCorrectionRecord(
        _ record: PbCorrectionRecord,
        upsertingCorrection correction: PbUserCorrection?
    ) async throws {
        try await updateCorrectionRecords([record], upsertingCorrection: correction)
    }

    public func updateCorrectionRecords(
        _ records: [PbCorrectionRecord],
        upsertingCorrection correction: PbUserCorrection?
    ) async throws {
        guard let first = records.first else { return }
        // Encode before the transaction so a bad record aborts before any write.
        let rows: [(record: PbCorrectionRecord, json: String)] = try records.map {
            ($0, try $0.jsonString())
        }
        let correctionJSON = try correction.map { try $0.jsonString() }
        let mealID = first.mealID
        try await queue.write { db in
            for (record, json) in rows {
                try Self.upsertCorrectionRecordRow(db, record: record, json: json)
            }
            // The reconciling PbUserCorrection write shares this transaction
            // (design "the reconciling write"): a session killed mid-review
            // must not leave the corpus holding a relabel while Records shows
            // the uncorrected total permanently.
            if let correction, let correctionJSON {
                try Self.upsertCorrectionRow(
                    db, mealId: mealID, correction: correction, json: correctionJSON
                )
            }
        }
        if correction != nil {
            // The meal's displayed value changed (appendCorrection precedent).
            changeBroadcaster.notify()
        }
    }

    // Mutation is a self-healing upsert, not a bare UPDATE: if the creation
    // INSERT failed — its error is swallowed per Req 8.5 — a bare UPDATE
    // would match zero rows on every later correction while the reconciling
    // corrections upsert beside it succeeded, leaving Records showing a
    // corrected meal the corpus never recorded. On conflict only the
    // corrected columns are touched: created_at and outcome_id keep their
    // first-write values and the row identity never changes (Req 9.2, 9.3).
    private static func upsertCorrectionRecordRow(
        _ db: Database, record: PbCorrectionRecord, json: String
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO correction_records
                    (meal_id, predicted_class, outcome_id, created_at,
                     updated_at, class_corrected, rejected, absent,
                     amount_corrected, record_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (meal_id, predicted_class) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    class_corrected = excluded.class_corrected,
                    rejected = excluded.rejected,
                    absent = excluded.absent,
                    amount_corrected = excluded.amount_corrected,
                    record_json = excluded.record_json
                """,
            arguments: [
                record.mealID, record.predicted.classID,
                record.outcomeID.isEmpty ? nil : record.outcomeID,
                record.createdAtMs, record.updatedAtMs,
                record.classCorrected, record.rejected,
                record.absent, record.amountCorrected,
                json
            ]
        )
    }

    public func upsertCorrection(mealId: UUID, correction: PbUserCorrection) async throws {
        let json = try correction.jsonString()
        try await queue.write { db in
            try Self.upsertCorrectionRow(
                db, mealId: mealId.uuidString, correction: correction, json: json
            )
        }
        changeBroadcaster.notify()
    }

    // One corrections row per meal, created_at fixed at review-session start
    // (design "the reconciling write"). appendCorrection stays a plain INSERT
    // for its existing callers; the review path upserts so a held stepper or
    // a scale tap in the same millisecond cannot raise a constraint violation
    // that would roll back the correction_records write beside it (Req 8.5).
    private static func upsertCorrectionRow(
        _ db: Database, mealId: String, correction: PbUserCorrection, json: String
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO corrections (meal_id, created_at, correction_json)
                VALUES (?, ?, ?)
                ON CONFLICT (meal_id, created_at)
                DO UPDATE SET correction_json = excluded.correction_json
                """,
            arguments: [mealId, correction.createdAtMs, json]
        )
    }

    public func correctionRecords(for mealId: UUID) async throws -> [PbCorrectionRecord] {
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT record_json FROM correction_records
                    WHERE meal_id = ?
                    ORDER BY predicted_class ASC
                    """,
                arguments: [mealId.uuidString])
        }
        return try rows.map(Self.decodeCorrectionRecord)
    }

    public func allCorrectionRecords() async throws -> [PbCorrectionRecord] {
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT record_json FROM correction_records
                    ORDER BY updated_at DESC, meal_id ASC, predicted_class ASC
                    """)
        }
        return try rows.map(Self.decodeCorrectionRecord)
    }

    public func recentCorrectedClassIds(
        forPredictedClass classId: String, limit: Int
    ) async throws -> [String] {
        guard limit > 0 else { return [] }
        // Recency shortlist (meal-review Req 3.1, Decision 18): corrected
        // classes the user has recently chosen for a food of this kind.
        // The corrected class lives inside record_json; the scan is bounded
        // because the candidate universe is the palette (≤ 33 classes).
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT record_json FROM correction_records
                    WHERE predicted_class = ? AND class_corrected = 1
                    ORDER BY updated_at DESC
                    LIMIT 100
                    """,
                arguments: [classId])
        }
        var seen: Set<String> = []
        var out: [String] = []
        for row in rows {
            let record = try Self.decodeCorrectionRecord(row)
            let corrected = record.corrected.classID
            guard !corrected.isEmpty, corrected != classId,
                  seen.insert(corrected).inserted else { continue }
            out.append(corrected)
            if out.count == limit { break }
        }
        return out
    }

    private static func decodeCorrectionRecord(_ row: Row) throws -> PbCorrectionRecord {
        let json: String = row["record_json"]
        do {
            return try PbCorrectionRecord(jsonString: json)
        } catch {
            throw PersistenceError.corruptRecord("corrupt correction record JSON: \(error)")
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

    public func deleteBslEvent(id: UUID) async throws {
        try await queue.write { db in
            // Gated on event_type so a meal/insulin/intake row sharing the
            // id survives. Bsl events have no side tables.
            try db.execute(
                sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                arguments: [id.uuidString, EventType.bsl]
            )
        }
        changeBroadcaster.notify()
    }

    // Chunk size for `IN (…)` lists — comfortably under SQLite's 32,766
    // bound-variable cap (the mergeBslKeepFirst precedent, cgm-connect
    // Phase 2).
    private static let deleteChunkSize = 500

    public func deleteRecords(mealIDs: [UUID], eventIDs: [UUID]) async throws {
        guard !mealIDs.isEmpty || !eventIDs.isEmpty else { return }
        try await queue.write { db in
            for chunk in stride(from: 0, to: eventIDs.count, by: Self.deleteChunkSize)
                .map({ Array(eventIDs[$0..<min($0 + Self.deleteChunkSize, eventIDs.count)]) }) {
                let placeholders = repeatElement("?", count: chunk.count).joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM events WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(chunk.map(\.uuidString))
                )
            }
            // Meal cascade mirrors deleteMeal — events row plus side tables.
            // As in deleteMeal, `correction_records` is exempt from the
            // cascade (meal-review Req 9.10).
            for id in mealIDs {
                try db.execute(
                    sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                    arguments: [id.uuidString, EventType.meal]
                )
                try db.execute(sql: "DELETE FROM meal_artefacts WHERE meal_id = ?",
                               arguments: [id.uuidString])
                try db.execute(sql: "DELETE FROM corrections WHERE meal_id = ?",
                               arguments: [id.uuidString])
            }
        }
        // Best-effort filesystem cleanup after commit (deleteMeal precedent).
        for id in mealIDs {
            let url = artefactsBaseURL
                .appendingPathComponent("meals", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
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

    // MARK: - Activity (specs/data/activity-events)

    public func saveActivity(_ activity: ActivityEvent) async throws {
        let metadata = try Self.activityMetadataJSON(for: activity)
        let timestampMs = Int64(activity.timestamp.timeIntervalSince1970 * 1000)
        try await queue.write { db in
            // `value` carries duration in minutes and stays NULL when the
            // duration is unrecorded (Req 1.5) — nil, never 0.
            try db.execute(
                sql: """
                    INSERT INTO events (id, timestamp, event_type, value, metadata)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    activity.id.uuidString, timestampMs, EventType.activity,
                    activity.durationMinutes, metadata
                ]
            )
        }
        changeBroadcaster.notify()
    }

    public func deleteActivityEvent(id: UUID) async throws {
        try await queue.write { db in
            // Gated on event_type so a meal/insulin/intake/bsl row sharing the
            // id survives. Activity events have no side tables — nothing else
            // to cascade.
            try db.execute(
                sql: "DELETE FROM events WHERE id = ? AND event_type = ?",
                arguments: [id.uuidString, EventType.activity]
            )
        }
        changeBroadcaster.notify()
    }

    public func activities(
        before instant: Date, within interval: TimeInterval
    ) async throws -> [ActivityEvent] {
        let endMs = Int64(instant.timeIntervalSince1970 * 1000)
        let startMs = Int64(instant.addingTimeInterval(-interval).timeIntervalSince1970 * 1000)
        let rows = try await queue.read { db in
            // Half-open at the lower bound, closed at the upper: `> startMs`
            // excludes an event exactly at `instant - interval`, `<= endMs`
            // includes one exactly at `instant` (Req 5.1).
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, timestamp, value, metadata FROM events
                    WHERE event_type = ? AND timestamp > ? AND timestamp <= ?
                    ORDER BY timestamp DESC, id DESC
                    """,
                arguments: [EventType.activity, startMs, endMs]
            )
        }
        // Undecodable rows are dropped, not thrown — TrendsModel's existing
        // handling of insulin rows with unreadable metadata.
        return rows.compactMap(Self.activityEvent(from:))
    }

    // Builds the `metadata` JSON object per design.md "Row shape":
    // `schema_version`, `kind` and `provenance`, plus `note` only when provided
    // — the key is absent, never null, when nil. `character` is deliberately
    // NOT written; it is derived from `kind`.
    private static func activityMetadataJSON(for activity: ActivityEvent) throws -> String {
        var payload: [String: Any] = [
            "schema_version": ActivityEvent.metadataSchemaVersion,
            "kind": activity.kind.rawValue,
            "provenance": activity.provenance.rawValue
        ]
        if let note = activity.note {
            payload["note"] = note
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    // Returns nil for any row that cannot be read as an activity — an
    // unparseable id, malformed metadata JSON, or a `kind`/`provenance` string
    // outside the shipped vocabulary. The caller drops those rows.
    private static func activityEvent(from row: Row) -> ActivityEvent? {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else { return nil }
        let metadata: String = row["metadata"]
        guard
            let parsed = try? JSONSerialization.jsonObject(with: Data(metadata.utf8)),
            let payload = parsed as? [String: Any],
            let kindString = payload["kind"] as? String,
            let kind = ActivityKind(rawValue: kindString),
            let provenanceString = payload["provenance"] as? String,
            let provenance = ActivityProvenance(rawValue: provenanceString)
        else { return nil }
        let timestampMs: Int64 = row["timestamp"]
        return ActivityEvent(
            id: id,
            timestamp: Date(timeIntervalSince1970: Double(timestampMs) / 1000),
            kind: kind,
            durationMinutes: row["value"],
            provenance: provenance,
            note: payload["note"] as? String
        )
    }

    public func deleteArtefacts(olderThan date: Date) async throws {
        let cutoffMs = Int64(date.timeIntervalSince1970 * 1000)
        // Meals holding an ACTUAL correction are exempt (meal-review Req 8.4):
        // their mask is pixel-level supervision for a retained training
        // example. "Actual" means any of the four correction facts — every
        // reviewed meal holds rows, so exempting on mere row existence would
        // make this an unconditional no-op rather than a retention policy.
        let ids: [String] = try await queue.read { db in
            try String.fetchAll(db,
                sql: """
                    SELECT id FROM events
                    WHERE event_type = ? AND timestamp < ?
                      AND id NOT IN (
                        SELECT meal_id FROM correction_records
                        WHERE class_corrected OR rejected
                           OR absent OR amount_corrected
                      )
                    """,
                arguments: [EventType.meal, cutoffMs])
        }
        guard !ids.isEmpty else { return }
        let mealsRoot = artefactsBaseURL.appendingPathComponent("meals", isDirectory: true)
        for id in ids {
            let url = mealsRoot.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
        }
        // The meal_artefacts rows go with the directories (meal-review
        // Req 8.4): a dangling row would make artefactData report an
        // artefact that no longer exists on disk.
        try await queue.write { db in
            for chunk in stride(from: 0, to: ids.count, by: Self.deleteChunkSize)
                .map({ Array(ids[$0..<min($0 + Self.deleteChunkSize, ids.count)]) }) {
                let placeholders = repeatElement("?", count: chunk.count).joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM meal_artefacts WHERE meal_id IN (\(placeholders))",
                    arguments: StatementArguments(chunk)
                )
            }
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
            CREATE TABLE IF NOT EXISTS quick_presets (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                carbs_g     REAL NOT NULL,
                protein_g   REAL,
                fat_g       REAL,
                fibre_g     REAL,
                sort_order  INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS estimation_outcomes (
                id                TEXT    PRIMARY KEY,
                timestamp         INTEGER NOT NULL,
                outcome           TEXT    NOT NULL,
                failure           TEXT,
                measurements      TEXT    NOT NULL,
                meal_id           TEXT,
                model_version     TEXT    NOT NULL,
                benchmark_meal_id TEXT
            );
            CREATE INDEX IF NOT EXISTS outcomes_timestamp
                ON estimation_outcomes(timestamp);
            CREATE INDEX IF NOT EXISTS outcomes_benchmark
                ON estimation_outcomes(benchmark_meal_id, model_version);
            CREATE TABLE IF NOT EXISTS benchmark_meals (
                id            TEXT    PRIMARY KEY,
                name          TEXT    NOT NULL,
                created_at    INTEGER NOT NULL,
                items         TEXT    NOT NULL,
                truth_carbs_g REAL    NOT NULL,
                db_edition    TEXT    NOT NULL,
                fidelity      TEXT    NOT NULL
            );
            CREATE TABLE IF NOT EXISTS correction_records (
                meal_id          TEXT NOT NULL,
                predicted_class  TEXT NOT NULL,
                outcome_id       TEXT,
                created_at       INTEGER NOT NULL,
                updated_at       INTEGER NOT NULL,
                class_corrected  INTEGER NOT NULL,
                rejected         INTEGER NOT NULL,
                absent           INTEGER NOT NULL,
                amount_corrected INTEGER NOT NULL,
                record_json      BLOB NOT NULL,
                PRIMARY KEY (meal_id, predicted_class)
            );
            CREATE INDEX IF NOT EXISTS idx_correction_records_meal
                ON correction_records(meal_id);
            CREATE INDEX IF NOT EXISTS idx_correction_records_predicted
                ON correction_records(predicted_class);
            CREATE TABLE IF NOT EXISTS dose_suggestions (
                id                TEXT    PRIMARY KEY,
                timestamp         INTEGER NOT NULL,
                meal_timestamp    INTEGER NOT NULL,
                row_version       INTEGER NOT NULL,
                rule_id           TEXT    NOT NULL,
                rule_version      INTEGER NOT NULL,
                fat_rule_id       TEXT,
                fat_rule_version  INTEGER,
                outcome           TEXT    NOT NULL,
                suppression       TEXT,
                carbs_g           REAL,
                carbs_source      TEXT    NOT NULL,
                source_event_id   TEXT,
                exact_units       REAL,
                rounded_units     REAL,
                increment_u       REAL    NOT NULL,
                seed_clamped      INTEGER NOT NULL,
                cr_g_per_u        REAL    NOT NULL,
                cr_source         TEXT    NOT NULL,
                cr_fit_ref        TEXT,
                band              TEXT    NOT NULL,
                local_hour        INTEGER NOT NULL,
                utc_hour          INTEGER NOT NULL,
                utc_offset_s      INTEGER NOT NULL,
                iob_u             REAL    NOT NULL,
                sigma_meal        REAL,
                start_bg_mmol     REAL,
                start_bg_age_s    INTEGER,
                fat_g             REAL,
                protein_g         REAL,
                fpu               REAL,
                fat_stale         INTEGER NOT NULL,
                given_units       REAL,
                insulin_event_id  TEXT,
                build_stamp       TEXT    NOT NULL
            );
            CREATE INDEX IF NOT EXISTS dose_suggestions_timestamp
                ON dose_suggestions(timestamp);
            CREATE TABLE IF NOT EXISTS dose_occurrences (
                id                TEXT    PRIMARY KEY,
                schedule_id       TEXT    NOT NULL,
                due_at            INTEGER NOT NULL,
                outcome           TEXT    NOT NULL,
                closed_at         INTEGER,
                insulin_event_id  TEXT,
                was_nominal       INTEGER
            );
            CREATE UNIQUE INDEX IF NOT EXISTS dose_occurrences_schedule
                ON dose_occurrences(schedule_id, due_at);
            """)
        try db.execute(
            sql: "INSERT OR IGNORE INTO meta (k, v) VALUES ('schema_version', '9')"
        )
    }

    // Idempotent: re-stamps schema_version to '9' so a dev DB carried over
    // from an earlier code path is correctly labelled. Version 9 adds
    // dose_occurrences (specs/data/dose-schedule, design "The occurrence
    // ledger"); version 8 added
    // dose_suggestions (specs/data/insulin-dosing, design "The ledger");
    // version 7 added
    // correction_records (specs/ui/meal-review, design "Correction store");
    // version 6 added estimation_outcomes AND benchmark_meals
    // (specs/estimation/snaq-parity Decision 7, design "Data Models");
    // version 5 added quick_presets (specs/data/manual-carb-intake). The
    // CREATE IF NOT EXISTS above retrofits all of them onto older DBs —
    // matching the processed_images/v4 precedent exactly. No DDL on legacy
    // tables (Decision 10).
    private static func migrate(_ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO meta (k, v) VALUES ('schema_version', '9')"
        )
    }

    // One-shot seed of the three authored defaults (Req 3.3): "A pint"
    // (17 g), "Bagel" (45 g), "Chips" (40 g) — carbohydrate values only, no
    // macros. Gated on the `quick_presets_seeded` meta flag so the seed runs
    // at most once per DB: a user who deletes all presets (defaults are
    // deletable like any other, Req 3.3) stays at zero across relaunches
    // (Req 4.3). Rows are inserted only when the flag is absent AND the
    // table is empty; a pre-flag DB that already holds presets is stamped
    // seeded without inserting, so existing rows are never duplicated.
    private static func seedDefaultQuickPresetsIfNeeded(_ db: Database) throws {
        let seeded = try String.fetchOne(
            db, sql: "SELECT v FROM meta WHERE k = 'quick_presets_seeded'"
        )
        guard seeded == nil else { return }
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM quick_presets") ?? 0
        if count == 0 {
            let defaults: [(name: String, carbsG: Double)] = [
                ("A pint", 17), ("Bagel", 45), ("Chips", 40)
            ]
            for (index, preset) in defaults.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO quick_presets (id, name, carbs_g, sort_order)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, preset.name, preset.carbsG, index]
                )
            }
        }
        try db.execute(
            sql: "INSERT OR IGNORE INTO meta (k, v) VALUES ('quick_presets_seeded', '1')"
        )
    }

    // MARK: - Quick-add presets (specs/data/manual-carb-intake)

    public func quickPresets() async throws -> [QuickPreset] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM quick_presets ORDER BY sort_order ASC"
            ).map(Self.quickPreset(from:))
        }
    }

    public func saveQuickPreset(_ preset: QuickPreset) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO quick_presets
                        (id, name, carbs_g, protein_g, fat_g, fibre_g, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    preset.id.uuidString, preset.name, preset.carbsG,
                    preset.macros.proteinG, preset.macros.fatG, preset.macros.fibreG,
                    preset.sortOrder
                ]
            )
        }
    }

    public func deleteQuickPreset(id: UUID) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM quick_presets WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    // MARK: - Estimation outcomes (specs/estimation/snaq-parity)

    public func saveEstimationOutcome(_ outcome: EstimationOutcome) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO estimation_outcomes
                        (id, timestamp, outcome, failure, measurements,
                         meal_id, model_version, benchmark_meal_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    outcome.id.uuidString,
                    outcome.timestampMs,
                    outcome.outcome,
                    outcome.failureJSON,
                    outcome.measurementsJSON,
                    outcome.mealID?.uuidString,
                    outcome.modelVersion,
                    outcome.benchmarkMealID?.uuidString
                ]
            )
            // Split eviction bounds (Req 2.5, Decision 7), applied in the same
            // write transaction so the insert-plus-eviction is atomic. Only the
            // population the insert belongs to can have grown, so only that
            // bound is enforced. "Newest" is (timestamp, id) descending —
            // the id tie-break keeps eviction deterministic when attempts
            // share a millisecond.
            if let benchmarkMealID = outcome.benchmarkMealID {
                // The group's latest completed attempt is exempt: oldest-first
                // eviction alone could drop a meal's ONLY success under a run
                // of refusals, silently flipping the meal to refused-only in
                // the report. The exempt row occupies one of the bound's
                // slots, so the group never exceeds the bound.
                let latestSuccessID = try String.fetchOne(
                    db,
                    sql: """
                        SELECT id FROM estimation_outcomes
                        WHERE benchmark_meal_id = ? AND model_version = ?
                          AND outcome = ?
                        ORDER BY timestamp DESC, id DESC
                        LIMIT 1
                        """,
                    arguments: [
                        benchmarkMealID.uuidString, outcome.modelVersion,
                        EstimationOutcomeKind.success.rawValue
                    ]
                )
                if let latestSuccessID {
                    try db.execute(
                        sql: """
                            DELETE FROM estimation_outcomes
                            WHERE benchmark_meal_id = ? AND model_version = ?
                              AND id <> ?
                              AND id NOT IN (
                                SELECT id FROM estimation_outcomes
                                WHERE benchmark_meal_id = ? AND model_version = ?
                                  AND id <> ?
                                ORDER BY timestamp DESC, id DESC
                                LIMIT ?
                              )
                            """,
                        arguments: [
                            benchmarkMealID.uuidString, outcome.modelVersion,
                            latestSuccessID,
                            benchmarkMealID.uuidString, outcome.modelVersion,
                            latestSuccessID,
                            EstimationOutcome.benchmarkAttemptsPerMealPerLineageBound - 1
                        ]
                    )
                } else {
                    try db.execute(
                        sql: """
                            DELETE FROM estimation_outcomes
                            WHERE benchmark_meal_id = ? AND model_version = ?
                              AND id NOT IN (
                                SELECT id FROM estimation_outcomes
                                WHERE benchmark_meal_id = ? AND model_version = ?
                                ORDER BY timestamp DESC, id DESC
                                LIMIT ?
                              )
                            """,
                        arguments: [
                            benchmarkMealID.uuidString, outcome.modelVersion,
                            benchmarkMealID.uuidString, outcome.modelVersion,
                            EstimationOutcome.benchmarkAttemptsPerMealPerLineageBound
                        ]
                    )
                }
            } else {
                try db.execute(
                    sql: """
                        DELETE FROM estimation_outcomes
                        WHERE benchmark_meal_id IS NULL
                          AND id NOT IN (
                            SELECT id FROM estimation_outcomes
                            WHERE benchmark_meal_id IS NULL
                            ORDER BY timestamp DESC, id DESC
                            LIMIT ?
                          )
                        """,
                    arguments: [EstimationOutcome.nonBenchmarkRowBound]
                )
            }
        }
        // No eventsDidChange: outcome rows are not `events` rows (quick_presets
        // convention) and a recording write must never ripple into UI refresh
        // of the event surfaces (Req 2.4).
    }

    public func estimationOutcomes(limit: Int) async throws -> [EstimationOutcome] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM estimation_outcomes
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map(Self.estimationOutcome(from:))
        }
    }

    // MARK: - Benchmark meals (specs/estimation/snaq-parity lane B)

    public func saveBenchmarkMeal(
        _ meal: BenchmarkMeal, carbsPer100g: (_ classID: String, _ edition: String) -> Double?
    ) async throws {
        // Validate and derive truth BEFORE the write: grams × carbs/100 g
        // summed over items — no volume, no β (Req 1.2). An unresolvable
        // class throws instead of contributing a silent 0 g (the
        // Macros.compute skip must not leak into ground truth).
        var truthCarbsG = 0.0
        for item in meal.items {
            guard BenchmarkMeal.itemGramsRange.contains(item.grams) else {
                throw PersistenceError.benchmarkGramsOutOfRange(item.grams)
            }
            guard let carbs = carbsPer100g(item.classID, meal.dbEdition) else {
                throw PersistenceError.benchmarkClassUnresolvable(item.classID)
            }
            truthCarbsG += item.grams * carbs / 100.0
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let itemsJSON = String(decoding: try encoder.encode(meal.items), as: UTF8.self)

        try await queue.write { db in
            // Immutability (Req 1.3 comparability): once attempts reference
            // the meal, an update would silently re-score history — reject
            // it; corrections create a new meal. Checked in the same write
            // transaction as the upsert so a concurrent attempt cannot race
            // past the gate.
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM benchmark_meals WHERE id = ?)",
                arguments: [meal.id.uuidString]
            ) ?? false
            if exists {
                let attempts = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM estimation_outcomes WHERE benchmark_meal_id = ?",
                    arguments: [meal.id.uuidString]
                ) ?? 0
                if attempts > 0 {
                    throw PersistenceError.benchmarkMealImmutable(meal.id)
                }
            }
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO benchmark_meals
                        (id, name, created_at, items, truth_carbs_g, db_edition, fidelity)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    meal.id.uuidString, meal.name, meal.createdAtMs,
                    itemsJSON, truthCarbsG, meal.dbEdition, meal.fidelity.rawValue
                ]
            )
        }
        // No eventsDidChange: benchmark meals are not `events` rows
        // (quick_presets convention).
    }

    public func benchmarkMeals() async throws -> [BenchmarkMeal] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM benchmark_meals ORDER BY created_at DESC, id DESC"
            ).map(Self.benchmarkMeal(from:))
        }
    }

    private static func benchmarkMeal(from row: Row) throws -> BenchmarkMeal {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else {
            throw PersistenceError.corruptRecord("invalid benchmark_meals UUID: \(idString)")
        }
        let fidelityString: String = row["fidelity"]
        guard let fidelity = BenchmarkFidelity(rawValue: fidelityString) else {
            throw PersistenceError.corruptRecord("invalid benchmark fidelity: \(fidelityString)")
        }
        let itemsJSON: String = row["items"]
        let items: [BenchmarkMealItem]
        do {
            items = try JSONDecoder().decode([BenchmarkMealItem].self, from: Data(itemsJSON.utf8))
        } catch {
            throw PersistenceError.corruptRecord("corrupt benchmark items JSON: \(error)")
        }
        return BenchmarkMeal(
            id: id,
            name: row["name"],
            createdAtMs: row["created_at"],
            items: items,
            truthCarbsG: row["truth_carbs_g"],
            dbEdition: row["db_edition"],
            fidelity: fidelity
        )
    }

    // MARK: - Dose suggestions (specs/data/insulin-dosing "The ledger")

    public func saveDoseSuggestion(_ row: DoseSuggestionRecord) async throws {
        // fpu is derived here and stored, never derived on read
        // (BenchmarkMeal.truthCarbsG precedent): the caller-supplied value is
        // ignored so a later change to the formula cannot reinterpret old rows.
        let fpu = DoseSuggestionRecord.fatProteinUnits(
            fatG: row.fatG, proteinG: row.proteinG
        )
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO dose_suggestions
                        (id, timestamp, meal_timestamp, row_version, rule_id,
                         rule_version, fat_rule_id, fat_rule_version, outcome,
                         suppression, carbs_g, carbs_source, source_event_id,
                         exact_units, rounded_units, increment_u, seed_clamped,
                         cr_g_per_u, cr_source, cr_fit_ref, band, local_hour,
                         utc_hour, utc_offset_s, iob_u, sigma_meal,
                         start_bg_mmol, start_bg_age_s, fat_g, protein_g, fpu,
                         fat_stale, given_units, insulin_event_id, build_stamp)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    row.id.uuidString, row.timestampMs, row.mealTimestampMs,
                    row.rowVersion, row.ruleID, row.ruleVersion,
                    row.fatRuleID, row.fatRuleVersion, row.outcome,
                    row.suppression, row.carbsG, row.carbsSource,
                    row.sourceEventID?.uuidString, row.exactUnits,
                    row.roundedUnits, row.incrementU, row.seedClamped,
                    row.crGramsPerUnit, row.crSource, row.crFitRef, row.band,
                    row.localHour, row.utcHour, row.utcOffsetS, row.iobU,
                    row.sigmaMeal, row.startBgMmol, row.startBgAgeS,
                    row.fatG, row.proteinG, fpu, row.fatStale,
                    row.givenUnits, row.insulinEventID?.uuidString,
                    row.buildStamp
                ]
            )
        }
        // No eventsDidChange: suggestion rows are not `events` rows (Req 7.4,
        // quick_presets / estimation_outcomes convention).
    }

    public func linkDose(
        suggestionID: UUID, insulinEventID: UUID, givenUnits: Double
    ) async throws {
        try await queue.write { db in
            // Side table only — the insulin event's metadata contract is left
            // exactly as medreg documents and parses it (Req 7.3, 9.7).
            try db.execute(
                sql: """
                    UPDATE dose_suggestions
                    SET given_units = ?, insulin_event_id = ?
                    WHERE id = ?
                    """,
                arguments: [
                    givenUnits, insulinEventID.uuidString, suggestionID.uuidString
                ]
            )
        }
        // No eventsDidChange (Req 7.4).
    }

    public func doseSuggestions(limit: Int) async throws -> [DoseSuggestionRecord] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dose_suggestions
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map(Self.doseSuggestion(from:))
        }
    }

    public func doseSuggestion(forSourceEventID id: UUID) async throws -> DoseSuggestionRecord? {
        try await queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM dose_suggestions
                    WHERE source_event_id = ?
                    ORDER BY timestamp DESC, id DESC
                    LIMIT 1
                    """,
                arguments: [id.uuidString]
            ).map(Self.doseSuggestion(from:))
        }
    }

    private static func doseSuggestion(from row: Row) throws -> DoseSuggestionRecord {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else {
            throw PersistenceError.corruptRecord("invalid dose_suggestions UUID: \(idString)")
        }
        let sourceEventIDString: String? = row["source_event_id"]
        let insulinEventIDString: String? = row["insulin_event_id"]
        return DoseSuggestionRecord(
            id: id,
            timestampMs: row["timestamp"],
            mealTimestampMs: row["meal_timestamp"],
            rowVersion: row["row_version"],
            ruleID: row["rule_id"],
            ruleVersion: row["rule_version"],
            fatRuleID: row["fat_rule_id"],
            fatRuleVersion: row["fat_rule_version"],
            outcome: row["outcome"],
            suppression: row["suppression"],
            carbsG: row["carbs_g"],
            carbsSource: row["carbs_source"],
            sourceEventID: sourceEventIDString.flatMap(UUID.init(uuidString:)),
            exactUnits: row["exact_units"],
            roundedUnits: row["rounded_units"],
            incrementU: row["increment_u"],
            seedClamped: row["seed_clamped"],
            crGramsPerUnit: row["cr_g_per_u"],
            crSource: row["cr_source"],
            crFitRef: row["cr_fit_ref"],
            band: row["band"],
            localHour: row["local_hour"],
            utcHour: row["utc_hour"],
            utcOffsetS: row["utc_offset_s"],
            iobU: row["iob_u"],
            sigmaMeal: row["sigma_meal"],
            startBgMmol: row["start_bg_mmol"],
            startBgAgeS: row["start_bg_age_s"],
            fatG: row["fat_g"],
            proteinG: row["protein_g"],
            fpu: row["fpu"],
            fatStale: row["fat_stale"],
            givenUnits: row["given_units"],
            insulinEventID: insulinEventIDString.flatMap(UUID.init(uuidString:)),
            buildStamp: row["build_stamp"]
        )
    }

    // MARK: - Dose occurrences (specs/data/dose-schedule "The occurrence ledger")

    public func openOccurrence(
        scheduleID: UUID, dueAt: Date
    ) async throws -> DoseOccurrence {
        let dueAtMs = Int64(dueAt.timeIntervalSince1970 * 1000)
        return try await queue.write { db in
            // INSERT OR IGNORE against the UNIQUE (schedule_id, due_at) index:
            // opening the same due instant twice — two foreground passes in a
            // second, or a foreground racing a notification handler — yields
            // ONE row, not two. Req 2.3's cap is enforced by the schema rather
            // than by every caller remembering to check first.
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO dose_occurrences
                        (id, schedule_id, due_at, outcome, closed_at,
                         insulin_event_id, was_nominal)
                    VALUES (?, ?, ?, ?, NULL, NULL, NULL)
                    """,
                arguments: [
                    UUID().uuidString, scheduleID.uuidString, dueAtMs,
                    OccurrenceOutcome.outstanding.rawValue
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM dose_occurrences
                    WHERE schedule_id = ? AND due_at = ?
                    """,
                arguments: [scheduleID.uuidString, dueAtMs]
            ) else {
                throw PersistenceError.corruptRecord(
                    "dose_occurrences row vanished after insert: \(scheduleID) @ \(dueAtMs)"
                )
            }
            return try Self.doseOccurrence(from: row)
        }
        // No eventsDidChange: occurrence rows are not `events` rows. Only the
        // insulin event fires it, so history refreshes exactly once per logged
        // dose rather than twice (dose_suggestions / estimation_outcomes
        // convention).
    }

    public func closeOccurrence(
        id: UUID,
        outcome: OccurrenceOutcome,
        closedAt: Date,
        insulinEventID: UUID? = nil,
        wasNominal: Bool? = nil
    ) async throws -> Bool {
        // Guard the vocabulary at the boundary: `outstanding` is the open
        // state, not an outcome, and closing to it would make the compare-and-
        // set a no-op that still reported success.
        guard outcome != .outstanding else { return false }
        let closedAtMs = Int64(closedAt.timeIntervalSince1970 * 1000)
        return try await queue.write { db in
            // The compare-and-set Req 4.6 rests on. `WHERE outcome =
            // 'outstanding'` inside the write transaction means a second action
            // on the same occurrence — a stale follow-up notification tapped
            // after the dose was logged in-app — matches zero rows and reports
            // no transition, so the caller writes no insulin event. This is a
            // single-process, single-writer path, so unlike the widget snapshot
            // guard it is exact rather than advisory.
            try db.execute(
                sql: """
                    UPDATE dose_occurrences
                    SET outcome = ?, closed_at = ?, insulin_event_id = ?,
                        was_nominal = ?
                    WHERE id = ? AND outcome = ?
                    """,
                arguments: [
                    outcome.rawValue, closedAtMs, insulinEventID?.uuidString,
                    wasNominal, id.uuidString,
                    OccurrenceOutcome.outstanding.rawValue
                ]
            )
            return db.changesCount > 0
        }
    }

    public func closeOccurrencesAsMissed(
        ids: [UUID], closedAt: Date
    ) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let closedAtMs = Int64(closedAt.timeIntervalSince1970 * 1000)
        return try await queue.write { db in
            var closed = 0
            for id in ids {
                // Each row carries the same outstanding-only gate as
                // `closeOccurrence`, so a row already logged or skipped between
                // the lazy read and this write is left exactly as it is.
                try db.execute(
                    sql: """
                        UPDATE dose_occurrences
                        SET outcome = ?, closed_at = ?
                        WHERE id = ? AND outcome = ?
                        """,
                    arguments: [
                        OccurrenceOutcome.missed.rawValue, closedAtMs,
                        id.uuidString, OccurrenceOutcome.outstanding.rawValue
                    ]
                )
                closed += db.changesCount
            }
            return closed
        }
    }

    public func outstandingOccurrences() async throws -> [DoseOccurrence] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dose_occurrences
                    WHERE outcome = ?
                    ORDER BY due_at ASC, id ASC
                    """,
                arguments: [OccurrenceOutcome.outstanding.rawValue]
            ).map(Self.doseOccurrence(from:))
        }
    }

    public func doseOccurrences(limit: Int) async throws -> [DoseOccurrence] {
        try await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dose_occurrences
                    ORDER BY due_at DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map(Self.doseOccurrence(from:))
        }
    }

    private static func doseOccurrence(from row: Row) throws -> DoseOccurrence {
        let idString: String = row["id"]
        let scheduleIDString: String = row["schedule_id"]
        guard let id = UUID(uuidString: idString),
              let scheduleID = UUID(uuidString: scheduleIDString) else {
            throw PersistenceError.corruptRecord(
                "invalid dose_occurrences UUID: \(idString) / \(scheduleIDString)"
            )
        }
        let outcomeRaw: String = row["outcome"]
        guard let outcome = OccurrenceOutcome(rawValue: outcomeRaw) else {
            throw PersistenceError.corruptRecord(
                "unknown dose_occurrences outcome: \(outcomeRaw)"
            )
        }
        let closedAtMs: Int64? = row["closed_at"]
        let insulinEventIDString: String? = row["insulin_event_id"]
        return DoseOccurrence(
            id: id,
            scheduleID: scheduleID,
            dueAt: Date(timeIntervalSince1970: Double(row["due_at"] as Int64) / 1000),
            outcome: outcome,
            closedAt: closedAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            insulinEventID: insulinEventIDString.flatMap(UUID.init(uuidString:)),
            wasNominal: row["was_nominal"]
        )
    }

    private static func estimationOutcome(from row: Row) throws -> EstimationOutcome {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else {
            throw PersistenceError.corruptRecord("invalid estimation_outcomes UUID: \(idString)")
        }
        let mealIDString: String? = row["meal_id"]
        let benchmarkMealIDString: String? = row["benchmark_meal_id"]
        return EstimationOutcome(
            id: id,
            timestampMs: row["timestamp"],
            outcome: row["outcome"],
            failureJSON: row["failure"],
            measurementsJSON: row["measurements"],
            mealID: mealIDString.flatMap(UUID.init(uuidString:)),
            modelVersion: row["model_version"],
            benchmarkMealID: benchmarkMealIDString.flatMap(UUID.init(uuidString:))
        )
    }

    private static func quickPreset(from row: Row) throws -> QuickPreset {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else {
            throw PersistenceError.corruptRecord("invalid quick_presets UUID: \(idString)")
        }
        let macros = IntakeMacros(
            proteinG: row["protein_g"],
            fatG: row["fat_g"],
            fibreG: row["fibre_g"]
        )
        return QuickPreset(
            id: id,
            name: row["name"],
            carbsG: row["carbs_g"],
            macros: macros,
            sortOrder: row["sort_order"]
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
    //
    // `correction_records` is deliberately NOT in this list and must not be
    // added (meal-review Req 9.9): the corpus admits no deletion path, and
    // it is not test data.
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
