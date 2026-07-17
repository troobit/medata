import Foundation
import GRDB

public enum FoodDatabaseError: Error {
    case bundleResourceMissing(String)
}

// GRDB-backed implementation of FoodDatabase per design §3.7 / §4.1 / Decision 39.
//
// Opens read-only `cofid_db.sqlite` and ATTACHes `afcd_db.sqlite`. Lookups join
// the two via a COALESCE that returns CoFID values when both databases supply a
// class, falling back to AFCD for AFCD-only classes. Both sources are always
// bundled in v1; the previous IFCDB overlay and `ifcdbOverlayEnabled` toggle
// are removed.
public final class GRDBFoodDatabase: FoodDatabase, @unchecked Sendable {

    private let queue: DatabaseQueue
    private let _version: String
    private let _editions: [String]

    // Production factory — opens the bundled CoFID + AFCD databases from the
    // module bundle. Both are always present per Decision 39; no user toggle.
    public static func bundled() throws -> GRDBFoodDatabase {
        let bundle = Bundle.module
        guard let cofidURL = bundle.url(forResource: "cofid_db", withExtension: "sqlite") else {
            throw FoodDatabaseError.bundleResourceMissing("cofid_db.sqlite")
        }
        guard let afcdURL = bundle.url(forResource: "afcd_db", withExtension: "sqlite") else {
            throw FoodDatabaseError.bundleResourceMissing("afcd_db.sqlite")
        }
        return try GRDBFoodDatabase(cofidPath: cofidURL.path, afcdPath: afcdURL.path)
    }

    // Designated init. Tests pass file-based temp paths; production uses bundled paths.
    public init(cofidPath: String, afcdPath: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "ATTACH DATABASE ? AS afcd", arguments: [afcdPath])
        }
        let q = try DatabaseQueue(path: cofidPath, configuration: config)
        let cofidEdition = try q.read { db in
            try String.fetchOne(db, sql: "SELECT v FROM meta WHERE k = 'edition'") ?? "CoFID"
        }
        let afcdEdition = try q.read { db in
            try String.fetchOne(db, sql: "SELECT v FROM afcd.meta WHERE k = 'edition'") ?? "AFCD"
        }
        // The composite edition string is what gets written to MealRecord.database_edition
        // so a meal can be re-derived later against the same pair (Decision 39, Req §11.9).
        _version = "\(cofidEdition) + \(afcdEdition)"
        _editions = [cofidEdition, afcdEdition, _version]
        queue = q
    }

    public var version: String { _version }

    public func availableEditions() -> [String] { _editions }

    public func entry(for classId: String) -> FoodEntry? {
        try? queue.read { db in try fetchEntry(db, classId: classId) }
    }

    public func entry(for classId: String, edition: String) -> FoodEntry? {
        // §6.12: v1 bundles a single (CoFID + AFCD) pair so the edition string
        // is informational. Multi-edition dispatch is reserved for a future
        // migration scenario per Decision 24.
        entry(for: classId)
    }

    // Servings live in the CoFID DB only (lookup table, not composition
    // data — the same one-home rule as liquid_servings), so no AFCD join.
    public func solidServing(for classId: String) -> SolidServing? {
        try? queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT unit_singular, unit_plural, grams_per_unit, step
                    FROM solid_servings WHERE class_id = ?
                    """,
                arguments: [classId]
            ).map { row in
                SolidServing(
                    unitSingular: row["unit_singular"],
                    unitPlural:   row["unit_plural"],
                    gramsPerUnit: row["grams_per_unit"],
                    step:         row["step"]
                )
            }
        }
    }

    // MARK: - private

    // Canonical CoFID-wins COALESCE join (design §4.1 / Decision 39). Any class
    // present in CoFID returns CoFID values; classes that are AFCD-only fall
    // through to AFCD via the FULL OUTER join shape (emulated here as a UNION
    // of a LEFT JOIN both directions, since SQLite has no FULL OUTER).
    private func fetchEntry(_ db: Database, classId: String) throws -> FoodEntry? {
        let sql = """
            WITH merged AS (
                SELECT
                    c.class_id           AS class_id,
                    c.name               AS name,
                    c.density            AS density,
                    c.energy_kj_100      AS energy_kj_100,
                    c.carbs_mono_100     AS carbs_mono_100,
                    c.protein_100        AS protein_100,
                    c.fat_100            AS fat_100,
                    c.fibre_100          AS fibre_100,
                    c.beta               AS beta,
                    c.beta_status        AS beta_status,
                    c.density_source     AS density_source,
                    c.composition_source AS composition_source,
                    c.beta_provenance    AS beta_provenance,
                    c.device_verified    AS device_verified
                FROM foods c
                WHERE c.class_id = ?
                UNION ALL
                SELECT
                    a.class_id           AS class_id,
                    a.name               AS name,
                    a.density            AS density,
                    a.energy_kj_100      AS energy_kj_100,
                    a.carbs_mono_100     AS carbs_mono_100,
                    a.protein_100        AS protein_100,
                    a.fat_100            AS fat_100,
                    a.fibre_100          AS fibre_100,
                    a.beta               AS beta,
                    a.beta_status        AS beta_status,
                    a.density_source     AS density_source,
                    a.composition_source AS composition_source,
                    a.beta_provenance    AS beta_provenance,
                    a.device_verified    AS device_verified
                FROM afcd.foods a
                WHERE a.class_id = ?
                AND NOT EXISTS (SELECT 1 FROM foods c WHERE c.class_id = a.class_id)
            )
            SELECT * FROM merged LIMIT 1
            """
        return try Row.fetchOne(db, sql: sql, arguments: [classId, classId])
            .map(rowToEntry)
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
            compositionSource: row["composition_source"],
            betaProvenance:    row["beta_provenance"],
            deviceVerified:    row["device_verified"]
        )
    }
}
