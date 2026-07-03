// HarnessCLI — offline test-set runner per design §7.3.
// Subcommands: accuracy, calibrate, seg-bench, calibrate-and-eval.
// Usage: HarnessCLI <subcommand> [flags]
//
// Feature-flagged off in v1 per Decision 41. The entire file is gated on
// HARNESS_ENABLED, defined only on the HarnessCLI SPM target. The shipping
// iOS app never includes this binary.
#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import HarnessCore
import PortableContracts
import Segmentation
import SwiftProtobuf

// MARK: - Argument Parsing

struct Args {
    let subcommand: String
    var fixturesDir: String = ""
    var checkpointSHA256: String = ""
    var outputPath: String = ""
    var voxelEdgeMm: Float = 3.0
    // nutrition5k-calibration (Req 4.4/5.5)
    var depthTestSplitPath: String = ""
    var seed: UInt64 = 42
    var mappingVersion: String = ""
    var intrinsicsModel: String = "realsense_d435_factory"
}

func parseArgs() -> Args? {
    var args = CommandLine.arguments.dropFirst()
    guard let subcommand = args.first else {
        fputs("Usage: HarnessCLI <accuracy|calibrate|seg-bench|calibrate-and-eval> [flags]\n", stderr)
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
        default: break
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
    let perClass: [String: PerClassJSON]
    struct PerClassJSON: Encodable {
        let mape: Float; let mae: Float
        let sampleCount: Int; let calibrationStatus: String
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
        let ingestionSkipCount: Int; let liquidExcludedCount: Int
        let stackingExcludedCount: Int; let qualifyingPlateCount: Int
        let effectiveSamplesByPath: [String: [String: Int]]
        let insufficientClasses: [String]
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

    init(_ r: CalibrationReport) {
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
    let meanFoodClassIoU: Float; let passesBar: Bool
    let perClassIoU: [String: Float]
}

// MARK: - Shared helpers

func loadFixtures(dir: String, sha256: String) throws -> [PbMealFixture] {
    try FixtureLoader.load(from: URL(fileURLWithPath: dir), checkpointSHA256: sha256)
}

func buildCalInputs(fixtures: [PbMealFixture], palette: ClassPalette,
                    db: any FoodDatabase, edgeMm: Float) -> [MealCalibrationInput] {
    fixtures.compactMap { fx in
        try? FixtureRunner.run(fixture: fx, palette: palette, database: db, voxelEdgeMm: edgeMm)
    }
}

// Decode FP16 LE HWC prob tensor and return per-pixel argmax.
func argmaxFromFP16Probs(probsData: Data, width: Int, height: Int, classes: Int) -> [UInt8] {
    probsData.withUnsafeBytes { raw -> [UInt8] in
        let buf = raw.bindMemory(to: Float16.self)
        var out = [UInt8](repeating: 0, count: height * width)
        for y in 0..<height {
            for x in 0..<width {
                let base = (y * width + x) * classes
                var maxIdx = 0
                var maxVal = Float16(-Float.infinity)
                for c in 0..<classes {
                    let v = buf[base + c]
                    if v > maxVal { maxVal = v; maxIdx = c }
                }
                out[y * width + x] = UInt8(clamping: maxIdx)
            }
        }
        return out
    }
}

// MARK: - accuracy (task 60)

func runAccuracy(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("accuracy requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let palette = ClassPalette.v1Standard
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let calInputs = buildCalInputs(fixtures: fixtures, palette: palette, db: db,
                                   edgeMm: args.voxelEdgeMm)
    let evalMeals: [MealEvalInput] = calInputs.map { m in
        MealEvalInput(
            fixtureID: m.fixtureID, capturePath: m.capturePath,
            predictedCarbsPerClass: m.predictedCarbsPerClass,
            statusPerClass: m.predictedCarbsPerClass.keys.reduce(into: [:]) { d, k in
                d[k] = .uncalibratedUnity
            },
            groundTruthTotalCarbsG: m.groundTruthTotalCarbsG
        )
    }
    let report = AccuracyHarness.evaluate(meals: evalMeals)
    try writeJSON(AccuracyJSON(
        mape: report.mape, mae: report.mae,
        ci95Lower: report.ci95Lower, ci95Upper: report.ci95Upper,
        passesBar: report.passesBar,
        perClass: report.perClassStats.mapValues { s in
            AccuracyJSON.PerClassJSON(mape: s.mape, mae: s.mae,
                                     sampleCount: s.sampleCount,
                                     calibrationStatus: s.calibrationStatus.rawValue)
        }
    ), to: args.outputPath)
    if !report.passesBar {
        fputs("FAIL: MAPE=\(report.mape)% MAE=\(report.mae)g\n", stderr); exit(1)
    }
}

// MARK: - calibrate (task 58, extended by nutrition5k-calibration tasks 21–22)

struct CalibrationOutcome {
    let artifact: CalibrationArtifact
    let routed: CalibrateRun.Routed
    let mixtureObs: [MixtureBetaCalibrator.PlateObservation]
    let mixtureResult: MixtureBetaCalibrator.Result
    let sdResult: CalibrationResult
    let admittedInputs: [MealCalibrationInput]
    // True when any fixture carries an estimator_path stamp (an N5k run).
    let hasN5k: Bool
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
    let routed = CalibrateRun.route(fixtures: fixtures, depthTestSplit: split)
    let hasN5k = fixtures.contains { !$0.estimatorPath.isEmpty }

    // Single-dominant (and legacy) fixtures via FixtureRunner; plates whose
    // pipeline run fails (e.g. poor plate-plane fit) are skipped + recorded
    // (Req 3.4/3.8).
    var planeFitSkipped: [String] = []
    var sdInputs: [MealCalibrationInput] = []
    var massDominant: [String: String] = [:]
    for fx in routed.singleDominant {
        do {
            let input = try FixtureRunner.run(fixture: fx, palette: palette,
                                              database: db, voxelEdgeMm: args.voxelEdgeMm)
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
    let admittedInputs = legacySD + gated.admitted
    let (sdResult, sdFit) = BetaCalibrator.calibrateWithFit(meals: admittedInputs)

    // Mixture fixtures: plate-region plane + depth-threshold hull volume.
    var mixtureObs: [MixtureBetaCalibrator.PlateObservation] = []
    for fx in routed.mixture {
        guard fx.hasNadirDepth else { planeFitSkipped.append(fx.fixtureID); continue }
        do {
            mixtureObs.append(try CalibrateRun.mixtureObservation(fixture: fx))
        } catch {
            planeFitSkipped.append(fx.fixtureID)
        }
    }
    let liquidClasses = Set(palette.liquidClasses)
    var densityByClass: [String: Float] = [:]
    for c in Set(mixtureObs.flatMap { $0.massByClassG.keys }) {
        densityByClass[c] = db.entry(for: c)?.densityGPerCm3
    }
    let mixtureResult = MixtureBetaCalibrator.fit(
        mixtureObs, densityByClass: densityByClass, liquidClasses: liquidClasses)

    let merged = CalibrationMerge.merge(singleDominant: sdFit, mixture: mixtureResult)

    // Lineage (Req 5.5). Release/metadata identifiers ride the fixtures'
    // source_dataset stamp: "nutrition5k@<release>/<metaver>".
    let source = fixtures.first(where: { !$0.sourceDataset.isEmpty })?.sourceDataset ?? ""
    let afterAt = source.split(separator: "@").last.map(String.init) ?? ""
    let parts = afterAt.split(separator: "/").map(String.init)
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
        licence: "CC BY 4.0")

    // Run summary (Req 3.8/4.2/4.3/4.7): every excluded/dropped plate is
    // recorded, with the drop reasons distinguished.
    fputs("""
        calibrate summary:
          depth-test-split excluded: \(routed.depthTestExcluded.map(\.fixtureID))
          purity dropped (not re-routed): \(gated.dropped)
          plane-fit/pipeline skipped: \(planeFitSkipped)
          stacking excluded: \(mixtureResult.excludedPlates)
          liquid excluded: \(mixtureResult.liquidExcludedPlates)\n
        """, stderr)

    return CalibrationOutcome(
        artifact: CalibrationArtifact(merged: merged, betaPool: sdFit.betaPool,
                                      lineage: lineage),
        routed: routed,
        mixtureObs: mixtureObs,
        mixtureResult: mixtureResult,
        sdResult: sdResult,
        admittedInputs: admittedInputs,
        hasN5k: hasN5k)
}

func runCalibrate(args: Args) throws {
    guard !args.fixturesDir.isEmpty else {
        fputs("calibrate requires --fixtures-dir\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let outcome = try runCalibration(args: args, db: db, palette: .v1Standard)
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

// N5k eval plate from a mixture observation. Per-class GT macros derive from
// GT mass × the DB fractions (the fixture proto carries per-dish totals only);
// the whole-dish figure is the fixture's own N5k total.
func n5kEvalPlate(obs: MixtureBetaCalibrator.PlateObservation,
                  fixture: PbMealFixture,
                  composition: ClassComposition,
                  official: Bool) -> N5kEvalPlate {
    var carbs: [String: Float] = [:]
    var protein: [String: Float] = [:]
    var fat: [String: Float] = [:]
    for (c, m) in obs.massByClassG {
        carbs[c] = m * composition.carbFractionPer100g[c, default: 0] / 100
        protein[c] = m * composition.proteinFractionPer100g[c, default: 0] / 100
        fat[c] = m * composition.fatFractionPer100g[c, default: 0] / 100
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

func runCalibrateAndEval(args: Args) throws {
    guard !args.fixturesDir.isEmpty else {
        fputs("calibrate-and-eval requires --fixtures-dir\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled()
    let palette = ClassPalette.v1Standard
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
        return n5kEvalPlate(obs: obs, fixture: fx, composition: composition, official: false)
    }
    var officialPlates: [N5kEvalPlate] = []
    for fx in outcome.routed.depthTestExcluded where fx.estimatorPath == "mixture" {
        guard fx.hasNadirDepth,
              let obs = try? CalibrateRun.mixtureObservation(fixture: fx) else { continue }
        officialPlates.append(n5kEvalPlate(obs: obs, fixture: fx,
                                           composition: composition, official: true))
    }

    let config = CalibrationEvalConfig(
        folds: 5, seed: args.seed,
        liquidClasses: Set(palette.liquidClasses),
        carbPriorityStaples: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries",
        ])
    // rgbdDishCount here is the loaded-fixture proxy; the authoritative pool
    // number lives in the ingestion run summary (Req 4.5).
    let report = AccuracyHarness.evaluateCalibration(
        calibrationPlates: calibrationPlates,
        officialSplitPlates: officialPlates,
        composition: composition,
        config: config,
        pool: PoolCounts(
            rgbdDishCount: calibrationPlates.count + officialPlates.count,
            depthTestSplitCount: outcome.routed.depthTestExcluded.count,
            ingestionSkipCount: 0))

    try writeSnakeCaseJSON(N5kEvalJSON(report), to: args.outputPath)
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
                             groundTruthTotalCarbsG: m.groundTruthTotalCarbsG)
    }
    let report = AccuracyHarness.evaluate(meals: evalMeals)
    try writeJSON(AccuracyJSON(
        mape: report.mape, mae: report.mae,
        ci95Lower: report.ci95Lower, ci95Upper: report.ci95Upper,
        passesBar: report.passesBar,
        perClass: report.perClassStats.mapValues { s in
            AccuracyJSON.PerClassJSON(mape: s.mape, mae: s.mae,
                                     sampleCount: s.sampleCount,
                                     calibrationStatus: s.calibrationStatus.rawValue)
        }
    ), to: args.outputPath)
    if !report.passesBar {
        fputs("FAIL: MAPE=\(report.mape)% MAE=\(report.mae)g\n", stderr); exit(1)
    }
}

// MARK: - seg-bench (task 64)

func runSegBench(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("seg-bench requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let palette = ClassPalette.v1Standard
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let samples: [SegBenchSample] = fixtures.compactMap { fx in
        let intr = CameraIntrinsics(pb: fx.nadirIntrinsics)
        let W = intr.imageWidth; let H = intr.imageHeight; let C = palette.totalClasses
        guard fx.nadirProbs.count == H * W * C * 2 else { return nil }
        let predicted = argmaxFromFP16Probs(probsData: fx.nadirProbs,
                                            width: W, height: H, classes: C)
        return SegBenchSample(fixtureID: fx.fixtureID,
                              predictedArgmax: predicted,
                              groundTruthArgmax: [UInt8](fx.nadirArgmax),
                              width: W, height: H)
    }
    let report = SegBench.evaluate(samples: samples, palette: palette)
    let perClassIoU = report.perClassIoU.reduce(into: [String: Float]()) { d, kv in
        let name = kv.key < palette.foodClasses.count
            ? palette.foodClasses[kv.key] : "class_\(kv.key)"
        d[name] = kv.value
    }
    try writeJSON(SegBenchJSON(
        meanFoodClassIoU: report.meanFoodClassIoU,
        passesBar: report.passesBar,
        perClassIoU: perClassIoU
    ), to: args.outputPath)
    if !report.passesBar {
        fputs("FAIL: mIoU=\(report.meanFoodClassIoU) — below 0.60\n", stderr); exit(1)
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
    default:
        fputs("Unknown subcommand '\(args.subcommand)'\n", stderr)
        fputs("Valid: accuracy, calibrate, seg-bench, calibrate-and-eval\n", stderr)
        exit(1)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
#endif
