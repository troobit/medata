import Pipeline

enum CaptureStage: Equatable, Sendable {
    case nadir
    case oblique
}

enum PermissionSubject: Equatable, Sendable {
    case camera
    case motion
}

// Capture-flow states. `.forcingTwoView` was removed per Decision 35 — the
// user picks a single persistent CaptureMode and the in-flight flow no longer
// observes mid-session mode changes.
enum CaptureState: Equatable {
    case initialising
    case permissionDenied(PermissionSubject)
    case trackingLost
    case ready(GatingSnapshot)
    case capturing(stage: CaptureStage, frozen: GatingSnapshot)
    case estimating(captureResult: CaptureResult)
    case showingResult(MealRecord)
    case refused(EstimationFailure, retryStage: CaptureStage)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.initialising, .initialising),
             (.trackingLost, .trackingLost):
            return true
        case let (.permissionDenied(a), .permissionDenied(b)):
            return a == b
        case let (.ready(a), .ready(b)):
            return a == b
        case let (.capturing(aStage, aFrozen), .capturing(bStage, bFrozen)):
            return aStage == bStage && aFrozen == bFrozen
        case (.estimating, .estimating):
            // CaptureResult wraps RawFrame which isn't Equatable; state-machine
            // tests only care that we're in the estimating phase.
            return true
        case let (.showingResult(a), .showingResult(b)):
            return a == b
        case let (.refused(aFailure, aStage), .refused(bFailure, bStage)):
            return aFailure == bFailure && aStage == bStage
        default:
            return false
        }
    }
}
