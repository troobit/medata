import Foundation

// Pipeline refusal cases per design §5, one-to-one with the table therein.
// Thrown by `Pipeline.estimate(_:)` to short-circuit the pipeline on an
// unrecoverable condition. The UI dispatches the message for each case
// verbatim (Req 17.1, task 52).
public enum EstimationFailure: Error, Equatable {
    // Device does not have the required LiDAR hardware (Req 1.3).
    case noLidarDevice
    // ARWorldTracking degraded during the oblique capture (Req 3.7).
    case arWorldTrackingLost
    // LiDAR became unavailable between path dispatch and volume estimation.
    case lidarUnavailableMidCapture
    // P4P pose has both sign-of-λ candidates behind the camera or a degenerate quad.
    case degenerateCardPose
    // Card is seen at >78° edge-on (§6.1 step 7 edge case 1).
    case cardTooOblique
    // LiDAR RANSAC plane-fit covariance matrix is singular.
    case lidarFitDegenerate
    // LiDAR RANSAC inlier σ exceeds 20 mm (Req 4.5, raised from 8 mm per Decision 46).
    case lidarFitResidualTooHigh
    // Card-only iterative fit best-of-5 residual exceeds 1.5 mm (Req 4.3).
    case iterationDiverged
    // Neither card nor LiDAR scale is available (Req 7.5).
    case noScaleAvailable
    // Zero food pixels survive the silhouette test (§5 edge case 3).
    case noFoodPixels
    // The segmenter labelled a substantial region `unknown_food` and it
    // dominates the recognised classes — the model saw food it cannot name,
    // so any estimate would come from a residual sliver (bugfix
    // unrecognised-food-estimated-as-residual-sliver).
    case unrecognisedFood
    // All per-class volumes are below 1 cm³ post β-correction.
    case noFoodVolumeRecovered
    // ≥1 food class has <30% LiDAR depth coverage in single-view path
    // (Req 3.5, 13.2; relaxed from 50% per Decision 47).
    case lidarCoverageTooLow([String])
    // Oblique-stage hard cap: |θ − 25°| > 30° — outside the soft-acceptance
    // envelope of research Req 3.3 / Decision 43. The SfS algorithm produces
    // silently-wrong volumes far outside the Dehais 2017 envelope, so the
    // oblique view is gated even after Decision 18 removed the nadir tilt gate.
    case obliqueTiltOutOfRange
    // meals.sqlite is corrupt; record quarantined, history temporarily unavailable.
    case mealsDbCorrupt
    // Catch-all for any non-typed error raised by `Pipeline.estimate` (Req 6 /
    // Decision 7 of `specs/capture/rawframe-rgb-conversion/`). The payload is the
    // underlying error's Swift type name so the on-screen message can be
    // correlated with the device log's `event=estimate.end success=false
    // error=<Type>` line at debug time.
    case internalError(String)

    // MARK: - User-facing messages (Req 17.1)

    public var localisedMessage: String {
        switch self {
        case .noLidarDevice:
            // Hardware floor: iPhone 16 Pro (segmenter-foundation Decision 22,
            // 2026-07-15; snaq-parity Req 3.5). Older devices — the 13 Pro Max
            // included — are out of scope.
            return "MeData requires an iPhone 16 Pro or later."
        case .arWorldTrackingLost:
            return "World tracking was lost during capture. Please retake the photo."
        case .lidarUnavailableMidCapture:
            return "The depth sensor became unavailable during capture. Switching to two-view mode."
        case .degenerateCardPose:
            return "Card not recognised. Please ensure the card is fully in view and flat."
        case .cardTooOblique:
            return "Place the card flat in the view. It appears to be at a steep angle."
        case .lidarFitDegenerate:
            return "Unable to detect a flat surface. Please place the meal on a level surface."
        case .lidarFitResidualTooHigh:
            return "The surface appears uneven. Please place the meal on a flat, level surface."
        case .iterationDiverged:
            return "Unable to determine plate position. Please include the card in the nadir view."
        case .noScaleAvailable:
            return "Unable to determine meal scale. Please include the reference card in the image."
        case .noFoodPixels:
            return "No food detected in the image. Please ensure the meal is clearly visible."
        case .unrecognisedFood:
            return "MeData can't name this food yet, so no estimate was made."
        case .noFoodVolumeRecovered:
            return "Unable to estimate the meal volume. Please retake the photo."
        case .lidarCoverageTooLow(let classes):
            let list = classes.joined(separator: ", ")
            return "Insufficient depth data for: \(list). Please use two-view mode instead."
        case .obliqueTiltOutOfRange:
            return "Tilt the camera closer to 25° for the angled view."
        case .mealsDbCorrupt:
            return
                "Your meal history could not be loaded and has been reset. Capture continues normally."
        case .internalError(let typeName):
            #if DEBUG
                return "Couldn't process the photo. Internal error: \(typeName)"
            #else
                _ = typeName
                return "Couldn't process the photo. Please try again."
            #endif
        }
    }
}
