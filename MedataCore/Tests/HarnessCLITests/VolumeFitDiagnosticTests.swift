#if HARNESS_ENABLED
import Foundation
import Testing
@testable import HarnessCore

// Tests for the volume-fit diagnostic (cross-dataset-calibration Req 2.3,
// Decision 7, spec task 9). β_geom = V_mesh_true / V_est per object, mean per
// class, from the metafood3d_truth.json sidecar. Reported, never baked.
@Suite("VolumeFitDiagnostic")
struct VolumeFitDiagnosticTests {

    @Test("β_geom is the per-class mean of V_mesh_true / V_est")
    func betaGeomIsPerClassMeanOfRatios() throws {
        // rice objects: 100 cm³ true / 80 cm³ est = 1.25, 60/60 = 1.0 → mean 1.125.
        // pasta object: 90/120 = 0.75.
        let truth: [String: Double] = [
            "mf3d_rice_0": 100_000,   // mm³
            "mf3d_rice_1": 60_000,
            "mf3d_pasta_0": 90_000,
        ]
        let report = VolumeFitDiagnostic.compute(
            observations: [
                .init(fixtureID: "mf3d_rice_0", className: "white_rice",
                      estimatedVolumeCm3: 80),
                .init(fixtureID: "mf3d_rice_1", className: "white_rice",
                      estimatedVolumeCm3: 60),
                .init(fixtureID: "mf3d_pasta_0", className: "pasta",
                      estimatedVolumeCm3: 120),
            ],
            truthVolumeMm3ByFixture: truth)

        let rice = try #require(report.perClass["white_rice"])
        #expect(abs(rice.betaGeom - 1.125) < 1e-5)
        #expect(rice.sampleCount == 2)
        let pasta = try #require(report.perClass["pasta"])
        #expect(abs(pasta.betaGeom - 0.75) < 1e-5)
        #expect(pasta.sampleCount == 1)
    }

    @Test("Objects with no truth entry are recorded, not silently dropped")
    func missingTruthRecorded() {
        let report = VolumeFitDiagnostic.compute(
            observations: [
                .init(fixtureID: "mf3d_known", className: "white_rice",
                      estimatedVolumeCm3: 50),
                .init(fixtureID: "mf3d_orphan", className: "white_rice",
                      estimatedVolumeCm3: 50),
            ],
            truthVolumeMm3ByFixture: ["mf3d_known": 50_000])

        #expect(report.missingTruth == ["mf3d_orphan"])
        #expect(report.perClass["white_rice"]?.sampleCount == 1)
    }

    @Test("Non-positive volumes are recorded as invalid and excluded from the mean")
    func invalidVolumesExcluded() {
        let report = VolumeFitDiagnostic.compute(
            observations: [
                .init(fixtureID: "mf3d_zero_est", className: "pasta",
                      estimatedVolumeCm3: 0),
                .init(fixtureID: "mf3d_zero_true", className: "pasta",
                      estimatedVolumeCm3: 40),
                .init(fixtureID: "mf3d_good", className: "pasta",
                      estimatedVolumeCm3: 40),
            ],
            truthVolumeMm3ByFixture: [
                "mf3d_zero_est": 40_000,
                "mf3d_zero_true": 0,
                "mf3d_good": 40_000,
            ])

        #expect(Set(report.invalidVolume) == ["mf3d_zero_est", "mf3d_zero_true"])
        #expect(report.perClass["pasta"] ==
                VolumeFitDiagnostic.ClassDiagnostic(betaGeom: 1.0, sampleCount: 1))
    }

    @Test("The truth sidecar parses the flat {fixture_id: mesh_volume_mm3} shape")
    func truthSidecarParses() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("metafood3d_truth_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"mf3d_rice_0": 123456.5, "mf3d_pasta_0": 90000}"#
            .write(to: url, atomically: true, encoding: .utf8)

        let truth = try VolumeFitDiagnostic.loadTruth(from: url)
        #expect(truth["mf3d_rice_0"] == 123456.5)
        #expect(truth["mf3d_pasta_0"] == 90000)
    }
}
#endif
