import CaptureKit
import Foundation
import PortableContracts
import SupportPlane

// Input bundle produced by the capture flow and consumed by Pipeline.estimate(_:).
// Carries all per-session data needed by the pipeline stages C–L (design §2.2).
public struct CaptureResult: Sendable {
    public let capturePath: CapturePath
    public let lidar: LiDARStatus
    public let nadirFrame: RawFrame
    public let obliqueFrame: RawFrame?      // nil for singleViewLidar path
    public let databaseEdition: String
    public let paletteVersion: String
    // Tilt angle (degrees from the stage's target axis: 0° for nadir, 25° for oblique)
    // sampled by `CaptureFlowDelegate.didUpdateTilt(angleDegrees:)` at shutter-tap
    // time per task 86 / Decision 44. Drives σ_tilt in `Confidence.combine`. The
    // values are the raw angles from straight-down (nadir reference); the pipeline
    // converts to per-stage Δθ.
    public let nadirAngleAtCaptureDeg: Float
    public let obliqueAngleAtCaptureDeg: Float?
    // Pre-shutter food-region mask sampled at nadir-capture instant (Decision 11).
    // Threaded into `SupportPlaneFitter.fit` and the `foodRegionCoveragePercent`
    // recompute inside `Pipeline.estimate`. nil ⇒ pre-shutter pass produced no
    // mask within the 750 ms staleness window (Req 1.2 / 3.2).
    public let preShutterFoodMask: BinaryMask?
    // Age of `preShutterFoodMask` at nadir-capture instant, in milliseconds.
    // Logged at `event=estimate.start` for on-device freshness telemetry.
    // nil when `preShutterFoodMask` is nil.
    public let preShutterMaskAgeMs: Int?

    public init(
        capturePath: CapturePath,
        lidar: LiDARStatus,
        nadirFrame: RawFrame,
        obliqueFrame: RawFrame?,
        databaseEdition: String,
        paletteVersion: String,
        nadirAngleAtCaptureDeg: Float = 0,
        obliqueAngleAtCaptureDeg: Float? = nil,
        preShutterFoodMask: BinaryMask? = nil,
        preShutterMaskAgeMs: Int? = nil
    ) {
        self.capturePath = capturePath
        self.lidar = lidar
        self.nadirFrame = nadirFrame
        self.obliqueFrame = obliqueFrame
        self.databaseEdition = databaseEdition
        self.paletteVersion = paletteVersion
        self.nadirAngleAtCaptureDeg = nadirAngleAtCaptureDeg
        self.obliqueAngleAtCaptureDeg = obliqueAngleAtCaptureDeg
        self.preShutterFoodMask = preShutterFoodMask
        self.preShutterMaskAgeMs = preShutterMaskAgeMs
    }
}
