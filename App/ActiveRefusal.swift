import Foundation
import Pipeline

// Identifiable wrapper around an `EstimationFailure` + its `retryStage` so
// `CaptureFlowView` can bind the `RefusalSheet` via `.sheet(item:)` (UI Req
// §20.7 / Decision 16). The `id` is derived from the failure case so SwiftUI
// recognises the same refusal across consecutive renders and does not
// re-present the sheet.
struct ActiveRefusal: Identifiable, Equatable {
    let failure: EstimationFailure
    let retryStage: CaptureStage

    var id: String {
        switch failure {
        case .lidarCoverageTooLow(let classes):
            return "lidarCoverageTooLow.\(classes.joined(separator: ","))"
        default:
            return String(describing: failure)
        }
    }
}
