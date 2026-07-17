import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// LiDAR support-plane RANSAC fitter per design §6.2. Pure function over the depth
// map, the food-region mask resampled to the colour grid, the camera intrinsics, and
// gravity. RNG is seeded by hashing the depth bytes (per §6.0) so two runs on the
// same fixture produce identical inliers.
public enum LiDARPlaneFitter {
    // Tunable parameters per design §6.2 ("Parameter justification").
    static let lowerEdgeBandMm: Float = 30
    // τ_conf: minimum normalised LiDAR confidence for a table pixel to seed the
    // fit. ARKit maps `ARConfidenceLevel.{low,medium,high}` → bytes `{0,127,255}`
    // (§6.0). Lowered from 0.66 (HIGH-only) to 0.40 per Decision 47 so MEDIUM
    // (127/255 = 0.498) is accepted and only genuine LOW/zero returns are dropped.
    // A matte / low-reflectance table returns a weaker LiDAR signal dominated by
    // MEDIUM confidence; the HIGH-only gate starved the fit → `noLidarPoints` →
    // the user-facing "no flat surface". The RANSAC 5 mm inlier band + 20 mm
    // residual gate still reject a bad plane, and σ_plane = exp(−r/5) carries the
    // extra medium-confidence noise into the confidence surface (Decision 46).
    // Bug `lidar-plane-fit-matte-table-confidence` 2026-07-06.
    static let confidenceThreshold: Float = 0.40
    static let maxIterations: Int = 256
    static let inlierBandMm: Float = 5
    static let gravityAngleMaxRad: Float = 15 * .pi / 180
    // Raised from 8 mm to 20 mm per Decision 46 / Req §4.5. Residuals in (8, 20]
    // accept the fit; σ_plane = exp(−r/5) carries the degradation (at r = 20 mm,
    // σ_plane ≈ 0.018, near the ε = 0.01 floor).
    public static let residualMaxMm: Float = 20
    static let stabilityRatioMin: Float = 1e-6
    static let minPoints: Int = 3
    // Upper bound on the deterministic consensus-polish passes after the RANSAC
    // winner is refined (estimation-runtime-consistency, PRD estimation-quality).
    // The loop usually exits earlier because the inlier set reaches a fixed point.
    static let consensusPolishMaxPasses: Int = 3

    // Where candidate points are sampled relative to `foodRegionMask`.
    public enum CandidateRegion: Sendable, Equatable {
        // §6.2 default: table pixels outside the food mask, in edge bands
        // around its bbox.
        case bandsAroundFoodRegion
        // Restrict candidates to pixels inside the mask; RANSAC then selects
        // the dominant plane within that region. Used by the offline harness
        // to fit the plate-top plane on a flood-filled plate region
        // (nutrition5k-calibration §Support plane, Decision 15 amendment).
        case insideMask
    }

    public struct Inputs: Sendable {
        public let depth: DepthMap
        public let colourIntrinsics: CameraIntrinsics
        public let foodRegionMask: BinaryMask    // colour-image grid
        public let gravityCamera: Vec3           // unit vector in camera-1 frame
        public let residualMaxMm: Float          // §6.2 step 5; default 8
        public let candidateRegion: CandidateRegion

        public init(depth: DepthMap, colourIntrinsics: CameraIntrinsics,
                    foodRegionMask: BinaryMask, gravityCamera: Vec3,
                    residualMaxMm: Float = LiDARPlaneFitter.residualMaxMm,
                    candidateRegion: CandidateRegion = .bandsAroundFoodRegion) {
            self.depth = depth
            self.colourIntrinsics = colourIntrinsics
            self.foodRegionMask = foodRegionMask
            self.gravityCamera = gravityCamera
            self.residualMaxMm = residualMaxMm
            self.candidateRegion = candidateRegion
        }
    }

    // Throwing convenience preserving the pre-outcome call shape for callers
    // that do not need the fit stats (harness, tests).
    public static func fit(_ inputs: Inputs) throws -> SupportPlane {
        let outcome = fitOutcome(inputs)
        if let plane = outcome.plane { return plane }
        throw outcome.refusal ?? SupportPlaneError.noLidarPoints
    }

    public static func fitOutcome(_ inputs: Inputs) -> SupportPlaneFitOutcome {
        // Step 1: collect candidate 3-D points in the colour-image lower-edge band.
        // Counters accumulate into `stats`, returned on both exits (snaq-parity
        // Req 3.1 — previously the `debugLast*` statics).
        var stats = SupportPlaneFitStats()
        let points = collectCandidatePoints(inputs, stats: &stats)
        stats.candidatePointCount = points.count
        guard points.count >= minPoints else {
            return SupportPlaneFitOutcome(plane: nil, stats: stats, refusal: .noLidarPoints)
        }

        // Step 2: RANSAC. Deterministic seed from the depth bytes (§6.0).
        let seed = Fnv1a64.hash(inputs.depth.depthBytesMm)
        var rng = SplitMix64(seed: seed)
        let gravity = inputs.gravityCamera.normalised()
        let (bestNormal, _, bestInliers) = ransac(
            points: points,
            gravity: gravity,
            rng: &rng
        )
        stats.inlierCount = bestInliers.count

        guard bestInliers.count >= minPoints else {
            return SupportPlaneFitOutcome(plane: nil, stats: stats, refusal: .noLidarPoints)
        }

        // Step 3 + 5: least-squares refinement on inliers; stability gate σ_min/σ_max.
        let refinedNormal: Vec3
        let refinedD: Float
        do {
            (refinedNormal, refinedD) = try refine(
                inliers: bestInliers.map { points[$0] },
                seedNormal: bestNormal
            )
        } catch {
            return SupportPlaneFitOutcome(
                plane: nil, stats: stats,
                refusal: (error as? SupportPlaneError) ?? .lidarFitDegenerate
            )
        }

        // Step 3b (additive robustness, estimation-runtime-consistency): consensus
        // polish. The RANSAC winner's ±5 mm inlier band is anchored to a 3-point
        // candidate plane, so points near the band edge flip membership under the
        // millimetre-level depth differences between two captures of the same
        // plate — and the LSQ plane, whose distance feeds the mm/px scale
        // (|d|/f at `Pipeline` stage E) and every height-field sample, inherits
        // that sensitivity straight into the carb reading. Re-selecting inliers
        // against the REFINED plane and re-refining until the consensus set stops
        // changing converges to a fixed point that no longer depends on which
        // minimal sample won. Fully deterministic: fixed pass cap, no RNG, stable
        // ascending point order. Conservative: a re-selection that goes
        // underpopulated, degenerate, or outside the gravity cone keeps the
        // previous pass's plane instead of failing a fit that used to succeed.
        var polishedNormal = refinedNormal
        var polishedD = refinedD
        var polishedInliers = bestInliers
        for _ in 0..<consensusPolishMaxPasses {
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(polishedNormal.dot(points[idx]) - polishedD) < inlierBandMm {
                reselected.append(idx)
            }
            if reselected == polishedInliers || reselected.count < minPoints { break }
            guard let (nextNormal, nextD) = try? refine(
                inliers: reselected.map { points[$0] },
                seedNormal: polishedNormal
            ) else { break }
            let angle = acos(max(-1, min(1, nextNormal.dot(gravity))))
            if angle > gravityAngleMaxRad { break }
            polishedInliers = reselected
            polishedNormal = nextNormal
            polishedD = nextD
        }
        stats.inlierCount = polishedInliers.count

        // Step 4: residual_mm = sqrt(mean(squared inlier signed-distances)).
        let residual = computeResidual(points: polishedInliers.map { points[$0] },
                                       normal: polishedNormal, d: polishedD)
        stats.residualMm = residual
        if residual > inputs.residualMaxMm {
            return SupportPlaneFitOutcome(
                plane: nil, stats: stats, refusal: .lidarFitResidualTooHigh
            )
        }

        let plane = SupportPlane(
            normal: polishedNormal,
            distanceMm: polishedD,
            residualMm: residual,
            convergedIterations: nil   // LiDAR fit per §3.3 sentinel
        )
        return SupportPlaneFitOutcome(plane: plane, stats: stats, refusal: nil)
    }

    // MARK: – internals

    static func collectCandidatePoints(
        _ inputs: Inputs, stats: inout SupportPlaneFitStats
    ) -> [Vec3] {
        // Resample depth + confidence onto the colour-image grid (bilinear depth, NN
        // confidence). For each colour-image pixel in an edge band around the food
        // bbox where the pixel is OUTSIDE the food mask AND confidence/255 ≥ τ_conf,
        // back-project to 3-D camera-1 space using K_colour^{-1} · [u,v,1] · z.
        //
        // Bands: bottom, top, left, right of the food bbox, each as thick as the
        // bbox dimension perpendicular to it, clipped to image bounds. The original
        // §6.2 design scanned only the lower-edge band on the assumption that the
        // camera framed the plate from above with the table visible below it. On a
        // centred capture envelope (`App/CaptureFlowModel.swift` gating) the plate
        // fills the middle of the frame and the table is visible on every side; a
        // bbox that extends close to an image edge starves the single-band scan and
        // surfaces as `noLidarPoints` or `lidarFitDegenerate` (near-collinear 3-D
        // points → singular covariance at `refine`). The four-edge scan keeps the
        // fitter's intent (collect table pixels around the plate) while tolerating
        // any side of the bbox sitting against the image edge.
        // Bug `lidar-plane-fit-degenerate-on-clean-capture` 2026-06-16.
        let mask = inputs.foodRegionMask

        if inputs.candidateRegion == .insideMask {
            // Sample every valid-depth pixel INSIDE the mask; the caller has
            // already restricted the mask to the region of interest (e.g. the
            // flood-filled plate region), so no band scan is needed.
            var points: [Vec3] = []
            let kc = inputs.colourIntrinsics
            for y in 0..<mask.height {
                for x in 0..<mask.width {
                    guard mask.isFood(x: x, y: y) else { continue }
                    let conf = sampleConfidenceNearest(depth: inputs.depth, colourX: x, colourY: y,
                                                       colourWidth: mask.width, colourHeight: mask.height)
                    if Float(conf) / 255 < confidenceThreshold { continue }
                    guard let zMm = sampleDepthBilinear(depth: inputs.depth, colourX: Float(x), colourY: Float(y),
                                                        colourWidth: mask.width, colourHeight: mask.height),
                          zMm > 0 else { continue }
                    points.append(Vec3(
                        (Float(x) - kc.cx) / kc.fx * zMm,
                        (Float(y) - kc.cy) / kc.fy * zMm,
                        -zMm
                    ))
                }
            }
            return points
        }

        guard let bbox = foodBBox(mask: mask) else { return [] }
        stats.foodBBoxX = bbox.minX
        stats.foodBBoxY = bbox.minY
        stats.foodBBoxW = bbox.widthPx
        stats.foodBBoxH = bbox.heightPx

        var points: [Vec3] = []
        let kc = inputs.colourIntrinsics
        let xMin = bbox.minX, xMax = bbox.maxX
        let yMin = bbox.minY, yMax = bbox.maxY
        // Below-bbox band starts AT bbox.maxY (food row, filtered by `isFood`) per
        // the original §6.2 design; the top/left/right bands mirror that convention
        // by starting one pixel outside the bbox in their respective directions.
        let scanRegions: [(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>)] = [
            // Below
            (xMin...xMax,
             yMax...min(mask.height - 1, yMax + bbox.heightPx)),
            // Above
            (xMin...xMax,
             max(0, yMin - bbox.heightPx)...yMin),
            // Left
            (max(0, xMin - bbox.widthPx)...xMin,
             yMin...yMax),
            // Right
            (xMax...min(mask.width - 1, xMax + bbox.widthPx),
             yMin...yMax),
        ]

        for (xRange, yRange) in scanRegions {
            for y in yRange {
                for x in xRange {
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
        // Centroid; then SVD of the 3×3 scatter matrix M = Σ (pᵢ − c)(pᵢ − c)ᵀ
        // to find the smallest singular vector = plane normal. d = n̂ · centroid.
        //
        // M's left singular vectors equal A's left singular vectors (where A is
        // the 3×n centred matrix), and M's singular values are A's squared, so
        // the stability gate becomes √(M.s[2])/√(M.s[0]) ≥ stabilityRatioMin.
        // The 3×n SVD is avoided because `LinearAlgebra.svdFull` requests
        // JOBVT='A' and allocates an n×n V^T (~32 GB at the 1920×1440 inlier
        // counts observed on iPhone 13 Pro Max). See bugfix spec
        // `specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/`.
        let n = inliers.count
        guard n >= 3 else { throw SupportPlaneError.lidarFitDegenerate }
        let cx = inliers.map { $0.x }.reduce(0, +) / Float(n)
        let cy = inliers.map { $0.y }.reduce(0, +) / Float(n)
        let cz = inliers.map { $0.z }.reduce(0, +) / Float(n)
        let centroid = Vec3(cx, cy, cz)

        // Accumulate the symmetric 3×3 scatter matrix in one O(n) pass.
        var m00: Float = 0, m01: Float = 0, m02: Float = 0
        var m11: Float = 0, m12: Float = 0, m22: Float = 0
        for idx in 0..<n {
            let p = inliers[idx] - centroid
            m00 += p.x * p.x
            m01 += p.x * p.y
            m02 += p.x * p.z
            m11 += p.y * p.y
            m12 += p.y * p.z
            m22 += p.z * p.z
        }
        // Column-major 3×3.
        let mCol: [Float] = [
            m00, m01, m02,
            m01, m11, m12,
            m02, m12, m22
        ]
        let svd = try LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)
        // svd.s holds the singular values of M, i.e., the squared singular
        // values of A. Compare √-magnitudes to keep the existing 1e-6 gate.
        let sMaxA = svd.s[0].squareRoot()
        let sMinA = svd.s[2].squareRoot()
        guard sMaxA > 0, sMinA / sMaxA >= stabilityRatioMin else {
            throw SupportPlaneError.lidarFitDegenerate
        }
        // U columns are the eigenvectors of M, ordered by descending singular
        // value. Column 2 is the smallest — the plane normal.
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
        var widthPx: Int { max(1, maxX - minX) }
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
        // No confidence map (e.g. N5k RealSense fixtures) means no confidence
        // filtering: invalid returns are zeroed depth, excluded by the zMm > 0
        // guard. Device captures always carry ARKit confidence.
        guard !depth.confidenceBytes.isEmpty else { return .max }
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
