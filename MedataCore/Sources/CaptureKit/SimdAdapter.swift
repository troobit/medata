import Foundation
import PortableContracts
import simd

// simd ↔ portable bridges. Lives in CaptureKit only — every other module consumes
// the portable Vec3 / Mat4 types directly (per task 5 / design §6.0 boundary rule).
//
// simd_float4x4 is column-major; columns are simd_float4 values. This matches the
// portable Mat4 column-major contract exactly, so the conversion is a copy of
// 16 floats with no reshuffling.
public extension Vec3 {
    init(_ s: simd_float3) {
        self.init(s.x, s.y, s.z)
    }

    var simd: simd_float3 { simd_float3(x, y, z) }
}

public extension Mat4 {
    init(_ s: simd_float4x4) {
        self.init(columns: [
            [s.columns.0.x, s.columns.0.y, s.columns.0.z, s.columns.0.w],
            [s.columns.1.x, s.columns.1.y, s.columns.1.z, s.columns.1.w],
            [s.columns.2.x, s.columns.2.y, s.columns.2.z, s.columns.2.w],
            [s.columns.3.x, s.columns.3.y, s.columns.3.z, s.columns.3.w]
        ])
    }

    var simd: simd_float4x4 {
        simd_float4x4(
            simd_float4(columns[0][0], columns[0][1], columns[0][2], columns[0][3]),
            simd_float4(columns[1][0], columns[1][1], columns[1][2], columns[1][3]),
            simd_float4(columns[2][0], columns[2][1], columns[2][2], columns[2][3]),
            simd_float4(columns[3][0], columns[3][1], columns[3][2], columns[3][3])
        )
    }
}
