import Foods
import Foundation

// Per-class macro breakdown persisted with the meal record (design §3.8 / Req 12.7).
public struct PerClassMacros: Sendable, Codable, Equatable {
    public let volumeCm3: Float         // β-corrected volume (input from Volume module)
    public let massG: Float             // V · ρ  (Req 12.1)
    public let carbsG: Float            // m · κ / 100  (Req 12.2)
    public let densitySource: String
    public let coefficientSource: String
    public let betaUsed: Float
    public let betaStatus: BetaCalibrationStatus

    public init(
        volumeCm3: Float, massG: Float, carbsG: Float,
        densitySource: String, coefficientSource: String,
        betaUsed: Float, betaStatus: BetaCalibrationStatus
    ) {
        self.volumeCm3 = volumeCm3
        self.massG = massG
        self.carbsG = carbsG
        self.densitySource = densitySource
        self.coefficientSource = coefficientSource
        self.betaUsed = betaUsed
        self.betaStatus = betaStatus
    }
}

// Clinical macros — computed and persisted but NOT displayed in v1 (Req 12.6).
public struct ClinicalMacros: Sendable, Codable, Equatable {
    public let energyKJ: Float
    public let proteinG: Float
    public let fatG: Float
    public let fibreG: Float

    public init(energyKJ: Float, proteinG: Float, fatG: Float, fibreG: Float) {
        self.energyKJ = energyKJ
        self.proteinG = proteinG
        self.fatG = fatG
        self.fibreG = fibreG
    }

    public static let zero = ClinicalMacros(energyKJ: 0, proteinG: 0, fatG: 0, fibreG: 0)
}

// Full meal macro result (design §3.8 / Req 12).
public struct MacroResult: Sendable, Codable, Equatable {
    // Persisted at full machine precision; display rounds to 1 g per Req 12.4.
    public let totalCarbsG: Float
    public let perClass: [String: PerClassMacros]
    public let clinicalTotals: ClinicalMacros

    public init(totalCarbsG: Float, perClass: [String: PerClassMacros], clinicalTotals: ClinicalMacros) {
        self.totalCarbsG = totalCarbsG
        self.perClass = perClass
        self.clinicalTotals = clinicalTotals
    }
}

// Pure computation module. No mutable state; thread-safe by construction.
public enum Macros {

    // Compute macros for all food classes present in perClassVolumesCm3.
    //
    // Classes with no database entry are skipped (logged at debug level via assertion).
    // unknown_food volumes contribute 0 carbs with calibrationStatus = .uncalibratedUnity
    // (Req 8.6), which the caller should detect and flag separately.
    public static func compute(
        perClassVolumesCm3: [String: Float],
        database: FoodDatabase,
        edition: String
    ) -> MacroResult {
        var totalCarbsG: Float  = 0
        var totalEnergyKJ: Float = 0
        var totalProteinG: Float = 0
        var totalFatG: Float    = 0
        var totalFibreG: Float  = 0
        var perClass: [String: PerClassMacros] = [:]

        for (classId, volumeCm3) in perClassVolumesCm3 {
            guard let entry = database.entry(for: classId, edition: edition) else {
                // Class not in database — skip silently (flagged at Pipeline level).
                continue
            }

            let massG  = volumeCm3 * entry.densityGPerCm3          // Req 12.1
            let carbsG = massG * entry.carbsMonoG / 100.0           // Req 12.2

            totalCarbsG  += carbsG
            totalEnergyKJ += massG * entry.energyKJPer100g / 100.0
            totalProteinG += massG * entry.proteinG / 100.0
            totalFatG     += massG * entry.fatG     / 100.0
            totalFibreG   += massG * entry.fibreG   / 100.0

            perClass[classId] = PerClassMacros(
                volumeCm3:         volumeCm3,
                massG:             massG,
                carbsG:            carbsG,
                densitySource:     entry.densitySource,
                coefficientSource: entry.compositionSource,
                betaUsed:          entry.beta,
                betaStatus:        entry.calibrationStatus
            )
        }

        let clinical = ClinicalMacros(
            energyKJ:  totalEnergyKJ,
            proteinG:  totalProteinG,
            fatG:      totalFatG,
            fibreG:    totalFibreG
        )

        return MacroResult(
            totalCarbsG:     totalCarbsG,
            perClass:        perClass,
            clinicalTotals:  clinical
        )
    }
}
