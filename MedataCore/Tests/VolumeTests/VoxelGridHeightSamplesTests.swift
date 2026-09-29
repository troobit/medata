import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// `foodHeightSamplesMm` + `percentile` are the refactor that let the carve
// residual audit read the WHOLE height distribution behind the grid's vertical
// bound instead of just its P98 (two-view-trust, 2026-09-25). They must stay
// the exact sample set and the exact rule `measuredFoodHeightMm` uses, or the
// diagnostic stops describing the production bound.
//
// Geometry as in VoxelGridMeasuredHeightTests: camera at origin, −Z forward,
// 100×100 at fx=fy=500, support plane n̂=(0,0,1) at −400 mm. A colour pixel's
// height above the plane is then exactly 400 − depth.
final class VoxelGridHeightSamplesTests: XCTestCase {

    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)

    // 20×20 food square, 400 samples — above `minHeightSampleCount`.
    private func foodMask() -> BinaryMask {
        makeBinaryMask(width: 100, height: 100) { y, x in
            (40..<60).contains(x) && (40..<60).contains(y)
        }
    }

    // A staircase inside the square: the top-left quarter at 50 mm, the rest at
    // 20 mm. 100 of 400 samples are high, so the quartiles are known exactly.
    private func staircaseDepth() -> DepthMap {
        makeDepthMap(width: 100, height: 100, intrinsics: k) { y, x in
            let inFood = (40..<60).contains(x) && (40..<60).contains(y)
            if !inFood { return 400 }
            let high = (40..<50).contains(x) && (40..<50).contains(y)
            return high ? 350 : 380
        }
    }

    func testSamplesAreSortedAndCoverEveryFoodPixel() {
        let samples = VoxelGridSizer.foodHeightSamplesMm(
            foodMask: foodMask(), depth: staircaseDepth(),
            intrinsics: k, supportPlane: plane)
        XCTAssertEqual(samples.count, 400, "every food pixel with usable depth is a sample")
        XCTAssertEqual(samples, samples.sorted(), "samples must come back ascending")
        // 300 at ~20 mm, 100 at ~50 mm.
        XCTAssertEqual(samples.filter { $0 > 35 }.count, 100)
    }

    func testMeasuredHeightIsThePercentileOfTheSamples() throws {
        let mask = foodMask()
        let depth = staircaseDepth()
        let samples = VoxelGridSizer.foodHeightSamplesMm(
            foodMask: mask, depth: depth, intrinsics: k, supportPlane: plane)
        let viaSamples = try XCTUnwrap(
            VoxelGridSizer.percentile(ofSorted: samples, VoxelGridSizer.heightPercentile))
        let production = try XCTUnwrap(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: mask, depth: depth, intrinsics: k, supportPlane: plane))
        XCTAssertEqual(viaSamples, production, accuracy: 1e-4,
                       "the diagnostic path and the production path must agree exactly")
    }

    func testPercentileIsNearestRankOnTheEnds() {
        let sorted: [Float] = [1, 2, 3, 4, 5]
        XCTAssertEqual(VoxelGridSizer.percentile(ofSorted: sorted, 0), 1)
        XCTAssertEqual(VoxelGridSizer.percentile(ofSorted: sorted, 1), 5)
        XCTAssertEqual(VoxelGridSizer.percentile(ofSorted: sorted, 0.5), 3)
        XCTAssertNil(VoxelGridSizer.percentile(ofSorted: [], 0.5))
    }

    // Too few usable samples still falls back to the constant extent, exactly
    // as before the refactor.
    func testTooFewSamplesReturnsNil() {
        let tiny = makeBinaryMask(width: 100, height: 100) { y, x in
            (50..<52).contains(x) && (50..<52).contains(y)     // 4 pixels
        }
        XCTAssertNil(VoxelGridSizer.measuredFoodHeightMm(
            foodMask: tiny, depth: staircaseDepth(), intrinsics: k, supportPlane: plane))
        XCTAssertEqual(VoxelGridSizer.foodHeightSamplesMm(
            foodMask: tiny, depth: staircaseDepth(),
            intrinsics: k, supportPlane: plane).count, 4,
            "the sample accessor still reports what it found; only the bound refuses")
    }
}
