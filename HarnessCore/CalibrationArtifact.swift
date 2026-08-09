#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import PortableContracts
import SupportPlane

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
    // Mirrors ingest.py's UNMAPPED_SIGNIFICANT_FRACTION (Req 4.1) — applied
    // at ingestion, recorded here for the lineage block (Req 5.5).
    public static let unmappedSignificantFraction: Float = 0.10

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
        // Mixture plates whose unmapped mass exceeded the ingestion threshold
        // (Req 4.1): their hull volume contains unmapped food, so admitting
        // them would bias co-occurring mapped β downward.
        public let unmappedExcluded: [PbMealFixture]
    }

    // An ingestion run summary (tools/nutrition5k/ingest.py, and
    // tools/metafood3d/ingest.py once cross-dataset-calibration stream 1
    // lands). Fixtures carry mapped masses only, so the >10%-unmapped-mass
    // mixture-fit exclusion (design §Unmapped-volume bias) can only come from
    // this file — the harness consumes it rather than re-deriving it.
    //
    // Multi-dataset keys (all optional, absent on pre-feature N5k summaries):
    //   dataset          — e.g. "metafood3d"; "" reads as nutrition5k.
    //   snapshot         — dataset snapshot identifier (Req 9.1).
    //   mapping_version  — the dataset's mapping-artifact version.
    //   render_config    — the pinned MetaFood3D render camera configuration;
    //                      `plane_depth_mm` is what the injected-plane branch
    //                      (Decision 13) authors the SupportPlane from.
    public struct IngestSummary: Sendable {
        public let dataset: String
        public let snapshot: String
        public let mappingVersion: String
        public let unmappedExcluded: Set<String>
        public let liquidExcluded: Set<String>
        public let ingestionSkipCount: Int
        public let renderPlaneDepthMm: Float?
        public let renderIntrinsicsModel: String?
        public let renderImageWidth: Int?
        public let renderImageHeight: Int?
        public let renderSeatingRule: String?
    }

    public static func loadIngestSummary(from url: URL) throws -> IngestSummary {
        struct RenderDoc: Decodable {
            let planeDepthMm: Float
            let intrinsicsModel: String?
            let imageWidth: Int?
            let imageHeight: Int?
            let seatingRule: String?
            enum CodingKeys: String, CodingKey {
                case planeDepthMm = "plane_depth_mm"
                case intrinsicsModel = "intrinsics_model"
                case imageWidth = "image_width"
                case imageHeight = "image_height"
                case seatingRule = "seating_rule"
            }
        }
        struct Doc: Decodable {
            let dataset: String?
            let snapshot: String?
            let mappingVersion: String?
            let skipped: [String: [String]]?
            let mixtureFitExcludedUnmapped: [String]?
            let liquidExcluded: [String]?
            let renderConfig: RenderDoc?
            enum CodingKeys: String, CodingKey {
                case dataset, snapshot, skipped
                case mappingVersion = "mapping_version"
                case mixtureFitExcludedUnmapped = "mixture_fit_excluded_unmapped"
                case liquidExcluded = "liquid_excluded"
                case renderConfig = "render_config"
            }
        }
        let doc = try JSONDecoder().decode(Doc.self, from: Data(contentsOf: url))
        return IngestSummary(
            dataset: doc.dataset ?? "",
            snapshot: doc.snapshot ?? "",
            mappingVersion: doc.mappingVersion ?? "",
            unmappedExcluded: Set(doc.mixtureFitExcludedUnmapped ?? []),
            liquidExcluded: Set(doc.liquidExcluded ?? []),
            ingestionSkipCount: (doc.skipped ?? [:]).values.reduce(0) { $0 + $1.count },
            renderPlaneDepthMm: doc.renderConfig?.planeDepthMm,
            renderIntrinsicsModel: doc.renderConfig?.intrinsicsModel,
            renderImageWidth: doc.renderConfig?.imageWidth,
            renderImageHeight: doc.renderConfig?.imageHeight,
            renderSeatingRule: doc.renderConfig?.seatingRule)
    }

    // The dataset a fixture belongs to: the `source_dataset` stamp before the
    // "@" (e.g. "nutrition5k@<release>/<metaver>" → "nutrition5k"). Legacy
    // fixtures carry no stamp and read "".
    public static func dataset(of fixture: PbMealFixture) -> String {
        fixture.sourceDataset.split(separator: "@").first.map(String.init) ?? ""
    }

    // Depth-test-split exclusion FIRST — before any selection (Req 4.4) —
    // then routing per the authoritative estimator_path stamp (Req 3.7).
    // Legacy fixtures (empty estimator_path) ride the single-dominant path,
    // which is the pre-N5k behaviour.
    public static func route(
        fixtures: [PbMealFixture],
        depthTestSplit: Set<String>,
        unmappedExcluded unmappedIDs: Set<String> = []
    ) -> Routed {
        var mixture: [PbMealFixture] = []
        var singleDominant: [PbMealFixture] = []
        var excluded: [PbMealFixture] = []
        var unmapped: [PbMealFixture] = []
        for fx in fixtures {
            if depthTestSplit.contains(fx.fixtureID) {
                excluded.append(fx)
                continue
            }
            if fx.estimatorPath == "mixture" {
                if unmappedIDs.contains(fx.fixtureID) {
                    unmapped.append(fx)
                } else {
                    mixture.append(fx)
                }
            } else {
                singleDominant.append(fx)
            }
        }
        return Routed(mixture: mixture, singleDominant: singleDominant,
                      depthTestExcluded: excluded, unmappedExcluded: unmapped)
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

    // The support-plane reference β_c is fitted and applied under. Every attempt
    // the device produces on the LiDAR path records `.foodSupport` or falls back,
    // so this is the reference a baked β will meet at inference.
    public static let fittedSupportPlaneReference: SupportPlaneReference = .foodSupport

    public struct ReferenceGated {
        public let admitted: [MealCalibrationInput]
        public let excluded: [String]
    }

    // Req 5.4: where the corpus spans more than one reference, β_c is fitted on
    // the subset sharing the reference it will be applied under. An attempt
    // recording NO reference is excluded rather than admitted — it derived no
    // depth plane (two-view) or predates this feature, and in both cases its
    // volumes rest on a different geometric basis. Absent blocks; it does not
    // permit (Req 5.3).
    public static func applyReferenceGate(
        _ inputs: [MealCalibrationInput],
        reference: SupportPlaneReference = fittedSupportPlaneReference
    ) -> ReferenceGated {
        var admitted: [MealCalibrationInput] = []
        var excluded: [String] = []
        for input in inputs {
            if input.supportPlaneReference == reference {
                admitted.append(input)
            } else {
                excluded.append(input.fixtureID)
            }
        }
        return ReferenceGated(admitted: admitted, excluded: excluded)
    }

    // Build a mixture PlateObservation from a fixture: plate-region plane fit
    // (Req 3.6) + depth-threshold total hull volume. Throws on a poor plate
    // plane so the CLI can skip and record the plate (Req 3.4/3.8).
    //
    // MetaFood3D branch (cross-dataset-calibration Decision 13): the render
    // authors its support plane exactly, and a nadir render of a steep-sided
    // food presents a > 5 mm edge cliff the centre-seeded flood fill cannot
    // cross — RANSAC would fit the FOOD surface, a silent shape-dependent
    // volume error. Passing `injectedSupportPlane` bypasses the plate-region
    // refit entirely and integrates against the authored plane. N5k fixtures
    // pass nil and keep the existing refit path.
    public static func mixtureObservation(
        fixture: PbMealFixture,
        injectedSupportPlane: SupportPlane? = nil
    ) throws -> MixtureBetaCalibrator.PlateObservation {
        let intrinsics = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let depth = DepthMap(pb: fixture.nadirDepth)
        let plane: SupportPlane
        if let injected = injectedSupportPlane {
            plane = injected
        } else {
            plane = try FixtureRunner.fitPlateRegionPlane(
                depth: depth, intrinsics: intrinsics,
                gravity: Vec3(pb: fixture.gravity),
                fixtureID: fixture.fixtureID)
        }
        let hull = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: intrinsics, supportPlane: plane))
        return MixtureBetaCalibrator.PlateObservation(
            fixtureID: fixture.fixtureID,
            totalHullVolumeCm3: hull,
            massByClassG: fixture.groundTruthClassMassG)
    }

    // The authored MetaFood3D support plane from the render configuration:
    // gravity-aligned normal (n̂·gravity > 0, matching the LiDARPlaneFitter
    // orientation convention) at the pinned plane depth. Residual 0 — the
    // plane is exact by construction, not fitted (Decision 13).
    public static func authoredSupportPlane(
        gravity: Vec3, planeDepthMm: Float
    ) -> SupportPlane {
        SupportPlane(normal: gravity.normalised(), distanceMm: planeDepthMm,
                     residualMm: 0, convergedIterations: nil)
    }

    // Build an eval plate from a mixture observation. GT macros come from the
    // fixture's per-class N5k maps (Req 6.2/6.6) — the estimate uses the DB
    // composition, so an independent GT basis is what lets the Req 6.7
    // cross-macro check see mapping/composition-source errors. Fixtures
    // predating the per-class maps (all three empty) fall back to GT mass ×
    // DB fraction; that fallback is circular across macros and cannot raise
    // the 6.7 flag, which is exactly why the maps exist.
    public static func evalPlate(
        obs: MixtureBetaCalibrator.PlateObservation,
        fixture: PbMealFixture,
        composition: ClassComposition,
        official: Bool
    ) -> N5kEvalPlate {
        var carbs = fixture.groundTruthClassCarbsG
        var protein = fixture.groundTruthClassProteinG
        var fat = fixture.groundTruthClassFatG
        if carbs.isEmpty, protein.isEmpty, fat.isEmpty {
            for (c, m) in obs.massByClassG {
                carbs[c] = m * composition.carbFractionPer100g[c, default: 0] / 100
                protein[c] = m * composition.proteinFractionPer100g[c, default: 0] / 100
                fat[c] = m * composition.fatFractionPer100g[c, default: 0] / 100
            }
        }
        return N5kEvalPlate(
            fixtureID: obs.fixtureID,
            estimatorPath: fixture.estimatorPath == "single_dominant"
                ? .singleDominant : .mixture,
            totalHullVolumeCm3: obs.totalHullVolumeCm3,
            massByClassG: obs.massByClassG,
            gtCarbsByClassG: carbs,
            gtProteinByClassG: protein,
            gtFatByClassG: fat,
            wholeDishCarbsG: fixture.groundTruthTotalCarbsG,
            inOfficialTestSplit: official)
    }
}

// The calibrate JSON artifact. `betaPool` and `classes` predate this spec
// (existing consumers of the CalibrationJSON shape); the per-class
// provenance/SE fields, the lineage block (Req 5.5), and the run summary
// extend the same writer rather than adding a parallel output path.
public struct CalibrationArtifact: Codable {
    public struct ClassEntry: Codable {
        public let beta: Float
        public let status: String
        public let provenance: String
        public let standardError: Float?
        public let effectiveSample: Int
        public let clamped: Bool
        // Which support-plane reference THIS β was fitted under (Req 5.4). Per
        // class rather than per artifact because the corpus spans two references
        // permanently, not just in transition: the mixture path keeps the flood
        // fill (Decision 17), so a single artifact carries `plateRegion` and
        // `foodSupport` β side by side and nothing may mix them.
        public let supportPlaneReference: String
        // Cross-dataset provenance (cross-dataset-calibration Req 4.3, 6.2):
        // dataset → weighted sample contribution feeding this β, and the
        // corroboration flag — true unless ≥ 2 datasets each yielded an
        // independently identifiable standalone β AND those TOST-agree.
        public let contributingDatasets: [String: Int]
        public let singleSourceUncorroborated: Bool

        enum CodingKeys: String, CodingKey {
            case beta, status, provenance, clamped
            case standardError = "standard_error"
            case effectiveSample = "effective_sample"
            case supportPlaneReference = "support_plane_reference"
            case contributingDatasets = "contributing_datasets"
            case singleSourceUncorroborated = "single_source_uncorroborated"
        }

        init(beta: Float, status: String, provenance: String,
             standardError: Float?, effectiveSample: Int, clamped: Bool,
             supportPlaneReference: String,
             contributingDatasets: [String: Int] = [:],
             singleSourceUncorroborated: Bool = false) {
            self.beta = beta
            self.status = status
            self.provenance = provenance
            self.standardError = standardError
            self.effectiveSample = effectiveSample
            self.clamped = clamped
            self.supportPlaneReference = supportPlaneReference
            self.contributingDatasets = contributingDatasets
            self.singleSourceUncorroborated = singleSourceUncorroborated
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
            try c.encode(supportPlaneReference, forKey: .supportPlaneReference)
            try c.encode(contributingDatasets, forKey: .contributingDatasets)
            try c.encode(singleSourceUncorroborated, forKey: .singleSourceUncorroborated)
        }

        // Pre-cross-dataset artifacts lack the two provenance keys; absent
        // decodes to the additive defaults (no recorded contributors, flag
        // false) so older artifacts round-trip unchanged.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            beta = try c.decode(Float.self, forKey: .beta)
            status = try c.decode(String.self, forKey: .status)
            provenance = try c.decode(String.self, forKey: .provenance)
            standardError = try c.decodeIfPresent(Float.self, forKey: .standardError)
            effectiveSample = try c.decode(Int.self, forKey: .effectiveSample)
            clamped = try c.decode(Bool.self, forKey: .clamped)
            supportPlaneReference = try c.decode(String.self, forKey: .supportPlaneReference)
            contributingDatasets = try c.decodeIfPresent(
                [String: Int].self, forKey: .contributingDatasets) ?? [:]
            singleSourceUncorroborated = try c.decodeIfPresent(
                Bool.self, forKey: .singleSourceUncorroborated) ?? false
        }
    }

    // The pinned MetaFood3D render configuration (Req 2.4, 9.1): recorded in
    // lineage so β is reproducible from lineage alone. `noiseFreeRenderNote`
    // is the Req 2.5 statement that β is fit on noise-free rendered depth and
    // corrects geometric bias only.
    public struct RenderConfig: Codable, Equatable, Sendable {
        public static let defaultNoiseFreeRenderNote =
            "beta fit on noise-free rendered depth; corrects geometric bias "
            + "only, not sensor-noise-induced bias (Decision 8)"

        public let intrinsicsModel: String
        public let planeDepthMm: Float
        public let imageWidth: Int
        public let imageHeight: Int
        public let seatingRule: String
        public let skewDelta: Float
        public let skewAlpha: Float
        public let noiseFreeRenderNote: String

        enum CodingKeys: String, CodingKey {
            case intrinsicsModel = "intrinsics_model"
            case planeDepthMm = "plane_depth_mm"
            case imageWidth = "image_width"
            case imageHeight = "image_height"
            case seatingRule = "seating_rule"
            case skewDelta = "skew_delta"
            case skewAlpha = "skew_alpha"
            case noiseFreeRenderNote = "noise_free_render_note"
        }

        public init(intrinsicsModel: String, planeDepthMm: Float,
                    imageWidth: Int, imageHeight: Int, seatingRule: String,
                    skewDelta: Float = Float(CrossDatasetSkew.defaultDelta),
                    skewAlpha: Float = Float(CrossDatasetSkew.defaultAlpha),
                    noiseFreeRenderNote: String = defaultNoiseFreeRenderNote) {
            self.intrinsicsModel = intrinsicsModel
            self.planeDepthMm = planeDepthMm
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
            self.seatingRule = seatingRule
            self.skewDelta = skewDelta
            self.skewAlpha = skewAlpha
            self.noiseFreeRenderNote = noiseFreeRenderNote
        }
    }

    // Per-contributing-dataset lineage (Req 6.1, 9.1): snapshot identifier and
    // mapping-artifact version, keyed by dataset name.
    public struct DatasetLineage: Codable, Equatable, Sendable {
        public let snapshot: String
        public let mappingArtifactVersion: String

        enum CodingKeys: String, CodingKey {
            case snapshot
            case mappingArtifactVersion = "mapping_artifact_version"
        }

        public init(snapshot: String, mappingArtifactVersion: String) {
            self.snapshot = snapshot
            self.mappingArtifactVersion = mappingArtifactVersion
        }
    }

    public struct Lineage: Codable {
        public let n5kRelease: String              // SHA-256 manifest id (Req 1.4)
        public let n5kMetadataVersion: String
        public let mappingArtifactVersion: String
        public let tauRoute: Float
        public let tauPurity: Float
        public let tauEff: Float
        public let kappaStacking: Float
        // Remaining provisional gate values (design §Provisional gate
        // values), recorded so a bake is reproducible from its lineage alone.
        public let liquidSignificantFraction: Float
        public let unmappedSignificantFraction: Float
        public let relativeSEBound: Float
        public let effectiveSampleMin: Int
        public let seed: UInt64
        public let effectiveSamplePerClass: [String: Int]
        public let conditionNumber: Float
        public let identifiablePerClass: [String: Bool]
        public let pinnedIntrinsicsModel: String   // nominal camera model (Req 3.3)
        public let licence: String                 // "CC BY 4.0" (Req 1.5)
        // cross-dataset-calibration Req 9.1: the MetaFood3D render camera
        // configuration (nil on an N5k-only run — no render happened) and the
        // per-contributing-dataset snapshot + mapping-artifact version.
        public let renderConfig: RenderConfig?
        public let perDataset: [String: DatasetLineage]

        enum CodingKeys: String, CodingKey {
            case n5kRelease = "n5k_release"
            case n5kMetadataVersion = "n5k_metadata_version"
            case mappingArtifactVersion = "mapping_artifact_version"
            case tauRoute = "tau_route"
            case tauPurity = "tau_purity"
            case tauEff = "tau_eff"
            case kappaStacking = "kappa_stacking"
            case liquidSignificantFraction = "liquid_significant_fraction"
            case unmappedSignificantFraction = "unmapped_significant_fraction"
            case relativeSEBound = "relative_se_bound"
            case effectiveSampleMin = "effective_sample_min"
            case seed
            case effectiveSamplePerClass = "effective_sample_per_class"
            case conditionNumber = "condition_number"
            case identifiablePerClass = "identifiable_per_class"
            case pinnedIntrinsicsModel = "pinned_intrinsics_model"
            case licence
            case renderConfig = "render_config"
            case perDataset = "per_dataset"
        }

        // Pre-cross-dataset artifacts lack the two new keys; absent decodes to
        // the additive defaults so older artifacts round-trip unchanged.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            n5kRelease = try c.decode(String.self, forKey: .n5kRelease)
            n5kMetadataVersion = try c.decode(String.self, forKey: .n5kMetadataVersion)
            mappingArtifactVersion = try c.decode(String.self, forKey: .mappingArtifactVersion)
            tauRoute = try c.decode(Float.self, forKey: .tauRoute)
            tauPurity = try c.decode(Float.self, forKey: .tauPurity)
            tauEff = try c.decode(Float.self, forKey: .tauEff)
            kappaStacking = try c.decode(Float.self, forKey: .kappaStacking)
            liquidSignificantFraction = try c.decode(
                Float.self, forKey: .liquidSignificantFraction)
            unmappedSignificantFraction = try c.decode(
                Float.self, forKey: .unmappedSignificantFraction)
            relativeSEBound = try c.decode(Float.self, forKey: .relativeSEBound)
            effectiveSampleMin = try c.decode(Int.self, forKey: .effectiveSampleMin)
            seed = try c.decode(UInt64.self, forKey: .seed)
            effectiveSamplePerClass = try c.decode(
                [String: Int].self, forKey: .effectiveSamplePerClass)
            conditionNumber = try c.decode(Float.self, forKey: .conditionNumber)
            identifiablePerClass = try c.decode(
                [String: Bool].self, forKey: .identifiablePerClass)
            pinnedIntrinsicsModel = try c.decode(String.self, forKey: .pinnedIntrinsicsModel)
            licence = try c.decode(String.self, forKey: .licence)
            renderConfig = try c.decodeIfPresent(RenderConfig.self, forKey: .renderConfig)
            perDataset = try c.decodeIfPresent(
                [String: DatasetLineage].self, forKey: .perDataset) ?? [:]
        }

        public init(n5kRelease: String, n5kMetadataVersion: String,
                    mappingArtifactVersion: String, tauRoute: Float,
                    tauPurity: Float, tauEff: Float, kappaStacking: Float,
                    liquidSignificantFraction: Float =
                        MixtureBetaCalibrator.liquidSignificantFraction,
                    unmappedSignificantFraction: Float =
                        CalibrateRun.unmappedSignificantFraction,
                    relativeSEBound: Float = CalibrationMerge.relativeSEBound,
                    effectiveSampleMin: Int = CalibrationMerge.effectiveSampleMin,
                    seed: UInt64, effectiveSamplePerClass: [String: Int],
                    conditionNumber: Float, identifiablePerClass: [String: Bool],
                    pinnedIntrinsicsModel: String, licence: String,
                    renderConfig: RenderConfig? = nil,
                    perDataset: [String: DatasetLineage] = [:]) {
            self.n5kRelease = n5kRelease
            self.n5kMetadataVersion = n5kMetadataVersion
            self.mappingArtifactVersion = mappingArtifactVersion
            self.tauRoute = tauRoute
            self.tauPurity = tauPurity
            self.tauEff = tauEff
            self.kappaStacking = kappaStacking
            self.liquidSignificantFraction = liquidSignificantFraction
            self.unmappedSignificantFraction = unmappedSignificantFraction
            self.relativeSEBound = relativeSEBound
            self.effectiveSampleMin = effectiveSampleMin
            self.seed = seed
            self.effectiveSamplePerClass = effectiveSamplePerClass
            self.conditionNumber = conditionNumber
            self.identifiablePerClass = identifiablePerClass
            self.pinnedIntrinsicsModel = pinnedIntrinsicsModel
            self.licence = licence
            self.renderConfig = renderConfig
            self.perDataset = perDataset
        }
    }

    // Skip/drop accounting for the run summary (Req 3.4/3.8/4.1/4.2/4.3/4.7).
    public struct RunSummary: Codable {
        public let depthTestSplitExcluded: [String]
        public let unmappedExcluded: [String]
        public let purityDropped: [String]
        public let planeFitSkipped: [String]
        public let stackingExcluded: [String]
        public let liquidExcluded: [String]
        // Plates whose support plane referenced a different surface from the one
        // the fitted β will be applied under (Req 5.4). Recorded rather than
        // merely dropped: a run where most plates land here is measuring the
        // fallback rate, not calibrating.
        public let supportPlaneReferenceExcluded: [String]
        // Per-dataset exclusion buckets (cross-dataset-calibration Req 1.4,
        // design §Data Models): counts keyed by dataset so N5k depth-test-split
        // drops and MetaFood3D scale/unmapped drops stay attributable in a
        // multi-dataset run.
        public let depthTestSplitExcludedByDataset: [String: Int]
        public let unmappedExcludedByDataset: [String: Int]
        public let ingestionSkippedByDataset: [String: Int]

        enum CodingKeys: String, CodingKey {
            case depthTestSplitExcluded = "depth_test_split_excluded"
            case unmappedExcluded = "unmapped_excluded"
            case purityDropped = "purity_dropped"
            case planeFitSkipped = "plane_fit_skipped"
            case stackingExcluded = "stacking_excluded"
            case liquidExcluded = "liquid_excluded"
            case supportPlaneReferenceExcluded = "support_plane_reference_excluded"
            case depthTestSplitExcludedByDataset = "depth_test_split_excluded_by_dataset"
            case unmappedExcludedByDataset = "unmapped_excluded_by_dataset"
            case ingestionSkippedByDataset = "ingestion_skipped_by_dataset"
        }

        public init(depthTestSplitExcluded: [String], unmappedExcluded: [String] = [],
                    purityDropped: [String],
                    planeFitSkipped: [String], stackingExcluded: [String],
                    liquidExcluded: [String],
                    supportPlaneReferenceExcluded: [String] = [],
                    depthTestSplitExcludedByDataset: [String: Int] = [:],
                    unmappedExcludedByDataset: [String: Int] = [:],
                    ingestionSkippedByDataset: [String: Int] = [:]) {
            self.depthTestSplitExcluded = depthTestSplitExcluded
            self.unmappedExcluded = unmappedExcluded
            self.purityDropped = purityDropped
            self.planeFitSkipped = planeFitSkipped
            self.stackingExcluded = stackingExcluded
            self.liquidExcluded = liquidExcluded
            self.supportPlaneReferenceExcluded = supportPlaneReferenceExcluded
            self.depthTestSplitExcludedByDataset = depthTestSplitExcludedByDataset
            self.unmappedExcludedByDataset = unmappedExcludedByDataset
            self.ingestionSkippedByDataset = ingestionSkippedByDataset
        }

        // Pre-cross-dataset artifacts lack the by-dataset buckets; absent
        // decodes to empty so older artifacts round-trip unchanged.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            depthTestSplitExcluded = try c.decode(
                [String].self, forKey: .depthTestSplitExcluded)
            unmappedExcluded = try c.decodeIfPresent(
                [String].self, forKey: .unmappedExcluded) ?? []
            purityDropped = try c.decode([String].self, forKey: .purityDropped)
            planeFitSkipped = try c.decode([String].self, forKey: .planeFitSkipped)
            stackingExcluded = try c.decode([String].self, forKey: .stackingExcluded)
            liquidExcluded = try c.decode([String].self, forKey: .liquidExcluded)
            supportPlaneReferenceExcluded = try c.decodeIfPresent(
                [String].self, forKey: .supportPlaneReferenceExcluded) ?? []
            depthTestSplitExcludedByDataset = try c.decodeIfPresent(
                [String: Int].self, forKey: .depthTestSplitExcludedByDataset) ?? [:]
            unmappedExcludedByDataset = try c.decodeIfPresent(
                [String: Int].self, forKey: .unmappedExcludedByDataset) ?? [:]
            ingestionSkippedByDataset = try c.decodeIfPresent(
                [String: Int].self, forKey: .ingestionSkippedByDataset) ?? [:]
        }
    }

    public let betaPool: Float
    public let classes: [String: ClassEntry]
    public let lineage: Lineage?
    public let runSummary: RunSummary?
    // The reference `betaPool` was fitted under, and the one that gates
    // application (Req 5.3). The bake refuses an artifact that records none:
    // every artifact produced before this feature records none, and those are
    // precisely the ones calibrated on the old basis, so absent must BLOCK
    // rather than permit.
    public let supportPlaneReference: String?

    enum CodingKeys: String, CodingKey {
        case betaPool, classes, lineage
        case runSummary = "run_summary"
        case supportPlaneReference = "support_plane_reference"
    }

    // Mixture β are fitted on the flood-filled plate region, single-dominant β on
    // the food-support plane (Decision 17). Pooled/unity classes carry no fit of
    // their own, so they ride the pool's reference — which is what `betaPool` is
    // fitted under, and what a consumer applying them would be applying.
    static func reference(for provenance: BetaProvenance,
                          singleDominant: SupportPlaneReference?) -> String {
        switch provenance {
        case .n5kMixture: return SupportPlaneReference.plateRegion.rawValue
        case .n5kSingleDominant, .gravimetric, .none:
            return singleDominant?.rawValue ?? ""
        }
    }

    public init(merged: [String: CalibrationMerge.ClassCalibration],
                betaPool: Float,
                supportPlaneReference: SupportPlaneReference?,
                lineage: Lineage?,
                runSummary: RunSummary? = nil) {
        var classes: [String: ClassEntry] = [:]
        for (name, c) in merged {
            classes[name] = ClassEntry(
                beta: c.beta,
                status: c.status.rawValue,
                provenance: c.provenance.rawValue,
                standardError: c.standardError,
                effectiveSample: c.effectiveSample,
                clamped: c.clamped,
                supportPlaneReference: Self.reference(
                    for: c.provenance, singleDominant: supportPlaneReference),
                contributingDatasets: c.contributingDatasets,
                singleSourceUncorroborated: c.singleSourceUncorroborated)
        }
        self.betaPool = betaPool
        self.classes = classes
        self.lineage = lineage
        self.runSummary = runSummary
        self.supportPlaneReference = supportPlaneReference?.rawValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        betaPool = try c.decode(Float.self, forKey: .betaPool)
        classes = try c.decode([String: ClassEntry].self, forKey: .classes)
        lineage = try c.decodeIfPresent(Lineage.self, forKey: .lineage)
        runSummary = try c.decodeIfPresent(RunSummary.self, forKey: .runSummary)
        supportPlaneReference = try c.decodeIfPresent(
            String.self, forKey: .supportPlaneReference)
    }

    // Encode a null support_plane_reference explicitly. The bake distinguishes
    // "recorded no reference" from "carries an unexpected shape", and a key that
    // is sometimes missing collapses those two into one.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(betaPool, forKey: .betaPool)
        try c.encode(classes, forKey: .classes)
        try c.encode(lineage, forKey: .lineage)
        try c.encode(runSummary, forKey: .runSummary)
        try c.encode(supportPlaneReference, forKey: .supportPlaneReference)
    }

    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
#endif
