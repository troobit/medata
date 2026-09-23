import PortableContracts
import XCTest
@testable import MetricScale

// Task 17: tests for the metric-scale resolver and σ_s per §6.4 / Req 7.
final class MetricScaleResolverTests: XCTestCase {
    // Req 7 case 1: both signals present. σ_s = 0.85 + 0.15·a where a is
    // 1 − |s_lidar−s_card| / ((s_lidar+s_card)/2).
    func testBothSignalsPresentRaisesSigmaWithAgreement() throws {
        // Identical scales → a = 1 → σ_s = 1.0 (clamped at 1).
        let perfect = try MetricScaleResolver.resolve(
            cardScaleMmPerPx: 0.20, lidarScaleMmPerPx: 0.20
        )
        XCTAssertEqual(perfect.sigmaScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(perfect.metresPerVoxelEdgeMm, 0.20)
        XCTAssertTrue(perfect.cardScaleAvailable && perfect.lidarScaleAvailable)

        // 5% disagreement → a = 0.95 → σ_s = 0.85 + 0.15·0.95 = 0.9925.
        let close = try MetricScaleResolver.resolve(
            cardScaleMmPerPx: 0.20, lidarScaleMmPerPx: 0.21
        )
        XCTAssertEqual(close.sigmaScale, 0.85 + 0.15 * (1 - 0.01 / 0.205), accuracy: 1e-5)

        // Maximum disagreement (>100% relative) → a = 0 → σ_s = 0.85.
        let far = try MetricScaleResolver.resolve(
            cardScaleMmPerPx: 0.10, lidarScaleMmPerPx: 1.0
        )
        XCTAssertEqual(far.sigmaScale, 0.85, accuracy: 1e-6)
    }

    // M4 fix: swapping inputs gives identical σ_s (symmetric agreement formula).
    func testSymmetricAgreementInvariantUnderInputSwap() throws {
        let a = try MetricScaleResolver.resolve(cardScaleMmPerPx: 0.20, lidarScaleMmPerPx: 0.30)
        let b = try MetricScaleResolver.resolve(cardScaleMmPerPx: 0.30, lidarScaleMmPerPx: 0.20)
        XCTAssertEqual(a.sigmaScale, b.sigmaScale, accuracy: 1e-7)
    }

    // Req 7 case 2: LiDAR only.
    func testLidarOnlyReportsSigmaPointEightFiveAndNoCardFlag() throws {
        let m = try MetricScaleResolver.resolve(
            cardScaleMmPerPx: nil, lidarScaleMmPerPx: 0.18
        )
        XCTAssertEqual(m.sigmaScale, 0.85, accuracy: 1e-7)
        XCTAssertEqual(m.metresPerVoxelEdgeMm, 0.18)
        XCTAssertFalse(m.cardScaleAvailable)
        XCTAssertTrue(m.lidarScaleAvailable)
    }

    // Req 7 case 3: card only.
    func testCardOnlyReportsSigmaPointEightFiveAndNoLidarFlag() throws {
        let m = try MetricScaleResolver.resolve(
            cardScaleMmPerPx: 0.22, lidarScaleMmPerPx: nil
        )
        XCTAssertEqual(m.sigmaScale, 0.85, accuracy: 1e-7)
        XCTAssertEqual(m.metresPerVoxelEdgeMm, 0.22)
        XCTAssertTrue(m.cardScaleAvailable)
        XCTAssertFalse(m.lidarScaleAvailable)
    }

    // Req 7 case 4: neither signal → noScaleAvailable.
    func testNoSignalsThrowsNoScaleAvailable() {
        XCTAssertThrowsError(try MetricScaleResolver.resolve(
            cardScaleMmPerPx: nil, lidarScaleMmPerPx: nil
        )) { err in
            XCTAssertEqual(err as? MetricScaleError, .noScaleAvailable)
        }
    }

    // §6.4 unit consistency: LiDARScaleAdapter converts m/px → mm/px (×1000).
    func testLidarScaleAdapterConvertsMetresToMillimetres() {
        XCTAssertEqual(LiDARScaleAdapter.mmPerPx(fromMetresPerPx: 0.0002), 0.2, accuracy: 1e-6)
        XCTAssertEqual(LiDARScaleAdapter.mmPerPx(fromMetresPerPx: 1), 1000, accuracy: 1e-6)
    }

    // σ_s lives in [ε, 1] always (Req 7 + Req 13.1 floor).
    func testSigmaScaleClampsToFloorAndCeiling() throws {
        // The formula 0.85 + 0.15·a sits in [0.85, 1.0] when a ∈ [0,1] so the floor
        // never bites here. We assert the clamp is robust to input noise by checking
        // the two extremes plus a midpoint.
        let one = try MetricScaleResolver.resolve(cardScaleMmPerPx: 1, lidarScaleMmPerPx: 1)
        let mid = try MetricScaleResolver.resolve(cardScaleMmPerPx: 1, lidarScaleMmPerPx: 1.5)
        let zero = try MetricScaleResolver.resolve(cardScaleMmPerPx: 0.01, lidarScaleMmPerPx: 100)
        XCTAssertGreaterThanOrEqual(one.sigmaScale, MetricScaleResolver.sigmaFloor)
        XCTAssertLessThanOrEqual(one.sigmaScale, 1)
        XCTAssertGreaterThanOrEqual(mid.sigmaScale, MetricScaleResolver.sigmaFloor)
        XCTAssertLessThanOrEqual(mid.sigmaScale, 1)
        XCTAssertGreaterThanOrEqual(zero.sigmaScale, MetricScaleResolver.sigmaFloor)
        XCTAssertLessThanOrEqual(zero.sigmaScale, 1)
    }
}
