import PortableContracts
import XCTest
@testable import Confidence

// Tests for Confidence.combine per design §6.8 / Req 13 / task 39.
//
// Fixed input conventions used throughout:
//   sigmaScale = 0.85    (LiDAR-only, Req 7.3)
//   sigmaSeg   = 0.80    (representative mean class probability)
//   residual   = 2.0 mm  → σ_plane = exp(−2/5) ≈ 0.6703

final class ConfidenceTests: XCTestCase {

    // MARK: - T39.1 Geometric mean formula

    func testGeometricMeanFormula() {
        // Two-view full path (no occlusion, no card-only penalty):
        //   σ_view  = 1.00
        //   σ_plane = exp(−2/5) ≈ 0.670320
        //   σ_occl  = 1.00
        //   σ_geom  = 1.00 × 0.670320 × 1.00 = 0.670320
        //   σ_s_tilde   = max(0.05, 0.85) = 0.85
        //   σ_seg_tilde  = max(0.05, 0.80) = 0.80
        //   σ_geom_tilde = max(0.05, 0.670320) = 0.670320
        //   σ_meal = (0.85 × 0.80 × 0.670320)^(1/3) ≈ 0.7527
        let result = Confidence.combine(
            sigmaScale: 0.85,
            sigmaSeg: 0.80,
            planeFitResidualMm: 2.0,
            viewCoverage: .twoViewFull,
            capturePath: .twoViewSfS,
            interClassOcclusionDetected: false,
            cardOnlyPath: false,
            cardOnlyIterations: 3
        )
        let sigmaPlane = Float(Foundation.exp(-2.0 / 5.0))
        let sigmaGeom  = 1.00 * sigmaPlane * 1.00
        let expected   = Foundation.pow(0.85 * 0.80 * sigmaGeom, 1.0 / 3.0)
        XCTAssertEqual(result.sigmaMeal, expected, accuracy: 1e-5)
    }

    // MARK: - T39.2 ε = 0.05 floor per top-level input (not sub-factors)

    func testEpsilonFloorAppliedToTopLevelInputs() {
        // Drive σ_s and σ_seg below ε; residual = 100 mm → σ_plane ≈ 0 → σ_geom ≈ 0.
        // After flooring all three at 0.05:  σ_meal = (0.05 × 0.05 × 0.05)^(1/3) = 0.05.
        let result = Confidence.combine(
            sigmaScale: 0.0,
            sigmaSeg: 0.0,
            planeFitResidualMm: 500.0,   // → σ_plane ≈ 0 → σ_geom ≈ 0 → floored to 0.05
            viewCoverage: .twoViewFull,
            capturePath: .twoViewSfS,
            interClassOcclusionDetected: false,
            cardOnlyPath: false,
            cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaMeal, 0.05, accuracy: 1e-5,
                       "All three inputs floored to ε → geometric mean = ε")
    }

    func testEpsilonFloorOnSigmaScaleOnly() {
        // σ_s = 0.0 → floored to 0.05; σ_seg and σ_geom remain above ε.
        // σ_plane = exp(0) = 1.0 (residual = 0), σ_geom = 1.0
        // σ_meal = (0.05 × 0.80 × 1.0)^(1/3)
        let result = Confidence.combine(
            sigmaScale: 0.0,
            sigmaSeg: 0.80,
            planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull,
            capturePath: .twoViewSfS,
            interClassOcclusionDetected: false,
            cardOnlyPath: false,
            cardOnlyIterations: 0
        )
        let expected = Foundation.pow(Float(0.05 * 0.80 * 1.0), 1.0 / 3.0)
        XCTAssertEqual(result.sigmaMeal, expected, accuracy: 1e-5)
    }

    // MARK: - T39.3 σ_geom sub-factors are NOT individually floored

    func testGeomSubfactorsNotIndividuallyFloored() {
        // σ_plane near zero (huge residual), but σ_view and σ_occl = 1.0.
        // σ_geom = 1.0 × ~0 × 1.0 ≈ 0 → floored to ε = 0.05 at the σ_geom level only.
        let result = Confidence.combine(
            sigmaScale: 0.85,
            sigmaSeg: 0.80,
            planeFitResidualMm: 1000.0,   // exp(−200) ≈ 0
            viewCoverage: .twoViewFull,
            capturePath: .twoViewSfS,
            interClassOcclusionDetected: false,
            cardOnlyPath: false,
            cardOnlyIterations: 0
        )
        // sigmaPlane itself is not stored floored
        XCTAssertLessThan(result.sigmaGeom.sigmaPlane, 0.05,
                          "sigmaPlane sub-factor stored as-is (not floored individually)")
        // But sigmaMeal should still be ≥ ε
        XCTAssertGreaterThanOrEqual(result.sigmaMeal, Confidence.epsilon)
    }

    // MARK: - T39.4 σ_geom_view lookup table per Req 13.2

    func testSigmaViewTwoViewFull() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaView, 1.00, accuracy: 1e-6)
    }

    func testSigmaViewSingleViewFull() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .singleViewFull, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.90, accuracy: 1e-6)
    }

    func testSigmaViewTwoViewPartial() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewPartial, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.75, accuracy: 1e-6)
    }

    func testSigmaViewSingleViewPartial() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .singleViewPartial, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.60, accuracy: 1e-6)
    }

    // MARK: - T39.5 σ_plane = exp(−r/5), with ×0.9 penalty when card-only best-of-5

    func testSigmaPlaneFormula() {
        // r = 3 mm → σ_plane = exp(−3/5) ≈ 0.5488
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 3.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        let expected = Float(Foundation.exp(-3.0 / 5.0))
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, expected, accuracy: 1e-5)
    }

    func testSigmaPlanePenaltyAppliedWhenCardOnlyBestOfFive() {
        // cardOnlyPath = true AND iterations = 5 → ×0.9 penalty
        let r: Float = 3.0
        let basePlane = Float(Foundation.exp(-Double(r) / 5.0))
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: r,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: true, cardOnlyIterations: 5
        )
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, basePlane * 0.9, accuracy: 1e-5)
    }

    func testSigmaPlanePenaltyNotAppliedWhenIterationsLessThanFive() {
        let r: Float = 3.0
        let basePlane = Float(Foundation.exp(-Double(r) / 5.0))
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: r,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: true, cardOnlyIterations: 3
        )
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, basePlane, accuracy: 1e-5)
    }

    func testSigmaPlanePenaltyNotAppliedWhenNotCardOnlyPath() {
        // iterations = 5 but cardOnlyPath = false → no penalty
        let r: Float = 3.0
        let basePlane = Float(Foundation.exp(-Double(r) / 5.0))
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: r,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 5
        )
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, basePlane, accuracy: 1e-5)
    }

    // MARK: - T39.6 σ_occl = 0.80 only on single-view with inter-class occlusion

    func testSigmaOcclReducedOnSingleViewWithOcclusion() {
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 0.0,
            viewCoverage: .singleViewFull, capturePath: .singleViewLidar,
            interClassOcclusionDetected: true, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaOccl, 0.80, accuracy: 1e-6)
    }

    func testSigmaOcclIsOneOnTwoViewPathEvenWithOcclusion() {
        // Two-view path: σ_occl = 1.00 regardless (oblique view recovers occluded regions)
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: true, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaOccl, 1.00, accuracy: 1e-6)
    }

    func testSigmaOcclIsOneOnSingleViewWithoutOcclusion() {
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 0.0,
            viewCoverage: .singleViewFull, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaOccl, 1.00, accuracy: 1e-6)
    }

    // MARK: - T39.7 Bounds: σ_meal ∈ [ε, 1] always

    func testSigmaMealAlwaysAtLeastEpsilon() {
        // Worst case: all inputs = 0
        let result = Confidence.combine(
            sigmaScale: 0.0, sigmaSeg: 0.0, planeFitResidualMm: 1_000_000.0,
            viewCoverage: .singleViewPartial, capturePath: .singleViewLidar,
            interClassOcclusionDetected: true, cardOnlyPath: true, cardOnlyIterations: 5
        )
        XCTAssertGreaterThanOrEqual(result.sigmaMeal, Confidence.epsilon)
    }

    func testSigmaMealAtMostOne() {
        // Best case: all inputs = 1
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertLessThanOrEqual(result.sigmaMeal, 1.0)
        XCTAssertEqual(result.sigmaMeal, 1.0, accuracy: 1e-5)
    }

    // MARK: - T39.8 Sub-confidences persisted in result (Req 13.4)

    func testSubConfidencesPersisted() {
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.72, planeFitResidualMm: 1.5,
            viewCoverage: .singleViewFull, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaScale, 0.85, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaSeg,   0.72, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.90, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, Float(Foundation.exp(-1.5 / 5.0)), accuracy: 1e-5)
        XCTAssertEqual(result.sigmaGeom.sigmaOccl, 1.00, accuracy: 1e-6)
    }

    // MARK: - T39.9 Uncertain threshold constant is 0.6

    func testUncertainThresholdValue() {
        XCTAssertEqual(Confidence.uncertainThreshold, 0.6, accuracy: 1e-6)
    }

    // MARK: - T39.10 Zero residual → σ_plane = 1.0

    func testZeroResidualGivesMaxPlane() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, 1.0, accuracy: 1e-5)
    }
}
