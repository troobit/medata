import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// Depth-grown food region (depth-grown-food-region Req 1–3, 5). Geometry as in
// HeightFieldUnknownTests: nadir camera, plane at z = −600 mm. Colour 64×48,
// depth 16×12 (4×4 colour pixels per depth cell). A "slab" is a raised block of
// cells at 560 mm (40 mm above the plane) with the plate at 599 mm (1 mm above
// the plane, under the 3 mm floor) — the one-cell edge is a 39 mm cliff.

@Suite("FoodRegionGrowth")
struct FoodRegionGrowthTests {

    // food_0 = 0, food_1 = 1; bg = 2, unknown = 3, unsupported = 4.
    let palette = makePalette(numFood: 2)
    let w = 64, h = 48, dw = 16, dh = 12
    let k = CameraIntrinsics(fx: 80, fy: 80, cx: 32, cy: 24,
                             distortion: [], imageWidth: 64, imageHeight: 48)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)

    // Slab occupies depth cells x 4..<12, y 3..<9 (8×6 = 48 cells).
    func inSlab(_ dx: Int, _ dy: Int) -> Bool { (4..<12).contains(dx) && (3..<9).contains(dy) }

    func depth(_ depthMm: @escaping (Int, Int) -> Float,
               conf: @escaping (Int, Int) -> UInt8 = { _, _ in 255 }) -> DepthMap {
        makeDepthMap(width: dw, height: dh, intrinsics: k, depthMm: depthMm, conf: conf)
    }
    var slabDepth: DepthMap { depth { dy, dx in inSlab(dx, dy) ? 560 : 599 } }

    // One food_0 seed: the colour block of depth cell (5, 4).
    func seedArgmax(cells: [(Int, Int, Int)]) -> ArgmaxMap {
        makeArgmax(width: w, height: h) { y, x in
            for (dx, dy, label) in cells where x / 4 == dx && y / 4 == dy { return label }
            return palette.background
        }
    }

    func countVolumetric(_ a: ArgmaxMap) -> Int {
        [UInt8](a.pixels).filter { palette.isVolumetricClass(Int($0)) }.count
    }

    @Test("a speck on a slab grows to the whole slab and stops at its cliff")
    func growsToTheCliff() throws {
        let r = FoodRegionGrowth.grow(argmax: seedArgmax(cells: [(5, 4, 0)]), depth: slabDepth,
                                      intrinsics: k, supportPlane: plane, palette: palette)
        #expect(r.applied)
        #expect(!r.capTripped)
        #expect(r.foodPixelsBefore == 16)
        // The colour-grid edge follows the bilinear depth contour, so the count
        // runs up to half a cell past the 48-cell slab (768 px block area).
        #expect(r.foodPixelsAfter > 700 && r.foodPixelsAfter < 1150, "after \(r.foodPixelsAfter)")
        let labels = [UInt8](r.argmax.pixels)
        for y in 0..<h {
            for x in 0..<w {
                // Interior of the slab (a cell in from the edge) is food_0; two
                // cells out from the slab is background; the edge band is free.
                let dx = x / 4, dy = y / 4
                if (5..<11).contains(dx) && (4..<8).contains(dy) {
                    #expect(Int(labels[y * w + x]) == 0, "pixel \(x),\(y)")
                } else if !((3...12).contains(dx) && (2...9).contains(dy)) {
                    #expect(Int(labels[y * w + x]) == palette.background, "pixel \(x),\(y)")
                }
            }
        }
        let region = try #require(r.grownRegion)
        #expect(region.pixels.filter { $0 != 0 }.count == r.foodPixelsAfter - 16)
        #expect(!region.isFood(x: 5 * 4, y: 4 * 4))   // the seed block is not "added"
    }

    @Test("a ramp under the floor is not entered, so the plate stays background")
    func floorStopsThePlate() {
        // Slab at 560 with a gentle ramp: every plate cell at 599 → 1 mm high.
        // Steps between neighbouring plate cells are 0 mm, so only the floor
        // keeps the fill off them; the slab edge is a cliff in any case. Make
        // the slab edge gentle too: cell x = 12 at 562, x = 13 at 565 — both
        // above the floor and within the 3 mm cliff — then 599 beyond.
        let d = depth { dy, dx in
            if inSlab(dx, dy) { return 560 }
            if (3..<9).contains(dy) && dx == 12 { return 562 }
            if (3..<9).contains(dy) && dx == 13 { return 565 }
            return 599
        }
        // Slab plus ramp is ~40 % of this small frame once the contour edge is
        // counted, so the cap is lifted for the scene.
        let roomy = FoodRegionGrowthConfig(cliffMm: 3, floorMm: 3, frameFractionCap: 0.6)
        let r = FoodRegionGrowth.grow(argmax: seedArgmax(cells: [(5, 4, 0)]), depth: d,
                                      intrinsics: k, supportPlane: plane, palette: palette,
                                      config: roomy)
        #expect(r.applied)
        // 48 slab cells + 2 ramp columns × 6 rows = 60 cells (960 px), edge band free.
        #expect(r.foodPixelsAfter > 800 && r.foodPixelsAfter < 1350, "after \(r.foodPixelsAfter)")
    }

    // Decision 1: on an edge-band (table) plane the plate sits at the ring
    // median above the plane, and growth is gated on height above THAT. With
    // the offset the fill stays on the slab; without it the plate (everything
    // else in this scene) is "raised" and the fill runs past the cap.
    @Test("the ring-median offset keeps the fill off a plate above a table plane")
    func supportOffsetKeepsThePlateOut() {
        // Real LiDAR: the slab's side is a slope, not a cliff. Two ramp columns
        // (580, 596) join the slab (560) to the plate (599) in steps a 20 mm
        // cliff allows, so only the height rule can stop the fill.
        let ramped = depth { dy, dx in
            if inSlab(dx, dy) { return 560 }
            if (3..<9).contains(dy) && dx == 12 { return 580 }
            if (3..<9).contains(dy) && dx == 13 { return 596 }
            return 599
        }
        // Cap lifted for the small frame (the leak case still covers all of it).
        let sloped = FoodRegionGrowthConfig(cliffMm: 20, floorMm: 3, frameFractionCap: 0.6)
        let table = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -620,
                                 residualMm: 0.5, convergedIterations: nil)
        let a = seedArgmax(cells: [(5, 4, 0)])
        let leaked = FoodRegionGrowth.grow(argmax: a, depth: ramped, intrinsics: k,
                                           supportPlane: table, supportOffsetMm: 0,
                                           palette: palette, config: sloped)
        #expect(!leaked.applied && leaked.capTripped)
        let held = FoodRegionGrowth.grow(argmax: a, depth: ramped, intrinsics: k,
                                         supportPlane: table, supportOffsetMm: 21,
                                         palette: palette, config: sloped)
        #expect(held.applied)
        // Slab (48 cells) plus both ramp columns (596 is 3 mm above the plate): 960 px.
        #expect(held.foodPixelsAfter > 800 && held.foodPixelsAfter < 1350, "after \(held.foodPixelsAfter)")
        // Prune against a plane on the food top drops everything: the known
        // inert case, which leaves the segmenter's map as it was.
        let foodTop = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -560,
                                   residualMm: 0.5, convergedIterations: nil)
        let onFood = FoodRegionGrowth.prune(held, depth: ramped, intrinsics: k,
                                            supportPlane: foodTop, palette: palette,
                                            config: .standard)
        #expect(!onFood.applied && onFood.argmax == a)
    }

    @Test("growth past the frame cap returns the input unchanged and says so")
    func capTrips() {
        // Everything raised and flat: the fill would cover the whole frame.
        let d = depth { _, _ in 560 }
        let a = seedArgmax(cells: [(5, 4, 0)])
        let r = FoodRegionGrowth.grow(argmax: a, depth: d, intrinsics: k,
                                      supportPlane: plane, palette: palette)
        #expect(!r.applied)
        #expect(r.capTripped)
        #expect(r.argmax == a)
        #expect(r.foodPixelsAfter == r.foodPixelsBefore)
    }

    @Test("two seed classes on one slab split it by distance; neither is removed")
    func twoSeedsSplit() {
        let a = seedArgmax(cells: [(4, 5, 0), (11, 5, 1)])
        let r = FoodRegionGrowth.grow(argmax: a, depth: slabDepth, intrinsics: k,
                                      supportPlane: plane, palette: palette)
        #expect(r.applied)
        let labels = [UInt8](r.argmax.pixels)
        let count0 = labels.filter { $0 == 0 }.count
        let count1 = labels.filter { $0 == 1 }.count
        #expect(count0 + count1 > 700 && count0 + count1 < 1150)
        #expect(abs(count0 - count1) <= 64)
        #expect(Int(labels[(5 * 4) * w + 5 * 4]) == 0)    // near seed 0
        #expect(Int(labels[(5 * 4) * w + 10 * 4]) == 1)   // near seed 1
    }

    @Test("an unknown_food seed grows as unknown_food")
    func unknownGrows() {
        let r = FoodRegionGrowth.grow(argmax: seedArgmax(cells: [(5, 4, palette.unknownFood)]),
                                      depth: slabDepth, intrinsics: k,
                                      supportPlane: plane, palette: palette)
        #expect(r.applied)
        let labels = [UInt8](r.argmax.pixels)
        let n = labels.filter { Int($0) == palette.unknownFood }.count
        #expect(n > 700 && n < 1150, "unknown pixels \(n)")
    }

    @Test("low-confidence cells are not entered")
    func confidenceGates() {
        let d = depth({ dy, dx in inSlab(dx, dy) ? 560 : 599 },
                      conf: { dy, dx in dx >= 8 ? 127 : 255 })
        let r = FoodRegionGrowth.grow(argmax: seedArgmax(cells: [(5, 4, 0)]), depth: d,
                                      intrinsics: k, supportPlane: plane, palette: palette)
        #expect(r.applied)
        // Slab columns 4..<8 only (384 px), edge band free.
        #expect(r.foodPixelsAfter > 300 && r.foodPixelsAfter < 600, "after \(r.foodPixelsAfter)")
    }

    @Test("a disabled config and a background-only map are passthrough")
    func passthrough() {
        let a = seedArgmax(cells: [(5, 4, 0)])
        let off = FoodRegionGrowth.grow(argmax: a, depth: slabDepth, intrinsics: k,
                                        supportPlane: plane, palette: palette, config: .disabled)
        #expect(!off.applied && off.argmax == a)
        let empty = seedArgmax(cells: [])
        let none = FoodRegionGrowth.grow(argmax: empty, depth: slabDepth, intrinsics: k,
                                         supportPlane: plane, palette: palette)
        #expect(!none.applied && none.argmax == empty && none.foodPixelsBefore == 0)
    }

    @Test("two runs over the same inputs are byte-identical")
    func deterministic() {
        let a = seedArgmax(cells: [(4, 5, 0), (11, 5, 1)])
        let r1 = FoodRegionGrowth.grow(argmax: a, depth: slabDepth, intrinsics: k,
                                       supportPlane: plane, palette: palette)
        let r2 = FoodRegionGrowth.grow(argmax: a, depth: slabDepth, intrinsics: k,
                                       supportPlane: plane, palette: palette)
        #expect(r1.argmax == r2.argmax)
        #expect(r1.grownRegion?.pixels == r2.grownRegion?.pixels)
    }

    // Req 5: the integrator measures a grown pixel whose probabilities say
    // background when the region marks it, and skips it when unmarked.
    @Test("the integrator measures grown pixels only when the region marks them")
    func integratorHonoursGrownRegion() throws {
        let bg = palette.background
        // The seed block reads as food_0 (a real seed has P(class) > P(bg));
        // everything else reads as background.
        let probs = makeProbTensor(width: w, height: h, palette: palette) { y, x, c in
            let seed = x / 4 == 5 && y / 4 == 4
            if seed { return c == 0 ? 0.90 : 0.025 }
            return c == bg ? 0.95 : 0.0125
        }
        let grown = FoodRegionGrowth.grow(argmax: seedArgmax(cells: [(5, 4, 0)]), depth: slabDepth,
                                          intrinsics: k, supportPlane: plane, palette: palette)
        // Depth on the colour grid for the integrator: same slab at colour resolution.
        let colourDepth = makeDepthMap(width: w, height: h, intrinsics: k) { y, x in
            inSlab(x / 4, y / 4) ? 560 : 599
        }
        func integrate(region: BinaryMask?) -> VolumeOutcome<HeightFieldEstimate> {
            HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                probabilities: probs, argmax: grown.argmax, depth: colourDepth, intrinsics: k,
                supportPlane: plane, beta: BetaCorrection(entries: [:]), palette: palette,
                grownRegion: region))
        }
        let with = try #require(integrate(region: grown.grownRegion).estimate)
        let withVol = try #require(with.perClassVolumesCm3["food_0"])
        // Unmarked: only the 16 seed pixels pass the silhouette test.
        let without = try #require(integrate(region: nil).estimate)
        #expect(without.perClassFoodPixelCount["food_0"] == 16)
        #expect(with.perClassFoodPixelCount["food_0"] == grown.foodPixelsAfter)
        let withoutVol = try #require(without.perClassVolumesCm3["food_0"])
        #expect(withVol > withoutVol * 40)
    }
}
