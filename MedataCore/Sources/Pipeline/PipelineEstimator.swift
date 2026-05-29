import Foundation
import Persistence
import PortableContracts

// Test seam per `specs/ui/decision_log.md` Decision 13. `CaptureFlowModel`
// holds `any PipelineEstimator` so unit tests can inject a mock without
// spinning up a real `Pipeline` (which requires the segmenter weights and
// a full `FoodDatabase` / `PersistenceStore`). Production code passes a real
// `Pipeline`.
//
// `mode` is the user-selected `CaptureMode` from §2.3 / Decision 35. It is the
// authoritative input that drives volume-estimator dispatch; `MealRecord.capturePath`
// is copied from `mode.capturePath` so the recorded path matches what executed.
public protocol PipelineEstimator: Sendable {
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord
}

extension Pipeline: PipelineEstimator {}
