#if HARNESS_ENABLED
import Foundation
import PortableContracts
import SwiftProtobuf
import Testing
@testable import HarnessCore

// Per-path load guards keyed off the authoritative estimator_path field
// (spec task 17, Req 3.7, Decision 17). The guard matrix, design §Testing:
// estimator_path — not the sentinel string — selects the path, or any fixture
// could bypass the hash guard by writing the magic value.
@Suite("FixtureLoader per-path guards")
struct FixtureLoaderGuardTests {

    static let realSHA = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"

    func makeDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func makeFixture(id: String, path: String, sha: String,
                     withProbs: Bool) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        fx.paletteVersion = "v0"
        fx.segmenterCheckpointSha256 = sha
        fx.estimatorPath = path
        fx.capturePathCanonical = "single_view_lidar"
        fx.groundTruthClassMassG = ["white_rice": 120]
        if withProbs {
            fx.nadirProbs = Data(count: 4 * 4 * 35 * 2)
            fx.nadirArgmax = Data(count: 4 * 4)
        }
        return fx
    }

    func write(_ fixtures: [PbMealFixture], to dir: URL) throws {
        for fx in fixtures {
            try fx.serializedData().write(to: dir.appendingPathComponent("\(fx.fixtureID).fixture"))
        }
    }

    @Test("A mixture fixture with the sentinel SHA loads on the mixture path")
    func mixtureWithSentinelLoads() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-mix", path: "mixture",
                               sha: FixtureLoader.sentinelSHA, withProbs: false)], to: dir)

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        #expect(loaded.map(\.fixtureID) == ["fx-mix"])
    }

    @Test("A mixture fixture carrying segmentation probabilities is rejected")
    func mixtureWithProbsRejected() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-mix-probs", path: "mixture",
                               sha: FixtureLoader.sentinelSHA, withProbs: true)], to: dir)

        #expect(throws: FixtureLoader.Error.probabilitiesOnMixturePath(file: "fx-mix-probs.fixture")) {
            try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        }
    }

    @Test("A mixture fixture carrying only an argmax mask is rejected too")
    func mixtureWithArgmaxOnlyRejected() throws {
        // Req 3.7 forbids segmenter output on the mixture path — a
        // pre-computed argmax is a mask even without the probability tensor.
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var fx = makeFixture(id: "fx-mix-argmax", path: "mixture",
                             sha: FixtureLoader.sentinelSHA, withProbs: false)
        fx.nadirArgmax = Data(count: 4 * 4)
        try write([fx], to: dir)

        #expect(throws: FixtureLoader.Error.probabilitiesOnMixturePath(file: "fx-mix-argmax.fixture")) {
            try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        }
    }

    @Test("A mixture fixture whose SHA is not the sentinel is rejected")
    func mixtureWithRealSHARejected() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-mix-sha", path: "mixture",
                               sha: Self.realSHA, withProbs: false)], to: dir)

        #expect(throws: FixtureLoader.Error.self) {
            try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        }
    }

    @Test("Single-dominant SHA guard rejects wrong, missing, empty, and sentinel SHAs",
          arguments: [
            "1111111111111111111111111111111111111111111111111111111111111111",
            "",
            "no_segmenter",
          ])
    func singleDominantRejectsBadSHA(sha: String) throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-sd-bad", path: "single_dominant",
                               sha: sha, withProbs: true)], to: dir)

        #expect(throws: FixtureLoader.Error.self) {
            try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        }
    }

    @Test("A missing/empty SHA is never coerced to the sentinel — even when the sentinel is expected")
    func emptySHANeverCoerced() throws {
        // Even if a caller passed the sentinel as the expected checkpoint, an
        // empty SHA on the single-dominant path is malformed, not sentinel.
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-sd-empty", path: "single_dominant",
                               sha: "", withProbs: true)], to: dir)

        #expect(throws: FixtureLoader.Error.self) {
            try FixtureLoader.load(from: dir, checkpointSHA256: FixtureLoader.sentinelSHA)
        }
    }

    @Test("A single-dominant fixture with the matching real SHA loads")
    func singleDominantWithRealSHALoads() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-sd", path: "single_dominant",
                               sha: Self.realSHA, withProbs: true)], to: dir)

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        #expect(loaded.map(\.fixtureID) == ["fx-sd"])
    }

    @Test("An unknown estimator_path value is malformed")
    func unknownEstimatorPathMalformed() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([makeFixture(id: "fx-odd", path: "hybrid",
                               sha: Self.realSHA, withProbs: true)], to: dir)

        #expect(throws: FixtureLoader.Error.malformedEstimatorPath(value: "hybrid", file: "fx-odd.fixture")) {
            try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        }
    }

    @Test("Mixed directories load both paths under their own guards")
    func mixedDirectoryLoadsBothPaths() throws {
        let dir = makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write([
            makeFixture(id: "fx-a-mix", path: "mixture",
                        sha: FixtureLoader.sentinelSHA, withProbs: false),
            makeFixture(id: "fx-b-sd", path: "single_dominant",
                        sha: Self.realSHA, withProbs: true),
        ], to: dir)

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: Self.realSHA)
        #expect(loaded.map(\.fixtureID) == ["fx-a-mix", "fx-b-sd"])
    }
}
#endif
