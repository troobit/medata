import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Tests for VoxelCarveEstimator per design §6.6.
//
// Geometry (used for all tests):
//   Camera at origin, −Z forward, nadir orientation: gravity = (0,0,−1).
//   axisZ = −gravity = (0,0,1), axisX = (1,0,0), axisY = axisZ×axisX = (0,1,0).
//   Support plane: n̂=(0,0,1), distanceMm=−400 → table at z=−400 mm.
//   Grid 10×10×10 at 5 mm edge, origin (0,0,−400):
//     voxel p = (dx, dy, −400+dz), p.z ∈ [−397.5, −352.5] (all < 0 ✓).
//     u = 500·dx/(400−dz)+50 ∈ [~18, ~82]  (spans both halves of 100×100 image ✓).
//     v = 500·dy/(400−dz)+50 ∈ [~18, ~82].
//   Both views use the identity transform (same camera pose).

final class VoxelCarveEstimatorTests: XCTestCase {

    // MARK: - fixtures

    let palette = makePalette(numFood: 2)   // food_0=0, food_1=1, bg=2, liq=4

    let intrinsics = CameraIntrinsics(
        fx: 500, fy: 500, cx: 50, cy: 50,
        distortion: [], imageWidth: 100, imageHeight: 100
    )
    // n̂=(0,0,1), distanceMm=−400 → table at z=−400 mm.
    let plane = SupportPlane(
        normal: Vec3(0, 0, 1), distanceMm: -400,
        residualMm: 0.5, convergedIterations: nil
    )
    var grid: VoxelGrid {
        VoxelGrid(
            edgeMm: 5,
            dimsX: 10, dimsY: 10, dimsZ: 10,
            originCamera1: Vec3(0, 0, -400),
            axisX: Vec3(1, 0, 0),
            axisY: Vec3(0, 1, 0),
            axisZ: Vec3(0, 0, 1)
        )
    }

    // Uniform probability tensor: food_0 dominates.
    func makeFoodProbs(width: Int = 100, height: Int = 100) -> ProbabilityTensor {
        let bgId = palette.background
        return makeProbTensor(width: width, height: height, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
    }

    func makeBaseInputs(probs1: ProbabilityTensor? = nil,
                        probs2: ProbabilityTensor? = nil,
                        matched: Set<Int> = [0, 1],
                        beta: BetaCorrection = BetaCorrection()) -> VoxelCarveEstimator.Inputs {
        let p1 = probs1 ?? makeFoodProbs()
        let p2 = probs2 ?? makeFoodProbs()
        return VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: p1, intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: p2, intrinsics: intrinsics),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: matched,
            singleViewOnlyClassesView1: [],
            singleViewOnlyClassesView2: [],
            beta: beta,
            palette: palette
        )
    }

    // MARK: - T24.1 Synthetic cube volume within 5%

    func testSyntheticCubeVolumeWithin5Percent() throws {
        let inputs = makeBaseInputs()
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        // Analytical: 10×10×10 voxels × (5 mm)³ / 1000 = 125 cm³.
        let expected: Float = 125
        let vol = result.perClassVolumesCm3["food_0"] ?? 0
        XCTAssertLessThanOrEqual(abs(vol - expected), expected * 0.05,
            "Volume \(vol) cm³ not within 5% of \(expected) cm³")
    }

    // MARK: - T24.2 Silhouette test: (1 − q[bg]) ≥ τ_sil, not argmax=bg

    func testSilhouetteTestExcludesHighBgPixels() throws {
        // Right half of image (x >= 50) gets q_bg = 0.99 → fails silhouette.
        // Voxels projecting to x ∈ [18, 82] span both halves; only left-half
        // projections pass silhouette and should be counted.
        let bgId = palette.background
        let p = makeProbTensor(width: 100, height: 100, palette: palette) { _, x, c in
            if x >= 50 {
                return c == bgId ? 0.99 : 0.005
            }
            return c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let inputs = makeBaseInputs(probs1: p, probs2: p)
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        let count = result.perClassVoxelCount["food_0"] ?? 0
        XCTAssertGreaterThan(count, 0, "Some voxels must project to the non-masked region")
        XCTAssertLessThan(count, 1000, "Masked half must exclude a fraction of voxels")
    }

    // MARK: - T24.3 FP32 product promotion: correct argmax when two classes are close in FP16

    func testFP32ProductPromotionPicksCorrectWinner() throws {
        // food_0: q=0.501 in both views → product=0.251001.
        // food_1: q=0.499 in both views → product=0.249001.
        // Promote to FP32 before argmax (§6.0): food_0 wins.
        let bgId = palette.background
        let p = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            switch c {
            case 0:    return 0.501
            case 1:    return 0.499
            case bgId: return 0.0
            default:   return 0.0
            }
        }
        let inputs = makeBaseInputs(probs1: p, probs2: p, matched: [0, 1])
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        let c0 = result.perClassVoxelCount["food_0"] ?? 0
        let c1 = result.perClassVoxelCount["food_1"] ?? 0
        XCTAssertGreaterThan(c0, 0, "food_0 should win the argmax")
        XCTAssertEqual(c1, 0, "food_1 must not win when food_0 product is higher")
    }

    // MARK: - T24.4 Voxel ownership disjointness: per-class counts sum to total

    func testOwnershipDisjointness() throws {
        // food_0 wins in left half of image (x < 50), food_1 in right (x >= 50).
        // Since voxels project to u ∈ [18, 82] they hit both halves.
        let bgId = palette.background
        let p = makeProbTensor(width: 100, height: 100, palette: palette) { _, x, c in
            switch c {
            case bgId: return 0.05
            case 0:    return x < 50 ? 0.90 : 0.05
            case 1:    return x >= 50 ? 0.90 : 0.05
            default:   return 0.0
            }
        }
        let inputs = makeBaseInputs(probs1: p, probs2: p, matched: [0, 1])
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        let c0 = result.perClassVoxelCount["food_0"] ?? 0
        let c1 = result.perClassVoxelCount["food_1"] ?? 0
        XCTAssertGreaterThan(c0, 0, "food_0 should win in the left-image half")
        XCTAssertGreaterThan(c1, 0, "food_1 should win in the right-image half")
        // Voxels are disjoint: no voxel counted twice.
        // Ambiguity fraction should be ~0 (clear winner per pixel).
        XCTAssertEqual(result.ambiguousVoxelFraction, 0, accuracy: 0.01)
    }

    // MARK: - T24.5 Single-view-only fallback degraded extrusion

    func testSingleViewFallbackAppearsInDegradedClasses() throws {
        // food_1 only in view1 (matchedClasses={0}, singleViewOnlyView1={1}).
        // view1: food_1 clearly dominant (q=0.80), so argmax=food_1 for all pixels.
        let bgId = palette.background
        let p1 = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 1 ? 0.80 : (c == bgId ? 0.05 : 0.10)
        }
        let inputs = VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: p1, intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: makeFoodProbs(), intrinsics: intrinsics),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: [0],
            singleViewOnlyClassesView1: [1],
            singleViewOnlyClassesView2: [],
            beta: BetaCorrection(),
            palette: palette
        )
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        XCTAssertTrue(result.degradedClasses.contains("food_1"),
            "food_1 must appear in degradedClasses when single-view fallback is used")
        XCTAssertNotNil(result.perClassVolumesCm3["food_1"],
            "Single-view fallback must produce a volume estimate for food_1")
    }

    // MARK: - T24.6 τ_v = 0.04 ambiguous-voxel discard

    func testAmbiguousVoxelDiscardAtTauV() throws {
        // Left-half pixels: food_0 q=0.19 → product=0.0361 < τ_v=0.04 → ambiguous.
        // Right-half pixels: food_0 q=0.22 → product=0.0484 > τ_v=0.04 → assigned.
        let bgId = palette.background
        let p = makeProbTensor(width: 100, height: 100, palette: palette) { _, x, c in
            switch c {
            case bgId: return 0.05
            case 0:    return x < 50 ? 0.19 : 0.22
            default:   return 0.0
            }
        }
        let inputs = makeBaseInputs(probs1: p, probs2: p, matched: [0])
        let result = try XCTUnwrap(VoxelCarveEstimator.carve(inputs).estimate)
        XCTAssertGreaterThan(result.ambiguousVoxelFraction, 0,
            "Some voxels (left-half projections) should be ambiguous (product < τ_v=0.04)")
        XCTAssertLessThan(result.ambiguousVoxelFraction, 1,
            "Not all voxels should be ambiguous")
    }

    // MARK: - T24.7 noFoodVolumeRecovered when count below minVoxelCountForClass

    func testNoFoodVolumeRecoveredWhenCountTooLow() throws {
        // 3×3×3 = 27 voxels; minVoxelCountForClass=30 → class refused → throw.
        let tinyGrid = VoxelGrid(
            edgeMm: 5, dimsX: 3, dimsY: 3, dimsZ: 3,
            originCamera1: Vec3(0, 0, -400),
            axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1)
        )
        let inputs = VoxelCarveEstimator.Inputs(
            grid: tinyGrid,
            view1: VoxelCarveView(probabilities: makeFoodProbs(), intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: makeFoodProbs(), intrinsics: intrinsics),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: [0],
            singleViewOnlyClassesView1: [],
            singleViewOnlyClassesView2: [],
            beta: BetaCorrection(),
            palette: palette
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertNil(outcome.estimate)
        XCTAssertEqual(outcome.refusal, VolumeError.noFoodVolumeRecovered)
    }
}
