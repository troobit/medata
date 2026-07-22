import XCTest
@testable import Segmentation
@testable import CaptureKit
import PortableContracts

/// Canned inference engine for Core ML segmenter tests. Returns caller-supplied logits
/// so the test can drive the pre/post pipeline without loading a real Core ML model.
/// (Renamed from `StubInferenceEngine` to avoid clashing with the public
/// `Segmentation.StubInferenceEngine` used by Phase 1 dev builds, Req §23.2.)
final class CannedInferenceEngine: SegmenterInferenceEngine, @unchecked Sendable {
    let classes: Int
    let builder: (Int) -> [Float]
    private(set) var calls = 0
    private(set) var lastInputBytes: Data?
    private(set) var lastTargetSize: Int = 0

    init(classes: Int, builder: @escaping (Int) -> [Float]) {
        self.classes = classes
        self.builder = builder
    }

    func runInference(inputFP16Bytes: Data, targetSize: Int) async throws -> (logits: [Float], classes: Int) {
        calls += 1
        lastInputBytes = inputFP16Bytes
        lastTargetSize = targetSize
        return (builder(targetSize), classes)
    }
}

final class CoreMLSegmenterTests: XCTestCase {

    // The `segmenter.mask` diagnostic MUST default to `.perCapture` (persisted
    // `.info`) so the Pipeline's shutter-time capture stays visible on device.
    // Only the pre-shutter live path opts into `.livePreview` (`.debug`) to avoid
    // flooding the persisted store. A regression flipping this default would
    // silently drop the on-device capture diagnostic. Bug `capture-log-flood-…`.
    func testMaskLogDefaultsToPerCapture() {
        let seg = CoreMLSegmenter(
            modelPath: "/dev/null",
            palette: makeTestPalette(),
            engine: CannedInferenceEngine(classes: 4) { _ in [] }
        )
        XCTAssertEqual(seg.maskLog, .perCapture)
    }

    private func makeTestPalette(numFoodClasses: Int = 2) -> ClassPalette {
        ClassPalette(
            foodClasses: (0..<numFoodClasses).map { "food_\($0)" },
            background: numFoodClasses,
            unknownFood: numFoodClasses + 1,
            unsupportedLiquid: numFoodClasses + 2,
            version: "test_v1"
        )
    }

    private func makeFrame(width: Int, height: Int, pixelFormat: PixelFormat) -> RawFrame {
        let bytesPerPixel = (pixelFormat == .rgb8) ? 3 : 4
        let intrinsics = CameraIntrinsics(
            fx: 1500, fy: 1500, cx: Float(width) / 2, cy: Float(height) / 2,
            distortion: [], imageWidth: width, imageHeight: height
        )
        return RawFrame(
            imageBytes: Data(repeating: 128, count: width * height * bytesPerPixel),
            pixelFormat: pixelFormat,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: width, imageHeight: height,
            timestampMonotonicNs: 1_000_000_000,
            intrinsics: intrinsics,
            gravity: Vec3(0, -1, 0),
            worldFromCamera: .identity,
            depth: nil
        )
    }

    // MARK: - String path (P8)

    func testModelPathIsStringNotURL() {
        let palette = makeTestPalette()
        let engine = CannedInferenceEngine(classes: palette.totalClasses) { ts in
            [Float](repeating: 0, count: ts * ts * palette.totalClasses)
        }
        let path = "/some/bundled/segmenter.mlpackage"
        let segmenter = CoreMLSegmenter(modelPath: path, palette: palette, engine: engine)
        XCTAssertEqual(segmenter.modelPathString, path)
    }

    // MARK: - Portable byte layout regardless of inference backend

    func testProducesPortableFP16LEByteLayout() async throws {
        let palette = makeTestPalette()
        let targetSize = 8
        let classes = palette.totalClasses
        let engine = CannedInferenceEngine(classes: classes) { ts in
            // All pixels favour food_0 (class 0).
            var logits = [Float](repeating: 0, count: ts * ts * classes)
            for i in 0..<(ts * ts) { logits[i * classes + 0] = 12 }
            return logits
        }
        let segmenter = CoreMLSegmenter(
            modelPath: "/tmp/fake.mlpackage", palette: palette, engine: engine, targetSize: targetSize
        )
        let frame = makeFrame(width: 16, height: 16, pixelFormat: .rgb8)
        let result = try await segmenter.segment(frame)

        XCTAssertEqual(result.probabilities.height, 16)
        XCTAssertEqual(result.probabilities.width, 16)
        XCTAssertEqual(result.probabilities.classes, classes)
        // Portable contract: bytes are FP16 LE HWC row-major — size is H × W × C × 2.
        XCTAssertEqual(result.probabilities.bytes.count, 16 * 16 * classes * 2)
        // Argmax labels every pixel as class 0.
        XCTAssertTrue(result.argmax.pixels.allSatisfy { $0 == 0 })
    }

    func testInferenceRunsOnPreProcessedFP16Input() async throws {
        let palette = makeTestPalette()
        let targetSize = 32
        let classes = palette.totalClasses
        let engine = CannedInferenceEngine(classes: classes) { ts in
            var logits = [Float](repeating: 0, count: ts * ts * classes)
            for i in 0..<(ts * ts) { logits[i * classes + 0] = 12 }
            return logits
        }
        let segmenter = CoreMLSegmenter(
            modelPath: "stub", palette: palette, engine: engine, targetSize: targetSize
        )
        let frame = makeFrame(width: 64, height: 32, pixelFormat: .bgra8)
        _ = try await segmenter.segment(frame)
        // Inference is invoked exactly once with the FP16 LE buffer (HWC row-major).
        XCTAssertEqual(engine.calls, 1)
        XCTAssertEqual(engine.lastTargetSize, targetSize)
        XCTAssertEqual(engine.lastInputBytes?.count, targetSize * targetSize * 3 * 2)
    }

    // MARK: - Weights budget (Req 8.2)

    func testWeightsBudget_PassesWhenUnderBudget() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seg-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 1 * 1024 * 1024).write(to: url)
        XCTAssertNoThrow(try SegmenterWeightsBudget.validate(at: url.path))
    }

    func testWeightsBudget_ThrowsWhenAboveBudget() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seg-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: SegmenterWeightsBudget.maxBytes + 1).write(to: url)
        XCTAssertThrowsError(try SegmenterWeightsBudget.validate(at: url.path)) { error in
            guard case .weightsBudgetExceeded(let actual, let max_) = error as? SegmentationError else {
                return XCTFail("expected weightsBudgetExceeded, got \(error)")
            }
            XCTAssertGreaterThan(actual, max_)
        }
    }

    func testWeightsBudget_WalksDirectoryRecursively() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Two 1 MB files inside a directory: total 2 MB — within budget.
        try Data(repeating: 0, count: 1 * 1024 * 1024).write(to: dir.appendingPathComponent("a"))
        try Data(repeating: 0, count: 1 * 1024 * 1024).write(to: dir.appendingPathComponent("b"))
        let total = try SegmenterWeightsBudget.totalBytes(at: dir)
        XCTAssertEqual(total, 2 * 1024 * 1024)
        XCTAssertNoThrow(try SegmenterWeightsBudget.validate(at: dir.path))
    }
}

#if canImport(CoreML) && (os(iOS) || os(macOS))
import CoreML

// Regression: specs/bugfixes/segmenter-output-stride-ignored.
//
// Core ML returns output MLMultiArrays whose rows can be padded for alignment —
// the 513-wide segmenter output comes back with a row stride of 544 elements on
// every compute-unit configuration measured. `unpackLogits` must honour
// `MLMultiArray.strides` rather than assume a densely packed buffer; the dense
// read shifts every row by the padding, shearing the whole logit plane and
// flooding field-capture masks with `unsupported_liquid`.
final class CoreMLLogitsUnpackStrideTests: XCTestCase {

    private func expectedValue(_ c: Int, _ y: Int, _ x: Int) -> Float {
        Float(c * 100 + y * 10 + x)
    }

    private func assertDenseHWC(_ logits: [Float], h: Int, w: Int, classes: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<classes {
                    XCTAssertEqual(
                        logits[(y * w + x) * classes + c], expectedValue(c, y, x),
                        "mismatch at y=\(y) x=\(x) c=\(c) — MLMultiArray strides ignored?",
                        file: file, line: line
                    )
                }
            }
        }
    }

    func testUnpackLogitsHonoursPaddedRowStride_CHW() throws {
        let classes = 3, side = 4, paddedW = 8
        // Row-padded CHW backing buffer; NaN sentinels in the padding so a
        // dense read cannot accidentally produce the right answer.
        var backing = [Float](repeating: .nan, count: classes * side * paddedW)
        for c in 0..<classes {
            for y in 0..<side {
                for x in 0..<side {
                    backing[c * side * paddedW + y * paddedW + x] = expectedValue(c, y, x)
                }
            }
        }
        let logits: [Float] = try backing.withUnsafeMutableBufferPointer { buf in
            let arr = try MLMultiArray(
                dataPointer: UnsafeMutableRawPointer(buf.baseAddress!),
                shape: [1, NSNumber(value: classes), NSNumber(value: side), NSNumber(value: side)],
                dataType: .float32,
                strides: [NSNumber(value: classes * side * paddedW),
                          NSNumber(value: side * paddedW),
                          NSNumber(value: paddedW),
                          1]
            )
            return try CoreMLInferenceEngine.unpackLogits(
                arr, targetSize: side, classes: classes, chw: true
            )
        }
        assertDenseHWC(logits, h: side, w: side, classes: classes)
    }

    func testUnpackLogitsHonoursPaddedRowStride_HWC() throws {
        let classes = 3, side = 4, paddedW = 8
        var backing = [Float](repeating: .nan, count: side * paddedW * classes)
        for y in 0..<side {
            for x in 0..<side {
                for c in 0..<classes {
                    backing[(y * paddedW + x) * classes + c] = expectedValue(c, y, x)
                }
            }
        }
        let logits: [Float] = try backing.withUnsafeMutableBufferPointer { buf in
            let arr = try MLMultiArray(
                dataPointer: UnsafeMutableRawPointer(buf.baseAddress!),
                shape: [1, NSNumber(value: side), NSNumber(value: side), NSNumber(value: classes)],
                dataType: .float32,
                strides: [NSNumber(value: side * paddedW * classes),
                          NSNumber(value: paddedW * classes),
                          NSNumber(value: classes),
                          1]
            )
            return try CoreMLInferenceEngine.unpackLogits(
                arr, targetSize: side, classes: classes, chw: false
            )
        }
        assertDenseHWC(logits, h: side, w: side, classes: classes)
    }
}
#endif
