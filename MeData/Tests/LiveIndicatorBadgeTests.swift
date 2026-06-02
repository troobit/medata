import Testing
@testable import MeData

// Task 44/54/55 — Req §20.4 / Decisions 16, 18, 19. Behavioural assertions for
// the consolidated indicator chip. Decision 19 replaces the binary
// in-range/out-of-range tilt state with a continuous σ_tilt = cos(Δθ) readout;
// the chip auto-hide gate is re-anchored to σ_tilt > 0.95 (≈ Δθ < 18°) plus the
// other indicators in-range.
@Suite("LiveIndicatorBadge state — composition, σ_tilt gate, auto-hide")
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

    // MARK: - σ_tilt readout (Decision 19)

    @Test("σ_tilt = cos(Δθ) per Decision 19 — Δθ=0 → 1.0; Δθ=60 → 0.5")
    func sigmaTiltCurve() {
        let s0 = LiveIndicatorBadgeState.sigmaTilt(deltaThetaDegrees: 0)
        let s60 = LiveIndicatorBadgeState.sigmaTilt(deltaThetaDegrees: 60)
        #expect(s0 > 0.999)
        #expect(abs(s60 - 0.5) < 0.001)
    }

    @Test("σ_tilt > 0.95 satisfied at Δθ=10° (≈0.985) but not at Δθ=20° (≈0.940)")
    func sigmaTiltAutoHideThreshold() {
        #expect(LiveIndicatorBadgeState.isSigmaTiltSufficient(deltaThetaDegrees: 10))
        #expect(!LiveIndicatorBadgeState.isSigmaTiltSufficient(deltaThetaDegrees: 20))
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

    // MARK: - All-in-range gate (drives the 5 s auto-hide)

    @Test("allInRange = σ_tilt > 0.95 AND (no-LiDAR OR (distance-in-range AND coverage>0))")
    func allInRangeWithLiDAR() {
        let yes = LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: 5, distanceCm: 35, lidarCoveragePercent: 80, supportsLiDAR: true
        )
        #expect(yes)

        let outTilt = LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: 20, distanceCm: 35, lidarCoveragePercent: 80, supportsLiDAR: true
        )
        #expect(!outTilt)

        let outDist = LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: 5, distanceCm: 100, lidarCoveragePercent: 80, supportsLiDAR: true
        )
        #expect(!outDist)
    }

    @Test("no-LiDAR: distance does not gate (only σ_tilt)")
    func allInRangeNoLiDAR() {
        let yes = LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: 5, distanceCm: nil, lidarCoveragePercent: 0, supportsLiDAR: false
        )
        #expect(yes)
        let no = LiveIndicatorBadgeState.allInRange(
            deltaThetaDegrees: 25, distanceCm: nil, lidarCoveragePercent: 0, supportsLiDAR: false
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
