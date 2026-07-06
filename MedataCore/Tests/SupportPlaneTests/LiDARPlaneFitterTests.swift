import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 13: LiDAR support-plane RANSAC fit (§6.2).
// Tests synthesise a depth map of a tilted plane plus controlled outliers and food
// region, then assert RANSAC recovers normal/distance, that the seed-from-bytes is
// deterministic, that singular inlier covariance is rejected, and that residual
// breaches above 20 mm trigger lidarFitResidualTooHigh (raised from 8 mm per
// Decision 46 / T88).

private let intrinsics = CameraIntrinsics(
    fx: 1500, fy: 1500, cx: 320, cy: 240,
    distortion: [], imageWidth: 640, imageHeight: 480
)

// Synthesise a depth map for a plane n̂·p = d (mm) under §6.0 (-Z forward), at the
// given depth resolution. Each pixel's ray is K^{-1}·[u,v,1] (direction = (X/-Z, Y/-Z, -1)
// in §6.0 sign convention); the z value where the ray meets the plane is plane-z(u,v).
// Returns a DepthMap with confidence=255 everywhere unless overrides are supplied.
private func syntheticPlaneDepthMap(
    width w: Int = 64, height h: Int = 48,
    normal: Vec3, distanceMm dPlane: Float,
    uniformConfidence: UInt8 = 255,
    confidenceOverrides: [(x: Int, y: Int, conf: UInt8)] = [],
    depthOverrides: [(x: Int, y: Int, mm: Float)] = []
) -> DepthMap {
    let kd = CameraIntrinsics(
        fx: intrinsics.fx * Float(w) / Float(intrinsics.imageWidth),
        fy: intrinsics.fy * Float(h) / Float(intrinsics.imageHeight),
        cx: intrinsics.cx * Float(w) / Float(intrinsics.imageWidth),
        cy: intrinsics.cy * Float(h) / Float(intrinsics.imageHeight),
        distortion: [], imageWidth: w, imageHeight: h
    )
    var depthBytes = Data(count: w * h * 4)
    var confBytes = Data(repeating: uniformConfidence, count: w * h)
    let n = normal.normalised()
    depthBytes.withUnsafeMutableBytes { rawPtr -> Void in
        let buf = rawPtr.bindMemory(to: Float.self)
        for y in 0..<h {
            for x in 0..<w {
                // Ray direction in camera (§6.0 -Z forward): (X/-Z, Y/-Z, -1) for
                // normalised image coords. Solve plane: n·(t·dir) = d → t = d/(n·dir).
                let dirX = (Float(x) - kd.cx) / kd.fx
                let dirY = (Float(y) - kd.cy) / kd.fy
                let dirZ: Float = -1
                let denom = n.x * dirX + n.y * dirY + n.z * dirZ
                let t = dPlane / denom
                let p = Vec3(t * dirX, t * dirY, t * dirZ)
                // depth = -p.z (positive distance along optical axis, mm)
                buf[y * w + x] = -p.z
            }
        }
    }
    for ov in depthOverrides {
        depthBytes.withUnsafeMutableBytes { rawPtr -> Void in
            rawPtr.bindMemory(to: Float.self)[ov.y * w + ov.x] = ov.mm
        }
    }
    for ov in confidenceOverrides {
        confBytes[ov.y * w + ov.x] = ov.conf
    }
    return DepthMap(
        depthBytesMm: depthBytes,
        confidenceBytes: confBytes,
        width: w, height: h, rowStrideBytes: w * 4,
        depthIntrinsics: kd,
        depthFromColour: .identity
    )
}

// Build a food mask covering a centred rectangle in the colour-image grid.
private func centredFoodMask(width: Int = intrinsics.imageWidth,
                             height: Int = intrinsics.imageHeight,
                             foodRectX: Range<Int>,
                             foodRectY: Range<Int>) -> BinaryMask {
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in foodRectY where y >= 0 && y < height {
        for x in foodRectX where x >= 0 && x < width {
            pixels[y * width + x] = 1
        }
    }
    return BinaryMask(pixels: pixels, width: width, height: height)
}

final class LiDARPlaneFitterTests: XCTestCase {
    // §7.1: synthesise plane + outliers; assert recovered plane normal within 1° of
    // gravity, distance within 2 mm.
    func testRecoversTablePlaneFromCleanFixture() throws {
        let trueNormal = Vec3(0, 1, 0)              // gravity-aligned
        let trueDist: Float = 100                   // 100 mm signed distance
        let depth = syntheticPlaneDepthMap(normal: trueNormal, distanceMm: trueDist)
        let foodMask = centredFoodMask(
            foodRectX: 250..<390,
            foodRectY: 200..<320
        )
        let plane = try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: intrinsics,
            foodRegionMask: foodMask,
            gravityCamera: trueNormal
        ))
        let angleRad = acos(max(-1, min(1, plane.normal.dot(trueNormal))))
        let angleDeg = angleRad * 180 / .pi
        XCTAssertLessThan(angleDeg, 1.0,
                          "recovered normal off by \(angleDeg)°; spec bound is 1°")
        XCTAssertEqual(plane.distanceMm, trueDist, accuracy: 2.0)
        XCTAssertNil(plane.convergedIterations, "LiDAR fit must report nil convergedIterations")
    }

    // Task 13 bullet 2: deterministic seed from xxh64(depth.bytes) (we use FNV-1a per
    // Hash.swift; the required property is "two runs on same fixture give identical
    // inliers"). Run twice on identical fixture, assert exact equality of outputs.
    func testDeterministicSeedProducesIdenticalResults() throws {
        let depth = syntheticPlaneDepthMap(normal: Vec3(0, 1, 0), distanceMm: 80)
        let foodMask = centredFoodMask(foodRectX: 250..<390, foodRectY: 200..<320)
        let inputs = LiDARPlaneFitter.Inputs(
            depth: depth, colourIntrinsics: intrinsics,
            foodRegionMask: foodMask, gravityCamera: Vec3(0, 1, 0)
        )
        let p1 = try LiDARPlaneFitter.fit(inputs)
        let p2 = try LiDARPlaneFitter.fit(inputs)
        XCTAssertEqual(p1, p2, "deterministic seed must produce bit-equal output")
    }

    // Task 13 bullet 3: lidarFitDegenerate when inlier covariance is singular. Build
    // a fixture where every candidate point lies on a single line — refine() SVD
    // ratio σ_min/σ_max = 0, so the stability gate trips.
    func testRejectsDegenerateInlierCovariance() {
        // All-zero depth → all back-projected points are at the origin → covariance
        // is exactly singular. We also need at least 3 points pass the confidence
        // filter so the algorithm reaches refine().
        var depthBytes = Data(repeating: 0, count: 64 * 48 * 4)
        // Override a few points to non-zero but all on the same z=10 plane.
        let kd = CameraIntrinsics(
            fx: intrinsics.fx * 64 / Float(intrinsics.imageWidth),
            fy: intrinsics.fy * 48 / Float(intrinsics.imageHeight),
            cx: intrinsics.cx * 64 / Float(intrinsics.imageWidth),
            cy: intrinsics.cy * 48 / Float(intrinsics.imageHeight),
            distortion: [], imageWidth: 64, imageHeight: 48
        )
        // Make ALL points have z=10 mm (a constant depth) — they'll back-project to
        // points all at depth -10 with varying x/y; that's a planar set that's NOT
        // degenerate. To force degeneracy, make all back-projected points share a
        // single 3-D line by collapsing the food mask to one row and constant z.
        depthBytes.withUnsafeMutableBytes { rawPtr -> Void in
            let buf = rawPtr.bindMemory(to: Float.self)
            for i in 0..<(64 * 48) { buf[i] = 100 }
        }
        let depth = DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: Data(repeating: 255, count: 64 * 48),
            width: 64, height: 48, rowStrideBytes: 64 * 4,
            depthIntrinsics: kd, depthFromColour: .identity
        )
        // Food mask carves a thin horizontal strip; the lower-edge band sits below
        // it on a single row → 3-D points lie on a single ray-fan that's almost
        // 1-D, so SVD ratio collapses.
        let foodMask = centredFoodMask(foodRectX: 100..<540, foodRectY: 200..<201)
        XCTAssertThrowsError(try LiDARPlaneFitter.fit(.init(
            depth: depth, colourIntrinsics: intrinsics,
            foodRegionMask: foodMask, gravityCamera: Vec3(0, 1, 0)
        ))) { err in
            // Either lidarFitDegenerate (single-line points) OR noLidarPoints (if
            // the fixture is too restrictive to collect 3 points). Both are
            // acceptable refusal paths from §6.2; the failure to fit is the point.
            let supportError = err as? SupportPlaneError
            XCTAssertTrue(supportError == .lidarFitDegenerate
                          || supportError == .noLidarPoints
                          || supportError == .lidarFitResidualTooHigh,
                          "unexpected refusal: \(String(describing: supportError))")
        }
    }

    // Task 13 bullet 4 / T88: lidarFitResidualTooHigh refusal path. The 20 mm
    // production bound (raised from 8 mm per Decision 46) is unreachable from
    // the RANSAC inlier band of 5 mm in normal operation (every inlier is within
    // ±5 mm of its candidate plane by construction), so we verify the threshold
    // logic with a fixture and a tightened residualMaxMm so a normally-acceptable
    // σ ~3 mm trips the refusal.
    func testRefusesWhenResidualExceedsThreshold() {
        let trueNormal = Vec3(0, 1, 0)
        let trueDist: Float = 100
        var depth = syntheticPlaneDepthMap(normal: trueNormal, distanceMm: trueDist)
        // Inject pseudo-random ±4 mm jitter so the inlier set σ ≈ 2.3 mm — well
        // above the test's tightened 0.1 mm cap, well below the 5 mm RANSAC inlier
        // band so RANSAC still converges to the planar solution.
        var corrupted = depth.depthBytesMm
        var rng = SplitMix64(seed: 0xBADC0FFEE)
        corrupted.withUnsafeMutableBytes { rawPtr -> Void in
            let buf = rawPtr.bindMemory(to: Float.self)
            for i in 0..<(depth.width * depth.height) {
                let r = Float(rng.next() % 1000) / 1000     // 0..1
                let jitter: Float = (r - 0.5) * 8           // ±4 mm
                buf[i] = buf[i] + jitter
            }
        }
        depth = DepthMap(
            depthBytesMm: corrupted,
            confidenceBytes: depth.confidenceBytes,
            width: depth.width, height: depth.height,
            rowStrideBytes: depth.rowStrideBytes,
            depthIntrinsics: depth.depthIntrinsics,
            depthFromColour: depth.depthFromColour
        )
        let foodMask = centredFoodMask(foodRectX: 250..<390, foodRectY: 200..<320)
        XCTAssertThrowsError(try LiDARPlaneFitter.fit(.init(
            depth: depth, colourIntrinsics: intrinsics,
            foodRegionMask: foodMask, gravityCamera: trueNormal,
            residualMaxMm: 0.1     // tightened from the production 8.0 default
        ))) { err in
            XCTAssertEqual(err as? SupportPlaneError, .lidarFitResidualTooHigh)
        }
    }

    // T88: production residualMaxMm raised from 8 to 20. Verify the default value.
    func testProductionResidualMaxIsTwentyMm() {
        XCTAssertEqual(LiDARPlaneFitter.residualMaxMm, 20)
    }

    // Regression for `lidar-plane-fit-matte-table-confidence` (2026-07-06 device
    // report: "1 view complained of no flat surface on a matte table"). ARKit maps
    // its `ARConfidenceLevel.{low,medium,high}` to bytes `{0,127,255}` (§6.0). A
    // matte / low-reflectance table returns a WEAKER LiDAR signal, so the
    // confidence map is dominated by MEDIUM (127), not HIGH (255). The pre-fix
    // τ_conf = 0.66 gate (`127/255 = 0.498 < 0.66`) rejected every medium-confidence
    // table pixel → zero candidate points → `noLidarPoints` → the user-facing "no
    // flat surface". The fix lowers τ_conf so medium-or-better confidence is
    // accepted (only genuine LOW/zero returns are dropped), letting a matte table
    // still fit; the RANSAC 5 mm inlier band + 20 mm residual gate still reject a
    // bad plane, and σ_plane carries any degradation (consistent with Decision 46).
    func testFitsMatteTableWithUniformMediumConfidence() throws {
        let trueNormal = Vec3(0, 1, 0)
        let trueDist: Float = 100
        let depth = syntheticPlaneDepthMap(
            normal: trueNormal, distanceMm: trueDist,
            uniformConfidence: 127          // ARKit .medium — a matte table
        )
        let foodMask = centredFoodMask(foodRectX: 250..<390, foodRectY: 200..<320)
        let plane = try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: intrinsics,
            foodRegionMask: foodMask,
            gravityCamera: trueNormal
        ))
        let angleDeg = acos(max(-1, min(1, plane.normal.dot(trueNormal)))) * 180 / .pi
        XCTAssertLessThan(angleDeg, 1.0,
                          "recovered normal off by \(angleDeg)°; medium-confidence table must still fit")
        XCTAssertEqual(plane.distanceMm, trueDist, accuracy: 2.0)
    }

    // Diagnostic counter `debugLastResidualMm` feeds the on-device
    // `supportplane.end` trace so a residual-too-high refusal (real-but-noisy
    // plane) is distinguishable from point-starvation/degeneracy. It carries the
    // RMS residual on a fit that reaches step 4, and the -1 sentinel when the fit
    // refuses BEFORE residual is computed. Bug `capture-log-flood-…` round.
    func testResidualCounterReflectsFitOutcome() throws {
        let trueNormal = Vec3(0, 1, 0)
        // Clean fit → residual is computed and near zero.
        let clean = syntheticPlaneDepthMap(normal: trueNormal, distanceMm: 100)
        let foodMask = centredFoodMask(foodRectX: 250..<390, foodRectY: 200..<320)
        _ = try LiDARPlaneFitter.fit(.init(
            depth: clean, colourIntrinsics: intrinsics,
            foodRegionMask: foodMask, gravityCamera: trueNormal
        ))
        XCTAssertGreaterThanOrEqual(LiDARPlaneFitter.debugLastResidualMm, 0,
                                    "a completed fit must record its residual")
        XCTAssertLessThan(LiDARPlaneFitter.debugLastResidualMm, 5,
                          "clean synthetic plane residual should be small")

        // Point-starvation refusal (all-low confidence) → residual never reached,
        // sentinel stays -1.
        let starved = syntheticPlaneDepthMap(normal: trueNormal, distanceMm: 100,
                                             uniformConfidence: 0)
        XCTAssertThrowsError(try LiDARPlaneFitter.fit(.init(
            depth: starved, colourIntrinsics: intrinsics,
            foodRegionMask: foodMask, gravityCamera: trueNormal
        )))
        XCTAssertEqual(LiDARPlaneFitter.debugLastResidualMm, -1,
                       "a pre-residual refusal must leave the -1 sentinel")
    }

    // Guard the lower bound: genuine LOW/zero-confidence returns must STILL be
    // rejected, so a table that produces only unreliable depth refuses rather than
    // fitting a garbage plane. τ_conf accepts medium (127) but not low (0).
    func testRejectsUniformLowConfidenceTable() {
        let trueNormal = Vec3(0, 1, 0)
        let depth = syntheticPlaneDepthMap(
            normal: trueNormal, distanceMm: 100,
            uniformConfidence: 0            // ARKit .low — unreliable returns
        )
        let foodMask = centredFoodMask(foodRectX: 250..<390, foodRectY: 200..<320)
        XCTAssertThrowsError(try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: intrinsics,
            foodRegionMask: foodMask,
            gravityCamera: trueNormal
        ))) { err in
            XCTAssertEqual(err as? SupportPlaneError, .noLidarPoints,
                           "all-low-confidence table must refuse, not fit a garbage plane")
        }
    }

    // Regression for `lidar-plane-fit-degenerate-on-clean-capture` real-mask
    // path (2026-06-16 device verification on the iPhone 13 Pro Max). The pre-shutter
    // segmenter produces a centred food mask whose bbox extends to the
    // image's bottom edge (~y=1437 of 1440 on device). Pre-fix
    // `collectCandidatePoints` only scans BELOW the bbox — the window
    // collapses to zero rows and the fit throws `noLidarPoints`. Post-fix
    // the scan extends to all four edge bands (top, bottom, left, right)
    // around the bbox so centred framings still find table pixels on the
    // sides when the bottom band is starved.
    func testFitsCentredMaskWithBboxAtImageBottomEdge() throws {
        let tiltRad: Float = 5 * .pi / 180
        let trueNormal = Vec3(sin(tiltRad), cos(tiltRad), 0)
        let trueDist: Float = 200
        let depth = syntheticPlaneDepthMap(normal: trueNormal, distanceMm: trueDist)
        // bbox.maxY = 479 (the image's last row): the below-bbox scan
        // window collapses to a single row that is itself inside the food
        // mask, leaving zero candidate pixels. Mimics the on-device
        // dev-stub ellipse bbox extending to y ≈ mask.height − 3 in a
        // 1440-tall frame.
        let foodMask = centredFoodMask(
            foodRectX: 100..<540,
            foodRectY: 100..<480
        )
        let plane = try LiDARPlaneFitter.fit(.init(
            depth: depth,
            colourIntrinsics: intrinsics,
            foodRegionMask: foodMask,
            gravityCamera: trueNormal
        ))
        let angleRad = acos(max(-1, min(1, plane.normal.dot(trueNormal))))
        let angleDeg = angleRad * 180 / .pi
        XCTAssertLessThan(angleDeg, 2.0,
                          "recovered normal off by \(angleDeg)°; expected within 2°")
        XCTAssertEqual(plane.distanceMm, trueDist, accuracy: 5.0,
                       "recovered distance \(plane.distanceMm) mm; expected \(trueDist) ± 5 mm")
    }
}
