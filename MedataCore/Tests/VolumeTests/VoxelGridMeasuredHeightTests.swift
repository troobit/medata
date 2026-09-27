import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Measured vertical extent of the carve grid (two-view-trust, 2026-09-25).
//
// Geometry as in VoxelGridSizerTests: camera at origin, −Z forward, 100×100 at
// fx=fy=500, support plane n̂=(0,0,1) at −400 mm, gravity (world-up) = (0,0,1).
// A colour pixel's height above the plane is then exactly 400 − depth, so a
// 40 mm object is a depth of 360 mm over its footprint.

final class VoxelGridMeasuredHeightTests: XCTestCase {

    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)
    let gravity = Vec3(0, 0, 1)

    // 20×20 food square centred in the 100×100 image — 400 pixels, comfortably
    // above `minHeightSampleCount`.
    func foodMask(half: Int = 10) -> BinaryMask {
        makeBinaryMask(width: 100, height: 100) { y, x in
            (50 - half..<50 + half).contains(x) && (50 - half..<50 + half).contains(y)
        }
    }

    // Depth field: `objectMm` above the plane inside the food square, the plane
    // itself outside it. `spikes` pixels in the square are pushed to `spikeMm`.
    func depth(objectMm: Float, spikeMm: Float = 0, spikes: Int = 0) -> DepthMap {
        var placed = 0
        var spikePixels: Set<Int> = []
        for y in 40..<60 where placed < spikes {
            for x in 40..<60 where placed < spikes {
                spikePixels.insert(y * 100 + x)
                placed += 1
            }
        }
        return makeDepthMap(width: 100, height: 100, intrinsics: k) { y, x in
            let inFood = (40..<60).contains(x) && (40..<60).contains(y)
            if !inFood { return 400 }
            return spikePixels.contains(y * 100 + x) ? 400 - spikeMm : 400 - objectMm
        }
    }

    func testMeasuredHeightMatchesTheObject() throws {
        let h = try XCTUnwrap(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: depth(objectMm: 40),
            intrinsics: k, supportPlane: plane))
        XCTAssertEqual(h, 40, accuracy: 0.5)
    }

    func testA40mmObjectGivesA40mmPlusMarginExtent() throws {
        let h = VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: depth(objectMm: 40),
            intrinsics: k, supportPlane: plane)
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: gravity, measuredFoodHeightMm: h))
        // 40 + margin, rounded up to a whole voxel — and never a whole
        // threadgroup above it, which is the point of dropping the alignment.
        let wanted = 40 + VoxelGridSizer.heightMarginMm
        XCTAssertGreaterThanOrEqual(grid.verticalExtentMm, wanted)
        XCTAssertLessThan(grid.verticalExtentMm, wanted + VoxelGridSizer.defaultEdgeMm)
    }

    func testNoDepthKeepsThe120mmConstant() throws {
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: gravity, measuredFoodHeightMm: nil))
        XCTAssertEqual(grid.verticalExtentMm, VoxelGridSizer.verticalExtentMm, accuracy: 1e-3)
        XCTAssertEqual(grid.dimsZ % VoxelGridSizer.threadgroupAlignment, 0,
                       "the constant path keeps the threadgroup rounding it always had")
    }

    // The percentile is what stops one bad depth sample from setting the grid.
    func testAFewWildSamplesDoNotSetTheHeight() throws {
        let h = try XCTUnwrap(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: depth(objectMm: 40, spikeMm: 200, spikes: 4),
            intrinsics: k, supportPlane: plane))
        XCTAssertEqual(h, 40, accuracy: 1)
    }

    func testTooFewSamplesRefuseToMeasure() {
        // 3×3 food square — below `minHeightSampleCount`.
        let tiny = makeBinaryMask(width: 100, height: 100) { y, x in
            (49..<52).contains(x) && (49..<52).contains(y)
        }
        XCTAssertNil(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: tiny, depth: depth(objectMm: 40),
            intrinsics: k, supportPlane: plane))
    }

    func testAFlatFoodStillGetsTheFloorExtent() throws {
        let h = VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: depth(objectMm: 4),
            intrinsics: k, supportPlane: plane)
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: gravity, measuredFoodHeightMm: h))
        XCTAssertGreaterThanOrEqual(grid.verticalExtentMm, VoxelGridSizer.minVerticalExtentMm)
    }

    // two-view-trust Decision 10: the plane is the origin the height is
    // measured from as well as the grid's floor, so a plane refit 7 mm nearer
    // the food lowers the measured height by 7 mm and the grid's extent by at
    // least one voxel. This is the whole mechanism by which a grown-region
    // refit changes a two-view carve without touching the silhouette.
    func testAPlaneRaised7mmLowersTheHeightAndTheExtent() throws {
        let raised = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -393,
                                  residualMm: 0.5, convergedIterations: nil)
        let d = depth(objectMm: 40)
        let h0 = try XCTUnwrap(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: d, intrinsics: k, supportPlane: plane))
        let h1 = try XCTUnwrap(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: foodMask(), depth: d, intrinsics: k, supportPlane: raised))
        XCTAssertEqual(h0 - h1, 7, accuracy: 0.5)
        let g0 = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: gravity, measuredFoodHeightMm: h0))
        let g1 = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: raised,
            gravityCamera: gravity, measuredFoodHeightMm: h1))
        XCTAssertGreaterThanOrEqual(g0.verticalExtentMm - g1.verticalExtentMm,
                                    VoxelGridSizer.defaultEdgeMm)
    }

    func testAnImplausiblyTallMeasurementIsCappedAt120mm() throws {
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: foodMask(), nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: gravity, measuredFoodHeightMm: 500))
        XCTAssertLessThanOrEqual(grid.verticalExtentMm, VoxelGridSizer.verticalExtentMm)
    }
}
