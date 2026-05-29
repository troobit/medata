import Testing
@testable import MeData

// Task 44 / Req §20.4 / Decision 16. Behavioural assertions for the
// consolidated indicator chip — chip composition, in-range tint, auto-hide
// timing, and re-show triggers. The pure `LiveIndicatorBadgeState` carries the
// state-machine surface so we can test it without a SwiftUI host.
@Suite("LiveIndicatorBadge state — composition, in-range, auto-hide")
@MainActor
struct LiveIndicatorBadgeTests {

    // MARK: - Composition

    @Test("supportsLiDAR=true renders tilt + distance + coverage")
    func compositionWithLiDAR() {
        let elements = LiveIndicatorBadgeState.elements(supportsLiDAR: true)
        #expect(elements == [.tilt, .distance, .coverage])
    }

    @Test("supportsLiDAR=false renders tilt only — distance & coverage omitted")
    func compositionWithoutLiDAR() {
        let elements = LiveIndicatorBadgeState.elements(supportsLiDAR: false)
        #expect(elements == [.tilt])
    }

    // MARK: - In-range tint

    @Test("tilt within ±5° of target → green (in-range)")
    func tiltInRange() {
        #expect(LiveIndicatorBadgeState.isTiltInRange(degrees: 0, target: 0))
        #expect(LiveIndicatorBadgeState.isTiltInRange(degrees: 4.9, target: 0))
        #expect(LiveIndicatorBadgeState.isTiltInRange(degrees: 25, target: 25))
    }

    @Test("tilt outside ±5° of target → white (out-of-range)")
    func tiltOutOfRange() {
        #expect(!LiveIndicatorBadgeState.isTiltInRange(degrees: 5.5, target: 0))
        #expect(!LiveIndicatorBadgeState.isTiltInRange(degrees: -10, target: 0))
        #expect(!LiveIndicatorBadgeState.isTiltInRange(degrees: 0, target: 25))
    }

    @Test("distance in 25–50 cm → in-range; outside → out-of-range; nil → out-of-range")
    func distanceRange() {
        #expect(LiveIndicatorBadgeState.isDistanceInRange(cm: 25))
        #expect(LiveIndicatorBadgeState.isDistanceInRange(cm: 35))
        #expect(LiveIndicatorBadgeState.isDistanceInRange(cm: 50))
        #expect(!LiveIndicatorBadgeState.isDistanceInRange(cm: 24.9))
        #expect(!LiveIndicatorBadgeState.isDistanceInRange(cm: 51))
        #expect(!LiveIndicatorBadgeState.isDistanceInRange(cm: nil))
    }

    // MARK: - All-in-range gate

    @Test("allInRange = tilt-in-range AND (no-LiDAR OR distance-in-range)")
    func allInRangeWithLiDAR() {
        let yes = LiveIndicatorBadgeState.allInRange(
            tiltDegrees: 0, target: 0, distanceCm: 35, supportsLiDAR: true
        )
        #expect(yes)

        let outTilt = LiveIndicatorBadgeState.allInRange(
            tiltDegrees: 10, target: 0, distanceCm: 35, supportsLiDAR: true
        )
        #expect(!outTilt)

        let outDist = LiveIndicatorBadgeState.allInRange(
            tiltDegrees: 0, target: 0, distanceCm: 100, supportsLiDAR: true
        )
        #expect(!outDist)
    }

    @Test("no-LiDAR: distance does not gate (only tilt)")
    func allInRangeNoLiDAR() {
        let yes = LiveIndicatorBadgeState.allInRange(
            tiltDegrees: 0, target: 0, distanceCm: nil, supportsLiDAR: false
        )
        #expect(yes)
        let no = LiveIndicatorBadgeState.allInRange(
            tiltDegrees: 10, target: 0, distanceCm: nil, supportsLiDAR: false
        )
        #expect(!no)
    }

    // MARK: - Auto-hide timing

    @Test("auto-hide delay is 5 seconds (Req §20.4)")
    func autoHideDelay() {
        #expect(LiveIndicatorBadgeState.autoHideDelaySeconds == 5)
    }

    @Test("reduced motion: auto-hide is snap-to-zero, no fade")
    func reducedMotionFade() {
        #expect(LiveIndicatorBadgeState.fadeDuration(reduceMotion: true) == 0)
        #expect(LiveIndicatorBadgeState.fadeDuration(reduceMotion: false) > 0)
    }
}
