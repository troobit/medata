import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import XCTest
@testable import Volume

// Req 1.6: the voxel carve uses the support plane as a lower carving bound, and
// any change in excluded voxels caused by correcting the plane must be STATED.
// `VoxelCarveEstimator` drops a voxel outright when
// `signedDistanceToPlane(centre) < 0` (`VoxelCarveEstimator.swift:116`) — a hard
// exclusion, where the height field only clamps with `max(0, ·)`. The design's
// parity-audit row predicted that raising the plane ~26 mm would "delete a
// slab", so this measures whether it does.
//
// MEASURED ANSWER: the excluded-voxel count does not change at all, and the
// prediction was wrong about the mechanism. It assumed a grid fixed in space
// with a plane sliding through it. The grid is not fixed: `VoxelGridSizer`
// anchors `originCamera1` ON the support plane (the food-mask centroid
// back-projected onto it) and `VoxelGrid.voxelCentre` offsets every voxel along
// `axisZ` by `dz = (iz + 0.5) · edgeMm`, which is strictly ONE-SIGNED. Raising
// the plane translates the whole grid with it, so each voxel keeps its signed
// distance and the exclusion decides identically before and after.
//
// The real consequence of the correction is therefore a TRANSLATION, not a
// deletion: the ~26 mm of space between the table and the plate top, which used
// to lie inside the grid, now lies outside it. Food overhanging below the plate
// (Decision 4) leaves the grid entirely rather than being excluded by the plane
// test — the same under-measurement Decision 4 already accepts and brackets at
// ~11 %, reached by a different route. Nothing compounds, because the two
// mechanisms are the same 26 mm counted once.
//
// A separate finding, deliberately not fixed here. The two callers disagree on
// what `gravityCamera` means: `Pipeline` passes `nadir.gravity`, which
// `CameraGravity` documents as world-UP in the camera frame, while
// `VoxelGridSizerTests`/`VoxelCarveEstimatorTests` pass (0,0,−1) and comment it
// as gravity pointing DOWN. The sign decides whether the grid extends above the
// plane or below it, and therefore whether the exclusion drops no voxel or every
// voxel. Both conventions are measured below and the Req 1.6 answer — no change
// — holds under each, which is why this feature does not turn on it. The
// disagreement itself belongs to `bugfixes/two-view-carve-no-volume`, and the
// two-view carve's accuracy is an explicit Non-Goal of this spec.
final class VoxelCarvePlaneExclusionTests: XCTestCase {

    private let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                     distortion: [], imageWidth: 100, imageHeight: 100)

    // The diagnosed capture's own numbers: the fit landed 26.1 mm below the plate
    // the bread rested on, so the corrected plane sits that much nearer the camera.
    private let tableDepthMm: Float = 400
    private let plateRiseMm: Float = 26.1

    private func plane(atDepthMm depth: Float) -> SupportPlane {
        SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -depth,
                     residualMm: 0.5, convergedIterations: nil)
    }

    private func mask() -> BinaryMask {
        makeBinaryMask(width: 100, height: 100) { y, x in
            (40..<60).contains(x) && (40..<60).contains(y)
        }
    }

    private func excludedVoxels(planeDepthMm: Float, gravity: Vec3) throws -> (excluded: Int, total: Int, origin: Vec3) {
        let p = plane(atDepthMm: planeDepthMm)
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask(), nadirIntrinsics: k, supportPlane: p, gravityCamera: gravity
        ))
        var excluded = 0
        for iz in 0..<grid.dimsZ {
            for iy in 0..<grid.dimsY {
                for ix in 0..<grid.dimsX where
                    signedDistanceToPlane(grid.voxelCentre(ix: ix, iy: iy, iz: iz), plane: p) < 0 {
                    excluded += 1
                }
            }
        }
        return (excluded, grid.dimsX * grid.dimsY * grid.dimsZ, grid.originCamera1)
    }

    // Req 1.6, under the convention `Pipeline` actually passes (world-up).
    func testExcludedVoxelCountIsUnchangedByRaisingThePlane_worldUpGravity() throws {
        let up = Vec3(0, 0, 1)
        let before = try excludedVoxels(planeDepthMm: tableDepthMm, gravity: up)
        let after = try excludedVoxels(planeDepthMm: tableDepthMm - plateRiseMm, gravity: up)

        XCTAssertEqual(before.total, after.total, "the grid must not change size")
        XCTAssertEqual(
            after.excluded - before.excluded, 0,
            """
            excluded voxels moved \(before.excluded) → \(after.excluded) of \(before.total). \
            The grid is anchored on the plane and extends one way only, so the count \
            cannot depend on where the plane sits; a non-zero change means \
            VoxelGridSizer no longer origins on the plane.
            """
        )
        // The absolute figure, pinned because it is more alarming than the delta
        // Req 1.6 asked for: under the convention `Pipeline` passes, EVERY voxel
        // is excluded — 23,040 of 23,040 — so the two-view carve recovers no
        // volume at all on a LiDAR device whose depth-derived plane reaches it.
        // That is the `bugfixes/two-view-carve-no-volume` defect, not a change
        // this feature introduces: it reads the same before and after.
        XCTAssertEqual(before.excluded, before.total)
        XCTAssertEqual(after.excluded, after.total)
        // The translation that DOES happen, and is the whole of the effect.
        XCTAssertEqual(after.origin.z - before.origin.z, plateRiseMm, accuracy: 0.1,
                       "the grid must rise with the plane")
    }

    // The same measurement under the tests' opposite convention, to show the Req 1.6
    // answer does not rest on resolving the sign disagreement.
    func testExcludedVoxelCountIsUnchangedByRaisingThePlane_downwardGravity() throws {
        let down = Vec3(0, 0, -1)
        let before = try excludedVoxels(planeDepthMm: tableDepthMm, gravity: down)
        let after = try excludedVoxels(planeDepthMm: tableDepthMm - plateRiseMm, gravity: down)

        XCTAssertEqual(after.excluded - before.excluded, 0)
        // The mirror image of the world-up case: the grid extends above the plane,
        // so NO voxel is excluded — again identically before and after.
        XCTAssertEqual(before.excluded, 0)
        XCTAssertEqual(after.excluded, 0)
        XCTAssertEqual(after.origin.z - before.origin.z, plateRiseMm, accuracy: 0.1)
    }

    // The structural reason, asserted directly so a future change to
    // `voxelCentre` that made `dz` two-signed fails here rather than silently
    // making the exclusion live again.
    func testVoxelHeightOffsetsAreOneSigned() {
        let grid = VoxelGrid(
            edgeMm: 3, dimsX: 8, dimsY: 8, dimsZ: 8,
            originCamera1: Vec3(0, 0, -400),
            axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1)
        )
        for iz in 0..<grid.dimsZ {
            let dz = grid.voxelCentre(ix: 0, iy: 0, iz: iz).z - grid.originCamera1.z
            XCTAssertGreaterThan(dz, 0, "voxel z-offsets must stay one-signed about the plane")
        }
    }
}
