import Foundation
import GRDB
import PortableContracts
import ZIPFoundation

// GRDB-backed PersistenceStore. Uses meals.sqlite per design §4.1.
// record_json column is protobuf-JSON of PbMealRecord (Decision 31).
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
        try queue.write { db in try GRDBPersistenceStore.createSchema(db) }
    }

    // MARK: - PersistenceStore

    public func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {
        let json = try record.jsonString()
        let artefactsDir = "meals/\(record.id.uuidString)"
        let sigmaMeal = Double(record.confidence.sigmaMeal)
        let totalCarbsG = Double(record.macros.totalCarbsG)
        let createdAtMs = Int64(record.createdAt.timeIntervalSince1970 * 1000)

        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meals
                        (id, created_at, capture_path, database_edition, palette_version,
                         sigma_meal, total_carbs_g, record_json, artefacts_dir,
                         segmenter_source, photo_asset_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString,
                    createdAtMs,
                    record.capturePath.rawValue,
                    record.databaseEdition,
                    record.paletteVersion,
                    sigmaMeal,
                    totalCarbsG,
                    json,
                    artefactsDir,
                    record.segmenterSource,
                    record.photoAssetID
                ]
            )

            for (classId, pbStatus) in record.perClassCalibration {
                let classEntry = record.macros.perClass[classId]
                try db.execute(
                    sql: """
                        INSERT INTO meal_classes
                            (meal_id, class_id, beta_status, mass_g, carbs_g)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        record.id.uuidString,
                        classId,
                        pbStatus.betaStatusString,
                        Double(classEntry?.massG ?? 0),
                        Double(classEntry?.carbsG ?? 0)
                    ]
                )
            }

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
    }

    public func meal(id: UUID) async throws -> MealRecord {
        let row = try await queue.read { db in
            try Row.fetchOne(db,
                sql: """
                    SELECT record_json, palette_version, segmenter_source, photo_asset_id
                    FROM meals WHERE id = ?
                    """,
                arguments: [id.uuidString])
        }
        guard let row else { throw PersistenceError.mealNotFound(id) }
        let json: String = row["record_json"]
        let paletteVersion: String = row["palette_version"]
        let segmenterSource: String? = row["segmenter_source"]
        let photoAssetID: String? = row["photo_asset_id"]
        return try MealRecord.from(
            jsonString: json,
            paletteVersion: paletteVersion,
            segmenterSource: segmenterSource,
            photoAssetID: photoAssetID
        )
    }

    public func allMeals() async throws -> [MealRecord] {
        let rows = try await queue.read { db in
            try Row.fetchAll(db,
                sql: """
                    SELECT record_json, palette_version, segmenter_source, photo_asset_id
                    FROM meals ORDER BY created_at DESC
                    """)
        }
        return try rows.map { row in
            let json: String = row["record_json"]
            let paletteVersion: String = row["palette_version"]
            let segmenterSource: String? = row["segmenter_source"]
            let photoAssetID: String? = row["photo_asset_id"]
            return try MealRecord.from(
                jsonString: json,
                paletteVersion: paletteVersion,
                segmenterSource: segmenterSource,
                photoAssetID: photoAssetID
            )
        }
    }

    public func deleteMeal(id: UUID) async throws {
        let artefactsDir = try await queue.write { db -> String? in
            let dir = try String.fetchOne(db,
                sql: "SELECT artefacts_dir FROM meals WHERE id = ?",
                arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM meal_classes WHERE meal_id = ?",
                           arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM meal_artefacts WHERE meal_id = ?",
                           arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM corrections WHERE meal_id = ?",
                           arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM meals WHERE id = ?",
                           arguments: [id.uuidString])
            return dir
        }
        if let artefactsDir {
            // Best-effort cleanup — log via stderr but swallow per design.md.
            let url = artefactsBaseURL.appendingPathComponent(artefactsDir)
            try? FileManager.default.removeItem(at: url)
        }
        changeBroadcaster.notify()
    }

    public var mealsDidChange: AsyncStream<Void> { changeBroadcaster.subscribe() }

    public func deleteArtefacts(olderThan date: Date) async throws {
        let cutoffMs = Int64(date.timeIntervalSince1970 * 1000)
        let dirs: [String] = try await queue.read { db in
            try String.fetchAll(db,
                sql: "SELECT artefacts_dir FROM meals WHERE created_at < ?",
                arguments: [cutoffMs])
        }
        for dir in dirs {
            let url = artefactsBaseURL.appendingPathComponent(dir)
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

    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS meals (
                id               TEXT PRIMARY KEY,
                created_at       INTEGER NOT NULL,
                capture_path     TEXT NOT NULL,
                database_edition TEXT NOT NULL,
                palette_version  TEXT NOT NULL,
                sigma_meal       REAL NOT NULL,
                total_carbs_g    REAL NOT NULL,
                record_json      BLOB NOT NULL,
                artefacts_dir    TEXT NOT NULL,
                segmenter_source TEXT,
                photo_asset_id   TEXT
            );
            CREATE TABLE IF NOT EXISTS meal_classes (
                meal_id     TEXT NOT NULL,
                class_id    TEXT NOT NULL,
                beta_status TEXT NOT NULL,
                mass_g      REAL NOT NULL,
                carbs_g     REAL NOT NULL,
                PRIMARY KEY (meal_id, class_id)
            );
            CREATE INDEX IF NOT EXISTS meal_classes_class ON meal_classes(class_id);
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
            CREATE INDEX IF NOT EXISTS meals_created_at ON meals(created_at);
            CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
            """)
        try db.execute(
            sql: "INSERT OR IGNORE INTO meta (k, v) VALUES ('schema_version', '1')"
        )
        // v1.1 additive columns. Existing v1.0 databases need an ALTER; new
        // databases already have them from the CREATE TABLE above so ignore
        // the "duplicate column" error.
        try? db.execute(sql: "ALTER TABLE meals ADD COLUMN segmenter_source TEXT")
        try? db.execute(sql: "ALTER TABLE meals ADD COLUMN photo_asset_id TEXT")
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

// MARK: - Helpers

private extension PbBetaCalibrationStatus {
    var betaStatusString: String {
        switch self {
        case .calibrated: return "calibrated"
        case .uncalibratedPooled: return "uncalibrated_pooled"
        case .uncalibratedUnity, .unspecified, .UNRECOGNIZED: return "uncalibrated_unity"
        }
    }
}
