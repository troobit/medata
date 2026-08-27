import Foundation
// Leaf value type only — GlucoseWidgetShared is Foundation-only with an empty
// dependency list (glucose-lock-widget Decision 10), so this edge costs the
// estimation link closure nothing.
import GlucoseWidgetShared

// The one place a `GlucoseSnapshot` is derived from stored `bsl` rows.
//
// Extracted from `GlucoseWidgetPublisher` (App) when the home page grew a
// latest-reading header (home-router Req 4): two surfaces deriving "the latest
// reading and its trend" independently is how they drift, and the derivation
// carries two non-obvious rules — the future-skew window bound and the
// 24-hour horizon — that were learned from a field bug and must not be
// re-learned per caller.
//
// The publisher still owns the write/reload side effects and the skew logging;
// only the read-and-derive step lives here.
public enum GlucoseSnapshotSource {

    // The display horizon. Bounded at ~288 rows a day, so no full-history scan
    // and no new store accessor. A reading older than this is beyond any
    // glance-useful horizon and is treated as never-recorded.
    public static let displayHorizon: TimeInterval = 24 * 60 * 60

    // The window's UPPER bound, and not cosmetic. It was `now`, which silently
    // dropped any reading timestamped ahead of the device clock — and CGM rows
    // routinely are, which is why `GlucoseTimeline.render` clamps a future
    // reading's age to zero ("clock skew, not a prediction"). With the bound at
    // `now` the render layer's skew handling was unreachable and the widget sat
    // one reading behind for as long as the skew lasted.
    //
    // Bounded rather than open-ended: a future reading renders as fresh, so an
    // unbounded window would let one corrupt far-future row pin the display to
    // a wrong value indefinitely. An hour absorbs real clock and
    // timezone-rounding skew while capping that blast radius.
    public static let futureSkewAllowance: TimeInterval = 60 * 60

    // The last 24 hours of `bsl` rows condensed into a snapshot. A throw
    // (corrupt row) degrades to never-recorded rather than propagating —
    // both callers render a display, neither has an error surface.
    //
    // `holdWindow` is not defaulted, for the reason `GlucoseDerivation.snapshot`
    // states: hold semantics must be asked for, never acquired by accident.
    // Both app-side callers read the same setting, which is what makes Req 3.7
    // hold — home and the published snapshot resolve the same reading.
    public static func current(
        store: any PersistenceStore, now: Date, holdWindow: TimeInterval
    ) async -> GlucoseSnapshot {
        let oldest = now.addingTimeInterval(-displayHorizon)
        let newest = now.addingTimeInterval(futureSkewAllowance)
        let events = (try? await store.events(in: oldest...newest, type: EventType.bsl)) ?? []
        return snapshot(from: events.compactMap(reading(from:)), now: now, holdWindow: holdWindow)
    }

    // One `bsl` row as a reading, or nil when the row carries no value.
    //
    // Public and here rather than private to each consumer because THREE
    // surfaces read provenance off these rows — this snapshot derivation, the
    // Graph's trace/marker split, and the Records row label — and a second
    // spelling of the fallback rule is how one of them starts calling a blood
    // reading a sensor one.
    public static func reading(from event: Event) -> GlucoseReading? {
        event.value.map {
            GlucoseReading(
                timestamp: event.timestamp, mmolL: $0, provenance: provenance(of: event))
        }
    }

    // The stored form of provenance, and the whole of Req 7.1: an ABSENT
    // `metadata.provenance` key is a sensor reading, so every row recorded
    // before this feature reads back correctly with nothing rewritten and no
    // migration. An unrecognised value falls the same way, which is the
    // fail-safe direction — a reading mistaken for blood would earn a hold it
    // has not measured.
    public static func provenance(of event: Event) -> GlucoseProvenance {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(event.metadata.utf8))
                as? [String: Any],
            let raw = object["provenance"] as? String,
            let provenance = GlucoseProvenance(rawValue: raw)
        else { return .sensor }
        return provenance
    }

    // The pure half moved to `GlucoseDerivation` (GlucoseWidgetShared) when the
    // widget started deriving its own snapshot from a vendor fetch
    // (glucose-lock-widget Decision 16) — same argument as the extraction from
    // the publisher, one rung further out: two surfaces deriving "the latest
    // reading and its trend" independently is how they drift. This forward
    // keeps `import Persistence` enough for app-side callers.
    public static func snapshot(
        from readings: [GlucoseReading], now: Date, holdWindow: TimeInterval
    ) -> GlucoseSnapshot {
        GlucoseDerivation.snapshot(from: readings, now: now, holdWindow: holdWindow)
    }
}
