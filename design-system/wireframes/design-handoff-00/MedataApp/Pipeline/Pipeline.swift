import Foundation

// MARK: - Volume estimation (req §9)

struct VolumeRecord: Hashable {
    let classKey: String
    let volumeCubicCm: Double
    /// Compressed bounding-set representation (req §9.6) — opaque to consumers.
    let boundingSetBlob: Data
}

protocol VolumeEstimator: AnyObject {
    /// Two-view canonical path — req §9.4 first bullet.
    func estimateTwoView(
        nadir: CapturedFrame, oblique: CapturedFrame,
        pose: PoseSE3,
        nadirSeg: SegmentationResult, obliqueSeg: SegmentationResult,
        supportPlane: SupportPlane
    ) async throws -> [VolumeRecord]

    /// Single-view depth-augmented path — req §9.4 second bullet.
    func estimateSingleView(
        nadir: CapturedFrame,
        nadirSeg: SegmentationResult,
        depth: DepthMap,
        supportPlane: SupportPlane
    ) async throws -> [VolumeRecord]
}

final class MockVolumeEstimator: VolumeEstimator {
    func estimateTwoView(nadir: CapturedFrame, oblique: CapturedFrame,
                         pose: PoseSE3,
                         nadirSeg: SegmentationResult, obliqueSeg: SegmentationResult,
                         supportPlane: SupportPlane) async throws -> [VolumeRecord] {
        SampleMeals.seed[0].classes.map {
            VolumeRecord(classKey: $0.classKey, volumeCubicCm: $0.volumeCubicCm, boundingSetBlob: Data())
        }
    }
    func estimateSingleView(nadir: CapturedFrame,
                            nadirSeg: SegmentationResult,
                            depth: DepthMap,
                            supportPlane: SupportPlane) async throws -> [VolumeRecord] {
        SampleMeals.seed[0].classes.map {
            VolumeRecord(classKey: $0.classKey, volumeCubicCm: $0.volumeCubicCm, boundingSetBlob: Data())
        }
    }
}

// MARK: - Density / macronutrient database (req §11)

struct DensityEntry: Hashable {
    let classKey: String
    let displayName: String
    let densityGPerCm3: Double          // ρ
    let carbsPer100g: Double             // κ — monosaccharide equivalents
    let proteinPer100g: Double
    let fatPer100g: Double
    let fibrePer100g: Double
    let energyKjPer100g: Double
    let bulkCorrection: Double           // β ∈ (0, 1]
    let densitySource: String
    let coefficientSource: String
}

protocol DensityDatabase: AnyObject {
    var edition: String { get }   // e.g. "CoFID 2024 + IFCDB 2023"
    func entry(for classKey: String) -> DensityEntry?
}

final class MockDensityDatabase: DensityDatabase {
    let edition = "CoFID 2024 + IFCDB 2023"
    private let entries: [String: DensityEntry] = [
        "rice_white":     DensityEntry(classKey: "rice_white", displayName: "White rice",
                                       densityGPerCm3: 1.18, carbsPer100g: 28.0, proteinPer100g: 2.6,
                                       fatPer100g: 0.3, fibrePer100g: 0.4, energyKjPer100g: 540,
                                       bulkCorrection: 0.85, densitySource: "FAO/INFOODS",
                                       coefficientSource: "CoFID 2024"),
        "chicken_roast":  DensityEntry(classKey: "chicken_roast", displayName: "Roast chicken",
                                       densityGPerCm3: 1.08, carbsPer100g: 0.0, proteinPer100g: 27,
                                       fatPer100g: 14, fibrePer100g: 0.0, energyKjPer100g: 1010,
                                       bulkCorrection: 0.92, densitySource: "Dehais 2017 Tab II",
                                       coefficientSource: "CoFID 2024"),
        "broccoli":       DensityEntry(classKey: "broccoli", displayName: "Broccoli",
                                       densityGPerCm3: 1.05, carbsPer100g: 7.0, proteinPer100g: 2.8,
                                       fatPer100g: 0.4, fibrePer100g: 2.6, energyKjPer100g: 145,
                                       bulkCorrection: 0.70, densitySource: "Project gravimetric",
                                       coefficientSource: "CoFID 2024"),
    ]
    func entry(for classKey: String) -> DensityEntry? { entries[classKey] }
}

// MARK: - Macro calculator (req §12)

protocol MacroCalculator: AnyObject {
    /// m_c = V_c · ρ_c, C_c = m_c · κ_c / 100.
    func compute(volumes: [VolumeRecord], db: DensityDatabase) -> [FoodClass]
}

final class MockMacroCalculator: MacroCalculator {
    func compute(volumes: [VolumeRecord], db: DensityDatabase) -> [FoodClass] {
        volumes.compactMap { vol in
            guard let e = db.entry(for: vol.classKey) else { return nil }
            let mass = vol.volumeCubicCm * e.densityGPerCm3
            let carbs = mass * e.carbsPer100g / 100.0
            return FoodClass(name: e.displayName, classKey: e.classKey,
                             volumeCubicCm: vol.volumeCubicCm,
                             massGrams: mass, carbsGrams: carbs,
                             confidence: 0.8)
        }
    }
}

// MARK: - Confidence combiner (req §13)

protocol ConfidenceCombiner: AnyObject {
    func combine(scale: Double, segmentation: Double, geometric: Double) -> Confidence
}

final class GeometricMeanConfidence: ConfidenceCombiner {
    func combine(scale: Double, segmentation: Double, geometric: Double) -> Confidence {
        Confidence(scale: scale, segmentation: segmentation, geometric: geometric)
    }
}
