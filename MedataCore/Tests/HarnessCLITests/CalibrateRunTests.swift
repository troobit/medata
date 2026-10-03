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

    // MARK: - Ingest-summary contract (cross-dataset Decision 17, Req 9.1)

    @Test("A metafood3d summary missing lineage keys fails loudly, never defaults to empty")
    func mf3dSummaryMissingKeysThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_summary_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // The pre-fix emitter's shape: snapshot_identifier instead of
        // snapshot, no mapping_version, width/height instead of
        // image_width/image_height, no seating_rule. This used to decode to
        // empty strings and bake unreproducible per-dataset lineage.
        try """
        {"dataset": "metafood3d",
         "licence": "CC BY-NC 4.0",
         "snapshot_identifier": "abc123def456",
         "skipped": {},
         "render_config": {"plane_depth_mm": 385.0,
                           "width": 640, "height": 480}}
        """.write(to: url, atomically: true, encoding: .utf8)

        #expect {
            try CalibrateRun.loadIngestSummary(from: url)
        } throws: { error in
            guard let e = error as? CalibrateRun.IngestSummaryContractError
            else { return false }
            return e.missingKeys.contains("snapshot")
                && e.missingKeys.contains("mapping_version")
                && e.missingKeys.contains("render_config.image_width")
                && e.missingKeys.contains("render_config.seating_rule")
        }
    }

    @Test("A complete metafood3d summary parses every lineage key, licence included")
    func mf3dSummaryParsesCompletely() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_summary_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"dataset": "metafood3d",
         "licence": "CC BY-NC 4.0",
         "snapshot": "abc123def456",
         "mapping_version": "c0ffee123456",
         "skipped": {"no_stable_pose": ["obj_9"]},
         "render_config": {"plane_depth_mm": 385.0,
                           "intrinsics_model": "realsense_d435_rgb_nominal",
                           "image_width": 640, "image_height": 480,
                           "seating_rule": "stable_pose_base_on_plane"}}
        """.write(to: url, atomically: true, encoding: .utf8)

        let summary = try CalibrateRun.loadIngestSummary(from: url)
        #expect(summary.dataset == "metafood3d")
        #expect(summary.snapshot == "abc123def456")
        #expect(summary.mappingVersion == "c0ffee123456")
        #expect(summary.licence == "CC BY-NC 4.0")
        #expect(summary.renderPlaneDepthMm == 385.0)
        #expect(summary.renderImageWidth == 640)
        #expect(summary.renderImageHeight == 480)
        #expect(summary.renderSeatingRule == "stable_pose_base_on_plane")
        #expect(summary.ingestionSkipCount == 1)
    }

    // tools/field_loop/derive_dataset.py's shape: no authored plane, so no
    // plane_depth_mm. It once wrote `skipped` as a list and failed to decode.
    @Test("A field summary from derive_dataset.py parses without an authored plane")
    func fieldSummaryParses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_summary_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"dataset": "medata_field",
         "licence": "developer's own captures; not redistributable",
         "snapshot": "field",
         "mapping_version": "palette-native",
         "skipped": {"not_weighed": [], "bundle_missing": ["1790655022746-success"]},
         "render_config": {"intrinsics_model": "arkit_per_capture",
                           "image_width": 1920, "image_height": 1440,
                           "seating_rule": "none"}}
        """.write(to: url, atomically: true, encoding: .utf8)

        let summary = try CalibrateRun.loadIngestSummary(from: url)
        #expect(summary.dataset == "medata_field")
        #expect(summary.renderPlaneDepthMm == nil)
        #expect(summary.ingestionSkipCount == 1)
    }

    // MARK: - Field review (field-score): relabels reach the volume before the gate

    @Test("A field summary's per-fixture review decodes; a summary without one is empty")
    func fieldReviewParses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("run_summary_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        {"dataset": "medata_field", "licence": "own", "snapshot": "field",
         "mapping_version": "palette-native",
         "render_config": {"intrinsics_model": "arkit_per_capture",
                           "image_width": 4, "image_height": 4, "seating_rule": "none"},
         "fixtures": {
           "a-success": {"truth": {"class_mass_g": {"bread_wholemeal": 80},
                                   "total_carbs_g": 30.4},
                         "review": {"relabelled": {"bread_white": "bread_wholemeal"},
                                    "rejected": ["white_rice"]}},
           "b-success": {"truth": {"class_mass_g": {}, "total_carbs_g": 1}}}}
        """.write(to: url, atomically: true, encoding: .utf8)

        let summary = try CalibrateRun.loadIngestSummary(from: url)
        #expect(summary.review == ["a-success": FieldReview(
            relabelled: ["bread_white": "bread_wholemeal"], rejected: ["white_rice"])])

        try #"{"ingested": 1, "skipped": {}}"#.write(to: url, atomically: true, encoding: .utf8)
        #expect(try CalibrateRun.loadIngestSummary(from: url).review.isEmpty)
    }

    @Test("Review volumes drop removed regions, merge renamed ones, and never chain")
    func fieldReviewVolumes() {
        let review = FieldReview(
            relabelled: ["unknown_food": "bread_wholemeal", "bread_wholemeal": "toast"],
            rejected: ["coffee"])
        let volumes = review.volumes(
            ["unknown_food": 125, "bread_wholemeal": 300, "coffee": 60, "peas": 5])
        // bread_wholemeal's own region moved to toast; unknown_food's took its
        // place rather than following it on to toast.
        #expect(volumes == ["bread_wholemeal": 125, "toast": 300, "peas": 5])
        #expect(FieldReview().volumes(["peas": 5]) == ["peas": 5])
    }

    @Test("A relabelled plate passes the purity gate it failed under the segmenter's class")
    func fieldReviewBeforePurityGate() throws {
        let db = try GRDBFoodDatabase.bundled()
        let labelled = MealCalibrationInput(
            fixtureID: "roll", capturePath: .singleViewLidar, dominantClass: "bread_white",
            predictedCarbsPerClass: ["bread_white": 43, "white_rice": 4],
            actualCarbsPerClass: ["bread_wholemeal": 30.4],
            groundTruthTotalCarbsG: 30.4,
            perClassVolumesCm3: ["bread_white": 236.8, "white_rice": 16.3],
            supportPlaneReference: .foodSupport)
        let dominant = ["roll": "bread_wholemeal"]
        #expect(CalibrateRun.applyPurityGate([labelled], massDominantByFixture: dominant)
            .dropped == ["roll"])

        let review = FieldReview(relabelled: ["bread_white": "bread_wholemeal"],
                                 rejected: ["white_rice"])
        let edition = "CoFID 2024 + AFCD 2024"  // informational in v1 (§6.12)
        let reviewed = review.apply(to: labelled, database: db, edition: edition)
        #expect(reviewed.perClassVolumesCm3 == ["bread_wholemeal": 236.8])
        #expect(reviewed.dominantClass == "bread_wholemeal")
        #expect(reviewed.actualCarbsPerClass == labelled.actualCarbsPerClass)
        #expect(reviewed.supportPlaneReference == .foodSupport)
        // Re-priced at the reviewed class, β = 1: V · ρ · κ / 100.
        let entry = try #require(db.entry(for: "bread_wholemeal", edition: edition))
        let expected = 236.8 * entry.densityGPerCm3 * entry.carbsMonoG / 100
        #expect(abs((reviewed.predictedCarbsPerClass["bread_wholemeal"] ?? 0) - expected) < 1e-3)
        #expect(CalibrateRun.applyPurityGate([reviewed], massDominantByFixture: dominant)
            .admitted.map(\.fixtureID) == ["roll"])
    }

    @Test("The strictest contributing licence wins the top-level lineage field (Decision 17)")
    func strictestLicenceWins() {
        #expect(CalibrationArtifact.strictestLicence(
            ["CC BY 4.0", "CC BY-NC 4.0"]) == "CC BY-NC 4.0")
        #expect(CalibrationArtifact.strictestLicence(["CC BY 4.0"]) == "CC BY 4.0")
        #expect(CalibrationArtifact.strictestLicence([]) == nil)
        #expect(CalibrationArtifact.strictestLicence(["", "CC BY 4.0"]) == "CC BY 4.0")
        // An unrecognised licence ranks strictest of all — fail-strict.
        #expect(CalibrationArtifact.strictestLicence(
            ["CC BY-NC 4.0", "Proprietary-X"]) == "Proprietary-X")
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
        return CalibrationArtifact(
            merged: merged, betaPool: 1.0,
            supportPlaneReference: CalibrateRun.fittedSupportPlaneReference,
            lineage: lineage)
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
        // The remaining provisional gate values (Req 5.5): a bake must be
        // reproducible from its lineage alone.
        #expect(lineage["liquid_significant_fraction"] as? Double != nil)
        #expect(lineage["unmapped_significant_fraction"] as? Double != nil)
        #expect(lineage["relative_se_bound"] as? Double != nil)
        #expect(lineage["effective_sample_min"] as? Int
                == CalibrationMerge.effectiveSampleMin)
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

    // MARK: - Eval-plate GT basis (Req 6.2/6.6/6.7)

    @Test("Eval GT macros come from the fixture's N5k per-class maps, not the DB composition")
    func evalPlateUsesFixtureGT() {
        var fx = makeFixture(id: "dish_gt", path: "mixture")
        // N5k GT deliberately differs from what mass × DB fraction would give
        // (120 g × 28/100 = 33.6) — a composition-source error the Req 6.7
        // cross-macro check must be able to see.
        fx.groundTruthClassCarbsG = ["white_rice": 20]
        fx.groundTruthClassProteinG = ["white_rice": 9]
        fx.groundTruthClassFatG = ["white_rice": 2]
        fx.groundTruthTotalCarbsG = 25
        let obs = MixtureBetaCalibrator.PlateObservation(
            fixtureID: "dish_gt", totalHullVolumeCm3: 150,
            massByClassG: ["white_rice": 120])
        let composition = ClassComposition(
            densityByClass: ["white_rice": 0.9],
            carbFractionPer100g: ["white_rice": 28],
            proteinFractionPer100g: ["white_rice": 2.7],
            fatFractionPer100g: ["white_rice": 0.3])

        let plate = CalibrateRun.evalPlate(obs: obs, fixture: fx,
                                           composition: composition, official: true)
        #expect(plate.gtCarbsByClassG["white_rice"] == 20)
        #expect(plate.gtProteinByClassG["white_rice"] == 9)
        #expect(plate.gtFatByClassG["white_rice"] == 2)
        #expect(plate.wholeDishCarbsG == 25)
        #expect(plate.inOfficialTestSplit)
        #expect(plate.estimatorPath == .mixture)
    }

    @Test("Fixtures predating the per-class GT maps fall back to GT mass × DB fraction")
    func evalPlateDBFallback() {
        let fx = makeFixture(id: "dish_old", path: "mixture")  // no GT maps
        let obs = MixtureBetaCalibrator.PlateObservation(
            fixtureID: "dish_old", totalHullVolumeCm3: 150,
            massByClassG: ["white_rice": 120])
        let composition = ClassComposition(
            densityByClass: ["white_rice": 0.9],
            carbFractionPer100g: ["white_rice": 28],
            proteinFractionPer100g: ["white_rice": 2.7],
            fatFractionPer100g: ["white_rice": 0.3])

        let plate = CalibrateRun.evalPlate(obs: obs, fixture: fx,
                                           composition: composition, official: false)
        #expect(abs((plate.gtCarbsByClassG["white_rice"] ?? 0) - 120 * 0.28) < 1e-4)
        #expect(abs((plate.gtProteinByClassG["white_rice"] ?? 0) - 120 * 0.027) < 1e-4)
    }
}
#endif
