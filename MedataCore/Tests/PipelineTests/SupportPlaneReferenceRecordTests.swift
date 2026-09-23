import Foundation
import SupportPlane
import XCTest
@testable import Pipeline

// Task 11: the diagnostic fields `specs/estimation/support-plane-reference/`
// persists per attempt (Reqs 6.1–6.4).
//
// The distinction these fields exist to provide is destroyed by a default: a
// pre-feature row and a row whose fit recorded nothing must stay tellable apart,
// so every field is optional AND absent from the encoded JSON when unset (Req 6.3).
final class SupportPlaneReferenceRecordTests: XCTestCase {

    // MARK: - Req 6.3: absent, not defaulted

    func testPreFeatureRowDecodesWithTheNewFieldsAbsent() throws {
        let json = """
        {"v": 1, "timestampMs": 1700000000000, "outcome": "success",
         "modelVersion": "dev_stub", "capturePath": "single_view_lidar",
         "planeCandidateCount": 1200, "planeInlierCount": 940, "planeResidualMm": 3.2}
        """
        let record = try JSONDecoder().decode(
            EstimationAttemptRecord.self, from: Data(json.utf8)
        )
        XCTAssertNil(record.planeReference)
        XCTAssertNil(record.planeRingMedianMm)
        XCTAssertNil(record.planeRingBandMediansMm)
        XCTAssertNil(record.planeCandidatePlaneCount)
        XCTAssertNil(record.planeSupportingSectors)
        // The pre-feature point/inlier counts still decode — the new fields sit
        // alongside them rather than replacing them.
        XCTAssertEqual(record.planeCandidateCount, 1200)
        XCTAssertEqual(record.planeInlierCount, 940)
    }

    func testUnsetFieldsAreOmittedFromTheEncodedRow() throws {
        let diagnostics = PipelineDiagnostics(
            capturePath: "two_view_sfs",
            modelVersion: "dev_stub",
            timestampMs: 1_752_700_000_000
        )
        // The card-only path has no depth map, so no reference exists to record.
        diagnostics.recordSupportPlane(candidateCount: 12, inlierCount: 9, residualMm: 1.5)
        let data = try JSONEncoder().encode(diagnostics.snapshot())
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["planeReference"])
        XCTAssertNil(object["planeRingMedianMm"])
        XCTAssertNil(object["planeRingBandMediansMm"])
        XCTAssertNil(object["planeCandidatePlaneCount"])
        XCTAssertNil(object["planeSupportingSectors"])
    }

    // MARK: - Reqs 6.1, 6.4: the restricted path

    func testFoodSupportAttemptPersistsTheReferenceAndTheRingMeasure() throws {
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "dev_stub",
            timestampMs: 1_752_700_000_000
        )
        diagnostics.recordSupportPlane(
            candidateCount: 4_200, inlierCount: 3_100, residualMm: 1.8,
            reference: .foodSupport,
            ring: Self.ring(medianMm: 0.4, bandMedians: [0.3, 0.5, 0.6], supportingSectors: 8),
            candidatePlaneCount: 2
        )
        let record = diagnostics.snapshot()
        XCTAssertEqual(record.planeReference, "foodSupport")
        XCTAssertEqual(record.planeRingMedianMm, 0.4)
        XCTAssertEqual(record.planeRingBandMediansMm, [0.3, 0.5, 0.6])
        XCTAssertEqual(record.planeSupportingSectors, 8)
        XCTAssertEqual(record.planeCandidatePlaneCount, 2)

        let decoded = try JSONDecoder().decode(
            EstimationAttemptRecord.self, from: try JSONEncoder().encode(record)
        )
        XCTAssertEqual(decoded, record)
    }

    // MARK: - Req 6.2: the fallback path records the ring too

    // Without this the before/after comparison of Req 6.2 has no "before" to read:
    // the pre-feature fit is exactly what the fallback runs.
    func testFallbackAttemptPersistsTheRingMeasureAndTheSectorCount() {
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "dev_stub",
            timestampMs: 1_752_700_000_000
        )
        diagnostics.recordSupportPlane(
            candidateCount: 240_000, inlierCount: 180_000, residualMm: 2.6,
            reference: .edgeBand,
            ring: Self.ring(medianMm: 21.7, bandMedians: [21.4, 21.8, 22.1],
                            supportingSectors: 3),
            candidatePlaneCount: nil
        )
        let record = diagnostics.snapshot()
        XCTAssertEqual(record.planeReference, "edgeBand")
        XCTAssertEqual(record.planeRingMedianMm, 21.7)
        // Req 6.4: the radial profile is what identifies a rim-borne ring after the
        // fact, and the sector count is what separates a correct fit from a ring
        // that crossed the plate edge — both read ~0 on the median alone.
        XCTAssertEqual(record.planeRingBandMediansMm, [21.4, 21.8, 22.1])
        XCTAssertEqual(record.planeSupportingSectors, 3)
        // No candidate set was selected from on this path.
        XCTAssertNil(record.planeCandidatePlaneCount)
    }

    // MARK: - Req 3.5 needs no new field

    func testMaskCoverageLandsOnTheSameRowAsTheReference() {
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "dev_stub",
            timestampMs: 1_752_700_000_000
        )
        diagnostics.recordSupportPlane(
            candidateCount: 4_200, inlierCount: 3_100, residualMm: 1.8,
            reference: .foodSupport,
            ring: Self.ring(medianMm: 0.1, bandMedians: [0, 0.1, 0.2], supportingSectors: 7),
            candidatePlaneCount: 3
        )
        diagnostics.recordFoodRegionCoverage(percent: 84.5)
        let record = diagnostics.snapshot()
        XCTAssertEqual(record.foodRegionCoveragePercent, 84.5)
        XCTAssertEqual(record.planeReference, "foodSupport")
    }

    // MARK: - helpers

    private static func ring(medianMm: Float, bandMedians: [Float],
                             supportingSectors: Int) -> RingStatistics {
        RingStatistics(
            medianMm: medianMm,
            bandMedianMm: bandMedians,
            supportFraction: 0.9,
            supportingSectors: supportingSectors,
            bandSampleCount: [420, 640, 880],
            supportVisibility: 0.4
        )
    }
}
