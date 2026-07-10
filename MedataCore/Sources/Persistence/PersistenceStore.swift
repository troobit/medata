import Foundation
import PortableContracts

public enum PersistenceError: Error, Equatable {
    case corruptRecord(String)
    case mealNotFound(UUID)
    case archiveFailed(String)
    // Insulin dose rejected at the store layer: units outside 0...60
    // (PRD regression-suggestion-integration Core 4).
    case insulinUnitsOutOfRange(Double)
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
}

// Whether a dose is fast-acting meal/correction insulin or background
// insulin. Raw values are the exact `metadata.kind` strings in the medreg
// convention.
public enum InsulinKind: String, Sendable, Equatable, CaseIterable {
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

    public init(
        id: UUID = UUID(),
        name: String,
        carbsG: Double,
        macros: IntakeMacros = IntakeMacros(),
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.carbsG = carbsG
        self.macros = macros
        self.sortOrder = sortOrder
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
}
