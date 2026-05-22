import Foundation
import Persistence
import PortableContracts

// Test seam per `specs/ui/decision_log.md` Decision 13. `CaptureFlowModel`
// holds `any PipelineEstimator` so unit tests can inject a mock without
// spinning up a real `Pipeline` (which requires the segmenter weights and
// a full `FoodDatabase` / `PersistenceStore`). Production code passes a real
// `Pipeline`.
public protocol PipelineEstimator: Sendable {
    func estimate(captureResult: CaptureResult) async throws -> MealRecord
}

extension Pipeline: PipelineEstimator {}
