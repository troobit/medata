import Foundation
import PortableContracts

public enum PersistenceError: Error, Equatable {
    case corruptRecord(String)
    case mealNotFound(UUID)
    case archiveFailed(String)
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
    // stored at least one row). Does NOT emit on `appendCorrection` —
    // corrections live in their own side table.
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
}
