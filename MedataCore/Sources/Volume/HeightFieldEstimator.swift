import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane

// Single-view height-field integrator per design §6.7. Pure Swift reference
// implementation. Iterates one thread per nadir-view pixel; the equivalent Metal
// kernel lives in Kernels/height_field.metal for GPU dispatch on device.

public struct HeightFieldEstimate: Sendable {
    public let perClassVolumesCm3: [String: Float]
    public let lidarCoverageFraction: [String: Float]
    public let interClassOcclusionDetected: Bool
    public let perClassFoodPixelCount: [String: Int]

    public init(perClassVolumesCm3: [String: Float],
                lidarCoverageFraction: [String: Float],
                interClassOcclusionDetected: Bool,
                perClassFoodPixelCount: [String: Int]) {
        self.perClassVolumesCm3 = perClassVolumesCm3
        self.lidarCoverageFraction = lidarCoverageFraction
        self.interClassOcclusionDetected = interClassOcclusionDetected
        self.perClassFoodPixelCount = perClassFoodPixelCount
    }
}

public enum HeightFieldEstimator {
    public static let tauSilhouette: Float = 0.5
    public static let tauConfidence: Float = 0.66
    public static let coverageRefuseFraction: Float = 0.5
    public static let minVolumeCm3: Float = 1

    public struct Inputs: Sendable {
        public let probabilities: ProbabilityTensor
        public let argmax: ArgmaxMap
        public let depth: DepthMap
        public let intrinsics: CameraIntrinsics
        public let supportPlane: SupportPlane
        public let beta: BetaCorrection
        public let palette: ClassPalette

        public init(probabilities: ProbabilityTensor, argmax: ArgmaxMap,
                    depth: DepthMap, intrinsics: CameraIntrinsics,
                    supportPlane: SupportPlane, beta: BetaCorrection,
                    palette: ClassPalette) {
            self.probabilities = probabilities
            self.argmax = argmax
            self.depth = depth
            self.intrinsics = intrinsics
            self.supportPlane = supportPlane
            self.beta = beta
            self.palette = palette
        }
    }

    public static func integrate(_ inputs: Inputs) throws -> HeightFieldEstimate {
        let probs = inputs.probabilities
        let argmax = inputs.argmax
        let palette = inputs.palette

        guard probs.width == argmax.width && probs.height == argmax.height else {
            throw VolumeError.mismatchedViewDimensions(
                "argmax \(argmax.width)×\(argmax.height) ≠ probabilities \(probs.width)×\(probs.height)"
            )
        }

        let w = probs.width
        let h = probs.height
        let bgId = palette.background
        let liquidId = palette.unsupportedLiquid
        let k = inputs.intrinsics
        let plane = inputs.supportPlane

        let fMean = (k.fx + k.fy) / 2

        var vRawMm3: [Int: Double] = [:]
        var coveredPixels: [Int: Int] = [:]
        var totalPixels: [Int: Int] = [:]
        var depthTopMm = [Float](repeating: 0, count: w * h)

        // Walk pixels. Use a flat byte iteration into the FP16 tensor.
        try probs.bytes.withUnsafeBytes { raw -> Void in
            let buf = raw.bindMemory(to: Float16.self).baseAddress!
            try argmax.pixels.withUnsafeBytes { argRaw -> Void in
                let labels = argRaw.bindMemory(to: UInt8.self).baseAddress!
                for y in 0..<h {
                    for x in 0..<w {
                        let off = (y * w + x) * probs.classes
                        let qBg = Float(buf[off + bgId])
                        if (1 - qBg) < tauSilhouette { continue }   // not in silhouette
                        let labelC = Int(labels[y * w + x])
                        if !palette.isFoodClass(labelC) { continue }
                        if labelC == liquidId { continue }
                        totalPixels[labelC, default: 0] += 1

                        let conf = sampleConfidenceUInt8(
                            depth: inputs.depth,
                            colourX: x, colourY: y,
                            colourWidth: w, colourHeight: h
                        )
                        if Float(conf) / 255 < tauConfidence { continue }
                        guard let zt = sampleDepthBilinearMm(
                            depth: inputs.depth,
                            colourX: Float(x), colourY: Float(y),
                            colourWidth: w, colourHeight: h
                        ), zt > 0 else { continue }
                        coveredPixels[labelC, default: 0] += 1
                        depthTopMm[y * w + x] = zt

                        // §6.7: camera-frame ray and support-plane intersection.
                        let dir = Vec3(
                            (Float(x) - k.cx) / k.fx,
                            (Float(y) - k.cy) / k.fy,
                            -1
                        ).normalised()
                        // p_top along the ray at depth z_t (positive forward). With
                        // §6.0 −Z forward: |dir.z| ≈ cosθ, so p_top = (zt / |dir.z|) · dir.
                        let absDz = abs(dir.z)
                        if absDz < 1e-9 { continue }
                        let pTop = dir * (zt / absDz)

                        let denom = plane.normal.dot(dir)
                        if abs(denom) < 1e-9 { continue }
                        let alphaSup = plane.distanceMm / denom
                        let pSup = dir * alphaSup
                        let zS = abs(pSup.z)
                        let zTopAbs = abs(pTop.z)
                        let height = max(0, zS - zTopAbs)

                        // Off-axis pixel area at z_t (M1 fix).
                        let du = Float(x) - k.cx
                        let dv = Float(y) - k.cy
                        let denomRoot = (fMean * fMean + du * du + dv * dv).squareRoot()
                        let cosTheta = fMean / denomRoot
                        let cos3 = cosTheta * cosTheta * cosTheta
                        let aP = (zt * zt) / (k.fx * k.fy * cos3)

                        vRawMm3[labelC, default: 0] += Double(height) * Double(aP)
                    }
                }
            }
        }

        // Per-class LiDAR coverage and refusal.
        var coverage: [String: Float] = [:]
        var perClassPixelCount: [String: Int] = [:]
        var lowCoverageClasses: [String] = []
        for (cId, total) in totalPixels {
            guard let name = palette.foodClassName(at: cId) else { continue }
            let covered = coveredPixels[cId, default: 0]
            let frac = total > 0 ? Float(covered) / Float(total) : 0
            coverage[name] = frac
            perClassPixelCount[name] = total
            if frac < coverageRefuseFraction {
                lowCoverageClasses.append(name)
            }
        }
        if !lowCoverageClasses.isEmpty {
            throw VolumeError.lidarCoverageTooLow(classes: lowCoverageClasses.sorted())
        }

        // Convert mm³ → cm³ and apply β.
        var perClass: [String: Float] = [:]
        for (cId, rawMm3) in vRawMm3 {
            guard let name = palette.foodClassName(at: cId) else { continue }
            let cm3 = Float(rawMm3 / 1000.0)
            perClass[name] = cm3 * inputs.beta.beta(for: name)
        }

        let present = perClass.filter { $0.value >= minVolumeCm3 }
        if present.isEmpty {
            throw VolumeError.noFoodVolumeRecovered
        }

        let occlusion = InterClassOcclusionDetector.detect(
            argmax: argmax, depthTopMm: depthTopMm, palette: palette
        )

        return HeightFieldEstimate(
            perClassVolumesCm3: perClass,
            lidarCoverageFraction: coverage,
            interClassOcclusionDetected: occlusion,
            perClassFoodPixelCount: perClassPixelCount
        )
    }
}
