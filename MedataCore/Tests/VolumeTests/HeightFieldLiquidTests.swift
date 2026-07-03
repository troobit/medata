import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// Liquid surface-to-plane volume (Req 7.3, Decisions 19/23/24).
//
// Recognised liquid classes integrate the visible liquid surface down to the
// support plane through isLiquidClass — strictly opt-in; isFoodClass keeps its
// solids-only meaning. unsupported_liquid stays skipped. The integration
// includes the vessel base/walls (a known upward bias): converting the volume
// to carbs and raising the liquid over-estimate flag is LiquidResolver's job,
// tested there.
//
// Geometry mirrors HeightFieldEstimatorTests: camera at origin, −Z forward,
// support plane n̂ = (0,0,1) at z = −600 mm. With that nadir plane the ray-plane
// height reduces to (600 − z_t) per pixel, so flat AND tilted synthetic
// surfaces have a closed-form analytic volume.

@Suite("HeightFieldEstimator liquid integration")
struct HeightFieldLiquidTests {

    // food_0 = 0; water = 1, beer = 2; bg = 3, unknown = 4, unsupported = 5.
    let palette = ClassPalette(
        foodClasses: ["food_0"],
        liquidClasses: ["water", "beer"],
        background: 3,
        unknownFood: 4,
        unsupportedLiquid: 5,
        version: "test_v1"
    )
    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)
    let planeZMm: Float = 600

    private var waterId: Int { palette.foodClasses.count }

    private func probs(for label: Int) -> ProbabilityTensor {
        let bgId = palette.background
        return makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == label ? 0.90 : (c == bgId ? 0.05 : 0.01)
        }
    }

    private func inputs(argmaxLabel: (Int, Int) -> Int,
                        probLabel: Int,
                        depthMm: @escaping (Int, Int) -> Float,
                        conf: @escaping (Int, Int) -> UInt8 = { _, _ in 255 })
        -> HeightFieldEstimator.Inputs {
        HeightFieldEstimator.Inputs(
            probabilities: probs(for: probLabel),
            argmax: makeArgmax(width: 100, height: 100, label: argmaxLabel),
            depth: makeDepthMap(width: 100, height: 100, intrinsics: k,
                                depthMm: depthMm, conf: conf),
            intrinsics: k,
            supportPlane: plane,
            beta: BetaCorrection(),
            palette: palette
        )
    }

    // Closed form of the estimator's integral for the nadir plane: per pixel,
    // a_p = z_t²/(fx·fy·cos³θ) and height = 600 − z_t.
    private func analyticCm3(depthMm: (Int, Int) -> Float) -> Float {
        let fMean = (k.fx + k.fy) / 2
        var mm3 = 0.0
        for y in 0..<100 {
            for x in 0..<100 {
                let zt = depthMm(y, x)
                guard zt > 0 else { continue }
                let du = Float(x) - k.cx
                let dv = Float(y) - k.cy
                let cosT = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                let aP = Double(zt * zt) /
                    (Double(k.fx * k.fy) * Double(cosT * cosT * cosT))
                mm3 += aP * Double(max(0, planeZMm - zt))
            }
        }
        return Float(mm3 / 1000)
    }

    @Test("flat liquid surface integrates to its analytic volume")
    func flatSurface() throws {
        let depth: (Int, Int) -> Float = { _, _ in 520 }
        let result = try HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, _ in self.waterId },
                   probLabel: waterId, depthMm: depth))
        let expected = analyticCm3(depthMm: depth)
        let vol = try #require(result.perClassVolumesCm3["water"])
        #expect(abs(vol - expected) / expected <= 0.03,
                "liquid volume \(vol) cm³ not within 3% of analytic \(expected) cm³")
    }

    @Test("tilted liquid surfaces integrate to their analytic volume",
          arguments: [Float(0.25), 0.5, 1.0])
    func tiltedSurface(slopeMmPerPx: Float) throws {
        // Depth increases linearly across x: a plane tilted about the y-axis.
        let depth: (Int, Int) -> Float = { _, x in 450 + slopeMmPerPx * Float(x) }
        let result = try HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, _ in self.waterId },
                   probLabel: waterId, depthMm: depth))
        let expected = analyticCm3(depthMm: depth)
        let vol = try #require(result.perClassVolumesCm3["water"])
        #expect(abs(vol - expected) / expected <= 0.03,
                "tilted (slope \(slopeMmPerPx)) volume \(vol) cm³ not within 3% of analytic \(expected) cm³")
    }

    @Test("unsupported_liquid stays skipped")
    func unsupportedLiquidSkipped() throws {
        // Left half solid food, right half unsupported_liquid: only the food
        // integrates and no unsupported key appears.
        let unsupported = palette.unsupportedLiquid
        let result = try HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, x in x < 50 ? 0 : unsupported },
                   probLabel: 0, depthMm: { _, _ in 520 }))
        #expect(result.perClassVolumesCm3["food_0"] != nil)
        #expect(result.perClassVolumesCm3.count == 1)
    }

    @Test("a recognised liquid alongside food integrates both")
    func mixedScene() throws {
        let result = try HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, x in x < 50 ? 0 : self.waterId },
                   probLabel: 0, depthMm: { _, _ in 520 }))
        let food = try #require(result.perClassVolumesCm3["food_0"])
        let water = try #require(result.perClassVolumesCm3["water"])
        #expect(food > 0)
        #expect(water > 0)
    }

    @Test("low liquid depth coverage does not refuse the estimate")
    func lowLiquidCoverageDoesNotThrow() throws {
        // Transparent liquids return poor depth. The coverage REFUSAL stays a
        // solid-food rule — the liquid's low coverage is reported so
        // LiquidResolver can apply the Req 7.6 usable-surface-depth precedence,
        // not thrown as a whole-estimate error.
        let result = try HeightFieldEstimator.integrate(
            inputs(argmaxLabel: { _, x in x < 50 ? 0 : self.waterId },
                   probLabel: 0,
                   depthMm: { _, _ in 520 },
                   conf: { _, x in x < 55 ? 255 : 0 }))  // liquid ~10% covered
        let liquidCoverage = try #require(result.lidarCoverageFraction["water"])
        #expect(liquidCoverage < 0.3)
        #expect(result.perClassVolumesCm3["food_0"] != nil)
    }
}
