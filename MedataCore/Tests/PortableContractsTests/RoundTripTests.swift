import Foundation
import SwiftProtobuf
import XCTest
@testable import PortableContracts

// Round-trip every top-level portable contract message: encode → decode → bit-equal.
// Per design §4.3 and Decision 31, the protobuf binary encoding is the canonical contract.
final class ProtoBinaryRoundTripTests: XCTestCase {
    func testVec3BinaryRoundTrip() throws {
        var v = PbVec3()
        v.x = 1.5
        v.y = -2.25
        v.z = 0
        let bytes = try v.serializedData()
        let decoded = try PbVec3(serializedBytes: bytes)
        XCTAssertEqual(v, decoded)
    }

    func testMat4BinaryRoundTrip() throws {
        var m = PbMat4()
        m.m = (0..<16).map { Float($0) * 0.5 }
        let bytes = try m.serializedData()
        let decoded = try PbMat4(serializedBytes: bytes)
        XCTAssertEqual(m, decoded)
        XCTAssertEqual(decoded.m.count, 16)
    }

    func testRawFrameBinaryRoundTrip() throws {
        var f = PbRawFrame()
        f.imageBytes = Data([0xAA, 0xBB, 0xCC, 0xDD])
        f.pixelFormat = .rgb8
        f.colourSpace = .srgb
        f.orientation = 1
        f.imageWidth = 4032
        f.imageHeight = 3024
        f.timestampMonotonicNs = 123_456_789_000
        var k = PbCameraIntrinsics()
        k.fx = 1500
        k.fy = 1500
        k.cx = 2016
        k.cy = 1512
        k.imageWidth = 4032
        k.imageHeight = 3024
        f.intrinsics = k
        var g = PbVec3()
        g.x = 0
        g.y = -1
        g.z = 0
        f.gravity = g
        var t = PbMat4()
        t.m = (0..<16).map { Float($0) }
        f.worldFromCamera = t
        let bytes = try f.serializedData()
        let decoded = try PbRawFrame(serializedBytes: bytes)
        XCTAssertEqual(f, decoded)
    }

    func testProbabilityTensorBinaryRoundTrip() throws {
        var p = PbProbabilityTensor()
        p.height = 8
        p.width = 8
        p.classes = 27
        p.bytes = Data(repeating: 0xFF, count: 8 * 8 * 27 * 2)
        var palette = PbClassPalette()
        palette.foodClasses = ["rice", "chips"]
        palette.background = 0
        palette.unknownFood = 25
        palette.unsupportedLiquid = 26
        palette.version = "v0"
        p.palette = palette
        let bytes = try p.serializedData()
        let decoded = try PbProbabilityTensor(serializedBytes: bytes)
        XCTAssertEqual(p, decoded)
    }

    func testMealRecordBinaryRoundTrip() throws {
        var record = PbMealRecord()
        record.id = "11111111-2222-3333-4444-555555555555"
        record.createdAtMs = 1_700_000_000_000
        record.capturePath = .singleViewLidar
        record.databaseEdition = "CoFID 2024 + IFCDB 2023"
        var perClassMacros = PbPerClassMacros()
        perClassMacros.volumeCm3 = 120
        perClassMacros.massG = 80
        perClassMacros.carbsG = 22
        perClassMacros.densitySource = "CoFID 2024"
        perClassMacros.coefficientSource = "CoFID 2024"
        perClassMacros.betaUsed = 0.92
        perClassMacros.betaStatus = .calibrated
        var macroResult = PbMacroResult()
        macroResult.totalCarbsG = 22
        macroResult.perClass = ["rice": perClassMacros]
        record.macros = macroResult
        let bytes = try record.serializedData()
        let decoded = try PbMealRecord(serializedBytes: bytes)
        XCTAssertEqual(record, decoded)
    }

    func testMealFixtureBinaryRoundTrip() throws {
        var fixture = PbMealFixture()
        fixture.fixtureID = "fx-0001"
        fixture.fixtureRevision = "rev-1"
        fixture.paletteVersion = "v0"
        fixture.databaseEdition = "CoFID 2024 + IFCDB 2023"
        fixture.segmenterCheckpointSha256 =
            "0000000000000000000000000000000000000000000000000000000000000000"
        fixture.nadirImage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        fixture.nadirProbs = Data(count: 4 * 4 * 27 * 2)
        fixture.nadirArgmax = Data(count: 4 * 4)
        fixture.groundTruthClassMassG = ["rice": 80, "chicken_breast": 100]
        fixture.groundTruthTotalCarbsG = 22
        fixture.capturePathCanonical = "single_view_lidar"
        let bytes = try fixture.serializedData()
        let decoded = try PbMealFixture(serializedBytes: bytes)
        XCTAssertEqual(fixture, decoded)
    }
}

// Verify protobuf-JSON encoding is deterministic per Decision 31:
// camelCase keys, RFC 7159 stable ordering. Encoding the same message twice
// must produce byte-identical JSON.
final class ProtoJsonDeterminismTests: XCTestCase {
    func testDeterministicJsonEncoding() throws {
        var record = PbMealRecord()
        record.id = "abcdefab-1234-5678-9abc-deadbeef0000"
        record.createdAtMs = 1_700_000_000_000
        record.capturePath = .twoViewSfs
        record.databaseEdition = "CoFID 2024"
        var subc = PbGeomSubconfidences()
        subc.sigmaView = 0.95
        subc.sigmaPlane = 0.91
        subc.sigmaOccl = 1.0
        var conf = PbConfidenceResult()
        conf.sigmaMeal = 0.78
        conf.sigmaScale = 0.92
        conf.sigmaSeg = 0.88
        conf.sigmaGeom = subc
        record.confidence = conf

        let json1 = try record.jsonString()
        let json2 = try record.jsonString()
        XCTAssertEqual(json1, json2, "protobuf-JSON must be deterministic per Decision 31")

        // camelCase: createdAtMs, not created_at_ms.
        XCTAssertTrue(json1.contains("\"createdAtMs\""),
                      "expected camelCase key 'createdAtMs'; got: \(json1)")
        XCTAssertFalse(json1.contains("created_at_ms"),
                       "snake_case key must not appear in protobuf-JSON")
    }

    func testJsonRoundTripIsBitEqual() throws {
        var v = PbVec3()
        v.x = 0.125
        v.y = -0.5
        v.z = 1.0
        let json = try v.jsonString()
        let decoded = try PbVec3(jsonString: json)
        XCTAssertEqual(v, decoded)
    }
}
