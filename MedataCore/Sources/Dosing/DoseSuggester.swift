import Foundation

// The whole suggester (specs/data/insulin-dosing Req 3, 5). Pure functions
// over supplied values: no store, no UI, no clock of its own (Req 10.2).

public struct DoseInputs: Sendable {
    public let carbsG: Double?  // nil → suppressed, never defaulted (Req 3.5)
    public let mealInstant: Date
    public let calendar: Calendar  // supplied, never ambient (Req 10.2)
    public let ratios: CarbRatioTable
    public let iobUnits: Double
    public let increment: DosableIncrement
    public let bounds: DoseControlBounds

    public init(
        carbsG: Double?,
        mealInstant: Date,
        calendar: Calendar,
        ratios: CarbRatioTable,
        iobUnits: Double,
        increment: DosableIncrement = .standard,
        bounds: DoseControlBounds = .stepper
    ) {
        self.carbsG = carbsG
        self.mealInstant = mealInstant
        self.calendar = calendar
        self.ratios = ratios
        self.iobUnits = iobUnits
        self.increment = increment
        self.bounds = bounds
    }
}

// Carried even when nothing is suggested, because Req 7.1 records
// suppressions as fully as suggestions — a band whose ratio suppresses
// everything is a finding, not an absence.
public struct SuggestionContext: Sendable, Equatable {
    public let band: DoseBand
    public let clock: BandClock
    public let ratio: CarbRatio
    public let ratioWasSeed: Bool
    public let iobUnits: Double
    public let incrementUnits: Double
}

public enum SuppressionReason: String, Sendable, Equatable {
    case noCarbTotal  // Req 3.5
    case belowMeaningfulDose  // exact < 0.5 U, Req 3.4
    case belowControlMinimum  // rounded < bounds.minimumUnits, Req 5.4
}

public struct SuggestedDose: Sendable, Equatable {
    public static let ruleID = "cr-v0"  // Req 7.9
    public static let ruleVersion = 1

    public let exactUnits: Double  // unrounded, ≥ 2 dp retained (Req 5.3)
    public let roundedUnits: Double  // multiple of the increment (Req 5.1)
    public let seedUnits: Int  // what the stepper opens at (Req 6.4)
    public let seedWasClamped: Bool  // rounded exceeded bounds.maximum (Req 5.5)
    public let context: SuggestionContext
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason, context: SuggestionContext)
}

public enum DoseSuggester {
    // Below this, on the UNROUNDED value, nothing is suggested (Req 3.4): a
    // 3 g quick-add at 10 g/U is 0.30 U and must not become a 1 U dose
    // invented by the stepper's floor.
    static let meaningfulDoseUnits = 0.5

    // The whole rule, in order — and the order matters.
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome {
        let band = DoseBand.band(at: inputs.mealInstant, calendar: inputs.calendar)
        let (ratio, isSeed) = inputs.ratios.ratio(for: band)
        let context = SuggestionContext(
            band: band,
            clock: BandClock(instant: inputs.mealInstant, calendar: inputs.calendar),
            ratio: ratio,
            ratioWasSeed: isSeed,
            iobUnits: inputs.iobUnits,
            incrementUnits: inputs.increment.units
        )

        guard let carbsG = inputs.carbsG, carbsG.isFinite else {
            return .suppressed(.noCarbTotal, context: context)
        }
        let exact = max(0, carbsG / ratio.gramsPerUnit - inputs.iobUnits)  // Req 3.1
        guard exact >= meaningfulDoseUnits else {
            return .suppressed(.belowMeaningfulDose, context: context)
        }
        // Rounding is applied ONCE, to the final value — never to the carb
        // term and the insulin-on-board term separately (Req 5.2).
        let steps = (exact / inputs.increment.units).rounded(.toNearestOrAwayFromZero)
        let rounded = steps * inputs.increment.units
        guard rounded >= inputs.bounds.minimumUnits else {
            return .suppressed(.belowControlMinimum, context: context)
        }
        let clamped = rounded > inputs.bounds.maximumUnits
        let seedUnits = Int(min(rounded, inputs.bounds.maximumUnits).rounded())
        return .suggested(
            SuggestedDose(
                exactUnits: exact,
                roundedUnits: rounded,
                seedUnits: seedUnits,
                seedWasClamped: clamped,
                context: context
            )
        )
    }
}
