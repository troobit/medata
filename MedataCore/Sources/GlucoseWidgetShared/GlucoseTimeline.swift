import Foundation

// The render state at one instant (Reqs 5.1-5.3, 8.1). Each case carries exactly
// what its state is allowed to show, so a stale reading structurally cannot
// carry a status token or an arrow (Req 4.4) and a >30-minute reading
// structurally cannot carry a number.
//
// `provenance` rides on the two value-carrying cases and on neither of the
// others, for the same structural reason (fingerprick-glucose Req 3.5): the
// requirement binds surfaces REPORTING a current value, and past thirty minutes
// there is no value left to qualify.
public enum GlucoseRender: Equatable, Sendable {
    case fresh(
        value: String, status: GlucoseBandStatus, trend: GlucoseTrend?,
        provenance: GlucoseProvenance)
    case stale(value: String, age: String, provenance: GlucoseProvenance)
    case lastReading(age: String)
    case neverRecorded
}

// The staleness ladder as a pure function of (snapshot, reference date), so
// every transition is unit-tested rather than asserted against the opaque
// WidgetKit scheduler (Decision 9).
//
// Foundation types only, deliberately: `renderPoints` returns dated render
// states and `nextBoundary` returns a `Date?` rather than WidgetKit's
// `TimelineEntry` / `TimelineReloadPolicy`. The extension owns that mapping
// (Decision 12) — importing WidgetKit here would drag a UI framework through
// Persistence into Pipeline and the macOS HarnessCLI.
public enum GlucoseTimeline {

    // The reading is fresh up to and including this age, stale up to and
    // including `lastReadingAge` (Reqs 5.1, 5.2).
    public static let staleAge: TimeInterval = 15 * 60
    public static let lastReadingAge: TimeInterval = 30 * 60

    // Both bands are inclusive, so the first instant at which the ladder has
    // actually advanced is one second past the boundary. An entry placed ON the
    // boundary would render the OLD state and freeze the ladder a step behind
    // for its whole life (Decision 13).
    public static let transitionOffset: TimeInterval = 1

    // A snapshot missing any of value, timestamp, or status is the
    // never-recorded state — `GlucoseSnapshot.make` is the only construction
    // path and always supplies all three together. One accessor so the ladder
    // and the render can never disagree about which snapshots carry a reading.
    private static func reading(
        _ snapshot: GlucoseSnapshot
    ) -> (mmolL: Double, date: Date, status: GlucoseBandStatus)? {
        guard
            let mmolL = snapshot.mmolL,
            let readingDate = snapshot.readingDate,
            let status = snapshot.status
        else { return nil }
        return (mmolL, readingDate, status)
    }

    // The state at `date`.
    public static func render(_ snapshot: GlucoseSnapshot, at date: Date) -> GlucoseRender {
        guard let (mmolL, readingDate, status) = reading(snapshot) else { return .neverRecorded }

        // A reading timestamped in the future is clock skew, not a prediction
        // (Req 5.5).
        let age = max(0, date.timeIntervalSince(readingDate))
        let value = String(format: "%.1f", mmolL)
        // Absent means sensor, exactly as it does in the stored row (Req 7.1) —
        // a v2 snapshot written before a blood reading ever existed, and every
        // sensor derivation, leave the field nil.
        //
        // `holdsUntil` is deliberately NOT consulted here. The ladder measures a
        // reading's age from its own instant (Req 3.6), so a held reading ages
        // normally and reaches the fresh/stale boundary at 15 minutes whether it
        // is holding the display or not.
        let provenance = snapshot.provenance ?? .sensor

        if age <= staleAge {
            return .fresh(
                value: value, status: status, trend: snapshot.trend, provenance: provenance)
        }
        if age <= lastReadingAge {
            return .stale(value: value, age: ageString(age), provenance: provenance)
        }
        return .lastReading(age: ageString(age))
    }

    // The render states to pre-bake from `reference` onwards: the reference
    // itself plus each ladder transition still ahead of it. The boundaries are
    // ages of the READING, not of `reference`, so a snapshot that is already
    // stale when the timeline is built simply has fewer points — and a
    // >30-minute or never-recorded reading has exactly one, its state being
    // terminal.
    public static func renderPoints(
        _ snapshot: GlucoseSnapshot, from reference: Date
    ) -> [(date: Date, render: GlucoseRender)] {
        let dates = [reference] + transitions(snapshot).filter { $0 > reference }
        return dates.map { (date: $0, render: render(snapshot, at: $0)) }
    }

    // When the ladder next advances, or nil once it cannot advance again — the
    // widget maps nil to `.never` and a date to `.after(_)`. Nil in the
    // last-reading and never-recorded states: an `.after` in the past would
    // trigger a pointless reload-asap, and the "Xh ago" label need not tick
    // between data writes.
    public static func nextBoundary(_ snapshot: GlucoseSnapshot, after reference: Date) -> Date? {
        transitions(snapshot).first { $0 > reference }
    }

    // The two ladder transitions, ascending; empty for a never-recorded
    // snapshot, whose state never changes.
    private static func transitions(_ snapshot: GlucoseSnapshot) -> [Date] {
        guard let readingDate = reading(snapshot)?.date else { return [] }
        return [staleAge, lastReadingAge].map {
            readingDate.addingTimeInterval($0 + transitionOffset)
        }
    }

    // Whole minutes for the first hour, whole hours beyond (Req 5.5).
    static func ageString(_ age: TimeInterval) -> String {
        let seconds = max(0, age)
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }
}
