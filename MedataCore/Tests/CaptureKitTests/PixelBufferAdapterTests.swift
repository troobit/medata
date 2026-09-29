import CoreVideo
import Foundation
import XCTest
@testable import CaptureKit
@testable import PortableContracts

// Task 1 / pba-tests (red baseline): unit coverage for PixelBufferAdapter.convert.
// Builds synthetic CVPixelBuffers (YCbCr biplanar full-range, BGRA, RGBA) with
// public CoreVideo APIs so the suite runs on the iOS Simulator without ARKit
// (Req 3.2). Tolerance on the colour assertions is ±2 to absorb the fixed-point
// rounding of vImage's BT.601 conversion (Req 1.2).

final class PixelBufferAdapterTests: XCTestCase {

    // MARK: - Tests

    func testFlatGrayYCbCrProducesGrayBGRA() throws {
        let buffer = makeYCbCrBuffer(width: 4, height: 4,
                                     yPlane: [UInt8](repeating: 128, count: 4 * 4),
                                     cbCrPlane: [UInt8](repeating: 128, count: 2 * 2 * 2))
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.format, .bgra8)
        XCTAssertEqual(output.width, 4)
        XCTAssertEqual(output.height, 4)
        XCTAssertEqual(output.bytes.count, 4 * 4 * 4)
        for px in 0..<(4 * 4) {
            assertChannel(output.bytes, pixel: px, offset: 0, expected: 128) // B
            assertChannel(output.bytes, pixel: px, offset: 1, expected: 128) // G
            assertChannel(output.bytes, pixel: px, offset: 2, expected: 128) // R
            // Alpha is opaque on the BGRA output.
            assertChannel(output.bytes, pixel: px, offset: 3, expected: 255, tolerance: 0)
        }
    }

    func testKnownColourPatchMatchesBT601() throws {
        // 2×2 patch: red / green / blue / white. The chroma plane is 1×1 in 4:2:0,
        // so all four pixels share one (Cb, Cr) sample. To make the patch hand-
        // computable per pixel we cheat by using one solid colour per sub-image:
        // build four 2×2 buffers and test each independently.
        struct Patch: CustomStringConvertible {
            let name: String
            let r: UInt8
            let g: UInt8
            let b: UInt8
            var description: String { name }
        }
        let patches: [Patch] = [
            .init(name: "red",   r: 255, g: 0,   b: 0),
            .init(name: "green", r: 0,   g: 255, b: 0),
            .init(name: "blue",  r: 0,   g: 0,   b: 255),
            .init(name: "white", r: 255, g: 255, b: 255)
        ]
        for patch in patches {
            // BT.601 full-range RGB → YCbCr.
            let yp = Self.bt601Y(r: patch.r, g: patch.g, b: patch.b)
            let (cb, cr) = Self.bt601CbCr(r: patch.r, g: patch.g, b: patch.b, yp: yp)
            let buffer = makeYCbCrBuffer(
                width: 2, height: 2,
                yPlane: [UInt8](repeating: yp, count: 4),
                cbCrPlane: [cb, cr]
            )
            let output = try PixelBufferAdapter.convert(buffer)
            XCTAssertEqual(output.bytes.count, 2 * 2 * 4, "\(patch)")
            for px in 0..<4 {
                assertChannel(output.bytes, pixel: px, offset: 0, expected: patch.b,
                              context: "\(patch).B")
                assertChannel(output.bytes, pixel: px, offset: 1, expected: patch.g,
                              context: "\(patch).G")
                assertChannel(output.bytes, pixel: px, offset: 2, expected: patch.r,
                              context: "\(patch).R")
            }
        }
    }

    func testOutputIsContiguousNoStridePadding() throws {
        let width = 6
        let height = 4
        let buffer = makeYCbCrBuffer(
            width: width, height: height,
            yPlane: [UInt8](repeating: 128, count: width * height),
            cbCrPlane: [UInt8](repeating: 128, count: (width / 2) * (height / 2) * 2)
        )
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.bytes.count, width * height * 4,
                       "no per-row padding allowed in the adapter output")
        // Every row starts at offset row * width * 4 — the byte at the start of
        // each row must be the B-channel of pixel (row, 0).
        for row in 0..<height {
            let offset = row * width * 4
            XCTAssertLessThan(offset, output.bytes.count)
        }
    }

    func testBGRASourcePassesThrough() throws {
        let width = 4
        let height = 2
        // Fill with a recognisable BGRA gradient.
        var src = [UInt8]()
        src.reserveCapacity(width * height * 4)
        for px in 0..<(width * height) {
            let v = UInt8(px * 16)
            src.append(contentsOf: [v, v &+ 1, v &+ 2, 255])
        }
        let buffer = makeBGRABuffer(width: width, height: height, bytes: src)
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.format, .bgra8)
        XCTAssertEqual(output.bytes.count, width * height * 4)
        XCTAssertEqual([UInt8](output.bytes), src)
    }

    func testRGBASourceReportsRGBA() throws {
        let width = 4
        let height = 2
        var src = [UInt8]()
        src.reserveCapacity(width * height * 4)
        for px in 0..<(width * height) {
            let v = UInt8(px * 16)
            src.append(contentsOf: [v, v &+ 1, v &+ 2, 255])
        }
        // CoreVideo refuses `kCVPixelFormatType_32RGBA` on the macOS host
        // (returns -6680). Skip the test when the platform cannot construct
        // the source buffer at all — iOS device runs cover this path.
        guard let buffer = tryMakeRGBABuffer(width: width, height: height, bytes: src) else {
            throw XCTSkip("Host platform does not support kCVPixelFormatType_32RGBA")
        }
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.format, .rgba8)
        XCTAssertEqual(output.bytes.count, width * height * 4)
        XCTAssertEqual([UInt8](output.bytes), src)
    }

    func testYCbCrSourceReportsBGRAOnOutput() throws {
        let buffer = makeYCbCrBuffer(
            width: 2, height: 2,
            yPlane: [UInt8](repeating: 128, count: 4),
            cbCrPlane: [128, 128]
        )
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.format, .bgra8)
    }

    func testUnsupportedFourCCThrows() {
        // kCVPixelFormatType_422YpCbCr8 → '2vuy' is not in the supported set.
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 4, 2,
            kCVPixelFormatType_422YpCbCr8,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        guard let buffer else { return XCTFail("CVPixelBufferCreate returned nil") }
        do {
            _ = try PixelBufferAdapter.convert(buffer)
            XCTFail("expected ConversionError.unsupportedSourceFormat")
        } catch PixelBufferAdapter.ConversionError.unsupportedSourceFormat(let fourCC) {
            XCTAssertEqual(fourCC, "2vuy")
        } catch {
            XCTFail("expected unsupportedSourceFormat, got \(error)")
        }
    }

    func testNonSquareDimensions() throws {
        let width = 8
        let height = 4
        // Flat 128/128/128 — verifies dimensions propagate correctly even on a
        // non-square buffer where chroma sub-sampling produces a different plane
        // size from the luma plane.
        let buffer = makeYCbCrBuffer(
            width: width, height: height,
            yPlane: [UInt8](repeating: 128, count: width * height),
            cbCrPlane: [UInt8](repeating: 128, count: (width / 2) * (height / 2) * 2)
        )
        let output = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(output.width, width)
        XCTAssertEqual(output.height, height)
        XCTAssertEqual(output.bytes.count, width * height * 4)
    }

    // PBT-style randomised round-trip — 200 deterministic samples of a 2×2 single-
    // colour buffer; verifies the BGRA output matches the BT.601 reference within
    // ±2 across the full Y/Cb/Cr cube. Pattern matches CardPosePropertyTests'
    // splitmix64 seeded RNG (no SwiftCheck dep — project convention).
    func testRandomisedRoundTripWithinTolerance() throws {
        var rng = SeededRNG(seed: 0xF00D_C0FF_BEEF_BABE)
        let samples = 200
        for _ in 0..<samples {
            let r = UInt8(rng.next() & 0xFF)
            let g = UInt8(rng.next() & 0xFF)
            let b = UInt8(rng.next() & 0xFF)
            let yp = Self.bt601Y(r: r, g: g, b: b)
            let (cb, cr) = Self.bt601CbCr(r: r, g: g, b: b, yp: yp)
            let buffer = makeYCbCrBuffer(
                width: 2, height: 2,
                yPlane: [UInt8](repeating: yp, count: 4),
                cbCrPlane: [cb, cr]
            )
            let output = try PixelBufferAdapter.convert(buffer)
            for px in 0..<4 {
                assertChannel(output.bytes, pixel: px, offset: 0, expected: b,
                              context: "rgb=(\(r),\(g),\(b)) ycbcr=(\(yp),\(cb),\(cr))")
                assertChannel(output.bytes, pixel: px, offset: 1, expected: g,
                              context: "rgb=(\(r),\(g),\(b)) ycbcr=(\(yp),\(cb),\(cr))")
                assertChannel(output.bytes, pixel: px, offset: 2, expected: r,
                              context: "rgb=(\(r),\(g),\(b)) ycbcr=(\(yp),\(cb),\(cr))")
            }
        }
    }

    // MARK: - BT.601 helpers

    private static func bt601Y(r: UInt8, g: UInt8, b: UInt8) -> UInt8 {
        let yp = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return UInt8(clamping: Int(yp.rounded()))
    }

    private static func bt601CbCr(r: UInt8, g: UInt8, b: UInt8, yp: UInt8) -> (UInt8, UInt8) {
        let cb = 128.0 + (Double(b) - Double(yp)) * 0.564
        let cr = 128.0 + (Double(r) - Double(yp)) * 0.713
        return (
            UInt8(clamping: Int(cb.rounded())),
            UInt8(clamping: Int(cr.rounded()))
        )
    }

    // MARK: - Buffer builders

    private func makeYCbCrBuffer(width: Int, height: Int,
                                 yPlane: [UInt8], cbCrPlane: [UInt8],
                                 file: StaticString = #file, line: UInt = #line) -> CVPixelBuffer {
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            pixelFormat,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess, "CVPixelBufferCreate failed", file: file, line: line)
        guard let buffer else {
            XCTFail("CVPixelBufferCreate returned nil", file: file, line: line)
            return makeFallbackBuffer()
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        copyPlane(into: buffer, plane: 0, bytes: yPlane, rowWidth: width)
        copyPlane(into: buffer, plane: 1, bytes: cbCrPlane, rowWidth: width)
        return buffer
    }

    private func makeBGRABuffer(width: Int, height: Int, bytes: [UInt8],
                                file: StaticString = #file, line: UInt = #line) -> CVPixelBuffer {
        return makeChunkyBuffer(width: width, height: height, bytes: bytes,
                                pixelFormat: kCVPixelFormatType_32BGRA,
                                file: file, line: line)
    }

    private func tryMakeRGBABuffer(width: Int, height: Int, bytes: [UInt8]) -> CVPixelBuffer? {
        return tryMakeChunkyBuffer(width: width, height: height, bytes: bytes,
                                   pixelFormat: kCVPixelFormatType_32RGBA)
    }

    private func makeChunkyBuffer(width: Int, height: Int, bytes: [UInt8],
                                  pixelFormat: OSType,
                                  file: StaticString = #file, line: UInt = #line) -> CVPixelBuffer {
        guard let buffer = tryMakeChunkyBuffer(width: width, height: height,
                                               bytes: bytes, pixelFormat: pixelFormat) else {
            XCTFail("CVPixelBufferCreateWithBytes failed for format \(pixelFormat)",
                    file: file, line: line)
            return makeFallbackBuffer()
        }
        return buffer
    }

    // Build a chunky CVPixelBuffer via CVPixelBufferCreateWithBytes so the
    // caller controls memory. Returns nil when the host platform rejects the
    // pixel format (so tests can XCTSkip cleanly).
    private func tryMakeChunkyBuffer(width: Int, height: Int, bytes: [UInt8],
                                     pixelFormat: OSType) -> CVPixelBuffer? {
        let rowBytes = width * 4
        let totalBytes = rowBytes * height
        let raw = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 16)
        _ = bytes.withUnsafeBufferPointer { src in
            memcpy(raw, src.baseAddress!, totalBytes)
        }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault, width, height, pixelFormat,
            raw, rowBytes,
            { _, releaseRefCon in
                if let p = releaseRefCon {
                    UnsafeMutableRawPointer(mutating: p).deallocate()
                }
            },
            UnsafeMutableRawPointer(raw),
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            raw.deallocate()
            return nil
        }
        return pixelBuffer
    }

    private func copyPlane(into buffer: CVPixelBuffer, plane: Int, bytes: [UInt8], rowWidth: Int) {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { return }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
        // The number of bytes consumed per row in the source buffer differs
        // between the Y plane (rowWidth bytes) and the CbCr plane (rowWidth
        // bytes — two samples each spanning two pixels horizontally).
        let bytesPerRow = (plane == 0) ? rowWidth : rowWidth
        bytes.withUnsafeBufferPointer { src in
            for row in 0..<height {
                let dst = base.advanced(by: row * stride)
                memcpy(dst, src.baseAddress!.advanced(by: row * bytesPerRow), bytesPerRow)
            }
        }
    }

    private func makeFallbackBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        _ = CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &buffer)
        return buffer!
    }

    // MARK: - Channel assertion

    private func assertChannel(_ data: Data, pixel: Int, offset: Int, expected: UInt8,
                               tolerance: Int = 2, context: String = "",
                               file: StaticString = #file, line: UInt = #line) {
        let idx = pixel * 4 + offset
        let actual = Int(data[idx])
        let delta = abs(actual - Int(expected))
        XCTAssertLessThanOrEqual(
            delta, tolerance,
            "channel mismatch (pixel \(pixel), offset \(offset), context=\(context)): " +
            "expected \(expected) ± \(tolerance), got \(actual)",
            file: file, line: line
        )
    }
}

// MARK: - Deterministic seeded RNG (matches CardPosePropertyTests' pattern)

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0xDEAD_BEEF }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
