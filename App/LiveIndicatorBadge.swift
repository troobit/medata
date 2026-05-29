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
    static let tiltToleranceDegrees: Float = 5
    static let distanceMinCm: Float = 25
    static let distanceMaxCm: Float = 50

    static func elements(supportsLiDAR: Bool) -> [LiveIndicatorBadgeElement] {
        supportsLiDAR ? [.tilt, .distance, .coverage] : [.tilt]
    }

    static func isTiltInRange(degrees: Float, target: Float) -> Bool {
        abs(degrees - target) <= tiltToleranceDegrees
    }

    static func isDistanceInRange(cm: Float?) -> Bool {
        guard let cm else { return false }
        return cm >= distanceMinCm && cm <= distanceMaxCm
    }

    static func allInRange(
        tiltDegrees: Float,
        target: Float,
        distanceCm: Float?,
        supportsLiDAR: Bool
    ) -> Bool {
        guard isTiltInRange(degrees: tiltDegrees, target: target) else { return false }
        guard supportsLiDAR else { return true }
        return isDistanceInRange(cm: distanceCm)
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
    var targetTiltDegrees: Float = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible: Bool = true
    @State private var autoHideTask: Task<Void, Never>?

    private var tiltInRange: Bool {
        LiveIndicatorBadgeState.isTiltInRange(
            degrees: model.liveTiltDegrees,
            target: targetTiltDegrees
        )
    }

    private var distanceInRange: Bool {
        LiveIndicatorBadgeState.isDistanceInRange(cm: model.liveDistanceCm)
    }

    private var allInRange: Bool {
        LiveIndicatorBadgeState.allInRange(
            tiltDegrees: model.liveTiltDegrees,
            target: targetTiltDegrees,
            distanceCm: model.liveDistanceCm,
            supportsLiDAR: supportsLiDAR
        )
    }

    var body: some View {
        chip
            .opacity(visible ? 1 : 0)
            .animation(
                reduceMotion ? .none : .easeInOut(duration: LiveIndicatorBadgeState.fadeDuration(reduceMotion: false)),
                value: visible
            )
            .frame(minWidth: LiveIndicatorBadgeState.hitSlopPoints, minHeight: LiveIndicatorBadgeState.hitSlopPoints)
            .contentShape(Rectangle())
            .onTapGesture { showAndScheduleHide() }
            .onChange(of: allInRange) { _, ready in
                if ready, isReady {
                    scheduleHide()
                } else {
                    showAndScheduleHide()
                }
            }
            .onChange(of: isReady) { _, ready in
                if ready, allInRange {
                    scheduleHide()
                } else {
                    showAndScheduleHide()
                }
            }
            .onAppear { showAndScheduleHide() }
            .onDisappear {
                autoHideTask?.cancel()
                autoHideTask = nil
            }
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
            Label {
                Text("\(Int(model.liveTiltDegrees.rounded()))°")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "level")
            }
            .foregroundStyle(tiltInRange ? Color.medataAccent : Color.captureChromeText)
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

    private func showAndScheduleHide() {
        autoHideTask?.cancel()
        visible = true
        if isReady, allInRange { scheduleHide() }
    }

    private func scheduleHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(LiveIndicatorBadgeState.autoHideDelaySeconds * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
