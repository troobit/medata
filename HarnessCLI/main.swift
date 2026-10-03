// HarnessCLI — offline test-set runner per design §7.3.
// Subcommands: accuracy, calibrate, seg-bench, calibrate-and-eval, diagnose,
// volumes, cards.
// Usage: HarnessCLI <subcommand> [flags]
//
// Feature-flagged off in v1 per Decision 41. The entire file is gated on
// HARNESS_ENABLED, defined only on the HarnessCLI SPM target. The shipping
// iOS app never includes this binary.
#if HARNESS_ENABLED
import CaptureKit
import CardDetection
import CardDetectionVision
import Foods
import Foundation
import HarnessCore
import Macros
import PortableContracts
import Segmentation
import SupportPlane
import SwiftProtobuf
import Volume

// MARK: - Argument Parsing

struct Args {
    let subcommand: String
    var fixturesDir: String = ""
    // Positional `.fixture` paths (`cards`): one bundle at a time, no directory.
    var fixturePaths: [String] = []
    // `cards`: how many ranked rectangles Vision may return per frame. 1 is
    // what the device runs; more lists the candidates the single pick hides.
    var maxObservations: Int = 8
    // `cards --oblique` replays the detector on the oblique frame instead.
    var oblique: Bool = false
    // `carve-audit`: the synthetic control box, "LxWxH" in mm (grid axes).
    var boxMm: SIMD3<Float> = SIMD3(120, 70, 40)
    // `carve-audit --no-depth`: also size the carve as a phone without LiDAR
    // would (two-view-trust Decision 11).
    var noDepth: Bool = false
    // `carve-audit --tilts 22.2,26,40,60`: synthetic box under an orbited
    // oblique at each tilt; `--caps 120,85.9,45`: grid extents for the box.
    var syntheticTiltsDeg: [Float] = []
    var syntheticCapsMm: [Float]?
    var checkpointSHA256: String = ""
    var outputPath: String = ""
    var voxelEdgeMm: Float = 3.0
    // nutrition5k-calibration (Req 4.4/5.5)
    var depthTestSplitPath: String = ""
    var seed: UInt64 = 42
    var mappingVersion: String = ""
    var intrinsicsModel: String = "realsense_d435_factory"
    // Ingestion run_summary.json files (Req 4.1): carry the unmapped-mass
    // mixture exclusions the harness cannot derive from fixtures, plus skip
    // counts. Repeatable — one per dataset (cross-dataset-calibration
    // Req 10.1): the MetaFood3D summary additionally carries the render
    // configuration the injected-plane branch needs.
    var ingestSummaryPaths: [String] = []
    // Fraction of MetaFood3D objects held out of the fit for the Req 10.2
    // accuracy anchor. 0 = no holdout (the anchor is then not measured).
    var heldoutFrac: Float = 0
    // The ingestion truth sidecar metafood3d_truth.json ({fixture_id:
    // mesh_volume_mm3}) for the Req 2.3 volume-fit diagnostic: β_geom =
    // V_mesh_true / V_est per class, reported next to the mass-fit β with a
    // divergence flag. Reported, never baked.
    var meshTruthPath: String = ""
    // ml-feedback-loop Req 4.3: the checkpoint the REPLAYING binary holds, as
    // distinct from `--checkpoint-sha256`, which is the loader's guard and must
    // equal what the capture recorded for the fixture to load at all. When the
    // two differ the diagnosis is stamped `replay_version_skew` and the Mac
    // side drops that pair from the attribution floor. Defaults to
    // `--checkpoint-sha256`, i.e. no skew claimed.
    var replayCheckpointSHA256: String = ""
    // unknown-food-nameable task 3: sweep the Req 10 sliver-absorption fraction
    // without a rebuild. Applies to every subcommand that replays a fixture
    // through the segmenter's label map — seg-bench, accuracy, calibrate,
    // diagnose — all of which otherwise regularise with
    // `MaskRegularisationConfig.standard`, the config the app ships. The speckle
    // strength is not swept; only the sliver rule is under measurement.
    var sliverFraction: Double?
    // depth-grown-food-region task 4: sweep the growth constants without a
    // rebuild. `--growth-cap 0` disables the pass and reproduces the ungrown
    // single-view number. Only `accuracy` (and calibrate, through the same
    // replay) reads them; seg-bench scores the label map before growth.
    var growthCliffMm: Float?
    var growthFloorMm: Float?
    var growthCap: Float?
    var growthBandMm: Float?
    // depth-grown-food-region Decision 5: the seed-area gate, cm² on the
    // first plane (0 = no gate). Applies to the single-view replay only.
    var growthGateCm2: Float?
    // two-view-trust Req 3.14 / Decision 7: a hand-placed growth seed for
    // `volumes`, in NADIR COLOUR-GRID pixels (top-left origin, the 1920 x 1440
    // buffer the intrinsics declare — not view coordinates). Only the
    // 4-connected food-like component containing this point seeds the fill;
    // every other food-like component is cleared. Both must be given.
    var seedX: Int?
    var seedY: Int?
}

// The growth the harness applies on the single-view replay: `.standard` (what
// the device runs) with any of the five constants substituted when given.
func growthConfig(args: Args) -> FoodRegionGrowthConfig {
    let standard = FoodRegionGrowthConfig.standard
    return FoodRegionGrowthConfig(
        cliffMm: args.growthCliffMm ?? standard.cliffMm,
        floorMm: args.growthFloorMm ?? standard.floorMm,
        frameFractionCap: args.growthCap ?? standard.frameFractionCap,
        seedBandMm: args.growthBandMm ?? standard.seedBandMm,
        seedAreaGateCm2: args.growthGateCm2 ?? standard.seedAreaGateCm2)
}

// The regularisation the harness applies to a replayed argmax: `.standard`
// (what the device runs) with `--sliver-fraction` substituted when given.
func regularisationConfig(args: Args) -> MaskRegularisationConfig {
    let standard = MaskRegularisationConfig.standard
    guard let fraction = args.sliverFraction else { return standard }
    return MaskRegularisationConfig(
        minRegionArea: standard.minRegionArea, sliverFraction: fraction)
}

func parseArgs() -> Args? {
    var args = CommandLine.arguments.dropFirst()
    guard let subcommand = args.first else {
        fputs("Usage: HarnessCLI <accuracy|calibrate|seg-bench|calibrate-and-eval|diagnose|volumes|cards|carve-audit> [flags]\n", stderr)
        return nil
    }
    args = args.dropFirst()
    var result = Args(subcommand: subcommand)
    var it = args.makeIterator()
    while let flag = it.next() {
        switch flag {
        case "--fixtures-dir":      result.fixturesDir      = it.next() ?? ""
        case "--checkpoint-sha256": result.checkpointSHA256 = it.next() ?? ""
        case "--output":            result.outputPath        = it.next() ?? ""
        case "--edge":
            if let s = it.next(), let f = Float(s) { result.voxelEdgeMm = f }
        case "--depth-test-split":  result.depthTestSplitPath = it.next() ?? ""
        case "--seed":
            if let s = it.next(), let v = UInt64(s) { result.seed = v }
        case "--mapping-version":   result.mappingVersion   = it.next() ?? ""
        case "--intrinsics-model":  result.intrinsicsModel  = it.next() ?? ""
        case "--ingest-summary":
            if let path = it.next() { result.ingestSummaryPaths.append(path) }
        case "--heldout-frac":
            if let s = it.next(), let f = Float(s) { result.heldoutFrac = f }
        case "--mesh-truth":        result.meshTruthPath    = it.next() ?? ""
        case "--replay-checkpoint-sha256":
            result.replayCheckpointSHA256 = it.next() ?? ""
        case "--sliver-fraction":
            if let s = it.next(), let f = Double(s) { result.sliverFraction = f }
        case "--growth-cliff-mm":
            if let s = it.next(), let f = Float(s) { result.growthCliffMm = f }
        case "--growth-floor-mm":
            if let s = it.next(), let f = Float(s) { result.growthFloorMm = f }
        case "--growth-cap":
            if let s = it.next(), let f = Float(s) { result.growthCap = f }
        case "--growth-band-mm":
            if let s = it.next(), let f = Float(s) { result.growthBandMm = f }
        case "--growth-gate-cm2":
            if let s = it.next(), let f = Float(s) { result.growthGateCm2 = f }
        case "--max-observations":
            if let s = it.next(), let n = Int(s), n > 0 { result.maxObservations = n }
        case "--oblique":
            result.oblique = true
        case "--box":
            if let s = it.next() {
                let parts = s.split(separator: "x").compactMap { Float($0) }
                if parts.count == 3 { result.boxMm = SIMD3(parts[0], parts[1], parts[2]) }
            }
        case "--no-depth":
            result.noDepth = true
        case "--tilts":
            if let s = it.next() { result.syntheticTiltsDeg = s.split(separator: ",").compactMap { Float($0) } }
        case "--caps":
            if let s = it.next() { result.syntheticCapsMm = s.split(separator: ",").compactMap { Float($0) } }
        case "--seed-x":
            if let s = it.next(), let v = Int(s) { result.seedX = v }
        case "--seed-y":
            if let s = it.next(), let v = Int(s) { result.seedY = v }
        default:
            if !flag.hasPrefix("--") { result.fixturePaths.append(flag) }
        }
    }
    return result
}

// MARK: - JSON report helpers

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(value)
    if path.isEmpty {
        print(String(data: data, encoding: .utf8) ?? "{}")
    } else {
        try data.write(to: URL(fileURLWithPath: path))
    }
}

struct AccuracyJSON: Encodable {
    let mape: Float; let mae: Float
    let ci95Lower: Float?; let ci95Upper: Float?
    let passesBar: Bool
    // Meals that carried usable ground truth versus those that did not. A device
    // capture bundle records truth as zero (back-filled off-device), so a field
    // replay is normally all-unscored — which is why `mape`/`mae` must be read
    // together with `scoredCount`.
    let scoredCount: Int; let unscoredCount: Int
    // Distinct segmenter checkpoints across the loaded fixtures. Normally one;
    // more than one means the run mixed models and the aggregate is not
    // attributable to any single checkpoint.
    let checkpointSHAs: [String]
    // Req 4.4: how often the restricted support-plane fit was rejected, segmented
    // by reference. `fallbackRate` is null when nothing was depth-derived.
    let supportPlaneFallback: FallbackJSON
    let perClass: [String: PerClassJSON]
    let rows: [RowJSON]
    struct FallbackJSON: Encodable {
        let countsByReference: [String: Int]
        let depthDerivedCount: Int
        let unreportedCount: Int
        let fallbackCount: Int
        let fallbackRate: Float?

        init(_ r: FallbackRateReport) {
            countsByReference = r.countsByReference
            depthDerivedCount = r.depthDerivedCount
            unreportedCount = r.unreportedCount
            fallbackCount = r.fallbackCount
            fallbackRate = r.fallbackRate
        }

        // Encode a null rate explicitly, so an absent rate reads as absent rather
        // than as a missing key a consumer would default to zero.
        enum CodingKeys: String, CodingKey {
            case countsByReference, depthDerivedCount, unreportedCount
            case fallbackCount, fallbackRate
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(countsByReference, forKey: .countsByReference)
            try c.encode(depthDerivedCount, forKey: .depthDerivedCount)
            try c.encode(unreportedCount, forKey: .unreportedCount)
            try c.encode(fallbackCount, forKey: .fallbackCount)
            try c.encode(fallbackRate, forKey: .fallbackRate)
        }
    }
    struct PerClassJSON: Encodable {
        let mape: Float; let mae: Float
        let sampleCount: Int; let calibrationStatus: String
    }
    struct RowJSON: Encodable {
        let fixtureID: String; let capturePath: String
        let groundTruthCarbsG: Float; let predictedCarbsG: Float
        // Null when the meal carries no truth — absent, not zero.
        let absoluteErrorG: Float?; let percentError: Float?
        let scored: Bool
        // What the scored figure was computed from (the `accuracy` path only;
        // absent on the legacy eval). Volumes and masses are the scored ones —
        // under the review's classes when a review applied.
        let perClassVolumesCm3: [String: Float]?
        let perClassMassG: [String: Float]?
        let groundTruthClassMassG: [String: Float]?
        let supportPlaneReference: String?
        let review: ReviewJSON?
    }
    // Present only on a fixture whose ingest summary carried a review: what
    // the review changed, and the meal as the segmenter labelled it.
    struct ReviewJSON: Encodable {
        let relabelled: [String: String]
        let rejected: [String]
        let labelledVolumesCm3: [String: Float]
        let labelledCarbsG: Float
    }
    struct DetailJSON {
        let perClassVolumesCm3: [String: Float]
        let perClassMassG: [String: Float]
        let groundTruthClassMassG: [String: Float]
        let supportPlaneReference: String?
        let review: ReviewJSON?
    }
}

// Writes the accuracy artifact and applies the exit policy, shared by the
// `accuracy` and legacy-eval paths so the two cannot drift apart.
func emitAccuracy(_ report: AccuracyReport,
                  checkpointSHAs: [String] = [],
                  details: [String: AccuracyJSON.DetailJSON] = [:],
                  to outputPath: String) throws {
    try writeJSON(AccuracyJSON(
        mape: report.mape, mae: report.mae,
        ci95Lower: report.ci95Lower, ci95Upper: report.ci95Upper,
        passesBar: report.passesBar,
        scoredCount: report.scoredCount, unscoredCount: report.unscoredCount,
        checkpointSHAs: checkpointSHAs,
        supportPlaneFallback: AccuracyJSON.FallbackJSON(report.fallback),
        perClass: report.perClassStats.mapValues { s in
            AccuracyJSON.PerClassJSON(mape: s.mape, mae: s.mae,
                                      sampleCount: s.sampleCount,
                                      calibrationStatus: s.calibrationStatus.rawValue)
        },
        rows: report.rows.map { r in
            let detail = details[r.fixtureID]
            return AccuracyJSON.RowJSON(
                fixtureID: r.fixtureID, capturePath: r.capturePath,
                groundTruthCarbsG: r.groundTruthCarbsG,
                predictedCarbsG: r.predictedCarbsG,
                absoluteErrorG: r.absoluteErrorG, percentError: r.percentError,
                scored: r.isScored,
                perClassVolumesCm3: detail?.perClassVolumesCm3,
                perClassMassG: detail?.perClassMassG,
                groundTruthClassMassG: detail?.groundTruthClassMassG,
                supportPlaneReference: detail?.supportPlaneReference,
                review: detail?.review)
        }
    ), to: outputPath)

    // Req 4.5: a fallback rate above the (task 26) threshold is a defect against
    // this feature, not a success — a change where every capture falls back
    // satisfies Reqs 4.1–4.3 while delivering nothing. Printed on every run so the
    // figure is read alongside the accuracy, not looked up afterwards.
    if let rate = report.fallback.fallbackRate {
        let byReference = report.fallback.countsByReference
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        fputs("support-plane fallback rate: \(rate * 100)% "
              + "(\(report.fallback.fallbackCount) of "
              + "\(report.fallback.depthDerivedCount) depth-derived attempts; "
              + "\(byReference))\n", stderr)
    } else {
        fputs("support-plane fallback rate: not measured — no attempt derived a "
              + "plane from depth\n", stderr)
    }

    if report.unscoredCount > 0 {
        fputs("WARNING: \(report.unscoredCount) of \(report.rows.count) meals carry no "
              + "ground truth and were excluded from MAPE/MAE. Device capture bundles "
              + "record truth as zero; back-fill it off-device before reading these "
              + "aggregates as accuracy.\n", stderr)
    }
    guard report.scoredCount > 0 else {
        fputs("FAIL: no meal carried ground truth — nothing was scored.\n", stderr)
        exit(1)
    }
    if !report.passesBar {
        fputs("FAIL: MAPE=\(report.mape)% MAE=\(report.mae)g over "
              + "\(report.scoredCount) scored meal(s)\n", stderr)
        exit(1)
    }
}

// The calibrate JSON artifact is HarnessCore.CalibrationArtifact — the
// extended CalibrationJSON shape (design §DB bake handoff contract).

// Compact snake_cased mirror of the N5k CalibrationReport for the
// calibrate-and-eval output.
struct N5kEvalJSON: Encodable {
    struct MacroJSON: Encodable {
        let mapeBaseline: Float; let mapeCalibrated: Float
        let maeBaseline: Float; let maeCalibrated: Float
        let samples: Int
        init(_ a: MacroAccuracy) {
            mapeBaseline = a.mapeBaseline; mapeCalibrated = a.mapeCalibrated
            maeBaseline = a.maeBaseline; maeCalibrated = a.maeCalibrated
            samples = a.sampleCount
        }
    }
    struct OfficialJSON: Encodable {
        let maeBaselineG: Float; let maeCalibratedG: Float
        let maeOverMeanBaseline: Float; let maeOverMeanCalibrated: Float
        let evaluatedDishCount: Int; let splitTotalCount: Int
        let mappedCarbCoverageFraction: Float; let caveat: String
    }
    struct PoolJSON: Encodable {
        let rgbdDishCount: Int; let depthTestSplitCount: Int
        let ingestionSkipCount: Int; let unmappedExcludedCount: Int
        let liquidExcludedCount: Int
        let stackingExcludedCount: Int; let qualifyingPlateCount: Int
        let effectiveSamplesByPath: [String: [String: Int]]
        let insufficientClasses: [String]
    }
    // Cross-dataset reporting block (cross-dataset-calibration Req 8.2/10).
    // Optional and omitted when nil, so an N5k-only run's output keeps its
    // pre-feature shape (Req 7.2).
    struct CrossDatasetJSON: Encodable {
        struct CoverageJSON: Encodable {
            let betaBefore: Float; let betaAfter: Float; let betaDelta: Float
            let effectiveSampleBefore: Int; let effectiveSampleAfter: Int
            let statusBefore: String; let statusAfter: String
            init(_ d: BetaCoverageDelta) {
                betaBefore = d.betaBefore; betaAfter = d.betaAfter
                betaDelta = d.betaDelta
                effectiveSampleBefore = d.effectiveSampleBefore
                effectiveSampleAfter = d.effectiveSampleAfter
                statusBefore = d.statusBefore; statusAfter = d.statusAfter
            }
        }
        struct ClassDeltaJSON: Encodable {
            let mapeBaseline: Float; let mapeCombined: Float
            let maeBaseline: Float; let maeCombined: Float
            let evalPlateCount: Int
            init(_ d: CarbDeltaReport.ClassDelta) {
                mapeBaseline = d.mapeBaseline; mapeCombined = d.mapeCombined
                maeBaseline = d.maeBaseline; maeCombined = d.maeCombined
                evalPlateCount = d.evalPlateCount
            }
        }
        struct AnchorJSON: Encodable {
            let massMapePercent: Float?
            let sampleCount: Int
            let perClassMape: [String: Float]
            let broccoliCrossCheckMape: Float?
            let unscoredCount: Int
            let reportedNotGating: Bool
            init(_ a: HeldOutAnchorReport) {
                massMapePercent = a.massMAPEPercent
                sampleCount = a.sampleCount
                perClassMape = a.perClassMAPE
                broccoliCrossCheckMape = a.broccoliCrossCheckMAPE
                unscoredCount = a.unscoredCount
                reportedNotGating = true
            }
        }
        let betaCoverageDelta: [String: CoverageJSON]
        let carbDeltaOverall: ClassDeltaJSON
        let carbDeltaPerClass: [String: ClassDeltaJSON]
        let carbDeltaSuppressedBelowMinCount: [String: Int]
        let unvalidatedStaples: [String]
        let minEvalPlateCount: Int
        let heldOutAnchor: AnchorJSON?
        // Req 2.3 volume-fit diagnostic (nil unless --mesh-truth was given):
        // β_geom per class beside the mass-fit β + divergence flag. Reported,
        // never baked.
        let volumeFitDiagnostic: CalibrationArtifact.VolumeFitDiagnosticBlock?
    }

    let seed: UInt64
    let folds: Int
    let mapeTargetPercent: Float
    let carbsOverall: MacroJSON
    let proteinOverall: MacroJSON
    let fatOverall: MacroJSON
    let carbsPerStaple: [String: MacroJSON]
    let staplesMeetingTarget: [String: Bool]
    let crossMacroFlags: [String]
    let dispersionPerClass: [String: Float]
    let officialSplit: OfficialJSON
    let pool: PoolJSON
    let crossDataset: CrossDatasetJSON?

    init(_ r: CalibrationReport, crossDataset: CrossDatasetJSON? = nil) {
        self.crossDataset = crossDataset
        seed = r.seed
        folds = r.foldCount
        mapeTargetPercent = r.mapeTargetPercent
        carbsOverall = MacroJSON(r.carbs.overall)
        proteinOverall = MacroJSON(r.protein.overall)
        fatOverall = MacroJSON(r.fat.overall)
        carbsPerStaple = r.carbs.perStaple.mapValues(MacroJSON.init)
        staplesMeetingTarget = r.staplesMeetingTarget
        crossMacroFlags = r.crossMacroFlags
        dispersionPerClass = r.dispersionPerClass.filter { $0.value.isFinite }
        officialSplit = OfficialJSON(
            maeBaselineG: r.officialSplit.maeBaselineG,
            maeCalibratedG: r.officialSplit.maeCalibratedG,
            maeOverMeanBaseline: r.officialSplit.maeOverMeanBaseline,
            maeOverMeanCalibrated: r.officialSplit.maeOverMeanCalibrated,
            evaluatedDishCount: r.officialSplit.evaluatedDishCount,
            splitTotalCount: r.officialSplit.splitTotalCount,
            mappedCarbCoverageFraction: r.officialSplit.mappedCarbCoverageFraction,
            caveat: r.officialSplit.caveat)
        pool = PoolJSON(
            rgbdDishCount: r.pool.rgbdDishCount,
            depthTestSplitCount: r.pool.depthTestSplitCount,
            ingestionSkipCount: r.pool.ingestionSkipCount,
            unmappedExcludedCount: r.pool.unmappedExcludedCount,
            liquidExcludedCount: r.pool.liquidExcludedCount,
            stackingExcludedCount: r.pool.stackingExcludedCount,
            qualifyingPlateCount: r.pool.qualifyingPlateCount,
            effectiveSamplesByPath: r.pool.effectiveSamplesByPath,
            insufficientClasses: r.pool.insufficientClasses)
    }
}

func writeSnakeCaseJSON<T: Encodable>(_ value: T, to path: String) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.keyEncodingStrategy = .convertToSnakeCase
    let data = try enc.encode(value)
    if path.isEmpty {
        print(String(data: data, encoding: .utf8) ?? "{}")
    } else {
        try data.write(to: URL(fileURLWithPath: path))
    }
}

struct SegBenchJSON: Encodable {
    let meanFoodClassIoU: Float
    // The Req 10 sliver fraction the predicted argmax was regularised with, so a
    // sweep's reports are self-describing rather than told apart by filename.
    let sliverFraction: Double
    let perClassIoU: [String: Float]
}

// MARK: - Shared helpers

func loadFixtures(dir: String, sha256: String) throws -> [PbMealFixture] {
    try FixtureLoader.load(from: URL(fileURLWithPath: dir), checkpointSHA256: sha256)
}

// Pre-release there is exactly one palette (pipeline Decision 50), so every
// fixture resolves to `ClassPalette.standard`. The learning that led here
// stands: a fixture whose tensors were recorded against a different palette
// shape must fail loudly, never trap — the batch size guards
// (seg-bench-silently-drops-mis-sized-fixtures) report such fixtures as
// mis-sized skips. Fixtures stamped with a superseded pre-release palette are
// scratch and must be regenerated, not resolved.
func paletteForFixture(_ fixture: PbMealFixture) -> ClassPalette {
    _ = fixture
    return ClassPalette.standard
}

// A fixture the pipeline cannot process is a reported skip, never a silent
// drop (calibrate-silently-drops-unreadable-fixtures): the old `try?` +
// `compactMap` here computed the accuracy report over an unstated subset.
func buildCalInputs(
    fixtures: [PbMealFixture], db: any FoodDatabase, edgeMm: Float,
    regularisation: MaskRegularisationConfig = .standard,
    growth: FoodRegionGrowthConfig = .standard
) -> (inputs: [MealCalibrationInput], skips: [FixtureBatch.Skip]) {
    let (results, skips) = FixtureBatch.partition(fixtures: fixtures) { fx in
        try FixtureRunner.run(
            fixture: fx, palette: paletteForFixture(fx), database: db, voxelEdgeMm: edgeMm,
            regularisation: regularisation, growth: growth)
    }
    return (results, skips)
}

// One line per single-view fixture for the depth-grown-food-region sweep
// (task 5): the food-like fraction of the frame before and after growth,
// whether the cap tripped, and what the refit returned.
func reportRegionGrowth(_ inputs: [MealCalibrationInput], fixtures: [PbMealFixture]) {
    let frame: [String: Int] = fixtures.reduce(into: [:]) { d, fx in
        d[fx.fixtureID] = Int(fx.nadirIntrinsics.imageWidth) * Int(fx.nadirIntrinsics.imageHeight)
    }
    for m in inputs {
        guard let g = m.regionGrowth, let px = frame[m.fixtureID], px > 0 else { continue }
        let before = Float(g.foodPixelsBefore) / Float(px)
        let after = Float(g.foodPixelsAfter) / Float(px)
        let refit = g.refitReference?.rawValue ?? (g.refitRefused ? "refused" : "none")
        fputs(String(format: "growth fixture=%@ before=%.4f after=%.4f applied=%d capTripped=%d refit=%@ plane=%@ seedAreaCm2=%.1f gated=%d\n",
                     m.fixtureID, before, after, g.applied ? 1 : 0, g.capTripped ? 1 : 0,
                     refit, m.supportPlaneReference?.rawValue ?? "none",
                     g.seedAreaCm2, g.gated ? 1 : 0), stderr)
    }
}

// MARK: - volumes (field replay: what the device would measure, no truth needed)

// One JSON object per fixture with the per-class volumes the single- or
// two-view replay produces, the plane it used, and what growth did. The
// `accuracy` report needs ground-truth carbs; a field bundle has none, so this
// is the way to read a replayed device capture — and to compare a bundle
// against a modified copy of it (a user-drawn silhouette, a relabelled view).
func runVolumes(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("volumes requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let regularisation = regularisationConfig(args: args)
    let growth = growthConfig(args: args)
    var nadirSeed: SIMD2<Int>?
    if let x = args.seedX, let y = args.seedY {
        nadirSeed = SIMD2(x, y)
    } else if args.seedX != nil || args.seedY != nil {
        fputs("volumes: --seed-x and --seed-y must be given together\n", stderr); exit(1)
    }
    struct Row: Encodable {
        let fixtureID: String
        let capturePath: String
        let perClassVolumesCm3: [String: Float]
        let predictedCarbsPerClass: [String: Float]
        let planeReference: String?
        let planeResidualMm: Float?
        let growthApplied: Bool?
        let foodPixelsBefore: Int?
        let foodPixelsAfter: Int?
        let refitReference: String?
        let seedAreaCm2: Float?
        let growthGated: Bool?
        let nadirSeed: [Int]?
        let skipped: String?
    }
    var rows: [Row] = []
    for fx in fixtures {
        do {
            let m = try FixtureRunner.run(
                fixture: fx, palette: paletteForFixture(fx), database: db,
                voxelEdgeMm: args.voxelEdgeMm, regularisation: regularisation, growth: growth,
                nadirSeed: nadirSeed)
            rows.append(Row(
                fixtureID: m.fixtureID, capturePath: m.capturePath.rawValue,
                perClassVolumesCm3: m.perClassVolumesCm3,
                predictedCarbsPerClass: m.predictedCarbsPerClass,
                planeReference: m.supportPlaneReference?.rawValue,
                planeResidualMm: m.supportPlaneResidualMm,
                growthApplied: m.regionGrowth?.applied,
                foodPixelsBefore: m.regionGrowth?.foodPixelsBefore,
                foodPixelsAfter: m.regionGrowth?.foodPixelsAfter,
                refitReference: m.regionGrowth?.refitReference?.rawValue,
                seedAreaCm2: m.regionGrowth?.seedAreaCm2,
                growthGated: m.regionGrowth?.gated,
                nadirSeed: nadirSeed.map { [$0.x, $0.y] },
                skipped: nil))
        } catch {
            rows.append(Row(
                fixtureID: fx.fixtureID, capturePath: fx.capturePathCanonical,
                perClassVolumesCm3: [:], predictedCarbsPerClass: [:],
                planeReference: nil, planeResidualMm: nil, growthApplied: nil,
                foodPixelsBefore: nil, foodPixelsAfter: nil, refitReference: nil,
                seedAreaCm2: nil, growthGated: nil,
                nadirSeed: nadirSeed.map { [$0.x, $0.y] },
                skipped: "\(error)"))
        }
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(rows)
    if args.outputPath.isEmpty {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } else {
        try data.write(to: URL(fileURLWithPath: args.outputPath))
    }
}

// MARK: - cards (card-detection replay: what Vision finds on a stored nadir frame)

// One line per fixture and candidate: the quad Vision's rectangle detector
// returns on the bundle's nadir image, the P4P pose solved from it, and the
// card-plane scale beside the LiDAR scale at the food plane (|d| / f_mean, the
// single-view replay's own plane fit). `--max-observations 1` (the default) is
// the device's single pick; higher lists the ranked candidates behind it. No
// checkpoint gate — the detector reads the image, not the segmenter's output;
// the stored argmax is used only for the food mask the plane fit needs,
// regularised as the replay regularises it.
func runCards(args: Args) throws {
    guard !args.fixturePaths.isEmpty else {
        fputs("cards requires one or more .fixture paths\n", stderr); exit(1)
    }
    let detector = VisionCardDetector(maximumObservations: args.maxObservations)
    let palette = ClassPalette.standard
    func fmt(_ v: Float, _ places: Int = 2) -> String { String(format: "%.\(places)f", v) }
    for path in args.fixturePaths {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let fixture = try PbMealFixture(serializedBytes: Data(contentsOf: URL(fileURLWithPath: path)))
        let frame = try args.oblique ? FixtureRunner.obliqueFrame(fixture: fixture) : FixtureRunner.nadirFrame(fixture: fixture)
        let k = frame.intrinsics
        let W = k.imageWidth
        let H = k.imageHeight
        var line = "stem=\(stem) view=\(args.oblique ? "oblique" : "nadir") path=\(fixture.capturePathCanonical)"
        line += " K=(\(k.fx),\(k.fy),\(k.cx),\(k.cy),\(W)x\(H))"

        var sLidar: Float?
        if !args.oblique, fixture.hasNadirDepth, fixture.nadirArgmax.count == W * H {
            let cleaned = SegmenterPostProcessor.regularise(
                argmax: fixture.nadirArgmax, width: W, height: H,
                palette: palette, config: .standard)
            let argmax = ArgmaxMap(pixels: cleaned, height: H, width: W)
            if let fit = try? FixtureRunner.fitSupportPlane(
                depth: DepthMap(pb: fixture.nadirDepth), intrinsics: k, gravity: frame.gravity,
                foodMask: FixtureRunner.foodRegionMask(argmax: argmax, palette: palette),
                fixtureID: fixture.fixtureID) {
                sLidar = abs(fit.plane.distanceMm) / ((k.fx + k.fy) / 2)
                line += " lidarPlaneDistMm=\(fmt(fit.plane.distanceMm, 1))"
            }
        }
        line += " sLidarMmPerPx=" + (sLidar.map { fmt($0, 4) } ?? "none")

        let candidates = detectSync(detector, frame: frame)
        guard !candidates.isEmpty else {
            print(line + " corners=none"); continue
        }
        // The candidate the pipeline would take (CardPoseSolver.pick).
        let picked = (try? CardPoseSolver.pick(candidates: candidates, intrinsics: k, lidarMmPerPx: sLidar))??.corners
        for (index, corners) in candidates.enumerated() {
            var row = line + " candidate=\(index + 1)/\(candidates.count) picked=\(corners == picked)"
            let labels = ["tl", "tr", "br", "bl"]
            for (label, c) in zip(labels, corners) {
                row += " \(label)=(\(fmt(c.u, 1)),\(fmt(c.v, 1)))"
            }
            // The solver maps TL→TR onto the card's 85.60 mm edge; a quad whose
            // first edge is the short one is being solved with the sides swapped.
            let e0 = hypot(corners[1].u - corners[0].u, corners[1].v - corners[0].v)
            let e1 = hypot(corners[2].u - corners[1].u, corners[2].v - corners[1].v)
            row += " edgesPx=\(fmt(e0, 0))/\(fmt(e1, 0))"
            do {
                let pose = try CardPoseSolver.solve(corners: corners, intrinsics: k)
                row += " pnpResidualPx=\(fmt(pose.pnpResidualPx))"
                row += " tzMm=\(fmt(pose.translationMm.z, 1))"
                row += " sCardMmPerPx=\(fmt(pose.scaleAtCardPlaneMmPerPx, 4))"
                row += " cornersExact=\(corners.map { [$0.u, $0.v] })"
                if let sLidar {
                    let sCard = pose.scaleAtCardPlaneMmPerPx
                    row += " disagreement=\(fmt(abs(sLidar - sCard) / ((sLidar + sCard) / 2), 3))"
                }
            } catch {
                row += " pose=failed(\(error))"
            }
            print(row)
        }
    }
}

// `detect(in:)` is async and this is a synchronous command-line
// tool: run it on a task and block the main thread until the continuation
// resumes off the detector's own queue.
func detectSync(_ detector: VisionCardDetector, frame: RawFrame) -> [[PixelCorner]] {
    final class Box: @unchecked Sendable { var candidates: [[PixelCorner]] = [] }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    Task {
        box.candidates = await detector.detect(in: frame)
        done.signal()
    }
    done.wait()
    return box.candidates
}

// MARK: - accuracy (task 60)

func runAccuracy(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("accuracy requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let regularisation = regularisationConfig(args: args)
    let growth = growthConfig(args: args)
    let (labelledInputs, skips) = buildCalInputs(
        fixtures: fixtures, db: db, edgeMm: args.voxelEdgeMm,
        regularisation: regularisation, growth: growth)
    // `--ingest-summary` (a field derivation's run_summary.json) scores each
    // reviewed capture at the classes its review named, as `calibrate` fits it.
    let review = CalibrateRun.review(from: try args.ingestSummaryPaths.map {
        try CalibrateRun.loadIngestSummary(from: URL(fileURLWithPath: $0))
    })
    let fixtureByID = Dictionary(fixtures.map { ($0.fixtureID, $0) },
                                 uniquingKeysWith: { first, _ in first })
    var details: [String: AccuracyJSON.DetailJSON] = [:]
    let calInputs = labelledInputs.map { labelled -> MealCalibrationInput in
        let edition = fixtureByID[labelled.fixtureID]?.databaseEdition ?? ""
        var scored = labelled
        var reviewJSON: AccuracyJSON.ReviewJSON?
        if let reviewed = review[labelled.fixtureID] {
            scored = reviewed.apply(to: labelled, database: db, edition: edition)
            reviewJSON = AccuracyJSON.ReviewJSON(
                relabelled: reviewed.relabelled, rejected: reviewed.rejected.sorted(),
                labelledVolumesCm3: labelled.perClassVolumesCm3,
                labelledCarbsG: labelled.predictedCarbsPerClass.values.reduce(0, +))
        }
        let macros = Macros.compute(perClassVolumesCm3: scored.perClassVolumesCm3,
                                    database: db, edition: edition)
        details[labelled.fixtureID] = AccuracyJSON.DetailJSON(
            perClassVolumesCm3: scored.perClassVolumesCm3,
            perClassMassG: macros.perClass.mapValues(\.massG),
            groundTruthClassMassG: fixtureByID[labelled.fixtureID]?.groundTruthClassMassG ?? [:],
            supportPlaneReference: scored.supportPlaneReference?.rawValue,
            review: reviewJSON)
        return scored
    }
    if !review.isEmpty {
        fputs("accuracy: review applied to \(details.values.filter { $0.review != nil }.count) "
              + "of \(calInputs.count) replayed fixture(s)\n", stderr)
    }
    fputs("accuracy: sliver fraction \(regularisation.sliverFraction)\n", stderr)
    fputs("accuracy: growth cliff=\(growth.cliffMm) floor=\(growth.floorMm) cap=\(growth.frameFractionCap) band=\(growth.seedBandMm) gateCm2=\(growth.seedAreaGateCm2)\n", stderr)
    reportRegionGrowth(calInputs, fixtures: fixtures)
    for skip in skips {
        fputs("accuracy: fixture skipped \(skip.fixtureID): \(skip.reason)\n", stderr)
    }
    // Report the count even when it is zero, so its absence is a measurement
    // rather than a silence (same rule as the calibrate-and-eval skips).
    fputs("accuracy: pipeline skips \(skips.count) of \(fixtures.count) fixtures\n", stderr)
    if calInputs.isEmpty && !fixtures.isEmpty {
        fputs("accuracy: every fixture failed the pipeline — refusing to emit "
            + "a report over zero meals\n", stderr)
        exit(1)
    }
    let evalMeals: [MealEvalInput] = calInputs.map { m in
        MealEvalInput(
            fixtureID: m.fixtureID, capturePath: m.capturePath,
            predictedCarbsPerClass: m.predictedCarbsPerClass,
            statusPerClass: m.predictedCarbsPerClass.keys.reduce(into: [:]) { d, k in
                d[k] = .uncalibratedUnity
            },
            groundTruthTotalCarbsG: m.groundTruthTotalCarbsG,
            supportPlaneReference: m.supportPlaneReference
        )
    }
    let report = AccuracyHarness.evaluate(meals: evalMeals)
    let checkpointSHAs = Set(fixtures.map(\.segmenterCheckpointSha256)).sorted()
    try emitAccuracy(report, checkpointSHAs: checkpointSHAs, details: details,
                     to: args.outputPath)
}

// MARK: - calibrate (task 58, extended by nutrition5k-calibration tasks 21–22)

struct CalibrationOutcome {
    let artifact: CalibrationArtifact
    let routed: CalibrateRun.Routed
    let mixtureObs: [MixtureBetaCalibrator.PlateObservation]
    let mixtureResult: MixtureBetaCalibrator.Result
    let sdResult: CalibrationResult
    let admittedInputs: [MealCalibrationInput]
    // True when any fixture carries a Nutrition5k source_dataset stamp.
    // MetaFood3D fixtures and device capture bundles do not count: neither
    // has an official split to exclude.
    let hasN5k: Bool
    let ingestSummaries: [CalibrateRun.IngestSummary]
    // Cross-dataset reporting inputs (cross-dataset-calibration Req 8.2/10):
    // the combined merge, the N5k-only baseline merge (nil when the run has
    // no MetaFood3D rows), and the held-out anchor report (nil when
    // --heldout-frac is 0 or nothing was held out).
    let merged: [String: CalibrationMerge.ClassCalibration]
    let mergedBaseline: [String: CalibrationMerge.ClassCalibration]?
    let heldOutAnchor: HeldOutAnchorReport?
    // Req 2.3 volume-fit diagnostic (nil unless --mesh-truth was given):
    // rides the calibrate artifact AND the eval report — reported, never
    // baked (generate.py does not read it).
    let volumeFitDiagnostic: CalibrationArtifact.VolumeFitDiagnosticBlock?
}

// β map the eval applies: calibrated classes only — pooled/unity classes ride
// the default β = 1 exactly as the estimator would apply them.
func calibratedBetaMap(_ merged: [String: CalibrationMerge.ClassCalibration])
    -> [String: Float] {
    merged.filter { $0.value.status == .calibrated }.mapValues(\.beta)
}

// Route fixtures per estimator_path, run both calibrators, merge, and build
// the JSON artifact: single_dominant through the existing BetaCalibrator on
// the HeightFieldEstimator masking path (Req 5.1); mixture through
// TotalHullVolume + MixtureBetaCalibrator; CalibrationMerge decides per-class
// β (Req 5.2).
func runCalibration(args: Args, db: any FoodDatabase,
                    palette: ClassPalette) throws -> CalibrationOutcome {
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let split = args.depthTestSplitPath.isEmpty
        ? Set<String>()
        : try CalibrateRun.loadDepthTestSplit(
            from: URL(fileURLWithPath: args.depthTestSplitPath))
    // One --ingest-summary per dataset (cross-dataset-calibration Req 10.1):
    // exclusion sets merge across datasets; per-dataset skip counts stay
    // attributable in the run-summary buckets.
    let ingestSummaries = try args.ingestSummaryPaths.map {
        try CalibrateRun.loadIngestSummary(from: URL(fileURLWithPath: $0))
    }
    let mergedUnmapped = ingestSummaries.reduce(into: Set<String>()) {
        $0.formUnion($1.unmappedExcluded)
    }
    let routed = CalibrateRun.route(fixtures: fixtures, depthTestSplit: split,
                                    unmappedExcluded: mergedUnmapped)
    // Identified by the source_dataset stamp, which N5k ingestion has written
    // since the same commit that introduced estimator_path. A device capture
    // bundle (CaptureBundleRecorder) is stamped single_dominant with no
    // source_dataset and has no official split to exclude.
    let hasN5k = fixtures.contains { CalibrateRun.dataset(of: $0) == "nutrition5k" }
    // Req 4.4 is a SHALL: an N5k run without the official depth-test split
    // would silently calibrate on held-out dishes — fail loudly instead.
    if hasN5k && split.isEmpty {
        fputs("calibrate: N5k fixtures require --depth-test-split "
            + "(data/dish_ids/splits/depth_test_ids.txt) so the official "
            + "test dishes are excluded before selection (Req 4.4)\n", stderr)
        exit(1)
    }
    // Fixtures carry mapped masses only, so without the ingestion run summary
    // the >10%-unmapped-mass exclusion (Req 4.1) cannot be applied and those
    // plates would bias co-occurring β downward.
    if hasN5k && ingestSummaries.isEmpty {
        fputs("calibrate: WARNING — no --ingest-summary; unmapped-heavy "
            + "plates (Req 4.1) cannot be excluded from the mixture fit\n",
            stderr)
    }
    // MetaFood3D fixtures integrate against the AUTHORED support plane
    // (Decision 13) — the plane depth rides the MF3D ingestion summary's
    // render_config. Without it the only alternative is the plate-region
    // RANSAC, which silently fits the food surface on steep foods, so a
    // MetaFood3D run without the summary fails loudly instead.
    let mf3dSummary = ingestSummaries.first { $0.dataset == "metafood3d" }
    let hasMF3D = fixtures.contains { CalibrateRun.dataset(of: $0) == "metafood3d" }
    if hasMF3D && mf3dSummary?.renderPlaneDepthMm == nil {
        fputs("calibrate: MetaFood3D fixtures require an --ingest-summary "
            + "carrying render_config.plane_depth_mm — the injected support "
            + "plane (Decision 13) is authored from it\n", stderr)
        exit(1)
    }

    // A field capture's volume rows are relabelled to the review's classes
    // BEFORE the purity gate: its truth is recorded under the class the user
    // named, and a plate measured under the segmenter's class would be dropped
    // for disagreeing with it. N5k and MetaFood3D summaries carry no review.
    let review = CalibrateRun.review(from: ingestSummaries)

    // Single-dominant (and legacy) fixtures via FixtureRunner; plates whose
    // pipeline run fails (e.g. poor plate-plane fit) are skipped + recorded
    // (Req 3.4/3.8).
    var planeFitSkipped: [String] = []
    var sdInputs: [MealCalibrationInput] = []
    var massDominant: [String: String] = [:]
    for fx in routed.singleDominant {
        do {
            var input = try FixtureRunner.run(fixture: fx, palette: palette,
                                              database: db, voxelEdgeMm: args.voxelEdgeMm,
                                              regularisation: regularisationConfig(args: args))
            if let reviewed = review[fx.fixtureID] {
                input = reviewed.apply(to: input, database: db, edition: fx.databaseEdition)
            }
            sdInputs.append(input)
            if fx.estimatorPath == "single_dominant" {
                massDominant[fx.fixtureID] =
                    fx.groundTruthClassMassG.max(by: { $0.value < $1.value })?.key
            }
        } catch {
            planeFitSkipped.append(fx.fixtureID)
        }
    }
    // τ_purity applies only to stamped N5k single-dominant plates (Req 4.2);
    // legacy fixtures bypass it.
    let n5kSD = sdInputs.filter { massDominant[$0.fixtureID] != nil }
    let legacySD = sdInputs.filter { massDominant[$0.fixtureID] == nil }
    let gated = CalibrateRun.applyPurityGate(n5kSD, massDominantByFixture: massDominant)
    // Req 5.4: β_c is fitted on the subset sharing the reference it will be
    // applied under. The corpus spans two references permanently (Decision 17),
    // so this is a standing constraint rather than a migration measure.
    let referenceGated = CalibrateRun.applyReferenceGate(legacySD + gated.admitted)
    let admittedInputs = referenceGated.admitted
    // The split-based result feeds the legacy self-evaluation only; the baked
    // β fits on ALL qualifying plates (design §Split reconciliation), so a
    // single-dominant staple needs the 30-plate floor, not ~50.
    let (sdResult, _) = BetaCalibrator.calibrateWithFit(meals: admittedInputs)
    let sdFit = BetaCalibrator.bakeFit(meals: admittedInputs)

    // Mixture fixtures: plate-region plane + depth-threshold hull volume for
    // N5k; the authored injected plane for MetaFood3D (Decision 13). The
    // skips are counted SEPARATELY from the single-dominant ones: this site
    // swallows a `fitPlateRegionPlane` throw, so a broken flood fill would empty
    // the mixture corpus while the run still reported success (Decision 17).
    //
    // The Req 10.2 held-out MetaFood3D objects are excluded from the fit but
    // still measured — they are the anchor's out-of-sample pool.
    let mf3dIDs = routed.mixture
        .filter { CalibrateRun.dataset(of: $0) == "metafood3d" }
        .map(\.fixtureID)
    let heldOutIDs = AccuracyHarness.heldOutSplit(
        ids: mf3dIDs, fraction: args.heldoutFrac, seed: args.seed)

    var mixtureObs: [MixtureBetaCalibrator.PlateObservation] = []
    var obsDataset: [String: String] = [:]          // fixtureID → dataset
    var heldOutObs: [SingleFoodObservation] = []
    var mixturePlaneFitSkipped: [String] = []
    for fx in routed.mixture {
        guard fx.hasNadirDepth else { mixturePlaneFitSkipped.append(fx.fixtureID); continue }
        let dataset = CalibrateRun.dataset(of: fx)
        let injectedPlane: SupportPlane? = dataset == "metafood3d"
            ? mf3dSummary?.renderPlaneDepthMm.map {
                CalibrateRun.authoredSupportPlane(gravity: Vec3(pb: fx.gravity),
                                                  planeDepthMm: $0)
            } ?? nil
            : nil
        do {
            let obs = try CalibrateRun.mixtureObservation(
                fixture: fx, injectedSupportPlane: injectedPlane)
            if heldOutIDs.contains(fx.fixtureID) {
                // Single-food by construction: the one mapped class carries
                // the whole GT mass.
                if let (className, massG) = fx.groundTruthClassMassG
                    .max(by: { $0.value < $1.value }) {
                    heldOutObs.append(SingleFoodObservation(
                        fixtureID: fx.fixtureID, className: className,
                        estimatedVolumeCm3: obs.totalHullVolumeCm3,
                        groundTruthMassG: massG))
                }
            } else {
                mixtureObs.append(obs)
                obsDataset[fx.fixtureID] = dataset.isEmpty ? "nutrition5k" : dataset
            }
        } catch {
            mixturePlaneFitSkipped.append(fx.fixtureID)
        }
    }
    planeFitSkipped.append(contentsOf: mixturePlaneFitSkipped)
    let liquidClasses = Set(palette.liquidClasses)
    var densityByClass: [String: Float] = [:]
    let fitClasses = Set(mixtureObs.flatMap { $0.massByClassG.keys })
        .union(heldOutObs.map(\.className))
    for c in fitClasses {
        densityByClass[c] = db.entry(for: c)?.densityGPerCm3
    }
    let mixtureResult = MixtureBetaCalibrator.fit(
        mixtureObs, densityByClass: densityByClass, liquidClasses: liquidClasses)

    // Standalone per-dataset solves (Req 5.1): the skew guard and the
    // corroboration flag read these; the baked β always comes from the shared
    // pooled solve above. A single-dataset run is the identity through this
    // path (Req 7.1).
    var obsByDataset: [String: [MixtureBetaCalibrator.PlateObservation]] = [:]
    for obs in mixtureObs {
        obsByDataset[obsDataset[obs.fixtureID] ?? "nutrition5k", default: []].append(obs)
    }
    let datasetFits = obsByDataset.sorted { $0.key < $1.key }.map { dataset, obs in
        CalibrationMerge.DatasetFit(
            dataset: dataset,
            result: MixtureBetaCalibrator.fit(obs, densityByClass: densityByClass,
                                              liquidClasses: liquidClasses))
    }

    let merged = CalibrationMerge.merge(singleDominant: sdFit, mixture: mixtureResult,
                                        perDataset: datasetFits)

    // N5k-only baseline merge (Req 8.2/10.1): what this run would have baked
    // without the MetaFood3D rows, for the before/after coverage report.
    var mergedBaseline: [String: CalibrationMerge.ClassCalibration]?
    if hasMF3D {
        let n5kObs = mixtureObs.filter { obsDataset[$0.fixtureID] != "metafood3d" }
        let n5kResult = MixtureBetaCalibrator.fit(
            n5kObs, densityByClass: densityByClass, liquidClasses: liquidClasses)
        mergedBaseline = CalibrationMerge.merge(singleDominant: sdFit, mixture: n5kResult)
    }

    // Held-out anchor (Req 10.2): predicted mass = V_est·β·ρ_DB on the
    // objects excluded from the fit. Reported, never a bake gate (Decision 9).
    let anchor: HeldOutAnchorReport? = heldOutObs.isEmpty ? nil
        : AccuracyHarness.heldOutAnchor(
            observations: heldOutObs,
            beta: calibratedBetaMap(merged),
            densityByClass: densityByClass)
    if let anchor {
        fputs("held-out MetaFood3D anchor (reported, not gating): "
            + "mass MAPE \(anchor.massMAPEPercent.map { "\($0)%" } ?? "not measured") "
            + "over \(anchor.sampleCount) object(s)"
            + (anchor.broccoliCrossCheckMAPE.map { "; broccoli cross-check \($0)%" } ?? "")
            + "\n", stderr)
    }

    // Volume-fit diagnostic (Req 2.3, Decision 7): β_geom = V_mesh_true/V_est
    // per class from the ingestion truth sidecar, next to the baked mass-fit
    // β with a divergence flag. Reported, never baked — a large gap between
    // the two isolates a density-draw problem the mass fit conflates. Held-out
    // objects are included: the diagnostic is per object, not part of the fit.
    var volumeFitDiagnostic: CalibrationArtifact.VolumeFitDiagnosticBlock?
    if !args.meshTruthPath.isEmpty {
        let truth = try VolumeFitDiagnostic.loadTruth(
            from: URL(fileURLWithPath: args.meshTruthPath))
        var diagObs: [VolumeFitDiagnostic.Observation] = []
        for obs in mixtureObs where obsDataset[obs.fixtureID] == "metafood3d" {
            // Single-food by construction: the one mapped class.
            if let className = obs.massByClassG.max(by: { $0.value < $1.value })?.key {
                diagObs.append(.init(fixtureID: obs.fixtureID, className: className,
                                     estimatedVolumeCm3: obs.totalHullVolumeCm3))
            }
        }
        for held in heldOutObs {
            diagObs.append(.init(fixtureID: held.fixtureID, className: held.className,
                                 estimatedVolumeCm3: held.estimatedVolumeCm3))
        }
        let report = VolumeFitDiagnostic.compute(
            observations: diagObs, truthVolumeMm3ByFixture: truth)
        let block = CalibrationArtifact.VolumeFitDiagnosticBlock(
            report: report, bakedBeta: calibratedBetaMap(merged))
        volumeFitDiagnostic = block
        for (className, row) in block.perClass.sorted(by: { $0.key < $1.key }) {
            fputs("volume-fit diagnostic (reported, not baked): \(className) "
                + "beta_geom \(row.betaGeom) over \(row.sampleCount) object(s)"
                + (row.betaBaked.map { "; mass-fit beta \($0)"
                    + (row.divergesFromMassFit ? " — DIVERGES (>\(block.divergenceDelta))" : "")
                } ?? "; no baked beta")
                + "\n", stderr)
        }
        if !report.missingTruth.isEmpty {
            fputs("volume-fit diagnostic: \(report.missingTruth.count) object(s) "
                + "missing from the truth sidecar: "
                + report.missingTruth.joined(separator: " ") + "\n", stderr)
        }
    } else if hasMF3D {
        fputs("calibrate: WARNING — MetaFood3D fixtures without --mesh-truth; "
            + "the Req 2.3 volume-fit diagnostic (beta_geom vs the mass-fit "
            + "beta) is not computed\n", stderr)
    }

    // Lineage (Req 5.5). Release/metadata identifiers ride the fixtures'
    // source_dataset stamp: "nutrition5k@<release>/<metaver>".
    let source = fixtures.first(where: {
        !$0.sourceDataset.isEmpty && CalibrateRun.dataset(of: $0) != "metafood3d"
    })?.sourceDataset ?? ""
    let afterAt = source.split(separator: "@").last.map(String.init) ?? ""
    let parts = afterAt.split(separator: "/").map(String.init)

    // Cross-dataset lineage (Req 9.1): the pinned render configuration and
    // each contributing dataset's snapshot + mapping-artifact version.
    var renderConfig: CalibrationArtifact.RenderConfig?
    if let mf3d = mf3dSummary, let planeDepthMm = mf3d.renderPlaneDepthMm {
        renderConfig = CalibrationArtifact.RenderConfig(
            intrinsicsModel: mf3d.renderIntrinsicsModel ?? args.intrinsicsModel,
            planeDepthMm: planeDepthMm,
            imageWidth: mf3d.renderImageWidth ?? 0,
            imageHeight: mf3d.renderImageHeight ?? 0,
            seatingRule: mf3d.renderSeatingRule ?? "")
    }
    // Licence provenance (cross-dataset-calibration Decision 17): each
    // dataset's licence rides its per-dataset lineage — Nutrition5k is a
    // known CC BY 4.0 release; MetaFood3D's comes from its ingest summary
    // (whose loader already fails loudly when it is absent). The top-level
    // lineage licence is the STRICTEST contributing licence, so a MetaFood3D
    // contribution (CC BY-NC 4.0, non-commercial) is never understated by
    // the single value generate.py persists.
    let n5kLicence = "CC BY 4.0"
    var perDatasetLineage: [String: CalibrationArtifact.DatasetLineage] = [:]
    if hasN5k {
        perDatasetLineage["nutrition5k"] = .init(
            snapshot: afterAt, mappingArtifactVersion: args.mappingVersion,
            licence: n5kLicence)
    }
    if let mf3d = mf3dSummary, hasMF3D {
        perDatasetLineage["metafood3d"] = .init(
            snapshot: mf3d.snapshot, mappingArtifactVersion: mf3d.mappingVersion,
            licence: mf3d.licence ?? "")
    }
    // Field captures (tools/field_loop/derive_dataset.py): without this a
    // field-only run's lineage would fall back to N5k's CC BY 4.0.
    if let field = ingestSummaries.first(where: { $0.dataset == "medata_field" }) {
        perDatasetLineage["medata_field"] = .init(
            snapshot: field.snapshot, mappingArtifactVersion: field.mappingVersion,
            licence: field.licence ?? "")
    }
    let lineageLicence = CalibrationArtifact.strictestLicence(
        perDatasetLineage.values.map(\.licence)) ?? n5kLicence

    let lineage = CalibrationArtifact.Lineage(
        n5kRelease: parts.first ?? "",
        n5kMetadataVersion: parts.count > 1 ? parts[1] : "",
        mappingArtifactVersion: args.mappingVersion,
        tauRoute: CalibrateRun.tauRoute,
        tauPurity: CalibrateRun.tauPurity,
        tauEff: MixtureBetaCalibrator.tauEff,
        kappaStacking: MixtureBetaCalibrator.stackingKappa,
        seed: args.seed,
        effectiveSamplePerClass: merged.mapValues(\.effectiveSample),
        conditionNumber: mixtureResult.conditionNumber.isFinite
            ? mixtureResult.conditionNumber : -1,
        identifiablePerClass: mixtureResult.identifiablePerClass,
        pinnedIntrinsicsModel: args.intrinsicsModel,
        licence: lineageLicence,
        renderConfig: renderConfig,
        perDataset: perDatasetLineage)

    // Run summary (Req 3.8/4.2/4.3/4.7): every excluded/dropped plate is
    // recorded, with the drop reasons distinguished.
    fputs("""
        calibrate summary:
          depth-test-split excluded: \(routed.depthTestExcluded.count)
          unmapped-mass excluded (Req 4.1): \(routed.unmappedExcluded.count)
          purity dropped (not re-routed): \(gated.dropped)
          plane-fit/pipeline skipped: \(planeFitSkipped.count)
          of which mixture plate-region fits: \(mixturePlaneFitSkipped.count) \
        of \(routed.mixture.count)
          support-plane reference excluded (Req 5.4): \
        \(referenceGated.excluded.count)
          stacking excluded: \(mixtureResult.excludedPlates)
          liquid excluded: \(mixtureResult.liquidExcludedPlates)\n
        """, stderr)
    if !review.isEmpty {
        let applied = routed.singleDominant.filter { review[$0.fixtureID] != nil }.count
        fputs("  review relabels applied before the purity gate: \(applied) "
              + "of \(routed.singleDominant.count) single-dominant fixture(s)\n", stderr)
    }

    // Per-dataset exclusion buckets (cross-dataset-calibration Req 1.4): the
    // N5k depth-test-split drops and each dataset's ingestion skips stay
    // attributable in a multi-dataset run.
    func countByDataset(_ fixtures: [PbMealFixture]) -> [String: Int] {
        fixtures.reduce(into: [:]) { counts, fx in
            let ds = CalibrateRun.dataset(of: fx)
            counts[ds.isEmpty ? "nutrition5k" : ds, default: 0] += 1
        }
    }
    let ingestionSkippedByDataset = ingestSummaries.reduce(into: [String: Int]()) {
        let ds = $1.dataset.isEmpty ? "nutrition5k" : $1.dataset
        $0[ds, default: 0] += $1.ingestionSkipCount
    }

    let runSummary = CalibrationArtifact.RunSummary(
        depthTestSplitExcluded: routed.depthTestExcluded.map(\.fixtureID).sorted(),
        unmappedExcluded: routed.unmappedExcluded.map(\.fixtureID).sorted(),
        purityDropped: gated.dropped.sorted(),
        planeFitSkipped: planeFitSkipped.sorted(),
        stackingExcluded: mixtureResult.excludedPlates.sorted(),
        liquidExcluded: mixtureResult.liquidExcludedPlates.sorted(),
        supportPlaneReferenceExcluded: referenceGated.excluded.sorted(),
        depthTestSplitExcludedByDataset: countByDataset(routed.depthTestExcluded),
        unmappedExcludedByDataset: countByDataset(routed.unmappedExcluded),
        ingestionSkippedByDataset: ingestionSkippedByDataset)

    return CalibrationOutcome(
        artifact: CalibrationArtifact(
            merged: merged, betaPool: sdFit.betaPool,
            supportPlaneReference: CalibrateRun.fittedSupportPlaneReference,
            lineage: lineage, runSummary: runSummary,
            volumeFitDiagnostic: volumeFitDiagnostic),
        routed: routed,
        mixtureObs: mixtureObs,
        mixtureResult: mixtureResult,
        sdResult: sdResult,
        admittedInputs: admittedInputs,
        hasN5k: hasN5k,
        ingestSummaries: ingestSummaries,
        merged: merged,
        mergedBaseline: mergedBaseline,
        heldOutAnchor: anchor,
        volumeFitDiagnostic: volumeFitDiagnostic)
}

func runCalibrate(args: Args) throws {
    guard !args.fixturesDir.isEmpty else {
        fputs("calibrate requires --fixtures-dir\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let outcome = try runCalibration(args: args, db: db, palette: .standard)
    let data = try CalibrationArtifact.encoder().encode(outcome.artifact)
    if args.outputPath.isEmpty {
        print(String(data: data, encoding: .utf8) ?? "{}")
    } else {
        try data.write(to: URL(fileURLWithPath: args.outputPath))
    }
}

// MARK: - calibrate-and-eval (task 62, extended by nutrition5k-calibration task 22)

// Build the composition tables the eval shares with inference (Req 5.3).
func classComposition(for classes: Set<String>, db: any FoodDatabase) -> ClassComposition {
    var density: [String: Float] = [:]
    var carb: [String: Float] = [:]
    var protein: [String: Float] = [:]
    var fat: [String: Float] = [:]
    for c in classes {
        guard let e = db.entry(for: c) else { continue }
        density[c] = e.densityGPerCm3
        carb[c] = e.carbsMonoG
        protein[c] = e.proteinG
        fat[c] = e.fatG
    }
    return ClassComposition(densityByClass: density, carbFractionPer100g: carb,
                            proteinFractionPer100g: protein, fatFractionPer100g: fat)
}

func runCalibrateAndEval(args: Args) throws {
    guard !args.fixturesDir.isEmpty else {
        fputs("calibrate-and-eval requires --fixtures-dir\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let palette = ClassPalette.standard
    let outcome = try runCalibration(args: args, db: db, palette: palette)

    guard outcome.hasN5k else {
        // Legacy fixtures: the original split-based eval, unchanged.
        try runLegacyEval(outcome: outcome, args: args)
        return
    }

    // N5k eval: k-fold CV over the calibration pool + the official-split
    // whole-dish section (Req 6.1/6.8).
    let fixtureByID = Dictionary(uniqueKeysWithValues:
        (outcome.routed.mixture + outcome.routed.depthTestExcluded)
            .map { ($0.fixtureID, $0) })
    let allClasses = Set(outcome.mixtureObs.flatMap { $0.massByClassG.keys })
        .union(outcome.routed.depthTestExcluded.flatMap { $0.groundTruthClassMassG.keys })
    let composition = classComposition(for: allClasses, db: db)

    let calibrationPlates: [N5kEvalPlate] = outcome.mixtureObs.compactMap { obs in
        guard let fx = fixtureByID[obs.fixtureID] else { return nil }
        return CalibrateRun.evalPlate(obs: obs, fixture: fx,
                                      composition: composition, official: false)
    }
    // Req 6.8: the report states evaluated-dish count vs split total —
    // enumerate the skips so the shrinkage is visible, not silent. Pre-
    // checkpoint every test dish is mixture-stamped; post-checkpoint the
    // single-dominant-stamped ones need the masked per-class eval, which
    // lands with the model-production re-fit (design §Accuracy reporting).
    var officialPlates: [N5kEvalPlate] = []
    var officialSkipped: [String: [String]] = [:]
    for fx in outcome.routed.depthTestExcluded {
        guard fx.estimatorPath == "mixture" else {
            officialSkipped["non_mixture_path", default: []].append(fx.fixtureID)
            continue
        }
        guard fx.hasNadirDepth else {
            officialSkipped["no_depth", default: []].append(fx.fixtureID)
            continue
        }
        guard let obs = try? CalibrateRun.mixtureObservation(fixture: fx) else {
            officialSkipped["plane_fit_failed", default: []].append(fx.fixtureID)
            continue
        }
        officialPlates.append(CalibrateRun.evalPlate(obs: obs, fixture: fx,
                                                     composition: composition,
                                                     official: true))
    }
    for (reason, ids) in officialSkipped.sorted(by: { $0.key < $1.key }) {
        fputs("calibrate-and-eval: official-split skip \(reason) "
            + "(\(ids.count)): \(ids.sorted().joined(separator: " "))\n", stderr)
    }
    // The plate-region fit is wrapped in `try?` here, so a broken fitter reads as
    // an empty official split rather than a failure. Report the count even when it
    // is zero, so its absence is a measurement rather than a silence (Decision 17).
    fputs("calibrate-and-eval: official-split mixture plate-region fits skipped: "
        + "\(officialSkipped["plane_fit_failed"]?.count ?? 0) of "
        + "\(outcome.routed.depthTestExcluded.count)\n", stderr)

    let config = CalibrationEvalConfig(
        folds: 5, seed: args.seed,
        liquidClasses: Set(palette.liquidClasses),
        carbPriorityStaples: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries",
        ])
    // rgbdDishCount here is the loaded-fixture proxy; the authoritative pool
    // number lives in the ingestion run summary (Req 4.5).
    let unmappedCount = outcome.routed.unmappedExcluded.count
    let report = AccuracyHarness.evaluateCalibration(
        calibrationPlates: calibrationPlates,
        officialSplitPlates: officialPlates,
        composition: composition,
        config: config,
        pool: PoolCounts(
            rgbdDishCount: calibrationPlates.count + officialPlates.count + unmappedCount,
            depthTestSplitCount: outcome.routed.depthTestExcluded.count,
            ingestionSkipCount: outcome.ingestSummaries
                .reduce(0) { $0 + $1.ingestionSkipCount },
            unmappedExcludedCount: unmappedCount))

    // Cross-dataset block (Req 8.2/10.1/10.2): only when the run carried
    // MetaFood3D rows — an N5k-only output keeps its pre-feature shape.
    var crossDataset: N5kEvalJSON.CrossDatasetJSON?
    if let baseline = outcome.mergedBaseline {
        let coverage = AccuracyHarness.betaCoverageDelta(
            before: baseline, after: outcome.merged)
        // The carb delta is measurable only on the N5k eval pool: staples
        // absent from it are named as having no in-harness validation.
        let carbDelta = AccuracyHarness.carbAccuracyDelta(
            plates: calibrationPlates,
            baselineBeta: calibratedBetaMap(baseline),
            combinedBeta: calibratedBetaMap(outcome.merged),
            composition: composition,
            liquidClasses: config.liquidClasses,
            staples: config.carbPriorityStaples)
        crossDataset = N5kEvalJSON.CrossDatasetJSON(
            betaCoverageDelta: coverage.mapValues(N5kEvalJSON.CrossDatasetJSON.CoverageJSON.init),
            carbDeltaOverall: .init(carbDelta.overall),
            carbDeltaPerClass: carbDelta.perClass
                .mapValues(N5kEvalJSON.CrossDatasetJSON.ClassDeltaJSON.init),
            carbDeltaSuppressedBelowMinCount: carbDelta.suppressedBelowMinCount,
            unvalidatedStaples: carbDelta.unvalidatedStaples,
            minEvalPlateCount: carbDelta.minEvalPlateCount,
            heldOutAnchor: outcome.heldOutAnchor
                .map(N5kEvalJSON.CrossDatasetJSON.AnchorJSON.init),
            volumeFitDiagnostic: outcome.volumeFitDiagnostic)
    }

    try writeSnakeCaseJSON(N5kEvalJSON(report, crossDataset: crossDataset),
                           to: args.outputPath)
}

func runLegacyEval(outcome: CalibrationOutcome, args: Args) throws {
    let calResult = outcome.sdResult
    let calInputs = outcome.admittedInputs
    let evalMeals: [MealEvalInput] = calResult.evalIndices.sorted().compactMap { i in
        guard i < calInputs.count else { return nil }
        let m = calInputs[i]
        let predicted = m.predictedCarbsPerClass.mapValues { v -> Float in
            let beta = calResult.betaPerClass[m.dominantClass ?? ""] ?? 1.0
            return v * beta
        }
        let status = m.predictedCarbsPerClass.keys.reduce(into: [String: BetaCalibrationStatus]()) {
            $0[$1] = calResult.statusPerClass[$1] ?? .uncalibratedUnity
        }
        return MealEvalInput(fixtureID: m.fixtureID, capturePath: m.capturePath,
                             predictedCarbsPerClass: predicted, statusPerClass: status,
                             groundTruthTotalCarbsG: m.groundTruthTotalCarbsG,
                             supportPlaneReference: m.supportPlaneReference)
    }
    let report = AccuracyHarness.evaluate(meals: evalMeals)
    // Legacy eval works from calibration inputs, not fixtures, so no checkpoint
    // set is available here.
    try emitAccuracy(report, to: args.outputPath)
}

// MARK: - diagnose (specs/estimation/ml-feedback-loop tasks 3-4)

// Emits the MealCalibrationInput data `accuracy` computes and discards, one
// record per fixture, stamped with the artifacts the replay ran against
// (Reqs 4.1/4.2/4.3). The Mac-side loop consumes this to attribute an
// estimation-vs-stated gap to a class, a volume, or a plane.
//
// Exit policy: non-zero ONLY on I/O failure — an unloadable fixtures directory
// or an unwritable output. Zero replayed meals is a REPORTED status, not a
// crash: field bundles routinely fail to replay (missing depth, a refusal
// recorded before segmentation), and the diagnosis of that is the artifact the
// loop needs, not an empty exit code (the calibrate-silently-drops precedent
// read the other way — nothing is dropped, so nothing needs to fail).
func runDiagnose(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("diagnose requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let replaySHA = args.replayCheckpointSHA256.isEmpty
        ? args.checkpointSHA256 : args.replayCheckpointSHA256
    let dbHash = try DiagnoseRun.contentSHA256(of: GRDBFoodDatabase.bundledResourceURLs())

    let report = DiagnoseRun.diagnose(
        fixtures: fixtures,
        replayCheckpointSHA256: replaySHA,
        replayDatabaseSHA256: dbHash,
        replayDatabaseEdition: db.version
    ) { fx in
        try FixtureRunner.run(fixture: fx, palette: paletteForFixture(fx),
                              database: db, voxelEdgeMm: args.voxelEdgeMm,
                              regularisation: regularisationConfig(args: args))
    }

    let data = try DiagnoseRun.encoder().encode(report)
    if args.outputPath.isEmpty {
        print(String(data: data, encoding: .utf8) ?? "{}")
    } else {
        try data.write(to: URL(fileURLWithPath: args.outputPath))
    }
    fputs("diagnose: \(report.replayedCount) replayed, "
        + "\(report.notReplayableCount) not replayable, "
        + "\(report.zeroMealCount) zero-meal, "
        + "\(report.versionSkewCount) version-skewed of \(fixtures.count) fixture(s)\n",
        stderr)
}

// MARK: - seg-bench (task 64)

func runSegBench(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("seg-bench requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let palette = fixtures.first.map(paletteForFixture) ?? .standard
    // Same per-fixture resolution as buildCalInputs, and the same rule
    // (seg-bench-silently-drops-mis-sized-fixtures): a fixture the bench
    // cannot decode is a reported skip, never a silent drop.
    let regularisation = regularisationConfig(args: args)
    let (samples, skips) = FixtureBatch.partition(fixtures: fixtures) { fx in
        try SegBench.sample(
            from: fx, palette: paletteForFixture(fx), regularisation: regularisation)
    }
    fputs("seg-bench: sliver fraction \(regularisation.sliverFraction)\n", stderr)
    for skip in skips {
        fputs("seg-bench: fixture skipped \(skip.fixtureID): \(skip.reason)\n", stderr)
    }
    fputs("seg-bench: pipeline skips \(skips.count) of \(fixtures.count) fixtures\n", stderr)
    if samples.isEmpty && !fixtures.isEmpty {
        fputs("seg-bench: every fixture failed — refusing to emit a report "
            + "over zero samples\n", stderr)
        exit(1)
    }
    let report = SegBench.evaluate(samples: samples, palette: palette)
    let perClassIoU = report.perClassIoU.reduce(into: [String: Float]()) { d, kv in
        let name = kv.key < palette.foodClasses.count
            ? palette.foodClasses[kv.key] : "class_\(kv.key)"
        d[name] = kv.value
    }
    try writeJSON(SegBenchJSON(
        meanFoodClassIoU: report.meanFoodClassIoU,
        sliverFraction: regularisation.sliverFraction,
        perClassIoU: perClassIoU
    ), to: args.outputPath)
}

// MARK: - carve-audit

// Accounts for the two-view carve's residual over-read on one or more stored
// bundles: the silhouette footprint, the whole height distribution behind the
// grid's vertical bound, a percentile x margin sweep of that bound, and a
// synthetic box of known size carved through the SAME estimator at the same
// bundle's baseline, which measures the visual hull's own bias with perfect
// masks. Positional `.fixture` paths, no checkpoint gate (as `cards`).
func runCarveAudit(args: Args) throws {
    guard !args.fixturePaths.isEmpty else {
        fputs("carve-audit requires one or more .fixture paths\n", stderr); exit(1)
    }
    func fmt(_ v: Float, _ places: Int = 1) -> String { String(format: "%.\(places)f", v) }
    let options = CarveResidualAudit.Options(
        edgeMm: args.voxelEdgeMm,
        boxMm: args.boxMm,
        syntheticCapsMm: args.syntheticCapsMm,
        syntheticTiltsDeg: args.syntheticTiltsDeg,
        regularisation: regularisationConfig(args: args),
        noDepth: args.noDepth)
    for path in args.fixturePaths {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let fixture = try PbMealFixture(serializedBytes: Data(contentsOf: URL(fileURLWithPath: path)))
        // Every bundle with nadir depth gets the profile: on a single-view
        // capture of the same food it IS the reference the carve is judged
        // against, measured by the identical rule.
        if let profile = try? CarveResidualAudit.heightProfile(
            fixture: fixture, palette: paletteForFixture(fixture), options: options) {
            var line = "stem=\(stem) profile path=\(profile.capturePath)"
            line += " plane=\(profile.planeReference ?? "none")"
            line += " planeDistMm=\(fmt(profile.planeDistanceMm))"
            line += " planeResidualMm=\(profile.planeResidualMm.map { fmt($0, 2) } ?? "none")"
            line += " foodPx=\(profile.foodPixels) footprintCm2=\(fmt(profile.footprintCm2))"
            line += " heightFieldCm3=\(fmt(profile.heightFieldIntegralCm3))"
            for q in profile.heights { line += " p\(Int(q.percentile * 100))=\(fmt(q.heightMm))" }
            print(line)
        }
        let report: CarveResidualAudit.Report
        do {
            report = try CarveResidualAudit.audit(
                fixture: fixture, palette: paletteForFixture(fixture), options: options)
        } catch {
            print("stem=\(stem) skipped=\(error)")
            continue
        }
        var head = "stem=\(stem) plane=\(report.planeReference ?? "none")"
        head += " planeResidualMm=\(report.planeResidualMm.map { fmt($0, 2) } ?? "none")"
        head += " baselineMm=\(fmt(report.baselineMm)) rotationDeg=\(fmt(report.obliqueRotationDeg))"
        head += " nadirFoodPx=\(report.nadirFoodPixels) obliqueFoodPx=\(report.obliqueFoodPixels)"
        head += " nadirFootprintCm2=\(fmt(report.nadirFootprintCm2))"
        head += " obliqueFootprintCm2=\(fmt(report.obliqueFootprintCm2))"
        head += " heightSamples=\(report.heightSampleCount)"
        print(head)
        var hs = "stem=\(stem) heights"
        for q in report.heights { hs += " p\(Int(q.percentile * 100))=\(fmt(q.heightMm))" }
        print(hs)
        print("stem=\(stem) production carvedCm3=\(fmt(report.productionCarvedCm3))"
            + " extentMm=\(fmt(report.productionExtentMm)) prismFill=\(fmt(report.prismFill, 3))")
        for row in report.sweep {
            print("stem=\(stem) sweep p=\(fmt(row.percentile, 2)) marginMm=\(fmt(row.marginMm, 0))"
                + " heightMm=\(fmt(row.heightMm)) extentMm=\(fmt(row.extentMm)) dimsZ=\(row.dimsZ)"
                + " carvedCm3=\(fmt(row.carvedCm3)) clippedFrac=\(fmt(row.clippedSampleFraction, 4))")
        }
        for v in report.planeVariants {
            print("stem=\(stem) plane variant=\(v.name) reference=\(v.reference ?? "none")"
                + (v.refitReference.map { " refit=\($0)" } ?? "")
                + " distMm=\(fmt(v.distanceMm)) residualMm=\(fmt(v.residualMm, 2))"
                + " footprintCm2=\(fmt(v.footprintCm2)) p50Mm=\(fmt(v.medianHeightMm))"
                + " p98Mm=\(fmt(v.p98HeightMm)) extentMm=\(fmt(v.extentMm))"
                + " carvedCm3=\(fmt(v.carvedCm3)) heightFieldCm3=\(fmt(v.heightFieldCm3))"
                + " hullOverSurface=\(fmt(v.heightFieldCm3 > 0 ? v.carvedCm3 / v.heightFieldCm3 : 0, 3))")
        }
        if let nd = report.noDepth {
            print("stem=\(stem) noDepth plane=\(nd.planeName) classes=\(nd.classes.joined(separator: ","))"
                + " capMm=\(fmt(nd.classCapMm)) capSource=\(nd.capSource)"
                + " constantExtentMm=\(fmt(nd.constantExtentMm)) constantCarvedCm3=\(fmt(nd.constantCarvedCm3))"
                + " capExtentMm=\(fmt(nd.capExtentMm)) capCarvedCm3=\(fmt(nd.capCarvedCm3))"
                + " lidarExtentMm=\(fmt(nd.lidarExtentMm)) lidarCarvedCm3=\(fmt(nd.lidarCarvedCm3))"
                + " constantOverLidar=\(fmt(nd.lidarCarvedCm3 > 0 ? nd.constantCarvedCm3 / nd.lidarCarvedCm3 : 0, 3))"
                + " capOverLidar=\(fmt(nd.lidarCarvedCm3 > 0 ? nd.capCarvedCm3 / nd.lidarCarvedCm3 : 0, 3))")
            // Decision 12: the footprint the ratio cap scaled with and its carve.
            print("stem=\(stem) noDepthRatio plane=\(nd.planeName)"
                + " footprintMm2=\(fmt(nd.footprintMm2, 0))"
                + " ratioCapMm=\(fmt(nd.ratioCapMm)) ratioCapSource=\(nd.ratioCapSource)"
                + " ratioExtentMm=\(fmt(nd.ratioExtentMm)) ratioCarvedCm3=\(fmt(nd.ratioCarvedCm3))"
                + " ratioOverLidar=\(fmt(nd.lidarCarvedCm3 > 0 ? nd.ratioCarvedCm3 / nd.lidarCarvedCm3 : 0, 3))")
        }
        for row in report.synthetic {
            print("stem=\(stem) synthetic box=\(row.boxMm.map { fmt($0, 0) }.joined(separator: "x"))"
                + (row.tiltDeg.map { " tiltDeg=\(fmt($0))" } ?? " tilt=stored")
                + " capMm=\(fmt(row.capMm))"
                + " extentMm=\(fmt(row.extentMm)) truthCm3=\(fmt(row.voxelisedTruthCm3))"
                + " carvedCm3=\(fmt(row.carvedCm3)) hullBias=\(fmt(row.hullBias, 3))"
                + " silhouetteFootprintCm2=\(fmt(row.silhouetteFootprintCm2))"
                + " trueFootprintCm2=\(fmt(row.trueFootprintCm2))")
        }
    }
}

// MARK: - Entry point

guard let args = parseArgs() else { exit(1) }

do {
    switch args.subcommand {
    case "accuracy":           try runAccuracy(args: args)
    case "calibrate":          try runCalibrate(args: args)
    case "calibrate-and-eval": try runCalibrateAndEval(args: args)
    case "seg-bench":          try runSegBench(args: args)
    case "diagnose":           try runDiagnose(args: args)
    case "volumes":            try runVolumes(args: args)
    case "cards":              try runCards(args: args)
    case "carve-audit":        try runCarveAudit(args: args)
    default:
        fputs("Unknown subcommand '\(args.subcommand)'\n", stderr)
        fputs("Valid: accuracy, calibrate, seg-bench, calibrate-and-eval, diagnose, volumes, cards, carve-audit\n", stderr)
        exit(1)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
#endif

