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
    public static func current(store: any PersistenceStore, now: Date) async -> GlucoseSnapshot {
        let oldest = now.addingTimeInterval(-displayHorizon)
        let newest = now.addingTimeInterval(futureSkewAllowance)
        let events = (try? await store.events(in: oldest...newest, type: EventType.bsl)) ?? []
        let readings = events.compactMap { event in
            event.value.map { GlucoseReading(timestamp: event.timestamp, mmolL: $0) }
        }
        // Zero window until the provenance decode and the app-side setting land
        // (specs/data/fingerprick-glucose tasks 12 and 13): with every reading
        // still reading back as `.sensor`, a window of any size would resolve
        // the same reading anyway.
        return snapshot(from: readings, now: now, holdWindow: 0)
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
