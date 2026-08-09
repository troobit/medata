#if HARNESS_ENABLED
import Foundation

// Cross-dataset capture-skew guard (cross-dataset-calibration Req 5.2,
// Decision 10): two datasets' per-class β are pooled only when they are
// EQUIVALENT within a practical bound that accounts for each source's
// standard error — not a fixed relative constant, which would fire on
// ordinary sampling noise for small samples and miss real skew for large
// ones.
//
// The test is TOST (two one-sided tests) under a normal approximation:
// the (1 − 2α) confidence interval of (β_A − β_B), with
// SE_Δ = √(SE_A² + SE_B²), must lie entirely within ±δ·β̄ where
// β̄ = (β_A + β_B)/2. Note the TOST asymmetry is intended: wide standard
// errors mean equivalence CANNOT be claimed even when the point estimates
// agree exactly — an under-powered comparison is "not corroborated", never
// "corroborated by default".
public enum CrossDatasetSkew {
    // Practical equivalence bound as a fraction of the mean β (Decision 10).
    // Recorded in lineage (Req 9.1) by the CLI.
    public static let defaultDelta = 0.20
    // One-sided test size; the TOST interval is the (1 − 2α) CI.
    public static let defaultAlpha = 0.05

    // True when β_A and β_B are practically equivalent under TOST.
    // Fails closed: any non-finite input, a non-positive β or δ, a negative
    // SE, or an α outside (0, 0.5) returns false — an unmeasurable pair must
    // read as "not corroborated", not as "agrees".
    public static func equivalent(
        betaA: Double, seA: Double,
        betaB: Double, seB: Double,
        delta: Double = defaultDelta,
        alpha: Double = defaultAlpha
    ) -> Bool {
        guard betaA.isFinite, betaB.isFinite, seA.isFinite, seB.isFinite,
              delta.isFinite, alpha.isFinite,
              betaA > 0, betaB > 0, seA >= 0, seB >= 0,
              delta > 0, alpha > 0, alpha < 0.5 else { return false }

        let diff = betaA - betaB
        let seDelta = (seA * seA + seB * seB).squareRoot()
        let margin = delta * (betaA + betaB) / 2
        let z = normalQuantile(1 - alpha)
        let lower = diff - z * seDelta
        let upper = diff + z * seDelta
        return lower >= -margin && upper <= margin
    }

    // Inverse standard-normal CDF (Acklam's rational approximation, |ε| < 1.15e-9
    // over (0, 1)). Deterministic and dependency-free, consistent with the
    // offline-harness invariants; α is a lineage-recorded parameter, so the
    // quantile cannot be a hard-coded 1.645.
    static func normalQuantile(_ p: Double) -> Double {
        precondition(p > 0 && p < 1, "normalQuantile requires p in (0, 1)")
        let a = [-3.969683028665376e+01, 2.209460984245205e+02,
                 -2.759285104469687e+02, 1.383577518672690e+02,
                 -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02,
                 -1.556989798598866e+02, 6.680131188771972e+01,
                 -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01,
                 -2.400758277161838e+00, -2.549732539343734e+00,
                 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01,
                 2.445134137142996e+00, 3.754408661907416e+00]
        let pLow = 0.02425
        let pHigh = 1 - pLow

        if p < pLow {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > pHigh {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5
        let r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }
}
#endif
