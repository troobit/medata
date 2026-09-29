import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// Bugfix two-view-unknown-carve (BACKLOG 24). On 2026-09-24 two two-view
// captures of a sesame roll recorded an unknown_food row of 1148 cm³ and
// 317 cm³ from a nadir mask with no unknown pixels: the oblique view alone
// labelled some pixels unknown_food, MaskMatcher marked the class single-view-
// only in view 2, and the §6.6 fallback extruded the oblique silhouette to the
// plane at the 30 mm prior height. The nadir is the primary silhouette on both
// capture paths; an unknown region the nadir does not see is not evidence of
// food, and the fallback must not fabricate a row from it.

@Suite("VoxelCarve: unknown_food seen only in the oblique view")
struct VoxelCarveObliqueOnlyUnknownTests {

    // food_0 = 0, food_1 = 1, bg = 2, unknown = 3, liquid = 4.
    let palette = makePalette(numFood: 2)
    let intrinsics = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                      distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)
    var grid: VoxelGrid {
        VoxelGrid(edgeMm: 5, dimsX: 10, dimsY: 10, dimsZ: 10,
                  originCamera1: Vec3(0, 0, -400),
                  axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1))
    }

    // View 1 (nadir): food_0 everywhere. View 2 (oblique): food_0 on the left
    // half, unknown_food on the right half.
    func probs(unknownOnRight: Bool) -> ProbabilityTensor {
        let bg = palette.background
        let unknown = palette.unknownFood
        return makeProbTensor(width: 100, height: 100, palette: palette) { _, x, c in
            let label = (unknownOnRight && x >= 50) ? unknown : 0
            return c == label ? 0.90 : (c == bg ? 0.05 : 0.025)
        }
    }

    func inputs(unknownIn view: Int) -> VoxelCarveEstimator.Inputs {
        let p1 = probs(unknownOnRight: view == 1)
        let p2 = probs(unknownOnRight: view == 2)
        let matching = MaskMatcher.match(
            view1: argmax(of: p1), view2: argmax(of: p2), palette: palette)
        return VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: p1, intrinsics: intrinsics),
            view2: VoxelCarveView(probabilities: p2, intrinsics: intrinsics),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: matching.matchedClasses,
            singleViewOnlyClassesView1: matching.singleViewOnly(view: 1),
            singleViewOnlyClassesView2: matching.singleViewOnly(view: 2),
            beta: BetaCorrection(),
            palette: palette)
    }

    func argmax(of p: ProbabilityTensor) -> ArgmaxMap {
        let c = p.classes
        return makeArgmax(width: p.width, height: p.height) { y, x in
            p.bytes.withUnsafeBytes { raw in
                let buf = raw.bindMemory(to: Float16.self).baseAddress!
                let off = (y * p.width + x) * c
                var best = 0
                for k in 1..<c where buf[off + k] > buf[off + best] { best = k }
                return best
            }
        }
    }

    @Test("unknown_food present only in the oblique view yields no unknown row")
    func obliqueOnlyUnknownIsNotFabricated() throws {
        let outcome = VoxelCarveEstimator.carve(inputs(unknownIn: 2))
        let est = try #require(outcome.estimate)
        #expect(est.perClassVolumesCm3["unknown_food"] == nil,
                "oblique-only unknown_food read \(est.perClassVolumesCm3["unknown_food"] ?? 0) cm³")
        #expect(outcome.stats.perClassVolumesPreBetaCm3["unknown_food"] == nil)
        #expect((est.perClassVolumesCm3["food_0"] ?? 0) > 0)
    }

    @Test("unknown_food present only in the nadir view keeps its fallback row")
    func nadirOnlyUnknownStillCarries() throws {
        let outcome = VoxelCarveEstimator.carve(inputs(unknownIn: 1))
        let est = try #require(outcome.estimate)
        #expect((est.perClassVolumesCm3["unknown_food"] ?? 0) > 0)
    }
}
