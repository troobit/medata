import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 1: depth-intrinsics derivation and colour-to-depth mask downsampling
// (design §"Native depth grid, and the intrinsics trap"; Req 2.1, 2.4).

final class SupportRegionGeometryTests: XCTestCase {
    // The half-pixel terms are the point of the test: dropping them shifts the
    // principal point by 0.5·(1 − s) depth px — silent at nadir, but wrong.
    func testDepthIntrinsicsAppliesHalfPixelScaling() {
        let colour = CameraIntrinsics(fx: 1920, fy: 1440, cx: 963.2, cy: 717.9,
                                      distortion: [], imageWidth: 1920, imageHeight: 1440)
        let depth = heightFieldDepthMap(intrinsics: colour, depthWidth: 256, depthHeight: 192,
                                        heightMmAt: { _, _ in 100 })
        let kd = SupportRegion.depthIntrinsics(from: colour, depth: depth)

        let sx: Float = 256.0 / 1920.0
        let sy: Float = 192.0 / 1440.0
        XCTAssertEqual(kd.fx, colour.fx * sx, accuracy: 1e-4)
        XCTAssertEqual(kd.fy, colour.fy * sy, accuracy: 1e-4)
        XCTAssertEqual(kd.cx, (colour.cx + 0.5) * sx - 0.5, accuracy: 1e-4)
        XCTAssertEqual(kd.cy, (colour.cy + 0.5) * sy - 0.5, accuracy: 1e-4)
        XCTAssertEqual(kd.imageWidth, 256)
        XCTAssertEqual(kd.imageHeight, 192)
    }

    // Guard against reading `depth.depthIntrinsics` (ARKit writes it as
    // all-zero on device — see LiDARPlaneFitter's identical guidance): the
    // derived intrinsics must never be the degenerate fx=0 that produces a
    // NaN plane, regardless of what the DepthMap's own field says.
    func testDepthIntrinsicsIgnoresDepthMapsOwnZeroedField() {
        let colour = CameraIntrinsics(fx: 1500, fy: 1500, cx: 320, cy: 240,
                                      distortion: [], imageWidth: 640, imageHeight: 480)
        let zeroDepthIntrinsics = CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0,
                                                   distortion: [], imageWidth: 256, imageHeight: 192)
        let depth = DepthMap(
            depthBytesMm: Data(count: 256 * 192 * 4), confidenceBytes: Data(count: 256 * 192),
            width: 256, height: 192, rowStrideBytes: 256 * 4,
            depthIntrinsics: zeroDepthIntrinsics, depthFromColour: .identity
        )
        let kd = SupportRegion.depthIntrinsics(from: colour, depth: depth)
        XCTAssertGreaterThan(kd.fx, 0)
        XCTAssertGreaterThan(kd.fy, 0)
    }

    // Assert a depth pixel is food when ANY covered colour pixel is food, so
    // ambiguity resolves towards exclusion (Req 2.1) — the fitted set may
    // never contain a food pixel.
    func testMaskDownsampleMarksDepthPixelFoodWhenAnyCoveredColourPixelIsFood() {
        // 8×8 colour grid downsampled 4:1 to a 2×2 depth grid. Only ONE colour
        // pixel inside the depth pixel (0,0)'s 4×4 block is food.
        var colourPixels = [UInt8](repeating: 0, count: 8 * 8)
        colourPixels[0 * 8 + 0] = 1   // single food pixel, corner of block (0,0)
        let colourMask = BinaryMask(pixels: colourPixels, width: 8, height: 8)

        let depthMask = SupportRegion.depthGridMask(from: colourMask, depthWidth: 2, depthHeight: 2)

        XCTAssertTrue(depthMask.isFood(x: 0, y: 0), "any covered colour pixel food => depth pixel food")
        XCTAssertFalse(depthMask.isFood(x: 1, y: 0))
        XCTAssertFalse(depthMask.isFood(x: 0, y: 1))
        XCTAssertFalse(depthMask.isFood(x: 1, y: 1))
    }

    func testMaskDownsampleAllFoodBlockStaysFood() {
        let colourMask = BinaryMask(pixels: [UInt8](repeating: 1, count: 8 * 8), width: 8, height: 8)
        let depthMask = SupportRegion.depthGridMask(from: colourMask, depthWidth: 2, depthHeight: 2)
        for y in 0..<2 {
            for x in 0..<2 {
                XCTAssertTrue(depthMask.isFood(x: x, y: y))
            }
        }
    }

    func testMaskDownsampleAllBackgroundBlockStaysBackground() {
        let colourMask = BinaryMask(pixels: [UInt8](repeating: 0, count: 8 * 8), width: 8, height: 8)
        let depthMask = SupportRegion.depthGridMask(from: colourMask, depthWidth: 2, depthHeight: 2)
        for y in 0..<2 {
            for x in 0..<2 {
                XCTAssertFalse(depthMask.isFood(x: x, y: y))
            }
        }
    }

    // Non-integer scale factors (the real 1920×1440 → 256×192 case is exact,
    // but N5k identity-grid fixtures and other resolutions are not) must not
    // crash or drop rows/columns.
    func testMaskDownsamplePreservesDimensionsAtNonIntegerScale() {
        let colourMask = BinaryMask(pixels: [UInt8](repeating: 1, count: 100 * 60), width: 100, height: 60)
        let depthMask = SupportRegion.depthGridMask(from: colourMask, depthWidth: 33, depthHeight: 19)
        XCTAssertEqual(depthMask.width, 33)
        XCTAssertEqual(depthMask.height, 19)
        for y in 0..<19 {
            for x in 0..<33 {
                XCTAssertTrue(depthMask.isFood(x: x, y: y), "all-food source must downsample to all-food")
            }
        }
    }
}
