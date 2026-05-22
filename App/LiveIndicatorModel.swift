import Observation

@Observable
@MainActor
final class LiveIndicatorModel {
    var liveTiltDegrees: Float = 0
    var liveDistanceCm: Float?
    var liveLiDARCoveragePercent: Float = 0
}
