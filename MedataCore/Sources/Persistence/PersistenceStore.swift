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
}
