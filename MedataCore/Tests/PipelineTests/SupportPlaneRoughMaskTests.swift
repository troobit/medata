import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing
@testable import Pipeline

// Regression coverage for the bugfix at
// `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/`. Two test cases
// share the same synthetic depth fixture (a gravity-aligned table at d = 200 mm
// with a closer "plate" patch in the centre):
//   (a) with an all-ones mask, `LiDARPlaneFitter.fit` throws `noLidarPoints` —
//       the pre-fix behaviour, encoded as a sentinel so the regression cannot
//       silently return.
//   (b) with the centre-rectangle mask from `makeCentreRectangleMask`, the fit
//       returns a finite plane within `gravityAngleMaxRad` of the synthesised
//       gravity vector and below `LiDARPlaneFitter.residualMaxMm`.
@Suite("Pipeline rough-mask regression (lidarFitDegenerate bugfix)")
struct SupportPlaneRoughMaskTests {

    @Test("all-ones mask throws SupportPlaneError.noLidarPoints (regression sentinel)")
    func allOnesMaskReproducesNoLidarPoints() throws {
        let fixture = Self.makeFixture()
        let allOnes = BinaryMask(
            pixels: [UInt8](repeating: 1, count: fixture.width * fixture.height),
            width: fixture.width,
            height: fixture.height
        )
        do {
            _ = try LiDARPlaneFitter.fit(.init(
                depth: fixture.depth,
                colourIntrinsics: fixture.intrinsics,
                foodRegionMask: allOnes,
                gravityCamera: fixture.gravity
            ))
            Issue.record("expected noLidarPoints; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .noLidarPoints,
                    "expected noLidarPoints; got \(error)")
        }
    }

    @Test("centre-rectangle mask yields a finite gravity-aligned plane")
    func centreRectangleMaskFitsTablePlane() throws {
        let fixture = Self.makeFixture()
        let mask = makeCentreRectangleMask(
            width: fixture.width,
            height: fixture.height,
            fillFraction: centreRectangleFillFraction
        )
        let plane = try LiDARPlaneFitter.fit(.init(
            depth: fixture.depth,
            colourIntrinsics: fixture.intrinsics,
            foodRegionMask: mask,
            gravityCamera: fixture.gravity
        ))
        let cosAngle = plane.normal.dot(fixture.gravity)
        let angleRad = acos(max(-1, min(1, cosAngle)))
        #expect(angleRad <= LiDARPlaneFitter.gravityAngleMaxRad,
                "plane normal off-gravity by \(angleRad) rad")
        #expect(plane.residualMm.isFinite, "residual should be finite")
        #expect(plane.residualMm < LiDARPlaneFitter.residualMaxMm,
                "residual \(plane.residualMm) mm exceeds \(LiDARPlaneFitter.residualMaxMm) mm cap")
    }

    // MARK: - Fixture

    private struct Fixture {
        let depth: DepthMap
        let intrinsics: CameraIntrinsics
        let gravity: Vec3
        let width: Int
        let height: Int
    }

    // 64×64 colour/depth grid, principal point at (32, 32). The synthesised
    // surface is a table at d = 200 mm tilted 3° from gravity so the SVD
    // stability gate (σ_min/σ_max ≥ 1e-6) is not tripped by a perfectly
    // degenerate y axis, with a closer "plate" patch (d = 150 mm) over the
    // centre 70%×70% region — the plate is present so the fixture reflects
    // real-world geometry, even though the regression-test assertions ride on
    // the band *below* the plate where the depth tracks the table plane.
    private static func makeFixture() -> Fixture {
        let w = 64, h = 64
        let intrinsics = CameraIntrinsics(
            fx: 200, fy: 200, cx: 32, cy: 32,
            distortion: [], imageWidth: w, imageHeight: h
        )
        let gravity = Vec3(0, 1, 0)
        let tiltRad: Float = 3 * .pi / 180
        let nTable = Vec3(sin(tiltRad), cos(tiltRad), 0)
        let tableD: Float = 200
        let plateD: Float = 150
        // Inner rectangle [10, 54) × [10, 54) for fillFraction = 0.7 on 64×64.
        let plateXRange = 10..<54
        let plateYRange = 10..<54
        var depthBytes = Data(count: w * h * 4)
        depthBytes.withUnsafeMutableBytes { rawPtr in
            let buf = rawPtr.bindMemory(to: Float.self)
            for y in 0..<h {
                let dirY = (Float(y) - intrinsics.cy) / intrinsics.fy
                for x in 0..<w {
                    let dirX = (Float(x) - intrinsics.cx) / intrinsics.fx
                    let isPlate = plateXRange.contains(x) && plateYRange.contains(y)
                    if isPlate {
                        buf[y * w + x] = plateD
                    } else {
                        let denom = nTable.x * dirX + nTable.y * dirY
                        if denom > 0 {
                            // Plane intersection at t = d / (n · dir); depth
                            // = -p.z = t under §6.0 −Z-forward. Add a sub-mm
                            // deterministic perturbation so the SVD stability
                            // gate (σ_min/σ_max ≥ 1e-6) does not reject the
                            // perfectly coplanar synthetic.
                            let jitter = sin(Float(y) * 0.7 + Float(x) * 0.3) * 0.2
                            buf[y * w + x] = tableD / denom + jitter
                        } else {
                            // Above the horizon the table plane is behind the
                            // camera; mark invalid (filtered by zMm ≤ 0).
                            buf[y * w + x] = 0
                        }
                    }
                }
            }
        }
        let depth = DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: Data(repeating: 255, count: w * h),
            width: w, height: h, rowStrideBytes: w * 4,
            depthIntrinsics: intrinsics,
            depthFromColour: .identity
        )
        return Fixture(depth: depth, intrinsics: intrinsics,
                       gravity: gravity, width: w, height: h)
    }
}
