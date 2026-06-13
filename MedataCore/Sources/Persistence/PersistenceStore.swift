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
    // (`save`, `deleteMeal`, `updatePhotoAssetID`). Does NOT emit on
    // `appendCorrection` — corrections live in their own side table.
    var eventsDidChange: AsyncStream<Void> { get }
}
