import Foundation
import Observation
import Persistence
import Photos
import PortableContracts
import UIKit

// One row's worth of display data for the Data screen (design-handoff-00 §8,
// critic R2). `reload()` composes each meal with its corrections so that a
// landed correction actually invalidates the SwiftUI row: a value-identical
// `MealRecord` refetch alone would diff as unchanged, so the corrected total and
// the corrected flag are folded into this struct (which IS `Equatable`).
struct DisplayMeal: Identifiable, Equatable {
    let record: MealRecord
    // True when any correction row exists for the meal (Req 7.3 marker).
    let isCorrected: Bool
    // The most-recent correction's total override, or nil when no correction set
    // a total — callers fall back to the original estimate.
    let correctedTotalCarbsG: Float?

    var id: UUID { record.id }

    // Total to show in the row: the corrected override when present, otherwise
    // the pipeline's original estimate.
    var displayTotalCarbsG: Float {
        correctedTotalCarbsG ?? record.macros.totalCarbsG
    }
}

// @Observable @MainActor data source for the Data screen (design-handoff-00 §8).
// Loads meals from the store on `start()`, composes each with its corrections,
// refreshes on every `eventsDidChange` tick (which now fires on
// `appendCorrection` too — Decision 18), and routes deletes through the store.
@Observable
@MainActor
final class MealHistoryModel {
    var displayMeals: [DisplayMeal] = []
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

    func delete(_ record: MealRecord) async {
        do {
            try await store.deleteMeal(id: record.id)
        } catch {
            // Best-effort: a delete failure leaves the row in the store and the
            // next eventsDidChange tick (if any) restores the displayed state.
        }
    }

    private func reload() async {
        guard let records = try? await store.allMeals() else { return }
        var composed: [DisplayMeal] = []
        composed.reserveCapacity(records.count)
        for record in records {
            let corrections = (try? await store.corrections(for: record.id)) ?? []
            // Corrections are ordered created_at ASC, so the last one that set a
            // total override is the current corrected total.
            let correctedTotal = corrections
                .last { $0.correctedTotalCarbsGOneof != nil }?
                .correctedTotalCarbsG
            composed.append(
                DisplayMeal(
                    record: record,
                    isCorrected: !corrections.isEmpty,
                    correctedTotalCarbsG: correctedTotal
                )
            )
        }
        self.displayMeals = composed
    }
}

// Shared PHAsset → UIImage loader (extracted from ResultView so the Data,
// Meal-overview, and Result surfaces resolve the captured photo identically —
// design-handoff-00 §6.8 fallback). `nonisolated` so callers on any actor can
// await it; the Photos callback resumes a single checked continuation.
//
// `.highQualityFormat` delivers exactly one callback: `.opportunistic` would
// invoke the handler twice (a fast degraded image then the full one), which
// crashes a checked continuation with "resumed more than once".
enum MealPhotoLoader {
    nonisolated static func loadImage(
        assetID: String,
        targetSize: CGSize = PHImageManagerMaximumSize
    ) async -> UIImage? {
        guard !assetID.isEmpty else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}
