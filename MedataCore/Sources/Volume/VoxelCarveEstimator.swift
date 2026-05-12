import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane

// Two-view voxel carving with class-ownership rule per design §6.6. Pure Swift
// reference implementation. The equivalent Metal kernel lives in
// Kernels/voxel_carve.metal for GPU dispatch on device (Apple Silicon UMA via
// `MTLBuffer<atomic_uint>[C]` with `.storageModeShared`).

public struct VoxelCarveView: Sendable {
    public let probabilities: ProbabilityTensor
    public let intrinsics: CameraIntrinsics

    public init(probabilities: ProbabilityTensor, intrinsics: CameraIntrinsics) {
        self.probabilities = probabilities
        self.intrinsics = intrinsics
    }
}

public struct VoxelCarveEstimate: Sendable {
    public let perClassVolumesCm3: [String: Float]
    public let ambiguousVoxelFraction: Float
    public let voxelGridSummary: PbVoxelGridSummary
    public let perClassVoxelCount: [String: Int]
    public let degradedClasses: Set<String>      // single-view-only fallback used

    public init(perClassVolumesCm3: [String: Float], ambiguousVoxelFraction: Float,
                voxelGridSummary: PbVoxelGridSummary, perClassVoxelCount: [String: Int],
                degradedClasses: Set<String>) {
        self.perClassVolumesCm3 = perClassVolumesCm3
        self.ambiguousVoxelFraction = ambiguousVoxelFraction
        self.voxelGridSummary = voxelGridSummary
        self.perClassVoxelCount = perClassVoxelCount
        self.degradedClasses = degradedClasses
    }
}

public enum VoxelCarveEstimator {
    public static let tauSilhouette: Float = 0.5
    public static let tauOwnership: Float = 0.04
    public static let singleViewPriorHeightMm: Float = 30
    public static let minVoxelCountForClass: Int = 30

    public struct Inputs: Sendable {
        public let grid: VoxelGrid
        public let view1: VoxelCarveView
        public let view2: VoxelCarveView
        public let transform1To2: Mat4              // p_2 = T · p_1
        public let supportPlane: SupportPlane
        public let matchedClasses: Set<Int>         // classes_in_both_views (food only)
        public let singleViewOnlyClassesView1: Set<Int>
        public let singleViewOnlyClassesView2: Set<Int>
        public let beta: BetaCorrection
        public let palette: ClassPalette

        public init(grid: VoxelGrid, view1: VoxelCarveView, view2: VoxelCarveView,
                    transform1To2: Mat4, supportPlane: SupportPlane,
                    matchedClasses: Set<Int>,
                    singleViewOnlyClassesView1: Set<Int>,
                    singleViewOnlyClassesView2: Set<Int>,
                    beta: BetaCorrection, palette: ClassPalette) {
            self.grid = grid
            self.view1 = view1
            self.view2 = view2
            self.transform1To2 = transform1To2
            self.supportPlane = supportPlane
            self.matchedClasses = matchedClasses
            self.singleViewOnlyClassesView1 = singleViewOnlyClassesView1
            self.singleViewOnlyClassesView2 = singleViewOnlyClassesView2
            self.beta = beta
            self.palette = palette
        }
    }

    public static func carve(_ inputs: Inputs) throws -> VoxelCarveEstimate {
        let grid = inputs.grid
        let palette = inputs.palette
        let bgId = palette.background
        let liquidId = palette.unsupportedLiquid

        let probs1 = inputs.view1.probabilities
        let probs2 = inputs.view2.probabilities
        guard probs1.classes == palette.totalClasses,
              probs2.classes == palette.totalClasses else {
            throw VolumeError.mismatchedViewDimensions(
                "probability tensors must match palette.totalClasses=\(palette.totalClasses)"
            )
        }

        // Per-class voxel ownership sets are flattened into a count map.
        var counts: [Int: Int] = [:]
        var passedSilhouettePlaneTest = 0
        var ambiguousCount = 0

        // Walk every voxel. The 8×8×8 threadgroup constraint on the Metal kernel is
        // satisfied by §6.10 (dims are multiples of 8); the CPU reference walks the
        // full grid directly.
        let classList = inputs.matchedClasses.sorted()
        probs1.bytes.withUnsafeBytes { rawP1 in
            let buf1 = rawP1.bindMemory(to: Float16.self).baseAddress!
            probs2.bytes.withUnsafeBytes { rawP2 in
                let buf2 = rawP2.bindMemory(to: Float16.self).baseAddress!
                for iz in 0..<grid.dimsZ {
                    for iy in 0..<grid.dimsY {
                        for ix in 0..<grid.dimsX {
                            let p1 = grid.voxelCentre(ix: ix, iy: iy, iz: iz)
                            if signedDistanceToPlane(p1, plane: inputs.supportPlane) < 0 {
                                continue
                            }
                            guard let u1 = projectCamera1(inputs.view1.intrinsics, p1) else { continue }
                            let (u1x, u1y) = u1
                            if !pixelInside(u: u1x, v: u1y, width: probs1.width, height: probs1.height) {
                                continue
                            }
                            let p2 = applyMat4(inputs.transform1To2, p1)
                            guard let u2 = projectCamera1(inputs.view2.intrinsics, p2) else { continue }
                            let (u2x, u2y) = u2
                            if !pixelInside(u: u2x, v: u2y, width: probs2.width, height: probs2.height) {
                                continue
                            }

                            let pix1 = nearestPixel(u: u1x, v: u1y,
                                                    width: probs1.width, height: probs1.height)
                            let pix2 = nearestPixel(u: u2x, v: u2y,
                                                    width: probs2.width, height: probs2.height)
                            let off1 = (pix1.y * probs1.width + pix1.x) * probs1.classes
                            let off2 = (pix2.y * probs2.width + pix2.x) * probs2.classes

                            // Silhouette test on (1 − q[bg]) ≥ τ_sil in BOTH views.
                            let q1Bg = Float(buf1[off1 + bgId])
                            let q2Bg = Float(buf2[off2 + bgId])
                            if (1 - q1Bg) < tauSilhouette { continue }
                            if (1 - q2Bg) < tauSilhouette { continue }

                            passedSilhouettePlaneTest += 1

                            // Per-pixel-pair argmax over classes_in_both_views, in FP32.
                            var bestScore: Float = 0
                            var bestClass: Int = -1
                            for c in classList {
                                let qc1 = Float(buf1[off1 + c])
                                let qc2 = Float(buf2[off2 + c])
                                let score = qc1 * qc2
                                if score > bestScore {
                                    bestScore = score
                                    bestClass = c
                                }
                            }
                            if bestClass < 0 { continue }
                            if bestClass == liquidId { continue }      // safety
                            if bestScore < tauOwnership {
                                ambiguousCount += 1
                                continue
                            }
                            counts[bestClass, default: 0] += 1
                        }
                    }
                }
            }
        }

        // Single-view-only fallback per §6.6: extrude silhouette to π_sup at a 30 mm
        // prior height for any class that appears only in one view.
        var fallbackVolumesMm3: [Int: Double] = [:]
        let fallbackClasses1 = inputs.singleViewOnlyClassesView1.filter { palette.isFoodClass($0) }
        let fallbackClasses2 = inputs.singleViewOnlyClassesView2.filter { palette.isFoodClass($0) }
        for c in fallbackClasses1 {
            fallbackVolumesMm3[c] = singleViewExtrudedVolumeMm3(
                classId: c, view: inputs.view1,
                supportPlane: inputs.supportPlane, palette: palette
            )
        }
        for c in fallbackClasses2 {
            fallbackVolumesMm3[c] = singleViewExtrudedVolumeMm3(
                classId: c, view: inputs.view2,
                supportPlane: inputs.supportPlane, palette: palette
            )
        }

        // Volumes: mm³ → cm³ → β-correct.
        let voxelVolumeMm3 = Double(grid.edgeMm) * Double(grid.edgeMm) * Double(grid.edgeMm)
        var perClassVolumes: [String: Float] = [:]
        var perClassVoxelCount: [String: Int] = [:]
        var degraded: Set<String> = []
        var foodClassesPresent: [String] = []

        for (classId, count) in counts where count >= minVoxelCountForClass {
            guard let name = palette.foodClassName(at: classId) else { continue }
            let mm3 = Double(count) * voxelVolumeMm3
            let cm3 = Float(mm3 / 1000.0) * inputs.beta.beta(for: name)
            perClassVolumes[name] = cm3
            perClassVoxelCount[name] = count
            foodClassesPresent.append(name)
        }
        for (classId, mm3) in fallbackVolumesMm3 {
            guard let name = palette.foodClassName(at: classId) else { continue }
            let cm3 = Float(mm3 / 1000.0) * inputs.beta.beta(for: name)
            if cm3 < 1 { continue }                     // tiny-class refusal
            perClassVolumes[name] = cm3
            degraded.insert(name)
            foodClassesPresent.append(name)
        }

        if foodClassesPresent.isEmpty {
            throw VolumeError.noFoodVolumeRecovered
        }

        let ambiguous: Float = passedSilhouettePlaneTest > 0
            ? Float(ambiguousCount) / Float(passedSilhouettePlaneTest)
            : 0

        let summary = VoxelGridSizer.summary(grid, perClassVoxelCount: perClassVoxelCount)

        return VoxelCarveEstimate(
            perClassVolumesCm3: perClassVolumes,
            ambiguousVoxelFraction: ambiguous,
            voxelGridSummary: summary,
            perClassVoxelCount: perClassVoxelCount,
            degradedClasses: degraded
        )
    }

    // MARK: - helpers

    static func pixelInside(u: Float, v: Float, width: Int, height: Int) -> Bool {
        u >= 0 && v >= 0 && u < Float(width) && v < Float(height)
    }

    static func nearestPixel(u: Float, v: Float, width: Int, height: Int) -> (x: Int, y: Int) {
        let x = max(0, min(width - 1, Int(u.rounded(.down))))
        let y = max(0, min(height - 1, Int(v.rounded(.down))))
        return (x, y)
    }

    // Single-view extrusion: silhouette pixels in the given view, extruded a fixed
    // 30 mm down to π_sup. Each silhouette pixel contributes its metric area at the
    // food-plane depth multiplied by the prior height. Per §6.6, this is the
    // degraded fallback used when a class is missing from one view.
    static func singleViewExtrudedVolumeMm3(
        classId: Int, view: VoxelCarveView,
        supportPlane: SupportPlane, palette: ClassPalette
    ) -> Double {
        let probs = view.probabilities
        let k = view.intrinsics
        let bgId = palette.background
        let liquidId = palette.unsupportedLiquid
        let fMean = (k.fx + k.fy) / 2
        var totalMm3: Double = 0
        probs.bytes.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Float16.self).baseAddress!
            for y in 0..<probs.height {
                for x in 0..<probs.width {
                    let off = (y * probs.width + x) * probs.classes
                    let qBg = Float(buf[off + bgId])
                    if (1 - qBg) < tauSilhouette { continue }
                    // argmax over food classes only (no special classes).
                    var bestC = -1
                    var bestQ: Float = -1
                    for c in 0..<probs.classes {
                        if !palette.isFoodClass(c) { continue }
                        if c == liquidId { continue }
                        let q = Float(buf[off + c])
                        if q > bestQ { bestQ = q; bestC = c }
                    }
                    if bestC != classId { continue }

                    // Compute pixel area at food-plane depth via ray-plane intersection.
                    let dir = Vec3(
                        (Float(x) - k.cx) / k.fx,
                        (Float(y) - k.cy) / k.fy,
                        -1
                    ).normalised()
                    let denom = supportPlane.normal.dot(dir)
                    if abs(denom) < 1e-9 { continue }
                    let alpha = supportPlane.distanceMm / denom
                    if alpha <= 0 { continue }
                    let pFood = dir * alpha
                    let zT = abs(pFood.z)

                    let du = Float(x) - k.cx
                    let dv = Float(y) - k.cy
                    let denomRoot = (fMean * fMean + du * du + dv * dv).squareRoot()
                    let cosTheta = fMean / denomRoot
                    let cos3 = cosTheta * cosTheta * cosTheta
                    let aP = (zT * zT) / (k.fx * k.fy * cos3)
                    totalMm3 += Double(aP * singleViewPriorHeightMm)
                }
            }
        }
        return totalMm3
    }
}
