#if HARNESS_ENABLED
import Foods
import Foundation

// β provenance — a dimension SEPARATE from BetaCalibrationStatus (Decision 16):
// the status enum stays three-valued so existing consumers' switches don't
// break, and provenance records where a calibrated β came from for audit and
// the Req 5.1 masking-guarantee distinction.
public enum BetaProvenance: String, Codable, Sendable {
    case n5kSingleDominant = "n5k_single_dominant"
    case n5kMixture        = "n5k_mixture"
    case gravimetric       = "gravimetric"    // hand-measured
    case none              = "none"           // pooled/unity, no fit
}

// Owns the per-class β/status/provenance decision (design §Extended
// CalibrationResult, Req 5.2/5.4). A class receives exactly one β:
//   1. single-dominant fit clearing the effective-sample AND SE gates —
//      carries the Req 5.1 masking guarantee;
//   2. else a mixture fit clearing the same gates (masking-transfer gap
//      recorded via provenance) — so a strong mixture fit is NOT discarded
//      when single-dominant is merely under-sampled;
//   3. else the pooled/unity fallback, provenance none.
public enum CalibrationMerge {
    // Provisional gate values (design §Provisional gate values).
    public static let effectiveSampleMin = BetaCalibrator.minCalibrationMeals
    public static let relativeSEBound: Float = MixtureBetaCalibrator.relativeSEBound

    public struct ClassCalibration: Sendable {
        public let className: String
        public let beta: Float
        public let status: BetaCalibrationStatus   // calibrated | pooled | unity
        public let provenance: BetaProvenance
        public let standardError: Float?           // absolute SE on β
        public let effectiveSample: Int
        public let clamped: Bool                   // Req 5.6 warning
    }

    public static func merge(
        singleDominant: BetaCalibrator.PerClassFit,
        mixture: MixtureBetaCalibrator.Result
    ) -> [String: ClassCalibration] {
        let allClasses = Set(singleDominant.classes.keys)
            .union(mixture.effectiveSamplePerClass.keys)
            .union(mixture.betaPerClass.keys)

        var merged: [String: ClassCalibration] = [:]
        for c in allClasses {
            let sd = singleDominant.classes[c]

            // Rule 1: qualifying single-dominant fit. The gate is the
            // tightened Req 5.4 pair — never the raw plate count — and the
            // log-residual SE is the relative SE on β.
            if let sd, sd.effectiveSample >= effectiveSampleMin,
               let relSE = sd.logResidualSE, relSE <= relativeSEBound {
                merged[c] = ClassCalibration(
                    className: c,
                    beta: sd.beta,
                    status: .calibrated,
                    provenance: .n5kSingleDominant,
                    standardError: relSE * sd.beta,
                    effectiveSample: sd.effectiveSample,
                    clamped: sd.clamped
                )
                continue
            }

            // Rule 2: qualifying mixture fit (identifiable already encodes
            // the SE bound and per-class conditioning).
            if let beta = mixture.betaPerClass[c],
               mixture.effectiveSamplePerClass[c, default: 0] >= effectiveSampleMin,
               mixture.identifiablePerClass[c] == true {
                merged[c] = ClassCalibration(
                    className: c,
                    beta: beta,
                    status: .calibrated,
                    provenance: .n5kMixture,
                    standardError: mixture.standardErrorPerClass[c],
                    effectiveSample: mixture.effectiveSamplePerClass[c, default: 0],
                    clamped: mixture.clampedClasses.contains(c)
                )
                continue
            }

            // Rule 3: pooled/unity fallback, provenance none. A class the
            // closed form marked calibrated on raw count alone but which
            // failed the tightened 5.4 gate is demoted to the pool β — its
            // unqualified fitted value must not be baked.
            let demoted = sd?.status == .calibrated
            merged[c] = ClassCalibration(
                className: c,
                beta: demoted ? singleDominant.betaPool : (sd?.beta ?? 1.0),
                status: demoted ? .uncalibratedPooled
                                : (sd?.status ?? .uncalibratedUnity),
                provenance: .none,
                standardError: nil,
                effectiveSample: sd?.effectiveSample
                    ?? mixture.effectiveSamplePerClass[c, default: 0],
                clamped: false
            )
        }
        return merged
    }
}
#endif
