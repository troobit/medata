import Foundation
import Volume
import XCTest
@testable import Pipeline

// Tests for the EstimationAttemptRecord snapshot type and the
// PipelineDiagnostics accumulator (snaq-parity tasks 3–4, Req 2.1/2.6/3.3/3.4).
// The record is the JSON payload persisted in the estimation_outcomes
// `measurements` column: Codable + Sendable, schema-versioned via `v`, no raw
// imagery, failure encoded as {domain, case, payload}.

final class EstimationAttemptRecordTests: XCTestCase {

    // MARK: - fixtures

    func makeSuccessRecord() -> EstimationAttemptRecord {
        EstimationAttemptRecord(
            v: EstimationAttemptRecord.currentSchemaVersion,
            timestampMs: 1_752_700_000_123,
            outcome: .success,
            failure: nil,
            modelVersion: "coreml_24e0b022241a",
            mealID: "5D3B0000-0000-0000-0000-000000000001",
            capturePath: "single_view_lidar",
            nadirTiltDeg: 2.5,
            obliqueTiltDeg: nil,
            scaleSource: "lidar",
            cardFallback: false,
            planeCandidateCount: 1200,
            planeInlierCount: 940,
            planeResidualMm: 3.2,
            foodRegionCoveragePercent: 84.5,
            segmentationNadir: .init(
                foodCoveragePercent: 41,
                preprocessMs: 12, predictionMs: 96, argmaxMs: 44
            ),
            segmentationOblique: nil,
            volume: .init(
                perClassVolumesPreBetaCm3: ["white_rice": 210.4],
                perClassVolumesPostBetaCm3: ["white_rice": 168.3],
                betaApplied: ["white_rice": 0.8],
                thresholdDiscardedClasses: [],
                degenerateVoxelSkipCount: 0,
                degenerateRaySkipCount: 3,
                lidarCoverageFraction: ["white_rice": 0.92]
            ),
            preShutterSegmentationErrorCount: 1,
            decomposition: [
                .init(className: "white_rice", volumeCm3: 168.3, massG: 220.1,
                      carbsG: 62.4, beta: 0.8,
                      densitySource: "cofid:13-456", coefficientSource: "cofid:13-456")
            ],
            sigma: .init(sigmaMeal: 0.62, sigmaScale: 0.85, sigmaSeg: 0.71,
                         sigmaPlane: 0.53, sigmaView: 0.9, sigmaTilt: 0.99)
        )
    }

    func makeRefusalRecord() -> EstimationAttemptRecord {
        EstimationAttemptRecord(
            v: EstimationAttemptRecord.currentSchemaVersion,
            timestampMs: 1_752_700_100_456,
            outcome: .refused,
            failure: .init(estimation: .lidarCoverageTooLow(["chips", "white_rice"])),
            modelVersion: "coreml_24e0b022241a",
            mealID: nil,
            capturePath: "two_view_sfs",
            nadirTiltDeg: 1.0,
            obliqueTiltDeg: 26.5,
            scaleSource: "lidar",
            cardFallback: true,
            planeCandidateCount: 300,
            planeInlierCount: 41,
            planeResidualMm: 11.6,
            foodRegionCoveragePercent: 22.0,
            segmentationNadir: .init(
                foodCoveragePercent: 18,
                preprocessMs: 11, predictionMs: 101, argmaxMs: 47
            ),
            segmentationOblique: .init(
                foodCoveragePercent: 15,
                preprocessMs: 12, predictionMs: 99, argmaxMs: 45
            ),
            volume: .init(
                perClassVolumesPreBetaCm3: ["chips": 0.4],
                perClassVolumesPostBetaCm3: ["chips": 0.3],
                betaApplied: ["chips": 0.75],
                thresholdDiscardedClasses: ["chips"],
                degenerateVoxelSkipCount: 87,
                degenerateRaySkipCount: 12,
                lidarCoverageFraction: ["chips": 0.21]
            ),
            preShutterSegmentationErrorCount: 0,
            decomposition: nil,
            sigma: nil
        )
    }

    // MARK: - JSON round-trip (Req 2.1)

    func testSuccessRecordRoundTripsThroughJSON() throws {
        let record = makeSuccessRecord()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(EstimationAttemptRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testRefusalRecordRoundTripsThroughJSON() throws {
        let record = makeRefusalRecord()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(EstimationAttemptRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    // MARK: - schema version field

    func testSchemaVersionFieldIsEncodedAsV() throws {
        let data = try JSONEncoder().encode(makeSuccessRecord())
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["v"] as? Int, EstimationAttemptRecord.currentSchemaVersion)
    }

    // The browser must tolerate older rows: a minimal record (only the fields
    // an early schema version guaranteed) decodes without error.
    func testMinimalOlderRowDecodes() throws {
        let json = """
        {"v": 1, "timestampMs": 1700000000000, "outcome": "refused",
         "failure": {"domain": "estimation", "case": "noFoodVolumeRecovered"},
         "modelVersion": "dev_stub", "capturePath": "single_view_lidar"}
        """
        let record = try JSONDecoder().decode(
            EstimationAttemptRecord.self, from: Data(json.utf8)
        )
        XCTAssertEqual(record.v, 1)
        XCTAssertEqual(record.outcome, .refused)
        XCTAssertEqual(record.failure?.caseName, "noFoodVolumeRecovered")
        XCTAssertNil(record.volume)
        XCTAssertNil(record.mealID)
    }

    // Future rows with unknown keys must not break this decoder either.
    func testUnknownKeysAreTolerated() throws {
        let data = try JSONEncoder().encode(makeRefusalRecord())
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["someFutureField"] = "ignored"
        let mutated = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNoThrow(try JSONDecoder().decode(EstimationAttemptRecord.self, from: mutated))
    }

    // MARK: - failure encoding {domain, case, payload} (Req 3.3)

    func testFailureEncodesDomainCasePayloadKeys() throws {
        let data = try JSONEncoder().encode(makeRefusalRecord())
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let failure = try XCTUnwrap(object["failure"] as? [String: Any])
        XCTAssertEqual(failure["domain"] as? String, "estimation")
        XCTAssertEqual(failure["case"] as? String, "lidarCoverageTooLow")
        XCTAssertNotNil(failure["payload"])
    }

    func testFailureInfoFromEstimationFailureAssociatedValues() {
        let coverage = EstimationAttemptRecord.FailureInfo(
            estimation: .lidarCoverageTooLow(["chips", "white_rice"])
        )
        XCTAssertEqual(coverage.domain, "estimation")
        XCTAssertEqual(coverage.caseName, "lidarCoverageTooLow")
        XCTAssertEqual(coverage.payload, "chips, white_rice")

        let internalError = EstimationAttemptRecord.FailureInfo(
            estimation: .internalError("PixelBufferError")
        )
        XCTAssertEqual(internalError.caseName, "internalError")
        XCTAssertEqual(internalError.payload, "PixelBufferError")

        let plain = EstimationAttemptRecord.FailureInfo(estimation: .noFoodVolumeRecovered)
        XCTAssertEqual(plain.caseName, "noFoodVolumeRecovered")
        XCTAssertNil(plain.payload)
    }

    // MARK: - content rule: derived measurements only, no raw imagery (Req 2.6)

    func testEncodedRecordStaysCompact() throws {
        // The record carries derived measurements and references — never pixel
        // buffers. A fully populated record must stay well under 10 KB.
        let data = try JSONEncoder().encode(makeSuccessRecord())
        XCTAssertLessThan(data.count, 10_240)
    }

    // MARK: - PipelineDiagnostics accumulator → snapshot (task 4)

    func testDiagnosticsSnapshotCarriesStampedFailure() {
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "coreml_24e0b022241a",
            timestampMs: 1_752_700_000_000
        )
        diagnostics.recordTilt(nadirDeg: 2.0, obliqueDeg: nil)
        diagnostics.recordScale(source: "lidar", cardFallback: false)
        diagnostics.recordSupportPlane(candidateCount: 900, inlierCount: 700, residualMm: 2.9)
        diagnostics.recordVolume(stats: VolumeStats(
            perClassVolumesPreBetaCm3: ["chips": 0.4],
            perClassVolumesPostBetaCm3: ["chips": 0.3],
            betaApplied: ["chips": 0.75],
            thresholdDiscardedClasses: ["chips"],
            degenerateVoxelSkipCount: 5,
            degenerateRaySkipCount: 2,
            lidarCoverageFraction: ["chips": 0.4]
        ))
        diagnostics.stampFailure(.noFoodVolumeRecovered)

        let record = diagnostics.snapshot()
        XCTAssertEqual(record.outcome, .refused)
        XCTAssertEqual(record.failure?.domain, "estimation")
        XCTAssertEqual(record.failure?.caseName, "noFoodVolumeRecovered")
        XCTAssertEqual(record.volume?.perClassVolumesPreBetaCm3["chips"], 0.4)
        XCTAssertEqual(record.volume?.thresholdDiscardedClasses, ["chips"])
        XCTAssertEqual(record.volume?.degenerateVoxelSkipCount, 5)
        XCTAssertEqual(record.planeInlierCount, 700)
        XCTAssertNil(record.mealID)
    }

    // A non-typed error must preserve the underlying description in the
    // record — not just the Swift type name (Req 3.3).
    func testDiagnosticsSnapshotPreservesUnderlyingErrorDescription() {
        struct ObscureError: Error, CustomStringConvertible {
            var description: String { "mask buffer stride mismatch (rows=7)" }
        }
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "dev_stub",
            timestampMs: 0
        )
        diagnostics.stampError(ObscureError())
        let record = diagnostics.snapshot()
        XCTAssertEqual(record.outcome, .refused)
        XCTAssertEqual(record.failure?.caseName, "internalError")
        XCTAssertEqual(record.failure?.payload, "mask buffer stride mismatch (rows=7)")
    }

    func testDiagnosticsSnapshotSuccessEmbedsDecomposition() {
        let diagnostics = PipelineDiagnostics(
            capturePath: "single_view_lidar",
            modelVersion: "coreml_24e0b022241a",
            timestampMs: 1
        )
        diagnostics.stampSuccess(
            mealID: "ABC",
            decomposition: [
                .init(className: "white_rice", volumeCm3: 168.3, massG: 220.1,
                      carbsG: 62.4, beta: 0.8,
                      densitySource: "cofid:13-456", coefficientSource: "cofid:13-456")
            ],
            sigma: .init(sigmaMeal: 0.62, sigmaScale: 0.85, sigmaSeg: 0.71,
                         sigmaPlane: 0.53, sigmaView: 0.9, sigmaTilt: 0.99)
        )
        let record = diagnostics.snapshot()
        XCTAssertEqual(record.outcome, .success)
        XCTAssertEqual(record.mealID, "ABC")
        XCTAssertNil(record.failure)
        XCTAssertEqual(record.decomposition?.first?.carbsG, 62.4)
        XCTAssertEqual(record.sigma?.sigmaMeal, 0.62)
    }

    // Merged in by CaptureFlowModel at persist time — the count never crosses
    // CaptureResult (design lane A, pre-shutter row).
    func testWithPreShutterErrorCountProducesUpdatedCopy() {
        let record = makeSuccessRecord()
        let updated = record.withPreShutterSegmentationErrorCount(7)
        XCTAssertEqual(updated.preShutterSegmentationErrorCount, 7)
        XCTAssertEqual(record.preShutterSegmentationErrorCount, 1,
            "the snapshot is immutable — merging returns a copy")
        XCTAssertEqual(updated.mealID, record.mealID)
        XCTAssertEqual(updated.volume, record.volume)
    }
}
