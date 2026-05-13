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
}
