#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import SupportPlane

// Total above-plane hull volume for the mixture calibration path
// (design §MixtureBetaCalibrator). Harness-only: mixture fixtures carry no
// segmenter output (Req 3.7), so the silhouette is depth-thresholded — a pixel
// is food when its ray-plane height above the support plane exceeds ε — rather
// than argmax-masked. The ray-plane height and off-axis pixel-area geometry
// mirror HeightFieldEstimator/VolumeTypes exactly so the hull is measured the
// way the estimator measures per-class volume; only the masking differs (the
// recorded Req 5.1 masking-transfer gap).
public enum TotalHullVolume {
    // Documented silhouette threshold: heights at or below ε are treated as the
    // support plane itself (plane-fit residual noise), not food.
    public static let heightEpsilonMm: Float = 3.0

    public struct Inputs: Sendable {
        public let depth: DepthMap
        public let intrinsics: CameraIntrinsics   // colour-grid intrinsics
        public let supportPlane: SupportPlane
        public let heightEpsilonMm: Float

        public init(depth: DepthMap, intrinsics: CameraIntrinsics,
                    supportPlane: SupportPlane,
                    heightEpsilonMm: Float = TotalHullVolume.heightEpsilonMm) {
            self.depth = depth
            self.intrinsics = intrinsics
            self.supportPlane = supportPlane
            self.heightEpsilonMm = heightEpsilonMm
        }
    }

    // Integrate the total above-plane hull volume in cm³.
    public static func integrate(_ inputs: Inputs) -> Float {
        let k = inputs.intrinsics
        let plane = inputs.supportPlane
        let depth = inputs.depth
        let w = k.imageWidth
        let h = k.imageHeight
        let fMean = (k.fx + k.fy) / 2

        var vRawMm3: Double = 0
        depth.depthBytesMm.withUnsafeBytes { raw in
            for y in 0..<h {
                for x in 0..<w {
                    // Nearest-neighbour depth sample at the colour pixel centre
                    // (mirrors VolumeTypes.readDepthMm / sampleConfidenceUInt8
                    // resampling). Nearest — not bilinear — so a sentinel 0
                    // excludes exactly its own pixel rather than bleeding into
                    // neighbours through interpolation.
                    let dx = min(depth.width - 1,
                                 max(0, Int((Float(x) + 0.5) * Float(depth.width) / Float(w))))
                    let dy = min(depth.height - 1,
                                 max(0, Int((Float(y) + 0.5) * Float(depth.height) / Float(h))))
                    let zt = raw.loadUnaligned(fromByteOffset: (dy * depth.width + dx) * 4,
                                               as: Float.self)
                    // Sentinel/at-cap pixels are written as 0 by ingestion (Req 3.2).
                    guard zt > 0 else { continue }

                    // §6.7 ray-plane height (identical to HeightFieldEstimator).
                    let dir = Vec3(
                        (Float(x) - k.cx) / k.fx,
                        (Float(y) - k.cy) / k.fy,
                        -1
                    ).normalised()
                    let absDz = abs(dir.z)
                    if absDz < 1e-9 { continue }
                    let pTop = dir * (zt / absDz)

                    let denom = plane.normal.dot(dir)
                    if abs(denom) < 1e-9 { continue }
                    let alphaSup = plane.distanceMm / denom
                    let pSup = dir * alphaSup
                    let height = max(0, abs(pSup.z) - abs(pTop.z))

                    // Depth-threshold silhouette: above-plane by more than ε.
                    guard height > inputs.heightEpsilonMm else { continue }

                    // Off-axis pixel area at z_t (M1 fix, identical to §6.7).
                    let du = Float(x) - k.cx
                    let dv = Float(y) - k.cy
                    let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                    let cos3 = cosTheta * cosTheta * cosTheta
                    let aP = (zt * zt) / (k.fx * k.fy * cos3)

                    vRawMm3 += Double(height) * Double(aP)
                }
            }
        }
        return Float(vRawMm3 / 1000.0)
    }
}
#endif
