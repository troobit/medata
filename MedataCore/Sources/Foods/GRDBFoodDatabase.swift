import Foundation
import GRDB

public enum FoodDatabaseError: Error {
    case bundleResourceMissing(String)
}

// GRDB-backed implementation of FoodDatabase per design §3.7 / §4.1 / §6.12.
//
// Opens a read-only bundled `food_db.sqlite`. When overlayPath is set, attaches
// `ifcdb_overlay.sqlite` via ATTACH DATABASE and uses the COALESCE merge query
// from design §4.1 (P13) so IFCDB values take priority over CoFID values.
public final class GRDBFoodDatabase: FoodDatabase, @unchecked Sendable {

    private let queue: DatabaseQueue
    private let _version: String
    private let _editions: [String]

    // Production factory — opens the bundled CoFID database from the module bundle.
    // Pass overlayEnabled = true to activate the IFCDB overlay per Decision 27.
    public static func bundled(overlayEnabled: Bool = false) throws -> GRDBFoodDatabase {
        let bundle = Bundle.module
        guard let mainURL = bundle.url(forResource: "food_db", withExtension: "sqlite") else {
            throw FoodDatabaseError.bundleResourceMissing("food_db.sqlite")
        }
        var overlayPath: String?
        if overlayEnabled {
            overlayPath = bundle.url(forResource: "ifcdb_overlay", withExtension: "sqlite")?.path
        }
        return try GRDBFoodDatabase(mainPath: mainURL.path, overlayPath: overlayPath)
    }

    // Designated init. Tests pass file-based temp paths; production uses bundled paths.
    public init(mainPath: String, overlayPath: String? = nil) throws {
        var config = Configuration()
        if let oPath = overlayPath {
            config.prepareDatabase { db in
                try db.execute(sql: "ATTACH DATABASE ? AS overlay", arguments: [oPath])
            }
        }
        let q = try DatabaseQueue(path: mainPath, configuration: config)
        _version = try q.read { db in
            try String.fetchOne(db, sql: "SELECT v FROM meta WHERE k = 'edition'") ?? "unknown"
        }
        _editions = try q.read { db in
            try String.fetchAll(db, sql: "SELECT v FROM meta WHERE k = 'edition'")
        }
        queue = q
    }

    public var version: String { _version }

    public func availableEditions() -> [String] { _editions }

    public func entry(for classId: String) -> FoodEntry? {
        try? queue.read { db in try fetchEntry(db, classId: classId, hasOverlay: overlayAttached(db)) }
    }

    public func entry(for classId: String, edition: String) -> FoodEntry? {
        // §6.12: use current DB regardless of edition string when only one edition is bundled.
        // A multi-edition implementation would dispatch here; v1 has one edition.
        entry(for: classId)
    }

    // MARK: - private

    private func overlayAttached(_ db: Database) -> Bool {
        (try? String.fetchOne(db, sql: "SELECT name FROM pragma_database_list WHERE name = 'overlay'")) != nil
    }

    private func fetchEntry(_ db: Database, classId: String, hasOverlay: Bool) throws -> FoodEntry? {
        if hasOverlay {
            return try fetchWithOverlay(db, classId: classId)
        } else {
            return try fetchBase(db, classId: classId)
        }
    }

    // Canonical merge query per design §4.1 (P13).
    private func fetchWithOverlay(_ db: Database, classId: String) throws -> FoodEntry? {
        let sql = """
            SELECT
                f.class_id,
                f.name,
                COALESCE(o.density,          f.density)          AS density,
                COALESCE(o.energy_kj_100,    f.energy_kj_100)    AS energy_kj_100,
                COALESCE(o.carbs_mono_100,   f.carbs_mono_100)   AS carbs_mono_100,
                COALESCE(o.protein_100,      f.protein_100)      AS protein_100,
                COALESCE(o.fat_100,          f.fat_100)          AS fat_100,
                COALESCE(o.fibre_100,        f.fibre_100)        AS fibre_100,
                COALESCE(o.beta,             f.beta)             AS beta,
                COALESCE(o.beta_status,      f.beta_status)      AS beta_status,
                COALESCE(o.density_source,   f.density_source)   AS density_source,
                COALESCE(o.composition_source, f.composition_source) AS composition_source
            FROM foods f
            LEFT JOIN overlay.foods_overlay o USING (class_id)
            WHERE f.class_id = ?
            """
        return try Row.fetchOne(db, sql: sql, arguments: [classId]).map(rowToEntry)
    }

    private func fetchBase(_ db: Database, classId: String) throws -> FoodEntry? {
        let sql = """
            SELECT class_id, name, density, energy_kj_100, carbs_mono_100,
                   protein_100, fat_100, fibre_100, beta, beta_status,
                   density_source, composition_source
            FROM foods WHERE class_id = ?
            """
        return try Row.fetchOne(db, sql: sql, arguments: [classId]).map(rowToEntry)
    }

    private func rowToEntry(_ row: Row) -> FoodEntry {
        let statusRaw: String = row["beta_status"]
        let status = BetaCalibrationStatus(rawValue: statusRaw) ?? .uncalibratedUnity
        return FoodEntry(
            classId:           row["class_id"],
            name:              row["name"],
            densityGPerCm3:    row["density"],
            energyKJPer100g:   row["energy_kj_100"],
            carbsMonoG:        row["carbs_mono_100"],
            proteinG:          row["protein_100"],
            fatG:              row["fat_100"],
            fibreG:            row["fibre_100"],
            beta:              row["beta"],
            calibrationStatus: status,
            densitySource:     row["density_source"],
            compositionSource: row["composition_source"]
        )
    }
}
