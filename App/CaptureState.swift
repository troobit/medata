import Pipeline

enum CaptureStage: Equatable, Sendable {
    case nadir
    case oblique
}

// Route enums replace `navigationDestination(for: MealRecord.self)` (design:
// Navigation routes). Each navigation stack keys exactly one enum.
//
// The capture stack (rooted in `CaptureFlowView`) drives a fresh capture through
// review → result. The `.correction` route is retired with
// ManualCorrectionView (serving-adjust PRD Req 5) — the result screen's
// per-food rows are the adjustment surface.
enum CaptureRoute: Hashable {
    case review(MealRecord)      // → SegmentationReviewView
    case result(MealRecord)      // → ResultView(.justCaptured)
}

// The Records and Trends sheet stacks share this enum: a day/list row pushes
// `.overview`, which can push the full `.result`.
enum MealRoute: Hashable {
    case overview(MealRecord)    // → MealOverviewView
    case result(MealRecord)      // → ResultView(.historyDetail)
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
