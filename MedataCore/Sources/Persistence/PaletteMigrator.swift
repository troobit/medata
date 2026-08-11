import Foundation
import PortableContracts

public enum PaletteMigratorError: Error, Equatable {
    case mappingFileMissing(String)
    case mappingFileMalformed(String)
    case foodEntryUnavailable(classId: String, edition: String)
}

// Food-DB interface used by PaletteMigrator. Kept narrow to avoid importing Foods.
// Per-edition lookups are required because migration reads old edition for old class
// and new edition for new class (design §6.12).
public protocol PaletteFoodDatabase: Sendable {
    func density(classId: String, edition: String) -> Float?
    func beta(classId: String, edition: String) -> Float?
    func carbsMono(classId: String, edition: String) -> Float?
}

public protocol PaletteMigrator: Sendable {
    func canMigrate(from: String, to: String) -> Bool
    // Produces a new shadow record with a fresh UUID. Original is not modified (Req 14.2).
    func reDerive(meal: MealRecord, to edition: String) async throws -> MealRecord
}

// Loads class_mapping_<from>_<to>.json from provided URLs.
// Algorithm per design §6.12: m_c' = V_c · ρ_new · β_new / (ρ_old · β_old)
public final class BundlePaletteMigrator: PaletteMigrator, @unchecked Sendable {

    // Keys are "\(fromPalette)→\(toPalette)". Dormant until a released palette
    // changes: pre-release there is a single palette (v0) and no mapping files
    // are bundled (pipeline Decision 50).
    private let mappingURLs: [String: URL]
    private let foodDB: any PaletteFoodDatabase

    public init(mappingURLs: [String: URL], foodDB: any PaletteFoodDatabase) {
        self.mappingURLs = mappingURLs
        self.foodDB = foodDB
    }

    public func canMigrate(from: String, to: String) -> Bool {
        mappingURLs[mapKey(from, to)] != nil
    }

    public func reDerive(meal: MealRecord, to edition: String) async throws -> MealRecord {
        guard let url = mappingURLs[mapKey(meal.paletteVersion, edition)] else {
            throw PaletteMigratorError.mappingFileMissing(mapKey(meal.paletteVersion, edition))
        }
        let data = try Data(contentsOf: url)
        let mappingFile: PbClassMappingFile
        do { mappingFile = try PbClassMappingFile(jsonUTF8Data: data) }
        catch { throw PaletteMigratorError.mappingFileMalformed(url.lastPathComponent) }

        let oldEdition = meal.databaseEdition
        var newVolumes = meal.volumes
        var newPerClassVols: [String: Float] = [:]
        // Pre-β volumes are geometric, independent of class identity — the map
        // is re-keyed through the migration unchanged in value (meal-review
        // Decision 17). Empty on records written before the field existed.
        var newPreBetaVols: [String: Float] = [:]
        var newPerClassMacros: [String: PbPerClassMacros] = [:]
        var newPerClassCalibration: [String: PbBetaCalibrationStatus] = [:]
        var newTotalCarbsG: Float = 0

        for (oldClassId, mapping) in mappingFile.mappings {
            guard let volumeCm3 = meal.volumes.perClassVolumesCm3[oldClassId],
                  volumeCm3 > 0 else { continue }

            if mapping.toClassIDOrUnmappable == "unmappable" {
                // Retain as-is under old edition label.
                newPerClassVols[oldClassId] = volumeCm3
                if let preBeta = meal.volumes.perClassVolumesPreBetaCm3[oldClassId] {
                    newPreBetaVols[oldClassId] = preBeta
                }
                if let entry = meal.macros.perClass[oldClassId] {
                    newPerClassMacros[oldClassId] = entry
                    newTotalCarbsG += entry.carbsG
                }
                newPerClassCalibration[oldClassId] = meal.perClassCalibration[oldClassId] ?? .uncalibratedUnity
            } else {
                let newClassId = mapping.toClassIDOrUnmappable

                guard let rhoOld = foodDB.density(classId: oldClassId, edition: oldEdition),
                      let betaOld = foodDB.beta(classId: oldClassId, edition: oldEdition) else {
                    throw PaletteMigratorError.foodEntryUnavailable(classId: oldClassId, edition: oldEdition)
                }
                guard let rhoNew = foodDB.density(classId: newClassId, edition: edition),
                      let betaNew = foodDB.beta(classId: newClassId, edition: edition),
                      let kappaNew = foodDB.carbsMono(classId: newClassId, edition: edition) else {
                    throw PaletteMigratorError.foodEntryUnavailable(classId: newClassId, edition: edition)
                }

                // m_c' = V_c · ρ_new · β_new / (ρ_old · β_old) — design §6.12
                let divisor = rhoOld * betaOld
                let massNew = divisor > 0 ? volumeCm3 * rhoNew * betaNew / divisor : 0
                let carbsNew = massNew * kappaNew / 100.0

                newPerClassVols[newClassId] = volumeCm3
                if let preBeta = meal.volumes.perClassVolumesPreBetaCm3[oldClassId] {
                    newPreBetaVols[newClassId] = preBeta
                }
                var entry = PbPerClassMacros()
                entry.volumeCm3 = volumeCm3
                entry.massG = massNew
                entry.carbsG = carbsNew
                entry.betaUsed = betaNew
                entry.betaStatus = meal.perClassCalibration[oldClassId] ?? .uncalibratedUnity
                newPerClassMacros[newClassId] = entry
                newTotalCarbsG += carbsNew
                newPerClassCalibration[newClassId] = meal.perClassCalibration[oldClassId] ?? .uncalibratedUnity
            }
        }

        newVolumes.perClassVolumesCm3 = newPerClassVols
        newVolumes.perClassVolumesPreBetaCm3 = newPreBetaVols
        var newMacros = meal.macros
        newMacros.perClass = newPerClassMacros
        newMacros.totalCarbsG = newTotalCarbsG

        return MealRecord(
            id: UUID(),
            createdAt: Date(),
            capturePath: meal.capturePath,
            databaseEdition: edition,
            paletteVersion: mappingFile.toPalette,
            frames: meal.frames,
            calibration: meal.calibration,
            supportPlane: meal.supportPlane,
            scale: meal.scale,
            volumes: newVolumes,
            macros: newMacros,
            confidence: meal.confidence,
            perClassCalibration: newPerClassCalibration,
            userCorrection: nil
        )
    }

    private func mapKey(_ from: String, _ to: String) -> String { "\(from)→\(to)" }
}
