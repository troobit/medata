#if HARNESS_ENABLED
import Foods
import Foundation
import PortableContracts
import Testing
@testable import HarnessCore

// Tests for the HarnessCLI calibrate wiring and the calibrate JSON artifact
// (spec task 21, Reqs 4.2/4.4/5.2/5.5, design §DB bake handoff contract).
@Suite("CalibrateRun wiring")
struct CalibrateRunTests {

    func makeFixture(id: String, path: String) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        fx.estimatorPath = path
        fx.segmenterCheckpointSha256 = path == "mixture" ? FixtureLoader.sentinelSHA : "aa"
        fx.groundTruthClassMassG = ["white_rice": 120]
        return fx
    }

    // MARK: - Depth-test-split exclusion (Req 4.4)

    @Test("The depth test split file parses one dish id per line, tolerating blanks")
    func splitFileParses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth_test_ids_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try "dish_001\n\ndish_002  \n dish_003\n".write(to: url, atomically: true, encoding: .utf8)

        let split = try CalibrateRun.loadDepthTestSplit(from: url)
        #expect(split == ["dish_001", "dish_002", "dish_003"])
    }

    @Test("Depth-test-split dishes are excluded before any selection, on both paths")
    func splitExcludedBeforeSelection() {
        let fixtures = [
            makeFixture(id: "dish_001", path: "mixture"),          // in split
            makeFixture(id: "dish_002", path: "single_dominant"),  // in split
            makeFixture(id: "dish_003", path: "mixture"),
            makeFixture(id: "dish_004", path: "single_dominant"),
        ]
        let routed = CalibrateRun.route(fixtures: fixtures,
                                        depthTestSplit: ["dish_001", "dish_002"])
        #expect(routed.mixture.map(\.fixtureID) == ["dish_003"])
        #expect(routed.singleDominant.map(\.fixtureID) == ["dish_004"])
        #expect(Set(routed.depthTestExcluded.map(\.fixtureID)) == ["dish_001", "dish_002"])
    }

    // MARK: - τ_purity volume gate (Req 4.2 / 5.2)

    @Test("Purity is the mass-dominant class's share of the above-plane food volume")
    func purityIsVolumeFraction() {
        let purity = CalibrateRun.volumePurity(
            perClassVolumesCm3: ["white_rice": 95, "peas": 5],
            massDominantClass: "white_rice")
        #expect(abs(purity - 0.95) <= 1e-5)
    }

    @Test("A segmentation that disagrees with the mass-dominant class yields a low fraction")
    func disagreeingSegmentationLowPurity() {
        // The segmenter put 90% of the volume in peas but the scales say rice
        // dominates: the plate is dropped, no separate disagreement rule.
        let purity = CalibrateRun.volumePurity(
            perClassVolumesCm3: ["peas": 90, "white_rice": 10],
            massDominantClass: "white_rice")
        #expect(purity < CalibrateRun.tauPurity)
    }

    @Test("Purity failures are dropped and recorded, never re-routed (Req 5.2)")
    func purityFailuresDroppedNotRerouted() {
        let pass = MealCalibrationInput(
            fixtureID: "dish_pure", capturePath: .singleViewLidar,
            dominantClass: "white_rice",
            predictedCarbsPerClass: ["white_rice": 40],
            actualCarbsPerClass: ["white_rice": 35],
            groundTruthTotalCarbsG: 35,
            perClassVolumesCm3: ["white_rice": 95, "peas": 5])
        let fail = MealCalibrationInput(
            fixtureID: "dish_impure", capturePath: .singleViewLidar,
            dominantClass: "white_rice",
            predictedCarbsPerClass: ["white_rice": 40],
            actualCarbsPerClass: ["white_rice": 35],
            groundTruthTotalCarbsG: 35,
            perClassVolumesCm3: ["white_rice": 60, "peas": 40])
        let gated = CalibrateRun.applyPurityGate(
            [pass, fail],
            massDominantByFixture: ["dish_pure": "white_rice", "dish_impure": "white_rice"])

        #expect(gated.admitted.map(\.fixtureID) == ["dish_pure"])
        #expect(gated.dropped == ["dish_impure"],
                "a failed plate contributes to neither estimator — recorded, not re-routed")
    }

    @Test("Purity with no volumes or no dominant class admits nothing")
    func purityDegenerateCases() {
        #expect(CalibrateRun.volumePurity(perClassVolumesCm3: [:],
                                          massDominantClass: "white_rice") == 0)
        #expect(CalibrateRun.volumePurity(perClassVolumesCm3: ["white_rice": 10],
                                          massDominantClass: nil) == 0)
    }

    // MARK: - Ingestion run-summary consumption (Req 4.1, design §Unmapped-volume bias)

    // Fixtures carry mapped masses only, so the >10%-unmapped-mass exclusion
    // can only come from the ingestion run summary — the harness must consume
    // it, not re-derive it.
    @Test("The ingestion run summary parses the unmapped exclusion list and skip count")
    func ingestSummaryParses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_summary_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"ingested": 5,
         "skipped": {"malformed_depth": ["dish_009"],
                     "depth_out_of_band": ["dish_010", "dish_011"],
                     "missing_rgb": []},
         "mixture_fit_excluded_unmapped": ["dish_003"],
         "liquid_excluded": ["dish_004"]}
        """.write(to: url, atomically: true, encoding: .utf8)

        let summary = try CalibrateRun.loadIngestSummary(from: url)
        #expect(summary.unmappedExcluded == ["dish_003"])
        #expect(summary.liquidExcluded == ["dish_004"])
        #expect(summary.ingestionSkipCount == 3)
    }

    @Test("Unmapped-heavy plates leave the mixture fit; depth-test exclusion still wins")
    func unmappedExcludedFromMixtureFit() {
        let fixtures = [
            makeFixture(id: "dish_001", path: "mixture"),          // unmapped-excluded
            makeFixture(id: "dish_002", path: "mixture"),
            makeFixture(id: "dish_003", path: "mixture"),          // in split AND unmapped
            makeFixture(id: "dish_004", path: "single_dominant"),
        ]
        let routed = CalibrateRun.route(fixtures: fixtures,
                                        depthTestSplit: ["dish_003"],
                                        unmappedExcluded: ["dish_001", "dish_003"])
        #expect(routed.mixture.map(\.fixtureID) == ["dish_002"])
        #expect(routed.unmappedExcluded.map(\.fixtureID) == ["dish_001"])
        #expect(routed.depthTestExcluded.map(\.fixtureID) == ["dish_003"])
        #expect(routed.singleDominant.map(\.fixtureID) == ["dish_004"])
    }

    // MARK: - JSON artifact (Req 5.5, design §DB bake handoff contract)

    func makeArtifact() -> CalibrationArtifact {
        let merged: [String: CalibrationMerge.ClassCalibration] = [
            "white_rice": .init(className: "white_rice", beta: 0.82,
                                status: .calibrated, provenance: .n5kSingleDominant,
                                standardError: 0.04, effectiveSample: 45, clamped: false),
            "chips_fries": .init(className: "chips_fries", beta: 1.5,
                                 status: .calibrated, provenance: .n5kMixture,
                                 standardError: 0.02, effectiveSample: 60, clamped: true),
            "peas": .init(className: "peas", beta: 1.0,
                          status: .uncalibratedUnity, provenance: .none,
                          standardError: nil, effectiveSample: 3, clamped: false),
        ]
        let lineage = CalibrationArtifact.Lineage(
            n5kRelease: "3fa8c1d2e4b5",
            n5kMetadataVersion: "9c7b6a5d4e3f",
            mappingArtifactVersion: "1",
            tauRoute: 0.90, tauPurity: 0.90,
            tauEff: MixtureBetaCalibrator.tauEff,
            kappaStacking: MixtureBetaCalibrator.stackingKappa,
            seed: 42,
            effectiveSamplePerClass: ["white_rice": 45, "chips_fries": 60, "peas": 3],
            conditionNumber: 3.2,
            identifiablePerClass: ["white_rice": true, "chips_fries": true, "peas": false],
            pinnedIntrinsicsModel: "realsense_d435_factory_640x480",
            licence: "CC BY 4.0"
        )
        return CalibrationArtifact(merged: merged, betaPool: 1.0, lineage: lineage)
    }

    @Test("Per-class entries carry beta, status, provenance, standard_error, effective_sample, clamped")
    func artifactClassEntries() throws {
        let data = try CalibrationArtifact.encoder().encode(makeArtifact())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let classes = try #require(json["classes"] as? [String: [String: Any]])

        let rice = try #require(classes["white_rice"])
        #expect(rice["beta"] as? Double == 0.82)
        #expect(rice["status"] as? String == "calibrated")
        #expect(rice["provenance"] as? String == "n5k_single_dominant")
        #expect(rice["standard_error"] as? Double != nil)
        #expect(rice["effective_sample"] as? Int == 45)
        #expect(rice["clamped"] as? Bool == false)

        let chips = try #require(classes["chips_fries"])
        #expect(chips["clamped"] as? Bool == true, "Req 5.6 warning input must survive the handoff")
        #expect(chips["provenance"] as? String == "n5k_mixture")

        let peas = try #require(classes["peas"])
        #expect(peas["status"] as? String == "uncalibrated_unity")
        #expect(peas["provenance"] as? String == "none")
        #expect(peas["standard_error"] is NSNull || peas["standard_error"] == nil)
    }

    @Test("The lineage block records release, versions, thresholds, seed, diagnostics, intrinsics, licence")
    func artifactLineageBlock() throws {
        let data = try CalibrationArtifact.encoder().encode(makeArtifact())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let lineage = try #require(json["lineage"] as? [String: Any])

        #expect(lineage["n5k_release"] as? String == "3fa8c1d2e4b5")
        #expect(lineage["n5k_metadata_version"] as? String == "9c7b6a5d4e3f")
        #expect(lineage["mapping_artifact_version"] as? String == "1")
        #expect(lineage["tau_route"] as? Double == 0.9)
        #expect(lineage["tau_purity"] as? Double == 0.9)
        #expect(lineage["tau_eff"] as? Double != nil)
        #expect(lineage["kappa_stacking"] as? Double != nil)
        #expect(lineage["seed"] as? Int == 42)
        #expect((lineage["effective_sample_per_class"] as? [String: Int])?["white_rice"] == 45)
        #expect(lineage["condition_number"] as? Double != nil)
        #expect((lineage["identifiable_per_class"] as? [String: Bool])?["peas"] == false)
        #expect(lineage["pinned_intrinsics_model"] as? String == "realsense_d435_factory_640x480")
        #expect(lineage["licence"] as? String == "CC BY 4.0")
    }

    @Test("The artifact extends the existing CalibrationJSON shape — betaPool stays at the top level")
    func artifactKeepsBetaPool() throws {
        let data = try CalibrationArtifact.encoder().encode(makeArtifact())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["betaPool"] as? Double == 1.0)
    }
}
#endif
