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
}

private struct EmptyDB: FoodDatabase {
    var version: String { "growth-replay" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}
#endif
