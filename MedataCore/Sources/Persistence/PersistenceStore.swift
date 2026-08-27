import Foundation
import PortableContracts

public enum PersistenceError: Error, Equatable {
    case corruptRecord(String)
    case mealNotFound(UUID)
    case archiveFailed(String)
    // Insulin dose rejected at the store layer: units outside 0...60
    // (PRD regression-suggestion-integration Core 4).
    case insulinUnitsOutOfRange(Double)
    // Manual carb entry rejected at the store layer: carbsG outside 1...999
    // (specs/data/manual-carb-intake Req 1.4).
    case intakeCarbsOutOfRange(Double)
    // Blood-glucose reading rejected at the store layer: mmol/L outside
    // 1...30 (specs/data/fingerprick-glucose Req 2.3). The entry pad cannot
    // express such a value; the guard is here so a deep-linked or future
    // caller cannot bypass the pad's bound.
    case bloodGlucoseOutOfRange(Double)
    // Benchmark-meal item rejected at the store layer: grams outside 1...5000
    // (specs/estimation/snaq-parity design "Error Handling").
    case benchmarkGramsOutOfRange(Double)
    // Benchmark-meal item names a palette class with no food-DB entry at the
    // current edition. Thrown instead of skipping the item — a silent 0 g
    // truth contribution would poison MAE (snaq-parity Req 1.2; the
    // Macros.compute skip must not leak into ground truth).
    case benchmarkClassUnresolvable(String)
    // Benchmark-meal update rejected: the meal already has estimation
    // attempts recorded against it. Editing items/grams would silently
    // re-score history — corrections create a new meal (snaq-parity lane B).
    case benchmarkMealImmutable(UUID)
}

// Vocabulary for the `event_type` column on the events table. Centralised here
// so call sites cannot typo the literal (Decision 9). Future event types extend
// this namespace with additional constants.
public enum EventType {
    public static let meal = "meal"
    // Blood glucose reading; `value` carries mmol/L (UI Design Handoff 00
    // Decision 13; specs/data/libre-ingestion Req 4.1). Trends reads
    // exclusively these rows; ingestion writes them via `ingestBsl` below.
    public static let bsl = "bsl"
    // Insulin dose; `value` carries units (U). Row shape follows medreg's
    // convention (medreg docs/insulin-event-convention.md, metadata schema
    // version 1); medreg reads these rows from the export archive.
    public static let insulin = "insulin"
    // Manual carb intake (specs/data/manual-carb-intake); `value` carries
    // carbohydrate grams. Row shape mirrors the insulin convention above.
    public static let intake = "intake"
    // Recorded activity (specs/data/activity-events Req 1.1); `value` carries
    // duration in MINUTES and is absent when no duration was given (Req 1.5).
    // `timestamp` is the activity start. Row shape mirrors the insulin
    // convention above; see `ActivityEvent`.
    public static let activity = "activity"
}

// Whether a dose is fast-acting meal/correction insulin or background
// insulin. Raw values are the exact `metadata.kind` strings in the medreg
// convention.
// `Codable` so `ScheduledDose` (specs/data/dose-schedule) can round-trip
// through the settings store as a plain Codable array; the raw values are the
// medreg strings above, so the encoded form is the convention's own vocabulary.
public enum InsulinKind: String, Sendable, Equatable, CaseIterable, Codable {
    case bolus
    case basal
}

// One insulin dose bound for the event log (medreg convention). `timestamp`
// is the administration time; `units` is the dose in international units (U);
// `insulinType` is the free-text product string (e.g. "NovoRapid");
// `note` is optional free text — omitted from metadata entirely when nil.
public struct InsulinDose: Sendable, Equatable {
    // Version of the insulin metadata convention (`metadata.schema_version`).
    public static let metadataSchemaVersion = 1

    public let id: UUID
    public let timestamp: Date
    public let units: Double
    public let kind: InsulinKind
    public let insulinType: String
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        units: Double,
        kind: InsulinKind,
        insulinType: String,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.units = units
        self.kind = kind
        self.insulinType = insulinType
        self.note = note
    }
}

// One extracted glucose reading bound for the event log
// (specs/data/libre-ingestion Req 4.1).
public struct BslReading: Sendable, Equatable {
    public let timestampMs: Int64  // UTC ms since epoch, 5-minute grid
    public let value: Double  // mmol/L, one decimal

    public init(timestampMs: Int64, value: Double) {
        self.timestampMs = timestampMs
        self.value = value
    }
}

// One live glucose reading bound for the event log (specs/data/cgm-connect
// Req 4.1, 4.2). The caller (GlucoseIngestion) has already snapped the
// instant to the 5-minute grid and normalised the value to mmol/L at one
// decimal (Decision 4, Req 5.5); the store builds the row's metadata JSON.
public struct LiveBslReading: Sendable, Equatable {
    public let timestampMs: Int64  // UTC ms since epoch, 5-minute grid
    public let mmolL: Double  // mmol/L, one decimal
    public let sourceID: String
    public let nativeInstantMs: Int64  // pre-snap instant, kept in metadata
    public let nativeID: String?  // source's native sample identity, if any

    public init(
        timestampMs: Int64, mmolL: Double, sourceID: String,
        nativeInstantMs: Int64, nativeID: String? = nil
    ) {
        self.timestampMs = timestampMs
        self.mmolL = mmolL
        self.sourceID = sourceID
        self.nativeInstantMs = nativeInstantMs
        self.nativeID = nativeID
    }
}

// One blood-glucose reading bound for the event log (specs/data/
// fingerprick-glucose Reqs 1.3, 2.5, 2.6; Decisions 6 and 10).
//
// The instant is stored exactly as measured, NOT snapped to the 5-minute grid.
// The grid is a cross-source dedup device for samples of one continuous trace;
// a fingerstick has no counterpart to deduplicate against, so snapping would
// falsify its instant and manufacture a collision with the sensor row at that
// mark.
//
// `nativeID` is the source's own stable identity — `HKObject.uuid` for a meter
// sample arriving through Apple Health. A hand entry has none and is never
// deduplicated: two fingersticks a minute apart are two measurements.
public struct BloodBslReading: Sendable, Equatable {
    public let instant: Date  // exact, not grid-snapped
    public let mmolL: Double  // one decimal, rounded at the caller's single rounding point
    public let sourceID: String  // "healthkit" | "manual"
    public let nativeID: String?  // HKObject.uuid; nil for a hand entry

    public init(instant: Date, mmolL: Double, sourceID: String, nativeID: String? = nil) {
        self.instant = instant
        self.mmolL = mmolL
        self.sourceID = sourceID
        self.nativeID = nativeID
    }
}

// Per-image ingest report (specs/data/libre-ingestion Req 5.4).
public struct BslIngestSummary: Sendable, Equatable {
    public struct Discrepancy: Sendable, Equatable {
        public let timestampMs: Int64
        public let kept: Double
        public let new: Double

        public init(timestampMs: Int64, kept: Double, new: Double) {
            self.timestampMs = timestampMs
            self.kept = kept
            self.new = new
        }
    }

    public let extracted: Int
    public let stored: Int
    public let skippedExisting: Int
    public let agreeing: Int  // overlapping readings within ±0.3 mmol/L
    public let discrepant: [Discrepancy]

    public init(
        extracted: Int, stored: Int, skippedExisting: Int,
        agreeing: Int, discrepant: [Discrepancy]
    ) {
        self.extracted = extracted
        self.stored = stored
        self.skippedExisting = skippedExisting
        self.agreeing = agreeing
        self.discrepant = discrepant
    }
}

// One quick-add preset (specs/data/manual-carb-intake, design.md "Quick-add
// presets — new table"). Presets are a flat, user-editable collection
// (Decision 6) stored in their own `quick_presets` table — CRUD'd
// independently of the `events` log, not one of its rows. `macros` fields
// absent on a given preset round-trip as `nil`, matching Req 2.3's
// absent-not-zero rule for manual entries.
public struct QuickPreset: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var carbsG: Double
    public var macros: IntakeMacros
    public var sortOrder: Int
    // The meal a capture-born preset was frozen from (manual-carb-intake
    // Req 8.8/8.9): a point-in-time stamp, never dereferenced — deleting or
    // correcting the meal changes nothing about the preset. Nil for
    // hand-authored presets.
    public var sourceMealID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        carbsG: Double,
        macros: IntakeMacros = IntakeMacros(),
        sortOrder: Int,
        sourceMealID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.carbsG = carbsG
        self.macros = macros
        self.sortOrder = sortOrder
        self.sourceMealID = sourceMealID
    }

    // Next free slot at the end of the grid — one expression, one home
    // (manual-carb-intake task 13; IntakeModel and the preset drafts all
    // call this).
    public static func nextSortOrder(after presets: [QuickPreset]) -> Int {
        (presets.map(\.sortOrder).max() ?? -1) + 1
    }
}

// Vocabulary for the `outcome` column on `estimation_outcomes` rows,
// shared by the producer (EstimationAttemptRecord.Outcome is this type) and
// the benchmark-report filters so the stored strings cannot drift apart
// (EventType precedent). Raw values are the exact column strings.
public enum EstimationOutcomeKind: String, Codable, Sendable, Equatable, CaseIterable {
    case success
    case refused
}

// One estimation attempt — success or refusal — persisted on-device
// (specs/estimation/snaq-parity Req 2, design "Persistence" + Data Models).
// Outcome rows live in their own `estimation_outcomes` table following the
// quick_presets convention: CRUD'd independently of the `events` log, no
// `eventsDidChange` interaction. `measurementsJSON` is the serialised
// `EstimationAttemptRecord` snapshot (schema-versioned via its `v` field) and
// `failureJSON` its {domain, case, payload} failure encoding — both built by
// the App/Pipeline layer and stored opaquely here, because Persistence sits
// below Pipeline in the dependency graph and cannot see the typed record.
public struct EstimationOutcome: Sendable, Equatable, Identifiable {
    // Split eviction bounds (snaq-parity Decision 7 / design lane A): the two
    // populations are bounded separately so neither starves the other.
    public static let nonBenchmarkRowBound = 500
    public static let benchmarkAttemptsPerMealPerLineageBound = 10

    public let id: UUID
    public let timestampMs: Int64  // UTC ms since epoch (last_sweep_at_ms precedent)
    public let outcome: String  // EstimationOutcomeKind raw value
    public let failureJSON: String?  // nil on success
    public let measurementsJSON: String
    public let mealID: UUID?  // saved MealRecord reference (success only)
    public let modelVersion: String  // segmenter lineage tag
    public let benchmarkMealID: UUID?  // set when launched from a benchmark meal

    public init(
        id: UUID = UUID(),
        timestampMs: Int64,
        outcome: String,
        failureJSON: String?,
        measurementsJSON: String,
        mealID: UUID?,
        modelVersion: String,
        benchmarkMealID: UUID?
    ) {
        self.id = id
        self.timestampMs = timestampMs
        self.outcome = outcome
        self.failureJSON = failureJSON
        self.measurementsJSON = measurementsJSON
        self.mealID = mealID
        self.modelVersion = modelVersion
        self.benchmarkMealID = benchmarkMealID
    }
}

// Weighing fidelity of a benchmark meal's ground truth (snaq-parity design
// lane B): `weighed` = items weighed to ±1 g before plating; `package` =
// pack-label weights, the marked lower-fidelity fallback. Raw values are the
// exact `fidelity` column strings.
public enum BenchmarkFidelity: String, Sendable, Equatable, CaseIterable {
    case weighed
    case package
}

// One weighed item of a benchmark meal. Persisted inside the `items` JSON
// column as [{class_id, grams}] (design Data Models) — the CodingKeys pin the
// export-facing snake_case shape.
public struct BenchmarkMealItem: Sendable, Codable, Equatable {
    public let classID: String  // 35-class palette id, e.g. "white_rice"
    public let grams: Double

    enum CodingKeys: String, CodingKey {
        case classID = "class_id"
        case grams
    }

    public init(classID: String, grams: Double) {
        self.classID = classID
        self.grams = grams
    }
}

// One weighed benchmark meal (specs/estimation/snaq-parity Req 1.2/1.3,
// design lane B + Data Models). `truthCarbsG` is DERIVED BY THE STORE at save
// (grams × carbs_per_100g / 100 summed over items — no volume, no β, so
// truth isolates the estimation pipeline); the value carried by a meal passed
// to `saveBenchmarkMeal` is ignored, and the stored figure is authoritative.
public struct BenchmarkMeal: Sendable, Equatable, Identifiable {
    // Bounds accepted at the store layer for each item's weighed grams.
    public static let itemGramsRange = 1.0...5000.0

    public let id: UUID
    public let name: String
    public let createdAtMs: Int64  // UTC ms since epoch (last_sweep_at_ms precedent)
    public let items: [BenchmarkMealItem]
    public let truthCarbsG: Double  // derived at save; see above
    public let dbEdition: String  // food-DB edition the truth was resolved against
    public let fidelity: BenchmarkFidelity

    public init(
        id: UUID = UUID(),
        name: String,
        createdAtMs: Int64,
        items: [BenchmarkMealItem],
        truthCarbsG: Double = 0,
        dbEdition: String,
        fidelity: BenchmarkFidelity
    ) {
        self.id = id
        self.name = name
        self.createdAtMs = createdAtMs
        self.items = items
        self.truthCarbsG = truthCarbsG
        self.dbEdition = dbEdition
        self.fidelity = fidelity
    }
}

// Generic surface for a row in the events table (Decision 8). `value` is
// `Double?` so future event types without a canonical scalar fit without a
// schema change. `metadata` is the raw JSON string — consumers decide how to
// decode it.
public struct Event: Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: String
    public let value: Double?
    public let metadata: String

    public init(
        id: UUID,
        timestamp: Date,
        eventType: String,
        value: Double?,
        metadata: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.value = value
        self.metadata = metadata
    }
}

public protocol PersistenceStore: Sendable {
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws
    func meal(id: UUID) async throws -> MealRecord
    // Age sweep over per-meal artefact directories. Meals holding a
    // correction_records row with an actual correction (class_corrected,
    // rejected, absent or amount_corrected) are exempt regardless of caller
    // (meal-review Req 8.4): the mask is pixel-level supervision for a
    // retained training example. Deletes the meal_artefacts rows alongside
    // the directories.
    func deleteArtefacts(olderThan date: Date) async throws
    func exportArchive() async throws -> String    // returns file path; UI wraps in URL
    func sweepIfDue() async throws
    // Stamps the PHAsset.localIdentifier returned by the Photos library save on
    // an existing meal (Decision 37). Called by the capture flow after the
    // pipeline returns and the photo save completes; pre-existing rows have
    // photo_asset_id = '' until this is invoked.
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws

    // v1.1 Meals tab — additive surface per UI Decision 15.
    // `allMeals` returns rows sorted by `createdAt` descending. `deleteMeal`
    // removes the SQLite row plus the per-meal artefact directory (best-effort)
    // and DOES NOT touch the user's Photos library. `eventsDidChange` emits a
    // tick after every successful event-row write; subscribers see the latest
    // event under `BufferingPolicy.bufferingNewest(1)`.
    func allMeals() async throws -> [MealRecord]
    func deleteMeal(id: UUID) async throws

    // Per-meal artefact byte transport (UI Design Handoff 00, Decision 15). No
    // filesystem paths cross the store boundary. `writeArtefact` writes the file
    // under `meals/{id}/{filename}` FIRST, then inserts the `meal_artefacts`
    // row, so a crash between the two leaves an orphan file, never a dangling
    // row. `artefactData` returns the bytes, or nil when the artefact row or its
    // file is absent — it NEVER throws for absence; that nil is the §6.8
    // photo-only fallback signal.
    func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws
    func artefactData(mealId: UUID, kind: String) async throws -> Data?

    // Req 1.4, 1.5. Closed interval; both bounds inclusive. Ordered
    // `(timestamp ASC, id ASC)`. `type == nil` returns every event type;
    // otherwise filters to `event_type = type`. Fail-fast: any per-row decode
    // failure throws `PersistenceError.corruptRecord` for the whole call.
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event]

    // Req 4.4. Returns the corrections side-table rows for a meal ordered by
    // `created_at ASC`. Empty array when none. The meal event's `value` is
    // unaffected; overlay composition is the caller's job.
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection]

    // MARK: Correction records (specs/ui/meal-review)
    //
    // One row per detected food per capture, keyed (meal_id, predicted_class):
    // the predicted side never changes after creation (Req 9.2), the corrected
    // side is updated in place (Req 9.3). The store is never pruned — no age,
    // count or sweep deletion, exempt from deleteMeal/deleteRecords cascades
    // and from the Debug reset (Req 9.9, 9.10).

    // Creation: INSERT ... DO NOTHING per row, one transaction. Re-presenting
    // the review surface for the same meal must not reset created_at or
    // overwrite a predicted side (Req 9.2); repeats are silent no-ops.
    // Does not tick eventsDidChange — creation changes no displayed value.
    func createCorrectionRecords(_ records: [PbCorrectionRecord]) async throws

    // Mutation: INSERT ... ON CONFLICT (meal_id, predicted_class) DO UPDATE
    // touching the corrected columns only — created_at and outcome_id keep
    // their first-write values on conflict. The insert arm self-heals a row
    // whose creation failed (that error is swallowed per Req 8.5); a bare
    // UPDATE would silently no-op forever. When `upsertingCorrection` is
    // non-nil, the meal's reconciling `corrections` row is upserted in the
    // SAME transaction (design "the reconciling write") and eventsDidChange
    // ticks once. Never INSERT OR REPLACE on either table.
    func updateCorrectionRecord(
        _ record: PbCorrectionRecord,
        upsertingCorrection correction: PbUserCorrection?
    ) async throws

    // Batch mutation for one meal (the whole-meal scale, Req 6.3): every row
    // update plus the reconciling corrections upsert in ONE transaction, so
    // a force-quit mid-write cannot diverge the corpus from Records. Same
    // per-row semantics as updateCorrectionRecord; all records must share
    // one meal_id. Empty input is a no-op. Ticks eventsDidChange once when
    // `upsertingCorrection` is non-nil.
    func updateCorrectionRecords(
        _ records: [PbCorrectionRecord],
        upsertingCorrection correction: PbUserCorrection?
    ) async throws

    // One `corrections` row per meal, `created_at` fixed at review-session
    // start, ON CONFLICT (meal_id, created_at) DO UPDATE. Every reader takes
    // the latest row, so one row satisfies them all. `appendCorrection` is
    // untouched for its existing callers. Ticks eventsDidChange.
    func upsertCorrection(mealId: UUID, correction: PbUserCorrection) async throws

    // Reads for the review surface, browse and export (Req 9.13). `for:` is
    // ordered predicted_class ASC; the unscoped read is newest-updated first.
    func correctionRecords(for mealId: UUID) async throws -> [PbCorrectionRecord]
    func allCorrectionRecords() async throws -> [PbCorrectionRecord]

    // Recency shortlist input (Req 3.1, meal-review Decision 18): distinct
    // corrected class ids previously chosen for this predicted class, newest
    // first, excluding the predicted class itself. Empty when never corrected.
    func recentCorrectedClassIds(
        forPredictedClass classId: String, limit: Int
    ) async throws -> [String]

    // Req 4.5. Emits after every successful event-row write or delete
    // (`save`, `deleteMeal`, `updatePhotoAssetID`, and `ingestBsl` when it
    // stored at least one row). Also emits on `appendCorrection` after a
    // successful insert (Decision 18) so Data rows and Meal overview refresh
    // their corrected totals, even though corrections live in their own side
    // table.
    var eventsDidChange: AsyncStream<Void> { get }

    // specs/data/libre-ingestion Req 5.1. True when an earlier ingest for
    // this content hash committed; rejected images are never marked.
    func isImageProcessed(hash: String) async throws -> Bool

    // specs/data/libre-ingestion Reqs 4.1–4.5, 5.2–5.4. Keep-first merge in
    // ONE transaction together with the processed_images marker: inserts
    // only at timestamps with no existing bsl row; overlaps are classified
    // agreeing (≤ 0.3 mmol/L) or discrepant and never written. Notifies
    // `eventsDidChange` once per batch, only when at least one row stored.
    func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary

    // specs/data/cgm-connect Reqs 4.1–4.5. Live-ingestion sibling to
    // ingestBsl: no processed_images marker (that's screenshot-import-only),
    // per-row metadata built by the store itself — mirroring how
    // saveInsulinDose builds its own JSON, GlucoseIngestion callers never
    // construct event JSON. Same keep-first merge as ingestBsl, so a live
    // reading and a screenshot reading at the same grid instant dedup
    // uniformly regardless of source. One transaction; notifies
    // `eventsDidChange` once iff at least one row was inserted.
    func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary

    // specs/data/fingerprick-glucose Reqs 1.3, 1.4, 2.5, 2.6, 4.1, 4.4, 4.5.
    // The blood sibling to `ingestLiveBsl`, sharing none of its code: ONE row
    // in ONE transaction at the exact measured instant, with no grid and no
    // keep-first. Insert-only — it holds no UPDATE and no DELETE against any
    // existing row, which is how Reqs 4.1 and 4.4 are met structurally rather
    // than by discipline.
    //
    // Metadata carries `provenance` ("blood"), `source_id`, `native_id` when
    // present, and the Req 4.5 pairing stamp (`paired_sensor_value`,
    // `paired_sensor_instant`, `sensor_delta`) when a sensor-provenance row
    // falls in the preceding 15 minutes — keys absent, never null, when nil.
    //
    // Returns the new event's id, or nil when the reading was a re-delivery of
    // one already stored under the same `(source_id, native_id)`. Notifies
    // `eventsDidChange` once, and only when a row was actually written.
    // Throws `bloodGlucoseOutOfRange` outside 1...30 mmol/L.
    @discardableResult
    func recordBloodBsl(_ reading: BloodBslReading) async throws -> UUID?

    // PRD regression-suggestion-integration Core 2–4. Writes ONE `events` row
    // per dose, exactly per medreg's convention (medreg
    // docs/insulin-event-convention.md): `value` = units (REAL, non-negative),
    // `timestamp` = administration time in UTC ms, `metadata` = JSON object
    // with `kind`, `insulin_type`, `schema_version` (integer 1), plus `note`
    // only when provided (key absent — not null — when nil). Throws
    // `insulinUnitsOutOfRange` for units < 0 or > 60; 0 and 60 are accepted
    // (the UI enforces its own floor). Notifies `eventsDidChange` once.
    func saveInsulinDose(_ dose: InsulinDose) async throws

    // PRD regression-suggestion-integration Core 3. Deletes a single insulin
    // event by id. The DELETE is gated on `event_type = insulin`, so a meal or
    // bsl row sharing the id survives, and no side tables are touched.
    // Notifies `eventsDidChange` once.
    func deleteInsulinEvent(id: UUID) async throws

    // specs/data/manual-carb-intake Req 1.3, 2.3, 6.1, 6.3. Writes ONE
    // `events` row per entry: `value` = carbsG (REAL), `timestamp` = the
    // user-set time, `metadata` = JSON object with `subtype`,
    // `schema_version` (integer 1), `source`, plus `preset_id` (quickadd
    // only) and macro keys (`protein_g`/`fat_g`/`fibre_g`) — all omitted,
    // never null, when absent. Throws `intakeCarbsOutOfRange` for carbsG
    // outside 1...999. Notifies `eventsDidChange` once.
    func saveIntakeEntry(_ entry: IntakeEntry) async throws

    // Req 7.2. In-place update of the same row id; re-validates the
    // 1...999 range, throwing `intakeCarbsOutOfRange` outside it. The
    // UPDATE is gated on `event_type = intake`, so a meal/insulin/bsl row
    // sharing the id is untouched. Notifies `eventsDidChange` once.
    func updateIntakeEntry(_ entry: IntakeEntry) async throws

    // Req 7.3. Deletes a single intake event by id. The DELETE is gated on
    // `event_type = intake`, so a meal/insulin/bsl row sharing the id
    // survives. Notifies `eventsDidChange` once (delete notifies
    // unconditionally, matching `deleteMeal`).
    func deleteIntakeEntry(id: UUID) async throws

    // specs/data/activity-events Req 1.1, 1.3, 1.5, 1.6. Writes ONE `events`
    // row per activity, following the insulin convention: `value` = duration
    // in minutes and is NULL when `durationMinutes` is nil (unrecorded, never
    // zero), `timestamp` = the activity start in UTC ms, `metadata` = JSON
    // object with `schema_version` (integer 1), `kind` and `provenance`, plus
    // `note` only when provided (key absent — not null — when nil).
    // `character` is NOT written: it is derivable from `kind`, and two sources
    // of truth for the field a later model keys on is the defect this avoids.
    // Notifies `eventsDidChange` once.
    func saveActivity(_ activity: ActivityEvent) async throws

    // Req 3.6. Deletes a single activity event by id. The DELETE is gated on
    // `event_type = activity`, so a meal/insulin/intake/bsl row sharing the id
    // survives, and no side tables are touched. Notifies `eventsDidChange`
    // once (delete notifies unconditionally, matching `deleteMeal`).
    func deleteActivityEvent(id: UUID) async throws

    // Req 5.1, 5.2. The lookback a dosing model asks rather than
    // reimplementing an interval query and a metadata decode. Returns events
    // whose timestamp falls in the HALF-OPEN interval
    // `(instant - interval, instant]` — one exactly at `instant - interval` is
    // excluded, one exactly at `instant` is included — newest first. Rows whose
    // metadata does not decode are DROPPED rather than throwing, matching how
    // TrendsModel already handles insulin rows with unreadable metadata; an
    // empty result is an ordinary answer, not an error.
    // `ActivityEvent.defaultLookback` is the 36-hour window of Decision 3.
    func activities(
        before instant: Date, within interval: TimeInterval
    ) async throws -> [ActivityEvent]

    // specs/ui/records-deletion Req (glucose deletable, superseding
    // home-router Req 3.5). Deletes a single bsl event by id, gated on
    // `event_type = bsl` (insulin/intake convention). A reading deleted
    // inside the live ingestion window may re-ingest on the next poll —
    // accepted (records-deletion Decision 3). Notifies `eventsDidChange`
    // once.
    func deleteBslEvent(id: UUID) async throws

    // specs/ui/records-deletion (bulk + date-range purge, Decision 2). One
    // write transaction deleting the given event rows by id (any event type
    // — the ids come from loaded rows) and the given meals with their full
    // cascade (events row, meal_artefacts, corrections; artefact directories
    // removed best-effort after commit). `IN` lists are chunked under
    // SQLite's bound-variable cap. Notifies `eventsDidChange` ONCE when
    // anything was deleted — never per row.
    func deleteRecords(mealIDs: [UUID], eventIDs: [UUID]) async throws

    // specs/data/manual-carb-intake, design.md "Quick-add presets — new
    // table". Returns every preset ordered `sort_order ASC`. Presets are not
    // `events` rows: none of these three methods touch `eventsDidChange`
    // (nothing outside the Intake surface reads them).
    func quickPresets() async throws -> [QuickPreset]

    // Insert or replace by id (`id` is the table's PRIMARY KEY) — a single
    // method covers both create (Req 4.1) and edit (Req 4.2).
    func saveQuickPreset(_ preset: QuickPreset) async throws

    // Req 4.2. Deletes a single preset by id.
    func deleteQuickPreset(id: UUID) async throws

    // specs/estimation/snaq-parity Req 2.1, 2.3, 2.5. Persists one estimation
    // attempt and applies the split eviction bounds INSIDE the same write
    // transaction as the insert (atomic): non-benchmark rows keep the newest
    // `EstimationOutcome.nonBenchmarkRowBound`; benchmark-tagged rows keep the
    // newest `benchmarkAttemptsPerMealPerLineageBound` per (benchmark_meal_id,
    // model_version) group, with the group's latest completed attempt exempt
    // from eviction (it occupies one of the bound's slots) so a run of
    // refusals can never evict the meal's scoring attempt. "Newest" orders by
    // (timestamp, id) so eviction and latest-attempt scoring stay
    // deterministic under equal timestamps.
    // Outcome rows are not `events` rows: no `eventsDidChange` interaction
    // (quick_presets convention above).
    func saveEstimationOutcome(_ outcome: EstimationOutcome) async throws

    // specs/estimation/ml-feedback-loop Req 3.2. Exempts one outcome id from
    // every eviction branch of `saveEstimationOutcome` for as long as the
    // protection row exists — a field note's subject must outlive the bound
    // it would otherwise fall out of. Idempotent, and valid for an id whose
    // row has not been written yet: protection is keyed on the id alone.
    // Profile-neutral — product builds simply never call it.
    func markOutcomeProtected(id: UUID) async throws

    // The same exemption reached through the meal instead of the attempt. A
    // field note taken on a recorded meal — the review surface, the result
    // screen, a Records row — knows the meal id and not the outcome id; the
    // outcome row is what carries the timestamp that joins a note onward to
    // its capture bundle, so leaving it evictable would strand exactly the
    // notes Req 3.2 exists to keep. Marks every attempt recorded against the
    // meal: the retries around a meal are part of the story the note is about.
    func markOutcomesProtected(mealID: UUID) async throws

    // Retires one protection (ml-feedback-loop Decision 14). The pull's
    // manifest pass calls this once the note that justified the protection
    // has been copied to the Mac and deleted from the phone, so protection
    // does not accumulate for the life of the install after its reason has
    // left. Removing a protection that was never granted is a no-op.
    func unmarkOutcomeProtected(id: UUID) async throws

    // Req 2.2 read path (log browser / export). Returns at most `limit` rows
    // ordered newest first ((timestamp, id) descending).
    func estimationOutcomes(limit: Int) async throws -> [EstimationOutcome]

    // specs/estimation/snaq-parity Req 1.2, 1.3. Insert-or-update by id.
    // `carbsPer100g` resolves a palette class to carbohydrate grams per 100 g
    // at the given food-DB edition; the store invokes it with the meal's
    // `dbEdition`, so the lookup's edition is tied to the `db_edition` the
    // row records. The caller backs it with the same
    // `FoodDatabase.entry(for:)` lookup `Macros.compute` uses; it is injected
    // because Persistence sits below Foods in the dependency graph and stores
    // food data opaquely (EstimationOutcome precedent). The store derives
    // `truthCarbsG` from it at save, ignoring the caller-supplied value.
    // Throws `benchmarkGramsOutOfRange` for any item outside 1...5000,
    // `benchmarkClassUnresolvable` when the lookup returns nil for an item
    // (never a silent 0 g truth), and `benchmarkMealImmutable` when the meal
    // id already has estimation attempts recorded against it. Benchmark meals
    // are not `events` rows: no `eventsDidChange` interaction.
    func saveBenchmarkMeal(
        _ meal: BenchmarkMeal, carbsPer100g: (_ classID: String, _ edition: String) -> Double?
    ) async throws

    // Req 1.3 read path (benchmark report / export). Returns every meal
    // ordered newest first ((created_at, id) descending).
    func benchmarkMeals() async throws -> [BenchmarkMeal]

    // specs/data/insulin-dosing Req 7.1, 7.2, 7.4. Persists one dose
    // suggestion — made or suppressed — as INSERT OR REPLACE by id, so a
    // review-screen correction rewrites the same row rather than appending one
    // per keystroke. `fpu` is DERIVED HERE from `fatG` and `proteinG`
    // (`DoseSuggestionRecord.fatProteinUnits`), ignoring the caller-supplied
    // value, so a later change to the formula cannot silently reinterpret old
    // rows. Suggestion rows are not `events` rows: no `eventsDidChange`
    // interaction (quick_presets / estimation_outcomes convention above), and
    // no key of the insulin event's metadata contract is added, altered or
    // extended (Req 7.3, 9.7). There is no eviction bound — unlike
    // `estimation_outcomes`, the longitudinal series is the product.
    func saveDoseSuggestion(_ row: DoseSuggestionRecord) async throws

    // Req 7.5. Associates a recorded dose with the suggestion it refers to:
    // an UPDATE of `given_units` and `insulin_event_id` on the side table
    // ONLY. The insulin event is not read, rewritten or touched. Does not
    // notify `eventsDidChange`.
    func linkDose(
        suggestionID: UUID, insulinEventID: UUID, givenUnits: Double
    ) async throws

    // Req 7.2 read path (ledger review / export). Returns at most `limit` rows
    // ordered newest first ((timestamp, id) descending).
    func doseSuggestions(limit: Int) async throws -> [DoseSuggestionRecord]

    // Req 6.10 read path: the newest recorded suggestion for one meal or
    // intake, so a history surface can render the row's values verbatim
    // (Req 6.11 — never a recomputation). Nil when the subject has no row.
    func doseSuggestion(forSourceEventID id: UUID) async throws -> DoseSuggestionRecord?

    // specs/data/dose-schedule Req 2.1, 2.2. Opens the occurrence for one
    // scheduled dose at one due instant, returning the row whether it was just
    // created or already existed. Idempotent by construction: a UNIQUE
    // (schedule_id, due_at) index plus INSERT OR IGNORE means two foreground
    // passes — or a foreground racing the notification handler — yield ONE
    // outstanding row, which is what caps outstanding occurrences at one per
    // schedule (Req 2.3). Occurrence rows are not `events` rows: no
    // `eventsDidChange` interaction, so history refreshes exactly once per
    // logged dose rather than twice.
    func openOccurrence(scheduleID: UUID, dueAt: Date) async throws -> DoseOccurrence

    // Req 2.2, 4.3, 4.6. A genuine COMPARE-AND-SET: records the outcome only if
    // the row is still `outstanding`, and returns whether it transitioned. The
    // caller writes the insulin event ONLY when it did — that is the whole of
    // Req 4.6's idempotency, and it is why a stale follow-up notification tapped
    // after the dose was logged elsewhere writes nothing at all.
    //
    // `closedAt` is the moment the dose was LOGGED, never the scheduled time
    // (Req 4.3); `dueAt` minus `closedAt` gives lateness by subtraction with no
    // extra column (Req 4.4). `insulinEventID` and `wasNominal` stay nil for a
    // skip or a miss, which write no insulin event of any amount (Req 6.3).
    // Passing `.outstanding` is rejected with `false` rather than performing a
    // no-op that reports success.
    @discardableResult
    func closeOccurrence(
        id: UUID,
        outcome: OccurrenceOutcome,
        closedAt: Date,
        insulinEventID: UUID?,
        wasNominal: Bool?
    ) async throws -> Bool

    // Req 2.3, 6.2. The write half of the missed-successor rule
    // (`DoseScheduleMath.occurrencesToCloseAsMissed` computes the ids). One
    // transaction; each row carries the same outstanding-only gate, so a row
    // logged or skipped between the lazy read and this write is untouched.
    // Returns how many rows actually transitioned.
    @discardableResult
    func closeOccurrencesAsMissed(ids: [UUID], closedAt: Date) async throws -> Int

    // Req 2.4. Every open occurrence, oldest first. The in-app outstanding
    // surface reads THIS — the ledger is the source of truth and notifications
    // are a view onto it, so the row renders whether or not a notification was
    // ever delivered or seen.
    func outstandingOccurrences() async throws -> [DoseOccurrence]

    // Read path for review and export: at most `limit` rows, newest due first.
    // Carries the `dueAt`/`closedAt` pairs the interval and cutoff are meant to
    // be set from once real use has accumulated (design.md open question 1).
    func doseOccurrences(limit: Int) async throws -> [DoseOccurrence]
}

extension PersistenceStore {
    // Default: no recorded suggestion. Lets stores that never persist
    // suggestions (test doubles) conform without a stub; the real store
    // overrides with the `dose_suggestions` query.
    public func doseSuggestion(forSourceEventID id: UUID) async throws -> DoseSuggestionRecord? {
        nil
    }
}
