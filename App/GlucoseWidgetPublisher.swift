import Foundation
import GlucoseWidgetShared
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
        await publishIfChanged()
        for await _ in changes {
            await publishIfChanged()
        }
    }

    // Writes and reloads ONLY when the recomputed snapshot differs from the
    // stored one (Req 1.3). An unchanged recompute — the common case for a
    // tick from an insulin or intake write — costs one read and nothing else.
    private func publishIfChanged() async {
        let snapshot = await currentSnapshot(now: Date())
        guard snapshot != GlucoseSnapshotStore.read() else { return }
        GlucoseSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: GlucoseSnapshotStore.widgetKind)
    }

    // The last 24 hours of `bsl` rows condensed into the snapshot: the newest
    // row is the reading, the trailing 15 minutes drive the trend. A throw
    // (corrupt row) degrades to never-recorded rather than crashing the app.
    private func currentSnapshot(now: Date) async -> GlucoseSnapshot {
        let window = now.addingTimeInterval(-Self.displayHorizon)...now
        let events = (try? await store.events(in: window, type: EventType.bsl)) ?? []
        let readings = events.compactMap { event in
            event.value.map { GlucoseReading(timestamp: event.timestamp, mmolL: $0) }
        }
        // `events(in:type:)` is ordered `(timestamp ASC, id ASC)`, so the last
        // row is the most recent one.
        guard let latest = readings.last else { return .neverRecorded }
        return GlucoseSnapshot.make(
            mmolL: latest.mmolL,
            readingDate: latest.timestamp,
            trend: TrendsMath.trend(readings, now: now),
            status: TrendsMath.bandStatus(latest.mmolL)
        )
    }
}
