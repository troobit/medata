import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// `unknown_food` integrates as its own class (unknown-food-nameable Req 3):
// the segmenter found food it cannot name, and the volume is carried through
// under the sentinel's class id so review can name it. Geometry mirrors
// HeightFieldLiquidTests: nadir plane at z = −600 mm, food top at z = −520.

@Suite("HeightFieldEstimator unknown_food integration")
struct HeightFieldUnknownTests {

    // food_0 = 0; bg = 1, unknown = 2, unsupported = 3.
    let palette = ClassPalette(
        foodClasses: ["food_0"],
        background: 1,
        unknownFood: 2,
        unsupportedLiquid: 3,
        version: "test"
    )
    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)

    private func inputs(argmaxLabel: @escaping (Int, Int) -> Int,
                        probLabel: Int) -> HeightFieldEstimator.Inputs {
        let bgId = palette.background
        return HeightFieldEstimator.Inputs(
            probabilities: makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
                c == probLabel ? 0.90 : (c == bgId ? 0.05 : 0.01)
            },
            argmax: makeArgmax(width: 100, height: 100, label: argmaxLabel),
            depth: makeDepthMap(width: 100, height: 100, intrinsics: k,
                                depthMm: { _, _ in 520 }),
            intrinsics: k,
            supportPlane: plane,
            beta: BetaCorrection(entries: ["food_0": 0.8]),
            palette: palette
        )
    }

    @Test("an all-unknown frame yields a positive volume keyed unknown_food at unity β")
    func allUnknownIntegrates() throws {
        let unknown = palette.unknownFood
        let outcome = HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, _ in unknown }, probLabel: unknown))
        let result = try #require(outcome.estimate)
        let vol = try #require(result.perClassVolumesCm3["unknown_food"])
        #expect(vol > 0)
        #expect(result.perClassVolumesCm3.count == 1)
        #expect(outcome.stats.betaApplied["unknown_food"] == 1)
        #expect(outcome.stats.perClassVolumesPreBetaCm3["unknown_food"] == vol)
    }

    @Test("unknown alongside a named class integrates both, each under its own β")
    func mixedScene() throws {
        let unknown = palette.unknownFood
        let outcome = HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, x in x < 50 ? 0 : unknown }, probLabel: 0))
        let result = try #require(outcome.estimate)
        let food = try #require(result.perClassVolumesCm3["food_0"])
        let unk = try #require(result.perClassVolumesCm3["unknown_food"])
        #expect(food > 0)
        #expect(unk > 0)
        #expect(outcome.stats.betaApplied["food_0"] == 0.8)
        #expect(outcome.stats.betaApplied["unknown_food"] == 1)
    }

    @Test("the pre-β volume round-trips through the persisted volume result")
    func preBetaRoundTrips() throws {
        var pb = PbVolumeResult()
        pb.perClassVolumesCm3 = ["unknown_food": 42.5]
        pb.perClassVolumesPreBetaCm3 = ["unknown_food": 42.5]
        let bytes = try pb.serializedData()
        let back = try PbVolumeResult(serializedBytes: bytes)
        #expect(back.perClassVolumesPreBetaCm3["unknown_food"] == 42.5)
    }
}
