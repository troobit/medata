import SwiftUI

// Single consolidated indicator chip replacing the v1.0 three-corner
// `LiveIndicatorView` (UI Req §20.4 / Decision 16). Spec: `design-system/pages/
// photo-tab.md` §"Indicator badge". Three sub-elements left-to-right (tilt,
// distance, LiDAR coverage) separated by 8pt hairlines; LiDAR-dependent
// sub-elements are omitted when `supportsLiDAR == false`.
//
// Auto-hide rule: when the badge has been in-range for `autoHideDelaySeconds`
// the chip fades to opacity 0; tap or any out-of-range write re-shows it.
// Hidden chip remains hit-testable via 48pt `hitSlop` (touch-target rule).

// MARK: - Pure state surface (testable without a SwiftUI host)

enum LiveIndicatorBadgeElement: Equatable {
    case tilt
    case distance
    case coverage
}

enum LiveIndicatorBadgeState {
    static let autoHideDelaySeconds: Double = 5
    static let hitSlopPoints: CGFloat = 48
    static let distanceMinCm: Float = 25
    static let distanceMaxCm: Float = 50
    // Decision 19: chip auto-hides only when σ_tilt = cos(Δθ) exceeds this
    // threshold — ≈ Δθ < 18°. Captures continue to land outside this band
    // (Decision 18) but the chip stays visible so the user sees the σ_tilt
    // % they are about to record.
    static let sigmaTiltAutoHideThreshold: Float = 0.95

    static func elements(supportsLiDAR: Bool) -> [LiveIndicatorBadgeElement] {
        supportsLiDAR ? [.tilt, .distance, .coverage] : [.tilt]
    }

    static func sigmaTilt(deltaThetaDegrees: Float) -> Float {
        cosf(deltaThetaDegrees * .pi / 180)
    }

    static func isSigmaTiltSufficient(deltaThetaDegrees: Float) -> Bool {
        sigmaTilt(deltaThetaDegrees: deltaThetaDegrees) > sigmaTiltAutoHideThreshold
    }

    static func isDistanceInRange(cm: Float?) -> Bool {
        guard let cm else { return false }
        return cm >= distanceMinCm && cm <= distanceMaxCm
    }

    static func allInRange(
        deltaThetaDegrees: Float,
        distanceCm: Float?,
        lidarCoveragePercent: Float,
        supportsLiDAR: Bool
    ) -> Bool {
        guard isSigmaTiltSufficient(deltaThetaDegrees: deltaThetaDegrees) else { return false }
        guard supportsLiDAR else { return true }
        return isDistanceInRange(cm: distanceCm) && lidarCoveragePercent > 0
    }

    // Reduced motion replaces the fade with a snap-to-zero (Req §20.11).
    static func fadeDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 0.25
    }
}

// The `LiveIndicatorBadge` view (auto-hiding tilt/distance/coverage chip) was
// deleted in the handoff-00 chrome rebuild — the always-visible
// `TelemetryCapsule` replaces it (design: parity audit). The pure
// `LiveIndicatorBadgeState` above is kept: `CaptureFlowModel.tiltInRange` calls
// `isSigmaTiltSufficient`, and it remains testable without a SwiftUI host.
