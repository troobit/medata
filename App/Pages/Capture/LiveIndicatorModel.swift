import Foundation
import Observation

@Observable
@MainActor
final class LiveIndicatorModel {
    var liveTiltDegrees: Float = 0
    // Two-axis tilt (degrees) for the bubble guide: length == liveTiltDegrees,
    // direction == on-screen azimuth of the tilt. See LiveSampleMath.tiltVector.
    var liveTiltVector: SIMD2<Float> = .zero
    var liveDistanceCm: Float?
    var liveLiDARCoveragePercent: Float = 0
    var visible: Bool = true

    @ObservationIgnored
    private var autoHideTask: Task<Void, Never>?

    func reveal() {
        autoHideTask?.cancel()
        visible = true
        scheduleHide()
    }

    func scheduleHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(LiveIndicatorBadgeState.autoHideDelaySeconds * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.visible = false
        }
    }
}
