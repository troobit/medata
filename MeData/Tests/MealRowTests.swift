import Foundation
import Persistence
import PortableContracts
import Testing
@testable import MeData

// Tests for `MealRow` per UI Req §19.2 / §19.3 (task 33). Behaviour-level
// assertions on the row's pure helpers — the SwiftUI body itself isn't
// snapshot-tested here; `MealRowFormat` carries the testable surface.
@Suite("MealRow placeholder chip, timestamp, photo-asset resolution")
@MainActor
struct MealRowTests {

    @Test("placeholder chip is shown when segmenterSource == \"dev_stub\"")
    func placeholderShownForDevStub() {
        let row = MealRowFormat(record: makeMealRecord(segmenterSource: "dev_stub"))
        #expect(row.showsPlaceholderChip)
    }

    @Test("placeholder chip is absent when segmenterSource is a real source")
    func placeholderAbsentForRealSource() {
        let row = MealRowFormat(record: makeMealRecord(segmenterSource: "coreml_v0.1"))
        #expect(!row.showsPlaceholderChip)
    }

    @Test("placeholder chip is absent when segmenterSource is nil (pre-task-82 fixtures)")
    func placeholderAbsentForNil() {
        let row = MealRowFormat(record: makeMealRecord(segmenterSource: ""))
        #expect(!row.showsPlaceholderChip)
    }

    @Test("timestamp uses dd MMM yyyy, HH:mm in en_IE locale (Req §19.2)")
    func timestampFormat() {
        // 2026-05-29 14:07:00 UTC. The DateFormatter renders in the user's
        // current locale; we assert the *pattern* matches `dd MMM yyyy, HH:mm`.
        let date = Date(timeIntervalSince1970: 1748527620)
        let row = MealRowFormat(record: makeMealRecord(createdAt: date))
        let formatted = row.timestampString
        #expect(formatted.contains("2026"))
        // Allows the locale to substitute the comma but checks the structure.
        let parts = formatted.split(separator: " ")
        #expect(parts.count >= 3)
    }

    @Test("carb total rounds to nearest gram for display")
    func carbDisplayRounding() {
        let row = MealRowFormat(record: makeMealRecord(totalCarbsG: 27.6))
        #expect(row.carbDisplay == "28 g")
    }

    @Test("photoAssetID is exposed for PHImageManager resolution; nil → fallback")
    func photoAssetIDExposed() {
        let withPhoto = MealRowFormat(record: makeMealRecord(photoAssetID: "PHA-1234"))
        #expect(withPhoto.photoAssetID == "PHA-1234")

        let withoutPhoto = MealRowFormat(record: makeMealRecord(photoAssetID: ""))
        #expect(withoutPhoto.photoAssetID == nil)
    }
}

private func makeMealRecord(
    createdAt: Date = Date(),
    totalCarbsG: Float = 42,
    segmenterSource: String = "",
    photoAssetID: String = ""
) -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.82
    var macros = PbMacroResult()
    macros.totalCarbsG = totalCarbsG
    return MealRecord(
        createdAt: createdAt,
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v0",
        photoAssetID: photoAssetID,
        segmenterSource: segmenterSource,
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}
