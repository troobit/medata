import Foundation
import PortableContracts
import Segmentation
import XCTest
@testable import Persistence

// Tests for BundlePaletteMigrator per design §6.12 / Req 11.10 / task 47.

final class PaletteMigratorTests: XCTestCase {

    // MARK: - T47.1 canMigrate returns true when mapping URL exists

    func testCanMigrateReturnsTrueWhenMappingPresent() throws {
        let url = try writeMappingFile(from: "v1", to: "v2", mappings: [:])
        let migrator = BundlePaletteMigrator(mappingURLs: ["v1→v2": url], foodDB: StubFoodDB())
        XCTAssertTrue(migrator.canMigrate(from: "v1", to: "v2"))
        XCTAssertFalse(migrator.canMigrate(from: "v1", to: "v3"))
    }

    // MARK: - T47.2 Original record is not mutated (Req 14.2)

    func testOriginalRecordUnchanged() async throws {
        let original = makeMeal(paletteVersion: "v1", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "v1", to: "v2", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["rice": 32.0, "brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

        XCTAssertNotEqual(shadow.id, original.id, "shadow must have a new UUID")
        XCTAssertEqual(original.paletteVersion, "v1")
        XCTAssertEqual(original.databaseEdition, "CoFID-v1")
        XCTAssertEqual(original.volumes.perClassVolumesCm3["rice"], 100)
    }

    // MARK: - T47.3 Shadow record has new edition and palette version

    func testShadowRecordHasNewEdition() async throws {
        let original = makeMeal(paletteVersion: "v1", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "v1", to: "v2", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["rice": 32.0, "brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

        XCTAssertEqual(shadow.databaseEdition, "v2")
        XCTAssertEqual(shadow.paletteVersion, "v2")
    }

    // MARK: - T47.4 Mappable class re-derived with formula m_c' = V_c·ρ_new·β_new / (ρ_old·β_old)

    func testMappableClassReDerived() async throws {
        // rice: V=100, ρ_old=1.05, β_old=0.9, massOld=105
        // brown_rice: ρ_new=1.10, β_new=0.85, κ_new=30
        // m' = 100 × 1.10 × 0.85 / (1.05 × 0.9) = 93.5 / 0.945 ≈ 98.94
        // C' = 98.94 × 30 / 100 ≈ 29.68
        let original = makeMeal(paletteVersion: "v1", classId: "rice", volumeCm3: 100, massG: 105)
        let url = try writeMappingFile(from: "v1", to: "v2", mappings: ["rice": "brown_rice"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

        let newEntry = try XCTUnwrap(shadow.macros.perClass["brown_rice"])
        let expectedMass: Float = 100.0 * 1.10 * 0.85 / (1.05 * 0.9)
        let expectedCarbs: Float = expectedMass * 30.0 / 100.0
        XCTAssertEqual(newEntry.massG, expectedMass, accuracy: 0.01)
        XCTAssertEqual(newEntry.carbsG, expectedCarbs, accuracy: 0.01)
        XCTAssertEqual(shadow.macros.totalCarbsG, expectedCarbs, accuracy: 0.01)
    }

    // MARK: - T47.5 Unmappable class is retained under old class id

    func testUnmappableClassRetained() async throws {
        let original = makeMeal(paletteVersion: "v1", classId: "legacy_item",
                                volumeCm3: 80, massG: 72, carbsG: 15.0)
        let url = try writeMappingFile(from: "v1", to: "v2", mappings: ["legacy_item": "unmappable"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB()
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

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
        var entry1 = PbPerClassMacros(); entry1.volumeCm3 = 100; entry1.massG = 105; entry1.carbsG = 33.6; entry1.betaUsed = 0.9
        var entry2 = PbPerClassMacros(); entry2.volumeCm3 = 80;  entry2.massG = 72;  entry2.carbsG = 15.0; entry2.betaUsed = 1.0
        var macros = PbMacroResult(); macros.totalCarbsG = 48.6; macros.perClass = ["rice": entry1, "legacy_item": entry2]
        var confidence = PbConfidenceResult(); confidence.sigmaMeal = 0.8
        let original = MealRecord(
            capturePath: .singleViewLidar,
            databaseEdition: "CoFID-v1",
            paletteVersion: "v1",
            calibration: PbCameraIntrinsics(), supportPlane: PbSupportPlane(), scale: PbMetricScale(),
            volumes: volumes, macros: macros, confidence: confidence,
            perClassCalibration: ["rice": .calibrated, "legacy_item": .uncalibratedUnity]
        )

        let url = try writeMappingFile(from: "v1", to: "v2",
                                       mappings: ["rice": "brown_rice", "legacy_item": "unmappable"])
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB(densities: ["rice": 1.05, "brown_rice": 1.10],
                               betas: ["rice": 0.9, "brown_rice": 0.85],
                               carbsMonos: ["brown_rice": 30.0])
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

        let reDerivedEntry = try XCTUnwrap(shadow.macros.perClass["brown_rice"])
        let retainedEntry = try XCTUnwrap(shadow.macros.perClass["legacy_item"])
        XCTAssertEqual(retainedEntry.carbsG, 15.0, accuracy: 0.01)
        let expectedTotal = reDerivedEntry.carbsG + retainedEntry.carbsG
        XCTAssertEqual(shadow.macros.totalCarbsG, expectedTotal, accuracy: 0.01)
    }

    // MARK: - T47.7 Missing mapping file throws mappingFileMissing

    func testMissingMappingFileThrows() async throws {
        let original = makeMeal(paletteVersion: "v1", classId: "rice", volumeCm3: 100, massG: 105)
        let migrator = BundlePaletteMigrator(mappingURLs: [:], foodDB: StubFoodDB())
        do {
            _ = try await migrator.reDerive(meal: original, to: "v2")
            XCTFail("expected mappingFileMissing error")
        } catch PaletteMigratorError.mappingFileMissing {
            // expected
        }
    }

    // MARK: - Real v1 → v2 palettes (myfoodrepo-bridge PRD)

    // The real v1 → v2 mapping is the identity on every v1 class: cereal is the
    // only addition and nothing before it moves, so no v1 class remaps and none
    // is unmappable.
    private func realV1toV2Mapping() -> [String: String] {
        let v1 = ClassPalette.v1Standard
        let ids = v1.foodClasses + v1.liquidClasses
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
    }

    func testRealPalettesV1ClassesAllMapIntoV2() {
        let v1 = ClassPalette.v1Standard
        let v2 = ClassPalette.v2Standard
        let v2Ids = Set(v2.foodClasses + v2.liquidClasses)
        for (from, to) in realV1toV2Mapping() {
            XCTAssertEqual(from, to, "v1 → v2 is identity per class")
            XCTAssertTrue(v2Ids.contains(to), "\(to) must exist in v2")
        }
        // Cereal is new in v2: unreachable from any v1 class by design
        // (unmappable-from-v1 is acceptable; nothing maps to it).
        XCTAssertFalse(v1.foodClasses.contains("cereal"))
        XCTAssertFalse(realV1toV2Mapping().values.contains("cereal"))
    }

    func testRealV1MealMigratesToV2AcrossSolidAndLiquid() async throws {
        // A real v1 meal: a carb-priority solid plus a liquid, migrated with
        // the real identity mapping. Volumes carry over; the shadow record is
        // stamped v2; no cereal entry appears from nowhere.
        var volumes = PbVolumeResult()
        volumes.perClassVolumesCm3 = ["white_rice": 180, "milk": 200]
        var rice = PbPerClassMacros(); rice.volumeCm3 = 180; rice.massG = 131.4; rice.carbsG = 42.0; rice.betaUsed = 1.0
        var milk = PbPerClassMacros(); milk.volumeCm3 = 200; milk.massG = 206.0; milk.carbsG = 9.6; milk.betaUsed = 1.0
        var macros = PbMacroResult(); macros.totalCarbsG = 51.6
        macros.perClass = ["white_rice": rice, "milk": milk]
        var confidence = PbConfidenceResult(); confidence.sigmaMeal = 0.8
        let original = MealRecord(
            capturePath: .singleViewLidar,
            databaseEdition: "CoFID 2024",
            paletteVersion: ClassPalette.v1Standard.version,
            calibration: PbCameraIntrinsics(), supportPlane: PbSupportPlane(), scale: PbMetricScale(),
            volumes: volumes, macros: macros, confidence: confidence,
            perClassCalibration: ["white_rice": .uncalibratedUnity, "milk": .uncalibratedUnity]
        )

        let url = try writeMappingFile(from: ClassPalette.v1Standard.version,
                                       to: ClassPalette.v2Standard.version,
                                       mappings: realV1toV2Mapping())
        // ρ/β/κ constant across editions: the identity migration must preserve
        // mass and carbs exactly (m' = V·ρβ/ρβ · … with old == new).
        let allIds = ClassPalette.v1Standard.foodClasses + ClassPalette.v1Standard.liquidClasses
        let migrator = BundlePaletteMigrator(
            mappingURLs: ["v1→v2": url],
            foodDB: StubFoodDB(
                densities: Dictionary(uniqueKeysWithValues: allIds.map { ($0, Float(1.0)) }),
                betas: Dictionary(uniqueKeysWithValues: allIds.map { ($0, Float(1.0)) }),
                carbsMonos: ["white_rice": 32.0, "milk": 4.8]
            )
        )
        let shadow = try await migrator.reDerive(meal: original, to: "v2")

        XCTAssertEqual(shadow.paletteVersion, "v2")
        XCTAssertEqual(shadow.volumes.perClassVolumesCm3["white_rice"], 180)
        XCTAssertEqual(shadow.volumes.perClassVolumesCm3["milk"], 200)
        XCTAssertNil(shadow.volumes.perClassVolumesCm3["cereal"])
        XCTAssertNil(shadow.macros.perClass["cereal"])
        let riceOut = try XCTUnwrap(shadow.macros.perClass["white_rice"])
        let milkOut = try XCTUnwrap(shadow.macros.perClass["milk"])
        // Identity mapping with unchanged ρ/β: mass = V·ρ·β, carbs = mass·κ/100.
        XCTAssertEqual(riceOut.massG, 180.0, accuracy: 0.01)
        XCTAssertEqual(riceOut.carbsG, 180.0 * 32.0 / 100.0, accuracy: 0.01)
        XCTAssertEqual(milkOut.massG, 200.0, accuracy: 0.01)
        XCTAssertEqual(milkOut.carbsG, 200.0 * 4.8 / 100.0, accuracy: 0.01)
        XCTAssertEqual(shadow.macros.totalCarbsG, riceOut.carbsG + milkOut.carbsG, accuracy: 0.01)
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
        databaseEdition: "CoFID-v1",
        paletteVersion: paletteVersion,
        calibration: PbCameraIntrinsics(), supportPlane: PbSupportPlane(), scale: PbMetricScale(),
        volumes: vol, macros: macros, confidence: conf,
        perClassCalibration: [classId: .calibrated]
    )
}

private final class StubFoodDB: PaletteFoodDatabase, @unchecked Sendable {
    let densities: [String: Float]
    let betas: [String: Float]
    let carbsMonos: [String: Float]

    init(
        densities: [String: Float] = [:],
        betas: [String: Float] = [:],
        carbsMonos: [String: Float] = [:]
    ) {
        self.densities = densities
        self.betas = betas
        self.carbsMonos = carbsMonos
    }

    func density(classId: String, edition: String) -> Float? { densities[classId] }
    func beta(classId: String, edition: String) -> Float? { betas[classId] }
    func carbsMono(classId: String, edition: String) -> Float? { carbsMonos[classId] }
}
