#if HARNESS_ENABLED
import Foods
import Foundation
import Testing
@testable import HarnessCore

// Backwards-compat golden (cross-dataset-calibration Req 7.1, spec task 22):
// an N5k-only calibrate through the NEW pooling path (per-dataset solves +
// corroboration + skew guard, with a single dataset) reproduces the
// pre-cross-dataset baseline β byte-for-byte. The pooling path with one
// dataset must be the identity — the guard has nothing to compare and the
// pooled solve IS the dataset solve.
@Suite("Backwards-compat golden (N5k-only)")
struct BackwardsCompatGoldenTests {

    // A deterministic N5k-style mixture pool: three classes with varied
    // co-occurrence so at least one is identifiable, plus deterministic
    // volume noise so the SEs are non-zero. Mirrors the corpus shape (mixed
    // plates, mapped masses, one β solve) without needing the raw corpus.
    func syntheticPool() -> [MixtureBetaCalibrator.PlateObservation] {
        let rho: [String: Float] = ["broccoli": 0.6, "carrot": 0.7, "white_rice": 0.9]
        var obs: [MixtureBetaCalibrator.PlateObservation] = []
        let trueBeta: [String: Float] = ["broccoli": 0.5, "carrot": 0.9, "white_rice": 0.8]
        for i in 0..<60 {
            // Vary the mass mix per plate so the columns are not collinear.
            let mB = Float(60 + (i % 7) * 10)
            let mC = Float(40 + (i % 5) * 15)
            let mR = Float(30 + (i % 3) * 25)
            var volume: Float = 0
            volume += (mB / rho["broccoli"]!) / trueBeta["broccoli"]!
            volume += (mC / rho["carrot"]!) / trueBeta["carrot"]!
            volume += (mR / rho["white_rice"]!) / trueBeta["white_rice"]!
            let noise = 1 + Float(i % 9 - 4) / 200   // ±2%
            obs.append(MixtureBetaCalibrator.PlateObservation(
                fixtureID: "dish_\(i)",
                totalHullVolumeCm3: volume * noise,
                massByClassG: ["broccoli": mB, "carrot": mC, "white_rice": mR]))
        }
        return obs
    }

    @Test("Baseline β are bit-identical through the single-dataset pooling path")
    func baselineBetaBitIdentical() throws {
        let pool = syntheticPool()
        let density: [String: Float] = ["broccoli": 0.6, "carrot": 0.7, "white_rice": 0.9]
        let mixture = MixtureBetaCalibrator.fit(pool, densityByClass: density)
        let sd = BetaCalibrator.PerClassFit(classes: [:], betaPool: 1.0)

        // Pre-cross-dataset path.
        let baseline = CalibrationMerge.merge(singleDominant: sd, mixture: mixture)
        // New pooling path, exercised with the single N5k dataset (Req 7.1).
        let pooled = CalibrationMerge.merge(
            singleDominant: sd, mixture: mixture,
            perDataset: [.init(dataset: "nutrition5k", result: mixture)])

        #expect(Set(baseline.keys) == Set(pooled.keys))
        for (name, b) in baseline {
            let p = try #require(pooled[name])
            #expect(p.beta.bitPattern == b.beta.bitPattern,
                    "\(name): β \(b.beta) must be byte-identical, got \(p.beta)")
            #expect(p.status == b.status)
            #expect(p.provenance == b.provenance)
            #expect(p.effectiveSample == b.effectiveSample)
            #expect(p.standardError == b.standardError)
        }
        // At least one class actually calibrated — otherwise the identity
        // above proves nothing about the calibrated branch.
        #expect(baseline.values.contains { $0.status == .calibrated })
    }

    @Test("The artifact's baseline class entries are unchanged by the new schema fields")
    func artifactBaselineEntriesUnchanged() throws {
        let pool = syntheticPool()
        let density: [String: Float] = ["broccoli": 0.6, "carrot": 0.7, "white_rice": 0.9]
        let mixture = MixtureBetaCalibrator.fit(pool, densityByClass: density)
        let sd = BetaCalibrator.PerClassFit(classes: [:], betaPool: 1.0)
        let merged = CalibrationMerge.merge(
            singleDominant: sd, mixture: mixture,
            perDataset: [.init(dataset: "nutrition5k", result: mixture)])

        let artifact = CalibrationArtifact(
            merged: merged, betaPool: 1.0,
            supportPlaneReference: .foodSupport, lineage: nil)
        let data = try CalibrationArtifact.encoder().encode(artifact)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let classes = try #require(json["classes"] as? [String: [String: Any]])

        // The pre-existing keys keep their meaning; the new keys are additive
        // (Req 7.2) — no existing key was renamed or removed.
        for (name, c) in merged {
            let entry = try #require(classes[name])
            #expect(entry["beta"] != nil)
            #expect(entry["status"] as? String == c.status.rawValue)
            #expect(entry["provenance"] as? String == c.provenance.rawValue)
            #expect(entry["effective_sample"] as? Int == c.effectiveSample)
            #expect(entry["contributing_datasets"] != nil)
            #expect(entry["single_source_uncorroborated"] != nil)
        }
    }
}
#endif
