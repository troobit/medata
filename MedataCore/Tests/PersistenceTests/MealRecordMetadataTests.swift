import Foundation
import PortableContracts
import XCTest
@testable import Persistence

// Tests for MealRecord.metadataJSON() / from(metadata:) per spec
// `specs/data/event-log-schema/design.md` "MealRecord ↔ event metadata".
//
// The metadata blob is an outer JSON object with exactly two keys:
//   - "record"          → a JSON string holding the protobuf-JSON of PbMealRecord
//                         (byte-identical to SwiftProtobuf output — Decision 31).
//   - "palette_version" → a JSON string equal to MealRecord.paletteVersion.

final class MealRecordMetadataTests: XCTestCase {

    // MARK: - Round-trip preserves every field

    func testRoundTripPreservesEveryField() throws {
        let original = makeMealRecord()
        let metadata = try original.metadataJSON()
        let reloaded = try MealRecord.from(metadata: metadata)

        XCTAssertEqual(reloaded.id, original.id)
        XCTAssertEqual(reloaded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970,
                       accuracy: 1e-3)
        XCTAssertEqual(reloaded.capturePath, original.capturePath)
        XCTAssertEqual(reloaded.databaseEdition, original.databaseEdition)
        XCTAssertEqual(reloaded.paletteVersion, original.paletteVersion)
        XCTAssertEqual(reloaded.photoAssetID, original.photoAssetID)
        XCTAssertEqual(reloaded.segmenterSource, original.segmenterSource)
        XCTAssertEqual(reloaded.macros.totalCarbsG, original.macros.totalCarbsG, accuracy: 1e-4)
        XCTAssertEqual(reloaded.confidence.sigmaMeal, original.confidence.sigmaMeal, accuracy: 1e-6)
        XCTAssertEqual(reloaded.perClassCalibration, original.perClassCalibration)
    }

    // MARK: - Inner `record` string is byte-identical to pb.jsonString()
    //
    // Decision 31 invariant: the protobuf-JSON survives byte-identical round-trip
    // through JSONSerialization because it is held as a JSON string value, not
    // a parsed-and-re-emitted object.

    func testInnerRecordStringIsByteIdenticalToProtobufJSON() throws {
        let original = makeMealRecord()
        let expectedRecord = try original.pb.jsonString()
        let metadata = try original.metadataJSON()

        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        let actualRecord = try XCTUnwrap(parsed["record"] as? String)

        XCTAssertEqual(Data(actualRecord.utf8), Data(expectedRecord.utf8),
                       "inner `record` string must be byte-identical to pb.jsonString()")
    }

    // MARK: - palette_version round-trips

    func testPaletteVersionIsCarriedInOuterObject() throws {
        let original = makeMealRecord(paletteVersion: "v42")
        let metadata = try original.metadataJSON()
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        )
        let palette = try XCTUnwrap(parsed["palette_version"] as? String)
        XCTAssertEqual(palette, "v42")
    }

    // MARK: - Malformed outer JSON throws corruptRecord

    func testMalformedOuterJSONThrowsCorruptRecord() {
        let garbage = "{not-json"
        XCTAssertThrowsError(try MealRecord.from(metadata: garbage)) { error in
            guard case PersistenceError.corruptRecord = error else {
                return XCTFail("Expected corruptRecord, got \(error)")
            }
        }
    }

    // MARK: - Missing `record` key throws corruptRecord

    func testMissingRecordKeyThrowsCorruptRecord() {
        let metadata = #"{"palette_version":"v0"}"#
        XCTAssertThrowsError(try MealRecord.from(metadata: metadata)) { error in
            guard case PersistenceError.corruptRecord = error else {
                return XCTFail("Expected corruptRecord, got \(error)")
            }
        }
    }

    // MARK: - Missing `palette_version` key throws corruptRecord

    func testMissingPaletteVersionKeyThrowsCorruptRecord() throws {
        let pbJson = try makeMealRecord().pb.jsonString()
        // Build an outer object that only carries the `record` key.
        let outer = try JSONSerialization.data(withJSONObject: ["record": pbJson])
        let metadata = String(decoding: outer, as: UTF8.self)
        XCTAssertThrowsError(try MealRecord.from(metadata: metadata)) { error in
            guard case PersistenceError.corruptRecord = error else {
                return XCTFail("Expected corruptRecord, got \(error)")
            }
        }
    }

    // MARK: - Wrong-typed `record` value (number instead of string) throws

    func testWrongTypedRecordValueThrowsCorruptRecord() throws {
        let outer: [String: Any] = ["record": 123, "palette_version": "v0"]
        let data = try JSONSerialization.data(withJSONObject: outer)
        let metadata = String(decoding: data, as: UTF8.self)
        XCTAssertThrowsError(try MealRecord.from(metadata: metadata)) { error in
            guard case PersistenceError.corruptRecord = error else {
                return XCTFail("Expected corruptRecord, got \(error)")
            }
        }
    }
}

// MARK: - Fixture

private func makeMealRecord(
    paletteVersion: String = "v0",
    photoAssetID: String = "PHASSET-ABC-001",
    segmenterSource: String = "dev_stub"
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
        paletteVersion: paletteVersion,
        photoAssetID: photoAssetID,
        segmenterSource: segmenterSource,
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: volumes,
        macros: macros,
        confidence: confidence,
        perClassCalibration: ["white_rice": .calibrated]
    )
}
