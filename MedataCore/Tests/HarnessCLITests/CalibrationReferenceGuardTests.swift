#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Task 20: the calibration artefact records which support-plane reference each β
// was fitted under, and β_c is fitted only on the subset sharing the reference it
// will be applied under (Reqs 5.3, 5.4).
//
// A β_c is a ratio between a measured volume and a weighed mass, so it is valid
// only against the geometric basis it was fitted on. Applying a β fitted above
// the table to volumes measured above the plate is the ~3x error this feature
// exists to remove, reintroduced through the calibration path.
@Suite("Calibration-artefact support-plane reference guard (Reqs 5.3, 5.4)")
struct CalibrationReferenceGuardTests {

    // MARK: – Req 5.4: fitted within one reference

    @Test("only attempts recorded against the applied reference enter the fit")
    func referenceGateAdmitsOnlyTheMatchingSubset() {
        let gated = CalibrateRun.applyReferenceGate([
            input("a", reference: .foodSupport),
            input("b", reference: .edgeBand),
            input("c", reference: .foodSupport),
            input("d", reference: .plateRegion),
        ])
        #expect(gated.admitted.map(\.fixtureID) == ["a", "c"])
        #expect(gated.excluded == ["b", "d"])
    }

    // An attempt that recorded no reference derived no depth plane, or predates
    // the feature. Either way its volumes rest on a basis nothing can identify,
    // so it is excluded — absent BLOCKS, it does not permit.
    @Test("an attempt recording no reference is excluded, not admitted")
    func absentReferenceIsExcludedFromTheFit() {
        let gated = CalibrateRun.applyReferenceGate([
            input("a", reference: .foodSupport),
            input("legacy", reference: nil),
        ])
        #expect(gated.admitted.map(\.fixtureID) == ["a"])
        #expect(gated.excluded == ["legacy"])
    }

    @Test("the exclusions are recorded, not silently dropped")
    func exclusionsSurviveIntoTheRunSummary() throws {
        let gated = CalibrateRun.applyReferenceGate([
            input("a", reference: .foodSupport),
            input("b", reference: .edgeBand),
        ])
        let artifact = makeArtifact(runSummary: CalibrationArtifact.RunSummary(
            depthTestSplitExcluded: [], purityDropped: [], planeFitSkipped: [],
            stackingExcluded: [], liquidExcluded: [],
            supportPlaneReferenceExcluded: gated.excluded))
        let json = try encoded(artifact)
        let summary = try #require(json["run_summary"] as? [String: Any])
        #expect(summary["support_plane_reference_excluded"] as? [String] == ["b"])
    }

    // MARK: – Req 5.3: the artefact says what it was fitted on

    @Test("the artefact records the reference betaPool was fitted under")
    func artefactRecordsTheReference() throws {
        let json = try encoded(makeArtifact())
        #expect(json["support_plane_reference"] as? String == "foodSupport")
    }

    // The corpus spans two references permanently (Decision 17), so one artefact
    // carries both — and a consumer can only keep them apart per class.
    @Test("each class entry records the reference its own beta was fitted under")
    func classEntriesRecordTheirOwnReference() throws {
        let json = try encoded(makeArtifact())
        let classes = try #require(json["classes"] as? [String: [String: Any]])
        #expect(classes["white_rice"]?["support_plane_reference"] as? String
                == "foodSupport", "single-dominant β ride the food-support plane")
        #expect(classes["chips_fries"]?["support_plane_reference"] as? String
                == "plateRegion", "mixture β ride the flood-filled plate region")
        // A pooled/unity class carries no fit of its own, so it rides the pool's
        // reference — which is what a consumer applying it would be applying.
        #expect(classes["peas"]?["support_plane_reference"] as? String == "foodSupport")
    }

    // Cross-dataset-calibration Decision 16 (Req 8.3): a mixture β contributed
    // EXCLUSIVELY by MetaFood3D was integrated above the authored plane the
    // object rests on — the food-support basis — so it stamps `foodSupport`
    // and is applicable at bake. Any Nutrition5k contribution keeps the
    // fail-closed `plateRegion` stamp, as does an empty contributor record
    // (pinned above via chips_fries).
    @Test("a MetaFood3D-only mixture beta stamps the food-support reference")
    func metaFood3DOnlyMixtureBetaStampsFoodSupport() throws {
        let merged: [String: CalibrationMerge.ClassCalibration] = [
            "pasta": .init(className: "pasta", beta: 0.8,
                           status: .calibrated, provenance: .n5kMixture,
                           standardError: 0.01, effectiveSample: 34, clamped: false,
                           contributingDatasets: ["metafood3d": 34],
                           singleSourceUncorroborated: true),
            "broccoli": .init(className: "broccoli", beta: 0.9,
                              status: .calibrated, provenance: .n5kMixture,
                              standardError: 0.02, effectiveSample: 66, clamped: false,
                              contributingDatasets: ["nutrition5k": 34,
                                                     "metafood3d": 32]),
        ]
        let json = try encoded(CalibrationArtifact(
            merged: merged, betaPool: 1.0, supportPlaneReference: .foodSupport,
            lineage: nil, runSummary: nil))
        let classes = try #require(json["classes"] as? [String: [String: Any]])
        #expect(classes["pasta"]?["support_plane_reference"] as? String
                == "foodSupport",
                "an MF3D-only β is fitted above the authored support plane")
        #expect(classes["broccoli"]?["support_plane_reference"] as? String
                == "plateRegion",
                "pooling with N5k mixture rows mixes bases — fail closed")
    }

    // An artefact produced before this feature records none. Encoding the null
    // explicitly is what lets the bake distinguish "recorded no reference" from
    // "carries an unexpected shape" and refuse the first (Req 5.3).
    @Test("an artefact fitted without a known reference encodes an explicit null")
    func absentReferenceIsEncodedAsNull() throws {
        let data = try CalibrationArtifact.encoder()
            .encode(makeArtifact(reference: nil))
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["support_plane_reference"] is NSNull,
                "the key must be present and null, not missing")
    }

    // MARK: – Helpers

    private func input(_ id: String,
                       reference: SupportPlaneReference?) -> MealCalibrationInput {
        MealCalibrationInput(
            fixtureID: id, capturePath: .singleViewLidar, dominantClass: "white_rice",
            predictedCarbsPerClass: ["white_rice": 30],
            actualCarbsPerClass: ["white_rice": 30],
            groundTruthTotalCarbsG: 30,
            supportPlaneReference: reference)
    }

    private func encoded(_ artifact: CalibrationArtifact) throws -> [String: Any] {
        let data = try CalibrationArtifact.encoder().encode(artifact)
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeArtifact(
        reference: SupportPlaneReference? = .foodSupport,
        runSummary: CalibrationArtifact.RunSummary? = nil
    ) -> CalibrationArtifact {
        let merged: [String: CalibrationMerge.ClassCalibration] = [
            "white_rice": .init(className: "white_rice", beta: 0.82,
                                status: .calibrated, provenance: .n5kSingleDominant,
                                standardError: 0.04, effectiveSample: 45, clamped: false),
            "chips_fries": .init(className: "chips_fries", beta: 1.1,
                                 status: .calibrated, provenance: .n5kMixture,
                                 standardError: 0.02, effectiveSample: 60, clamped: false),
            "peas": .init(className: "peas", beta: 1.0,
                          status: .uncalibratedUnity, provenance: .none,
                          standardError: nil, effectiveSample: 3, clamped: false),
        ]
        return CalibrationArtifact(
            merged: merged, betaPool: 1.0, supportPlaneReference: reference,
            lineage: nil, runSummary: runSummary)
    }
}
#endif
