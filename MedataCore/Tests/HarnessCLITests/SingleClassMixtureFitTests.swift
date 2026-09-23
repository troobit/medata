#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import Testing
@testable import HarnessCore

// Single-class mixture-fit verification (cross-dataset-calibration spec task
// 14, Reqs 2.2/3.1–3.3/4.1/4.2, Decision 11 / design M1 check).
//
// A MetaFood3D object is a degenerate one-class mixture row: no segmenter, no
// checkpoint, mass fraction 1.0. These tests pin the two facts Decision 11
// rests on — that such a row recovers β = GT_mass/(V_est·ρ_DB) through the
// existing BVLS path unchanged, and that adding single-class rows to a
// collinear N5k pool increments the class's effective sample and LOWERS its
// SE (the information-weighting of Req 4.2 falls out of the conditioning, not
// a bespoke weighting layer).
@Suite("Single-class mixture rows (MetaFood3D)")
struct SingleClassMixtureFitTests {

    static let rho: Float = 0.9   // g/cm³, the ρ_DB stand-in

    // MARK: - β recovery through the full no-segmenter path

    @Test("A single-class row fits β ≈ GT_mass/(V_est·ρ_DB) with no segmenter output")
    func singleClassRowRecoversBeta() throws {
        // V_est from the injected-plane estimator path (the same fixture shape
        // ingest emits: mixture, sentinel SHA, no probability tensor), then 30
        // rows at masses consistent with a true β of 0.8.
        let scene = InjectedPlaneTests()
        let trueBeta: Float = 0.8
        let fixture = scene.makeFixture(id: "mf3d_0", massG: 1)
        let plane = CalibrateRun.authoredSupportPlane(
            gravity: scene.gravity, planeDepthMm: InjectedPlaneTests.planeMm)
        let vEst = try CalibrateRun.mixtureObservation(
            fixture: fixture, injectedSupportPlane: plane).totalHullVolumeCm3

        // GT mass such that mass/(V·ρ) = β_true.
        let massG = trueBeta * vEst * Self.rho
        let obs = (0..<30).map { i in
            MixtureBetaCalibrator.PlateObservation(
                fixtureID: "mf3d_\(i)",
                totalHullVolumeCm3: vEst,
                massByClassG: ["white_rice": massG])
        }
        let result = MixtureBetaCalibrator.fit(
            obs, densityByClass: ["white_rice": Self.rho])

        let beta = try #require(result.betaPerClass["white_rice"])
        #expect(abs(beta - trueBeta) <= 1e-3)
        #expect(abs(beta - massG / (vEst * Self.rho)) <= 1e-3)
        #expect(result.identifiablePerClass["white_rice"] == true)
        #expect(result.effectiveSamplePerClass["white_rice"] == 30)
    }

    // MARK: - Effective-sample and SE behaviour (Decision 11 / M1)

    // A collinear N5k-style pool: two classes always co-occurring 50/50, so
    // their design-matrix columns are proportional and neither is
    // identifiable. Deterministic ±2% volume noise keeps the residual
    // variance non-zero (an exact fit would read SE 0 everywhere).
    func collinearPlates(count: Int) -> [MixtureBetaCalibrator.PlateObservation] {
        (0..<count).map { i in
            let mass: Float = 100
            let volume = (mass / Self.rho) * 2
            let noise = 1 + Float(i % 5 - 2) / 100
            return MixtureBetaCalibrator.PlateObservation(
                fixtureID: "n5k_\(i)",
                totalHullVolumeCm3: volume * noise,
                massByClassG: ["white_rice": mass, "pasta": mass])
        }
    }

    @Test("Single-class rows increment the effective sample and lower the SE")
    func singleClassRowsBreakCollinearity() throws {
        let base = collinearPlates(count: 40)
        let density: [String: Float] = ["white_rice": Self.rho, "pasta": Self.rho]

        let before = MixtureBetaCalibrator.fit(base, densityByClass: density)
        #expect(before.effectiveSamplePerClass["white_rice"] == 40)
        #expect(before.identifiablePerClass["white_rice"] == false,
                "a 50/50 co-occurring pool must be unidentifiable on raw count alone (Req 4.2)")
        let seBefore = try #require(before.standardErrorPerClass["white_rice"])

        // 30 single-class rows (mass fraction 1.0 ≥ τ_eff): each counts +1
        // toward white_rice and, being orthogonal, tightens its SE.
        let single = (0..<30).map { i in
            MixtureBetaCalibrator.PlateObservation(
                fixtureID: "mf3d_\(i)",
                totalHullVolumeCm3: (100 / Self.rho) * (1 + Float(i % 5 - 2) / 100),
                massByClassG: ["white_rice": 100])
        }
        let after = MixtureBetaCalibrator.fit(base + single, densityByClass: density)

        #expect(after.effectiveSamplePerClass["white_rice"] == 70,
                "each single-class row increments the class count by one")
        let seAfter = try #require(after.standardErrorPerClass["white_rice"])
        #expect(seAfter < seBefore,
                "SE \(seBefore) → \(seAfter): a single-non-zero row must add information")
        #expect(after.identifiablePerClass["white_rice"] == true)

        // The existing mixture path is unchanged: pasta's count comes from the
        // same τ_eff rule as before the MetaFood3D rows joined.
        #expect(after.effectiveSamplePerClass["pasta"] == 40)
    }
}
#endif
