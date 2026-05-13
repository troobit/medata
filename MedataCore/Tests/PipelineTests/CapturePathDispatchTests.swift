import XCTest
import Persistence
import PortableContracts
@testable import Pipeline

// Tests for capture-path dispatch per design §2.3 / Req 3.5, 3.8 (task 49).

final class CapturePathDispatchTests: XCTestCase {

    // MARK: - §2.3 singleViewLidar selection

    func testLidarAndPlaneAndExactly80Coverage_selectsSingleViewLidar() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 80),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .singleViewLidar)
    }

    func testLidarAndPlaneAndAbove80Coverage_selectsSingleViewLidar() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 95.5),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .singleViewLidar)
    }

    func testLidarAndPlaneFull100Coverage_selectsSingleViewLidar() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 100),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .singleViewLidar)
    }

    // MARK: - §2.3 twoViewSfS fallback

    func testLidarUnavailable_selectsTwoViewSfS() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: false, foodRegionCoveragePercent: 95),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .twoViewSfS)
    }

    func testPlaneNotDetected_selectsTwoViewSfS() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 95),
            supportPlane: SupportPlaneCandidate(detected: false)
        )
        XCTAssertEqual(path, .twoViewSfS)
    }

    func testCoverageJustBelow80_selectsTwoViewSfS() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 79.9),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .twoViewSfS)
    }

    func testZeroCoverage_selectsTwoViewSfS() {
        let path = selectCapturePath(
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 0),
            supportPlane: SupportPlaneCandidate(detected: true)
        )
        XCTAssertEqual(path, .twoViewSfS)
    }

    func testAllConditionsFailing_selectsTwoViewSfS() {
        let path = selectCapturePath(
            lidar: .unavailable,
            supportPlane: SupportPlaneCandidate(detected: false)
        )
        XCTAssertEqual(path, .twoViewSfS)
    }

    // MARK: - Req 3.8 — capturePath is persisted on every MealRecord

    func testMealRecordCarriesCapturePathSingleViewLidar() throws {
        let record = makeMealRecord(capturePath: .singleViewLidar)
        XCTAssertEqual(record.capturePath, .singleViewLidar)
        // Verify the value survives a protobuf-JSON roundtrip (Decision 31).
        let json = try record.jsonString()
        let decoded = try MealRecord.from(jsonString: json, paletteVersion: record.paletteVersion)
        XCTAssertEqual(decoded.capturePath, .singleViewLidar)
    }

    func testMealRecordCarriesCapturePathTwoViewSfS() throws {
        let record = makeMealRecord(capturePath: .twoViewSfS)
        XCTAssertEqual(record.capturePath, .twoViewSfS)
        let json = try record.jsonString()
        let decoded = try MealRecord.from(jsonString: json, paletteVersion: record.paletteVersion)
        XCTAssertEqual(decoded.capturePath, .twoViewSfS)
    }

    func testBothCapturePathValuesRoundtrip() throws {
        for path in [CapturePath.singleViewLidar, .twoViewSfS] {
            let record = makeMealRecord(capturePath: path)
            let json = try record.jsonString()
            let decoded = try MealRecord.from(jsonString: json, paletteVersion: record.paletteVersion)
            XCTAssertEqual(decoded.capturePath, path,
                           "capturePath \(path.rawValue) did not survive JSON roundtrip")
        }
    }
}

// MARK: - Fixtures

private func makeMealRecord(capturePath: CapturePath) -> MealRecord {
    var macros = PbMacroResult()
    macros.totalCarbsG = 30
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.80
    return MealRecord(
        capturePath: capturePath,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v1",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}
