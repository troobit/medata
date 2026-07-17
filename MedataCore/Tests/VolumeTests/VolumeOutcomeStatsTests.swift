import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Tests for the non-throwing VolumeOutcome estimator surface (snaq-parity
// tasks 1–2, Req 3.1/3.2). The estimators return
// VolumeOutcome { estimate, stats, refusal } instead of throwing, so the
// stage measurements — per-class pre/post-β volumes, threshold discards, and
// degenerate voxel/ray skip counters — survive a refusal instead of dying
// with the throw. Geometry conventions match VoxelCarveEstimatorTests /
// HeightFieldEstimatorTests.

final class VolumeOutcomeStatsTests: XCTestCase {

    // MARK: - fixtures (shared conventions with the sibling suites)

    let palette = makePalette(numFood: 2)   // food_0=0, food_1=1, bg=2, liq=4

    let intrinsics = CameraIntrinsics(
        fx: 500, fy: 500, cx: 50, cy: 50,
        distortion: [], imageWidth: 100, imageHeight: 100
    )
    // n̂=(0,0,1), distanceMm=−400 → table at z=−400 mm (carve fixtures).
    let carvePlane = SupportPlane(
        normal: Vec3(0, 0, 1), distanceMm: -400,
        residualMm: 0.5, convergedIterations: nil
    )
    // n̂=(0,0,1), distanceMm=−600 → table at z=−600 mm (height-field fixtures).
    let heightFieldPlane = SupportPlane(
        normal: Vec3(0, 0, 1), distanceMm: -600,
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

    func makeFoodProbs(width: Int = 100, height: Int = 100) -> ProbabilityTensor {
        let bgId = palette.background
        return makeProbTensor(width: width, height: height, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
    }

    // All-background tensor: silhouette test fails everywhere.
    func makeAllBgProbs(width: Int = 100, height: Int = 100) -> ProbabilityTensor {
        let bgId = palette.background
        return makeProbTensor(width: width, height: height, palette: palette) { _, _, c in
            c == bgId ? 0.99 : 0.0025
        }
    }

    func carveInputs(
        probs1: ProbabilityTensor,
        probs2: ProbabilityTensor,
        grid: VoxelGrid? = nil,
        plane: SupportPlane? = nil,
        matched: Set<Int> = [0, 1],
        singleViewOnly1: Set<Int> = [],
        beta: BetaCorrection = BetaCorrection()
    ) -> VoxelCarveEstimator.Inputs {
        VoxelCarveEstimator.Inputs(
            grid: grid ?? self.grid,
            view1: VoxelCarveView(probabilities: probs1, intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: probs2, intrinsics: intrinsics),
            transform1To2: .identity,
            supportPlane: plane ?? carvePlane,
            matchedClasses: matched,
            singleViewOnlyClassesView1: singleViewOnly1,
            singleViewOnlyClassesView2: [],
            beta: beta,
            palette: palette
        )
    }

    func heightFieldInputs(
        depthMm: @escaping (Int, Int) -> Float,
        conf: @escaping (Int, Int) -> UInt8 = { _, _ in 255 },
        plane: SupportPlane? = nil,
        beta: BetaCorrection = BetaCorrection()
    ) -> HeightFieldEstimator.Inputs {
        let bgId = palette.background
        let probs = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let argm = makeArgmax(width: 100, height: 100) { _, _ in 0 }
        let depth = makeDepthMap(width: 100, height: 100, intrinsics: intrinsics,
                                 depthMm: depthMm, conf: conf)
        return HeightFieldEstimator.Inputs(
            probabilities: probs, argmax: argm, depth: depth,
            intrinsics: intrinsics, supportPlane: plane ?? heightFieldPlane,
            beta: beta, palette: palette
        )
    }

    // MARK: - VoxelCarveEstimator: stats survive refusal

    // Tiny single-view fallback class (< 1 cm³ post-β) was silently dropped at
    // VoxelCarveEstimator's tiny-class refusal; the refusal record must still
    // carry the recovered pre-β volume and name the discarded class.
    func testCarveTinyFallbackDropSurvivesRefusal() throws {
        let bgId = palette.background
        // 10 pixels of food_1 in view 1 (row y=50, x 40..<50); background elsewhere.
        // Extruded volume ≈ 10 px × ~19 mm³ ≈ 0.19 cm³ < 1 cm³ → discarded.
        let p1 = makeProbTensor(width: 100, height: 100, palette: palette) { y, x, c in
            if y == 50 && (40..<50).contains(x) {
                return c == 1 ? 0.80 : (c == bgId ? 0.05 : 0.05)
            }
            return c == bgId ? 0.99 : 0.0025
        }
        let inputs = carveInputs(
            probs1: p1, probs2: makeAllBgProbs(),
            matched: [], singleViewOnly1: [1]
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertEqual(outcome.refusal, VolumeError.noFoodVolumeRecovered)
        XCTAssertNil(outcome.estimate)
        let preBeta = outcome.stats.perClassVolumesPreBetaCm3["food_1"] ?? 0
        XCTAssertGreaterThan(preBeta, 0,
            "pre-β volume of the discarded tiny class must survive the refusal")
        XCTAssertLessThan(preBeta, 1)
        XCTAssertTrue(outcome.stats.thresholdDiscardedClasses.contains("food_1"),
            "the tiny-class drop must be named, not silent")
    }

    // Classes carved with fewer than minVoxelCountForClass voxels were silently
    // dropped; the refusal must retain their pre-β volume and name them.
    func testCarveMinVoxelCountDropSurvivesRefusal() throws {
        // 3×3×3 = 27 voxels < minVoxelCountForClass (30) → class discarded.
        let tinyGrid = VoxelGrid(
            edgeMm: 5, dimsX: 3, dimsY: 3, dimsZ: 3,
            originCamera1: Vec3(0, 0, -400),
            axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1)
        )
        let inputs = carveInputs(
            probs1: makeFoodProbs(), probs2: makeFoodProbs(),
            grid: tinyGrid, matched: [0]
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertEqual(outcome.refusal, VolumeError.noFoodVolumeRecovered)
        XCTAssertNil(outcome.estimate)
        // 27 voxels × 125 mm³ = 3.375 cm³ recovered before the count threshold.
        let preBeta = outcome.stats.perClassVolumesPreBetaCm3["food_0"] ?? 0
        XCTAssertEqual(preBeta, 3.375, accuracy: 0.35)
        XCTAssertTrue(outcome.stats.thresholdDiscardedClasses.contains("food_0"))
    }

    // Voxels that pass the silhouette test in both views but resolve to no
    // owning class were silently skipped; they must be counted.
    func testCarveDegenerateVoxelSkipCounted() throws {
        // Both views all-food but matchedClasses is empty → every voxel that
        // passes the silhouette test has no ownership candidate.
        let inputs = carveInputs(
            probs1: makeFoodProbs(), probs2: makeFoodProbs(), matched: []
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertEqual(outcome.refusal, VolumeError.noFoodVolumeRecovered)
        XCTAssertEqual(outcome.stats.degenerateVoxelSkipCount, 1000,
            "all 10×10×10 voxels pass the silhouette test and must be counted as ownerless skips")
    }

    // Degenerate rays in the single-view extrusion (support plane parallel to
    // the ray, or the intersection behind the camera) were silently skipped.
    func testCarveDegenerateRaySkipCounted() throws {
        let bgId = palette.background
        // Whole view-1 frame is food_1; support plane normal (1,0,0) makes the
        // column x = cx parallel (denominator ≈ 0) and every x > cx intersect
        // behind the camera (α ≤ 0): 100 + 49×100 = 5 000 skipped rays.
        let sidePlane = SupportPlane(
            normal: Vec3(1, 0, 0), distanceMm: -400,
            residualMm: 0.5, convergedIterations: nil
        )
        let p1 = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 1 ? 0.80 : (c == bgId ? 0.05 : 0.05)
        }
        let inputs = carveInputs(
            probs1: p1, probs2: makeAllBgProbs(),
            plane: sidePlane, matched: [], singleViewOnly1: [1]
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertEqual(outcome.stats.degenerateRaySkipCount, 5000)
    }

    // Success path: stats carry pre-β and post-β volumes consistent with the
    // estimate, plus the β factor applied per class.
    func testCarveSuccessStatsCarryBetaDecomposition() throws {
        let beta = BetaCorrection(entries: ["food_0": 0.5])
        let inputs = carveInputs(
            probs1: makeFoodProbs(), probs2: makeFoodProbs(),
            matched: [0], beta: beta
        )
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertNil(outcome.refusal)
        let estimate = try XCTUnwrap(outcome.estimate)
        let pre = try XCTUnwrap(outcome.stats.perClassVolumesPreBetaCm3["food_0"])
        let post = try XCTUnwrap(outcome.stats.perClassVolumesPostBetaCm3["food_0"])
        XCTAssertEqual(pre, 125, accuracy: 125 * 0.05)
        XCTAssertEqual(post, pre * 0.5, accuracy: 0.01)
        XCTAssertEqual(estimate.perClassVolumesCm3["food_0"], post)
        XCTAssertEqual(outcome.stats.betaApplied["food_0"], 0.5)
        XCTAssertTrue(outcome.stats.thresholdDiscardedClasses.isEmpty)
    }

    // Guard failures become refusals too — the surface no longer throws.
    func testCarveMismatchedDimensionsIsRefusal() throws {
        let smallPalette = makePalette(numFood: 1)   // classes ≠ inputs.palette
        let bgId = smallPalette.background
        let p = makeProbTensor(width: 100, height: 100, palette: smallPalette) { _, _, c in
            c == bgId ? 0.05 : 0.90
        }
        let inputs = carveInputs(probs1: p, probs2: p)
        let outcome = VoxelCarveEstimator.carve(inputs)
        XCTAssertNil(outcome.estimate)
        if case .mismatchedViewDimensions = outcome.refusal {
            // expected
        } else {
            XCTFail("Expected mismatchedViewDimensions refusal, got \(String(describing: outcome.refusal))")
        }
    }

    // MARK: - HeightFieldEstimator: stats survive refusal

    // A noFoodVolumeRecovered refusal (all classes sub-threshold) must retain
    // the recovered pre-β volumes and name the sub-threshold classes.
    func testHeightFieldTinyVolumeSurvivesRefusal() throws {
        // Food top at 599.99 mm over a table at 600 mm → 0.01 mm height →
        // ≈ 0.14 cm³ total, below the 1 cm³ floor.
        let inputs = heightFieldInputs(depthMm: { _, _ in 599.99 })
        let outcome = HeightFieldEstimator.integrate(inputs)
        XCTAssertEqual(outcome.refusal, VolumeError.noFoodVolumeRecovered)
        XCTAssertNil(outcome.estimate)
        let preBeta = outcome.stats.perClassVolumesPreBetaCm3["food_0"] ?? 0
        XCTAssertGreaterThan(preBeta, 0,
            "pre-β volume must survive the noFoodVolumeRecovered refusal")
        XCTAssertLessThan(preBeta, 1)
        XCTAssertTrue(outcome.stats.thresholdDiscardedClasses.contains("food_0"))
    }

    // A lidarCoverageTooLow refusal must retain the per-class coverage
    // fractions and whatever volume the covered pixels recovered.
    func testHeightFieldCoverageRefusalSurvivesWithStats() throws {
        // Only the first 20 columns have usable confidence → 20% coverage,
        // below the 30% refusal floor.
        let inputs = heightFieldInputs(
            depthMm: { _, _ in 500 },
            conf: { _, x in x < 20 ? 255 : 0 }
        )
        let outcome = HeightFieldEstimator.integrate(inputs)
        XCTAssertNil(outcome.estimate)
        if case .lidarCoverageTooLow(let classes) = outcome.refusal {
            XCTAssertTrue(classes.contains("food_0"))
        } else {
            XCTFail("Expected lidarCoverageTooLow refusal, got \(String(describing: outcome.refusal))")
        }
        let frac = outcome.stats.lidarCoverageFraction["food_0"] ?? 0
        XCTAssertEqual(frac, 0.20, accuracy: 0.02)
        XCTAssertGreaterThan(outcome.stats.perClassVolumesPreBetaCm3["food_0"] ?? 0, 0,
            "volume recovered from the covered pixels must survive the coverage refusal")
    }

    // Degenerate rays (support plane parallel to the pixel ray) were silently
    // skipped in the integrator; they must be counted.
    func testHeightFieldDegenerateRaySkipCounted() throws {
        // Support plane normal (1,0,0): the column x = cx has rays with a zero
        // plane-normal component → 100 degenerate-ray skips.
        let sidePlane = SupportPlane(
            normal: Vec3(1, 0, 0), distanceMm: -400,
            residualMm: 0.5, convergedIterations: nil
        )
        let inputs = heightFieldInputs(depthMm: { _, _ in 500 }, plane: sidePlane)
        let outcome = HeightFieldEstimator.integrate(inputs)
        XCTAssertEqual(outcome.stats.degenerateRaySkipCount, 100)
    }

    // Success path: stats carry the β decomposition consistent with the estimate.
    func testHeightFieldSuccessStatsCarryBetaDecomposition() throws {
        let beta = BetaCorrection(entries: ["food_0": 0.5])
        let inputs = heightFieldInputs(depthMm: { _, _ in 500 }, beta: beta)
        let outcome = HeightFieldEstimator.integrate(inputs)
        XCTAssertNil(outcome.refusal)
        let estimate = try XCTUnwrap(outcome.estimate)
        let pre = try XCTUnwrap(outcome.stats.perClassVolumesPreBetaCm3["food_0"])
        let post = try XCTUnwrap(outcome.stats.perClassVolumesPostBetaCm3["food_0"])
        XCTAssertEqual(post, pre * 0.5, accuracy: pre * 0.001)
        XCTAssertEqual(estimate.perClassVolumesCm3["food_0"], post)
        XCTAssertEqual(outcome.stats.betaApplied["food_0"], 0.5)
        XCTAssertEqual(outcome.stats.lidarCoverageFraction, estimate.lidarCoverageFraction)
    }

    func testHeightFieldMismatchedDimensionsIsRefusal() throws {
        let bgId = palette.background
        let probs = makeProbTensor(width: 50, height: 50, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let argm = makeArgmax(width: 100, height: 100) { _, _ in 0 }
        let depth = makeDepthMap(width: 100, height: 100, intrinsics: intrinsics,
                                 depthMm: { _, _ in 500 })
        let inputs = HeightFieldEstimator.Inputs(
            probabilities: probs, argmax: argm, depth: depth,
            intrinsics: intrinsics, supportPlane: heightFieldPlane,
            beta: BetaCorrection(), palette: palette
        )
        let outcome = HeightFieldEstimator.integrate(inputs)
        XCTAssertNil(outcome.estimate)
        if case .mismatchedViewDimensions = outcome.refusal {
            // expected
        } else {
            XCTFail("Expected mismatchedViewDimensions refusal, got \(String(describing: outcome.refusal))")
        }
    }
}
