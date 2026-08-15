import Foundation

// Activity as a fifth event type (specs/data/activity-events design §1).
// Shapes are lifted verbatim from that design so the row a later HealthKit
// source writes needs no migration (Req 6.1).
//
// STUB NOTE: activity-events tasks 1–2 own these types and the store surface.
// They were not merged when the entry/display tasks (4–7) were built, so the
// value types and the three store methods land here to keep the app buildable.
// If task 1/2 arrives separately, that version is authoritative.

// Raw values are the stable machine keys stored in metadata.kind (Req 1.4),
// never the display label — renaming a label must not orphan history.
public enum ActivityKind: String, Sendable, Equatable, CaseIterable {
    case swim, waterpolo, cycle, run, walk, gym, other

    // Req 2.2 / Decision 2. A property of the KIND, not of the session, so it
    // costs nothing at entry time and a regression can pool sparse kinds
    // without collapsing them. Exhaustive by construction: adding a case
    // without classifying it fails the build.
    public var character: ActivityCharacter {
        switch self {
        case .cycle, .run, .swim, .walk: .aerobic
        case .gym: .anaerobic
        case .waterpolo: .mixed
        case .other: .mixed
        }
    }
}

public enum ActivityCharacter: String, Sendable, Equatable, CaseIterable {
    case aerobic, anaerobic, mixed
}

public enum ActivityProvenance: String, Sendable, Equatable, CaseIterable {
    case manual, healthkit  // Req 1.6 / Decision 4
}

// One activity bound for the event log. `timestamp` is the activity START
// (Req 6.1, so an HKWorkout maps directly); `durationMinutes` is nil when
// unrecorded and is NEVER written as 0 (Req 1.5); `note` is omitted from the
// metadata JSON entirely when nil, exactly as InsulinDose does (Req 1.3).
public struct ActivityEvent: Sendable, Equatable, Identifiable {
    // Version of the activity metadata convention (`metadata.schema_version`).
    public static let metadataSchemaVersion = 1
    // Req 5.2 / Decision 3 — spans an evening activity through to the
    // following morning's dose. The lookback query takes its window as a
    // required parameter; this is the value call sites pass.
    public static let defaultLookback: TimeInterval = 36 * 3600

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

    // `character` is derived, never stored (design §2): storing it would let a
    // row disagree with the enum after an edit, and the enum is the thing a
    // regression joins on.
    public var character: ActivityCharacter { kind.character }
}
