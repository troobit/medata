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

// MARK: - View

struct LiveIndicatorBadge: View {
    @Bindable var model: LiveIndicatorModel
    let supportsLiDAR: Bool
    let isReady: Bool
    // Per-stage target tilt: 0° at nadir, 25° at oblique. Decision 19 only uses
    // this for the displayed Δθ — the colour treatment is greyscale regardless.
    var targetTiltDegrees: Float = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Δθ between the current measured tilt and the per-stage target.
    private var deltaThetaDeg: Float {
        abs(model.liveTiltDegrees - targetTiltDegrees)
    }

    private var sigmaTilt: Float {
        LiveIndicatorBadgeState.sigmaTilt(deltaThetaDegrees: deltaThetaDeg)
    }

    private var distanceInRange: Bool {
        LiveIndicatorBadgeState.isDistanceInRange(cm: model.liveDistanceCm)
    }

    private var allInRange: Bool {
        LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: deltaThetaDeg,
            distanceCm: model.liveDistanceCm,
            lidarCoveragePercent: model.liveLiDARCoveragePercent,
            supportsLiDAR: supportsLiDAR
        )
    }

    var body: some View {
        chip
            .opacity(model.visible ? 1 : 0)
            .animation(
                reduceMotion ? .none : .easeInOut(duration: LiveIndicatorBadgeState.fadeDuration(reduceMotion: false)),
                value: model.visible
            )
            .frame(minWidth: LiveIndicatorBadgeState.hitSlopPoints, minHeight: LiveIndicatorBadgeState.hitSlopPoints)
            .contentShape(Rectangle())
            .onTapGesture { model.reveal() }
            .onChange(of: allInRange) { _, ready in
                if ready, isReady {
                    model.scheduleHide()
                } else {
                    model.reveal()
                }
            }
            .onChange(of: isReady) { _, ready in
                if ready, allInRange {
                    model.scheduleHide()
                } else {
                    model.reveal()
                }
            }
            .onAppear { model.reveal() }
            .accessibilityIdentifier("liveIndicator.badge")
    }

    private var chip: some View {
        HStack(spacing: 0) {
            let elems = LiveIndicatorBadgeState.elements(supportsLiDAR: supportsLiDAR)
            ForEach(Array(elems.enumerated()), id: \.offset) { index, element in
                if index > 0 { hairline }
                elementView(element)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 14))
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.captureChromeText.opacity(0.2))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func elementView(_ element: LiveIndicatorBadgeElement) -> some View {
        switch element {
        case .tilt:
            // Decision 19: continuous greyscale Δθ + σ_tilt% readout. No
            // green/red in/out-of-range tinting — every angle is a valid
            // capture; the user sees the σ_tilt cost they are about to pay.
            HStack(spacing: 6) {
                Image(systemName: "level")
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(deltaThetaDeg.rounded()))°")
                        .monospacedDigit()
                    Text("\(Int((sigmaTilt * 100).rounded()))%")
                        .font(.caption2.weight(.regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Color.captureChromeText)
            .accessibilityIdentifier("liveIndicator.tilt")
        case .distance:
            Label {
                Text(model.liveDistanceCm.map { "\(Int($0.rounded())) cm" } ?? "— cm")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "ruler")
            }
            .foregroundStyle(distanceInRange ? Color.medataAccent : Color.captureChromeText)
            .accessibilityIdentifier("liveIndicator.distance")
        case .coverage:
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Capsule()
                    .fill(Color.captureChromeText.opacity(0.25))
                    .frame(width: 32, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.medataAccent)
                            .frame(
                                width: 32 * CGFloat(min(max(model.liveLiDARCoveragePercent, 0), 100) / 100),
                                height: 4
                            )
                    }
                Text("\(Int(model.liveLiDARCoveragePercent.rounded()))%")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("liveIndicator.coverage")
        }
    }

}
