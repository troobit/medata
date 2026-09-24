import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane

// Depth-grown food region (depth-grown-food-region smolspec, Decision 1).
//
// The segmenter can label a few percent of a food it does not know while the
// LiDAR depth shows the whole food as one raised slab with a sharp edge
// (2026-09-24 sesame roll: 0.5 % of the frame labelled, 7 % raised). Volume is
// integrated per labelled pixel, so the record under-reads by the fraction the
// model missed. This pass grows every food-like region of the label map into
// the depth cells reachable from it without crossing a cliff, so a partly
// recognised food is measured whole. Pure geometry on the single-view inputs;
// the model and the probability tensor are untouched.
//
// Rule, on the depth grid, in two steps:
//
// 1. `grow`: seeds are the depth cells under food-like colour pixels (first
//    food-like colour pixel in raster order labels the cell). A multi-source
//    breadth-first fill, seeds enqueued in raster order, steps to a 4-neighbour
//    when |Δz| ≤ cliffMm and the neighbour's confidence meets
//    `HeightFieldEstimator.tauConfidence`. First arrival labels a cell, so two
//    seed classes on one slab split it by distance; a class is only ever
//    extended, never removed. Growth past `frameFractionCap` of the colour
//    frame is discarded (the oversized-meal case), leaving the map unchanged.
// 2. `prune`, against the support plane the volume will use — the plane refit
//    from the grown mask when that fit succeeds, else the first plane: every
//    added cell whose surface sits under floorMm above that plane is dropped.
//
// Why prune after the refit rather than test height while growing: the first
// plane is fitted from the pre-shutter mask, and when that mask is a speck on a
// flat-topped food the contact ring lies on the food and the plane IS the food
// top. Measured against it nothing is raised, so a height test during growth
// would leave the pass inert on exactly the capture it exists for. Continuity
// finds the slab without a plane; the refit then puts the ring on the plate;
// the prune removes what the fill reached that is not raised above that plate.
//
// Why the floor is 3 mm rather than 0: on a `foodSupport` plane the plate
// surface sits above the plane by fit noise (1.5–1.8 mm residuals on the
// motivating sitting), and a zero floor would keep a fill that leaked onto
// it. On an `edgeBand` plane (the table) the plate is ~20 mm up and only the
// cap bounds a leak.

public struct FoodRegionGrowthConfig: Sendable, Equatable {
    /// Largest depth step between 4-neighbours the fill may cross, mm.
    public let cliffMm: Float
    /// Smallest height above the support plane a grown cell may have, mm.
    public let floorMm: Float
    /// Growth leaving more than this fraction of the colour frame food-like is
    /// discarded. 0 disables the pass.
    public let frameFractionCap: Float

    public init(cliffMm: Float, floorMm: Float, frameFractionCap: Float) {
        self.cliffMm = cliffMm
        self.floorMm = floorMm
        self.frameFractionCap = frameFractionCap
    }

    /// Starting constants; the corpus sweep (depth-grown-food-region task 5,
    /// Decision 2) settles them before the merge to main.
    public static let standard = FoodRegionGrowthConfig(cliffMm: 4, floorMm: 3, frameFractionCap: 0.35)
    public static let disabled = FoodRegionGrowthConfig(cliffMm: 0, floorMm: 0, frameFractionCap: 0)

    public var isDisabled: Bool { frameFractionCap <= 0 }
}

public struct FoodRegionGrowthResult: Sendable {
    /// The label map to integrate over: the input when nothing was added.
    public let argmax: ArgmaxMap
    /// Colour-grid pixels the pass added; nil when nothing was added.
    public let grownRegion: BinaryMask?
    public let foodPixelsBefore: Int
    public let foodPixelsAfter: Int
    /// True when the fill exceeded the cap and the input was returned unchanged.
    public let capTripped: Bool
    /// Depth cells the fill added, for `prune`; empty when nothing was added.
    let addedCells: [Bool]
    /// Cell label per added cell (index into `addedCells`), for `prune`.
    let cellLabel: [UInt8]
    /// The input map, so `prune` can rebuild the colour grid from it.
    let inputLabels: [UInt8]

    public var applied: Bool { grownRegion != nil }
}

public enum FoodRegionGrowth {
    static let unlabelled: UInt8 = 255

    /// Step 1, continuity growth. With `supportPlane` given the result is
    /// pruned against it at once (one-shot use); the pipeline passes nil,
    /// refits from the grown mask, then calls `prune` with the plane it will
    /// integrate against.
    public static func grow(
        argmax: ArgmaxMap,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane: SupportPlane? = nil,
        palette: ClassPalette,
        config: FoodRegionGrowthConfig = .standard
    ) -> FoodRegionGrowthResult {
        let w = argmax.width
        let h = argmax.height
        let dw = depth.width
        let dh = depth.height
        let cellCount = dw * dh
        let labels = [UInt8](argmax.pixels)

        var before = 0
        for l in labels where palette.isVolumetricClass(Int(l)) { before += 1 }

        func unchanged(capTripped: Bool) -> FoodRegionGrowthResult {
            FoodRegionGrowthResult(argmax: argmax, grownRegion: nil,
                                   foodPixelsBefore: before, foodPixelsAfter: before,
                                   capTripped: capTripped, addedCells: [], cellLabel: [],
                                   inputLabels: labels)
        }
        guard !config.isDisabled, before > 0, cellCount > 0, w > 0, h > 0 else {
            return unchanged(capTripped: false)
        }

        // Colour → depth cell, the mapping `sampleConfidenceUInt8` uses.
        let colX = (0..<w).map { x in min(dw - 1, max(0, Int((Float(x) + 0.5) * Float(dw) / Float(w)))) }
        let colY = (0..<h).map { y in min(dh - 1, max(0, Int((Float(y) + 0.5) * Float(dh) / Float(h)))) }

        // Per-cell depth and admissibility (finite depth, confidence).
        var zMm = [Float](repeating: 0, count: cellCount)
        var admissible = [Bool](repeating: false, count: cellCount)
        let confFloor = HeightFieldEstimator.tauConfidence
        for dy in 0..<dh {
            for dx in 0..<dw {
                let i = dy * dw + dx
                let z = readDepthMm(depth, x: dx, y: dy)
                zMm[i] = z
                guard z > 0, z.isFinite else { continue }
                admissible[i] = Float(depth.confidenceBytes[i]) / 255 >= confFloor
            }
        }

        var cellLabel = [UInt8](repeating: unlabelled, count: cellCount)
        var queue: [Int] = []
        queue.reserveCapacity(cellCount)
        for y in 0..<h {
            let cy = colY[y]
            for x in 0..<w {
                let l = labels[y * w + x]
                guard palette.isVolumetricClass(Int(l)) else { continue }
                let i = cy * dw + colX[x]
                if cellLabel[i] == unlabelled {
                    cellLabel[i] = l
                    queue.append(i)
                }
            }
        }

        // Breadth-first fill; FIFO order over a raster-ordered seed list keeps
        // the result independent of anything but the inputs.
        var added = [Bool](repeating: false, count: cellCount)
        var head = 0
        while head < queue.count {
            let c = queue[head]
            head += 1
            let zc = zMm[c]
            guard zc > 0 else { continue }   // a seed with no depth cannot compare
            let l = cellLabel[c]
            let cx = c % dw
            let cy = c / dw
            let neighbours = [
                cx > 0 ? c - 1 : -1,
                cx < dw - 1 ? c + 1 : -1,
                cy > 0 ? c - dw : -1,
                cy < dh - 1 ? c + dw : -1,
            ]
            for n in neighbours where n >= 0 {
                guard cellLabel[n] == unlabelled, admissible[n] else { continue }
                guard abs(zMm[n] - zc) <= config.cliffMm else { continue }
                cellLabel[n] = l
                added[n] = true
                queue.append(n)
            }
        }

        let result = toColourGrid(
            inputLabels: labels, added: added, cellLabel: cellLabel,
            before: before, width: w, height: h, depthWidth: dw, depthHeight: dh,
            palette: palette)
        guard result.applied else { return unchanged(capTripped: false) }
        if Float(result.foodPixelsAfter) > config.frameFractionCap * Float(w * h) {
            return unchanged(capTripped: true)
        }
        guard let plane = supportPlane else { return result }
        return prune(result, depth: depth, intrinsics: intrinsics,
                     supportPlane: plane, palette: palette, config: config)
    }

    /// Step 2: drop every added cell whose surface is under `floorMm` above
    /// `supportPlane`. Returns the input untouched when nothing was added.
    public static func prune(
        _ grown: FoodRegionGrowthResult,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane plane: SupportPlane,
        palette: ClassPalette,
        config: FoodRegionGrowthConfig
    ) -> FoodRegionGrowthResult {
        guard grown.applied else { return grown }
        let w = grown.argmax.width
        let h = grown.argmax.height
        let dw = depth.width
        let dh = depth.height
        var kept = grown.addedCells
        for dy in 0..<dh {
            for dx in 0..<dw {
                let i = dy * dw + dx
                guard kept[i] else { continue }
                // Height at the cell centre, on the colour grid, with the same
                // ray–plane arithmetic the integrator uses.
                let cxCol = (Float(dx) + 0.5) * Float(w) / Float(dw) - 0.5
                let cyCol = (Float(dy) + 0.5) * Float(h) / Float(dh) - 0.5
                let z = readDepthMm(depth, x: dx, y: dy)
                guard let height = heightAboveSupportPlaneMm(
                    colourX: cxCol, colourY: cyCol, depthMm: z,
                    intrinsics: intrinsics, plane: plane),
                      height >= config.floorMm else {
                    kept[i] = false
                    continue
                }
            }
        }
        return toColourGrid(
            inputLabels: grown.inputLabels, added: kept, cellLabel: grown.cellLabel,
            before: grown.foodPixelsBefore, width: w, height: h,
            depthWidth: dw, depthHeight: dh, palette: palette)
    }

    // Colour-grid rebuild from the cell decision: a colour pixel keeps its
    // existing food-like label; an added cell's block takes the cell label.
    private static func toColourGrid(
        inputLabels labels: [UInt8], added: [Bool], cellLabel: [UInt8],
        before: Int, width w: Int, height h: Int, depthWidth dw: Int, depthHeight dh: Int,
        palette: ClassPalette
    ) -> FoodRegionGrowthResult {
        let colX = (0..<w).map { x in min(dw - 1, max(0, Int((Float(x) + 0.5) * Float(dw) / Float(w)))) }
        let colY = (0..<h).map { y in min(dh - 1, max(0, Int((Float(y) + 0.5) * Float(dh) / Float(h)))) }
        var grown = labels
        var region = [UInt8](repeating: 0, count: w * h)
        var after = before
        var addedPixels = 0
        for y in 0..<h {
            let cy = colY[y]
            for x in 0..<w {
                let p = y * w + x
                guard !palette.isVolumetricClass(Int(labels[p])) else { continue }
                let i = cy * dw + colX[x]
                guard added[i] else { continue }
                grown[p] = cellLabel[i]
                region[p] = 1
                after += 1
                addedPixels += 1
            }
        }
        guard addedPixels > 0 else {
            return FoodRegionGrowthResult(
                argmax: ArgmaxMap(pixels: Data(labels), height: h, width: w),
                grownRegion: nil, foodPixelsBefore: before, foodPixelsAfter: before,
                capTripped: false, addedCells: [], cellLabel: [], inputLabels: labels)
        }
        return FoodRegionGrowthResult(
            argmax: ArgmaxMap(pixels: Data(grown), height: h, width: w),
            grownRegion: BinaryMask(pixels: region, width: w, height: h),
            foodPixelsBefore: before,
            foodPixelsAfter: after,
            capTripped: false,
            addedCells: added, cellLabel: cellLabel, inputLabels: labels
        )
    }
}

// §6.7 ray–plane height of a colour pixel's surface above the support plane,
// in mm; nil on a degenerate ray. The same arithmetic, in the same order, as
// `HeightFieldEstimator.integrate` so the two agree pixel for pixel.
@inline(__always)
func heightAboveSupportPlaneMm(
    colourX x: Float, colourY y: Float, depthMm zt: Float,
    intrinsics k: CameraIntrinsics, plane: SupportPlane
) -> Float? {
    let dir = Vec3(
        (x - k.cx) / k.fx,
        (y - k.cy) / k.fy,
        -1
    ).normalised()
    let absDz = abs(dir.z)
    if absDz < 1e-9 { return nil }
    let pTop = dir * (zt / absDz)
    let denom = plane.normal.dot(dir)
    if abs(denom) < 1e-9 { return nil }
    let alphaSup = plane.distanceMm / denom
    let pSup = dir * alphaSup
    let zS = abs(pSup.z)
    let zTopAbs = abs(pTop.z)
    return max(0, zS - zTopAbs)
}
