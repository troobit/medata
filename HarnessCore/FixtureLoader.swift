#if HARNESS_ENABLED
import Foundation
import PortableContracts
import SwiftProtobuf

// Loads PbMealFixture records from a directory of .fixture binary-proto files.
//
// Guards are per estimator path (Req 3.7, Decision 17). The `estimator_path`
// field — not the SHA value — authoritatively selects the path, or any fixture
// could bypass the hash guard by writing the sentinel string:
//   ""               — legacy fixture: the original design §7.3 checkpoint-SHA
//                      hash guard, unchanged.
//   "single_dominant" — hash guard unchanged, plus a missing, empty, or
//                      sentinel SHA is malformed (never coerced).
//   "mixture"        — accepts ONLY the sentinel SHA and rejects any fixture
//                      carrying segmentation probabilities.
// Any other value is malformed.
public enum FixtureLoader {
    // Sentinel carried by mixture fixtures, which bake without a checkpoint
    // (Decision 17). Must match tools/nutrition5k/ingest.py SENTINEL_SHA.
    public static let sentinelSHA = "no_segmenter"

    public enum Error: Swift.Error, Equatable {
        case checkpointMismatch(expected: String, got: String, file: String)
        case invalidCheckpointSHA(got: String, file: String)
        case probabilitiesOnMixturePath(file: String)
        case malformedEstimatorPath(value: String, file: String)
        case parseFailure(file: String)
        case directoryUnreadable(String)
    }

    // Load all `.fixture` files from `directoryURL` in lexicographic order.
    // Throws on the first fixture that fails its path's guard.
    public static func load(
        from directoryURL: URL,
        checkpointSHA256: String
    ) throws -> [PbMealFixture] {
        let urls: [URL]
        do {
            urls = try FileManager.default
                .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "fixture" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw Error.directoryUnreadable(directoryURL.path)
        }

        return try urls.map { url in
            let data = try Data(contentsOf: url)
            let fixture: PbMealFixture
            do {
                fixture = try PbMealFixture(serializedBytes: data)
            } catch {
                throw Error.parseFailure(file: url.lastPathComponent)
            }
            try validate(fixture, file: url.lastPathComponent,
                         checkpointSHA256: checkpointSHA256)
            return fixture
        }
    }

    static func validate(_ fixture: PbMealFixture, file: String,
                         checkpointSHA256: String) throws {
        let sha = fixture.segmenterCheckpointSha256
        switch fixture.estimatorPath {
        case "":
            // Legacy fixture (pre-N5k): original hash guard.
            guard sha == checkpointSHA256 else {
                throw Error.checkpointMismatch(
                    expected: checkpointSHA256, got: sha, file: file)
            }
        case "single_dominant":
            // A missing/empty SHA is malformed and never coerced to the
            // sentinel; the sentinel itself is invalid on this path.
            guard !sha.isEmpty, sha != sentinelSHA else {
                throw Error.invalidCheckpointSHA(got: sha, file: file)
            }
            guard sha == checkpointSHA256 else {
                throw Error.checkpointMismatch(
                    expected: checkpointSHA256, got: sha, file: file)
            }
        case "mixture":
            // Mixture fixtures bake without the checkpoint (Decision 17) and
            // must not smuggle in segmenter output (Req 3.7) — neither
            // probabilities nor a pre-computed argmax mask.
            guard fixture.nadirProbs.isEmpty, fixture.obliqueProbs.isEmpty,
                  fixture.nadirArgmax.isEmpty, fixture.obliqueArgmax.isEmpty else {
                throw Error.probabilitiesOnMixturePath(file: file)
            }
            guard sha == sentinelSHA else {
                throw Error.checkpointMismatch(
                    expected: sentinelSHA, got: sha, file: file)
            }
        default:
            throw Error.malformedEstimatorPath(
                value: fixture.estimatorPath, file: file)
        }
    }
}
#endif
