import Foundation
import PortableContracts
import XCTest
@testable import Persistence

// Persistence contract for the retained alternative-class evidence of
// `estimation/alternative-class-candidates` — fields 16/17 on PbMealRecord.
//
// Three things are pinned here and nowhere else:
//  - the member-wise copy sites (the pb bridge in both directions and
//    `withPhotoAssetID`), where a forgotten field drops evidence silently and
//    every other value still looks right (Decision 4);
//  - the Req 4.3 distinction between a record that never carried evidence and
//    one that carried a computed empty set, which is the denominator of the
//    whole acceptance bar;
//  - the Req 4.4 byte budget, measured in the encoding the record is actually
//    stored in (protobuf-JSON, Decision 31) rather than estimated in binary
//    proto.
final class CandidateEvidenceRecordTests: XCTestCase {

    // MARK: - Round trip through protobuf-JSON

    func testEvidenceAndMarkerSurviveTheJSONRoundTrip() throws {
        let original = makeRecordWithEvidence()
        let reloaded = try MealRecord.from(
            jsonString: try original.jsonString(), paletteVersion: "v0"
        )

        XCTAssertTrue(reloaded.candidateEvidenceProduced)
        XCTAssertEqual(reloaded.candidateEvidence.count, 2)
        XCTAssertEqual(reloaded.candidateEvidence["white_rice"]?.classNames,
                       ["brown_rice", "pasta", "lentils"])
        XCTAssertEqual(reloaded.candidateEvidence["white_rice"]?.meanPermille,
                       [412, 233, 90])
        XCTAssertEqual(reloaded.candidateEvidence["chicken"]?.classNames, ["pork"])
        XCTAssertEqual(reloaded.candidateEvidence["chicken"]?.meanPermille, [77])
    }

    // The pb bridge reconstructs member-wise in both directions, so a field it
    // forgets is dropped without any other value changing.
    func testPbBridgeCarriesEvidenceInBothDirections() throws {
        let original = makeRecordWithEvidence()

        let pb = original.pb
        XCTAssertEqual(pb.candidateEvidence, original.candidateEvidence)
        XCTAssertTrue(pb.candidateEvidenceProduced)

        let back = try MealRecord(pb: pb, paletteVersion: "v0")
        XCTAssertEqual(back.candidateEvidence, original.candidateEvidence)
        XCTAssertEqual(back.candidateEvidenceProduced, original.candidateEvidenceProduced)
    }

    // withPhotoAssetID is the same hazard and runs after every capture.
    func testWithPhotoAssetIDPreservesEvidence() throws {
        let original = makeRecordWithEvidence()
        let stamped = original.withPhotoAssetID("PHASSET-ABC-001")

        XCTAssertEqual(stamped.photoAssetID, "PHASSET-ABC-001")
        XCTAssertEqual(stamped.candidateEvidence, original.candidateEvidence)
        XCTAssertTrue(stamped.candidateEvidenceProduced)

        let reloaded = try MealRecord.from(
            jsonString: try stamped.jsonString(), paletteVersion: "v0"
        )
        XCTAssertEqual(reloaded.candidateEvidence, original.candidateEvidence)
        XCTAssertTrue(reloaded.candidateEvidenceProduced)
    }

    // MARK: - Req 4.3: absence is distinguishable from an empty computed set

    // A record written before the spec carries neither field. It must decode
    // with the marker false — not merely with no evidence, which is also what a
    // capture that ran the pass and found nothing produces.
    func testPreSpecRecordDecodesWithTheMarkerFalse() throws {
        let preSpecJSON = """
        {"id":"7C4A8D09-CA37-4A2E-9B15-0E1F9C2B3D44","createdAtMs":"1754870400000",\
        "capturePath":"CAPTURE_PATH_SINGLE_VIEW_LIDAR","databaseEdition":"CoFID 2024",\
        "photoAssetId":"","segmenterSource":"dev_stub"}
        """
        let record = try MealRecord.from(jsonString: preSpecJSON, paletteVersion: "v0")

        XCTAssertFalse(record.candidateEvidenceProduced)
        XCTAssertTrue(record.candidateEvidence.isEmpty)
    }

    func testProducedButEmptyIsDistinguishableFromNeverProduced() throws {
        let ran = try roundTrip(makeRecord(evidence: [:], produced: true))
        let didNotRun = try roundTrip(makeRecord(evidence: [:], produced: false))

        XCTAssertTrue(ran.candidateEvidence.isEmpty)
        XCTAssertTrue(didNotRun.candidateEvidence.isEmpty)
        XCTAssertTrue(ran.candidateEvidenceProduced)
        XCTAssertFalse(didNotRun.candidateEvidenceProduced)
    }

    // MARK: - Reader checks the writer's parallel-array invariant (Decision 10)

    func testUnequalParallelArraysReadAsNoEvidenceForThatClass() throws {
        var malformed = PbCandidateSet()
        malformed.classNames = ["brown_rice", "pasta"]
        malformed.meanPermille = [412]

        var wellFormed = PbCandidateSet()
        wellFormed.classNames = ["pork"]
        wellFormed.meanPermille = [77]

        let record = try MealRecord(
            pb: makeRecord(
                evidence: ["white_rice": malformed, "chicken": wellFormed],
                produced: true
            ).pb,
            paletteVersion: "v0"
        )

        XCTAssertNil(record.candidateEvidence["white_rice"],
                     "a mismatched set reads as no evidence for that class")
        XCTAssertEqual(record.candidateEvidence["chicken"], wellFormed)
        XCTAssertTrue(record.candidateEvidenceProduced,
                      "a malformed set is not a corrupt record — the marker stands")
    }

    // MARK: - Req 4.4: the budget, measured in the persisted encoding

    // Worst case under the Decision 10 caps: five sets, each of five candidates,
    // every name as long as the longest in the shipped palette
    // ("mixed_vegetables", 16 characters) and every magnitude at its four-digit
    // maximum.
    func testWorstCaseEvidenceAddsAtMostOneKilobyteOfJSON() throws {
        let longestName = "mixed_vegetables"
        var worstSet = PbCandidateSet()
        worstSet.classNames = Array(repeating: longestName, count: 5)
        worstSet.meanPermille = Array(repeating: 1000, count: 5)
        let keys = (0..<5).map { String(longestName.dropLast(1)) + String($0) }
        let worstCase = Dictionary(uniqueKeysWithValues: keys.map { ($0, worstSet) })

        let without = try makeRecord(evidence: [:], produced: false).jsonString()
        let with = try makeRecord(evidence: worstCase, produced: true).jsonString()
        let added = Data(with.utf8).count - Data(without.utf8).count

        XCTAssertLessThanOrEqual(added, 1024,
                                 "worst-case evidence added \(added) B of JSON")
    }

    // MARK: - Downgrade is not a supported path

    // SwiftProtobuf's JSON decoding rejects unknown fields, so a build that
    // predates fields 16/17 cannot read a record carrying them. Noted, not
    // designed around: this is a single-device developer-phase app and no reader
    // downgrades. Binary-proto readers (there are none) would be unaffected.
    func testJSONDecodingRejectsUnknownFields() {
        let futureJSON = """
        {"id":"7C4A8D09-CA37-4A2E-9B15-0E1F9C2B3D44",\
        "capturePath":"CAPTURE_PATH_SINGLE_VIEW_LIDAR","aFieldFromLater":true}
        """
        XCTAssertThrowsError(try PbMealRecord(jsonString: futureJSON))
    }
}

// MARK: - Fixtures

private func roundTrip(_ record: MealRecord) throws -> MealRecord {
    try MealRecord.from(jsonString: try record.jsonString(),
                        paletteVersion: record.paletteVersion)
}

private func makeRecordWithEvidence() -> MealRecord {
    var rice = PbCandidateSet()
    rice.classNames = ["brown_rice", "pasta", "lentils"]
    rice.meanPermille = [412, 233, 90]

    var chicken = PbCandidateSet()
    chicken.classNames = ["pork"]
    chicken.meanPermille = [77]

    return makeRecord(evidence: ["white_rice": rice, "chicken": chicken], produced: true)
}

private func makeRecord(
    evidence: [String: PbCandidateSet],
    produced: Bool
) -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.82
    confidence.sigmaScale = 0.90
    confidence.sigmaSeg = 0.85

    var perClassEntry = PbPerClassMacros()
    perClassEntry.volumeCm3 = 100.0
    perClassEntry.massG = 105.0
    perClassEntry.carbsG = 33.6
    perClassEntry.betaUsed = 0.9
    perClassEntry.betaStatus = .calibrated

    var macros = PbMacroResult()
    macros.totalCarbsG = 33.6
    macros.perClass = ["white_rice": perClassEntry]

    var volumes = PbVolumeResult()
    volumes.perClassVolumesCm3 = ["white_rice": 100.0]

    return MealRecord(
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v0",
        segmenterSource: "coreml_v0.1",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: volumes,
        macros: macros,
        confidence: confidence,
        perClassCalibration: ["white_rice": .calibrated],
        candidateEvidence: evidence,
        candidateEvidenceProduced: produced
    )
}
