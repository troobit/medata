#if HARNESS_ENABLED
import Foundation
import Testing
@testable import HarnessCore

// Tests for the TOST capture-skew guard (cross-dataset-calibration Req 5.2,
// Decision 10, spec task 7). δ = 0.20, α = 0.05: equivalence holds when the
// 90% CI of (β_A − β_B), SE_Δ = √(SE_A² + SE_B²), lies within ±δ·β̄.
@Suite("CrossDatasetSkew TOST")
struct CrossDatasetSkewTests {

    // z_{0.95} for hand-computed boundaries below.
    static let z95 = 1.6448536269514722

    @Test("Close betas with tight SEs are equivalent")
    func closeBetasTightSEsEquivalent() {
        // diff 0, SE_Δ = 0.0283 → CI ±0.0465, margin ±0.20.
        #expect(CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0.02,
                                            betaB: 1.0, seB: 0.02))
        // Small real difference, still well inside the bound.
        #expect(CrossDatasetSkew.equivalent(betaA: 0.82, seA: 0.03,
                                            betaB: 0.86, seB: 0.03))
    }

    @Test("Clearly disagreeing betas are inequivalent")
    func disagreeingBetasInequivalent() {
        // diff 0.30, β̄ = 0.85 → margin 0.17 < diff even before the CI widens it.
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0.02,
                                             betaB: 0.7, seB: 0.02))
    }

    @Test("The boundary pair flips exactly where the CI edge crosses δ·β̄")
    func boundaryPairFlipsAtTheMargin() {
        // With betaB = 0.9, seA = seB = 0.05: SE_Δ = 0.05√2, β̄ = 0.9 + d/2,
        // and the upper CI edge d + z·SE_Δ meets the margin
        // 0.20·(0.9 + d/2) = 0.18 + 0.1·d at d* = (0.18 − z·SE_Δ) / 0.9.
        let seDelta = 0.05 * 2.0.squareRoot()
        let dStar = (0.18 - Self.z95 * seDelta) / 0.9

        #expect(CrossDatasetSkew.equivalent(betaA: 0.9 + dStar - 0.005, seA: 0.05,
                                            betaB: 0.9, seB: 0.05),
                "just inside the boundary must read equivalent")
        #expect(!CrossDatasetSkew.equivalent(betaA: 0.9 + dStar + 0.005, seA: 0.05,
                                             betaB: 0.9, seB: 0.05),
                "just outside the boundary must read inequivalent")
    }

    @Test("Identical betas with wide SEs are NOT equivalent — TOST is not a difference test")
    func widePairIsUnderpoweredNotEquivalent() {
        // diff 0 but SE_Δ = 0.1√2 → CI ±0.2326 exceeds the ±0.20 margin: the
        // comparison is under-powered and must not corroborate (Req 6.2).
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0.10,
                                             betaB: 1.0, seB: 0.10))
    }

    @Test("The SE bound is uncertainty-aware, not a fixed relative constant (Req 5.2)")
    func boundScalesWithStandardError() {
        // Same point estimates: equivalent at tight SEs, inequivalent at wide
        // ones. A fixed relative tolerance could not distinguish the two.
        #expect(CrossDatasetSkew.equivalent(betaA: 0.95, seA: 0.02,
                                            betaB: 1.0, seB: 0.02))
        #expect(!CrossDatasetSkew.equivalent(betaA: 0.95, seA: 0.12,
                                             betaB: 1.0, seB: 0.12))
    }

    @Test("Degenerate inputs fail closed")
    func degenerateInputsFailClosed() {
        #expect(!CrossDatasetSkew.equivalent(betaA: .nan, seA: 0.02, betaB: 1.0, seB: 0.02))
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: -0.01, betaB: 1.0, seB: 0.02))
        #expect(!CrossDatasetSkew.equivalent(betaA: 0, seA: 0.02, betaB: 1.0, seB: 0.02))
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0.02, betaB: 1.0, seB: 0.02,
                                             delta: 0))
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0.02, betaB: 1.0, seB: 0.02,
                                             alpha: 0.5))
    }

    @Test("Exact SE-free pairs reduce to a plain margin check")
    func zeroSEReducesToMarginCheck() {
        // SE_Δ = 0 → the CI is the point difference itself.
        #expect(CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0, betaB: 0.85, seB: 0))
        #expect(!CrossDatasetSkew.equivalent(betaA: 1.0, seA: 0, betaB: 0.7, seB: 0))
    }

    @Test("The normal quantile matches the known z values the design quotes")
    func normalQuantileMatchesKnownValues() {
        #expect(abs(CrossDatasetSkew.normalQuantile(0.95) - Self.z95) < 1e-8)
        #expect(abs(CrossDatasetSkew.normalQuantile(0.975) - 1.959963984540054) < 1e-8)
        #expect(abs(CrossDatasetSkew.normalQuantile(0.5)) < 1e-12)
        // Symmetry.
        #expect(abs(CrossDatasetSkew.normalQuantile(0.05) + Self.z95) < 1e-8)
    }
}
#endif
