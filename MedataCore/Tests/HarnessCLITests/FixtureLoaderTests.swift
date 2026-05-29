#if HARNESS_ENABLED
import XCTest
import Foundation
import PortableContracts
import SwiftProtobuf
@testable import HarnessCore

// Tests for FixtureLoader — task 55: MealFixture .proto round-trip and sha256 guard.
final class FixtureLoaderTests: XCTestCase {

    // Verify that a PbMealFixture serialised to binary and read back via
    // FixtureLoader.load is bit-equal to the original (§7.3 round-trip).
    func testRoundTripViaFixtureLoader() throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sha = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"
        let original = makeFixture(id: "fx-001", sha256: sha)
        let data = try original.serializedData()
        try data.write(to: dir.appendingPathComponent("fx-001.fixture"))

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: sha)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], original)
    }

    // Fixture whose segmenter_checkpoint_sha256 does not match the expected hash must be refused.
    func testCheckpointSHA256GuardRefusesMismatch() throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bundledSHA = "1111111111111111111111111111111111111111111111111111111111111111"
        let fixtureSHA = "2222222222222222222222222222222222222222222222222222222222222222"
        let fixture = makeFixture(id: "fx-bad", sha256: fixtureSHA)
        let data = try fixture.serializedData()
        try data.write(to: dir.appendingPathComponent("fx-bad.fixture"))

        XCTAssertThrowsError(
            try FixtureLoader.load(from: dir, checkpointSHA256: bundledSHA)
        ) { error in
            guard case FixtureLoader.Error.checkpointMismatch(
                let expected, let got, let file
            ) = error else {
                XCTFail("Expected checkpointMismatch; got \(error)")
                return
            }
            XCTAssertEqual(expected, bundledSHA)
            XCTAssertEqual(got, fixtureSHA)
            XCTAssertEqual(file, "fx-bad.fixture")
        }
    }

    // A directory with matching fixtures loads all of them in lexicographic order.
    func testLoadsMultipleFixturesInOrder() throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sha = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        for id in ["fx-003", "fx-001", "fx-002"] {
            let fx = makeFixture(id: id, sha256: sha)
            try fx.serializedData().write(to: dir.appendingPathComponent("\(id).fixture"))
        }

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: sha)
        XCTAssertEqual(loaded.map(\.fixtureID), ["fx-001", "fx-002", "fx-003"])
    }

    // Non-.fixture files in the directory are ignored.
    func testIgnoresNonFixtureFiles() throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let fx = makeFixture(id: "fx-ok", sha256: sha)
        try fx.serializedData().write(to: dir.appendingPathComponent("fx-ok.fixture"))
        try Data("noise".utf8).write(to: dir.appendingPathComponent("README.md"))

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: sha)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].fixtureID, "fx-ok")
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFixture(id: String, sha256: String) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        fx.fixtureRevision = "rev-1"
        fx.paletteVersion = "v1"
        fx.databaseEdition = "CoFID 2024 + IFCDB 2023"
        fx.segmenterCheckpointSha256 = sha256
        fx.nadirImage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        fx.nadirProbs = Data(count: 4 * 4 * 27 * 2)
        fx.nadirArgmax = Data(count: 4 * 4)
        fx.groundTruthClassMassG = ["rice": 80, "chicken_breast": 100]
        fx.groundTruthTotalCarbsG = 22
        fx.capturePathCanonical = "single_view_lidar"
        return fx
    }
}
#endif
