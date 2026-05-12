import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Tests for HeightFieldEstimator per design §6.7.
//
// Geometry:
//   Camera at origin, −Z forward (standard §6.0 convention).
//   Support plane: n̂ = (0,0,1), distanceMm = −600 → table at z = −600 mm.
//   Food at z = −500 mm → height H = 100 mm above table.
//   Depth map values = 500.0 (|food z|) with confidence = 255.
//
//   For center pixel (cx, cy): dir = (0,0,−1), alphaSup = 600.
//   zS = 600, zTopAbs = 500, height = 100 mm. ✓
//
//   For nadir-style camera convention the support plane normal aligns with the
//   optical axis; off-axis corrections are testable at all scales.

final class HeightFieldEstimatorTests: XCTestCase {

    // MARK: - fixtures

    let palette = makePalette(numFood: 2)

    // Standard setup: 100×100, fx=fy=500 (narrow, cos θ ≈ 1 everywhere).
    let k500 = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                                distortion: [], imageWidth: 100, imageHeight: 100)
    // Wide-angle setup: fx=fy=100 (large off-axis angles to verify 1/cos³θ).
    let kWide = CameraIntrinsics(fx: 100, fy: 100, cx: 50, cy: 50,
                                 distortion: [], imageWidth: 100, imageHeight: 100)

    // Support plane at z = −600.
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)

    let ztMm: Float  = 500   // food-top depth
    let hMm: Float   = 100   // height above table (= 600 − 500)

    // All-food probability tensor: q_food0=0.90, q_bg=0.05.
    func makeAllFoodProbs(w: Int = 100, h: Int = 100) -> ProbabilityTensor {
        let bgId = palette.background
        return makeProbTensor(width: w, height: h, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
    }

    // All-food argmax map.
    func makeAllFoodArgmax(w: Int = 100, h: Int = 100) -> ArgmaxMap {
        makeArgmax(width: w, height: h) { _, _ in 0 }
    }

    // Uniform depth at ztMm, full confidence.
    func makeDepth(w: Int = 100, h: Int = 100, k: CameraIntrinsics) -> DepthMap {
        makeDepthMap(width: w, height: h, intrinsics: k,
                     depthMm: { _, _ in self.ztMm })
    }

    func makeInputs(k: CameraIntrinsics,
                    probs: ProbabilityTensor? = nil,
                    argmax: ArgmaxMap? = nil,
                    depth: DepthMap? = nil,
                    beta: BetaCorrection = BetaCorrection()) -> HeightFieldEstimator.Inputs {
        let k_ = k
        return HeightFieldEstimator.Inputs(
            probabilities: probs ?? makeAllFoodProbs(w: k_.imageWidth, h: k_.imageHeight),
            argmax: argmax ?? makeAllFoodArgmax(w: k_.imageWidth, h: k_.imageHeight),
            depth: depth ?? makeDepth(w: k_.imageWidth, h: k_.imageHeight, k: k_),
            intrinsics: k_,
            supportPlane: plane,
            beta: beta,
            palette: palette
        )
    }

    // MARK: - T26.1 Flat food volume within 3% of analytical

    func testFlatFoodVolumeWithin3Percent() throws {
        let inputs = makeInputs(k: k500)
        let result = try HeightFieldEstimator.integrate(inputs)

        // Expected: sum over all pixels of a_p × H, where
        // a_p = z_t² / (fx·fy·cos³θ) and cos θ = fMean/sqrt(fMean²+du²+dv²).
        let fMean = (k500.fx + k500.fy) / 2
        var expectedMm3: Double = 0
        for py in 0..<100 {
            for px in 0..<100 {
                let du = Float(px) - k500.cx
                let dv = Float(py) - k500.cy
                let denom = sqrt(fMean * fMean + du * du + dv * dv)
                let cosT = fMean / denom
                let cos3 = Double(cosT * cosT * cosT)
                let aP = Double(ztMm * ztMm) / (Double(k500.fx * k500.fy) * cos3)
                expectedMm3 += aP * Double(hMm)
            }
        }
        let expectedCm3 = Float(expectedMm3 / 1000)
        let vol = result.perClassVolumesCm3["food_0"] ?? 0
        XCTAssertLessThanOrEqual(abs(vol - expectedCm3) / expectedCm3, 0.03,
            "Volume \(vol) cm³ not within 3% of analytical \(expectedCm3) cm³")
    }

    // MARK: - T26.2 Off-axis 1/cos³θ correction: wide-angle run > flat approximation

    func testOffAxisCorrectionIncreasesVolume() throws {
        // Wide-angle camera (fx=fy=100): corner pixel (0,0) has
        //   du=dv=−50, cosθ = 100/√(100²+50²+50²) = 100/√15000 ≈ 0.816 → 1/cos³θ ≈ 1.84.
        // The off-axis correction must inflate total volume above the flat (θ=0) baseline.
        let inputs = makeInputs(k: kWide, depth: makeDepth(w: 100, h: 100, k: kWide))
        let result = try HeightFieldEstimator.integrate(inputs)

        // Flat baseline: every pixel treated as on-axis, a_p = z_t² / (fx·fy).
        let flatAreaPerPixel = ztMm * ztMm / (kWide.fx * kWide.fy)
        let flatVolumeCm3 = Float(100 * 100) * flatAreaPerPixel * hMm / 1000
        let vol = result.perClassVolumesCm3["food_0"] ?? 0
        XCTAssertGreaterThan(vol, flatVolumeCm3,
            "Off-axis correction should inflate volume above flat baseline \(flatVolumeCm3) cm³")
    }

    // MARK: - T26.3 Per-class lidarCoverageFraction tracking

    func testCoverageFractionTracking() throws {
        // 80 out of 100 pixels in row direction have full confidence; other 20 have conf=0.
        // Coverage for food_0 should be ≈ 0.80.
        let bgId = palette.background
        let probs = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let argm = makeArgmax(width: 100, height: 100) { _, _ in 0 }
        let depth = makeDepthMap(
            width: 100, height: 100, intrinsics: k500,
            depthMm: { _, _ in self.ztMm },
            conf: { _, x in x < 80 ? 255 : 0 }   // first 80 columns: good confidence
        )
        let inputs = HeightFieldEstimator.Inputs(
            probabilities: probs, argmax: argm, depth: depth,
            intrinsics: k500, supportPlane: plane,
            beta: BetaCorrection(), palette: palette
        )
        let result = try HeightFieldEstimator.integrate(inputs)
        let frac = result.lidarCoverageFraction["food_0"] ?? 0
        XCTAssertEqual(frac, 0.80, accuracy: 0.02,
            "Coverage fraction should be ~0.80 (80 of 100 columns have good confidence)")
    }

    // MARK: - T26.4 lidarCoverageTooLow throws when any class below 50%

    func testLidarCoverageTooLowThrows() throws {
        // Only 30% of pixels have sufficient confidence.
        let bgId = palette.background
        let probs = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let argm = makeArgmax(width: 100, height: 100) { _, _ in 0 }
        let depth = makeDepthMap(
            width: 100, height: 100, intrinsics: k500,
            depthMm: { _, _ in self.ztMm },
            conf: { _, x in x < 30 ? 255 : 0 }   // only first 30 columns: good
        )
        let inputs = HeightFieldEstimator.Inputs(
            probabilities: probs, argmax: argm, depth: depth,
            intrinsics: k500, supportPlane: plane,
            beta: BetaCorrection(), palette: palette
        )
        XCTAssertThrowsError(try HeightFieldEstimator.integrate(inputs)) { error in
            if case .lidarCoverageTooLow(let classes) = error as? VolumeError {
                XCTAssertTrue(classes.contains("food_0"))
            } else {
                XCTFail("Expected lidarCoverageTooLow, got \(error)")
            }
        }
    }

    // MARK: - T26.5 mm³→cm³ unit conversion (M5)

    func testVolumeIsInCubicCentimetres() throws {
        // 100×100 pixels × area ≈ 1 mm²/pixel × 100 mm height = 10⁶ mm³ = 1000 cm³.
        // Result must be in cm³ range (~ hundreds), not mm³ range (~ millions).
        let inputs = makeInputs(k: k500)
        let result = try HeightFieldEstimator.integrate(inputs)
        let vol = result.perClassVolumesCm3["food_0"] ?? 0
        XCTAssertGreaterThan(vol, 500,
            "Volume should be > 500 cm³ for 100×100 food pixels (not in mm³)")
        XCTAssertLessThan(vol, 5000,
            "Volume should be < 5000 cm³ (not in mm³ which would be millions)")
    }

    // MARK: - T26.6 noFoodVolumeRecovered when no LiDAR data available

    func testNoFoodVolumeRecoveredWhenZeroDepth() throws {
        // All depth values = 0 → HeightFieldEstimator skips all pixels (zt > 0 guard).
        let bgId = palette.background
        let probs = makeProbTensor(width: 100, height: 100, palette: palette) { _, _, c in
            c == 0 ? 0.90 : (c == bgId ? 0.05 : 0.025)
        }
        let argm = makeArgmax(width: 100, height: 100) { _, _ in 0 }
        // Zero depth everywhere → lidarCoverageTooLow (no covered pixels → 0/N = 0).
        let depth = makeDepthMap(
            width: 100, height: 100, intrinsics: k500,
            depthMm: { _, _ in 0 },
            conf: { _, _ in 255 }
        )
        let inputs = HeightFieldEstimator.Inputs(
            probabilities: probs, argmax: argm, depth: depth,
            intrinsics: k500, supportPlane: plane,
            beta: BetaCorrection(), palette: palette
        )
        // Zero depth means zt == 0 → skipped → zero coveredPixels → coverage = 0 < 0.5.
        XCTAssertThrowsError(try HeightFieldEstimator.integrate(inputs)) { error in
            if case .lidarCoverageTooLow = error as? VolumeError { return }
            XCTFail("Expected lidarCoverageTooLow, got \(error)")
        }
    }
}
