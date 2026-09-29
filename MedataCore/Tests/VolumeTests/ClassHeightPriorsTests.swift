import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// The class height cap on the voxel carve (two-view-trust Decisions 11 and
// 12). The bundled `height_priors.json` is `tools/metafood3d/height_priors.py`'s
// output and the cap rules are `HEIGHT_PRIORS.md`'s: class max-height P90
// plus the shipped 5 mm margin, the global P90 for a class with no or too few
// meshes, and for a class in ratio mode the ratio P90 times the square root
// of the silhouette footprint, never above the height-mode cap. The numbers
// pinned here are the file's, so a regenerated file with different statistics
// fails here on purpose.

@Suite("ClassHeightPriors")
struct ClassHeightPriorsTests {

    let palette = ClassPalette.standard
    let margin = VoxelGridSizer.heightMarginMm

    func index(_ name: String) throws -> Int {
        try #require(palette.foodClasses.firstIndex(of: name))
    }

    @Test("the bundled file loads and matches the palette")
    func bundledLoads() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        #expect(priors.schema == "height_priors.v2")
        #expect(priors.matches(palette))
        #expect(priors.classNames[try index("bread_white")] == "bread_white")
        #expect(priors.globalP90Mm == 71.8)
    }

    @Test("bread_white caps at its P90 plus the margin")
    func breadWhite() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let cap = priors.cap(forPaletteIndex: try index("bread_white"))
        #expect(abs(cap.mm - (80.9 + margin)) < 1e-4)
        #expect(cap.source == .classPrior)
        #expect(priors.capMm(forPaletteIndex: try index("bread_white")) == cap.mm)
    }

    @Test("egg caps at its P90 plus the margin")
    func egg() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let cap = priors.cap(forPaletteIndex: try index("egg"))
        #expect(abs(cap.mm - (44.3 + margin)) < 1e-4)
        #expect(cap.source == .classPrior)
    }

    @Test("a class with no meshes and the unknown sentinel take the global P90")
    func nullClassIsGlobal() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        for i in [try index("pasta"), palette.unknownFood] {
            let cap = priors.cap(forPaletteIndex: i)
            #expect(abs(cap.mm - (71.8 + margin)) < 1e-4)
            #expect(cap.source == .global)
        }
    }

    @Test("fewer than four meshes is not a class prior")
    func fewItemsIsGlobal() throws {
        let json = """
        {"schema":"height_priors.v2","global":{"max_height_p90_mm":70.0},
         "classes":{"a":{"index":0,"n_items":3,"max_height_p90_mm":20.0,
                         "ratio_p90":0.5,"cap_mode":"ratio"},
                    "b":{"index":1,"n_items":4,"max_height_p90_mm":20.0}}}
        """
        let priors = try ClassHeightPriors(data: Data(json.utf8), marginMm: 5)
        #expect(priors.cap(forPaletteIndex: 0) == .init(mm: 75, source: .global))
        #expect(priors.cap(forPaletteIndex: 1) == .init(mm: 25, source: .classPrior))
        // Nor a ratio: three meshes is the global cap whatever the footprint.
        #expect(priors.cap(forPaletteIndex: 0, footprintMm2: 400) == .init(mm: 75, source: .global))
    }

    @Test("a wrong schema is refused")
    func schemaGuard() {
        let json = #"{"schema":"height_priors.v3","global":{"max_height_p90_mm":1},"classes":{}}"#
        #expect(throws: ClassHeightPriors.Error.unexpectedSchema("height_priors.v3")) {
            try ClassHeightPriors(data: Data(json.utf8))
        }
    }

    // MARK: - the footprint-scaled cap (Decision 12)

    @Test("bread_white in ratio mode scales its cap with the footprint")
    func breadWhiteRatio() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let bread = try index("bread_white")
        let r = try #require(priors.classRatioP90[bread])
        #expect(abs(r - 0.511) < 1e-4)
        // A roll-sized silhouette, 80 cm²: r x sqrt(8000) + margin.
        let cap = priors.cap(forPaletteIndex: bread, footprintMm2: 8000)
        #expect(abs(cap.mm - (0.511 * Float(8000).squareRoot() + margin)) < 1e-3)
        #expect(abs(cap.mm - 50.7) < 0.1)
        #expect(cap.source == .classRatio)
        #expect(priors.capMm(forPaletteIndex: bread, footprintMm2: 8000) == cap.mm)
        // The height-mode entry point is untouched.
        #expect(priors.cap(forPaletteIndex: bread) == .init(mm: 80.9 + margin, source: .classPrior))
    }

    @Test("the ratio cap is clamped between the floor and the height-mode cap")
    func ratioClamp() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let bread = try index("bread_white")
        // A fragment of a silhouette: the floor, still a ratio cap.
        let tiny = priors.cap(forPaletteIndex: bread, footprintMm2: 16)
        #expect(tiny == .init(mm: ClassHeightPriors.ratioFloorMm, source: .classRatio))
        // A whole-loaf footprint: the height-mode cap, and its source.
        let huge = priors.cap(forPaletteIndex: bread, footprintMm2: 60_000)
        #expect(huge == priors.cap(forPaletteIndex: bread))
        #expect(huge.source == .classPrior)
        // No footprint at all is the height-mode cap.
        #expect(priors.cap(forPaletteIndex: bread, footprintMm2: 0) == priors.cap(forPaletteIndex: bread))
    }

    @Test("a height-mode class ignores the footprint")
    func heightModeIgnoresFootprint() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let egg = try index("egg")
        #expect(priors.classRatioP90[egg] == nil)
        #expect(priors.cap(forPaletteIndex: egg, footprintMm2: 400) == priors.cap(forPaletteIndex: egg))
        #expect(priors.cap(forPaletteIndex: egg, footprintMm2: 400).source == .classPrior)
        // And so does a class on the global cap.
        let pasta = try index("pasta")
        #expect(priors.cap(forPaletteIndex: pasta, footprintMm2: 400).source == .global)
    }

    @Test("the carve takes the ratio cap only where no height is measured")
    func carveCapYieldsToAMeasurement() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let bread = try index("bread_white")
        var pixels = Data(repeating: UInt8(palette.background), count: 16)
        pixels[0] = UInt8(bread)
        let argmax = ArgmaxMap(pixels: pixels, height: 4, width: 4)
        let noDepth = priors.carveCap(
            forNadirArgmax: argmax, palette: palette, footprintMm2: 8000, heightMeasured: false)
        #expect(noDepth == priors.cap(forPaletteIndex: bread, footprintMm2: 8000))
        let lidar = priors.carveCap(
            forNadirArgmax: argmax, palette: palette, footprintMm2: 8000, heightMeasured: true)
        #expect(lidar == priors.cap(forPaletteIndex: bread))
        // A ratio cap in the sizer is the extent, and reports its source.
        let b = VoxelGridSizer.verticalBound(measuredFoodHeightMm: nil, classCap: noDepth)
        #expect(b.source == .classRatio)
        #expect(abs(b.extentMm - 50.7) < 0.1)
    }

    @Test("a nadir map with several classes takes the tallest cap")
    func severalClassesTakeTheTallest() throws {
        let priors = try #require(ClassHeightPriors.bundled)
        let egg = try index("egg"), bread = try index("bread_white")
        var pixels = Data(repeating: UInt8(palette.background), count: 16)
        pixels[0] = UInt8(egg)
        pixels[1] = UInt8(bread)
        let argmax = ArgmaxMap(pixels: pixels, height: 4, width: 4)
        let cap = try #require(priors.cap(forNadirArgmax: argmax, palette: palette))
        #expect(cap == priors.cap(forPaletteIndex: bread))
        let none = ArgmaxMap(pixels: Data(repeating: UInt8(palette.background), count: 16),
                             height: 4, width: 4)
        #expect(priors.cap(forNadirArgmax: none, palette: palette) == nil)
    }

    // MARK: - the sizer's bound

    @Test("without a measurement the cap is the extent")
    func noDepthTakesTheCap() {
        let cap = ClassHeightPriors.Cap(mm: 85.9, source: .classPrior)
        let b = VoxelGridSizer.verticalBound(measuredFoodHeightMm: nil, classCap: cap)
        #expect(b == .init(extentMm: 85.9, source: .classPrior))
        let g = VoxelGridSizer.verticalBound(
            measuredFoodHeightMm: nil, classCap: .init(mm: 76.8, source: .global))
        #expect(g.source == .global)
        #expect(VoxelGridSizer.verticalBound(measuredFoodHeightMm: nil, classCap: nil).source == .constant)
    }

    @Test("a measurement below the cap stands, and the cap never raises it")
    func capOnlyLowers() {
        let cap = ClassHeightPriors.Cap(mm: 85.9, source: .classPrior)
        let measured = VoxelGridSizer.verticalBound(measuredFoodHeightMm: 47.3, classCap: cap)
        #expect(measured == .init(extentMm: 47.3 + VoxelGridSizer.heightMarginMm, source: .measured))
        #expect(measured == VoxelGridSizer.verticalBound(measuredFoodHeightMm: 47.3, classCap: nil))
        let bitten = VoxelGridSizer.verticalBound(measuredFoodHeightMm: 100, classCap: cap)
        #expect(bitten == .init(extentMm: 85.9, source: .classPrior))
        // A cap above the shipped constant clamps to it.
        let tall = VoxelGridSizer.verticalBound(
            measuredFoodHeightMm: nil, classCap: .init(mm: 127.6, source: .classPrior))
        #expect(tall.extentMm == VoxelGridSizer.verticalExtentMm)
    }

    @Test("the sized grid follows the bound to whole voxels")
    func gridFollowsTheBound() throws {
        let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                 distortion: [], imageWidth: 100, imageHeight: 100)
        let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                                 residualMm: 0.5, convergedIterations: nil)
        let mask = makeBinaryMask(width: 100, height: 100) { y, x in
            (40..<60).contains(x) && (40..<60).contains(y)
        }
        let cap = ClassHeightPriors.Cap(mm: 85.9, source: .classPrior)
        let capped = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask, nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: Vec3(0, 0, 1), classCap: cap))
        #expect(capped.dimsZ == 29)                                   // ceil(85.9 / 3)
        let measured = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask, nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: Vec3(0, 0, 1), measuredFoodHeightMm: 47.3, classCap: cap))
        let unCapped = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask, nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: Vec3(0, 0, 1), measuredFoodHeightMm: 47.3))
        #expect(measured == unCapped)
        let constant = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask, nadirIntrinsics: k, supportPlane: plane,
            gravityCamera: Vec3(0, 0, 1)))
        #expect(constant.dimsZ == 40)
    }
}
