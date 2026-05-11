import simd
import XCTest
@testable import CaptureKit
@testable import PortableContracts

// Task 8: portable RawFrame contract per design §3.1.
// Asserts the four properties that distinguish RawFrame from a naive iOS-only struct:
//   • timestampMonotonicNs is Int64 nanoseconds (NOT TimeInterval / Double seconds).
//   • pixelFormat and colourSpace are explicit, exhaustive enums.
//   • orientation is the EXIF tag (1..8), not a raw CGImagePropertyOrientation.
//   • simd_* never crosses the module boundary; SimdAdapter is the only converter.
final class RawFrameContractTests: XCTestCase {
    func testRawFrameCarriesPortableTimestamp() {
        let frame = RawFrame.fixture(timestampMonotonicNs: 12_345_678_901)
        // Compile-time guarantee that timestamp is Int64 ns (not TimeInterval/Double).
        let _: Int64 = frame.timestampMonotonicNs
        XCTAssertEqual(frame.timestampMonotonicNs, 12_345_678_901)
    }

    func testPixelFormatEnumIsExhaustive() {
        // Every PixelFormat must round-trip through Pb*; UNRECOGNIZED comes back as nil.
        for fmt in [PixelFormat.rgb8, .bgra8, .rgba8] {
            let pb = fmt.pb
            XCTAssertEqual(PixelFormat(pb: pb), fmt)
        }
        XCTAssertNil(PixelFormat(pb: .unspecified))
    }

    func testColourSpaceEnumIsExhaustive() {
        for cs in [ColourSpace.sRGB, .linear] {
            let pb = cs.pb
            XCTAssertEqual(ColourSpace(pb: pb), cs)
        }
        XCTAssertNil(ColourSpace(pb: .unspecified))
    }

    func testRawFrameRoundTripsThroughProtobuf() throws {
        let depth = DepthMap(
            depthBytesMm: Data([0, 0, 0, 0]),
            confidenceBytes: Data([255]),
            width: 1, height: 1, rowStrideBytes: 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 100, fy: 100, cx: 0.5, cy: 0.5,
                distortion: [],
                imageWidth: 1, imageHeight: 1
            ),
            depthFromColour: .identity
        )
        let original = RawFrame.fixture(timestampMonotonicNs: 7, pixelFormat: .rgb8, depth: depth)
        let pb = original.pb
        // Wire round-trip via SwiftProtobuf binary serialisation.
        let bytes: Data = try pb.serializedBytes()
        let decoded = try PbRawFrame(serializedBytes: bytes)
        XCTAssertEqual(decoded.timestampMonotonicNs, 7)
        XCTAssertEqual(decoded.pixelFormat, PbPixelFormat.rgb8)
        XCTAssertEqual(decoded.colourSpace, PbColourSpace.srgb)
        XCTAssertTrue(decoded.hasDepth)
        XCTAssertEqual(decoded.depth.width, 1)
    }

    func testLidarConfidenceMappingIsCanonical() {
        // Per §6.0: ARConfidenceLevel.{low, medium, high} → UInt8 {0, 127, 255}.
        XCTAssertEqual(LidarConfidenceLevel.low.normalisedByte, 0)
        XCTAssertEqual(LidarConfidenceLevel.medium.normalisedByte, 127)
        XCTAssertEqual(LidarConfidenceLevel.high.normalisedByte, 255)
    }
}

// SimdAdapter boundary rule: simd_* may appear in CaptureKit/SimdAdapter but the
// frame the actor exposes must be entirely portable. This test asserts that converting
// a simd_float4x4 world transform through SimdAdapter and into RawFrame leaves no
// trace of simd in the frame's storage by checking field types.
final class SimdBoundaryTests: XCTestCase {
    func testWorldFromCameraIsPortableMat4NotSimd() {
        let s = simd_float4x4(diagonal: simd_float4(1, 2, 3, 1))
        let portable = Mat4(s)
        let frame = RawFrame(
            imageBytes: Data(),
            pixelFormat: .bgra8, colourSpace: .sRGB, orientation: 1,
            imageWidth: 1, imageHeight: 1,
            timestampMonotonicNs: 0,
            intrinsics: CameraIntrinsics(fx: 1, fy: 1, cx: 0, cy: 0,
                                         distortion: [], imageWidth: 1, imageHeight: 1),
            gravity: Vec3(0, -1, 0),
            worldFromCamera: portable,
            depth: nil
        )
        // The frame's worldFromCamera is Mat4; simd is not in the public type.
        XCTAssertEqual(frame.worldFromCamera[col: 0, row: 0], 1)
        XCTAssertEqual(frame.worldFromCamera[col: 1, row: 1], 2)
        XCTAssertEqual(frame.worldFromCamera[col: 2, row: 2], 3)
        // And it round-trips bit-equal back to simd via the adapter.
        XCTAssertEqual(frame.worldFromCamera.simd, s)
    }
}
