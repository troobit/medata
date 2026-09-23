import Foundation
import GlucoseWidgetShared
import Observation
import Persistence

// @Observable @MainActor data source for the home page's latest-reading header
// (home-router Req 4). Holds one `GlucoseSnapshot` — the same value the lock
// screen widget renders — refreshed on every `eventsDidChange` tick, the
// mechanism RecordsModel/MealHistoryModel/TrendsModel already use.
//
// It reads the STORE, not `GlucoseSnapshotStore` (the App Group defaults the
// widget reads): the header must be correct on a build whose App Group is not
// yet provisioned, and the app already has the rows to hand. `GlucoseSnapshotSource`
// keeps the derivation identical to the publisher's, so home and widget can
// never disagree about the latest reading (Decision 15).
@Observable
@MainActor
final class HomeGlucoseModel {
    private(set) var snapshot: GlucoseSnapshot = .neverRecorded

    private let store: any PersistenceStore
    private var subscription: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    // No deinit: under MainActor-default isolation a deinit cannot touch
    // `subscription`. The subscription Task captures `self` weakly (RecordsModel
    // pattern).

    func start() async {
        await reload()
        subscription?.cancel()
        let stream = store.eventsDidChange
        subscription = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    func reload() async {
        // The hold window is read per reload, not cached: changing it in
        // Settings takes effect on the next `eventsDidChange` tick without a
        // relaunch (Req 3.2). `GlucoseWidgetPublisher` reads the same value, so
        // home and the widget resolve the same reading (Req 3.7).
        snapshot = await GlucoseSnapshotSource.current(
            store: store, now: Date(), holdWindow: GlucoseHoldWindow.seconds())
    }
}
