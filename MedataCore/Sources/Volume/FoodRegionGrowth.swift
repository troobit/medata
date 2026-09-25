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
//    breadth-first fill, seeds enqueued in raster order, steps to a
//    4-neighbour when |Δz| ≤ cliffMm, the neighbour's confidence meets
//    `HeightFieldEstimator.tauConfidence`, and the neighbour's surface sits
//    at least floorMm above the SUPPORT SURFACE: its height above the first
//    plane minus `supportOffsetMm`. On a `foodSupport` fit that offset is 0;
//    on an `edgeBand` fit (the table) it is the fitter's ring median, which is
//    the plate top's height above the table (+18…+26 mm on the corpus). First
//    arrival labels a cell, so two seed classes on one slab split it by
//    distance; a class is only ever extended, never removed. Growth past
//    `frameFractionCap` of the colour frame is discarded (the oversized-meal
//    case), leaving the map unchanged.
// 2. `prune`, against the plane the volume will use — the plane refit from the
//    grown mask when that fit succeeds, else the first plane — with the same
//    offset rule: every added cell under floorMm above that support surface is
//    dropped.
//
// Why height above the support surface, not depth continuity alone: the
// 2026-09-24 corpus sweep (Decision 1) showed the food-to-plate edge is a
// gentle slope in the smoothed LiDAR depth, not a cliff — a continuity-only
// fill leaked onto the plate and table on every capture at every cliff value
// tried (3, 4, 6 mm). The plate top is the level the fill must not go below,
// and the fitter already measures it as the ring median on an edge-band fit.
//
// Known limit: when the first plane sits on the food's own top (a flat food
// with a speck seed, admitted as foodSupport), nothing is raised above it and
// the pass is inert — the estimate is then exactly today's.

public struct FoodRegionGrowthConfig: Sendable, Equatable {
    /// Largest depth step between 4-neighbours the fill may cross, mm.
    public let cliffMm: Float
    /// Smallest height above the support plane a grown cell may have, mm.
    public let floorMm: Float
    /// Growth leaving more than this fraction of the colour frame food-like is
    /// discarded. 0 disables the pass.
    public let frameFractionCap: Float
    /// `prune` drops an added cell whose height above the support surface is
    /// below the seed cells' median height minus this, mm. 0 means no band.
    /// Why (Decision 4): the first plane can sit 4–5° off the table, which put
    /// the plate 6–16 mm above it on `1790315900185` with the food at 30 mm —
    /// a fixed floor cannot separate them, a food-relative band can, and the
    /// tilt cancels because seeds and added cells are measured the same way.
    public let seedBandMm: Float

    public init(cliffMm: Float, floorMm: Float, frameFractionCap: Float, seedBandMm: Float = 0) {
        self.cliffMm = cliffMm
        self.floorMm = floorMm
        self.frameFractionCap = frameFractionCap
        self.seedBandMm = seedBandMm
    }

    /// Set by the 2026-09-24 corpus sweep (depth-grown-food-region task 5,
    /// Decision 1 table): floor 3 mm is the value that keeps the median added
    /// area on well-segmented plates under the 20 % bar (+9 %; floor 2 mm reads
    /// +40 %), and cliff 3 mm is the tightest cliff at which the roll capture
    /// still grows to its full slab (7.1 % of the frame).
    /// Floor raised 3 → 5 mm on 2026-09-25 (Decision 3): with the first
    /// plane fitted from the pre-shutter mask, as the device does, a plate
    /// that sits 3–5 mm above the fitted plane (dish, tilt) leaked a blob
    /// out to the rim on both roll captures at 3 mm and not at 5 mm.
    public static let standard = FoodRegionGrowthConfig(cliffMm: 3, floorMm: 5, frameFractionCap: 0.35, seedBandMm: 10)
    public static let disabled = FoodRegionGrowthConfig(cliffMm: 0, floorMm: 0, frameFractionCap: 0, seedBandMm: 0)

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

    /// Step 1. `supportOffsetMm` is the support surface's height above
    /// `supportPlane` (the ring median on an `edgeBand` fit, 0 otherwise).
    public static func grow(
        argmax: ArgmaxMap,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane plane: SupportPlane,
        supportOffsetMm: Float = 0,
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

        // Per-cell depth and admissibility: finite depth, confidence, and
        // height above the support surface.
        var zMm = [Float](repeating: 0, count: cellCount)
        var admissible = [Bool](repeating: false, count: cellCount)
        let confFloor = HeightFieldEstimator.tauConfidence
        for dy in 0..<dh {
            for dx in 0..<dw {
                let i = dy * dw + dx
                let z = readDepthMm(depth, x: dx, y: dy)
                zMm[i] = z
                guard z > 0, z.isFinite else { continue }
                // No confidence plane (Nutrition5k) reads as fully confident.
                let conf: Float = i < depth.confidenceBytes.count ? Float(depth.confidenceBytes[i]) : 255
                guard conf / 255 >= confFloor else { continue }
                admissible[i] = cellClearsFloor(
                    dx: dx, dy: dy, depthMm: z, width: w, height: h,
                    depthWidth: dw, depthHeight: dh, intrinsics: intrinsics,
                    plane: plane, offsetMm: supportOffsetMm, floorMm: config.floorMm)
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
            palette: palette, depth: depth, intrinsics: intrinsics,
            plane: plane, offsetMm: supportOffsetMm, floorMm: config.floorMm)
        guard result.applied else { return unchanged(capTripped: false) }
        if Float(result.foodPixelsAfter) > config.frameFractionCap * Float(w * h) {
            return unchanged(capTripped: true)
        }
        return result
    }

    /// Step 2: drop every added cell whose surface is under `floorMm` above
    /// the support surface of `supportPlane` (see `grow` for the offset).
    /// Returns the input untouched when nothing was added.
    public static func prune(
        _ grown: FoodRegionGrowthResult,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane plane: SupportPlane,
        supportOffsetMm: Float = 0,
        palette: ClassPalette,
        config: FoodRegionGrowthConfig
    ) -> FoodRegionGrowthResult {
        guard grown.applied else { return grown }
        let w = grown.argmax.width
        let h = grown.argmax.height
        let dw = depth.width
        let dh = depth.height
        func height(_ dx: Int, _ dy: Int) -> Float? {
            cellHeightAboveSupportMm(
                dx: dx, dy: dy, depthMm: readDepthMm(depth, x: dx, y: dy),
                width: w, height: h, depthWidth: dw, depthHeight: dh,
                intrinsics: intrinsics, plane: plane, offsetMm: supportOffsetMm)
        }
        // The seed band (Decision 4): the segmenter's own cells, measured
        // against the same surface, set a floor the added cells must reach.
        var bandFloor = -Float.infinity
        if config.seedBandMm > 0 {
            let colX = (0..<w).map { x in min(dw - 1, max(0, Int((Float(x) + 0.5) * Float(dw) / Float(w)))) }
            let colY = (0..<h).map { y in min(dh - 1, max(0, Int((Float(y) + 0.5) * Float(dh) / Float(h)))) }
            var isSeed = [Bool](repeating: false, count: dw * dh)
            for y in 0..<h {
                for x in 0..<w where palette.isVolumetricClass(Int(grown.inputLabels[y * w + x])) {
                    isSeed[colY[y] * dw + colX[x]] = true
                }
            }
            var seedHeights: [Float] = []
            for i in 0..<(dw * dh) where isSeed[i] {
                if let hgt = height(i % dw, i / dw) { seedHeights.append(hgt) }
            }
            if !seedHeights.isEmpty {
                seedHeights.sort()
                bandFloor = seedHeights[seedHeights.count / 2] - config.seedBandMm
            }
        }
        var kept = grown.addedCells
        for dy in 0..<dh {
            for dx in 0..<dw {
                let i = dy * dw + dx
                guard kept[i] else { continue }
                guard let hgt = height(dx, dy) else { kept[i] = false; continue }
                kept[i] = hgt >= config.floorMm && hgt >= bandFloor
            }
        }
        return toColourGrid(
            inputLabels: grown.inputLabels, added: kept, cellLabel: grown.cellLabel,
            before: grown.foodPixelsBefore, width: w, height: h,
            depthWidth: dw, depthHeight: dh, palette: palette,
            depth: depth, intrinsics: intrinsics, plane: plane,
            offsetMm: supportOffsetMm, floorMm: config.floorMm)
    }

    // Height of the cell centre above the support surface, with the same
    // ray–plane arithmetic the integrator uses, against the floor.
    @inline(__always)
    private static func cellClearsFloor(
        dx: Int, dy: Int, depthMm z: Float, width w: Int, height h: Int,
        depthWidth dw: Int, depthHeight dh: Int, intrinsics: CameraIntrinsics,
        plane: SupportPlane, offsetMm: Float, floorMm: Float
    ) -> Bool {
        guard let height = cellHeightAboveSupportMm(
            dx: dx, dy: dy, depthMm: z, width: w, height: h, depthWidth: dw,
            depthHeight: dh, intrinsics: intrinsics, plane: plane, offsetMm: offsetMm)
        else { return false }
        return height >= floorMm
    }

    // Height of the cell centre above the support surface (plane + offset), mm;
    // nil on a degenerate ray.
    @inline(__always)
    private static func cellHeightAboveSupportMm(
        dx: Int, dy: Int, depthMm z: Float, width w: Int, height h: Int,
        depthWidth dw: Int, depthHeight dh: Int, intrinsics: CameraIntrinsics,
        plane: SupportPlane, offsetMm: Float
    ) -> Float? {
        let cxCol = (Float(dx) + 0.5) * Float(w) / Float(dw) - 0.5
        let cyCol = (Float(dy) + 0.5) * Float(h) / Float(dh) - 0.5
        guard let height = heightAboveSupportPlaneMm(
            colourX: cxCol, colourY: cyCol, depthMm: z,
            intrinsics: intrinsics, plane: plane) else { return nil }
        return height - offsetMm
    }

    // Colour-grid rebuild from the cell decision. A colour pixel keeps its
    // existing food-like label. Otherwise it is added when its own surface —
    // the bilinear depth sample the integrator will read at that pixel —
    // clears the floor above the support surface AND its nearest cell or one
    // of that cell's 4-neighbours was filled. The per-pixel height test is
    // what keeps the edge on the depth contour rather than on the 7.5 × 7.5 px
    // cell blocks ("speckles around edge of roll", 2026-09-24 field note);
    // the neighbour rule lets the contour run up to one cell past the fill.
    private static func toColourGrid(
        inputLabels labels: [UInt8], added: [Bool], cellLabel: [UInt8],
        before: Int, width w: Int, height h: Int, depthWidth dw: Int, depthHeight dh: Int,
        palette: ClassPalette, depth: DepthMap, intrinsics: CameraIntrinsics,
        plane: SupportPlane, offsetMm: Float, floorMm: Float
    ) -> FoodRegionGrowthResult {
        let colX = (0..<w).map { x in min(dw - 1, max(0, Int((Float(x) + 0.5) * Float(dw) / Float(w)))) }
        let colY = (0..<h).map { y in min(dh - 1, max(0, Int((Float(y) + 0.5) * Float(dh) / Float(h)))) }
        // A pixel may be added when its cell, or a 4-neighbour of it, was filled;
        // the filled cell nearest in raster order supplies the label.
        func filledNear(_ i: Int) -> Int? {
            if added[i] { return i }
            let cx = i % dw, cy = i / dw
            if cy > 0, added[i - dw] { return i - dw }
            if cx > 0, added[i - 1] { return i - 1 }
            if cx < dw - 1, added[i + 1] { return i + 1 }
            if cy < dh - 1, added[i + dw] { return i + dw }
            return nil
        }
        var grown = labels
        var region = [UInt8](repeating: 0, count: w * h)
        var after = before
        var addedPixels = 0
        for y in 0..<h {
            let cy = colY[y]
            for x in 0..<w {
                let p = y * w + x
                guard !palette.isVolumetricClass(Int(labels[p])) else { continue }
                guard let src = filledNear(cy * dw + colX[x]) else { continue }
                guard let z = sampleDepthBilinearMm(
                    depth: depth, colourX: Float(x), colourY: Float(y),
                    colourWidth: w, colourHeight: h), z > 0,
                      let height = heightAboveSupportPlaneMm(
                        colourX: Float(x), colourY: Float(y), depthMm: z,
                        intrinsics: intrinsics, plane: plane),
                      height - offsetMm >= floorMm else { continue }
                grown[p] = cellLabel[src]
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
