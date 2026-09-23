import Foundation
import Segmentation
import XCTest
@testable import Volume

// Tests for InterClassOcclusionDetector per design §6.8.
// Single-pass O(W·H) 4-neighbour scan over argmax + top-surface depth.
// A depth discontinuity > 10 mm at a food-food boundary signals inter-class occlusion.

final class InterClassOcclusionDetectorTests: XCTestCase {

    let palette = makePalette(numFood: 2)   // food_0=0, food_1=1, bg=2

    // MARK: - helpers

    func makeArgmax(width: Int, height: Int, labels: [UInt8]) -> ArgmaxMap {
        ArgmaxMap(pixels: Data(labels), height: height, width: width)
    }

    func makeUniformDepth(_ value: Float, count: Int) -> [Float] {
        [Float](repeating: value, count: count)
    }

    // MARK: - T29.1 Discontinuity > 10 mm at food–food boundary → true

    func testDepthDiscontinuityAtFoodBoundaryReturnsTrue() {
        // 4×4 image: left 2 columns = food_0 at 200 mm depth,
        //            right 2 columns = food_1 at 185 mm depth.
        // At the x=1→2 boundary, depth diff = 15 mm > 10 mm → occlusion.
        let w = 4, h = 4
        let labels: [UInt8] = (0..<h).flatMap { _ in
            [0, 0, 1, 1]
        }
        var depth = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                depth[y * w + x] = x < 2 ? 200 : 185
            }
        }
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        let result = InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette
        )
        XCTAssertTrue(result,
            "15 mm depth discontinuity at a food-food boundary must trigger occlusion detection")
    }

    // MARK: - T29.2 Discontinuity ≤ 10 mm at food–food boundary → false

    func testSmallDepthDiscontinuityReturnsFalse() {
        // Same layout but only 5 mm difference → no occlusion.
        let w = 4, h = 4
        let labels: [UInt8] = (0..<h).flatMap { _ in [0, 0, 1, 1] }
        var depth = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                depth[y * w + x] = x < 2 ? 200 : 195   // diff = 5 mm ≤ 10 mm
            }
        }
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertFalse(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }

    // MARK: - T29.3 Single food class → false (no inter-class boundary)

    func testSingleFoodClassReturnsFalse() {
        let w = 4, h = 4
        let labels = [UInt8](repeating: 0, count: w * h)   // all food_0
        var depth = [Float](repeating: 0, count: w * h)
        // Vary depth wildly — still no inter-class boundary.
        for i in 0..<(w * h) { depth[i] = Float(i) * 10 + 200 }
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertFalse(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }

    // MARK: - T29.4 All background pixels → false

    func testAllBackgroundReturnsFalse() {
        let w = 4, h = 4
        let bgId = UInt8(palette.background)
        let labels = [UInt8](repeating: bgId, count: w * h)
        let depth = makeUniformDepth(200, count: w * h)
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertFalse(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }

    // MARK: - T29.5 Discontinuity at food–background boundary → false (not inter-class food)

    func testFoodBackgroundBoundaryReturnsFalse() {
        // food_0 left, bg right; depth diff = 50 mm but bg is not a food class.
        let w = 4, h = 4
        let bgId = UInt8(palette.background)
        let labels: [UInt8] = (0..<h).flatMap { _ in [0, 0, bgId, bgId] }
        var depth = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                depth[y * w + x] = x < 2 ? 200 : 150   // 50 mm diff but bg-food boundary
            }
        }
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertFalse(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }

    // MARK: - T29.6 Discontinuity in horizontal direction (y neighbours)

    func testVerticalBoundaryOcclusionDetected() {
        // food_0 top 2 rows at 200 mm, food_1 bottom 2 rows at 185 mm.
        // Boundary is horizontal (y neighbours), depth diff = 15 mm.
        let w = 4, h = 4
        let labels: [UInt8] = (0..<h).flatMap { y in
            [UInt8](repeating: y < 2 ? 0 : 1, count: w)
        }
        var depth = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                depth[y * w + x] = y < 2 ? 200 : 185
            }
        }
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertTrue(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }

    // MARK: - T29.7 Flat single food class with uniform depth → false

    func testFlatSingleClassReturnsFalse() {
        let w = 8, h = 8
        let labels = [UInt8](repeating: 1, count: w * h)   // all food_1
        let depth = makeUniformDepth(300, count: w * h)
        let argmax = makeArgmax(width: w, height: h, labels: labels)
        XCTAssertFalse(InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depth, palette: palette))
    }
}
