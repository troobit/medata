import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane

// Synthetic scene builders shared by the `SupportRegion` suites
// (`specs/estimation/support-plane-reference/`, tasks 1–8).
//
// Every scene is a NADIR capture: the camera looks straight down, so world-up in the
// camera frame points back at the camera, a gravity-aligned plane has normal (0,0,1),
// and a point's signed height above a plane at depth Z is (Z − depth). Scenes are
// therefore authored as height maps in millimetres above the table, which is how the
// physical cases (plate, rim, bowl, overhang) are actually described.
//
// The intrinsics resolve ~2 mm per depth pixel at 350 mm — the figure the design's
// sector-viability and smear arguments rest on: fx_d = 700 × 256/1024 = 175, and
// 350/175 = 2.0 mm/px. The colour grid is an exact 4× multiple of the depth grid so
// the mask round trip is lossless and the scenes' geometry is exactly what they say.
enum SPRScene {
    static let colourWidth = 1024
    static let colourHeight = 768
    static let depthWidth = 256
    static let depthHeight = 192
    static let tableDepthMm: Float = 350

    static let colourIntrinsics = CameraIntrinsics(
        fx: 700, fy: 700, cx: 511.5, cy: 383.5,
        distortion: [], imageWidth: colourWidth, imageHeight: colourHeight
    )
    static let gravity = Vec3(0, 0, 1)

    // A plane parallel to the table at `heightMm` above it, in the (normal, d) form
    // the fitter works in: p = (X, Y, −z), n = (0,0,1), so d = n·p = −(350 − height).
    static func plane(atHeightMm heightMm: Float) -> (normal: Vec3, d: Float) {
        (Vec3(0, 0, 1), heightMm - tableDepthMm)
    }

    struct Grid {
        let width: Int
        let height: Int
        var heightMm: [Float]      // mm above the table, +ve towards the camera
        var food: [Bool]
        var confidence: [UInt8]
    }

    // `build` returns the surface height above the table and whether the pixel is
    // food, per DEPTH pixel.
    static func grid(width: Int = depthWidth, height: Int = depthHeight,
                     build: (Int, Int) -> (heightMm: Float, isFood: Bool)) -> Grid {
        var heights = [Float](repeating: 0, count: width * height)
        var food = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sample = build(x, y)
                heights[y * width + x] = sample.heightMm
                food[y * width + x] = sample.isFood
            }
        }
        return Grid(width: width, height: height, heightMm: heights, food: food,
                    confidence: [UInt8](repeating: 255, count: width * height))
    }

    // `depthIntrinsics` is written as ALL ZEROS, exactly as ARKitCaptureEngine writes
    // it on device. Any code that reads it divides by zero and produces a NaN plane,
    // so every scene here fails loudly if that derivation regresses.
    //
    // A deterministic ±`noiseMm` of sensor noise is added: real depth is never
    // exactly planar, and an exactly-planar sample set has a rank-2 scatter matrix,
    // which `LiDARPlaneFitter.refine`'s σ_min/σ_max stability gate rejects as
    // degenerate. 0.3 mm sits far inside the ±5 mm inlier band, so it changes no
    // support fraction while keeping the fit well-conditioned.
    static func makeDepth(_ grid: Grid, noiseMm: Float = 0.3) -> DepthMap {
        var depthBytes = Data(count: grid.width * grid.height * 4)
        depthBytes.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for i in 0..<(grid.width * grid.height) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let unit = Float(state >> 40) / Float(1 << 24)
                buffer[i] = tableDepthMm - grid.heightMm[i] + (unit - 0.5) * 2 * noiseMm
            }
        }
        return DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: Data(grid.confidence),
            width: grid.width, height: grid.height,
            rowStrideBytes: grid.width * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 0, fy: 0, cx: 0, cy: 0,
                distortion: [], imageWidth: grid.width, imageHeight: grid.height
            ),
            depthFromColour: .identity
        )
    }

    // The food mask the pipeline hands the fitter is colour-grid; scenes author it on
    // the depth grid, so it is expanded here using the same colour→depth mapping
    // `downsampleFoodMask` inverts. Exact, because the grids differ by a factor of 4.
    static func makeColourMask(_ grid: Grid) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: colourWidth * colourHeight)
        let sx = Float(grid.width) / Float(colourWidth)
        let sy = Float(grid.height) / Float(colourHeight)
        for cy in 0..<colourHeight {
            let dy = min(grid.height - 1, max(0, Int((Float(cy) + 0.5) * sy)))
            for cx in 0..<colourWidth {
                let dx = min(grid.width - 1, max(0, Int((Float(cx) + 0.5) * sx)))
                pixels[cy * colourWidth + cx] = grid.food[dy * grid.width + dx] ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: colourWidth, height: colourHeight)
    }

    static func radius(_ x: Int, _ y: Int, centreX: Float, centreY: Float) -> Float {
        let dx = Float(x) - centreX, dy = Float(y) - centreY
        return (dx * dx + dy * dy).squareRoot()
    }

    // Prepared geometry + ring samples, which most assertions need together.
    static func measure(_ grid: Grid) -> (geometry: SupportRegion.DepthGeometry,
                                          samples: SupportRegion.RingSamples)? {
        guard let geometry = SupportRegion.prepare(
            depth: makeDepth(grid), colourIntrinsics: colourIntrinsics,
            foodRegionMask: makeColourMask(grid)
        ) else { return nil }
        return (geometry, SupportRegion.ringSamples(geometry: geometry))
    }

    static func ringStatistics(_ grid: Grid, planeHeightMm: Float) -> RingStatistics? {
        guard let measured = measure(grid) else { return nil }
        let p = plane(atHeightMm: planeHeightMm)
        return SupportRegion.ringStatistics(samples: measured.samples,
                                            geometry: measured.geometry,
                                            normal: p.normal, d: p.d)
    }

    static func fit(_ grid: Grid) -> SupportRegion.FoodSupportFit? {
        SupportRegion.fitFoodSupportPlane(
            depth: makeDepth(grid), colourIntrinsics: colourIntrinsics,
            foodRegionMask: makeColourMask(grid), gravityCamera: gravity
        )
    }

    // A nadir `RawFrame` carrying the scene's depth map, for the suites that drive
    // the whole `SupportPlaneFitter` dispatch rather than `SupportRegion` directly
    // (tasks 9–10). `makeDepth` is deterministic, so a frame built here and a
    // `DepthMap` built separately from the same grid are byte-identical — which is
    // what lets the fallback plane be compared against a direct `LiDARPlaneFitter`
    // fit for equality (Req 4.3).
    static func makeFrame(_ grid: Grid) -> RawFrame {
        RawFrame(
            imageBytes: Data(count: colourWidth * colourHeight * 4),
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: colourWidth, imageHeight: colourHeight,
            timestampMonotonicNs: 1,
            intrinsics: colourIntrinsics,
            gravity: gravity,
            worldFromCamera: .identity,
            depth: makeDepth(grid)
        )
    }

    // Height of a fitted plane above the table, recovered from its (normal, d).
    static func heightMm(of plane: SupportPlane) -> Float {
        // d = n·p; for a fronto-parallel plane at depth z, d = −z and height = 350 − z.
        tableDepthMm + plane.distanceMm / max(1e-6, plane.normal.z)
    }

    // MARK: – Named scenes

    // A plate `plateHeightMm` above the table with food on it. The table dominates the
    // FRAME roughly 26:1 — the configuration the pre-feature band scan fits the table
    // on — while the annulus bound reduces it to near parity, which is the point of
    // the bound (Decision 15).
    // `scale` renders the SAME physical scene on a finer depth grid: the intrinsics
    // scale with it, so mm-denominated radii land on the same surfaces (Req 5.1).
    static func plateAboveTable(foodRadiusPx: Float = 12.5, plateRadiusPx: Float = 28,
                                plateHeightMm: Float = 20, foodHeightMm: Float = 8,
                                centreX: Float = 128, centreY: Float = 96,
                                scale: Float = 1) -> Grid {
        grid(width: Int(Float(depthWidth) * scale), height: Int(Float(depthHeight) * scale)) { x, y in
            let r = radius(x, y, centreX: centreX * scale, centreY: centreY * scale)
            let base: Float = r <= plateRadiusPx * scale ? plateHeightMm : 0
            if r <= foodRadiusPx * scale { return (plateHeightMm + foodHeightMm, true) }
            return (base, false)
        }
    }

    // A plate with a co-height board elsewhere in the annulus: same height, separated
    // by a strip of table, so it forms its own 8-connected blob (design §CC-RANSAC).
    static func plateWithCoHeightBoard(plateRadiusPx: Float = 28,
                                       boardInnerPx: Float = 33, boardOuterPx: Float = 39,
                                       plateHeightMm: Float = 20) -> Grid {
        grid { x, y in
            let r = radius(x, y, centreX: 128, centreY: 96)
            if r <= 12.5 { return (plateHeightMm + 8, true) }
            if r <= plateRadiusPx { return (plateHeightMm, false) }
            if r >= boardInnerPx, r <= boardOuterPx, Float(x) > 128 { return (plateHeightMm, false) }
            return (0, false)
        }
    }

    // Food resting on a plate with a wedge of it overhanging the plate edge and
    // drooping towards the worktop, so a documented share of food samples sits BELOW
    // the plate plane — the geometry Decision 22 shows `foodAboveFractionMax = 0.05`
    // rejects. `lobeHalfAngleDeg` is centred on a sector centre (22.5°) so the lost
    // ring arc falls inside one sector.
    static func overhangingFood(plateRadiusPx: Float = 28, foodRadiusPx: Float = 12.5,
                                lobeOuterPx: Float = 40, lobeHalfAngleDeg: Float = 10,
                                droopMmPerPx: Float = 1.2,
                                plateHeightMm: Float = 20, foodHeightMm: Float = 8) -> Grid {
        let centreAngle = Float(22.5) * .pi / 180
        let halfAngle = lobeHalfAngleDeg * .pi / 180
        return grid { x, y in
            let dx = Float(x) - 128, dy = Float(y) - 96
            let r = (dx * dx + dy * dy).squareRoot()
            if r <= foodRadiusPx { return (plateHeightMm + foodHeightMm, true) }
            var delta = abs(atan2(dy, dx) - centreAngle)
            if delta > .pi { delta = 2 * .pi - delta }
            if delta <= halfAngle, r <= lobeOuterPx {
                // Flat while the plate supports it, drooping once past the edge.
                let droop = max(0, r - plateRadiusPx) * droopMmPerPx
                return (plateHeightMm + foodHeightMm - droop, true)
            }
            return (r <= plateRadiusPx ? plateHeightMm : 0, false)
        }
    }

    // A rimmed plate: well at `wellHeightMm`, rim `rimStepMm` above it from
    // `rimStartPx` out to `plateRadiusPx`, table beyond.
    static func rimmedPlate(foodRadiusPx: Float = 12.5, rimStartPx: Float,
                            plateRadiusPx: Float = 44, wellHeightMm: Float = 20,
                            rimStepMm: Float = 15, foodHeightMm: Float = 8) -> Grid {
        grid { x, y in
            let r = radius(x, y, centreX: 128, centreY: 96)
            if r <= foodRadiusPx { return (wellHeightMm + foodHeightMm, true) }
            if r <= rimStartPx { return (wellHeightMm, false) }
            if r <= plateRadiusPx { return (wellHeightMm + rimStepMm, false) }
            return (0, false)
        }
    }

    // A bowl: the wall climbs continuously from the food boundary outwards, so every
    // radial band sits higher than the one inside it.
    static func bowl(foodRadiusPx: Float = 12.5, wallStartPx: Float = 13,
                     slopeMmPerPx: Float = 3, baseHeightMm: Float = 20,
                     foodHeightMm: Float = 8) -> Grid {
        grid { x, y in
            let r = radius(x, y, centreX: 128, centreY: 96)
            if r <= foodRadiusPx { return (baseHeightMm + foodHeightMm, true) }
            let climb = max(0, r - wallStartPx) * slopeMmPerPx
            return (baseHeightMm + climb, false)
        }
    }

    // Food half on a plate and half on the worktop — the geometry of capture
    // `1785901032716`, and the scene Decision 18 identifies as the design's most
    // dangerous. The plate is a half-plane whose edge is rotated by `edgeAngleDeg`
    // so the supported arc is centred on a sector rather than on a sector boundary;
    // see the note in SupportRegionSelectionTests.
    static func foodAcrossPlateEdge(foodRadiusPx: Float = 12.5, edgeOffsetPx: Float,
                                    edgeAngleDeg: Float = 22.5,
                                    plateHeightMm: Float = 20,
                                    foodHeightMm: Float = 8) -> Grid {
        let theta = edgeAngleDeg * .pi / 180
        let ux = cos(theta), uy = sin(theta)
        return grid { x, y in
            let dx = Float(x) - 128, dy = Float(y) - 96
            let along = dx * ux + dy * uy
            // The slice lies FLAT at the plate-supported height whether or not the
            // surface beneath it is the plate — it is supported by the plate and
            // overhangs the worktop, which is what makes the overhanging samples sit
            // below the plate plane (Decision 4).
            if radius(x, y, centreX: 128, centreY: 96) <= foodRadiusPx {
                return (plateHeightMm + foodHeightMm, true)
            }
            return (along <= edgeOffsetPx ? plateHeightMm : 0, false)
        }
    }
}
