#if HARNESS_ENABLED
import Foundation

// Volume-fit diagnostic (cross-dataset-calibration Req 2.3, Decision 7).
// β_geom = V_mesh_true / V_est per MetaFood3D object, aggregated per class.
// REPORTED, NEVER BAKED: the baked β is the mass-fit (Req 2.2), which
// conflates geometry with the density draw; β_geom isolates the estimator's
// geometric bias so a large gap between the two flags a density problem.
// True mesh volumes come from the ingestion sidecar `metafood3d_truth.json`
// ({fixture_id: mesh_volume_mm3}, design §The three β computations).
public enum VolumeFitDiagnostic {

    // One rendered single-food object run through the volume estimator.
    public struct Observation: Sendable {
        public let fixtureID: String
        public let className: String
        public let estimatedVolumeCm3: Float

        public init(fixtureID: String, className: String, estimatedVolumeCm3: Float) {
            self.fixtureID = fixtureID
            self.className = className
            self.estimatedVolumeCm3 = estimatedVolumeCm3
        }
    }

    public struct ClassDiagnostic: Sendable, Equatable {
        // Mean over the class's objects of V_mesh_true / V_est.
        public let betaGeom: Float
        public let sampleCount: Int
    }

    public struct Report: Sendable {
        public let perClass: [String: ClassDiagnostic]
        // Objects with no truth-sidecar entry — attributable, not silently dropped.
        public let missingTruth: [String]
        // Objects whose estimated or true volume was non-positive/non-finite.
        public let invalidVolume: [String]
    }

    // Parse the ingestion truth sidecar: a flat {fixture_id: mesh_volume_mm3}.
    public static func loadTruth(from url: URL) throws -> [String: Double] {
        try JSONDecoder().decode([String: Double].self, from: Data(contentsOf: url))
    }

    public static func compute(
        observations: [Observation],
        truthVolumeMm3ByFixture: [String: Double]
    ) -> Report {
        var ratios: [String: [Double]] = [:]
        var missing: [String] = []
        var invalid: [String] = []
        for obs in observations {
            guard let trueMm3 = truthVolumeMm3ByFixture[obs.fixtureID] else {
                missing.append(obs.fixtureID)
                continue
            }
            let estCm3 = Double(obs.estimatedVolumeCm3)
            let trueCm3 = trueMm3 / 1000.0
            guard estCm3.isFinite, trueCm3.isFinite, estCm3 > 0, trueCm3 > 0 else {
                invalid.append(obs.fixtureID)
                continue
            }
            ratios[obs.className, default: []].append(trueCm3 / estCm3)
        }
        var perClass: [String: ClassDiagnostic] = [:]
        for (c, rs) in ratios {
            perClass[c] = ClassDiagnostic(
                betaGeom: Float(rs.reduce(0, +) / Double(rs.count)),
                sampleCount: rs.count)
        }
        return Report(perClass: perClass,
                      missingTruth: missing.sorted(),
                      invalidVolume: invalid.sorted())
    }
}
#endif
