#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
import Volume
@testable import HarnessCore

// depth-grown-food-region Req 7: the single-view replay grows the region the
// device grows. Scene: ParityScene.plateAboveTable with an 8 mm disc of radius
// 10 depth cells on a 20 mm plate over the table. The "segmenter" labels a
// 6-cell-radius seed at the disc's centre — sized so the first fit's bands
// around it fall on the plate (a foodSupport fit at the plate top, as on the
// 2026-09-24 roll capture the fallback was the table with the plate at the
// ring median); growth must recover the disc, the refit must stay on the
// plate, and the volume must match the whole disc.

@Suite("FixtureRunner depth-grown food region")
struct FoodRegionGrowthReplayTests {

    // food_0 = 0, food_1 = 1; bg = 2, unknown = 3, unsupported = 4.
    static let palette = ClassPalette(
        foodClasses: ["food_0", "food_1"], background: 2, unknownFood: 3,
        unsupportedLiquid: 4, version: "test")
    static let seedRadiusCells: Float = 6
    static let foodRadiusCells: Float = 10

    static func fixture(seedRadius: Float, foodRadius: Float = foodRadiusCells) -> PbMealFixture {
        let w = ParityScene.colourWidth, h = ParityScene.colourHeight
        let dw = ParityScene.depthWidth, dh = ParityScene.depthHeight
        let classes = palette.totalClasses
        var values = [Float](repeating: 0, count: w * h * classes)
        var argmax = [UInt8](repeating: UInt8(palette.background), count: w * h)
        for y in 0..<h {
            let dy = min(dh - 1, Int((Float(y) + 0.5) * Float(dh) / Float(h)))
            for x in 0..<w {
                let dx = min(dw - 1, Int((Float(x) + 0.5) * Float(dw) / Float(w)))
                let p = y * w + x
                let seed = ParityScene.radius(dx, dy) <= seedRadius
                argmax[p] = seed ? 0 : UInt8(palette.background)
                values[p * classes + (seed ? 0 : palette.background)] = 0.9
            }
        }
        var fx = PbMealFixture()
        fx.fixtureID = "growth-replay"
        fx.segmenterCheckpointSha256 = String(repeating: "0", count: 64)
        fx.capturePathCanonical = "single_view_lidar"
        fx.estimatorPath = "single_dominant"
        fx.nadirIntrinsics = ParityScene.colourIntrinsics.pb
        fx.nadirDepth = ParityScene.depth(ParityScene.plateAboveTable(foodRadiusPx: foodRadius)).pb
        fx.gravity = ParityScene.gravity.pb
        fx.nadirProbs = FP16Bytes.encode(values)
        fx.nadirArgmax = Data(argmax)
        return fx
    }

    @Test("a speck seed grows to the disc, refits on the plate, and measures the whole disc")
    func replayGrowsAndRefits() throws {
        let fx = Self.fixture(seedRadius: Self.seedRadiusCells)
        let grown = try FixtureRunner.run(
            fixture: fx, palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .standard)
        let ungrown = try FixtureRunner.run(
            fixture: fx, palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .disabled)
        #expect(ungrown.regionGrowth?.applied == false)
        let g = try #require(grown.regionGrowth)
        #expect(g.applied)
        #expect(!g.capTripped)
        #expect(g.refitReference == .foodSupport)
        #expect(grown.supportPlaneReference == .foodSupport)
        // Disc area ≈ π·10² ≈ 314 cells of 4×4 colour pixels.
        #expect(g.foodPixelsAfter > 280 * 16 && g.foodPixelsAfter < 350 * 16)
        let vGrown = try #require(grown.perClassVolumesCm3["food_0"])
        let vUngrown = try #require(ungrown.perClassVolumesCm3["food_0"])
        // 8 mm × π·(20 mm)² ≈ 10 cm³ for the disc; the seed is ~36 % of it.
        #expect(vGrown > 8 && vGrown < 12, "grown volume \(vGrown) cm³")
        #expect(vGrown > vUngrown * 2, "ungrown volume \(vUngrown) cm³")
    }

    // MARK: - two-view (Decision 10)

    // The same disc with a pre-shutter mask covering the whole PLATE, so the
    // first fit's bands fall on the table and the plane sits 20 mm under the
    // food's support; the grown disc refits on the plate. Colour-grid mask, as
    // the device records it.
    static func plateMasked(_ fx: PbMealFixture) -> PbMealFixture {
        var fx = fx
        let w = ParityScene.colourWidth, h = ParityScene.colourHeight
        fx.preShutterMask = Data(ParityScene.colourMask(
            ParityScene.grid { x, y in (0, ParityScene.radius(x, y) <= 28) }).pixels)
        fx.preShutterMaskWidth = Int32(w)
        fx.preShutterMaskHeight = Int32(h)
        return fx
    }

    // An oblique camera orbited `tiltDeg` about +X through the seed's centre
    // (T(F)·R_x(−θ)·T(−F), as CarveResidualAuditTests builds it), and the
    // seed cylinder's exact silhouette in that view: the segmenter saw the
    // seed in both photos, nothing more. Seed radius 6 depth cells is
    // 6 · z / 175 mm at depth z (2 mm per cell at the 350 mm table).
    static func twoViewFixture(seedRadius: Float, tiltDeg: Float) -> PbMealFixture {
        var fx = plateMasked(fixture(seedRadius: seedRadius))
        fx.fixtureID = "growth-replay-two-view"
        fx.capturePathCanonical = "two_view_sfs"
        let plateTop: Float = -(ParityScene.tableDepthMm - 20)   // −330
        let discTop: Float = plateTop + 8                          // −322
        let f = (plateTop + discTop) / 2
        let t = tiltDeg * .pi / 180
        let c = cos(t), s = sin(t)
        let t1to2 = Mat4(columns: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0],
                                   [0, -(s * f), f - (c * f), 1]])
        let k = ParityScene.colourIntrinsics
        var points: [SIMD2<Float>] = []
        for i in 0..<48 {
            let a = Float(i) * 2 * .pi / 48
            for z in [plateTop, discTop] {
                let r = seedRadius * -z / 175
                let p = Vec3(r * cos(a), r * sin(a), z)
                if let q = CarveResidualAudit.project(k, CarveResidualAudit.apply(t1to2, p)) {
                    points.append(q)
                }
            }
        }
        let mask = CarveResidualAudit.polygonMask(
            CarveResidualAudit.convexHull(points), width: k.imageWidth, height: k.imageHeight)
        let classes = palette.totalClasses
        var values = [Float](repeating: 0, count: k.imageWidth * k.imageHeight * classes)
        var argmax = [UInt8](repeating: UInt8(palette.background), count: k.imageWidth * k.imageHeight)
        for p in 0..<(k.imageWidth * k.imageHeight) {
            let food = mask.pixels[p] != 0
            argmax[p] = food ? 0 : UInt8(palette.background)
            values[p * classes + (food ? 0 : palette.background)] = 0.9
        }
        fx.obliqueIntrinsics = k.pb
        fx.obliqueProbs = FP16Bytes.encode(values)
        fx.obliqueArgmax = Data(argmax)
        fx.t1To2 = t1to2.pb
        return fx
    }

    @Test("the two-view replay adopts the grown region's plane, plane only, and carves less from it")
    func twoViewRefitsThePlaneOnly() throws {
        let fx = Self.twoViewFixture(seedRadius: Self.seedRadiusCells, tiltDeg: 15)
        let refitted = try FixtureRunner.run(
            fixture: fx, palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .standard)
        let held = try FixtureRunner.run(
            fixture: fx, palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .disabled)
        #expect(refitted.capturePath == .twoViewSfS)
        #expect(held.regionGrowth?.applied == false)
        let g = try #require(refitted.regionGrowth)
        #expect(g.applied)
        #expect(g.refitReference == .foodSupport)
        #expect(refitted.supportPlaneReference == .foodSupport)
        let vRefit = try #require(refitted.perClassVolumesCm3["food_0"])
        let vHeld = try #require(held.perClassVolumesCm3["food_0"])
        // The plane rose to the plate, so the carve lost the slab of hull the
        // first plane put under the seed.
        #expect(held.supportPlaneResidualMm != refitted.supportPlaneResidualMm)
        #expect(vRefit < vHeld, "refit \(vRefit) cm³ against held \(vHeld) cm³")
        // Plane only: the silhouette stayed the seed's. Labelling the whole
        // disc in both views carves the disc's own footprint, ~2.8× the seed's.
        let disc = try FixtureRunner.run(
            fixture: Self.twoViewFixture(seedRadius: Self.foodRadiusCells, tiltDeg: 15),
            palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .standard)
        let vDisc = try #require(disc.perClassVolumesCm3["food_0"])
        #expect(vRefit < vDisc * 0.6, "refit \(vRefit) cm³ against disc \(vDisc) cm³")
    }

    @Test("both branches adopt the same plane from the same nadir inputs")
    func twoViewPlaneMatchesTheSingleViewPlane() throws {
        let single = try FixtureRunner.run(
            fixture: Self.plateMasked(Self.fixture(seedRadius: Self.seedRadiusCells)),
            palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .standard)
        let twoView = try FixtureRunner.run(
            fixture: Self.twoViewFixture(seedRadius: Self.seedRadiusCells, tiltDeg: 15),
            palette: Self.palette, database: EmptyDB(),
            regularisation: .disabled, growth: .standard)
        #expect(single.supportPlaneReference == .foodSupport)
        #expect(single.supportPlaneReference == twoView.supportPlaneReference)
        #expect(single.supportPlaneResidualMm == twoView.supportPlaneResidualMm)
        #expect(single.regionGrowth?.refitReference == twoView.regionGrowth?.refitReference)
        #expect(single.regionGrowth?.foodPixelsAfter == twoView.regionGrowth?.foodPixelsAfter)
    }

    // The device refuses at stage D when a depth-bearing capture's fit refuses,
    // on either path. The replay and the carve audit must refuse there too, not
    // carve on the nominal plane that exists for depth-free fixtures only.
    @Test("a two-view fixture whose LiDAR fit refuses is refused at the plane, not carved")
    func twoViewFitRefusalRefuses() throws {
        var fx = Self.twoViewFixture(seedRadius: Self.seedRadiusCells, tiltDeg: 15)
        fx.nadirDepth = ParityScene.blankDepth().pb
        let replays: [() throws -> Void] = [
            { _ = try FixtureRunner.run(fixture: fx, palette: Self.palette, database: EmptyDB(),
                                        regularisation: .disabled) },
            { _ = try CarveResidualAudit.audit(fixture: fx, palette: Self.palette) },
        ]
        for replay in replays {
            do {
                try replay()
                Issue.record("a fixture the device refuses produced a number")
            } catch FixtureRunner.Error.volumeEstimationFailed(_, let cause) {
                #expect(cause is SupportPlaneError, "refused at \(cause), not at the plane")
            }
        }
    }
}

private struct EmptyDB: FoodDatabase {
    var version: String { "growth-replay" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}
#endif
