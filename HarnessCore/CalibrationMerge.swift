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
        // cross-dataset-calibration Req 4.3/6.2: dataset → sample contribution
        // feeding this β, and the corroboration flag. A calibrated β is
        // flagged unless ≥ 2 datasets each yield an independently identifiable
        // standalone β AND those TOST-agree.
        public let contributingDatasets: [String: Int]
        public let singleSourceUncorroborated: Bool
        // Req 5.3: set when ≥ 2 independently identifiable per-dataset β
        // disagreed under the skew test and the class fell back to
        // pooled/unity rather than baking the blended value.
        public let crossDatasetInconsistent: Bool

        public init(className: String, beta: Float, status: BetaCalibrationStatus,
                    provenance: BetaProvenance, standardError: Float?,
                    effectiveSample: Int, clamped: Bool,
                    contributingDatasets: [String: Int] = [:],
                    singleSourceUncorroborated: Bool = false,
                    crossDatasetInconsistent: Bool = false) {
            self.className = className
            self.beta = beta
            self.status = status
            self.provenance = provenance
            self.standardError = standardError
            self.effectiveSample = effectiveSample
            self.clamped = clamped
            self.contributingDatasets = contributingDatasets
            self.singleSourceUncorroborated = singleSourceUncorroborated
            self.crossDatasetInconsistent = crossDatasetInconsistent
        }
    }

    // One dataset's standalone mixture solve (cross-dataset-calibration
    // Req 5.1): feeds the skew guard and corroboration; the baked β always
    // comes from the shared pooled solve.
    public struct DatasetFit: Sendable {
        public let dataset: String
        public let result: MixtureBetaCalibrator.Result

        public init(dataset: String, result: MixtureBetaCalibrator.Result) {
            self.dataset = dataset
            self.result = result
        }
    }

    // Pre-cross-dataset entry point, kept so existing callers and the Req 7.1
    // baseline behave identically: no per-dataset solves means no
    // corroboration and no skew guard — every calibrated class reads
    // single-source (fail closed on corroboration, open on skew).
    public static func merge(
        singleDominant: BetaCalibrator.PerClassFit,
        mixture: MixtureBetaCalibrator.Result
    ) -> [String: ClassCalibration] {
        merge(singleDominant: singleDominant, mixture: mixture, perDataset: [])
    }

    public static func merge(
        singleDominant: BetaCalibrator.PerClassFit,
        mixture: MixtureBetaCalibrator.Result,
        perDataset: [DatasetFit],
        skewDelta: Double = CrossDatasetSkew.defaultDelta,
        skewAlpha: Double = CrossDatasetSkew.defaultAlpha
    ) -> [String: ClassCalibration] {
        let allClasses = Set(singleDominant.classes.keys)
            .union(mixture.effectiveSamplePerClass.keys)
            .union(mixture.betaPerClass.keys)
            .union(perDataset.flatMap { $0.result.effectiveSamplePerClass.keys })

        var merged: [String: ClassCalibration] = [:]
        for c in allClasses {
            let sd = singleDominant.classes[c]

            // Cross-dataset assessment for this class (Req 5.1/5.2/6.2).
            // Contribution counts come from each dataset's own effective
            // samples; a dataset is INDEPENDENTLY identifiable only when its
            // standalone solve clears the same effective-sample + relative-SE
            // gates the pooled fit must clear. TOST equivalence over every
            // identifiable pair decides corroborated vs inconsistent.
            var contributing: [String: Int] = [:]
            var identifiableFits: [(beta: Float, se: Float)] = []
            for ds in perDataset {
                let n = ds.result.effectiveSamplePerClass[c, default: 0]
                if n > 0 { contributing[ds.dataset] = n }
                if n >= effectiveSampleMin,
                   ds.result.identifiablePerClass[c] == true,
                   let beta = ds.result.betaPerClass[c],
                   let se = ds.result.standardErrorPerClass[c] {
                    identifiableFits.append((beta, se))
                }
            }
            var allPairsEquivalent = true
            if identifiableFits.count >= 2 {
                for i in 0..<(identifiableFits.count - 1) {
                    for j in (i + 1)..<identifiableFits.count
                    where !CrossDatasetSkew.equivalent(
                        betaA: Double(identifiableFits[i].beta),
                        seA: Double(identifiableFits[i].se),
                        betaB: Double(identifiableFits[j].beta),
                        seB: Double(identifiableFits[j].se),
                        delta: skewDelta, alpha: skewAlpha) {
                        allPairsEquivalent = false
                    }
                }
            }
            let corroborated = identifiableFits.count >= 2 && allPairsEquivalent
            let inconsistent = identifiableFits.count >= 2 && !allPairsEquivalent

            // Rule 1: qualifying single-dominant fit. The gate is the
            // tightened Req 5.4 pair — never the raw plate count — and the
            // log-residual SE is the relative SE on β. Single-dominant is an
            // N5k-only path, so its corroboration follows the mixture
            // per-dataset assessment: absent that, it is single-source.
            if let sd, sd.effectiveSample >= effectiveSampleMin,
               let relSE = sd.logResidualSE, relSE <= relativeSEBound {
                merged[c] = ClassCalibration(
                    className: c,
                    beta: sd.beta,
                    status: .calibrated,
                    provenance: .n5kSingleDominant,
                    standardError: relSE * sd.beta,
                    effectiveSample: sd.effectiveSample,
                    clamped: sd.clamped,
                    contributingDatasets: contributing.isEmpty
                        ? ["nutrition5k": sd.effectiveSample] : contributing,
                    singleSourceUncorroborated: !corroborated
                )
                continue
            }

            // Rule 2: qualifying mixture fit (identifiable already encodes
            // the SE bound and per-class conditioning). A class flagged
            // cross-dataset-inconsistent falls through to Rule 3 — the
            // blended pooled value must NOT bake (Req 5.3).
            if !inconsistent,
               let beta = mixture.betaPerClass[c],
               mixture.effectiveSamplePerClass[c, default: 0] >= effectiveSampleMin,
               mixture.identifiablePerClass[c] == true {
                merged[c] = ClassCalibration(
                    className: c,
                    beta: beta,
                    status: .calibrated,
                    provenance: .n5kMixture,
                    standardError: mixture.standardErrorPerClass[c],
                    effectiveSample: mixture.effectiveSamplePerClass[c, default: 0],
                    clamped: mixture.clampedClasses.contains(c),
                    contributingDatasets: contributing,
                    singleSourceUncorroborated: !corroborated
                )
                continue
            }

            // Rule 3: pooled/unity fallback, provenance none. A class the
            // closed form marked calibrated on raw count alone but which
            // failed the tightened 5.4 gate is demoted to the pool β — its
            // unqualified fitted value must not be baked. A skew-inconsistent
            // class whose pooled fit would otherwise have qualified is demoted
            // the same way (Req 5.3), with the inconsistency recorded.
            let skewDemoted = inconsistent
                && mixture.betaPerClass[c] != nil
                && mixture.effectiveSamplePerClass[c, default: 0] >= effectiveSampleMin
                && mixture.identifiablePerClass[c] == true
            let demoted = sd?.status == .calibrated || skewDemoted
            merged[c] = ClassCalibration(
                className: c,
                beta: demoted ? singleDominant.betaPool : (sd?.beta ?? 1.0),
                status: demoted ? .uncalibratedPooled
                                : (sd?.status ?? .uncalibratedUnity),
                provenance: .none,
                standardError: nil,
                effectiveSample: sd?.effectiveSample
                    ?? mixture.effectiveSamplePerClass[c, default: 0],
                clamped: false,
                contributingDatasets: contributing,
                singleSourceUncorroborated: false,
                crossDatasetInconsistent: inconsistent
            )
        }
        return merged
    }
}
#endif
