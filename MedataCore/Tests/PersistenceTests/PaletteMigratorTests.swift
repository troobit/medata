import Foundation
import PortableContracts
import Segmentation
import XCTest
@testable import Persistence

// Tests for BundlePaletteMigrator per design §6.12 / Req 11.10 / task 47.

final class PaletteMigratorTests: XCTestCase {

    // MARK: - T47.1 canMigrate returns true when mapping URL exists

    func testCanMigrateReturnsTrueWhenMappingPresent() throws {
        let url = try writeMappingFile(from: "old", to: "new", mappings: [:])
        let migrator = BundlePaletteMigrator(mappingURLs: ["old→new": url], foodDB: StubFoodDB())
        XCTAssertTrue(migrator.canMigrate(from: "old", to: "new"))
        XCTAssertFalse(migrator.canMigrate(from: "old", to: "other"))
    }

    // MARK: - T47.2 Original record is not mutated (Req 14.2)

    func testOriginalRecordUnchanged() async throws {
        let original = makeMeal(paletteVersion: "old", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "old", to: "new", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["old→new": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["rice": 32.0, "brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "new")

        XCTAssertNotEqual(shadow.id, original.id, "shadow must have a new UUID")
        XCTAssertEqual(original.paletteVersion, "old")
        XCTAssertEqual(original.databaseEdition, "CoFID-old")
        XCTAssertEqual(original.volumes.perClassVolumesCm3["rice"], 100)
    }

    // MARK: - T47.3 Shadow record has new edition and palette version

    func testShadowRecordHasNewEdition() async throws {
        let original = makeMeal(paletteVersion: "old", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "old", to: "new", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["old→new": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["rice": 32.0, "brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "new")

        XCTAssertEqual(shadow.databaseEdition, "new")
        XCTAssertEqual(shadow.paletteVersion, "new")
    }

    // MARK: - T47.4 Mappable class re-derived with formula m_c' = V_c·ρ_new·β_new / (ρ_old·β_old)

    func testMappableClassReDerived() async throws {
        // rice: V=100, ρ_old=1.05, β_old=0.9, massOld=105
        // brown_rice: ρ_new=1.10, β_new=0.85, κ_new=30
        // m' = 100 × 1.10 × 0.85 / (1.05 × 0.9) = 93.5 / 0.945 ≈ 98.94
        // C' = 98.94 × 30 / 100 ≈ 29.68
        let original = makeMeal(paletteVersion: "old", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "old", to: "new", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["old→new": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "new")

        let newEntry = try XCTUnwrap(shadow.macros.perClass["brown_rice"])
        let expectedMass: Float = 100.0 * 1.10 * 0.85 / (1.05 * 0.9)
        let expectedCarbs: Float = expectedMass * 30.0 / 100.0
        XCTAssertEqual(newEntry.massG, expectedMass, accuracy: 0.01)
        XCTAssertEqual(newEntry.carbsG, expectedCarbs, accuracy: 0.01)
        XCTAssertEqual(shadow.macros.totalCarbsG, expectedCarbs, accuracy: 0.01)
    }

    // MARK: - T47.5 Unmappable class is retained under old class id

    func testUnmappableClassRetained() async throws {
        let original = makeMeal(paletteVersion: "old", classId: "legacy_item",
                                volumeCm3: 80, massG: 72, carbsG: 15.0)
        let url = try writeMappingFile(from: "old", to: "new", mappings: ["legacy_item": "unmappable"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["old→new": url],
            foodDB: StubFoodDB()
        )
        let shadow = try await migrator.reDerive(meal: original, to: "new")

        // The legacy_item entry must be retained unchanged.
        let retained = try XCTUnwrap(shadow.macros.perClass["legacy_item"])
        XCTAssertEqual(retained.massG, 72.0, accuracy: 0.01)
        XCTAssertEqual(retained.carbsG, 15.0, accuracy: 0.01)
        XCTAssertNil(shadow.macros.perClass["brown_rice"], "no remapped entry should appear")
    }

    // MARK: - T47.6 Mixed: one mappable + one unmappable

    func testMixedMappingCorrectTotals() async throws {
        var volumes = PbVolumeResult()
        volumes.perClassVolumesCm3 = ["rice": 100, "legacy_item": 80]
        volumes.perClassVolumesPreBetaCm3 = ["rice": 111.1, "legacy_item": 80]
        var entry1 = PbPerClassMacros(); entry1.volumeCm3 = 100; entry1.massG = 105; entry1.carbsG = 33.6; entry1.betaUsed = 0.9
        var entry2 = PbPerClassMacros(); entry2.volumeCm3 = 80;  entry2.massG = 72;  entry2.carbsG = 15.0; entry2.betaUsed = 1.0
        var macros = PbMacroResult(); macros.totalCarbsG = 48.6; macros.perClass = ["rice": entry1, "legacy_item": entry2]
        var confidence = PbConfidenceResult(); confidence.sigmaMeal = 0.8
        let original = MealRecord(
            capturePath: .singleViewLidar,
            databaseEdition: "CoFID-old",
            paletteVersion: "old",
            calibration: PbCameraIntrinsics(), supportPlane: PbSupportPlane(), scale: PbMetricScale(),
            volumes: volumes, macros: macros, confidence: confidence,
            perClassCalibration: ["rice": .calibrated, "legacy_item": .uncalibratedUnity]
        )

        let url = try writeMappingFile(from: "old", to: "new",
                                       mappings: ["rice": "brown_rice", "legacy_item": "unmappable"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["old→new": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "new")

        let reDerivedEntry = try XCTUnwrap(shadow.macros.perClass["brown_rice"])
        let retainedEntry = try XCTUnwrap(shadow.macros.perClass["legacy_item"])
        XCTAssertEqual(retainedEntry.carbsG, 15.0, accuracy: 0.01)
        let expectedTotal = reDerivedEntry.carbsG + retainedEntry.carbsG
        XCTAssertEqual(shadow.macros.totalCarbsG, expectedTotal, accuracy: 0.01)

        // Pre-β volumes re-key through the migration with values unchanged
        // (meal-review Decision 17): geometric facts carry no class identity.
        XCTAssertEqual(shadow.volumes.perClassVolumesPreBetaCm3["brown_rice"] ?? 0,
                       111.1, accuracy: 0.001)
        XCTAssertEqual(shadow.volumes.perClassVolumesPreBetaCm3["legacy_item"] ?? 0,
                       80, accuracy: 0.001)
        XCTAssertNil(shadow.volumes.perClassVolumesPreBetaCm3["rice"],
                     "old key must not survive a remap")
    }

    // MARK: - T47.7 Missing mapping file throws mappingFileMissing

    func testMissingMappingFileThrows() async throws {
        let original = makeMeal(paletteVersion: "old", classId: "rice", volumeCm3: 100, massG: 105)
        let migrator = BundlePaletteMigrator(mappingURLs: [:], foodDB: StubFoodDB())
        do {
            _ = try await migrator.reDerive(meal: original, to: "new")
            XCTFail("expected mappingFileMissing error")
        } catch PaletteMigratorError.mappingFileMissing {
            // expected
        }
    }

}

// MARK: - Helpers

private func writeMappingFile(from: String, to: String, mappings: [String: String]) throws -> URL {
    var file = PbClassMappingFile()
    file.fromPalette = from
    file.toPalette = to
    for (oldId, newId) in mappings {
        var m = PbClassMapping(); m.toClassIDOrUnmappable = newId
        file.mappings[oldId] = m
    }
    let data = try file.jsonUTF8Data()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapping-\(from)-\(to)-\(UUID().uuidString).json")
    try data.write(to: url)
    return url
}

private func makeMeal(
    paletteVersion: String,
    classId: String,
    volumeCm3: Float,
    massG: Float,
    carbsG: Float = 33.6
) -> MealRecord {
    var vol = PbVolumeResult(); vol.perClassVolumesCm3 = [classId: volumeCm3]
    var entry = PbPerClassMacros()
    entry.volumeCm3 = volumeCm3; entry.massG = massG; entry.carbsG = carbsG; entry.betaUsed = 0.9
    var macros = PbMacroResult(); macros.totalCarbsG = carbsG; macros.perClass = [classId: entry]
    var conf = PbConfidenceResult(); conf.sigmaMeal = 0.8
    return MealRecord(
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID-old",
        paletteVersion: paletteVersion,
        calibration: PbCameraIntrinsics(), supportPlane: PbSupportPlane(), scale: PbMetricScale(),
        volumes: vol, macros: macros, confidence: conf,
        perClassCalibration: [classId: .calibrated]
    )
}

private struct StubFoodDB: PaletteFoodDatabase {
    var densities: [String: Float] = [:]
    var betas: [String: Float] = [:]
    var carbsMonos: [String: Float] = [:]

    func density(classId: String, edition: String) -> Float? { densities[classId] }
    func beta(classId: String, edition: String) -> Float? { betas[classId] }
    func carbsMono(classId: String, edition: String) -> Float? { carbsMonos[classId] }
}
