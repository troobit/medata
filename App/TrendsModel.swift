import Foundation
import Observation
import Persistence

// Stub registered in task 12. The Trends view-model (range bucketing, axis
// mapping, glucose read) is task 22 (stream 3). It will bind TrendsMath and
// EventType.bsl once those land in MedataCore — do NOT reference them here.
@Observable
@MainActor
final class TrendsModel {
    private let store: any PersistenceStore

    init(store: any PersistenceStore) {
        self.store = store
    }
}
