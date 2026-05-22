import Pipeline

struct GatingSnapshot: Equatable, Sendable {
    let pathHint: CapturePath
    let tiltInRange: Bool
    let distanceCm: Float?
    let lidarCoveragePercent: Float

    func withPath(_ newPath: CapturePath) -> GatingSnapshot {
        GatingSnapshot(
            pathHint: newPath,
            tiltInRange: tiltInRange,
            distanceCm: distanceCm,
            lidarCoveragePercent: lidarCoveragePercent
        )
    }
}
