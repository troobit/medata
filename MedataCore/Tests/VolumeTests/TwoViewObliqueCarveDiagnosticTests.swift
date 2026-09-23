import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Characterisation tests for two-view carve photo-consistency (investigation:
// specs/bugfixes/two-view-carve-no-volume/).
//
// Two-view voxel carving owns a voxel only if it projects to food in BOTH views.
// The dev-stub (StubInferenceEngine) paints its food ellipse at the IMAGE CENTRE in
// every view regardless of camera pose, so the two silhouettes only describe the same
// 3-D object when the oblique camera is physically aimed at the food. These tests pin
// that behaviour: a well-aimed oblique recovers volume; a mis-aimed (tilted-in-place)
// oblique correctly recovers nothing. The device's two-view `noFoodVolumeRecovered` is
// the mis-aimed case (oblique tilt stuck outside the arming window), NOT a carve defect.
final class TwoViewObliqueCarveDiagnosticTests: XCTestCase {

    let palette = makePalette(numFood: 2)
    let intrinsics = CameraIntrinsics(
        fx: 500, fy: 500, cx: 50, cy: 50,
        distortion: [], imageWidth: 100, imageHeight: 100
    )
    // n̂=(0,0,1), table at z=−400 mm. Gravity = (0,0,−1) so axisZ = (0,0,1).
    let plane = SupportPlane(
        normal: Vec3(0, 0, 1), distanceMm: -400, residualMm: 0.5, convergedIterations: nil
    )

    // Centred ellipse in image space (α = 0.618, matching StubInferenceEngine).
    private func centredEllipseProbs() -> ProbabilityTensor {
        let bgId = palette.background
        let cx: Float = 50, cy: Float = 50
        let r: Float = 0.618 * 50
        return makeProbTensor(width: 100, height: 100, palette: palette) { y, x, c in
            let dx = (Float(x) + 0.5 - cx) / r
            let dy = (Float(y) + 0.5 - cy) / r
            let inside = (dx * dx + dy * dy) <= 1
            if inside { return c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025) }
            return c == bgId ? 0.99 : 0.0025
        }
    }

    private func centredEllipseMask() -> BinaryMask {
        let cx: Float = 50, cy: Float = 50
        let r: Float = 0.618 * 50
        return makeBinaryMask(width: 100, height: 100) { y, x in
            let dx = (Float(x) + 0.5 - cx) / r
            let dy = (Float(y) + 0.5 - cy) / r
            return (dx * dx + dy * dy) <= 1
        }
    }

    // transform1To2 for an oblique camera orbited θ about +X through the food
    // point F=(0,0,−400): T(F)·R_x(−θ)·T(−F). p₂ = M·p₁. Optical axis stays on food.
    private func wellAimedTransform(degrees: Float) -> Mat4 {
        let t = degrees * .pi / 180
        let c = cos(t), s = sin(t)
        let f: Float = -400
        let ty = -(s * f)        // F.y − (R·F).y, F.y = 0
        let tz = f - (c * f)     // F.z − (R·F).z
        return Mat4(columns: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, ty, tz, 1]])
    }

    // transform1To2 for an oblique camera tilted θ about its OWN origin (no re-aim):
    // pure rotation R_x(−θ). The optical axis swings off the food.
    private func misAimedTransform(degrees: Float) -> Mat4 {
        let t = degrees * .pi / 180
        let c = cos(t), s = sin(t)
        return Mat4(columns: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])
    }

    private func carve(transform: Mat4) throws -> VoxelCarveEstimate {
        let probs = centredEllipseProbs()
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: centredEllipseMask(),
            nadirIntrinsics: intrinsics,
            supportPlane: plane,
            gravityCamera: Vec3(0, 0, -1)
        ))
        let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: probs, intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: probs, intrinsics: intrinsics),
            transform1To2: transform,
            supportPlane: plane,
            matchedClasses: [0],
            singleViewOnlyClassesView1: [],
            singleViewOnlyClassesView2: [],
            beta: BetaCorrection(),
            palette: palette
        ))
        if let refusal = outcome.refusal { throw refusal }
        return try XCTUnwrap(outcome.estimate)
    }

    // Coincident cameras → world-consistent silhouettes → healthy volume.
    func testIdentityTransformRecoversVolume() throws {
        let vol = try carve(transform: .identity).perClassVolumesCm3["food_0"] ?? 0
        XCTAssertGreaterThan(vol, 0, "coincident views must recover a volume")
    }

    // Oblique aimed at the food → silhouettes still overlap → volume recovered
    // (reduced by the narrower frustum intersection, but non-zero).
    func testWellAimedObliqueRecoversVolume() throws {
        let vol = try carve(transform: wellAimedTransform(degrees: 25)).perClassVolumesCm3["food_0"] ?? 0
        XCTAssertGreaterThan(vol, 0, "an oblique aimed at the food must still recover a volume")
    }

    // Oblique tilted in place (the device's stuck-tilt failure) → image-centred
    // silhouettes describe different world regions → carve correctly recovers nothing.
    func testMisAimedObliqueRecoversNoVolume() throws {
        for deg in [Float(46), 57] {
            XCTAssertThrowsError(try carve(transform: misAimedTransform(degrees: deg))) { error in
                XCTAssertEqual(error as? VolumeError, .noFoodVolumeRecovered,
                    "mis-aimed oblique at \(deg)° must refuse with noFoodVolumeRecovered")
            }
        }
    }
}
