import PortableContracts
import XCTest
@testable import Confidence

// Task 13: the fallback confidence penalty of
// `specs/estimation/support-plane-reference/` Req 4.6 and Decision 12.
//
//   sigmaPlane = exp(-r/5) * iter_penalty * fallbackPenalty
//
// The penalty is a separate multiplicative factor, NOT an adjustment to the
// residual: the fallback plane can fit its surface perfectly while referencing
// the wrong one, so `planeResidualMm` must stay the measured residual.
final class SupportPlaneFallbackPenaltyTests: XCTestCase {

    private func combine(residualMm: Float, fallback: Bool,
                         cardOnlyPath: Bool = false,
                         cardOnlyIterations: Int = 0) -> ConfidenceResult {
        Confidence.combine(
            sigmaScale: 0.85,
            sigmaSeg: 0.80,
            planeFitResidualMm: residualMm,
            viewCoverage: .twoViewFull,
            capturePath: .singleViewLidar,
            interClassOcclusionDetected: false,
            cardOnlyPath: cardOnlyPath,
            cardOnlyIterations: cardOnlyIterations,
            supportPlaneFallback: fallback
        )
    }

    func testFallbackAppliesTheMultiplicativePenaltyToSigmaPlane() {
        let expected = exp(Float(-2.0) / 5) * Confidence.supportPlaneFallbackPenalty
        let result = combine(residualMm: 2.0, fallback: true)
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, expected, accuracy: 1e-6)
    }

    // Req 4.6 stated directly: equal residual, fallback must not read higher.
    func testFallbackConfidenceIsNeverHigherThanARestrictedFitOfEqualResidual() {
        for residual in [Float(0), 1, 2, 5, 12] {
            let restricted = combine(residualMm: residual, fallback: false)
            let fallback = combine(residualMm: residual, fallback: true)
            XCTAssertLessThan(fallback.sigmaGeom.sigmaPlane, restricted.sigmaGeom.sigmaPlane,
                              "residual \(residual) mm")
            XCTAssertLessThan(fallback.sigmaMeal, restricted.sigmaMeal,
                              "residual \(residual) mm")
        }
    }

    // Decision 12: the penalty lives on the confidence surface only. `combine` is a
    // pure function of the residual it is handed and never rewrites it, so the
    // value the attempt record persists is unaffected by which reference was used.
    func testTheResidualIsUnchangedByThePenalty() {
        let residualMm: Float = 3.4
        let fallback = combine(residualMm: residualMm, fallback: true)
        let restricted = combine(residualMm: residualMm, fallback: false)
        // Invert σ_plane back to the residual it was computed from: identical on
        // both paths once the known penalty factor is divided out.
        let recovered = -5 * log(fallback.sigmaGeom.sigmaPlane
                                 / Confidence.supportPlaneFallbackPenalty)
        XCTAssertEqual(recovered, residualMm, accuracy: 1e-4)
        XCTAssertEqual(-5 * log(restricted.sigmaGeom.sigmaPlane), residualMm, accuracy: 1e-4)
    }

    // The two penalties are independent factors on the same term; a card-only
    // best-of-5 fit that also fell back carries both.
    func testTheCardOnlyPenaltyAndTheFallbackPenaltyCompose() {
        let result = combine(residualMm: 2.0, fallback: true,
                             cardOnlyPath: true, cardOnlyIterations: 5)
        let expected = exp(Float(-2.0) / 5) * 0.9 * Confidence.supportPlaneFallbackPenalty
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, expected, accuracy: 1e-6)
    }

    // The restricted path is the unpenalised default, so no existing caller's
    // numbers move until a capture actually falls back.
    func testRestrictedFitIsUnpenalised() {
        let result = combine(residualMm: 2.0, fallback: false)
        XCTAssertEqual(result.sigmaGeom.sigmaPlane, exp(Float(-2.0) / 5), accuracy: 1e-6)
    }
}
