#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
import Volume
@testable import HarnessCore

// The measuring instruments the carve residual accounting rests on
// (two-view-trust, `docs/agent-notes/two-view-geometry-audit.md` §7). Each is
// pinned against a scene whose answer is known in closed form, because the
// audit's conclusions — "the footprint is not too wide", "the hull's own bias
// is 1.1–1.25" — are only worth anything if the rulers are right.
//
// Geometry: camera at origin, −Z forward (§6.0), 100×100 at fx = fy = 500,
// support plane n̂ = (0,0,1) at −400 mm, gravity (world-up) = (0,0,1). A point
// at z = −400 lies on the plane; larger z is "above" it, toward the camera.
@Suite("CarveResidualAudit")
struct CarveResidualAuditTests {

    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)
    let gravity = Vec3(0, 0, 1)

    // Grid axes for a fronto-parallel table: x right, y down, z toward camera.
    var referenceGrid: VoxelGrid {
        VoxelGrid(edgeMm: 3, dimsX: 64, dimsY: 64, dimsZ: 16,
                  originCamera1: Vec3(0, 0, -400),
                  axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1))
    }

    // An oblique camera orbited θ about +X through the food point (0,0,−400):
    // T(F)·R_x(−θ)·T(−F). The optical axis stays on the food, as the aim guide
    // requires, so the two silhouettes describe the same world region.
    func obliqueTransform(degrees: Float) -> Mat4 {
        let t = degrees * .pi / 180
        let c = cos(t), s = sin(t)
        let f: Float = -400
        return Mat4(columns: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0],
                              [0, -(s * f), f - (c * f), 1]])
    }

    // MARK: - convex hull

    @Test("the hull of a square plus its interior points is the square")
    func hullDropsInteriorPoints() {
        let hull = CarveResidualAudit.convexHull([
            SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10),
            SIMD2(5, 5), SIMD2(2, 7), SIMD2(9, 1)
        ])
        #expect(hull.count == 4)
        for corner in [SIMD2<Float>(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(0, 10)] {
            #expect(hull.contains(corner))
        }
    }

    @Test("a filled convex polygon covers its own area in pixels")
    func polygonMaskFillsTheQuad() {
        let mask = CarveResidualAudit.polygonMask(
            CarveResidualAudit.convexHull([
                SIMD2(20, 20), SIMD2(60, 20), SIMD2(60, 50), SIMD2(20, 50)
            ]), width: 100, height: 100)
        let filled = mask.pixels.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        // 41 × 31 pixel centres inclusive; allow the boundary row/column.
        #expect(filled >= 1200 && filled <= 1350)
        #expect(mask.isFood(x: 40, y: 35))
        #expect(!mask.isFood(x: 10, y: 35))
    }

    // MARK: - footprint

    @Test("a flat patch ON the plane measures its own metric area")
    func footprintOfAFlatPatchIsItsTrueArea() {
        // 40 × 30 mm rectangle lying on the plane at z = −400.
        let corners: [SIMD2<Float>] = [
            SIMD2(-20, -15), SIMD2(20, -15), SIMD2(20, 15), SIMD2(-20, 15)
        ].map { SIMD2(k.fx * $0.x / 400 + k.cx, k.fy * $0.y / 400 + k.cy) }
        let mask = CarveResidualAudit.polygonMask(
            CarveResidualAudit.convexHull(corners), width: 100, height: 100)
        let cm2 = CarveResidualAudit.footprintCm2(mask: mask, intrinsics: k, plane: plane)
        #expect(abs(cm2 - 12.0) < 1.0)          // 40 × 30 mm = 12 cm², ±8 %
    }

    // The claim the whole footprint argument rests on: the nadir silhouette of
    // a RAISED object, back-projected to the support plane, is larger than that
    // object's true footprint — by (d / (d − h))², purely from perspective. So
    // a measured footprint above the food's real one is not evidence of a wide
    // mask until this magnification is taken out.
    @Test("a raised object's silhouette measures larger than its true footprint")
    func raisedObjectSilhouetteIsMagnified() {
        let h: Float = 40
        let corners: [SIMD2<Float>] = [
            SIMD2(-20, -15), SIMD2(20, -15), SIMD2(20, 15), SIMD2(-20, 15)
        ].map { SIMD2(k.fx * $0.x / (400 - h) + k.cx, k.fy * $0.y / (400 - h) + k.cy) }
        let mask = CarveResidualAudit.polygonMask(
            CarveResidualAudit.convexHull(corners), width: 100, height: 100)
        let cm2 = CarveResidualAudit.footprintCm2(mask: mask, intrinsics: k, plane: plane)
        let expected = 12.0 * pow(400.0 / (400.0 - Double(h)), 2)   // ≈ 14.5 cm²
        #expect(cm2 > 12.5)
        #expect(abs(Double(cm2) - expected) < 1.2)
    }

    // MARK: - synthetic control

    @Test("the voxelised truth of a box is its analytic volume")
    func voxelisedTruthMatchesTheBox() {
        let box = SIMD3<Float>(60, 45, 30)
        let truth = CarveResidualAudit.voxelisedTruthCm3(
            grid: referenceGrid, base: referenceGrid.originCamera1,
            ax: referenceGrid.axisX, ay: referenceGrid.axisY, az: referenceGrid.axisZ,
            boxMm: box)
        let analytic = box.x * box.y * box.z / 1000                 // 81 cm³
        #expect(abs(truth - analytic) / analytic < 0.12)
    }

    // The control's whole purpose: with EXACT silhouettes and no segmenter, the
    // two-view carve of a box of known size still exceeds that box. The excess
    // is the visual hull's own bias — a hull of two views circumscribes the
    // object, and perspective cones widen it — and it is a floor on the
    // achievable accuracy, not a defect to tune away.
    @Test("the hull of a box with exact silhouettes circumscribes it")
    func hullBiasIsAtLeastUnityAndBounded() throws {
        let rows = try CarveResidualAudit.syntheticControls(
            boxMm: SIMD3(60, 45, 30), referenceGrid: referenceGrid,
            nadirK: k, obliqueK: k, t1to2: obliqueTransform(degrees: 25),
            plane: plane, gravity: gravity, edgeMm: 3, capsMm: [30],
            fixtureID: "synthetic")
        let row = try #require(rows.first)
        #expect(row.carvedCm3 > 0)
        #expect(row.hullBias >= 1.0, "a visual hull can never carve less than the object")
        #expect(row.hullBias < 2.0, "a well-aimed 25° pair should not double it either")
        #expect(row.trueFootprintCm2 == 27.0)                       // 60 × 45 mm
        #expect(row.silhouetteFootprintCm2 > row.trueFootprintCm2,
                "the raised box's silhouette projects wide on the plane")
    }

    // Widening the grid above the object's own height turns straight into
    // volume, because two cones at an aim-guide tilt never close over a low
    // food. This is why the margin, not the percentile, is the only part of the
    // height bound with any leverage.
    @Test("extra grid height above the box becomes extra hull")
    func marginTurnsIntoVolume() throws {
        let rows = try CarveResidualAudit.syntheticControls(
            boxMm: SIMD3(60, 45, 30), referenceGrid: referenceGrid,
            nadirK: k, obliqueK: k, t1to2: obliqueTransform(degrees: 25),
            plane: plane, gravity: gravity, edgeMm: 3, capsMm: [30, 39],
            fixtureID: "synthetic")
        #expect(rows.count == 2)
        #expect(rows[1].extentMm > rows[0].extentMm)
        #expect(rows[1].carvedCm3 > rows[0].carvedCm3)
    }
}
#endif
