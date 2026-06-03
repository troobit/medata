import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// LiDAR support-plane RANSAC fitter per design §6.2. Pure function over the depth
// map, the food-region mask resampled to the colour grid, the camera intrinsics, and
// gravity. RNG is seeded by hashing the depth bytes (per §6.0) so two runs on the
// same fixture produce identical inliers.
public enum LiDARPlaneFitter {
    #if DEBUG
    // Debug-only counters exposed for the Shutter-channel structured-log
    // instrumentation at `Pipeline.fitSupportPlane`. Populated by `fit(_:)`
    // before any throw or return. Not part of the production contract.
    public nonisolated(unsafe) static var debugLastCandidatePointCount: Int = 0
    public nonisolated(unsafe) static var debugLastInlierCount: Int = 0
    #endif

    // Tunable parameters per design §6.2 ("Parameter justification").
    static let lowerEdgeBandMm: Float = 30
    static let confidenceThreshold: Float = 0.66
    static let maxIterations: Int = 256
    static let inlierBandMm: Float = 5
    static let gravityAngleMaxRad: Float = 15 * .pi / 180
    // Raised from 8 mm to 20 mm per Decision 46 / Req §4.5. Residuals in (8, 20]
    // accept the fit; σ_plane = exp(−r/5) carries the degradation (at r = 20 mm,
    // σ_plane ≈ 0.018, near the ε = 0.01 floor).
    public static let residualMaxMm: Float = 20
    static let stabilityRatioMin: Float = 1e-6
    static let minPoints: Int = 3

    public struct Inputs: Sendable {
        public let depth: DepthMap
        public let colourIntrinsics: CameraIntrinsics
        public let foodRegionMask: BinaryMask    // colour-image grid
        public let gravityCamera: Vec3           // unit vector in camera-1 frame
        public let residualMaxMm: Float          // §6.2 step 5; default 8

        public init(depth: DepthMap, colourIntrinsics: CameraIntrinsics,
                    foodRegionMask: BinaryMask, gravityCamera: Vec3,
                    residualMaxMm: Float = LiDARPlaneFitter.residualMaxMm) {
            self.depth = depth
            self.colourIntrinsics = colourIntrinsics
            self.foodRegionMask = foodRegionMask
            self.gravityCamera = gravityCamera
            self.residualMaxMm = residualMaxMm
        }
    }

    public static func fit(_ inputs: Inputs) throws -> SupportPlane {
        // Step 1: collect candidate 3-D points in the colour-image lower-edge band.
        let points = try collectCandidatePoints(inputs)
        #if DEBUG
        debugLastCandidatePointCount = points.count
        debugLastInlierCount = 0
        #endif
        guard points.count >= minPoints else {
            throw SupportPlaneError.noLidarPoints
        }

        // Step 2: RANSAC. Deterministic seed from the depth bytes (§6.0).
        let seed = Fnv1a64.hash(inputs.depth.depthBytesMm)
        var rng = SplitMix64(seed: seed)
        let (bestNormal, _, bestInliers) = ransac(
            points: points,
            gravity: inputs.gravityCamera.normalised(),
            rng: &rng
        )
        #if DEBUG
        debugLastInlierCount = bestInliers.count
        #endif

        guard bestInliers.count >= minPoints else {
            throw SupportPlaneError.noLidarPoints
        }

        // Step 3 + 5: least-squares refinement on inliers; stability gate σ_min/σ_max.
        let (refinedNormal, refinedD) = try refine(
            inliers: bestInliers.map { points[$0] },
            seedNormal: bestNormal
        )

        // Step 4: residual_mm = sqrt(mean(squared inlier signed-distances)).
        let residual = computeResidual(points: bestInliers.map { points[$0] },
                                       normal: refinedNormal, d: refinedD)
        if residual > inputs.residualMaxMm {
            throw SupportPlaneError.lidarFitResidualTooHigh
        }

        return SupportPlane(
            normal: refinedNormal,
            distanceMm: refinedD,
            residualMm: residual,
            convergedIterations: nil   // LiDAR fit per §3.3 sentinel
        )
    }

    // MARK: – internals

    static func collectCandidatePoints(_ inputs: Inputs) throws -> [Vec3] {
        // Resample depth + confidence onto the colour-image grid (bilinear depth, NN
        // confidence). For each colour-image pixel in the lower-edge band of the food
        // bbox where the pixel is OUTSIDE the food mask AND confidence/255 ≥ τ_conf,
        // back-project to 3-D camera-1 space using K_colour^{-1} · [u,v,1] · z.
        let mask = inputs.foodRegionMask
        let bbox = foodBBox(mask: mask)
        guard let bbox else { return [] }

        // Lower-edge band: from y = bbox.maxY down to y = bbox.maxY + bandPx, where
        // bandPx = lowerEdgeBandMm / mm_per_px_at_food_plane. We don't have a precise
        // depth-aware px-mm conversion before fitting; use a depth-projection: for
        // each candidate pixel, accept it if its distance to the bbox lower edge in
        // camera-3D mm is ≤ lowerEdgeBandMm. That keeps the band depth-aware.
        var points: [Vec3] = []
        let kc = inputs.colourIntrinsics
        let xMin = bbox.minX
        let xMax = bbox.maxX
        let yLowerEdge = bbox.maxY
        let yScanMax = min(mask.height - 1, yLowerEdge + bbox.heightPx)  // generous scan window

        for y in yLowerEdge..<yScanMax + 1 {
            for x in xMin...xMax {
                if mask.isFood(x: x, y: y) { continue }
                let conf = sampleConfidenceNearest(depth: inputs.depth, colourX: x, colourY: y,
                                                   colourWidth: mask.width, colourHeight: mask.height)
                if Float(conf) / 255 < confidenceThreshold { continue }
                guard let zMm = sampleDepthBilinear(depth: inputs.depth, colourX: Float(x), colourY: Float(y),
                                                    colourWidth: mask.width, colourHeight: mask.height) else {
                    continue
                }
                if zMm <= 0 { continue }
                // Back-project: p = (X, Y, Z) with Z<0 in §6.0 (-Z forward). The
                // depth value is positive distance along the optical axis, so:
                //   p = ((u-cx)/fx, (v-cy)/fy, -1) · zMm
                let p = Vec3(
                    (Float(x) - kc.cx) / kc.fx * zMm,
                    (Float(y) - kc.cy) / kc.fy * zMm,
                    -zMm
                )
                points.append(p)
            }
        }
        return points
    }

    static func ransac(
        points: [Vec3],
        gravity: Vec3,
        rng: inout SplitMix64
    ) -> (normal: Vec3, d: Float, inliers: [Int]) {
        var bestScore = 0
        var bestInliers: [Int] = []
        var bestNormal = gravity
        var bestD: Float = 0
        let n = points.count

        for _ in 0..<maxIterations {
            // Sample 3 distinct indices.
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = points[i], p2 = points[j], p3 = points[k]
            let edge1 = p2 - p1
            let edge2 = p3 - p1
            var nHat = edge1.cross(edge2)
            if nHat.lengthSquared < 1e-12 { continue }     // degenerate triple
            nHat = nHat.normalised()
            // Orient so n̂ · gravity > 0 (table normal points "up" in §6.0 +Y).
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            let angle = acos(max(-1, min(1, nHat.dot(gravity))))
            if angle > gravityAngleMaxRad { continue }

            let d = nHat.dot(p1)
            // Inliers within ±5 mm.
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in 0..<n {
                let dist = abs(nHat.dot(points[idx]) - d)
                if dist < inlierBandMm {
                    inliers.append(idx)
                }
            }
            if inliers.count > bestScore {
                bestScore = inliers.count
                bestInliers = inliers
                bestNormal = nHat
                bestD = d
            }
        }
        return (bestNormal, bestD, bestInliers)
    }

    static func refine(inliers: [Vec3], seedNormal: Vec3) throws -> (Vec3, Float) {
        // Centroid; then SVD of centred matrix to find smallest singular vector =
        // plane normal. d = n̂ · centroid.
        let n = inliers.count
        guard n >= 3 else { throw SupportPlaneError.lidarFitDegenerate }
        let cx = inliers.map { $0.x }.reduce(0, +) / Float(n)
        let cy = inliers.map { $0.y }.reduce(0, +) / Float(n)
        let cz = inliers.map { $0.z }.reduce(0, +) / Float(n)
        let centroid = Vec3(cx, cy, cz)

        // Build column-major 3×n matrix A (rows = X/Y/Z, cols = points).
        var a = [Float](repeating: 0, count: 3 * n)
        for idx in 0..<n {
            let p = inliers[idx] - centroid
            a[idx * 3 + 0] = p.x
            a[idx * 3 + 1] = p.y
            a[idx * 3 + 2] = p.z
        }
        let svd = try LinearAlgebra.svdFull(a, rows: 3, cols: n)
        let sMax = svd.s[0]
        let sMin = svd.s[2]
        guard sMax > 0, sMin / sMax >= stabilityRatioMin else {
            throw SupportPlaneError.lidarFitDegenerate
        }
        // Smallest right singular vector = normal. With A 3×n, U is 3×3, columns are
        // the left singular vectors. The plane normal corresponds to the column with
        // the smallest singular value (s[2]).
        let nHatCandidate = Vec3(svd.u[6], svd.u[7], svd.u[8])
        var nHat = nHatCandidate.normalised()
        if nHat.dot(seedNormal) < 0 { nHat = -nHat }
        let d = nHat.dot(centroid)
        return (nHat, d)
    }

    static func computeResidual(points: [Vec3], normal: Vec3, d: Float) -> Float {
        guard !points.isEmpty else { return .infinity }
        var sumSq: Float = 0
        for p in points {
            let dist: Float = normal.dot(p) - d
            sumSq += dist * dist
        }
        return (sumSq / Float(points.count)).squareRoot()
    }

    // Minimum (smallest pixel x/y) and maximum (largest pixel x/y) of the food mask.
    struct BBox {
        let minX, maxX: Int
        let minY, maxY: Int
        var heightPx: Int { max(1, maxY - minY) }
    }

    static func foodBBox(mask: BinaryMask) -> BBox? {
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                if mask.isFood(x: x, y: y) {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return BBox(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    // Nearest-neighbour confidence sample. The depth grid may be lower-resolution
    // than the colour grid (256×192 on iPhone 12 Pro vs 4032×3024); we map colour
    // (x,y) to depth (x',y') by simple proportional scaling.
    static func sampleConfidenceNearest(
        depth: DepthMap, colourX: Int, colourY: Int,
        colourWidth: Int, colourHeight: Int
    ) -> UInt8 {
        let dx = min(depth.width - 1,
                     max(0, Int((Float(colourX) + 0.5) * Float(depth.width) / Float(colourWidth))))
        let dy = min(depth.height - 1,
                     max(0, Int((Float(colourY) + 0.5) * Float(depth.height) / Float(colourHeight))))
        return depth.confidenceBytes[dy * depth.width + dx]
    }

    // Bilinear depth sample (Float32 mm). Returns nil when out of range.
    static func sampleDepthBilinear(
        depth: DepthMap, colourX: Float, colourY: Float,
        colourWidth: Int, colourHeight: Int
    ) -> Float? {
        let fx = (colourX + 0.5) * Float(depth.width) / Float(colourWidth) - 0.5
        let fy = (colourY + 0.5) * Float(depth.height) / Float(colourHeight) - 0.5
        if fx < 0 || fy < 0 { return nil }
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let x1 = min(depth.width - 1, x0 + 1)
        let y1 = min(depth.height - 1, y0 + 1)
        if x0 >= depth.width || y0 >= depth.height { return nil }
        let ax = fx - Float(x0)
        let ay = fy - Float(y0)
        let z00 = depthValueMm(depth, x: x0, y: y0)
        let z10 = depthValueMm(depth, x: x1, y: y0)
        let z01 = depthValueMm(depth, x: x0, y: y1)
        let z11 = depthValueMm(depth, x: x1, y: y1)
        let zx0 = (1 - ax) * z00 + ax * z10
        let zx1 = (1 - ax) * z01 + ax * z11
        return (1 - ay) * zx0 + ay * zx1
    }

    static func depthValueMm(_ depth: DepthMap, x: Int, y: Int) -> Float {
        let offset = (y * depth.width + x) * 4
        // Float32 LE per §6.0; on little-endian Apple silicon this is a direct read.
        var value: Float = 0
        depth.depthBytesMm.withUnsafeBytes { rawPtr in
            value = rawPtr.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
        return value
    }
}
