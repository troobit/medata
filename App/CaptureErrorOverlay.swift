import Pipeline
import SwiftUI

// Full-screen capture-error overlay (§4), replacing the `RefusalSheet` bottom
// sheet. An amber ghost outline frames the frozen viewfinder; a ≤3-word status
// chip and a one-clause fix hint name the problem; three escape actions —
// `Retry`, `2-view`, `Cancel` — guarantee no dead end (Req 4.1). Chips and hints
// are verbatim from the copy inventory where a failure maps to a listed row.
//
// Actions bind to the same model surface the sheet used: `Retry` → `retry()`
// (resumes at the failed stage, AR live — folds iphone-experience 10.2/10.3);
// `2-view` → `switchToTwoViewAndRetry()`; `Cancel` → `dismissRefusal()`.
struct CaptureErrorOverlay: View {
    let failure: EstimationFailure
    let onRetry: () -> Void
    let onTwoView: () -> Void
    let onCancel: () -> Void

    private var amber: Color { Color(uiColor: .systemOrange) }

    var body: some View {
        ZStack {
            Color.captureBackground.opacity(0.72)
                .ignoresSafeArea()

            // Amber ghost outline — a translucent dashed frame that reads as an
            // alert without a solid banner (MASTER.md: flat overlays only).
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(
                    amber.opacity(0.6),
                    style: StrokeStyle(lineWidth: 3, dash: [10, 8])
                )
                .padding(16)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                chip
                Text(failure.errorHint)
                    .font(.callout)
                    .foregroundStyle(Color.captureChromeText.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("captureError.hint")
                actions
            }
            .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("captureErrorOverlay")
    }

    private var chip: some View {
        Label {
            Text(failure.errorChip)
                .font(.title3.weight(.bold))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(amber.opacity(0.85), in: Capsule())
        .accessibilityIdentifier("captureError.chip")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button("Retry", action: onRetry)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                // Make the whole pill tappable: without this only the centred
                // text label receives touches, so taps on the wide coloured area
                // are dead (the `.frame(maxWidth:.infinity)` expansion is not
                // hit-tested on its own).
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("captureError.retry")

            Button("2-view", action: onTwoView)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                .foregroundStyle(Color.captureChromeText)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("captureError.twoView")

            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .frame(height: 44)
                .foregroundStyle(Color.captureChromeText.opacity(0.85))
                .accessibilityIdentifier("captureError.cancel")
        }
    }
}

// Chip (≤3 words) and hint (one clause) per failure. Rows present in the copy
// inventory are verbatim; the rest follow the minimal-wording rule (Req 4.2).
extension EstimationFailure {
    var errorChip: String {
        switch self {
        case .obliqueTiltOutOfRange: return "too tilted"
        case .arWorldTrackingLost, .lidarUnavailableMidCapture: return "tracking lost"
        case .noLidarDevice: return "no LiDAR"
        case .noScaleAvailable, .degenerateCardPose, .cardTooOblique, .iterationDiverged:
            return "card needed"
        case .lidarCoverageTooLow: return "low depth"
        case .lidarFitDegenerate: return "no surface"
        case .lidarFitResidualTooHigh: return "uneven surface"
        case .noFoodPixels: return "no food"
        case .noFoodVolumeRecovered: return "no volume"
        case .mealsDbCorrupt: return "history reset"
        case .internalError: return "error"
        }
    }

    var errorHint: String {
        switch self {
        case .obliqueTiltOutOfRange: return "Target 25°"
        case .arWorldTrackingLost, .lidarUnavailableMidCapture: return "Retake second photo"
        case .noLidarDevice: return "2-view still works"
        case .noScaleAvailable, .degenerateCardPose, .cardTooOblique, .iterationDiverged:
            return "Any bank card sets scale"
        case .lidarCoverageTooLow: return "Use two-view mode"
        case .lidarFitDegenerate, .lidarFitResidualTooHigh: return "Use a flat surface"
        case .noFoodPixels: return "Show the meal clearly"
        case .noFoodVolumeRecovered: return "Retake the photo"
        case .mealsDbCorrupt: return "Capture still works"
        case .internalError: return "Try again"
        }
    }
}
