import Testing
@testable import MeData

// Pure-state tests for the persistent tilt aim guide. `TiltAimGuideState` carries
// all the per-stage targets, tolerances and the offset/correction maths so the
// SwiftUI host stays untested. Oblique mirrors the live shutter gate exactly
// (|Δθ − 25°| ≤ 15°, closeout-trail Decision 1); nadir's ±12° band is advisory
// (no nadir shutter gate).
@Suite("Tilt aim guide state")
struct TiltAimGuideTests {

    @Test("target axis is 0° nadir / 25° oblique")
    func targetPerStage() {
        #expect(TiltAimGuideState.target(awaitingOblique: false) == 0)
        #expect(TiltAimGuideState.target(awaitingOblique: true) == 25)
    }

    @Test("tolerance is ±12° nadir / ±15° oblique")
    func tolerancePerStage() {
        #expect(TiltAimGuideState.toleranceDegrees(awaitingOblique: false) == 12)
        #expect(TiltAimGuideState.toleranceDegrees(awaitingOblique: true) == 15)
    }

    @Test("offsetFraction maps signed tilt to ±1 and clamps beyond the span")
    func offsetFractionMapsAndClamps() {
        // At target → 0; at ±halfSpan → ±1.
        #expect(TiltAimGuideState.offsetFraction(tilt: 0, target: 0) == 0)
        #expect(TiltAimGuideState.offsetFraction(tilt: 30, target: 0) == 1)
        #expect(TiltAimGuideState.offsetFraction(tilt: -30, target: 0) == -1)
        // Half-way out maps proportionally.
        #expect(TiltAimGuideState.offsetFraction(tilt: 15, target: 0) == 0.5)
        // Beyond the span clamps, never exceeding ±1.
        #expect(TiltAimGuideState.offsetFraction(tilt: 100, target: 0) == 1)
        #expect(TiltAimGuideState.offsetFraction(tilt: -100, target: 25) == -1)
    }

    @Test("isAligned is inclusive at the tolerance edge")
    func isAlignedAtEdges() {
        // Oblique: ±15° around 25° → [10°, 40°] inclusive.
        #expect(TiltAimGuideState.isAligned(tilt: 40, target: 25, tolerance: 15))
        #expect(TiltAimGuideState.isAligned(tilt: 10, target: 25, tolerance: 15))
        #expect(!TiltAimGuideState.isAligned(tilt: 40.01, target: 25, tolerance: 15))
        #expect(!TiltAimGuideState.isAligned(tilt: 9.99, target: 25, tolerance: 15))
        // Nadir: ±12° around 0° → [-12°, 12°] inclusive.
        #expect(TiltAimGuideState.isAligned(tilt: 12, target: 0, tolerance: 12))
        #expect(TiltAimGuideState.isAligned(tilt: -12, target: 0, tolerance: 12))
        #expect(!TiltAimGuideState.isAligned(tilt: 12.5, target: 0, tolerance: 12))
    }

    @Test("correction is 0 in-band, -1 over-tilted, +1 under-tilted")
    func correctionSign() {
        // In-band → no correction.
        #expect(TiltAimGuideState.correction(tilt: 25, target: 25, tolerance: 15) == 0)
        #expect(TiltAimGuideState.correction(tilt: 40, target: 25, tolerance: 15) == 0)
        // Over the target → tilt down toward it.
        #expect(TiltAimGuideState.correction(tilt: 50, target: 25, tolerance: 15) == -1)
        // Under the target → tilt up toward it.
        #expect(TiltAimGuideState.correction(tilt: 0, target: 25, tolerance: 15) == 1)
        // Nadir under-tilt (negative side) → tilt up toward 0.
        #expect(TiltAimGuideState.correction(tilt: -30, target: 0, tolerance: 12) == 1)
    }
}
