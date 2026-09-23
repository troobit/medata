import simd
import XCTest
@testable import CaptureKit
@testable import PortableContracts

final class SimdAdapterTests: XCTestCase {
    func testVec3RoundTripBitEqual() {
        let original = Vec3(1.5, -2.5, 3.5)
        let s: simd_float3 = original.simd
        let back = Vec3(s)
        XCTAssertEqual(original, back, "Vec3 ↔ simd_float3 must be bit-equal round-trip")
    }

    func testMat4RoundTripBitEqual() {
        let original = Mat4(columns: [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ])
        let s: simd_float4x4 = original.simd
        // simd is column-major: s.columns.0 == column 0 = [1, 2, 3, 4].
        XCTAssertEqual(s.columns.0, simd_float4(1, 2, 3, 4))
        XCTAssertEqual(s.columns.3, simd_float4(13, 14, 15, 16))
        let back = Mat4(s)
        XCTAssertEqual(original, back, "Mat4 ↔ simd_float4x4 must be bit-equal round-trip")
    }
}
