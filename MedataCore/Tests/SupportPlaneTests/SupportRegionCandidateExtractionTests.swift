import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 5: bounded candidate sampling and CC-RANSAC extraction (Req 2.2, 2.3,
// 2.4; Decisions 13, 15).

final class SupportRegionCandidateExtractionTests: XCTestCase {
    // MARK: - Bounded candidate set (Decision 15)

    // Clutter positioned outside the 2×ringOuterMm candidate annulus must
    // never appear in the collected annulus samples.
    func testAnnulusExcludesClutterOutsideTheCandidateBound() {
        let dFood: Float = 126
        let dSurround: Float = 100
        let dClutter: Float = 500
        // Far corner of the image — well outside the ~97 px (2×25 mm) bound
        // around the food centroid at (150, 180).
        let clutterX = 0..<40, clutterY = 0..<40
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = heightFieldDepthMap(
            intrinsics: sceneIntrinsics, depthWidth: sceneWidth, depthHeight: sceneHeight,
            heightMmAt: { x, y in
                let dx = Float(x) - sceneFoodCentre.x, dy = Float(y) - sceneFoodCentre.y
                let r = (dx * dx + dy * dy).squareRoot()
                if r <= sceneFoodRadiusPx { return dFood }
                if clutterX.contains(x), clutterY.contains(y) { return dClutter }
                return dSurround
            }
        )
        guard let samples = SupportRegion.ringAndAnnulusSamples(
            depthGridFoodMask: mask, depth: depth, depthIntrinsics: sceneDepthIntrinsics(depth)
        ) else { return XCTFail("expected annulus samples") }

        for sample in samples.annulus {
            let x = sample.index % mask.width, y = sample.index / mask.width
            XCTAssertFalse(clutterX.contains(x) && clutterY.contains(y),
                           "clutter far outside the annulus bound must never become a candidate sample")
        }
        XCTAssertFalse(samples.annulus.isEmpty)
    }

    // MARK: - CC scoring (Decision 13)

    func testLargestConnectedComponentIgnoresDisjointFragments() {
        let width = 50, height = 50
        var indices: [Int] = []
        for y in 5..<15 { for x in 5..<15 { indices.append(y * width + x) } }      // blob A: 100 px, contiguous
        for y in 30..<40 { for x in 30..<40 { indices.append(y * width + x) } }    // blob B: 100 px, far away
        let component = SupportRegion.largestConnectedComponent(indices: indices, width: width, height: height)
        XCTAssertEqual(component.count, 100, "largest CC must be ONE blob, not the union's raw count (200)")
    }

    func testLargestConnectedComponentMergesDiagonalNeighbours() {
        let width = 10, height = 10
        let indices = (0..<5).map { i in i * width + i }   // a diagonal staircase
        let component = SupportRegion.largestConnectedComponent(indices: indices, width: width, height: height)
        XCTAssertEqual(component.count, 5, "8-connectivity must chain diagonally-touching pixels")
    }

    // A hypothesis whose raw inlier count is inflated by a spatially
    // DISCONNECTED total must still lose extraction to a smaller but fully
    // connected surface — the design's defence against a straddling plane
    // (a plane spanning two surfaces holds more RAW inliers than either
    // surface alone; component scoring changes which plane wins).
    func testExtractionPrefersConnectedSurfaceOverLargerDisconnectedTotal() {
        let width = 200, height = 200
        var points: [Vec3] = []
        var indices: [Int] = []
        let gravity = Vec3(0, 1, 0)
        // A hair of sub-millimetre jitter — real depth data is never
        // perfectly flat, and `refine`'s SVD stability gate (rightly) treats
        // an EXACTLY zero smallest singular value as degenerate.
        func jitter(_ x: Int, _ y: Int) -> Float { Float((x &* 7 &+ y &* 13) % 5) * 0.002 }

        // Surface D: one contiguous 25×25 block (625 points) at 130 mm.
        for y in 20..<45 {
            for x in 20..<45 {
                indices.append(y * width + x)
                points.append(Vec3(Float(x), 130 + jitter(x, y), Float(y)))
            }
        }
        // Surface E: the SAME plane (100 mm) split into two DISJOINT 20×20
        // blocks (400 + 400 = 800 raw points — more than D's 625), placed far
        // enough apart that 8-connectivity never bridges them.
        for y in 100..<120 {
            for x in 20..<40 {
                indices.append(y * width + x)
                points.append(Vec3(Float(x), 100 + jitter(x, y), Float(y)))
            }
        }
        for y in 150..<170 {
            for x in 150..<170 {
                indices.append(y * width + x)
                points.append(Vec3(Float(x), 100 + jitter(x, y), Float(y)))
            }
        }

        var rng = SplitMix64(seed: 12345)
        let candidates = SupportRegion.extractCandidatePlanes(
            points: points, depthIndices: indices, width: width, height: height,
            gravity: gravity, rng: &rng
        )
        guard let winner = candidates.first else { return XCTFail("expected at least one candidate") }
        XCTAssertEqual(winner.d, 130, accuracy: 1.0,
                       "CC-scoring must pick the connected 625-point surface over the disjoint 800-point total")
        XCTAssertTrue((620...625).contains(winner.inlierIndices.count),
                      "the winning inlier set must be surface D's 625-point block, not E's 800")
    }

    // MARK: - Adaptive iteration stopping (design §"Iteration budget")

    func testRequiredIterationsDerivesFromObservedInlierRatioNotTheInherited256() {
        // A low inlier ratio needs close to the full budget.
        XCTAssertEqual(SupportRegion.requiredRansacIterations(inlierRatio: 0.05),
                       SupportRegion.maxIterationsPerPass)
        // A high ratio needs far fewer than the inherited 256, let alone 2048.
        let highRatioN = SupportRegion.requiredRansacIterations(inlierRatio: 0.9)
        XCTAssertGreaterThan(highRatioN, 0)
        XCTAssertLessThan(highRatioN, 50)
        // Monotonically non-increasing in the observed inlier ratio.
        XCTAssertLessThanOrEqual(SupportRegion.requiredRansacIterations(inlierRatio: 0.5),
                                 SupportRegion.requiredRansacIterations(inlierRatio: 0.2))
    }
}
