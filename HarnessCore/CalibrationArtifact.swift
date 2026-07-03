#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import PortableContracts

// Calibrate-run wiring (routing, split exclusion, τ_purity gate) and the
// calibrate JSON artifact — the sole stream B↔C interface (design §DB bake
// handoff contract): HarnessCLI writes this file, tools/food_db/generate.py
// consumes it; the two streams never share source files.

public enum CalibrateRun {
    // τ_purity (Req 4.2): the mass-dominant class's above-plane-VOLUME share a
    // stamped single-dominant plate must clear to enter the fit. Distinct from
    // τ_route (mass fraction, at ingestion) and τ_eff (effective-sample).
    public static let tauPurity: Float = 0.90
    // τ_route is applied by tools/nutrition5k/ingest.py; recorded here only so
    // the lineage block can carry it (Req 5.5).
    public static let tauRoute: Float = 0.90

    // N5k's official RGB-D test split (dish_ids/splits/depth_test_ids.txt —
    // the depth split, NOT the rgb_* files). One dish id per line.
    public static func loadDepthTestSplit(from url: URL) throws -> Set<String> {
        let text = try String(contentsOf: url, encoding: .utf8)
        return Set(text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    public struct Routed {
        public let mixture: [PbMealFixture]
        public let singleDominant: [PbMealFixture]   // includes legacy fixtures
        public let depthTestExcluded: [PbMealFixture]
    }

    // Depth-test-split exclusion FIRST — before any selection (Req 4.4) —
    // then routing per the authoritative estimator_path stamp (Req 3.7).
    // Legacy fixtures (empty estimator_path) ride the single-dominant path,
    // which is the pre-N5k behaviour.
    public static func route(
        fixtures: [PbMealFixture],
        depthTestSplit: Set<String>
    ) -> Routed {
        var mixture: [PbMealFixture] = []
        var singleDominant: [PbMealFixture] = []
        var excluded: [PbMealFixture] = []
        for fx in fixtures {
            if depthTestSplit.contains(fx.fixtureID) {
                excluded.append(fx)
                continue
            }
            if fx.estimatorPath == "mixture" {
                mixture.append(fx)
            } else {
                singleDominant.append(fx)
            }
        }
        return Routed(mixture: mixture, singleDominant: singleDominant,
                      depthTestExcluded: excluded)
    }

    // Purity = above-plane volume of the mass-dominant class ÷ total
    // above-plane food-region volume (sentinel/at-cap already excluded by the
    // estimator). A segmentation that disagrees with the mass-dominant class
    // yields a low fraction — no separate disagreement rule is needed.
    public static func volumePurity(
        perClassVolumesCm3: [String: Float],
        massDominantClass: String?
    ) -> Float {
        guard let dominant = massDominantClass else { return 0 }
        let total = perClassVolumesCm3.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return perClassVolumesCm3[dominant, default: 0] / total
    }

    public struct PurityGated {
        public let admitted: [MealCalibrationInput]
        public let dropped: [String]
    }

    // A stamped single-dominant plate that fails τ_purity is DROPPED and
    // recorded — never re-routed: the mixture path rejects probability-
    // carrying fixtures (Req 3.7), and dropping preserves the Req 5.2
    // at-most-one-estimator invariant. Inputs without a mass-dominant entry
    // (legacy fixtures) bypass the gate — it is an N5k-path admission rule.
    public static func applyPurityGate(
        _ inputs: [MealCalibrationInput],
        massDominantByFixture: [String: String]
    ) -> PurityGated {
        var admitted: [MealCalibrationInput] = []
        var dropped: [String] = []
        for input in inputs {
            guard let dominant = massDominantByFixture[input.fixtureID] else {
                admitted.append(input)
                continue
            }
            let purity = volumePurity(perClassVolumesCm3: input.perClassVolumesCm3,
                                      massDominantClass: dominant)
            if purity >= tauPurity {
                admitted.append(input)
            } else {
                dropped.append(input.fixtureID)
            }
        }
        return PurityGated(admitted: admitted, dropped: dropped)
    }

    // Build a mixture PlateObservation from a fixture: plate-region plane fit
    // (Req 3.6) + depth-threshold total hull volume. Throws on a poor plate
    // plane so the CLI can skip and record the plate (Req 3.4/3.8).
    public static func mixtureObservation(
        fixture: PbMealFixture
    ) throws -> MixtureBetaCalibrator.PlateObservation {
        let intrinsics = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let depth = DepthMap(pb: fixture.nadirDepth)
        let plane = try FixtureRunner.fitPlateRegionPlane(
            depth: depth, intrinsics: intrinsics,
            gravity: Vec3(pb: fixture.gravity),
            fixtureID: fixture.fixtureID)
        let hull = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: intrinsics, supportPlane: plane))
        return MixtureBetaCalibrator.PlateObservation(
            fixtureID: fixture.fixtureID,
            totalHullVolumeCm3: hull,
            massByClassG: fixture.groundTruthClassMassG)
    }
}

// The calibrate JSON artifact. `betaPool` and `classes` predate this spec
// (existing consumers of the CalibrationJSON shape); the per-class
// provenance/SE fields, the lineage block (Req 5.5), and the run summary
// extend the same writer rather than adding a parallel output path.
public struct CalibrationArtifact: Encodable {
    public struct ClassEntry: Encodable {
        public let beta: Float
        public let status: String
        public let provenance: String
        public let standardError: Float?
        public let effectiveSample: Int
        public let clamped: Bool

        enum CodingKeys: String, CodingKey {
            case beta, status, provenance, clamped
            case standardError = "standard_error"
            case effectiveSample = "effective_sample"
        }

        // Encode a null standard_error explicitly so the bake reads a stable
        // schema rather than a sometimes-missing key.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(beta, forKey: .beta)
            try c.encode(status, forKey: .status)
            try c.encode(provenance, forKey: .provenance)
            try c.encode(standardError, forKey: .standardError)
            try c.encode(effectiveSample, forKey: .effectiveSample)
            try c.encode(clamped, forKey: .clamped)
        }
    }

    public struct Lineage: Encodable {
        public let n5kRelease: String              // SHA-256 manifest id (Req 1.4)
        public let n5kMetadataVersion: String
        public let mappingArtifactVersion: String
        public let tauRoute: Float
        public let tauPurity: Float
        public let tauEff: Float
        public let kappaStacking: Float
        public let seed: UInt64
        public let effectiveSamplePerClass: [String: Int]
        public let conditionNumber: Float
        public let identifiablePerClass: [String: Bool]
        public let pinnedIntrinsicsModel: String   // nominal camera model (Req 3.3)
        public let licence: String                 // "CC BY 4.0" (Req 1.5)

        enum CodingKeys: String, CodingKey {
            case n5kRelease = "n5k_release"
            case n5kMetadataVersion = "n5k_metadata_version"
            case mappingArtifactVersion = "mapping_artifact_version"
            case tauRoute = "tau_route"
            case tauPurity = "tau_purity"
            case tauEff = "tau_eff"
            case kappaStacking = "kappa_stacking"
            case seed
            case effectiveSamplePerClass = "effective_sample_per_class"
            case conditionNumber = "condition_number"
            case identifiablePerClass = "identifiable_per_class"
            case pinnedIntrinsicsModel = "pinned_intrinsics_model"
            case licence
        }

        public init(n5kRelease: String, n5kMetadataVersion: String,
                    mappingArtifactVersion: String, tauRoute: Float,
                    tauPurity: Float, tauEff: Float, kappaStacking: Float,
                    seed: UInt64, effectiveSamplePerClass: [String: Int],
                    conditionNumber: Float, identifiablePerClass: [String: Bool],
                    pinnedIntrinsicsModel: String, licence: String) {
            self.n5kRelease = n5kRelease
            self.n5kMetadataVersion = n5kMetadataVersion
            self.mappingArtifactVersion = mappingArtifactVersion
            self.tauRoute = tauRoute
            self.tauPurity = tauPurity
            self.tauEff = tauEff
            self.kappaStacking = kappaStacking
            self.seed = seed
            self.effectiveSamplePerClass = effectiveSamplePerClass
            self.conditionNumber = conditionNumber
            self.identifiablePerClass = identifiablePerClass
            self.pinnedIntrinsicsModel = pinnedIntrinsicsModel
            self.licence = licence
        }
    }

    // Skip/drop accounting for the run summary (Req 3.4/3.8/4.2/4.3/4.7).
    public struct RunSummary: Encodable {
        public let depthTestSplitExcluded: [String]
        public let purityDropped: [String]
        public let planeFitSkipped: [String]
        public let stackingExcluded: [String]
        public let liquidExcluded: [String]

        enum CodingKeys: String, CodingKey {
            case depthTestSplitExcluded = "depth_test_split_excluded"
            case purityDropped = "purity_dropped"
            case planeFitSkipped = "plane_fit_skipped"
            case stackingExcluded = "stacking_excluded"
            case liquidExcluded = "liquid_excluded"
        }

        public init(depthTestSplitExcluded: [String], purityDropped: [String],
                    planeFitSkipped: [String], stackingExcluded: [String],
                    liquidExcluded: [String]) {
            self.depthTestSplitExcluded = depthTestSplitExcluded
            self.purityDropped = purityDropped
            self.planeFitSkipped = planeFitSkipped
            self.stackingExcluded = stackingExcluded
            self.liquidExcluded = liquidExcluded
        }
    }

    public let betaPool: Float
    public let classes: [String: ClassEntry]
    public let lineage: Lineage?
    public let runSummary: RunSummary?

    enum CodingKeys: String, CodingKey {
        case betaPool, classes, lineage
        case runSummary = "run_summary"
    }

    public init(merged: [String: CalibrationMerge.ClassCalibration],
                betaPool: Float, lineage: Lineage?,
                runSummary: RunSummary? = nil) {
        var classes: [String: ClassEntry] = [:]
        for (name, c) in merged {
            classes[name] = ClassEntry(
                beta: c.beta,
                status: c.status.rawValue,
                provenance: c.provenance.rawValue,
                standardError: c.standardError,
                effectiveSample: c.effectiveSample,
                clamped: c.clamped)
        }
        self.betaPool = betaPool
        self.classes = classes
        self.lineage = lineage
        self.runSummary = runSummary
    }

    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
#endif
