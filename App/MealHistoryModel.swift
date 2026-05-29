import Foundation
import Observation
import Persistence

// @Observable @MainActor data source for the Meals tab (UI Req §19.1, §19.6,
// §19.7). Loads `meals` from the store on `start()`, refreshes on every
// `mealsDidChange` tick, and routes deletes through the store. The tab view
// owns one instance and keeps it alive across tab switches; `cancel()` ends
// the subscription so the model can be torn down deterministically in tests.
@Observable
@MainActor
final class MealHistoryModel {
    var meals: [MealRecord] = []
    private let store: any PersistenceStore
    private var subscription: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    // No deinit: under MainActor-default isolation a deinit cannot touch
    // `subscription`. The subscription Task captures `self` weakly so the
    // model can be dropped, and the AsyncStream tears down its continuation
    // when the model and its iterator deallocate.

    func start() async {
        await reload()
        subscription?.cancel()
        let stream = store.mealsDidChange
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

    func delete(_ record: MealRecord) async {
        do {
            try await store.deleteMeal(id: record.id)
        } catch {
            // Best-effort: a delete failure leaves the row in the store and the
            // next mealsDidChange tick (if any) restores the displayed state.
        }
    }

    private func reload() async {
        if let next = try? await store.allMeals() {
            self.meals = next
        }
    }
}
