#if HARNESS_ENABLED
import Foods
import Foundation
import Testing
@testable import HarnessCore

// Serialization round-trip for the cross-dataset-calibration artifact
// additions (spec task 11, Reqs 2.5/4.3/6.1/9.1): ClassEntry provenance
// fields, the lineage render_config + per_dataset blocks, and the RunSummary
// per-dataset exclusion buckets. All additive — an artifact without them
// still decodes (Req 7.2).
@Suite("CalibrationArtifact cross-dataset schema")
struct CalibrationArtifactSchemaTests {

    func makeArtifact() -> CalibrationArtifact {
        let merged: [String: CalibrationMerge.ClassCalibration] = [
            "white_rice": .init(
                className: "white_rice", beta: 0.78, status: .calibrated,
                provenance: .n5kMixture, standardError: 0.03,
                effectiveSample: 42, clamped: false,
                contributingDatasets: ["nutrition5k": 12, "metafood3d": 30],
                singleSourceUncorroborated: false),
            "pasta": .init(
                className: "pasta", beta: 0.9, status: .calibrated,
                provenance: .n5kMixture, standardError: 0.05,
                effectiveSample: 33, clamped: false,
                contributingDatasets: ["metafood3d": 33],
                singleSourceUncorroborated: true),
        ]
        let render = CalibrationArtifact.RenderConfig(
            intrinsicsModel: "realsense_d435_factory_640x480",
            planeDepthMm: 385, imageWidth: 640, imageHeight: 480,
            seatingRule: "stable_rest_base_on_plane")
        let lineage = CalibrationArtifact.Lineage(
            n5kRelease: "3fa8c1d2e4b5", n5kMetadataVersion: "9c7b6a5d4e3f",
            mappingArtifactVersion: "1",
            tauRoute: 0.9, tauPurity: 0.9,
            tauEff: MixtureBetaCalibrator.tauEff,
            kappaStacking: MixtureBetaCalibrator.stackingKappa,
            seed: 42,
            effectiveSamplePerClass: ["white_rice": 42, "pasta": 33],
            conditionNumber: 2.1,
            identifiablePerClass: ["white_rice": true, "pasta": true],
            pinnedIntrinsicsModel: "realsense_d435_factory_640x480",
            licence: "CC BY 4.0",
            renderConfig: render,
            perDataset: [
                "nutrition5k": .init(snapshot: "3fa8c1d2e4b5",
                                     mappingArtifactVersion: "1",
                                     licence: "CC BY 4.0"),
                "metafood3d": .init(snapshot: "mf3d_snap_01",
                                    mappingArtifactVersion: "a1b2c3d4e5f6",
                                    licence: "CC BY-NC 4.0"),
            ])
        let runSummary = CalibrationArtifact.RunSummary(
            depthTestSplitExcluded: ["dish_1"],
            unmappedExcluded: ["dish_2"],
            purityDropped: [],
            planeFitSkipped: ["mf3d_bad"],
            stackingExcluded: [],
            liquidExcluded: [],
            depthTestSplitExcludedByDataset: ["nutrition5k": 1],
            unmappedExcludedByDataset: ["nutrition5k": 1],
            ingestionSkippedByDataset: ["nutrition5k": 5, "metafood3d": 3])
        return CalibrationArtifact(
            merged: merged, betaPool: 1.0,
            supportPlaneReference: .foodSupport,
            lineage: lineage, runSummary: runSummary)
    }

    @Test("The artifact round-trips through its own encoder losslessly")
    func artifactRoundTrips() throws {
        let original = makeArtifact()
        let data = try CalibrationArtifact.encoder().encode(original)
        let decoded = try JSONDecoder().decode(CalibrationArtifact.self, from: data)

        // Encoding the decoded value again must be byte-identical: the
        // encoder sorts keys, so equality of bytes is equality of content.
        let reEncoded = try CalibrationArtifact.encoder().encode(decoded)
        #expect(data == reEncoded)

        let rice = try #require(decoded.classes["white_rice"])
        #expect(rice.contributingDatasets == ["nutrition5k": 12, "metafood3d": 30])
        #expect(!rice.singleSourceUncorroborated)
        let pasta = try #require(decoded.classes["pasta"])
        #expect(pasta.contributingDatasets == ["metafood3d": 33])
        #expect(pasta.singleSourceUncorroborated)

        let lineage = try #require(decoded.lineage)
        let render = try #require(lineage.renderConfig)
        #expect(render.planeDepthMm == 385)
        #expect(render.seatingRule == "stable_rest_base_on_plane")
        #expect(lineage.perDataset["metafood3d"]?.snapshot == "mf3d_snap_01")
        // Per-dataset licence provenance (Decision 17): the differing source
        // licences survive the round trip attributably.
        #expect(lineage.perDataset["metafood3d"]?.licence == "CC BY-NC 4.0")
        #expect(lineage.perDataset["nutrition5k"]?.licence == "CC BY 4.0")

        let summary = try #require(decoded.runSummary)
        #expect(summary.ingestionSkippedByDataset == ["nutrition5k": 5, "metafood3d": 3])
        #expect(summary.depthTestSplitExcludedByDataset == ["nutrition5k": 1])
        #expect(summary.unmappedExcludedByDataset == ["nutrition5k": 1])
    }

    @Test("The new keys appear snake_cased in the JSON (bake-side contract)")
    func newKeysAreSnakeCased() throws {
        let data = try CalibrationArtifact.encoder().encode(makeArtifact())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let classes = try #require(json["classes"] as? [String: [String: Any]])
        let rice = try #require(classes["white_rice"])
        #expect((rice["contributing_datasets"] as? [String: Int])?["metafood3d"] == 30)
        #expect(rice["single_source_uncorroborated"] as? Bool == false)

        let lineage = try #require(json["lineage"] as? [String: Any])
        let render = try #require(lineage["render_config"] as? [String: Any])
        #expect(render["plane_depth_mm"] as? Double == 385)
        #expect(render["intrinsics_model"] as? String == "realsense_d435_factory_640x480")
        #expect(render["skew_delta"] as? Double != nil)
        #expect(render["skew_alpha"] as? Double != nil)
        // Req 2.5: the noise-free-render limitation is stated in lineage.
        let note = try #require(render["noise_free_render_note"] as? String)
        #expect(note.contains("noise-free"))
        #expect((lineage["per_dataset"] as? [String: [String: Any]])?
            .keys.contains("metafood3d") == true)

        let summary = try #require(json["run_summary"] as? [String: Any])
        #expect((summary["ingestion_skipped_by_dataset"] as? [String: Int])?["metafood3d"] == 3)
    }

    @Test("A pre-cross-dataset artifact without the new keys still decodes (Req 7.2)")
    func preFeatureArtifactDecodes() throws {
        let legacy = """
        {"betaPool": 1.0,
         "classes": {"broccoli": {
            "beta": 0.5, "status": "calibrated", "provenance": "n5k_mixture",
            "standard_error": 0.05, "effective_sample": 34, "clamped": false,
            "support_plane_reference": "plateRegion"}},
         "lineage": null, "run_summary": null,
         "support_plane_reference": "foodSupport"}
        """
        let decoded = try JSONDecoder().decode(
            CalibrationArtifact.self, from: Data(legacy.utf8))
        let broccoli = try #require(decoded.classes["broccoli"])
        #expect(broccoli.contributingDatasets.isEmpty)
        #expect(!broccoli.singleSourceUncorroborated)
        #expect(decoded.supportPlaneReference == "foodSupport")
        #expect(decoded.volumeFitDiagnostic == nil)
    }

    @Test("A per-dataset lineage entry without the licence key still decodes (pre-Decision-17)")
    func preLicenceDatasetLineageDecodes() throws {
        let legacy = """
        {"snapshot": "3fa8c1d2e4b5", "mapping_artifact_version": "1"}
        """
        let decoded = try JSONDecoder().decode(
            CalibrationArtifact.DatasetLineage.self, from: Data(legacy.utf8))
        #expect(decoded.licence == "")
        #expect(decoded.snapshot == "3fa8c1d2e4b5")
    }

    @Test("The volume-fit diagnostic block round-trips and is omitted when absent (Req 2.3/7.2)")
    func volumeFitDiagnosticBlockRoundTrips() throws {
        // Absent: the key must not appear at all — pre-feature shape.
        let bare = try CalibrationArtifact.encoder().encode(makeArtifact())
        let bareJSON = try #require(
            try JSONSerialization.jsonObject(with: bare) as? [String: Any])
        #expect(bareJSON["volume_fit_diagnostic"] == nil)

        // Present: snake keys, β pairing, divergence flag survive.
        let report = VolumeFitDiagnostic.compute(
            observations: [
                .init(fixtureID: "mf3d_a", className: "white_rice",
                      estimatedVolumeCm3: 100),
                .init(fixtureID: "mf3d_b", className: "pasta",
                      estimatedVolumeCm3: 100),
            ],
            truthVolumeMm3ByFixture: ["mf3d_a": 100_000, "mf3d_b": 100_000])
        let block = CalibrationArtifact.VolumeFitDiagnosticBlock(
            report: report, bakedBeta: ["white_rice": 0.7])
        let artifact = CalibrationArtifact(
            merged: [:], betaPool: 1.0, supportPlaneReference: .foodSupport,
            lineage: nil, runSummary: nil, volumeFitDiagnostic: block)
        let data = try CalibrationArtifact.encoder().encode(artifact)

        let decoded = try JSONDecoder().decode(CalibrationArtifact.self, from: data)
        #expect(decoded.volumeFitDiagnostic == block)

        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diag = try #require(json["volume_fit_diagnostic"] as? [String: Any])
        let perClass = try #require(diag["per_class"] as? [String: [String: Any]])
        let rice = try #require(perClass["white_rice"])
        #expect(rice["beta_geom"] as? Double == 1.0)
        #expect(rice["beta_baked"] as? Double != nil)
        // 0.7 vs β_geom 1.0 is beyond the δ = 0.20 practical bound.
        #expect(rice["diverges_from_mass_fit"] as? Bool == true)
        let pasta = try #require(perClass["pasta"])
        #expect(pasta["beta_baked"] is NSNull,
                "an uncalibrated class records an explicit null baked β")
        #expect(pasta["diverges_from_mass_fit"] as? Bool == false)
    }
}
#endif
