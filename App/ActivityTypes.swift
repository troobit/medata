import Foundation
import Observation
import Persistence

// Activity value types, exactly the shapes given in
// `specs/data/activity-events/design.md` §1, plus the store surface §2 names.
//
// TEMPORARY LOCATION. `ActivityKind` / `ActivityCharacter` /
// `ActivityProvenance` / `ActivityEvent` belong in
// `MedataCore/Sources/Persistence/` (activity-events task 1) and the three
// store methods on `PersistenceStore` (task 2); neither is on this branch, so
// the UI phase carries them here to stay buildable. Every name matches the
// design document, so landing tasks 1–2 is a file move plus deleting
// `ActivityStore`'s in-memory arm.
//
// `nonisolated` because the project sets SWIFT_DEFAULT_ACTOR_ISOLATION =
// MainActor and these are Sendable value types read from any context.

/// Raw values are the stable machine keys stored in `metadata.kind` (Req 1.4).
nonisolated enum ActivityKind: String, Sendable, Equatable, CaseIterable {
    case swim, waterpolo, cycle, run, walk, gym, other

    /// Req 2.2 / Decision 2. A property of the activity, not of the session,
    /// so it costs nothing at entry time. The switch is exhaustive over
    /// `allCases` so adding a kind without classifying it fails the build.
    var character: ActivityCharacter {
        switch self {
        case .cycle, .run, .swim, .walk: .aerobic
        case .gym: .anaerobic
        case .waterpolo: .mixed
        case .other: .mixed
        }
    }

    var label: String {
        switch self {
        case .swim: "Swim"
        case .waterpolo: "Water polo"
        case .cycle: "Cycle"
        case .run: "Run"
        case .walk: "Walk"
        case .gym: "Gym"
        case .other: "Other"
        }
    }

    /// The chip glyph. A kind is a noun, and a noun with a picture is faster
    /// to hit than a noun alone — this is a label, not a signal beside a
    /// number (design-direction §8 bars glyphs beside the dose figure).
    var symbolName: String {
        switch self {
        case .swim: "figure.pool.swim"
        case .waterpolo: "figure.waterpolo"
        case .cycle: "figure.outdoor.cycle"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .gym: "figure.strengthtraining.traditional"
        case .other: "figure.mixed.cardio"
        }
    }
}

nonisolated enum ActivityCharacter: String, Sendable, Equatable, CaseIterable {
    case aerobic, anaerobic, mixed
}

nonisolated enum ActivityProvenance: String, Sendable, Equatable, CaseIterable {
    case manual, healthkit  // Req 1.6 / Decision 4
}

nonisolated struct ActivityEvent: Sendable, Equatable, Identifiable {
    static let metadataSchemaVersion = 1
    /// Moves to `EventType.activity` with task 1; the string is the contract.
    static let eventType = "activity"

    let id: UUID
    let timestamp: Date  // activity START (Req 6.1)
    let kind: ActivityKind
    let durationMinutes: Double?  // nil == unrecorded, never 0 (Req 1.5)
    let provenance: ActivityProvenance
    let note: String?

    init(
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

    /// End instant where a duration was given; nil renders as a point mark.
    var end: Date? {
        durationMinutes.map { timestamp.addingTimeInterval($0 * 60) }
    }

    /// `character` is NOT written to metadata — it is derivable from `kind`,
    /// and two sources of truth for the regression key is the defect this
    /// avoids (design.md §2).
    var metadataJSON: String {
        var object: [String: Any] = [
            "schema_version": Self.metadataSchemaVersion,
            "kind": kind.rawValue,
            "provenance": provenance.rawValue
        ]
        if let note, !note.isEmpty { object["note"] = note }
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// Rows that fail to decode are dropped, matching how `TrendsModel`
    /// already handles insulin rows with unreadable metadata.
    static func decode(from event: Event) -> ActivityEvent? {
        guard
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = ActivityKind(rawValue: kindRaw)
        else { return nil }
        let provenance = (object["provenance"] as? String)
            .flatMap(ActivityProvenance.init(rawValue:)) ?? .manual
        return ActivityEvent(
            id: event.id,
            timestamp: event.timestamp,
            kind: kind,
            durationMinutes: event.value,
            provenance: provenance,
            note: object["note"] as? String
        )
    }
}

// MARK: - Store surface (design.md §2)

/// The three methods activity-events task 2 puts on `PersistenceStore`, plus
/// the range read the Graph needs. `activities(in:)` needs NO new store
/// method once `EventType.activity` exists — `events(in:type:)` already takes
/// an arbitrary type string, so it is a decode away.
protocol ActivityStoring: AnyObject, Sendable {
    func saveActivity(_ activity: ActivityEvent) async throws
    func deleteActivityEvent(id: UUID) async throws
    /// Req 5.1 — the lookback. Events whose timestamp falls in
    /// `(instant - interval, instant]`, newest first.
    func activities(before instant: Date, within interval: TimeInterval) async throws
        -> [ActivityEvent]
    func activities(in range: ClosedRange<Date>) async throws -> [ActivityEvent]
}

/// The only stub in this branch that touches data.
///
/// Reads and deletes go to the real database: `events(in:type:)` and
/// `deleteRecords(mealIDs:eventIDs:)` both already accept an arbitrary event
/// type / id, so activity rows written by a later build are read and removed
/// here for real. WRITES have nowhere to go — `saveActivity` is
/// activity-events task 2 and is not on this branch — so a saved activity
/// lands in `pending` and is merged into every read for the life of the
/// process.
///
/// DELETE `pending`, the merge in `activities(in:)`, and the append in
/// `saveActivity` when task 2 lands; the four method bodies then forward
/// straight to the store.
@Observable
@MainActor
final class ActivityStore: ActivityStoring {
    private let store: any PersistenceStore
    private var pending: [ActivityEvent] = []
    /// Fires after a write so the Graph and Records reload — the real
    /// `saveActivity` will tick `eventsDidChange` instead and this goes away.
    private(set) var revision = 0

    init(store: any PersistenceStore) {
        self.store = store
    }

    func saveActivity(_ activity: ActivityEvent) async throws {
        pending.removeAll { $0.id == activity.id }
        pending.append(activity)
        revision += 1
    }

    func deleteActivityEvent(id: UUID) async throws {
        pending.removeAll { $0.id == id }
        try? await store.deleteRecords(mealIDs: [], eventIDs: [id])
        revision += 1
    }

    func activities(before instant: Date, within interval: TimeInterval) async throws
        -> [ActivityEvent] {
        let start = instant.addingTimeInterval(-interval)
        return try await activities(in: start...instant)
            .filter { $0.timestamp > start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func activities(in range: ClosedRange<Date>) async throws -> [ActivityEvent] {
        let rows = (try? await store.events(in: range, type: ActivityEvent.eventType)) ?? []
        let stored = rows.compactMap(ActivityEvent.decode(from:))
        let storedIDs = Set(stored.map(\.id))
        let merged = stored + pending.filter {
            range.contains($0.timestamp) && !storedIDs.contains($0.id)
        }
        return merged.sorted { $0.timestamp < $1.timestamp }
    }
}
