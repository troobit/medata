import CoreVideo
import Foundation
import XCTest
@testable import CaptureKit
@testable import PortableContracts
@testable import Segmentation

// Task 3 / pba-integration: cross-target regression sentinel that locks the
// `PixelBufferAdapter` → `SegmenterPreProcessor` contract from
// `specs/rawframe-rgb-conversion/requirements.md#5.1`. Asserts the typical
// 1920×1440 capture handoff flows through both APIs without raising
// `SegmentationError.invalidInputDimensions`, and that the pre-processor's
// FP16 output has the expected `targetSize × targetSize × 3` byte count.
//
// The synthetic YCbCr buffer is built locally rather than reused from
// `PixelBufferAdapterTests` to keep this test target free of any internal
// helper dependency (CaptureKit is the only shared dependency); the buffer
// helpers mirror the ones used in that test for readability.
final class PreProcessorAcceptsAdapterOutputTests: XCTestCase {

    func testAdapterOutputFeedsPreProcessor() throws {
        let width = 1920
        let height = 1440
        let buffer = try makeFlatYCbCrBuffer(width: width, height: height, y: 128, cb: 128, cr: 128)

        let adapterOutput = try PixelBufferAdapter.convert(buffer)
        XCTAssertEqual(adapterOutput.format, .bgra8)
        XCTAssertEqual(adapterOutput.width, width)
        XCTAssertEqual(adapterOutput.height, height)
        XCTAssertEqual(adapterOutput.bytes.count, width * height * 4)

        let targetSize = SegmenterPreProcessor.defaultTargetSize
        let processed = try SegmenterPreProcessor.process(
            imageBytes: adapterOutput.bytes,
            pixelFormat: adapterOutput.format,
            width: adapterOutput.width,
            height: adapterOutput.height,
            targetSize: targetSize
        )
        // FP16 (2 bytes per element), 3 channels per pixel.
        XCTAssertEqual(processed.bytes.count, targetSize * targetSize * 3 * 2)
        XCTAssertEqual(processed.targetSize, targetSize)
        XCTAssertEqual(processed.originalWidth, width)
        XCTAssertEqual(processed.originalHeight, height)
    }

    // MARK: - Helpers

    private func makeFlatYCbCrBuffer(width: Int, height: Int,
                                     y: UInt8, cb: UInt8, cr: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ] as CFDictionary,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        guard let buffer else {
            throw NSError(domain: "PreProcessorAcceptsAdapterOutputTests",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate returned nil"])
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let h = CVPixelBufferGetHeightOfPlane(buffer, 0)
            for row in 0..<h {
                memset(yBase.advanced(by: row * stride), Int32(y), width)
            }
        }
        if let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let h = CVPixelBufferGetHeightOfPlane(buffer, 1)
            let cw = CVPixelBufferGetWidthOfPlane(buffer, 1)
            for row in 0..<h {
                let dst = cbcrBase.advanced(by: row * stride)
                for col in 0..<cw {
                    dst.advanced(by: col * 2).storeBytes(of: cb, as: UInt8.self)
                    dst.advanced(by: col * 2 + 1).storeBytes(of: cr, as: UInt8.self)
                }
            }
        }
        return buffer
    }
}
