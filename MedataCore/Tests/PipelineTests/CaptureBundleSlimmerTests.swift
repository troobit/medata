import Foundation
import PortableContracts
import XCTest
@testable import Pipeline

// Tests for the wire-level capture-bundle slimmer
// (specs/estimation/ml-feedback-loop Req 3.6, design "Device storage budget and
// slimming").
//
// At ~390 MB per two-view success a three-day field session outruns the phone.
// Slimming drops the probability tensors — almost all of that mass — and keeps
// everything the geometry replays from: image, depth, argmax, intrinsics,
// gravity and the pre-shutter mask. A slimmed bundle is replayable for geometry
// and class identity, and no longer re-scorable; that trade is the point.
//
// `Fixtures/mini-bundle.fixture` is a committed hand-encoded PbMealFixture:
// a 4x3 colour grid, a 2x2 depth grid, four classes, and both probability
// tensors present at H*W*C*2 bytes each. It is hand-encoded rather than
// produced by SwiftProtobuf on purpose — the slimmer is asserted against real
// wire bytes it did not write.
final class CaptureBundleSlimmerTests: XCTestCase {

    private var tempDir: URL!
    private var bundleURL: URL!
    private var originalBytes: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlimmerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let source = try XCTUnwrap(
            Bundle.module.url(forResource: "mini-bundle", withExtension: "fixture",
                              subdirectory: "Fixtures"),
            "the committed miniature bundle must ship with the test target"
        )
        originalBytes = try Data(contentsOf: source)
        bundleURL = tempDir.appendingPathComponent("1785135663727-success.fixture")
        try originalBytes.write(to: bundleURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private var markerURL: URL {
        bundleURL.deletingPathExtension().appendingPathExtension(
            CaptureBundleSlimmer.markerExtension)
    }

    private func slimmedFixture() throws -> PbMealFixture {
        try PbMealFixture(serializedBytes: try Data(contentsOf: bundleURL))
    }

    // MARK: - What survives, what goes

    func testSlimmedBundleStillLoadsWithGeometryIntactAndProbabilitiesGone() throws {
        let before = try PbMealFixture(serializedBytes: originalBytes)
        XCTAssertFalse(before.nadirProbs.isEmpty, "the source bundle carries probabilities")
        XCTAssertFalse(before.obliqueProbs.isEmpty)

        _ = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)
        let after = try slimmedFixture()

        XCTAssertTrue(after.nadirProbs.isEmpty, "probability tensors are dropped")
        XCTAssertTrue(after.obliqueProbs.isEmpty)

        // Replayable for geometry and class identity (Req 3.6).
        XCTAssertEqual(after.nadirImage, before.nadirImage)
        XCTAssertEqual(after.obliqueImage, before.obliqueImage)
        XCTAssertEqual(after.nadirDepth, before.nadirDepth)
        XCTAssertEqual(after.nadirArgmax, before.nadirArgmax)
        XCTAssertEqual(after.obliqueArgmax, before.obliqueArgmax)
        XCTAssertEqual(after.nadirIntrinsics, before.nadirIntrinsics)
        XCTAssertEqual(after.obliqueIntrinsics, before.obliqueIntrinsics)
        XCTAssertEqual(after.gravity, before.gravity)
        XCTAssertEqual(after.t1To2, before.t1To2)
        XCTAssertEqual(after.preShutterMask, before.preShutterMask)
        XCTAssertEqual(after.capturePathCanonical, before.capturePathCanonical)
        XCTAssertEqual(after.segmenterCheckpointSha256, before.segmenterCheckpointSha256)
        XCTAssertEqual(after.databaseEdition, before.databaseEdition)
    }

    func testFixtureRevisionIsNotMutated() throws {
        // The revision versions the SCHEMA; the sidecar marks the content
        // state. Bumping the revision here would tell every reader the fixture
        // format changed, which it did not.
        _ = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)
        XCTAssertEqual(try slimmedFixture().fixtureRevision, "rev-1")
    }

    func testEveryRetainedByteIsPreservedVerbatim() throws {
        // The mechanism is a varint field skip, not a decode-and-re-encode: the
        // output must be the input with exactly the two probability records
        // excised, byte for byte. A round-trip through SwiftProtobuf could
        // renormalise or reorder and still pass the field-by-field checks
        // above — this is what says it did not happen.
        _ = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)
        let after = try Data(contentsOf: bundleURL)

        var expected = Data()
        for field in try CaptureBundleSlimmer.topLevelFieldRanges(originalBytes)
        where !CaptureBundleSlimmer.droppedFieldNumbers.contains(field.number) {
            expected.append(originalBytes.subdata(in: field.range))
        }
        XCTAssertEqual(after, expected)
    }

    // MARK: - File handling

    func testSlimmingReplacesInPlaceAndLeavesNoTemporaryBehind() throws {
        _ = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)

        let names = try FileManager.default
            .contentsOfDirectory(atPath: tempDir.path).sorted()
        XCTAssertEqual(names, ["1785135663727-success.fixture",
                               "1785135663727-success.slimmed"],
                       "temp-file plus atomic replace leaves the bundle path and its marker only")
        XCTAssertLessThan(try Data(contentsOf: bundleURL).count, originalBytes.count)
    }

    func testMarkerRecordsWhatWasDroppedBesideTheBundle() throws {
        let result = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        let marker = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(marker.contains("fields_dropped=9,10"), marker)
        XCTAssertTrue(marker.contains("bytes_before=\(originalBytes.count)"), marker)
        XCTAssertTrue(marker.contains("bytes_after=\(result.bytesAfter)"), marker)
        XCTAssertEqual(result.bytesBefore, originalBytes.count)
        XCTAssertGreaterThan(result.bytesBefore - result.bytesAfter, 0)
    }

    func testSlimmingAnAlreadySlimBundleIsANoOp() throws {
        _ = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)
        let once = try Data(contentsOf: bundleURL)

        // Oldest-first sweeps re-encounter bundles; a second pass must neither
        // fail nor rewrite, or the maintenance task would churn the disk it is
        // trying to free.
        let second = try CaptureBundleSlimmer.slim(bundleAt: bundleURL)
        XCTAssertTrue(second.alreadySlim)
        XCTAssertEqual(second.bytesBefore, second.bytesAfter)
        XCTAssertEqual(try Data(contentsOf: bundleURL), once)
    }

    func testAMalformedBundleThrowsRatherThanTruncatingTheOriginal() throws {
        // A bundle still being written, or corrupted on disk: the failure must
        // leave the file exactly as found. Silently replacing it with a
        // partially-parsed prefix would destroy field data irrecoverably.
        let junk = Data([0x0A, 0xFF, 0xFF, 0xFF])   // field 1, length runs off the end
        try junk.write(to: bundleURL)
        XCTAssertThrowsError(try CaptureBundleSlimmer.slim(bundleAt: bundleURL))
        XCTAssertEqual(try Data(contentsOf: bundleURL), junk)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testAnOversizedLengthThrowsRatherThanTrappingTheProcess() throws {
        // A corrupt length is data, not a programming error. `Int(varint)`
        // would trap and take the whole app down over one bad file.
        let huge = Data([0x0A] + [UInt8](repeating: 0xFF, count: 9) + [0x01])
        try huge.write(to: bundleURL)
        XCTAssertThrowsError(try CaptureBundleSlimmer.slim(bundleAt: bundleURL))
        XCTAssertEqual(try Data(contentsOf: bundleURL), huge)
    }
}
