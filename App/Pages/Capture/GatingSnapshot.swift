// Per-frame gating signals consumed at shutter-tap time. The capture path is
// no longer derived per-frame (Decision 35); it comes from `CaptureFlowModel.mode`
// (a persistent UserDefaults setting) and is read at shutter-tap time.
struct GatingSnapshot: Equatable, Sendable {
    let tiltInRange: Bool
    let distanceCm: Float?
    let lidarCoveragePercent: Float
}
