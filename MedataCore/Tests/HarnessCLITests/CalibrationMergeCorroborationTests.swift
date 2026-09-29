#if HARNESS_ENABLED
import Foods
import Foundation
import Testing
@testable import HarnessCore

// Tests for CalibrationMerge corroboration + skew wiring
// (cross-dataset-calibration Reqs 5.1/5.3/6.2/8.1/8.3, spec task 15).
@Suite("CalibrationMerge corroboration and skew")
struct CalibrationMergeCorroborationTests {

    func sdFit(_ classes: [String: BetaCalibrator.PerClassFit.ClassFit] = [:])
        -> BetaCalibrator.PerClassFit {
        BetaCalibrator.PerClassFit(classes: classes, betaPool: 0.93)
    }

    func mixResult(beta: [String: Float] = [:], se: [String: Float] = [:],
                   n: [String: Int] = [:], identifiable: [String: Bool] = [:],
                   clamped: Set<String> = []) -> MixtureBetaCalibrator.Result {
        .init(betaPerClass: beta, standardErrorPerClass: se,
              effectiveSamplePerClass: n, identifiablePerClass: identifiable,
              conditionNumber: 1, excludedPlates: [], liquidExcludedPlates: [],
              fixedOffsetClasses: [], clampedClasses: clamped)
    }

    // MARK: - Corroboration (Req 6.2)

    @Test("Two independently identifiable, TOST-agreeing datasets corroborate the class")
    func twoAgreeingDatasetsCorroborate() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["white_rice": 0.80], se: ["white_rice": 0.02],
                               n: ["white_rice": 60], identifiable: ["white_rice": true]),
            perDataset: [
                .init(dataset: "nutrition5k",
                      result: mixResult(beta: ["white_rice": 0.82], se: ["white_rice": 0.04],
                                        n: ["white_rice": 30],
                                        identifiable: ["white_rice": true])),
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["white_rice": 0.79], se: ["white_rice": 0.04],
                                        n: ["white_rice": 30],
                                        identifiable: ["white_rice": true])),
            ])
        let c = try #require(merged["white_rice"])
        #expect(c.status == .calibrated)
        #expect(c.beta == 0.80, "the baked value is the pooled fit")
        #expect(!c.singleSourceUncorroborated)
        #expect(!c.crossDatasetInconsistent)
        #expect(c.contributingDatasets == ["nutrition5k": 30, "metafood3d": 30])
    }

    @Test("Present in two datasets but identifiable in only one is still flagged (Req 6.2)")
    func identifiableInOnlyOneIsFlagged() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["pasta": 0.85], se: ["pasta": 0.03],
                               n: ["pasta": 45], identifiable: ["pasta": true]),
            perDataset: [
                .init(dataset: "nutrition5k",
                      // Present (10 plates) but under the effective-sample bar
                      // on its own solve — NOT independently identifiable.
                      result: mixResult(beta: ["pasta": 0.9], se: ["pasta": 0.4],
                                        n: ["pasta": 10],
                                        identifiable: ["pasta": false])),
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["pasta": 0.84], se: ["pasta": 0.03],
                                        n: ["pasta": 35],
                                        identifiable: ["pasta": true])),
            ])
        let c = try #require(merged["pasta"])
        #expect(c.status == .calibrated, "the pooled fit still bakes (Req 8.3)")
        #expect(c.singleSourceUncorroborated,
                "one identifiable source is not corroboration")
        #expect(c.contributingDatasets == ["nutrition5k": 10, "metafood3d": 35])
    }

    // MARK: - Skew guard (Req 5.3)

    @Test("Skew-inconsistent per-dataset betas demote the class to the pool, never the blend")
    func skewInconsistentGoesToPool() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            // The pooled blend would qualify on its own numbers…
            mixture: mixResult(beta: ["broccoli": 0.75], se: ["broccoli": 0.02],
                               n: ["broccoli": 80], identifiable: ["broccoli": true]),
            // …but the sources genuinely disagree (0.5 vs 1.0 at tight SEs).
            perDataset: [
                .init(dataset: "nutrition5k",
                      result: mixResult(beta: ["broccoli": 0.5], se: ["broccoli": 0.03],
                                        n: ["broccoli": 40],
                                        identifiable: ["broccoli": true])),
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["broccoli": 1.0], se: ["broccoli": 0.03],
                                        n: ["broccoli": 40],
                                        identifiable: ["broccoli": true])),
            ])
        let c = try #require(merged["broccoli"])
        #expect(c.status == .uncalibratedPooled)
        #expect(c.beta == 0.93, "falls back to the pool β, not the blended 0.75")
        #expect(c.provenance == BetaProvenance.none)
        #expect(c.crossDatasetInconsistent)
        #expect(!c.singleSourceUncorroborated)
    }

    @Test("A qualifying single-dominant fit still records the skew inconsistency (Req 5.3)")
    func singleDominantCarriesSkewInconsistency() throws {
        // The SD fit bakes — it is an N5k-only fit, not the blended pooled
        // value Req 5.3 blocks — but the per-dataset disagreement must be
        // recorded, not silently dropped on this path.
        let sd = sdFit(["broccoli": .init(
            beta: 0.6, status: .calibrated, logResidualSE: 0.05,
            effectiveSample: 40, clamped: false)])
        let merged = CalibrationMerge.merge(
            singleDominant: sd,
            mixture: mixResult(beta: ["broccoli": 0.75], se: ["broccoli": 0.02],
                               n: ["broccoli": 80], identifiable: ["broccoli": true]),
            perDataset: [
                .init(dataset: "nutrition5k",
                      result: mixResult(beta: ["broccoli": 0.5], se: ["broccoli": 0.03],
                                        n: ["broccoli": 40],
                                        identifiable: ["broccoli": true])),
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["broccoli": 1.0], se: ["broccoli": 0.03],
                                        n: ["broccoli": 40],
                                        identifiable: ["broccoli": true])),
            ])
        let c = try #require(merged["broccoli"])
        #expect(c.status == .calibrated)
        #expect(c.provenance == .n5kSingleDominant)
        #expect(c.beta == 0.6, "the SD fit bakes, never the blended 0.75")
        #expect(c.crossDatasetInconsistent,
                "the Req 5.3 record must survive the single-dominant path")
    }

    @Test("A single-dominant β records its actual N5k fit source, never MetaFood3D presence (Req 6.1)")
    func singleDominantAttributesActualFitSource() throws {
        // The class has ZERO N5k mixture effective samples but MetaFood3D
        // presence; the β is fit from N5k single-dominant plates, so the
        // contributor record must say nutrition5k — recording metafood3d
        // here misattributes a β MetaFood3D never touched.
        let sd = sdFit(["white_rice": .init(
            beta: 0.8, status: .calibrated, logResidualSE: 0.04,
            effectiveSample: 35, clamped: false)])
        let merged = CalibrationMerge.merge(
            singleDominant: sd,
            mixture: mixResult(beta: ["white_rice": 0.82], se: ["white_rice": 0.3],
                               n: ["white_rice": 12],
                               identifiable: ["white_rice": false]),
            perDataset: [
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["white_rice": 0.82],
                                        se: ["white_rice": 0.3],
                                        n: ["white_rice": 12],
                                        identifiable: ["white_rice": false])),
            ])
        let c = try #require(merged["white_rice"])
        #expect(c.provenance == .n5kSingleDominant)
        #expect(c.beta == 0.8)
        #expect(c.contributingDatasets == ["nutrition5k": 35],
                "the recorded contributors are the plates that fed THIS fit")
        #expect(c.singleSourceUncorroborated)
    }

    @Test("Sampling noise between agreeing datasets does NOT fire the skew guard (Req 5.2)")
    func samplingNoiseDoesNotFireTheGuard() throws {
        // 0.78 vs 0.82 at SE 0.03: a fixed 2.5% relative constant would fire;
        // the uncertainty-aware TOST must not.
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["chips_fries": 0.8], se: ["chips_fries": 0.02],
                               n: ["chips_fries": 70], identifiable: ["chips_fries": true]),
            perDataset: [
                .init(dataset: "nutrition5k",
                      result: mixResult(beta: ["chips_fries": 0.78], se: ["chips_fries": 0.03],
                                        n: ["chips_fries": 35],
                                        identifiable: ["chips_fries": true])),
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["chips_fries": 0.82], se: ["chips_fries": 0.03],
                                        n: ["chips_fries": 35],
                                        identifiable: ["chips_fries": true])),
            ])
        #expect(merged["chips_fries"]?.status == .calibrated)
        #expect(merged["chips_fries"]?.crossDatasetInconsistent == false)
    }

    // MARK: - Single-source bake (Req 8.3, Decision 9)

    @Test("A MetaFood3D-only class bakes on the statistical gates, flagged single-source")
    func singleSourceBakesOnGates() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["potato_boiled": 0.7], se: ["potato_boiled": 0.04],
                               n: ["potato_boiled": 33],
                               identifiable: ["potato_boiled": true]),
            perDataset: [
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["potato_boiled": 0.7],
                                        se: ["potato_boiled": 0.04],
                                        n: ["potato_boiled": 33],
                                        identifiable: ["potato_boiled": true])),
            ])
        let c = try #require(merged["potato_boiled"])
        #expect(c.status == .calibrated,
                "effective-sample + rel-SE gates decide the bake — no accuracy gate")
        #expect(c.beta == 0.7)
        #expect(c.singleSourceUncorroborated)
        #expect(c.contributingDatasets == ["metafood3d": 33])
    }

    @Test("A class below the gates keeps its pooled/unity state after pooling (Req 8.1)")
    func belowGatesKeepsFallback() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["peas": 0.9], se: ["peas": 0.5],
                               n: ["peas": 12], identifiable: ["peas": false]),
            perDataset: [
                .init(dataset: "metafood3d",
                      result: mixResult(beta: ["peas": 0.9], se: ["peas": 0.5],
                                        n: ["peas": 12],
                                        identifiable: ["peas": false])),
            ])
        let c = try #require(merged["peas"])
        #expect(c.status == .uncalibratedUnity)
        #expect(c.beta == 1.0)
        #expect(c.provenance == BetaProvenance.none)
    }

    // MARK: - Backwards compatibility

    @Test("The pre-cross-dataset entry point behaves as before, with honest defaults")
    func legacyEntryPointUnchanged() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(),
            mixture: mixResult(beta: ["white_rice": 0.8], se: ["white_rice": 0.02],
                               n: ["white_rice": 60], identifiable: ["white_rice": true]))
        let c = try #require(merged["white_rice"])
        #expect(c.status == .calibrated)
        #expect(c.beta == 0.8)
        #expect(c.singleSourceUncorroborated,
                "no per-dataset solves means no corroboration — fail closed")
        #expect(!c.crossDatasetInconsistent,
                "…but the skew guard needs two identifiable fits to fire")
    }
}
#endif
