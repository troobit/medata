import Pipeline
import SwiftUI

// Bottom-sheet refusal surface superseding the v1.0 `RefusalBanner` per UI
// Req §20.7 / Decision 16. Spec: `design-system/pages/photo-tab.md`
// §"Refusal banner". Presented via `.sheet(item: $model.refusal)` from
// `CaptureFlowView` (task 52).

// SF Symbol per failure case (Req §10.1 / §20.7). The mapping is exhaustive on
// `EstimationFailure`; new cases added in MedataCore will trigger a compiler
// warning at the `default` branch — chosen `default` over `@unknown` since
// `EstimationFailure` is not `@frozen`.
extension EstimationFailure {
    var refusalSymbol: String {
        switch self {
        case .noLidarDevice: return "iphone.gen3.slash"
        case .arWorldTrackingLost: return "scope"
        case .lidarUnavailableMidCapture: return "sensor.tag.radiowaves.forward.slash"
        case .degenerateCardPose, .cardTooOblique: return "creditcard.trianglebadge.exclamationmark"
        case .lidarFitDegenerate, .lidarFitResidualTooHigh: return "circle.dashed.inset.filled"
        case .iterationDiverged: return "rectangle.dashed"
        case .noScaleAvailable: return "rulerline.diagonal"
        case .noFoodPixels: return "fork.knife.circle"
        case .noFoodVolumeRecovered: return "cube.transparent"
        case .lidarCoverageTooLow: return "square.stack.3d.up.slash"
        case .obliqueTiltOutOfRange: return "rotate.3d"
        case .mealsDbCorrupt: return "exclamationmark.octagon"
        case .internalError: return "exclamationmark.triangle"
        }
    }

    // Short Irish-English title per design-system/pages/photo-tab.md
    // §"Refusal banner". The body of the sheet shows `localisedMessage` so the
    // verbatim Req §12.2 copy reaches the user; the title is the at-a-glance
    // failure category.
    var refusalTitle: String {
        switch self {
        case .noLidarDevice: return "Depth sensor not found"
        case .arWorldTrackingLost: return "Tracking lost"
        case .lidarUnavailableMidCapture: return "Depth sensor lost"
        case .degenerateCardPose, .cardTooOblique: return "Card not recognised"
        case .lidarFitDegenerate: return "Surface not detected"
        case .lidarFitResidualTooHigh: return "Surface not flat"
        case .iterationDiverged: return "Plate not located"
        case .noScaleAvailable: return "Meal scale unknown"
        case .noFoodPixels: return "No food detected"
        case .noFoodVolumeRecovered: return "Volume not estimated"
        case .lidarCoverageTooLow: return "Not enough depth data"
        case .obliqueTiltOutOfRange: return "Tilt closer to 25°"
        case .mealsDbCorrupt: return "Meal history reset"
        case .internalError: return "Couldn't process the photo"
        }
    }
}

struct RefusalSheet: View {
    let failure: EstimationFailure
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failure.refusalSymbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.confidenceLow)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(failure.refusalTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(failure.localisedMessage)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("refusal.message")

            Spacer(minLength: 8)

            Button("Try again", action: retry)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: Capsule())
                .foregroundStyle(Color.captureBackground)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityIdentifier("refusal.tryAgain")
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
        .presentationDetents([.fraction(0.35), .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("refusalSheet")
    }
}
