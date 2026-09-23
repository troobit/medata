import CaptureKit
import PortableContracts
import XCTest
@testable import CardDetection

// Task 10: ID-1 P4P card-pose recovery (§6.1).
// Synthesises known card poses, projects the four corners through the camera, then
// asserts the solver recovers translation/rotation within tolerance, and that the
// documented refusal paths fire on the right inputs.

private let intrinsics = CameraIntrinsics(
    fx: 1500, fy: 1500, cx: 2016, cy: 1512,
    distortion: [], imageWidth: 4032, imageHeight: 3024
)

// Build a column-major 3×3 rotation that yaws by `yaw` (about Y), then pitches by
// `pitch` (about X). Right-handed, +X right, +Y up, -Z forward (per §6.0).
private func rotation(yaw: Float, pitch: Float) -> [Float] {
    let cy = cos(yaw),  sy = sin(yaw)
    let cp = cos(pitch), sp = sin(pitch)
    // Ry(yaw) · Rx(pitch), column-major.
    let r00 = cy
    let r01: Float = 0
    let r02 = sy
    let r10 = sp * sy
    let r11 = cp
    let r12 = -sp * cy
    let r20 = -cp * sy
    let r21 = sp
    let r22 = cp * cy
    // Column-major flat: col k starts at index k*3.
    return [r00, r10, r20,   // col 0
            r01, r11, r21,   // col 1
            r02, r12, r22]   // col 2
}

private func project(_ p: Vec3, _ k: CameraIntrinsics) -> PixelCorner {
    // -Z forward; valid only for p.z < 0.
    let denom = -p.z
    let u = k.fx * p.x / denom + k.cx
    let v = k.fy * p.y / denom + k.cy
    return PixelCorner(u, v)
}

private func projectCard(rotation r: [Float], translation t: Vec3, k: CameraIntrinsics) -> [PixelCorner] {
    return ISO7810.cornersMm.map { (mx, my) in
        let X = Vec3(mx, my, 0)
        let pCam = CardPoseSolver.applyR(r, to: X) + t
        return project(pCam, k)
    }
}

final class CardPoseSolverTests: XCTestCase {
    // ----- Recovery accuracy -----

    func testRecoversFrontoParallelCard() throws {
        // Card sits 300 mm in front of camera, fronto-parallel, centred.
        let r = rotation(yaw: 0, pitch: 0)
        let t = Vec3(-ISO7810.widthMm / 2, -ISO7810.heightMm / 2, -300)
        let corners = projectCard(rotation: r, translation: t, k: intrinsics)
        let pose = try CardPoseSolver.solve(corners: corners, intrinsics: intrinsics)
        XCTAssertEqual(pose.translationMm.x, t.x, accuracy: 0.5)
        XCTAssertEqual(pose.translationMm.y, t.y, accuracy: 0.5)
        XCTAssertEqual(pose.translationMm.z, t.z, accuracy: 0.5)
        XCTAssertLessThan(pose.pnpResidualPx, 1.5)
    }

    // §7.1: perturb image points by ≤1 px noise; assert recovered translation < 2 mm error.
    // Pose chosen near nadir (Req 3.2 target ±5° of vertical) so this matches actual
    // capture conditions rather than a worst-case oblique view.
    func testTranslationStableUnder1PxNoise() throws {
        let r = rotation(yaw: 0.05, pitch: -0.05)
        let t = Vec3(20, -10, -350)
        let cleanCorners = projectCard(rotation: r, translation: t, k: intrinsics)
        // Add ≤1 px L2 perturbation (alternating sign, max |dx|+|dy| < 1).
        let noisy: [PixelCorner] = cleanCorners.enumerated().map { i, c in
            let dx: Float = (i % 2 == 0) ? 0.7 : -0.7
            let dy: Float = (i < 2) ? 0.7 : -0.7
            return PixelCorner(c.u + dx, c.v + dy)
        }
        let pose = try CardPoseSolver.solve(corners: noisy, intrinsics: intrinsics)
        let dx = pose.translationMm.x - t.x
        let dy = pose.translationMm.y - t.y
        let dz = pose.translationMm.z - t.z
        let err = (dx * dx + dy * dy + dz * dz).squareRoot()
        XCTAssertLessThan(err, 2.0, "translation error \(err) mm should be <2 mm under ≤1 px noise")
    }

    // ----- Sign-of-λ enforcement (M3) -----

    func testSignOfLambdaFlipsForBehindCameraSolve() throws {
        // The DLT/SVD step gives h up to ±sign. We construct a normal pose; if the
        // implementation didn't flip the sign of λ when needed, t.z would land ≥ 0.
        let r = rotation(yaw: 0.4, pitch: 0.3)
        let t = Vec3(-30, 25, -420)
        let corners = projectCard(rotation: r, translation: t, k: intrinsics)
        let pose = try CardPoseSolver.solve(corners: corners, intrinsics: intrinsics)
        XCTAssertLessThan(pose.translationMm.z, 0, "card must end up in front of camera per §6.0")
    }

    func testDegenerateCardPoseWhenAllCornersCollinear() {
        // Four collinear corners: rank-deficient H, smallest σ ratio → 0 → degenerate.
        let degenerateCorners = [
            PixelCorner(100, 100),
            PixelCorner(200, 100),
            PixelCorner(300, 100),
            PixelCorner(400, 100)
        ]
        XCTAssertThrowsError(try CardPoseSolver.solve(corners: degenerateCorners, intrinsics: intrinsics)) { err in
            XCTAssertEqual(err as? CardPoseError, .degenerateCardPose)
        }
    }

    // ----- SO(3) projection (det(UV^T) fix-up) -----

    func testRecoveredRotationIsProperRotation() throws {
        // R^T·R must be identity and det(R) must be +1 (right-handed). This validates
        // step 6's diag(1,1,det(UV^T)) fix-up — without it, det(R) could land at -1.
        let r = rotation(yaw: 0.35, pitch: 0.25)
        let t = Vec3(15, 10, -380)
        let corners = projectCard(rotation: r, translation: t, k: intrinsics)
        let pose = try CardPoseSolver.solve(corners: corners, intrinsics: intrinsics)

        let rt = LinearAlgebra.transpose3x3(pose.rotationColumnMajor)
        let rtR = LinearAlgebra.mul3x3(rt, pose.rotationColumnMajor)
        // diag entries ≈ 1, off-diagonals ≈ 0.
        XCTAssertEqual(rtR[0], 1, accuracy: 1e-4)
        XCTAssertEqual(rtR[4], 1, accuracy: 1e-4)
        XCTAssertEqual(rtR[8], 1, accuracy: 1e-4)
        XCTAssertEqual(rtR[1], 0, accuracy: 1e-4)
        XCTAssertEqual(rtR[3], 0, accuracy: 1e-4)
        XCTAssertEqual(rtR[5], 0, accuracy: 1e-4)
        XCTAssertEqual(LinearAlgebra.det3x3(pose.rotationColumnMajor), 1, accuracy: 1e-4)
    }

    // ----- cardTooOblique refusal (edge-case 1) -----

    func testCardTooObliqueRefusalAtSteepAngle() throws {
        // Yaw the card ~85° about Y so the surface normal is almost perpendicular to the
        // optical axis (|r3·ẑ_cam| = |r3.z| < 0.2). Solver must throw cardTooOblique.
        let yaw: Float = 1.45 // ~83°; cos(yaw)≈0.12 < 0.2
        let r = rotation(yaw: yaw, pitch: 0)
        let t = Vec3(0, -ISO7810.heightMm / 2, -250)
        let corners = projectCard(rotation: r, translation: t, k: intrinsics)
        XCTAssertThrowsError(try CardPoseSolver.solve(corners: corners, intrinsics: intrinsics)) { err in
            XCTAssertEqual(err as? CardPoseError, .cardTooOblique)
        }
    }

    // ----- Scale at card plane -----

    func testScaleAtCardPlaneMatchesAnalyticalForFrontoParallel() throws {
        // For a fronto-parallel card at depth z (mm), s_card,init = z / fx (mm/px).
        let z: Float = -300
        let r = rotation(yaw: 0, pitch: 0)
        let t = Vec3(-ISO7810.widthMm / 2, -ISO7810.heightMm / 2, z)
        let corners = projectCard(rotation: r, translation: t, k: intrinsics)
        let pose = try CardPoseSolver.solve(corners: corners, intrinsics: intrinsics)
        let expected: Float = -z / intrinsics.fx
        XCTAssertEqual(pose.scaleAtCardPlaneMmPerPx, expected, accuracy: 5e-3)
    }

    // ----- Wrong corner count -----

    func testWrongCornerCountThrows() {
        XCTAssertThrowsError(
            try CardPoseSolver.solve(corners: [PixelCorner(0, 0)], intrinsics: intrinsics)
        ) { err in
            XCTAssertEqual(err as? CardPoseError, .wrongCornerCount)
        }
    }
}
