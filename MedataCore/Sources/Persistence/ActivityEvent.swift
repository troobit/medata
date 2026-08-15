import Foundation

// Activity as a fifth event type in the existing `events` table
// (specs/data/activity-events design §1). Shape mirrors `InsulinDose`
// exactly — a typed value struct here, a metadata JSON payload built by the
// store, `value` carrying the one continuous quantity of the event.

// Raw values are the stable machine keys stored in `metadata.kind`
// (Req 1.4), never the display label, so renaming a label never orphans a
// historical row.
public enum ActivityKind: String, Sendable, Equatable, CaseIterable {
    case swim, waterpolo, cycle, run, walk, gym, other

    // Req 2.2 / Decision 2. A property of the KIND, not of the session, so it
    // costs nothing at entry time and a row can never disagree with the enum
    // after an edit — the enum is what a later regression joins on. Written
    // exhaustively so adding a case without classifying it fails the build.
    public var character: ActivityCharacter {
        switch self {
        case .cycle, .run, .swim, .walk: .aerobic
        case .gym: .anaerobic
        case .waterpolo: .mixed
        case .other: .mixed
        }
    }
}

// Cardiovascular character (Req 2.2). Lap swimming is sustained so `swim` is
// aerobic; waterpolo is intermittent sprint work with a contact load, so it
// is `mixed` and the two are deliberately not collapsed.
public enum ActivityCharacter: String, Sendable, Equatable, CaseIterable {
    case aerobic, anaerobic, mixed
}

// Req 1.6 / Decision 4. Seeded `manual` for everything this spec writes so a
// later HealthKit source is distinguishable without a migration.
public enum ActivityProvenance: String, Sendable, Equatable, CaseIterable {
    case manual, healthkit
}

// One activity bound for the event log. `timestamp` is the activity START
// (Req 6.1); `durationMinutes` is nil when unrecorded and is NEVER stored as
// zero (Req 1.5), so an unrecorded duration can never be read back as an
// instantaneous activity.
public struct ActivityEvent: Sendable, Equatable, Identifiable {
    // Version of the activity metadata convention (`metadata.schema_version`).
    public static let metadataSchemaVersion = 1

    public let id: UUID
    public let timestamp: Date
    public let kind: ActivityKind
    public let durationMinutes: Double?
    public let provenance: ActivityProvenance
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: ActivityKind,
        durationMinutes: Double? = nil,
        provenance: ActivityProvenance = .manual,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.durationMinutes = durationMinutes
        self.provenance = provenance
        self.note = note
    }

    // `character` is derived, never stored (design §2): writing it would give
    // the field a later model keys on two sources of truth.
    public var character: ActivityCharacter { kind.character }
}
