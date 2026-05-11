import CaptureKit
import PortableContracts
import XCTest
@testable import CardDetection

// Task 12: property-based P4P round-trip per design §7.2.
// Spec asks for SwiftCheck generators; we use a deterministic seeded RNG instead so
// the test is reproducible without the SwiftPM dep, the same envelope and properties
// hold, and CI cannot fetch generators differently between runs. The seeded sampler
// can be swapped for SwiftCheck.forAll without changing the property assertions.

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed != 0 ? seed : 0xDEAD_BEEF }
    mutating func next() -> UInt64 {
        // splitmix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension SeededRNG {
    mutating func uniform(_ lo: Float, _ hi: Float) -> Float {
        let u = Float(next() % 1_000_000) / 1_000_000
        return lo + (hi - lo) * u
    }
}

private struct CardPoseGen {
    var k: CameraIntrinsics
    var rotationColumnMajor: [Float]
    var translationMm: Vec3
}

// Generate a pose in a realistic envelope:
//   • intrinsics: fx ≈ fy ∈ [1300, 1700] (iPhone 12 Pro main camera range)
//   • rotation: yaw ∈ [-0.3, +0.3] rad (≈ ±17°), pitch ∈ [-0.3, +0.3] rad
//   • translation: x ∈ [-50, 50] mm, y ∈ [-50, 50] mm, z ∈ [-450, -250] mm
private func generate(_ rng: inout SeededRNG) -> CardPoseGen {
    let f = rng.uniform(1300, 1700)
    let k = CameraIntrinsics(
        fx: f, fy: f, cx: 2016, cy: 1512,
        distortion: [], imageWidth: 4032, imageHeight: 3024
    )
    let yaw = rng.uniform(-0.3, 0.3)
    let pitch = rng.uniform(-0.3, 0.3)
    let cy = cos(yaw),  sy = sin(yaw)
    let cp = cos(pitch), sp = sin(pitch)
    // Ry(yaw) · Rx(pitch), column-major.
    let r: [Float] = [
        cy,        sp * sy,   -cp * sy,
        0,         cp,         sp,
        sy,       -sp * cy,    cp * cy
    ]
    let t = Vec3(
        rng.uniform(-50, 50),
        rng.uniform(-50, 50),
        rng.uniform(-450, -250)
    )
    return CardPoseGen(k: k, rotationColumnMajor: r, translationMm: t)
}

private func projectCard(rotation r: [Float], translation t: Vec3, k: CameraIntrinsics) -> [PixelCorner] {
    return ISO7810.cornersMm.map { (mx, my) in
        let X = Vec3(mx, my, 0)
        let p = CardPoseSolver.applyR(r, to: X) + t
        let denom = -p.z
        let u = k.fx * p.x / denom + k.cx
        let v = k.fy * p.y / denom + k.cy
        return PixelCorner(u, v)
    }
}

final class CardPosePropertyTests: XCTestCase {
    // Property: recover(project(pose)) returns a pose within ε of the original (§7.2).
    // 200 deterministic samples; tolerance is 1 mm L2 on translation given exact
    // synthetic projection (no pixel noise) — the only error sources are floating-
    // point and the SO(3) projection.
    func testRoundTripRecoversTranslationWithinTolerance() throws {
        var rng = SeededRNG(seed: 0xC0FFEE_BEEF_F00D)
        let samples = 200
        var maxErrMm: Float = 0
        var failed = 0
        for _ in 0..<samples {
            let g = generate(&rng)
            let corners = projectCard(rotation: g.rotationColumnMajor, translation: g.translationMm, k: g.k)
            let pose: CardPose
            do {
                pose = try CardPoseSolver.solve(corners: corners, intrinsics: g.k)
            } catch {
                failed += 1
                continue
            }
            let dx: Float = pose.translationMm.x - g.translationMm.x
            let dy: Float = pose.translationMm.y - g.translationMm.y
            let dz: Float = pose.translationMm.z - g.translationMm.z
            let distSquared: Float = dx * dx + dy * dy + dz * dz
            let err = distSquared.squareRoot()
            maxErrMm = max(maxErrMm, err)
        }
        XCTAssertEqual(failed, 0, "no in-envelope pose should fail: failed=\(failed)")
        XCTAssertLessThan(maxErrMm, 1.0,
                          "max round-trip translation error \(maxErrMm) mm exceeded 1 mm")
    }

    // Property: PnP residual on noiseless inputs is ≈ 0 (sub-pixel) for every sample.
    func testRoundTripResidualIsSubPixel() throws {
        var rng = SeededRNG(seed: 0xC0DE_F00D_BABE_BABE)
        let samples = 200
        var maxResidual: Float = 0
        for _ in 0..<samples {
            let g = generate(&rng)
            let corners = projectCard(rotation: g.rotationColumnMajor, translation: g.translationMm, k: g.k)
            let pose = try CardPoseSolver.solve(corners: corners, intrinsics: g.k)
            maxResidual = max(maxResidual, pose.pnpResidualPx)
        }
        XCTAssertLessThan(maxResidual, 1.0,
                          "max PnP residual \(maxResidual) px exceeded 1 px on noiseless inputs")
    }
}
