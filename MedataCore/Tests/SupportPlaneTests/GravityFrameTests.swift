import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Regression: capture-no-flat-surface-gravity-frame (2026-07-06).
// `ARKitCaptureEngine` passed a world-frame constant (0, −1, 0) as
// `RawFrame.gravity`, but the contract (and `LiDARPlaneFitter`'s ±15° gravity
// gate) needs world-up in the §6.0 camera frame — a pose-dependent value. On a
// nadir capture the table normal sits ~90° from the constant, so RANSAC scored
// zero inliers (`supportplane.end failure=noLidarPoints candidates=1298
// inliers=0` on device) and BOTH capture modes refused with "no flat surface".
//
// These tests pin the conversion (`CameraGravity.worldUpInCameraFrame`) at the
// three poses that matter (identity, nadir, 25° oblique) and demonstrate the
// failure mode end-to-end on a synthetic fronto-parallel table: the fitter
// succeeds with the converted vector and throws with the old constant.
final class GravityFrameTests: XCTestCase {
    // Camera looking straight down (nadir): camera X_r = world X, camera
    // Y_r = world −Z, camera Z_r (backward) = world up. Column-major.
    private let nadirPose = Mat4(columns: [
        [1, 0, 0, 0],
        [0, 0, -1, 0],
        [0, 1, 0, 0],
        [0, 0, 0, 1]
    ])

    func testIdentityPoseMatchesLegacyConstant() {
        // At the identity pose the §6.0-frame world-up happens to equal the old
        // world-frame constant — the coincidence that made the bug read as
        // plausible (and keeps MockCaptureEngine's identity/(0,−1,0) pairing valid).
        let up = CameraGravity.worldUpInCameraFrame(worldFromCamera: .identity)
        XCTAssertEqual(up.x, 0, accuracy: 1e-6)
        XCTAssertEqual(up.y, -1, accuracy: 1e-6)
        XCTAssertEqual(up.z, 0, accuracy: 1e-6)
    }

    func testNadirPoseGivesOpticalAxisUp() {
        // Looking straight down, the table normal points back along the optical
        // axis: +Z in the §6.0 back-projection frame.
        let up = CameraGravity.worldUpInCameraFrame(worldFromCamera: nadirPose)
        XCTAssertEqual(up.x, 0, accuracy: 1e-6)
        XCTAssertEqual(up.y, 0, accuracy: 1e-6)
        XCTAssertEqual(up.z, 1, accuracy: 1e-6)
    }

    func testObliquePoseTiltsTowardImageTop() {
        // Nadir pose pitched 25° about the camera X axis (the two-view oblique
        // stage). World-up gains a −Y (image-up) component of sin 25° while the
        // optical-axis component drops to cos 25°.
        let theta: Float = 25 * .pi / 180
        let oblique = Mat4(columns: [
            [1, 0, 0, 0],
            [0, sin(theta), -cos(theta), 0],
            [0, cos(theta), sin(theta), 0],
            [0, 0, 0, 1]
        ])
        let up = CameraGravity.worldUpInCameraFrame(worldFromCamera: oblique)
        XCTAssertEqual(up.x, 0, accuracy: 1e-6)
        XCTAssertEqual(up.y, -sin(theta), accuracy: 1e-6)
        XCTAssertEqual(up.z, cos(theta), accuracy: 1e-6)
    }

    // End-to-end failure-mode demonstration on a synthetic near-fronto-parallel
    // table (the nadir-capture geometry from the device logs): the fit succeeds
    // with the pose-derived gravity and throws `noLidarPoints` (zero RANSAC
    // inliers — every iteration rejected by the gravity gate) with the legacy
    // world-frame constant.
    func testFitterAcceptsConvertedGravityAndRejectsLegacyConstant() throws {
        // Slight tilt keeps the inlier covariance non-singular (an exactly
        // constant-depth plane has a zero smallest singular value and trips the
        // stability gate instead).
        let trueNormal = Vec3(0.06, 0.04, 1).normalised()
        let depth = syntheticPlane(normal: trueNormal, distanceMm: -400)
        let mask = centredMask()

        let plane = try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: colourIntrinsics,
            foodRegionMask: mask,
            gravityCamera: trueNormal   // ≈ worldUpInCameraFrame(nadir pose)
        ))
        XCTAssertGreaterThan(plane.normal.dot(trueNormal), 0.999)

        XCTAssertThrowsError(try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: colourIntrinsics,
            foodRegionMask: mask,
            gravityCamera: Vec3(0, -1, 0)   // legacy world-frame constant
        ))) { error in
            XCTAssertEqual(error as? SupportPlaneError, .noLidarPoints)
        }
    }

    // MARK: – fixture helpers (same construction as LiDARPlaneFitterTests)

    private let colourIntrinsics = CameraIntrinsics(
        fx: 1500, fy: 1500, cx: 320, cy: 240,
        distortion: [], imageWidth: 640, imageHeight: 480
    )

    private func syntheticPlane(normal: Vec3, distanceMm dPlane: Float,
                                width w: Int = 64, height h: Int = 48) -> DepthMap {
        let kd = CameraIntrinsics(
            fx: colourIntrinsics.fx * Float(w) / Float(colourIntrinsics.imageWidth),
            fy: colourIntrinsics.fy * Float(h) / Float(colourIntrinsics.imageHeight),
            cx: colourIntrinsics.cx * Float(w) / Float(colourIntrinsics.imageWidth),
            cy: colourIntrinsics.cy * Float(h) / Float(colourIntrinsics.imageHeight),
            distortion: [], imageWidth: w, imageHeight: h
        )
        var depthBytes = Data(count: w * h * 4)
        let n = normal.normalised()
        depthBytes.withUnsafeMutableBytes { rawPtr -> Void in
            let buf = rawPtr.bindMemory(to: Float.self)
            for y in 0..<h {
                for x in 0..<w {
                    // Ray in §6.0 (−Z forward): (dirX, dirY, −1); plane n·(t·dir) = d.
                    let dirX = (Float(x) - kd.cx) / kd.fx
                    let dirY = (Float(y) - kd.cy) / kd.fy
                    let denom = n.x * dirX + n.y * dirY + n.z * -1
                    let t = dPlane / denom
                    buf[y * w + x] = -(t * -1)   // depth = −p.z, positive mm
                }
            }
        }
        return DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: Data(repeating: 255, count: w * h),
            width: w, height: h, rowStrideBytes: w * 4,
            depthIntrinsics: kd,
            depthFromColour: .identity
        )
    }

    private func centredMask() -> BinaryMask {
        let w = colourIntrinsics.imageWidth, h = colourIntrinsics.imageHeight
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 200..<320 {
            for x in 250..<390 {
                pixels[y * w + x] = 1
            }
        }
        return BinaryMask(pixels: pixels, width: w, height: h)
    }
}
