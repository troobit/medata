#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Tests for the MetaFood3D injected-plane branch (cross-dataset-calibration
// Req 2.1/2.4, Decision 13, spec task 12).
//
// Scene: nadir render geometry — camera at origin looking down −Z, gravity
// (0,0,−1), synthetic support plane at 385 mm (inside the N5k
// CAMERA_TO_PLATE_BAND (250,400)). The food is STEEP-SIDED: a flat-topped
// column 60 mm tall covering the frame centre. The 60 mm edge cliff exceeds
// the 5 mm flood-fill continuity threshold, so the centre-seeded plate-region
// fill can never reach the plane — RANSAC fits the FOOD TOP, and every food
// column then reads ~0 mm tall. The injected authored plane removes the
// failure mode exactly.
@Suite("CalibrateRun injected support plane (MetaFood3D)")
struct InjectedPlaneTests {

    static let w = 100, h = 100
    static let planeMm: Float = 385
    static let foodTopMm: Float = 325          // 60 mm tall column
    static let halfExtentPx = 20               // food spans 41×41 px at the centre

    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: w, imageHeight: h)
    let gravity = Vec3(0, 0, -1)

    static func isFood(_ x: Int, _ y: Int) -> Bool {
        abs(x - 50) <= halfExtentPx && abs(y - 50) <= halfExtentPx
    }

    // Deterministic ±0.3 mm noise on the food top: a perfectly planar
    // synthetic surface is degenerate for the RANSAC refine step
    // (σ_min/σ_max gate — see docs/agent-notes/support-plane-fit.md), and the
    // failure-mode half of this test needs that fit to SUCCEED on the food.
    static func steepFoodDepth(x: Int, y: Int) -> Float {
        guard isFood(x, y) else { return planeMm }
        let noise = Float((x * 31 + y * 17) % 7 - 3) / 10.0
        return foodTopMm + noise
    }

    func makeDepth(_ depthMm: (Int, Int) -> Float) -> DepthMap {
        var bytes = Data(count: Self.w * Self.h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Float.self).baseAddress!
            for y in 0..<Self.h {
                for x in 0..<Self.w {
                    buf[y * Self.w + x] = depthMm(x, y)
                }
            }
        }
        return DepthMap(
            depthBytesMm: bytes,
            confidenceBytes: Data(repeating: 255, count: Self.w * Self.h),
            width: Self.w, height: Self.h, rowStrideBytes: Self.w * 4,
            depthIntrinsics: k, depthFromColour: .identity)
    }

    func makeFixture(id: String, massG: Float) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        fx.estimatorPath = "mixture"
        fx.segmenterCheckpointSha256 = FixtureLoader.sentinelSHA
        fx.nadirDepth = makeDepth(Self.steepFoodDepth).pb
        fx.nadirIntrinsics = k.pb
        fx.gravity = gravity.pb
        fx.groundTruthClassMassG = ["white_rice": massG]
        return fx
    }

    // Integrator-basis expected volume: for two constant-z planes the
    // ray-plane height is exactly 60 mm at every food pixel, and the pixel
    // area at the food top is z²/(fx·fy·cos³θ) — cos³θ ≥ 0.995 over this
    // footprint, so the flat-area product is correct to well under 1%.
    static var expectedVolumeCm3: Float {
        let px = Float(2 * halfExtentPx + 1)
        let heightMm = planeMm - foodTopMm
        let areaMm2 = px * px * (foodTopMm / 500) * (foodTopMm / 500)
        return heightMm * areaMm2 / 1000
    }

    @Test("The plate-region RANSAC fits the food surface on a steep food — the Decision 13 failure mode")
    func plateRegionFitLandsOnFoodSurface() throws {
        let depth = makeDepth(Self.steepFoodDepth)
        let plane = try FixtureRunner.fitPlateRegionPlane(
            depth: depth, intrinsics: k, gravity: gravity, fixtureID: "mf3d_steep")

        // The centre-seeded flood fill cannot cross the 60 mm cliff, so the
        // fitted plane is the FOOD TOP (~325 mm), not the authored 385 mm plane.
        #expect(abs(plane.distanceMm - Self.foodTopMm) <= 3,
                "plane at \(plane.distanceMm) mm; expected the food top ≈ \(Self.foodTopMm) mm")
        #expect(abs(plane.distanceMm - Self.planeMm) >= 30)
    }

    @Test("Without the injected plane a steep food's volume collapses to ~0")
    func refitPathCollapsesSteepFoodVolume() throws {
        let obs = try CalibrateRun.mixtureObservation(
            fixture: makeFixture(id: "mf3d_refit", massG: 100))
        // Integrated above the food-top plane, the food itself has ~0 height
        // and the true plane sits BELOW the fitted one (clamped to 0).
        #expect(obs.totalHullVolumeCm3 < 0.1 * Self.expectedVolumeCm3,
                "refit volume \(obs.totalHullVolumeCm3) cm³ should collapse against the expected \(Self.expectedVolumeCm3) cm³")
    }

    @Test("The injected authored plane yields the correct volume (Decision 13)")
    func injectedPlaneYieldsCorrectVolume() throws {
        let plane = CalibrateRun.authoredSupportPlane(
            gravity: gravity, planeDepthMm: Self.planeMm)
        let obs = try CalibrateRun.mixtureObservation(
            fixture: makeFixture(id: "mf3d_injected", massG: 100),
            injectedSupportPlane: plane)

        let expected = Self.expectedVolumeCm3
        #expect(abs(obs.totalHullVolumeCm3 - expected) <= 0.03 * expected,
                "injected-plane volume \(obs.totalHullVolumeCm3) cm³; expected ≈ \(expected) cm³")
        #expect(obs.massByClassG == ["white_rice": 100])
    }

    @Test("The authored plane matches the harness plane conventions")
    func authoredPlaneConventions() {
        let plane = CalibrateRun.authoredSupportPlane(
            gravity: gravity, planeDepthMm: Self.planeMm)
        // n̂·gravity > 0 (LiDARPlaneFitter orientation), positive distance,
        // zero residual: exact by construction, not fitted.
        #expect(plane.normal.dot(gravity) > 0.99)
        #expect(plane.distanceMm == Self.planeMm)
        #expect(plane.residualMm == 0)
        #expect(plane.convergedIterations == nil)
    }
}
#endif
