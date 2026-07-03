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
    // nutrition5k-calibration Req 10.1: protein/fat from the same β-corrected
    // mass × DB fraction — carbs stay primary, these are additive (Req 10.2)
    // and not surfaced in v1 UI (Req 10.3).
    public let proteinG: Float
    public let fatG: Float
    // Banner inputs (Req 8.1): baked per class from the food DB / class kind.
    public let deviceVerified: Bool
    public let isLiquid: Bool

    public init(
        volumeCm3: Float, massG: Float, carbsG: Float,
        densitySource: String, coefficientSource: String,
        betaUsed: Float, betaStatus: BetaCalibrationStatus,
        proteinG: Float = 0, fatG: Float = 0,
        deviceVerified: Bool = false, isLiquid: Bool = false
    ) {
        self.volumeCm3 = volumeCm3
        self.massG = massG
        self.carbsG = carbsG
        self.densitySource = densitySource
        self.coefficientSource = coefficientSource
        self.betaUsed = betaUsed
        self.betaStatus = betaStatus
        self.proteinG = proteinG
        self.fatG = fatG
        self.deviceVerified = deviceVerified
        self.isLiquid = isLiquid
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
    // nutrition5k-calibration Req 8.2: both liquid estimate paths over-read
    // (Decision 19) — raised here so ResultView needs no new lookups.
    public let liquidOverEstimate: Bool

    public init(
        totalCarbsG: Float, perClass: [String: PerClassMacros],
        clinicalTotals: ClinicalMacros, liquidOverEstimate: Bool = false
    ) {
        self.totalCarbsG = totalCarbsG
        self.perClass = perClass
        self.clinicalTotals = clinicalTotals
        self.liquidOverEstimate = liquidOverEstimate
    }
}

// Pure computation module. No mutable state; thread-safe by construction.
public enum Macros {

    // Compute macros for all food classes present in perClassVolumesCm3.
    //
    // Classes with no database entry are skipped (logged at debug level via assertion).
    // unknown_food volumes contribute 0 carbs with calibrationStatus = .uncalibratedUnity
    // (Req 8.6), which the caller should detect and flag separately.
    //
    // `liquidClassIds` marks entries as liquid (the palette's coarse liquid
    // classes — liquid-ness is a palette property, not a DB column). A liquid
    // entry here came through the depth-integrated path, which over-reads
    // (Req 7.3), so it raises `liquidOverEstimate`; `liquidOverEstimate: true`
    // threads the same flag from the LiquidResolver vessel path (Req 7.4/8.2).
    public static func compute(
        perClassVolumesCm3: [String: Float],
        database: FoodDatabase,
        edition: String,
        liquidClassIds: Set<String> = [],
        liquidOverEstimate: Bool = false
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

            let massG    = volumeCm3 * entry.densityGPerCm3        // Req 12.1
            let carbsG   = massG * entry.carbsMonoG / 100.0         // Req 12.2
            let proteinG = massG * entry.proteinG / 100.0           // Req 10.1
            let fatG     = massG * entry.fatG     / 100.0

            totalCarbsG  += carbsG
            totalEnergyKJ += massG * entry.energyKJPer100g / 100.0
            totalProteinG += proteinG
            totalFatG     += fatG
            totalFibreG   += massG * entry.fibreG   / 100.0

            perClass[classId] = PerClassMacros(
                volumeCm3:         volumeCm3,
                massG:             massG,
                carbsG:            carbsG,
                densitySource:     entry.densitySource,
                coefficientSource: entry.compositionSource,
                betaUsed:          entry.beta,
                betaStatus:        entry.calibrationStatus,
                proteinG:          proteinG,
                fatG:              fatG,
                deviceVerified:    entry.deviceVerified,
                isLiquid:          liquidClassIds.contains(classId)
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
            clinicalTotals:  clinical,
            liquidOverEstimate: liquidOverEstimate
                || perClass.values.contains { $0.isLiquid }
        )
    }
}
