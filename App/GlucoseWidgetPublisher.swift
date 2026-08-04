import Foundation
import GlucoseWidgetShared
import OSLog
import Persistence
import WidgetKit

// The app→widget bridge (glucose-lock-widget Reqs 1.2-1.4, 6.1; Decision 11).
//
// An `actor`, deliberately NOT `@MainActor`: the 24-hour `bsl` read runs on
// every CGM tick (~288 a day) and must not hop to the main thread. The actor
// also serialises the read-compare-write-reload sequence, so two ticks
// arriving together cannot interleave into a reload for a snapshot that was
// never written.
//
// The init ordering is **subscribe → prime → consume**, and the order matters:
//
//   1. `store.eventsDidChange` is bound to a stored property SYNCHRONOUSLY in
//      `init`. The property is `changeBroadcaster.subscribe()`, so simply
//      reading it registers the continuation — no `await`, and therefore the
//      only step that can be ordered against `App.swift`'s synchronous init.
//      `AsyncStream` has no replay, so a tick emitted before the subscription
//      exists is lost outright; this is what makes "subscribed before the
//      glucose sources start" a guarantee rather than a hope.
//   2. The prime recompute+write happens inside the spawned `Task`. An actor
//      init cannot `await` and `store.events(in:type:)` is `async throws`, so
//      it necessarily runs there — after step 1. It exists so a user with
//      existing `bsl` history sees their reading immediately instead of the
//      never-recorded placeholder until the next event.
//   3. Only then does the loop consume the stream captured in step 1. Any tick
//      landing DURING the prime read is buffered by the stream rather than
//      dropped — which is precisely why priming must not precede subscribing.
//
// The `Task` is unstructured and never cancelled: it retains the publisher and
// runs for the process lifetime, which is the intent (`App.swift` also holds
// it). Reloads are scoped to the glucose kind so glucose writes never spend
// the shared WidgetKit reload budget on the co-hosted static launcher widgets.
actor GlucoseWidgetPublisher {
    // The display horizon (design: "Display-horizon read"). Bounded at ≤288
    // rows a day, so no full-history scan and no new store accessor. A reading
    // older than this is beyond any glance-useful horizon and is treated as
    // never-recorded.
    private static let displayHorizon: TimeInterval = 24 * 60 * 60

    // The window's UPPER bound, and not cosmetic. It was `now`, which silently
    // dropped any reading timestamped ahead of the device clock — and CGM rows
    // routinely are, which is precisely why `GlucoseTimeline.render` clamps a
    // future reading's age to zero ("clock skew, not a prediction", Req 5.5).
    // With the bound at `now` the render layer's skew handling was unreachable
    // and the widget sat one reading behind for as long as the skew lasted,
    // while the Trends screen — which queries to the end of the calendar day —
    // showed the row perfectly well.
    //
    // Bounded rather than open-ended: a future reading renders as fresh, so an
    // unbounded window would let one corrupt far-future row pin the widget to a
    // wrong value indefinitely. An hour absorbs real clock and timezone-rounding
    // skew while capping that blast radius.
    private static let futureSkewAllowance: TimeInterval = 60 * 60

    // Every interpolation is `.public`: os_log redacts non-literals by default,
    // which would render the timestamps here as `<private>` — useless for the
    // one question these lines exist to answer (did a reload get requested for
    // this reading, and when).
    private let log = Logger(subsystem: "ie.medata.app", category: "GlucoseWidget")

    private let store: any PersistenceStore
    private let changes: AsyncStream<Void>

    init(store: any PersistenceStore) {
        self.store = store
        // Step 1 — subscribe. Must happen here, synchronously, before anything
        // that can write a `bsl` row is started.
        self.changes = store.eventsDidChange
        // Steps 2 and 3.
        Task { [self] in await self.run() }
    }

    private func run() async {
        log.info("event=publisher.start")
        await publishIfChanged(trigger: "prime")
        for await _ in changes {
            await publishIfChanged(trigger: "tick")
        }
        // Reached only if the store's broadcaster finishes the stream. If this
        // ever logs, the widget has silently stopped updating for the rest of
        // the process lifetime.
        log.error("event=publisher.streamEnded")
    }

    // Writes and reloads ONLY when the recomputed snapshot differs from the
    // stored one (Req 1.3). An unchanged recompute — the common case for a
    // tick from an insulin or intake write — costs one read and nothing else.
    private func publishIfChanged(trigger: String) async {
        let now = Date()
        let snapshot = await currentSnapshot(now: now)
        let stored = GlucoseSnapshotStore.read()
        guard snapshot != stored else {
            log.debug("""
                event=publish.skipped trigger=\(trigger, privacy: .public) \
                reason=unchanged reading=\(Self.stamp(snapshot.readingDate), privacy: .public)
                """)
            return
        }
        GlucoseSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: GlucoseSnapshotStore.widgetKind)
        // `reloadTimelines` is a REQUEST, not a refresh: WidgetKit spends it
        // from a daily budget and may defer it by many minutes. So this line
        // means "asked", never "shown" — a widget lagging behind these
        // timestamps is the system throttling, not a missed write.
        log.info("""
            event=publish.reloadRequested trigger=\(trigger, privacy: .public) \
            was=\(Self.stamp(stored.readingDate), privacy: .public) \
            now=\(Self.stamp(snapshot.readingDate), privacy: .public) \
            lagSeconds=\(Int(now.timeIntervalSince(snapshot.readingDate ?? now)), privacy: .public)
            """)
    }

    private static func stamp(_ date: Date?) -> String {
        date.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
    }

    // The last 24 hours of `bsl` rows condensed into the snapshot: the newest
    // row is the reading, the trailing 15 minutes drive the trend. A throw
    // (corrupt row) degrades to never-recorded rather than crashing the app.
    private func currentSnapshot(now: Date) async -> GlucoseSnapshot {
        let oldest = now.addingTimeInterval(-Self.displayHorizon)
        let newest = now.addingTimeInterval(Self.futureSkewAllowance)
        let events = (try? await store.events(in: oldest...newest, type: EventType.bsl)) ?? []
        let readings = events.compactMap { event in
            event.value.map { GlucoseReading(timestamp: event.timestamp, mmolL: $0) }
        }
        // `events(in:type:)` is ordered `(timestamp ASC, id ASC)`, so the last
        // row is the most recent one.
        guard let latest = readings.last else { return .neverRecorded }
        // Confirms or refutes the skew diagnosis from the field: if this fires,
        // the old `...now` bound was hiding this row from the widget.
        if latest.timestamp > now {
            log.info("""
                event=publish.futureReading \
                skewSeconds=\(Int(latest.timestamp.timeIntervalSince(now)), privacy: .public)
                """)
        }
        return GlucoseSnapshot.make(
            mmolL: latest.mmolL,
            readingDate: latest.timestamp,
            trend: TrendsMath.trend(readings, now: now),
            status: TrendsMath.bandStatus(latest.mmolL)
        )
    }
}
