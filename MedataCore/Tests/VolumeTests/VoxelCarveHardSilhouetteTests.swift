import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// The carve's silhouette is the regularised label map, not the raw tensor
// (two-view-trust, 2026-09-25). Geometry as in VoxelCarveEstimatorTests.
//
// The halo this pins is the one measured on bundle `1790318627741`: pixels with
// no winning class but at least half their probability mass off background
// passed the old test, giving a nadir silhouette 28 % larger than the label map
// and a footprint ~40 % larger than the food.

final class VoxelCarveHardSilhouetteTests: XCTestCase {

    let palette = makePalette(numFood: 2)   // food_0=0, food_1=1, bg=2
    let intrinsics = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                      distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)
    var grid: VoxelGrid {
        VoxelGrid(edgeMm: 5, dimsX: 10, dimsY: 10, dimsZ: 10,
                  originCamera1: Vec3(0, 0, -400),
                  axisX: Vec3(1, 0, 0), axisY: Vec3(0, 1, 0), axisZ: Vec3(0, 0, 1))
    }

    // Left half: food_0 wins outright. Right half: the halo — background is the
    // biggest single channel but holds only 45 % of the mass, so (1 − q[bg])
    // clears τ_sil while no class wins.
    func haloProbs() -> ProbabilityTensor {
        makeProbTensor(width: 100, height: 100, palette: palette) { _, x, c in
            if x < 50 {
                return c == 0 ? 0.90 : (c == palette.background ? 0.05 : 0.025)
            }
            switch c {
            case 0: return 0.28
            case 1: return 0.27
            case palette.background: return 0.45
            default: return 0
            }
        }
    }

    // The regularised label map the rest of the pipeline reads: the halo is
    // background, because no class won there.
    func haloArgmax() -> ArgmaxMap {
        makeArgmax(width: 100, height: 100) { _, x in x < 50 ? 0 : palette.background }
    }

    func inputs(argmax: ArgmaxMap?) -> VoxelCarveEstimator.Inputs {
        let p = haloProbs()
        return VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: p, intrinsics: intrinsics, argmax: argmax),
            view2: VoxelCarveView(probabilities: p, intrinsics: intrinsics, argmax: argmax),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: [0, 1],
            singleViewOnlyClassesView1: [],
            singleViewOnlyClassesView2: [],
            beta: BetaCorrection(),
            palette: palette
        )
    }

    func testTheLabelMapExcludesTheSoftHalo() throws {
        let soft = try XCTUnwrap(VoxelCarveEstimator.carve(inputs(argmax: nil)).estimate)
        let hard = try XCTUnwrap(VoxelCarveEstimator.carve(inputs(argmax: haloArgmax())).estimate)
        let softVol = soft.perClassVolumesCm3["food_0"] ?? 0
        let hardVol = hard.perClassVolumesCm3["food_0"] ?? 0
        // The halo is half the image and the grid straddles both halves, so the
        // soft test carves substantially more of the same grid.
        XCTAssertGreaterThan(softVol, hardVol,
            "soft \(softVol) cm³ must exceed hard \(hardVol) cm³")
        XCTAssertGreaterThan(hardVol, 0, "the real food must survive the hard test")
    }

    func testAMismatchedLabelMapIsRefused() {
        let p = haloProbs()
        let wrong = makeArgmax(width: 50, height: 50) { _, _ in 0 }
        let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: p, intrinsics: intrinsics, argmax: wrong),
            view2: VoxelCarveView(probabilities: p, intrinsics: intrinsics, argmax: nil),
            transform1To2: .identity,
            supportPlane: plane,
            matchedClasses: [0, 1],
            singleViewOnlyClassesView1: [],
            singleViewOnlyClassesView2: [],
            beta: BetaCorrection(),
            palette: palette
        ))
        XCTAssertNil(outcome.estimate)
        guard case .mismatchedViewDimensions = outcome.refusal else {
            return XCTFail("expected mismatchedViewDimensions, got \(String(describing: outcome.refusal))")
        }
    }
}
