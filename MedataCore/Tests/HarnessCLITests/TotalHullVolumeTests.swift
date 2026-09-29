#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Property tests for TotalHullVolume (spec task 9, design §MixtureBetaCalibrator).
//
// Geometry (same conventions as HeightFieldEstimatorTests):
//   Camera at origin, −Z forward (§6.0).
//   Support plane: n̂ = (0,0,1), distanceMm = −600 → plate top at z = −600 mm.
//   Food at z = −500 mm → height 100 mm above the plane.
//   The silhouette is depth-thresholded: a pixel is food when its ray-plane
//   height above the support plane exceeds heightEpsilonMm; there is no argmax
//   mask on this path (Req 3.7 forbids one on mixture fixtures).
@Suite("TotalHullVolume")
struct TotalHullVolumeTests {

    let k500 = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                distortion: [], imageWidth: 100, imageHeight: 100)
    let kWide = CameraIntrinsics(fx: 100, fy: 100, cx: 50, cy: 50,
                                 distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)

    func makeDepth(width: Int, height: Int, intrinsics: CameraIntrinsics,
                   depthMm: (Int, Int) -> Float) -> DepthMap {
        var depthBytes = Data(count: width * height * 4)
        let confBytes = Data(repeating: 255, count: width * height)
        depthBytes.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Float.self).baseAddress!
            for y in 0..<height {
                for x in 0..<width {
                    buf[y * width + x] = depthMm(y, x)
                }
            }
        }
        return DepthMap(
            depthBytesMm: depthBytes, confidenceBytes: confBytes,
            width: width, height: height, rowStrideBytes: width * 4,
            depthIntrinsics: intrinsics, depthFromColour: .identity
        )
    }

    // Analytic volume of a flat slab at depth zt over the included pixels:
    // Σ a_p × h with a_p = z_t²/(fx·fy·cos³θ), h = |plane| − z_t.
    func analyticCm3(k: CameraIntrinsics, ztMm: Float, heightMm: Float,
                     included: (Int, Int) -> Bool) -> Float {
        let fMean = (k.fx + k.fy) / 2
        var mm3: Double = 0
        for y in 0..<k.imageHeight {
            for x in 0..<k.imageWidth {
                guard included(y, x) else { continue }
                let du = Float(x) - k.cx
                let dv = Float(y) - k.cy
                let cosT = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                let cos3 = Double(cosT * cosT * cosT)
                let aP = Double(ztMm * ztMm) / (Double(k.fx * k.fy) * cos3)
                mm3 += aP * Double(heightMm)
            }
        }
        return Float(mm3 / 1000)
    }

    @Test("Flat slab over a known plane integrates to the analytic volume")
    func flatSlabMatchesAnalytic() {
        let depth = makeDepth(width: 100, height: 100, intrinsics: k500) { _, _ in 500 }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: k500, supportPlane: plane))
        let expected = analyticCm3(k: k500, ztMm: 500, heightMm: 100) { _, _ in true }
        #expect(abs(vol - expected) / expected <= 0.03,
                "volume \(vol) cm³ not within 3% of analytic \(expected) cm³")
    }

    @Test("Silhouette is height above plane > ε: at-plane pixels contribute nothing")
    func heightThresholdExcludesPlanePixels() {
        // Left half at the plane depth (height 0), right half raised 100 mm.
        let depth = makeDepth(width: 100, height: 100, intrinsics: k500) { _, x in
            x < 50 ? 600 : 500
        }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: k500, supportPlane: plane))
        let expected = analyticCm3(k: k500, ztMm: 500, heightMm: 100) { _, x in x >= 50 }
        #expect(abs(vol - expected) / expected <= 0.03)
    }

    @Test("Pixels below the documented ε are outside the silhouette")
    func subEpsilonHeightIsExcluded() {
        // Whole frame barely above the plane — below heightEpsilonMm.
        let zt = 600 - TotalHullVolume.heightEpsilonMm / 2
        let depth = makeDepth(width: 100, height: 100, intrinsics: k500) { _, _ in zt }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: k500, supportPlane: plane))
        #expect(vol == 0)
    }

    @Test("Sentinel/at-cap zero-depth pixels are excluded (Req 3.2)")
    func sentinelPixelsExcluded() {
        // Top-left quadrant is sentinel 0 (invalid / at-cap written as 0 by
        // ingestion); the rest is a flat slab. Volume must equal the analytic
        // value over the valid pixels only — sentinels must not read as surfaces.
        let depth = makeDepth(width: 100, height: 100, intrinsics: k500) { y, x in
            (y < 50 && x < 50) ? 0 : 500
        }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: k500, supportPlane: plane))
        let expected = analyticCm3(k: k500, ztMm: 500, heightMm: 100) { y, x in
            !(y < 50 && x < 50)
        }
        #expect(abs(vol - expected) / expected <= 0.03)
    }

    @Test("Off-axis pixel-area correction inflates volume above the flat baseline")
    func offAxisCorrectionApplied() {
        // Wide-angle camera: corner pixels have 1/cos³θ ≈ 1.84; the integrated
        // volume must exceed the uncorrected (θ=0 everywhere) baseline.
        let depth = makeDepth(width: 100, height: 100, intrinsics: kWide) { _, _ in 500 }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: kWide, supportPlane: plane))
        let flatBaseline = Float(100 * 100) * (500 * 500 / (kWide.fx * kWide.fy)) * 100 / 1000
        #expect(vol > flatBaseline)
    }

    @Test("Volume scales linearly with height", arguments: [50 as Float, 100, 200])
    func volumeScalesWithHeight(heightMm: Float) {
        let depth = makeDepth(width: 100, height: 100, intrinsics: k500) { _, _ in
            600 - heightMm
        }
        let vol = TotalHullVolume.integrate(TotalHullVolume.Inputs(
            depth: depth, intrinsics: k500, supportPlane: plane))
        let expected = analyticCm3(k: k500, ztMm: 600 - heightMm, heightMm: heightMm) { _, _ in true }
        #expect(abs(vol - expected) / expected <= 0.03)
    }
}
#endif
