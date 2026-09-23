import Foundation
import LibreLinkUpKit
import XCTest

@testable import GlucoseIngestion

// Decode-level tests for the LibreLinkUp payload contract
// (docs/agent-notes/librelinkup-api.md): canned JSON fixtures →
// [GlucoseSample]. Deliberately no URLSession stubbing — the client is a
// thin adapter and its network paths are verified on device (project
// minimal-test gate).
//
// The payload types and the graph→reading mapping live in LibreLinkUpKit since
// glucose-lock-widget Decision 16; `samples(from:)` — the reading→GlucoseSample
// step these tests assert — is still GlucoseIngestion's, so the fixtures stay
// here and cover both halves in one pass.
final class LibreLinkUpMappingTests: XCTestCase {

    // MARK: - Login decoding

    func testLoginSuccessDecodes() throws {
        let json = """
            {
              "status": 0,
              "data": {
                "user": { "id": "user-1234" },
                "authTicket": { "token": "jwt-token", "expires": 1795000000, "duration": 15552000000 }
              }
            }
            """
        let response = try JSONDecoder().decode(LLULoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.data?.authTicket?.token, "jwt-token")
        XCTAssertEqual(response.data?.authTicket?.expires, 1_795_000_000)
        XCTAssertEqual(response.data?.user?.id, "user-1234")
        XCTAssertNil(response.data?.redirect)
    }

    func testLoginRedirectVariantDecodes() throws {
        let json = """
            { "status": 0, "data": { "redirect": true, "region": "eu2" } }
            """
        let response = try JSONDecoder().decode(LLULoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.data?.redirect, true)
        XCTAssertEqual(response.data?.region, "eu2")
        XCTAssertNil(response.data?.authTicket)
    }

    func testVersionFloorBodyDecodes() throws {
        // HTTP 403 body: {"data":{"minimumVersion":"…"},"status":920} — all
        // payload fields are optional so the status still decodes.
        let json = """
            { "status": 920, "data": { "minimumVersion": "4.16.0" } }
            """
        let response = try JSONDecoder().decode(LLULoginResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, 920)
    }

    // MARK: - Graph mapping

    func testGraphResponseMapsToSamples() throws {
        let json = """
            {
              "status": 0,
              "data": {
                "connection": {
                  "patientId": "patient-1",
                  "glucoseMeasurement": {
                    "FactoryTimestamp": "7/10/2026 1:10:00 PM",
                    "Timestamp": "7/10/2026 2:10:00 PM",
                    "ValueInMgPerDl": 108,
                    "Value": 6.0,
                    "GlucoseUnits": 0,
                    "TrendArrow": 3,
                    "isHigh": false,
                    "isLow": false
                  }
                },
                "graphData": [
                  {
                    "FactoryTimestamp": "7/10/2026 1:00:00 PM",
                    "Timestamp": "7/10/2026 2:00:00 PM",
                    "ValueInMgPerDl": 100,
                    "Value": 5.5,
                    "GlucoseUnits": 0,
                    "isHigh": false,
                    "isLow": false
                  },
                  {
                    "FactoryTimestamp": "7/10/2026 1:05:00 PM",
                    "Timestamp": "7/10/2026 2:05:00 PM",
                    "ValueInMgPerDl": 104,
                    "Value": 5.8,
                    "GlucoseUnits": 0,
                    "isHigh": false,
                    "isLow": false
                  }
                ]
              }
            }
            """
        let response = try JSONDecoder().decode(LLUGraphResponse.self, from: Data(json.utf8))
        let samples = LibreLinkUpClient.samples(from: response)

        XCTAssertEqual(samples.count, 3, "graphData plus the latest measurement")

        // FactoryTimestamp is UTC "M/d/yyyy h:mm:ss a".
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(samples[0].nativeInstant, iso.date(from: "2026-07-10T13:00:00Z"))
        XCTAssertEqual(samples[2].nativeInstant, iso.date(from: "2026-07-10T13:10:00Z"))

        // ValueInMgPerDl only, converted at 18.0182 (unrounded here — the
        // coordinator holds the single rounding point).
        XCTAssertEqual(samples[0].mmolL, 100 / 18.0182, accuracy: 1e-12)
        XCTAssertEqual(samples[1].mmolL, 104 / 18.0182, accuracy: 1e-12)

        // nativeID is the FactoryTimestamp string (no stable per-reading id).
        XCTAssertEqual(samples[0].nativeID, "7/10/2026 1:00:00 PM")
    }

    func testGraphLatestMeasurementAlsoInGraphDataDedupsOnFactoryTimestamp() throws {
        let json = """
            {
              "status": 0,
              "data": {
                "connection": {
                  "glucoseMeasurement": {
                    "FactoryTimestamp": "7/10/2026 1:00:00 PM",
                    "ValueInMgPerDl": 100
                  }
                },
                "graphData": [
                  { "FactoryTimestamp": "7/10/2026 1:00:00 PM", "ValueInMgPerDl": 100 }
                ]
              }
            }
            """
        let response = try JSONDecoder().decode(LLUGraphResponse.self, from: Data(json.utf8))
        XCTAssertEqual(LibreLinkUpClient.samples(from: response).count, 1)
    }

    func testUnparseableFactoryTimestampIsSkipped() throws {
        let json = """
            {
              "status": 0,
              "data": {
                "graphData": [
                  { "FactoryTimestamp": "not a date", "ValueInMgPerDl": 100 },
                  { "FactoryTimestamp": "7/10/2026 1:00:00 PM", "ValueInMgPerDl": 104 }
                ]
              }
            }
            """
        let response = try JSONDecoder().decode(LLUGraphResponse.self, from: Data(json.utf8))
        let samples = LibreLinkUpClient.samples(from: response)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].nativeID, "7/10/2026 1:00:00 PM")
    }

    // MARK: - account-id header

    func testSha256HexMatchesKnownVector() {
        XCTAssertEqual(
            LibreLinkUpClient.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
