import Foundation
import Persistence
import PortableContracts

// Observer protocol that the SwiftUI capture flow view conforms to. The pipeline
// calls these on the pipeline's concurrency context; the UI must hop to MainActor.
public protocol CaptureFlowDelegate: AnyObject, Sendable {
    func didUpdateTilt(angleDegrees: Float)
    func didUpdateLiDARCoverage(percent: Float)
    func didDetectInterClassOcclusion()
    func didProduceEstimate(_ record: MealRecord)
    // Fires exactly once per non-cancelled `Pipeline.estimate` call — success
    // AND refusal — after the outcome has been stamped (snaq-parity lane A).
    // The payload is an immutable `Sendable` snapshot, safe to hand to a
    // detached write-behind task.
    func didCompleteAttempt(_ record: EstimationAttemptRecord)
}
