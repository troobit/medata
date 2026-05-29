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

struct CalibrationJSON: Encodable {
    let betaPool: Float
    let classes: [String: ClassJSON]
    struct ClassJSON: Encodable { let beta: Float; let status: String }
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
    let db = try GRDBFoodDatabase.bundled(overlayEnabled: false)
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

// MARK: - calibrate (task 58)

func runCalibrate(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("calibrate requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled(overlayEnabled: false)
    let palette = ClassPalette.v1Standard
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let calInputs = buildCalInputs(fixtures: fixtures, palette: palette, db: db,
                                   edgeMm: args.voxelEdgeMm)
    let result = BetaCalibrator.calibrate(meals: calInputs)
    try writeJSON(CalibrationJSON(
        betaPool: result.betaPool,
        classes: result.betaPerClass.keys.reduce(into: [:]) { d, k in
            d[k] = CalibrationJSON.ClassJSON(beta: result.betaPerClass[k]!,
                                             status: result.statusPerClass[k]!.rawValue)
        }
    ), to: args.outputPath)
}

// MARK: - calibrate-and-eval (task 62)

func runCalibrateAndEval(args: Args) throws {
    guard !args.fixturesDir.isEmpty, !args.checkpointSHA256.isEmpty else {
        fputs("calibrate-and-eval requires --fixtures-dir and --checkpoint-sha256\n", stderr); exit(1)
    }
    let db = try GRDBFoodDatabase.bundled(overlayEnabled: false)
    let palette = ClassPalette.v1Standard
    let fixtures = try loadFixtures(dir: args.fixturesDir, sha256: args.checkpointSHA256)
    let calInputs = buildCalInputs(fixtures: fixtures, palette: palette, db: db,
                                   edgeMm: args.voxelEdgeMm)
    let calResult = BetaCalibrator.calibrate(meals: calInputs)

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
