import PortableContracts
import XCTest
@testable import Confidence

// Tests for Confidence.combine per design §6.8 / Req 13 / task 39.
//
// Fixed input conventions used throughout:
//   sigmaScale = 0.85    (LiDAR-only, Req 7.3)
//   sigmaSeg   = 0.80    (representative mean class probability)
//   residual   = 2.0 mm  → σ_plane = exp(−2/5) ≈ 0.6703
//
// After T85 / Decision 44/45 σ_geom is the product of FOUR factors
//   σ_view · σ_plane · σ_occl · σ_tilt
// and ε is 0.01 (was 0.05).

final class ConfidenceTests: XCTestCase {

    // MARK: - T39.1 Geometric mean formula

    func testGeometricMeanFormula() {
        // Two-view full path (no occlusion, no card-only penalty, Δθ = 0):
        //   σ_view  = 1.00
        //   σ_plane = exp(−2/5) ≈ 0.670320
        //   σ_occl  = 1.00
        //   σ_tilt  = cos(0°) = 1.00
        //   σ_geom  = 1.00 × 0.670320 × 1.00 × 1.00 = 0.670320
        //   σ_s_tilde    = max(0.01, 0.85) = 0.85
        //   σ_seg_tilde  = max(0.01, 0.80) = 0.80
        //   σ_geom_tilde = max(0.01, 0.670320) = 0.670320
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
        let sigmaGeom  = 1.00 * sigmaPlane * 1.00 * 1.00
        let expected   = Foundation.pow(0.85 * 0.80 * sigmaGeom, 1.0 / 3.0)
        XCTAssertEqual(result.sigmaMeal, expected, accuracy: 1e-5)
    }

    // MARK: - T39.2 ε = 0.01 floor per top-level input (not sub-factors)

    func testEpsilonFloorAppliedToTopLevelInputs() {
        // Drive σ_s and σ_seg below ε; residual = 500 mm → σ_plane ≈ 0 → σ_geom ≈ 0.
        // After flooring all three at 0.01:  σ_meal = (0.01)^3^(1/3) = 0.01.
        let result = Confidence.combine(
            sigmaScale: 0.0,
            sigmaSeg: 0.0,
            planeFitResidualMm: 500.0,
            viewCoverage: .twoViewFull,
            capturePath: .twoViewSfS,
            interClassOcclusionDetected: false,
            cardOnlyPath: false,
            cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaMeal, 0.01, accuracy: 1e-5,
                       "All three inputs floored to ε → geometric mean = ε")
    }

    func testEpsilonFloorOnSigmaScaleOnly() {
        // σ_s = 0.0 → floored to 0.01; σ_seg and σ_geom remain above ε.
        // σ_plane = exp(0) = 1.0, σ_geom = 1.0
        // σ_meal = (0.01 × 0.80 × 1.0)^(1/3)
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
        let expected = Foundation.pow(Float(0.01 * 0.80 * 1.0), 1.0 / 3.0)
        XCTAssertEqual(result.sigmaMeal, expected, accuracy: 1e-5)
    }

    // MARK: - T39.3 σ_geom sub-factors are NOT individually floored

    func testGeomSubfactorsNotIndividuallyFloored() {
        // σ_plane near zero (huge residual), but σ_view, σ_occl, σ_tilt = 1.0.
        // σ_geom = 1.0 × ~0 × 1.0 × 1.0 ≈ 0 → floored to ε at the σ_geom level.
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
        XCTAssertLessThan(result.sigmaGeom.sigmaPlane, 0.01,
                          "sigmaPlane sub-factor stored as-is (not floored individually)")
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

    // T89: 30–50% coverage → σ_view = 0.30 (singleViewMinimal tier).
    func testSigmaViewSingleViewMinimal() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .singleViewMinimal, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.30, accuracy: 1e-6)
    }

    // MARK: - T39.5 σ_plane = exp(−r/5), with ×0.9 penalty when card-only best-of-5

    func testSigmaPlaneFormula() {
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 3.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0
        )
        let expected = Float(Foundation.exp(-3.0 / 5.0))
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, expected, accuracy: 1e-5)
    }

    func testSigmaPlanePenaltyAppliedWhenCardOnlyBestOfFive() {
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

    // MARK: - T85: σ_tilt = max(ε, cos(Δθ))

    func testSigmaTiltIsOneAtZeroDegrees() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 0
        )
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, 1.0, accuracy: 1e-6)
    }

    func testSigmaTiltAtFifteenDegrees() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 15
        )
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, Float(cos(15.0 * .pi / 180)), accuracy: 1e-5)
        // ≈ 0.9659
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, 0.9659, accuracy: 1e-3)
    }

    func testSigmaTiltFlooredAtNinetyDegrees() {
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 90
        )
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, Confidence.epsilon, accuracy: 1e-6)
    }

    func testSigmaTiltTwoViewTakesWorseOfNadirAndOblique() {
        // Worse-of: nadir 5° gives cos(5°)≈0.996; oblique 20° gives cos(20°)≈0.940.
        // The combiner must take the smaller (worse) of the two.
        let result = Confidence.combine(
            sigmaScale: 1.0, sigmaSeg: 1.0, planeFitResidualMm: 0.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 5,
            deltaThetaObliqueDeg: 20
        )
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, Float(cos(20.0 * .pi / 180)), accuracy: 1e-5)
    }

    // MARK: - T90: σ_meal floors at ε = 0.01 when all sub-confidences are zero

    func testSigmaMealFloorsAtEpsilonZeroOneWhenAllZero() {
        let result = Confidence.combine(
            sigmaScale: 0.0, sigmaSeg: 0.0, planeFitResidualMm: 10_000.0,
            viewCoverage: .singleViewMinimal, capturePath: .singleViewLidar,
            interClassOcclusionDetected: true, cardOnlyPath: true, cardOnlyIterations: 5,
            deltaThetaNadirDeg: 90
        )
        XCTAssertEqual(result.sigmaMeal, 0.01, accuracy: 1e-5)
    }

    // MARK: - T90: four-factor reduces to three-factor when σ_tilt = 1.0

    func testFourFactorReducesToThreeFactorWhenSigmaTiltOne() {
        // Compute the four-factor product directly at Δθ = 0 and verify it
        // equals σ_view * σ_plane * σ_occl (the pre-T85 three-factor σ_geom).
        let result = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.72, planeFitResidualMm: 1.5,
            viewCoverage: .singleViewFull, capturePath: .singleViewLidar,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 0
        )
        let g = result.sigmaGeom
        XCTAssertEqual(g.product, g.sigmaView * g.sigmaPlane * g.sigmaOccl, accuracy: 1e-6,
                       "When σ_tilt = 1.0 the four-factor product equals the three-factor product")
    }

    // MARK: - T39.7 Bounds: σ_meal ∈ [ε, 1] always

    func testSigmaMealAlwaysAtLeastEpsilon() {
        let result = Confidence.combine(
            sigmaScale: 0.0, sigmaSeg: 0.0, planeFitResidualMm: 1_000_000.0,
            viewCoverage: .singleViewMinimal, capturePath: .singleViewLidar,
            interClassOcclusionDetected: true, cardOnlyPath: true, cardOnlyIterations: 5
        )
        XCTAssertGreaterThanOrEqual(result.sigmaMeal, Confidence.epsilon)
    }

    func testSigmaMealAtMostOne() {
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
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 10
        )
        XCTAssertEqual(result.sigmaScale, 0.85, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaSeg,   0.72, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaGeom.sigmaView, 0.90, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, Float(Foundation.exp(-1.5 / 5.0)), accuracy: 1e-5)
        XCTAssertEqual(result.sigmaGeom.sigmaOccl, 1.00, accuracy: 1e-6)
        XCTAssertEqual(result.sigmaGeom.sigmaTilt, Float(cos(10.0 * .pi / 180)), accuracy: 1e-5)
        XCTAssertEqual(result.deltaThetaNadirDeg, 10, accuracy: 1e-6)
        XCTAssertNil(result.deltaThetaObliqueDeg)
    }

    // MARK: - T39.9 Uncertain threshold constant is 0.6

    func testUncertainThresholdValue() {
        XCTAssertEqual(Confidence.uncertainThreshold, 0.6, accuracy: 1e-6)
    }

    // MARK: - Epsilon constant is 0.01 per Decision 45

    func testEpsilonConstantIsZeroPointZeroOne() {
        XCTAssertEqual(Confidence.epsilon, 0.01, accuracy: 1e-6)
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

    // MARK: - T84: legacy decode of GeomSubconfidences without sigmaTilt → 1.0

    func testLegacyGeomDecodeDefaultsSigmaTiltToOne() throws {
        // Encode a JSON blob shaped like the v0.4 record (no sigmaTilt key).
        let legacyJSON = """
        {"sigmaView":0.90,"sigmaPlane":0.5488,"sigmaOccl":1.0}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GeomSubconfidences.self, from: legacyJSON)
        XCTAssertEqual(decoded.sigmaTilt, 1.0, accuracy: 1e-6,
                       "Legacy records re-derive σ_tilt = 1.0 per Req 13.4 / Decision 44")
        // σ_meal computed from the legacy record stays equal to the original
        // three-factor product (identity multiplier).
        XCTAssertEqual(decoded.product,
                       decoded.sigmaView * decoded.sigmaPlane * decoded.sigmaOccl,
                       accuracy: 1e-6)
    }

    func testLegacyConfidenceResultDecodeDefaultsDeltaThetaFields() throws {
        let legacyJSON = """
        {
            "sigmaMeal":0.7,
            "sigmaScale":0.85,
            "sigmaSeg":0.80,
            "sigmaGeom":{"sigmaView":0.90,"sigmaPlane":0.5488,"sigmaOccl":1.0}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ConfidenceResult.self, from: legacyJSON)
        XCTAssertEqual(decoded.deltaThetaNadirDeg, 0, accuracy: 1e-6)
        XCTAssertNil(decoded.deltaThetaObliqueDeg)
        XCTAssertEqual(decoded.sigmaGeom.sigmaTilt, 1.0, accuracy: 1e-6)
    }

    // MARK: - T84: round-trip with the new fields

    func testRoundTripWithNewFields() throws {
        let original = Confidence.combine(
            sigmaScale: 0.85, sigmaSeg: 0.80, planeFitResidualMm: 2.0,
            viewCoverage: .twoViewFull, capturePath: .twoViewSfS,
            interClassOcclusionDetected: false, cardOnlyPath: false, cardOnlyIterations: 0,
            deltaThetaNadirDeg: 3,
            deltaThetaObliqueDeg: 12
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConfidenceResult.self, from: encoded)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.deltaThetaNadirDeg, 3, accuracy: 1e-6)
        XCTAssertEqual(decoded.deltaThetaObliqueDeg ?? -1, 12, accuracy: 1e-6)
    }
}
