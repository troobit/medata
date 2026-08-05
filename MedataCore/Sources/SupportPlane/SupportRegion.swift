import CaptureKit
import Foundation
import PortableContracts

// Restricted support-plane fit per design §"Bound the candidate set to an annulus" /
// §"Candidate scoring — CC-RANSAC" / §"Selection and admissibility". Extracts up to
// `maxCandidatePlanes` gravity-aligned planes from an annulus around the food mask
// on the NATIVE depth grid (Req 2.4), scores each by its largest 8-connected inlier
// component (CC-RANSAC, Decision 13), and selects the admissible candidate with the
// highest inner-band ring support fraction (Decisions 18–22).
//
// Reuses `LiDARPlaneFitter.refine` / `.computeResidual` / the 15° gravity cone / the
// 5 mm inlier band unchanged (design §"What changes and what does not").

// Which reference produced a support plane for an attempt (Req 4.4, 6.1).
public enum SupportPlaneReference: String, Sendable, Codable, Equatable {
    case foodSupport
    case edgeBand
}

// Contact-ring evidence for a candidate plane (Req 3.1, 3.6, 3.8; Decisions 14, 18–20).
// `bandMedianMm` / `bandSampleCount` are ordered [inner, mid, outer].
public struct RingStatistics: Sendable, Equatable {
    // Whole-ring median signed height above the plane. Persisted for Req 6.2;
    // NOT used for selection (Decision 9) — see `supportFraction`.
    public let medianMm: Float
    // Per-band medians; rises outward on a rimmed plate (Decision 14). The
    // admission step guard reads [0]→[1] only (Decision 21).
    public let bandMedianMm: [Float]
    // Inner-band share of samples within ±ringBandMm of the plane — the score
    // (Decision 18's replacement for |median|).
    public let supportFraction: Float
    // Inner-band sectors meeting `sectorSupportMin`; empty sectors count as
    // neither supporting nor failing (Decision 20). Persisted for Req 6.4.
    public let supportingSectors: Int
    // ringMinSamples holds PER BAND (Decisions 14, 20).
    public let bandSampleCount: [Int]
    // Annulus samples within inlierBandMm of the plane ÷ food sample count
    // (Decision 14, Req 3.9). Native depth samples on both sides — dimensionless.
    public let supportVisibility: Float

    public init(medianMm: Float, bandMedianMm: [Float], supportFraction: Float,
                supportingSectors: Int, bandSampleCount: [Int], supportVisibility: Float) {
        self.medianMm = medianMm
        self.bandMedianMm = bandMedianMm
        self.supportFraction = supportFraction
        self.supportingSectors = supportingSectors
        self.bandSampleCount = bandSampleCount
        self.supportVisibility = supportVisibility
    }
}

// A gravity-aligned plane extracted from one CC-RANSAC pass over the residue
// (Decision 13). `inlierIndices` are the largest-8-connected-component members,
// as NATIVE DEPTH-GRID linear indices (y·width+x) — used for the extent guard
// and for reporting.
struct SupportPlaneCandidate {
    let normal: Vec3
    let d: Float
    let residualMm: Float
    let inlierIndices: [Int]
    // Raw (pre-CC) inlier ratio observed at the winning hypothesis, reported so
    // the iteration budget's sufficiency is a measurement (design §"Extraction
    // loop" / §"Iteration budget", Decision 15).
    let residueInlierRatio: Float
}

public enum SupportRegion {
    // MARK: - Constants (design §"Components and Interfaces")
    // Radii in MILLIMETRES, converted per capture from median food depth.
    // Provenance markers per the design: [derived] has a stated derivation here;
    // [inherited] reuses a named tested constant; [owed] is a task 26 corpus
    // measurement — the values below are the design's stated placeholders.
    public static let ringInnerMm: Float = 8    // [derived] ~4 px smear ≈ 8 mm at 350 mm
    public static let ringOuterMm: Float = 25   // [owed]
    public static let ringBandCount = 3         // structural: inner/mid/outer
    public static let bandStepMaxMm: Float = 6  // [owed]
    public static let supportVisibilityMin: Float = 0.15 // [owed]
    public static let ringBandMm: Float = LiDARPlaneFitter.inlierBandMm // [inherited]
    public static let ringSupportMin: Float = 0.6 // [owed]
    // Sector measure (Req 3.6, Decisions 18–20).
    public static let ringSectorCount = 8            // [owed] Req 3.7
    public static let sectorSupportMin: Float = 0.5  // [owed] Req 3.7
    public static let minSupportingSectors = 6       // [owed] Req 3.7
    public static let ringSupportMarginMin: Float = 0.15 // [owed]
    public static let escapeBandMm: Float = 30       // [owed] Decision 22
    // [derived] ringSectorCount × 25 (Decision 20): at 25 samples per sector a
    // 0.5 bar has binomial σ ≈ 0.10. Holds per radial band.
    public static let ringMinSamples = 200
    // [derived] Decision 22 — replaces foodAboveFractionMax.
    public static let foodEnvelopePercentile: Float = 0.90
    public static let foodEnvelopeMinMm: Float = 0    // [owed] Decision 22
    public static let maxCandidatePlanes = 3     // structural: table, support, one more
    public static let minCandidateSamples = 500  // [owed]
    public static let minAcceptedExtentPx = 24   // [owed]
    public static let maxIterationsPerPass = 2048 // [derived] adaptive stopping caps it

    static let confidenceThreshold: Float = LiDARPlaneFitter.confidenceThreshold
    // Amortisation factor for connected-component labelling (design §"Connected-
    // component labelling is the dominant term"): only hypotheses whose raw
    // inlier count is within this factor of the running best get CC-labelled.
    static let ccAmortizeFactor: Float = 0.5

    // MARK: - Depth intrinsics (Req 2.4; design §"Native depth grid, and the
    // intrinsics trap"). `depth.depthIntrinsics` is unusable on device — ARKit
    // writes it as all-zero — so depth intrinsics are derived from the colour
    // ones. The half-pixel terms match `LiDARPlaneFitter.sampleDepthBilinear`'s
    // existing convention.
    static func depthIntrinsics(from colour: CameraIntrinsics, depth: DepthMap) -> CameraIntrinsics {
        let sx = Float(depth.width) / Float(colour.imageWidth)
        let sy = Float(depth.height) / Float(colour.imageHeight)
        return CameraIntrinsics(
            fx: colour.fx * sx,
            fy: colour.fy * sy,
            cx: (colour.cx + 0.5) * sx - 0.5,
            cy: (colour.cy + 0.5) * sy - 0.5,
            distortion: [],
            imageWidth: depth.width,
            imageHeight: depth.height
        )
    }

    // MARK: - Mask downsample (Req 2.1, 2.4). A depth pixel is food when ANY
    // covered colour pixel is food — ambiguity resolves towards exclusion, so
    // the restricted fit's candidate set never contains a food pixel.
    static func depthGridMask(from colourMask: BinaryMask, depthWidth: Int, depthHeight: Int) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: depthWidth * depthHeight)
        let sx = Float(colourMask.width) / Float(depthWidth)
        let sy = Float(colourMask.height) / Float(depthHeight)
        for dy in 0..<depthHeight {
            let yStart = Int(Float(dy) * sy)
            let yEnd = max(yStart + 1, min(colourMask.height, Int(Float(dy + 1) * sy)))
            for dx in 0..<depthWidth {
                let xStart = Int(Float(dx) * sx)
                let xEnd = max(xStart + 1, min(colourMask.width, Int(Float(dx + 1) * sx)))
                var isFood = false
                yLoop: for y in yStart..<yEnd {
                    for x in xStart..<xEnd where colourMask.isFood(x: x, y: y) {
                        isFood = true
                        break yLoop
                    }
                }
                pixels[dy * depthWidth + dx] = isFood ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: depthWidth, height: depthHeight)
    }

    // MARK: - Contact ring (Req 3.1–3.9). `foodMask`/`intrinsics` are already on
    // the NATIVE DEPTH GRID — callers downsample via `depthGridMask` and derive
    // intrinsics via `depthIntrinsics` first (`fitFoodSupportPlane` does both).
    static func contactRing(foodMask: BinaryMask, depth: DepthMap, intrinsics: CameraIntrinsics) -> [Int] {
        ringAndAnnulusSamples(depthGridFoodMask: foodMask, depth: depth, depthIntrinsics: intrinsics)?
            .ring.map(\.index) ?? []
    }

    // Public convenience: computes ring statistics for an arbitrary plane (e.g.
    // the lazy edge-band fallback plane) directly from the colour-grid inputs a
    // caller has on hand, so Req 6.1's "every depth-derived attempt" holds
    // without the caller re-deriving depth intrinsics or the depth-grid mask.
    public static func ringStatistics(for plane: SupportPlane, depth: DepthMap,
                                      foodMask: BinaryMask,
                                      intrinsics colourIntrinsics: CameraIntrinsics) -> RingStatistics? {
        let depthIntr = depthIntrinsics(from: colourIntrinsics, depth: depth)
        let depthMask = depthGridMask(from: foodMask, depthWidth: depth.width, depthHeight: depth.height)
        return ringStatistics(foodMask: depthMask, depth: depth, intrinsics: depthIntr, plane: plane)
    }

    // Depth-grid-native entry point directly unit-tested (design §"contactRing
    // and ringStatistics are internal but directly unit-tested"). NOTE: this
    // takes the plane and derives ring + annulus itself, rather than the raw
    // index arrays the design's illustrative signature sketched — `ring`/
    // `annulus` there had no way to carry the 3-D points and angles the
    // statistics actually need without recomputing the mask's distance field a
    // second time per call.
    static func ringStatistics(foodMask: BinaryMask, depth: DepthMap, intrinsics: CameraIntrinsics,
                               plane: SupportPlane) -> RingStatistics? {
        guard let samples = ringAndAnnulusSamples(depthGridFoodMask: foodMask, depth: depth,
                                                   depthIntrinsics: intrinsics) else { return nil }
        let foodCount = foodSamplePoints(mask: foodMask, depth: depth, intrinsics: intrinsics).count
        guard foodCount > 0 else { return nil }
        return ringStatistics(ring: samples.ring, annulus: samples.annulus,
                              foodSampleCount: foodCount, plane: plane)
    }

    // MARK: - fitFoodSupportPlane (Req 1.1–1.3, 3.*, 7.7). nil when no candidate
    // is admissible — the caller then runs the edge-band fit (Req 4.1). Never
    // throws: rejection is an expected outcome, not an error.
    public static func fitFoodSupportPlane(
        depth: DepthMap, colourIntrinsics: CameraIntrinsics,
        foodRegionMask: BinaryMask, gravityCamera: Vec3
    ) -> (plane: SupportPlane, ring: RingStatistics, candidateCount: Int)? {
        let depthIntr = depthIntrinsics(from: colourIntrinsics, depth: depth)
        let depthMask = depthGridMask(from: foodRegionMask, depthWidth: depth.width, depthHeight: depth.height)
        guard let samples = ringAndAnnulusSamples(depthGridFoodMask: depthMask, depth: depth,
                                                   depthIntrinsics: depthIntr) else { return nil }
        guard samples.annulus.count >= minCandidateSamples else { return nil }

        let foodPoints = foodSamplePoints(mask: depthMask, depth: depth, intrinsics: depthIntr)
        guard !foodPoints.isEmpty else { return nil }

        let gravity = gravityCamera.normalised()
        let seed = Fnv1a64.hash(depth.depthBytesMm)
        var rng = SplitMix64(seed: seed)
        let annulusPoints = samples.annulus.map(\.point)
        let annulusIdx = samples.annulus.map(\.index)
        let candidates = extractCandidatePlanes(
            points: annulusPoints, depthIndices: annulusIdx,
            width: depth.width, height: depth.height, gravity: gravity, rng: &rng
        )
        guard !candidates.isEmpty else { return nil }

        struct Scored {
            let plane: SupportPlane
            let ring: RingStatistics
        }
        var scored: [Scored] = []
        for candidate in candidates {
            let plane = SupportPlane(normal: candidate.normal, distanceMm: candidate.d,
                                     residualMm: candidate.residualMm, convergedIterations: nil)
            guard let ring = ringStatistics(ring: samples.ring, annulus: samples.annulus,
                                            foodSampleCount: foodPoints.count, plane: plane) else { continue }
            guard isAdmissible(candidate: candidate, ring: ring, plane: plane,
                               annulus: samples.annulus, foodPoints: foodPoints,
                               width: depth.width) else { continue }
            scored.append(Scored(plane: plane, ring: ring))
        }
        guard !scored.isEmpty else { return nil }
        scored.sort { $0.ring.supportFraction > $1.ring.supportFraction }
        if scored.count >= 2,
           scored[0].ring.supportFraction - scored[1].ring.supportFraction < ringSupportMarginMin {
            return nil
        }
        let winner = scored[0]
        return (winner.plane, winner.ring, candidates.count)
    }

    // MARK: - Admissibility (design §"Selection and admissibility", Decisions 18–22)
    static func isAdmissible(
        candidate: SupportPlaneCandidate, ring: RingStatistics, plane: SupportPlane,
        annulus: [RingSample], foodPoints: [Vec3], width: Int
    ) -> Bool {
        // ring support fraction < ringSupportMin → ring not resting on this plane (Req 3.2)
        guard ring.supportFraction >= ringSupportMin else { return false }
        // supporting sectors < minSupportingSectors → ring crossed the support's
        // edge, or straddles two surfaces (Req 2.3, 3.6, Decisions 18–20)
        guard ring.supportingSectors >= minSupportingSectors else { return false }
        // food's p90 signed height above the plane < foodEnvelopeMinMm → vessel
        // rim, or a plane on the food top (Req 3.4, Decision 22)
        let foodHeights = foodPoints.map { plane.normal.dot($0) - plane.distanceMm }
        guard percentile(foodHeights, foodEnvelopePercentile) >= foodEnvelopeMinMm else { return false }
        // |ring median| outside the documented band around zero, signed (Req 3.1, 3.2)
        guard abs(ring.medianMm) <= ringBandMm else { return false }
        // inner→mid band step > bandStepMaxMm rising outward → not flat (Req 3.8, Decision 21)
        guard ring.bandMedianMm.count == ringBandCount,
              ring.bandMedianMm[1] - ring.bandMedianMm[0] <= bandStepMaxMm else { return false }
        // support visibility < supportVisibilityMin → support surface not
        // observable under the food (Req 3.9)
        guard ring.supportVisibility >= supportVisibilityMin else { return false }
        // plane below the annulus median height by > escapeBandMm → region
        // escaped through a depth dropout (Req 3.3, Decision 22)
        let annulusHeights = annulus.map { plane.normal.dot($0.point) - plane.distanceMm }
        guard median(annulusHeights) <= escapeBandMm else { return false }
        // fewer than minAcceptedExtentPx inlier bbox extent → badly conditioned normal (Req 2.3)
        guard inlierExtentPx(indices: candidate.inlierIndices, width: width) >= minAcceptedExtentPx
        else { return false }
        return true
    }

    // MARK: - Geometry internals

    // One depth-grid non-food sample, with its 3-D back-projection, its
    // distance to the food mask boundary (mm, converted via the per-capture
    // scale from median food depth), and its angle about the food-mask
    // centroid for sector bucketing (Req 3.6).
    struct RingSample {
        let index: Int
        let point: Vec3
        let distMm: Float
        let angle: Float
    }

    // Computes the ring (ringInnerMm..<ringOuterMm) and annulus
    // (0..<2×ringOuterMm) samples in one pass over the depth grid, sharing one
    // distance-field computation (design §"Bound the candidate set to an
    // annulus": "ring is the region the [candidate] set already reads").
    static func ringAndAnnulusSamples(
        depthGridFoodMask mask: BinaryMask, depth: DepthMap, depthIntrinsics intrinsics: CameraIntrinsics
    ) -> (ring: [RingSample], annulus: [RingSample])? {
        guard let medianZ = medianFoodDepthMm(mask: mask, depth: depth),
              let centroid = foodMaskCentroid(mask) else { return nil }
        let focalAvg = (intrinsics.fx + intrinsics.fy) / 2
        guard focalAvg > 0 else { return nil }
        let mmPerPixel = medianZ / focalAvg
        guard mmPerPixel > 0 else { return nil }
        let field = chamferDistanceField(foodMask: mask)
        let candidateBoundMm = 2 * ringOuterMm

        var ring: [RingSample] = []
        var annulus: [RingSample] = []
        let w = depth.width, h = depth.height
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if mask.isFood(x: x, y: y) { continue }
                let distMm = field.distancePx[i] * mmPerPixel
                guard distMm > 0, distMm < candidateBoundMm else { continue }
                let conf = depth.confidenceBytes.isEmpty ? UInt8.max : depth.confidenceBytes[i]
                if Float(conf) / 255 < confidenceThreshold { continue }
                let z = LiDARPlaneFitter.depthValueMm(depth, x: x, y: y)
                guard z > 0 else { continue }
                let p = Vec3((Float(x) - intrinsics.cx) / intrinsics.fx * z,
                            (Float(y) - intrinsics.cy) / intrinsics.fy * z, -z)
                let angle = atan2(Float(y) - centroid.y, Float(x) - centroid.x)
                let sample = RingSample(index: i, point: p, distMm: distMm, angle: angle)
                annulus.append(sample)
                if distMm >= ringInnerMm, distMm < ringOuterMm {
                    ring.append(sample)
                }
            }
        }
        return (ring, annulus)
    }

    // Core statistics computation shared by both public entry points, given
    // already-collected ring/annulus samples (avoids recomputing the distance
    // field once per candidate plane in `fitFoodSupportPlane`).
    static func ringStatistics(
        ring: [RingSample], annulus: [RingSample], foodSampleCount: Int, plane: SupportPlane
    ) -> RingStatistics? {
        let bandWidth = (ringOuterMm - ringInnerMm) / Float(ringBandCount)
        guard bandWidth > 0 else { return nil }
        var bandSamples: [[RingSample]] = Array(repeating: [], count: ringBandCount)
        for s in ring {
            var bandIdx = Int((s.distMm - ringInnerMm) / bandWidth)
            bandIdx = min(max(bandIdx, 0), ringBandCount - 1)
            bandSamples[bandIdx].append(s)
        }
        let bandSampleCount = bandSamples.map(\.count)
        guard bandSampleCount.allSatisfy({ $0 >= ringMinSamples }) else { return nil }

        func signedHeights(_ arr: [RingSample]) -> [Float] {
            arr.map { plane.normal.dot($0.point) - plane.distanceMm }
        }
        let bandMedianMm = bandSamples.map { median(signedHeights($0)) }
        let medianMm = median(signedHeights(ring))

        let innerSamples = bandSamples[0]
        let innerHeights = signedHeights(innerSamples)
        let supportedFlags = innerHeights.map { abs($0) <= ringBandMm }
        let supportCount = supportedFlags.filter { $0 }.count
        let supportFraction = innerSamples.isEmpty ? 0 : Float(supportCount) / Float(innerSamples.count)

        var sectorTotal = [Int](repeating: 0, count: ringSectorCount)
        var sectorSupport = [Int](repeating: 0, count: ringSectorCount)
        for (idx, sample) in innerSamples.enumerated() {
            let sector = sectorIndex(for: sample.angle)
            sectorTotal[sector] += 1
            if supportedFlags[idx] { sectorSupport[sector] += 1 }
        }
        var supportingSectors = 0
        for sec in 0..<ringSectorCount where sectorTotal[sec] > 0 {
            let frac = Float(sectorSupport[sec]) / Float(sectorTotal[sec])
            if frac >= sectorSupportMin { supportingSectors += 1 }
        }

        guard foodSampleCount > 0 else { return nil }
        let annulusInliers = annulus.filter {
            abs(plane.normal.dot($0.point) - plane.distanceMm) <= LiDARPlaneFitter.inlierBandMm
        }.count
        let supportVisibility = Float(annulusInliers) / Float(foodSampleCount)

        return RingStatistics(
            medianMm: medianMm, bandMedianMm: bandMedianMm, supportFraction: supportFraction,
            supportingSectors: supportingSectors, bandSampleCount: bandSampleCount,
            supportVisibility: supportVisibility
        )
    }

    static func sectorIndex(for angle: Float) -> Int {
        var a = angle
        if a < 0 { a += 2 * Float.pi }
        let sectorWidth = 2 * Float.pi / Float(ringSectorCount)
        var idx = Int(a / sectorWidth)
        idx = min(max(idx, 0), ringSectorCount - 1)
        return idx
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }

    static func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = min(sorted.count - 1, max(0, Int((p * Float(sorted.count - 1)).rounded())))
        return sorted[idx]
    }

    static func medianFoodDepthMm(mask: BinaryMask, depth: DepthMap) -> Float? {
        var values: [Float] = []
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                let z = LiDARPlaneFitter.depthValueMm(depth, x: x, y: y)
                if z > 0 { values.append(z) }
            }
        }
        guard !values.isEmpty else { return nil }
        return median(values)
    }

    static func foodMaskCentroid(_ mask: BinaryMask) -> (x: Float, y: Float)? {
        var sx: Float = 0, sy: Float = 0, n: Float = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                sx += Float(x); sy += Float(y); n += 1
            }
        }
        guard n > 0 else { return nil }
        return (sx / n, sy / n)
    }

    static func foodSamplePoints(mask: BinaryMask, depth: DepthMap, intrinsics: CameraIntrinsics) -> [Vec3] {
        var out: [Vec3] = []
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                let z = LiDARPlaneFitter.depthValueMm(depth, x: x, y: y)
                guard z > 0 else { continue }
                out.append(Vec3((Float(x) - intrinsics.cx) / intrinsics.fx * z,
                                (Float(y) - intrinsics.cy) / intrinsics.fy * z, -z))
            }
        }
        return out
    }

    // Two-pass chamfer distance transform (pixel units) to the nearest food
    // pixel; 0 inside the food mask. An approximation to true Euclidean
    // distance, adequate at the ring/annulus scale (design's radii are tens of
    // millimetres, a handful of depth pixels).
    struct DistanceField {
        let distancePx: [Float]
        let width: Int
        let height: Int
    }

    static func chamferDistanceField(foodMask: BinaryMask) -> DistanceField {
        let w = foodMask.width, h = foodMask.height
        let inf: Float = 1e9
        var dist = [Float](repeating: inf, count: w * h)
        for y in 0..<h {
            for x in 0..<w where foodMask.isFood(x: x, y: y) {
                dist[y * w + x] = 0
            }
        }
        let diag: Float = 1.4142135
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                var best = dist[i]
                if x > 0 { best = min(best, dist[i - 1] + 1) }
                if y > 0 { best = min(best, dist[i - w] + 1) }
                if x > 0, y > 0 { best = min(best, dist[i - w - 1] + diag) }
                if x < w - 1, y > 0 { best = min(best, dist[i - w + 1] + diag) }
                dist[i] = best
            }
        }
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = y * w + x
                var best = dist[i]
                if x < w - 1 { best = min(best, dist[i + 1] + 1) }
                if y < h - 1 { best = min(best, dist[i + w] + 1) }
                if x < w - 1, y < h - 1 { best = min(best, dist[i + w + 1] + diag) }
                if x > 0, y < h - 1 { best = min(best, dist[i + w - 1] + diag) }
                dist[i] = best
            }
        }
        return DistanceField(distancePx: dist, width: w, height: h)
    }

    // MARK: - CC-RANSAC extraction (Decision 13, 15; design §"Extraction loop")

    struct RansacHypothesis {
        let normal: Vec3
        let d: Float
        let ccInlierIndices: [Int]   // local indices into the pass's point array
        let rawInlierRatio: Float
    }

    // Adaptive per-pass iteration count (design §"Iteration budget"): derives N
    // from the best observed inlier ratio rather than a fixed 256/2048.
    static func requiredRansacIterations(inlierRatio w: Float, confidence: Float = 0.99) -> Int {
        guard w > 0, w < 1 else { return maxIterationsPerPass }
        let wCubed = Double(w) * Double(w) * Double(w)
        let denom = log(max(1e-12, 1 - wCubed))
        guard denom < 0 else { return maxIterationsPerPass }
        let numer = log(1 - Double(confidence))
        let needed = Int((numer / denom).rounded(.up))
        return max(1, min(maxIterationsPerPass, needed))
    }

    // Largest 8-connected component among `indices` (native depth-grid linear
    // indices). Returns its members. O(n) — each index visited once.
    static func largestConnectedComponent(indices: [Int], width: Int, height: Int) -> [Int] {
        guard !indices.isEmpty else { return [] }
        let indexSet = Set(indices)
        var visited = Set<Int>()
        var best: [Int] = []
        for start in indices {
            if visited.contains(start) { continue }
            visited.insert(start)
            var stack = [start]
            var comp: [Int] = []
            while let cur = stack.popLast() {
                comp.append(cur)
                let cx = cur % width, cy = cur / width
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let nb = ny * width + nx
                        guard indexSet.contains(nb), !visited.contains(nb) else { continue }
                        visited.insert(nb)
                        stack.append(nb)
                    }
                }
            }
            if comp.count > best.count { best = comp }
        }
        return best
    }

    // One CC-RANSAC pass over the current residue. Draws exactly 3
    // `rng.uniformInt` calls per iteration unconditionally (matching
    // `LiDARPlaneFitter.ransac`), so the RNG sequence stays pass-count-
    // independent when one generator is threaded across passes (Decision 15).
    static func ransacPass(
        points: [Vec3], depthIndices: [Int], width: Int, height: Int,
        gravity: Vec3, rng: inout SplitMix64
    ) -> RansacHypothesis? {
        let n = points.count
        guard n >= LiDARPlaneFitter.minPoints else { return nil }
        var bestRawCount = 0
        var bestCCSize = 0
        var best: RansacHypothesis?
        var requiredIterations = maxIterationsPerPass
        var iter = 0
        while iter < requiredIterations {
            iter += 1
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = points[i], p2 = points[j], p3 = points[k]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            let angle = acos(max(-1, min(1, nHat.dot(gravity))))
            if angle > LiDARPlaneFitter.gravityAngleMaxRad { continue }
            let d = nHat.dot(p1)

            var rawInliers: [Int] = []
            rawInliers.reserveCapacity(n)
            for idx in 0..<n where abs(nHat.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                rawInliers.append(idx)
            }
            guard !rawInliers.isEmpty else { continue }

            if rawInliers.count > bestRawCount {
                bestRawCount = rawInliers.count
                let w = Float(bestRawCount) / Float(n)
                requiredIterations = min(requiredIterations, requiredRansacIterations(inlierRatio: w))
            }

            if Float(rawInliers.count) >= Float(bestRawCount) * ccAmortizeFactor {
                let localDepthIndices = rawInliers.map { depthIndices[$0] }
                let component = largestConnectedComponent(indices: localDepthIndices, width: width, height: height)
                if component.count > bestCCSize {
                    bestCCSize = component.count
                    let componentSet = Set(component)
                    let ccInliers = rawInliers.filter { componentSet.contains(depthIndices[$0]) }
                    best = RansacHypothesis(normal: nHat, d: d, ccInlierIndices: ccInliers,
                                            rawInlierRatio: Float(rawInliers.count) / Float(n))
                }
            }
        }
        return best
    }

    // Sequential extraction: up to `maxCandidatePlanes` passes, each removing
    // the polished inlier set within 2×inlierBandMm from the residue (a 1×
    // shell seeds near-duplicate planes on the next pass, design §"Extraction
    // loop"). One RNG threaded across all passes (Decision 15).
    static func extractCandidatePlanes(
        points initialPoints: [Vec3], depthIndices initialIndices: [Int],
        width: Int, height: Int, gravity: Vec3, rng: inout SplitMix64
    ) -> [SupportPlaneCandidate] {
        var points = initialPoints
        var indices = initialIndices
        var candidates: [SupportPlaneCandidate] = []
        var pass = 0
        while pass < maxCandidatePlanes, points.count >= minCandidateSamples {
            pass += 1
            guard let hyp = ransacPass(points: points, depthIndices: indices, width: width, height: height,
                                       gravity: gravity, rng: &rng),
                  hyp.ccInlierIndices.count >= LiDARPlaneFitter.minPoints else { break }
            guard let (refinedNormal, refinedD) = try? LiDARPlaneFitter.refine(
                inliers: hyp.ccInlierIndices.map { points[$0] }, seedNormal: hyp.normal
            ) else { break }

            // Re-select against the refined plane and take its largest CC once
            // more — the deterministic polish step §"What changes and what does
            // not" says is reused.
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(refinedNormal.dot(points[idx]) - refinedD) < LiDARPlaneFitter.inlierBandMm {
                reselected.append(idx)
            }
            let reselectedDepthIdx = reselected.map { indices[$0] }
            let component = largestConnectedComponent(indices: reselectedDepthIdx, width: width, height: height)
            guard component.count >= LiDARPlaneFitter.minPoints else { break }
            let componentSet = Set(component)
            let finalInliers = reselected.filter { componentSet.contains(indices[$0]) }

            let residual = LiDARPlaneFitter.computeResidual(
                points: finalInliers.map { points[$0] }, normal: refinedNormal, d: refinedD
            )
            let finalDepthIndices = finalInliers.map { indices[$0] }
            candidates.append(SupportPlaneCandidate(
                normal: refinedNormal, d: refinedD, residualMm: residual,
                inlierIndices: finalDepthIndices, residueInlierRatio: hyp.rawInlierRatio
            ))

            var nextPoints: [Vec3] = []
            var nextIndices: [Int] = []
            nextPoints.reserveCapacity(points.count)
            nextIndices.reserveCapacity(indices.count)
            for idx in 0..<points.count {
                let dist = abs(refinedNormal.dot(points[idx]) - refinedD)
                if dist >= 2 * LiDARPlaneFitter.inlierBandMm {
                    nextPoints.append(points[idx])
                    nextIndices.append(indices[idx])
                }
            }
            points = nextPoints
            indices = nextIndices
        }
        return candidates
    }

    static func inlierExtentPx(indices: [Int], width: Int) -> Int {
        guard !indices.isEmpty else { return 0 }
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for idx in indices {
            let x = idx % width, y = idx / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        return min(maxX - minX + 1, maxY - minY + 1)
    }
}
