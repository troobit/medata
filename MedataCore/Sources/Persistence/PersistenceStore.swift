import Foundation
import PortableContracts

public enum PersistenceError: Error, Equatable {
    case corruptRecord(String)
    case mealNotFound(UUID)
    case archiveFailed(String)
}

public protocol PersistenceStore: Sendable {
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws
    func meal(id: UUID) async throws -> MealRecord
    func deleteArtefacts(olderThan date: Date) async throws
    func exportArchive() async throws -> String    // returns file path; UI wraps in URL
    func sweepIfDue() async throws
    // Stamps the PHAsset.localIdentifier returned by the Photos library save on
    // an existing meal (Decision 37). Called by the capture flow after the
    // pipeline returns and the photo save completes; pre-existing rows have
    // photo_asset_id = '' until this is invoked.
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws

    // v1.1 Meals tab — additive surface per UI Decision 15.
    // `allMeals` returns rows sorted by `createdAt` descending. `deleteMeal`
    // removes the SQLite row plus the per-meal artefact directory (best-effort)
    // and DOES NOT touch the user's Photos library. `mealsDidChange` emits a
    // tick after every successful write; subscribers see the latest event under
    // `BufferingPolicy.bufferingNewest(1)`.
    func allMeals() async throws -> [MealRecord]
    func deleteMeal(id: UUID) async throws
    var mealsDidChange: AsyncStream<Void> { get }
}
