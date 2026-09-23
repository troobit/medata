import Foundation

// Activity events (specs/data/activity-events, Req 1 and 2). Follows the same
// `events` row convention as InsulinDose and IntakeEntry (see
// docs/agent-notes/persistence.md "Insulin events"): `value` = duration in
// minutes and is ABSENT when no duration was given, `timestamp` = the activity
// START, `metadata` = a JSON object with `schema_version`, `kind`,
// `provenance`, plus `note` only when provided — the key is absent, never null,
// when nil.

// The shipped activity kinds (Req 2.1, 2.3). Raw values are the stable machine
// keys written to `metadata.kind` (Req 1.4) — renaming a case would orphan
// every row already recorded under the old key.
public enum ActivityKind: String, Sendable, Equatable, CaseIterable {
    case swim
    case waterpolo
    case cycle
    case run
    case walk
    case gym
    case other

    // Req 2.2 / Decision 2. A fixed property of the KIND, not of the session,
    // so it costs nothing at entry time and is DERIVED rather than stored:
    // storing it would let a row disagree with the enum after an edit, and the
    // enum is the thing a later regression joins on.
    //
    // The switch is exhaustive over the cases with no `default`, so adding a
    // kind without classifying it fails the build rather than silently
    // defaulting (Req 2.3).
    //
    // `swim` is aerobic and `waterpolo` mixed deliberately: lap swimming is
    // sustained, waterpolo is intermittent sprint work with a contact load.
    // Decision 1 records that the anaerobic character may not reduce insulin
    // requirement at all, which is precisely why the two are not collapsed.
    public var character: ActivityCharacter {
        switch self {
        case .cycle, .run, .swim, .walk: .aerobic
        case .gym: .anaerobic
        case .waterpolo: .mixed
        case .other: .mixed
        }
    }
}

// Cardiovascular character of an activity kind (Req 2.2). Never stored — see
// `ActivityKind.character`.
public enum ActivityCharacter: String, Sendable, Equatable, CaseIterable {
    case aerobic
    case anaerobic
    case mixed
}

// Where the activity record came from (Req 1.6 / Decision 4). `healthkit`
// exists in the vocabulary now so a later HealthKit import needs no metadata
// migration; nothing writes it in this spec.
public enum ActivityProvenance: String, Sendable, Equatable, CaseIterable {
    case manual
    case healthkit
}

// One activity bound for the event log. `timestamp` is the activity START
// (Req 6.1). `durationMinutes` is optional and `nil` means UNRECORDED — never
// zero (Req 1.5); a zero-minute activity and an activity of unstated length are
// different facts. `note` is optional free text — omitted from metadata
// entirely when nil, matching `InsulinDose`.
public struct ActivityEvent: Sendable, Equatable {
    // Version of the activity metadata convention (`metadata.schema_version`).
    public static let metadataSchemaVersion = 1

    // Req 5.2 / Decision 3. The lookback a dosing model uses by default,
    // spanning an evening activity through to the following morning's dose.
    // Exposed as a named constant rather than a defaulted parameter so every
    // call site's window stays visible in the code that uses it.
    public static let defaultLookback: TimeInterval = 36 * 60 * 60

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
}
