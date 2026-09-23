import CaptureKit
import Darwin
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Regression coverage for the bugfix at
// `specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/`.
//
// On iPhone 13 Pro Max iOS 26.5 the support-plane fit aborted with
//   `Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8`
// immediately after `event=supportplane.start width=1920 height=1440 fillFraction=0.7`.
// Root cause: `LiDARPlaneFitter.refine` called `LinearAlgebra.svdFull(_, rows: 3, cols: n)`
// where n is the inlier count. `svdFull` requests JOBVT='A' and allocates the full
// n×n V^T matrix (4·n² bytes). With n ≈ 89 720 inliers from a 1920×1440 frame the
// allocation request reaches ~32 GB and the process aborts. `refine` never reads
// `svd.vt`; the entire allocation is wasted.
//
// Two test cases pin the fix:
//
//   1. Correctness at small n: `refine` over 300 synthetic inliers must still
//      return the seed-aligned normal. The existing `LiDARPlaneFitterTests`
//      suite already exercises the full path on a 64×48 fixture; this case
//      anchors the refine() contract directly.
//
//   2. Allocation bound at moderate n: at n = 10 000 the pre-fix `vt` allocation
//      is 10 000² × 4 ≈ 400 MB, which shows up as a ~400 MB jump in resident set
//      size. The post-fix scatter-matrix path allocates 9 floats. The test
//      reads RSS via `mach_task_basic_info` around the call and asserts the
//      delta is well below the pre-fix footprint. Machine-RAM-independent.
@Suite("LiDAR plane refine — scale and equivalence (OOM bugfix)")
struct LiDARPlaneFitterRefineScaleTests {

    @Test("refine recovers the seed normal on a small synthetic inlier set")
    func refineSmallEquivalence() throws {
        // Points on the plane y = 100 mm with mild x/z spread and sub-mm jitter so
        // σ_min/σ_max ≥ 1e-6 holds.
        let seed = Vec3(0, 1, 0)
        var points: [Vec3] = []
        for i in 0..<300 {
            let x = Float(i % 30) - 15
            let z = Float(i / 30) * 2 - 10
            let jitter = sin(Float(i) * 0.3) * 0.05
            points.append(Vec3(x, 100 + jitter, z))
        }
        let (normal, d) = try LiDARPlaneFitter.refine(inliers: points, seedNormal: seed)
        #expect(abs(normal.y) > 0.999,
                "expected y-aligned normal, got (\(normal.x), \(normal.y), \(normal.z))")
        #expect(normal.y > 0, "refine should align with the +y seed")
        #expect(abs(d - 100) < 0.5, "expected d ≈ 100, got \(d)")
    }

    @Test("refine does not allocate an O(n²) buffer at moderate inlier counts")
    func refineAllocationBoundedAtModerateN() throws {
        // n = 10 000 puts the pre-fix `vt = [Float](repeating: 0, count: n*n)`
        // allocation at 4 × 10⁸ bytes ≈ 400 MB. The post-fix scatter-matrix path
        // is bounded by O(n) accumulator work and a 3×3 SVD (~hundreds of bytes).
        // The cap below sits comfortably between the two regimes.
        let n = 10_000
        // Points on a plane tilted 3° from +y around the z axis, with the same
        // 0.2 mm deterministic jitter the existing SupportPlaneRoughMaskTests
        // fixture uses so σ_min stays well above the float32 precision floor
        // of σ_max × ε at this scale.
        let tiltRad: Float = 3 * .pi / 180
        let nPlane = Vec3(sin(tiltRad), cos(tiltRad), 0)
        let dPlane: Float = 200
        var points: [Vec3] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let row = Float(i / 100)
            let col = Float(i % 100)
            let x = (col - 50) * 1.5
            let z = (row - 50) * 1.5
            // y from the tilted plane equation n·p = d.
            let yBase = (dPlane - nPlane.x * x - nPlane.z * z) / nPlane.y
            let jitter = sin(Float(i) * 0.137) * 0.2
            points.append(Vec3(x, yBase + jitter, z))
        }
        let rssBefore = currentResidentSizeBytes()
        let (normal, d) = try LiDARPlaneFitter.refine(inliers: points, seedNormal: nPlane)
        let rssAfter = currentResidentSizeBytes()

        // The recovered plane should match the synthesised one within a small
        // tolerance — confirming the algebraic substitution is equivalent.
        let cosAngle = normal.dot(nPlane)
        #expect(cosAngle > 0.999,
                "recovered normal off plane normal by cosine \(cosAngle)")
        #expect(abs(d - dPlane) < 1.0, "expected d ≈ \(dPlane), got \(d)")

        let delta = rssAfter - rssBefore
        // 64 MB cap: well below the pre-fix ~400 MB V^T allocation but
        // comfortably above the post-fix overhead (≤ a few MB for the inliers
        // copy, scatter accumulator, and 3×3 SVD).
        #expect(delta < 64 * 1024 * 1024,
                "refine RSS grew by \(delta) bytes; pre-fix V^T request was ~400 MB")
    }

    private func currentResidentSizeBytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}
