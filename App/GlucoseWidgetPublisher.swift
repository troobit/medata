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
    // The display-horizon read and the snapshot derivation moved to
    // `GlucoseSnapshotSource` (Persistence) when the home page grew a
    // latest-reading header (home-router Req 4) — the horizon and the
    // future-skew window bound are stated there. This actor keeps the
    // write/reload side effects and the skew logging.

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
        // `.notice` throughout for anything a device pull needs to see: `.info`
        // stays in memory and `log collect` never gets it
        // (docs/agent-notes/device-build-and-test.md).
        log.notice("event=publisher.start")
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
    // stored one (Req 1.3) AND carries a strictly newer reading (Req 1.8,
    // enforced in the store so the widget's own writes obey it too). An
    // unchanged recompute — the common case for a tick from an insulin or
    // intake write — costs one read and nothing else.
    // The deletion route (fingerprick-glucose Req 6.2). Recomputing after a
    // delete yields a snapshot carrying an OLDER `readingDate` than the stored
    // one — the reading that would have shown had the deleted one never been
    // recorded — and every case of the monotonic guard rejects it, so without
    // this the widget goes on rendering a reading that no longer exists.
    //
    // `removed` is what narrows the rollback: the store admits it only when the
    // stored snapshot's own `readingDate` is among these instants, so a
    // rollback can discard only a reading the app has just destroyed and a
    // newer extension fetch the app never saw is left alone.
    //
    // The `eventsDidChange` tick the delete also fires cannot do this job: it
    // knows a row went away but not which one. Both converge whichever order
    // the actor runs them in — one writes, the other then finds nothing to
    // change.
    func publishRemoval(of removed: [Date]) async {
        await publishIfChanged(trigger: "delete", replacingDeleted: removed)
    }

    private func publishIfChanged(trigger: String, replacingDeleted removed: [Date] = []) async {
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
        // Differing is not the same as newer. The widget publishes its own
        // fetches while this process is suspended (Decision 16), so a recompute
        // from a database that has not ingested them yet is a REGRESSION, not
        // an update — the store drops it (Req 1.8, Decision 19) and there is
        // nothing to reload. Seen in the field at both prime and tick.
        guard GlucoseSnapshotStore.write(snapshot, replacingDeleted: removed) else {
            log.notice("""
                event=publish.dropped trigger=\(trigger, privacy: .public) \
                reason=notNewer \
                was=\(Self.stamp(stored.readingDate), privacy: .public) \
                now=\(Self.stamp(snapshot.readingDate), privacy: .public)
                """)
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: GlucoseSnapshotStore.widgetKind)
        // `reloadTimelines` is a REQUEST, not a refresh: WidgetKit spends it
        // from a daily budget and may defer it by many minutes. So this line
        // means "asked", never "shown" — a widget lagging behind these
        // timestamps is the system throttling, not a missed write.
        log.notice("""
            event=publish.reloadRequested trigger=\(trigger, privacy: .public) \
            was=\(Self.stamp(stored.readingDate), privacy: .public) \
            now=\(Self.stamp(snapshot.readingDate), privacy: .public) \
            lagSeconds=\(Int(now.timeIntervalSince(snapshot.readingDate ?? now)), privacy: .public)
            """)
    }

    private static func stamp(_ date: Date?) -> String {
        date.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
    }

    // The last 24 hours of `bsl` rows condensed into the snapshot, shared with
    // the home page's latest-reading header via `GlucoseSnapshotSource`.
    private func currentSnapshot(now: Date) async -> GlucoseSnapshot {
        // Same reader as `HomeGlucoseModel`, so the published snapshot and the
        // home header can never resolve different readings (Req 3.7). The
        // window stays app-private: what crosses to the extension is the
        // resolved absolute `holdsUntil` on the snapshot (Decision 8).
        let snapshot = await GlucoseSnapshotSource.current(
            store: store, now: now, holdWindow: GlucoseHoldWindow.seconds())
        // Confirms or refutes the skew diagnosis from the field: if this fires,
        // the old `...now` window bound was hiding this row from the widget.
        if let readingDate = snapshot.readingDate, readingDate > now {
            log.notice("""
                event=publish.futureReading \
                skewSeconds=\(Int(readingDate.timeIntervalSince(now)), privacy: .public)
                """)
        }
        return snapshot
    }
}
