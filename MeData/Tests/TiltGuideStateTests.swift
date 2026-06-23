import Testing
@testable import MeData

// Pure-state tests for the persistent tilt guide. `TiltGuideState` carries the
// per-stage targets, tolerances and the in-range test so the SwiftUI host stays
// untested. Oblique mirrors the live shutter gate exactly (|Δθ − 25°| ≤ 15°,
// closeout-trail Decision 1); nadir's ±12° band is advisory (no nadir shutter
// gate).
@Suite("Tilt guide state")
struct TiltGuideStateTests {

    @Test("target axis is 0° nadir / 25° oblique")
    func targetPerStage() {
        #expect(TiltGuideState.target(awaitingOblique: false) == 0)
        #expect(TiltGuideState.target(awaitingOblique: true) == 25)
    }

    @Test("tolerance is ±12° nadir / ±15° oblique")
    func tolerancePerStage() {
        #expect(TiltGuideState.toleranceDegrees(awaitingOblique: false) == 12)
        #expect(TiltGuideState.toleranceDegrees(awaitingOblique: true) == 15)
    }

    @Test("isAligned is inclusive at the tolerance edge")
    func isAlignedAtEdges() {
        // Oblique: ±15° around 25° → [10°, 40°] inclusive.
        #expect(TiltGuideState.isAligned(tilt: 40, target: 25, tolerance: 15))
        #expect(TiltGuideState.isAligned(tilt: 10, target: 25, tolerance: 15))
        #expect(!TiltGuideState.isAligned(tilt: 40.01, target: 25, tolerance: 15))
        #expect(!TiltGuideState.isAligned(tilt: 9.99, target: 25, tolerance: 15))
        // Nadir: ±12° around 0° → [-12°, 12°] inclusive.
        #expect(TiltGuideState.isAligned(tilt: 12, target: 0, tolerance: 12))
        #expect(TiltGuideState.isAligned(tilt: -12, target: 0, tolerance: 12))
        #expect(!TiltGuideState.isAligned(tilt: 12.5, target: 0, tolerance: 12))
    }
}
