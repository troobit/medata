#if HARNESS_ENABLED
import CryptoKit
import Foundation
import PortableContracts

// The core of the `HarnessCLI diagnose` subcommand
// (specs/estimation/ml-feedback-loop Reqs 4.1/4.2/4.3, design "Deterministic
// diagnosis").
//
// `accuracy` builds a MealCalibrationInput per fixture and keeps one number
// from it — the predicted carb total. Everything the Mac-side loop needs to
// attribute a gap to a CAUSE rather than a symptom is in the part it discards:
// which classes were priced, what volume each carried, which class dominated,
// which surface the support plane referenced and how well it fitted. This emits
// exactly that, one record per fixture, plus the identity of the artifacts the
// replay ran against.
//
// The replay is injected (FixtureBatch.partition's shape): the pipeline has its
// own suites, and what belongs here is the per-fixture record, the replay-status
// vocabulary and the version-skew stamp.
public enum DiagnoseRun {

    // Req 4.2. `missing_bundle` is deliberately absent: only the Mac side, which
    // holds the corpus index, can know a note's bundle was never pulled — the
    // harness only ever sees files that exist.
    public enum ReplayStatus: String, Encodable, Sendable {
        case replayed
        case notReplayable = "not_replayable"
        case replayZeroMeals = "replay_zero_meals"
    }

    public struct Diagnosis: Encodable, Sendable {
        public let fixtureID: String
        // Req 6.6 segments every metric by capture mode, and the fixture stamp
        // is where the mode comes from.
        public let capturePathCanonical: String
        public let replayStatus: ReplayStatus
        // Present only on `not_replayable`; the pipeline error verbatim, so a
        // recurring failure mode is greppable rather than re-derived.
        public let replayFailureReason: String?

        // What the CAPTURE recorded, beside what the replay ran (Req 4.3).
        public let recordedModelVersion: String
        public let recordedDatabaseEdition: String
        // True when either differs from the replaying binary's. The Mac side
        // excludes skewed pairs from the 4.3 attribution floor: once the loop
        // lands fixes, HEAD-vs-device drift would otherwise absorb the loop's
        // own effect and report it as replay noise.
        public let replayVersionSkew: Bool

        // The MealCalibrationInput the accuracy path discards.
        public let dominantClass: String?
        public let predictedCarbsPerClass: [String: Float]
        public let perClassVolumesCm3: [String: Float]
        // nil on the two-view path, which derives no depth plane — absent, not
        // defaulted.
        public let supportPlaneReference: String?
        public let supportPlaneResidualMm: Float?

        public let predictedTotalCarbsG: Float
        public let groundTruthTotalCarbsG: Float

        // Every key is written on every row, nulls included (the AccuracyJSON
        // fallbackRate precedent). Synthesised encoding drops nil optionals,
        // which would make "two-view, so no plane reference" indistinguishable
        // from "the harness forgot to emit one" — and the Mac side segments
        // every metric by exactly those fields.
        enum CodingKeys: String, CodingKey {
            case fixtureID, capturePathCanonical, replayStatus, replayFailureReason
            case recordedModelVersion, recordedDatabaseEdition, replayVersionSkew
            case dominantClass, predictedCarbsPerClass, perClassVolumesCm3
            case supportPlaneReference, supportPlaneResidualMm
            case predictedTotalCarbsG, groundTruthTotalCarbsG
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(fixtureID, forKey: .fixtureID)
            try c.encode(capturePathCanonical, forKey: .capturePathCanonical)
            try c.encode(replayStatus, forKey: .replayStatus)
            try c.encode(replayFailureReason, forKey: .replayFailureReason)
            try c.encode(recordedModelVersion, forKey: .recordedModelVersion)
            try c.encode(recordedDatabaseEdition, forKey: .recordedDatabaseEdition)
            try c.encode(replayVersionSkew, forKey: .replayVersionSkew)
            try c.encode(dominantClass, forKey: .dominantClass)
            try c.encode(predictedCarbsPerClass, forKey: .predictedCarbsPerClass)
            try c.encode(perClassVolumesCm3, forKey: .perClassVolumesCm3)
            try c.encode(supportPlaneReference, forKey: .supportPlaneReference)
            try c.encode(supportPlaneResidualMm, forKey: .supportPlaneResidualMm)
            try c.encode(predictedTotalCarbsG, forKey: .predictedTotalCarbsG)
            try c.encode(groundTruthTotalCarbsG, forKey: .groundTruthTotalCarbsG)
        }
    }

    public struct Report: Encodable, Sendable {
        // The artifacts the replay actually ran against (Req 4.3). Recorded on
        // every run, not only on skew, so a diagnosis stays interpretable years
        // later without reconstructing which binary produced it.
        public let replayCheckpointSha256: String
        public let replayDatabaseSha256: String
        public let replayDatabaseEdition: String
        public let replayedCount: Int
        public let notReplayableCount: Int
        public let zeroMealCount: Int
        public let versionSkewCount: Int
        public let fixtures: [Diagnosis]
    }

    // snake_case, matching calibrate-and-eval: the consumer is
    // tools/field_loop/field_diagnose.py. Status values are already written in
    // the Req 4.2 vocabulary and pass through untouched — the strategy renames
    // keys, never values.
    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.keyEncodingStrategy = .convertToSnakeCase
        return enc
    }

    // Every fixture becomes exactly one row, whatever happens to it: a replay
    // failure is a recorded status, never a dropped fixture
    // (calibrate-silently-drops-unreadable-fixtures).
    public static func diagnose(
        fixtures: [PbMealFixture],
        replayCheckpointSHA256: String,
        replayDatabaseSHA256: String,
        replayDatabaseEdition: String,
        run: (PbMealFixture) throws -> MealCalibrationInput
    ) -> Report {
        var rows: [Diagnosis] = []
        rows.reserveCapacity(fixtures.count)
        for fx in fixtures {
            // Stamped before the replay is attempted: a fixture that failed to
            // replay AND was recorded under different artifacts must not read
            // as skew-free.
            let skew = fx.segmenterCheckpointSha256 != replayCheckpointSHA256
                || fx.databaseEdition != replayDatabaseEdition
            do {
                let input = try run(fx)
                let total = input.predictedCarbsPerClass.values.reduce(0, +)
                rows.append(Diagnosis(
                    fixtureID: fx.fixtureID,
                    capturePathCanonical: fx.capturePathCanonical,
                    // Volume without a priced class is not a failure and not a
                    // meal: the pipeline ran, and there is still nothing to
                    // compare a stated description against.
                    replayStatus: input.predictedCarbsPerClass.isEmpty
                        ? .replayZeroMeals : .replayed,
                    replayFailureReason: nil,
                    recordedModelVersion: fx.segmenterCheckpointSha256,
                    recordedDatabaseEdition: fx.databaseEdition,
                    replayVersionSkew: skew,
                    dominantClass: input.dominantClass,
                    predictedCarbsPerClass: input.predictedCarbsPerClass,
                    perClassVolumesCm3: input.perClassVolumesCm3,
                    supportPlaneReference: input.supportPlaneReference?.rawValue,
                    supportPlaneResidualMm: input.supportPlaneResidualMm,
                    predictedTotalCarbsG: total,
                    groundTruthTotalCarbsG: fx.groundTruthTotalCarbsG))
            } catch {
                rows.append(Diagnosis(
                    fixtureID: fx.fixtureID,
                    capturePathCanonical: fx.capturePathCanonical,
                    replayStatus: .notReplayable,
                    replayFailureReason: String(describing: error),
                    recordedModelVersion: fx.segmenterCheckpointSha256,
                    recordedDatabaseEdition: fx.databaseEdition,
                    replayVersionSkew: skew,
                    dominantClass: nil,
                    predictedCarbsPerClass: [:],
                    perClassVolumesCm3: [:],
                    supportPlaneReference: nil,
                    supportPlaneResidualMm: nil,
                    predictedTotalCarbsG: 0,
                    groundTruthTotalCarbsG: fx.groundTruthTotalCarbsG))
            }
        }
        return Report(
            replayCheckpointSha256: replayCheckpointSHA256,
            replayDatabaseSha256: replayDatabaseSHA256,
            replayDatabaseEdition: replayDatabaseEdition,
            replayedCount: rows.filter { $0.replayStatus == .replayed }.count,
            notReplayableCount: rows.filter { $0.replayStatus == .notReplayable }.count,
            zeroMealCount: rows.filter { $0.replayStatus == .replayZeroMeals }.count,
            versionSkewCount: rows.filter(\.replayVersionSkew).count,
            fixtures: rows)
    }

    // The DB content hash of design "Metrics": SHA-256 over the committed
    // sqlite artifacts as an ORDERED whole, so the pair identifies one bake
    // rather than two independently-swappable files. Streamed, because the
    // artifacts are tens of megabytes.
    public static func contentSHA256(of urls: [URL]) throws -> String {
        var hasher = SHA256()
        for url in urls {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
