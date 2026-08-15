// The suggester (specs/data/insulin-dosing Req 3 and 5, Decision 7).
//
// A pure function of its stated inputs — carbohydrate grams, ratio, band,
// insulin-on-board and dosable increment — with no dependence on ambient state
// beyond the calendar, which is supplied explicitly (Req 10.2). No network, no
// model, no clock of its own.
import Foundation

/// What the dose sheet's stepper can represent.
public struct DoseControlBounds: Sendable, Equatable {

    public let minimumUnits: Double
    public let maximumUnits: Double

    /// `InsulinDoseModel` holds units as an `Int` clamped 1...60 (Decision 7).
    public static let doseSheet = DoseControlBounds(minimumUnits: 1, maximumUnits: 60)

    public init(minimumUnits: Double, maximumUnits: Double) {
        self.minimumUnits = minimumUnits
        self.maximumUnits = maximumUnits
    }
}

/// The pen's smallest deliverable step (Req 5.1, 5.6).
public struct DosableIncrement: Sendable, Equatable {

    /// The only two values accepted; anything else leaves the previously
    /// stored value in force (Req 5.6).
    public static let permitted: [Double] = [0.5, 1.0]

    /// 1.0 U, the shipped default (Req 5.1).
    public static let standard = DosableIncrement(units: 1.0)!

    public let units: Double

    public init?(units: Double) {
        guard units.isFinite, Self.permitted.contains(units) else { return nil }
        self.units = units
    }
}

/// Everything the suggestion is computed from. Nothing else is consulted.
public struct DoseInputs: Sendable {

    /// `nil` suppresses the suggestion; it is never defaulted to a number
    /// (Req 3.5).
    public let carbsG: Double?

    /// The instant the meal or intake happened, which selects the band — not
    /// the moment the dose sheet was opened (Req 2.4).
    public let mealInstant: Date

    /// Supplied, never ambient (Req 2.2, 10.2).
    public let calendar: Calendar

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
        bounds: DoseControlBounds = .doseSheet
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

/// The band, hours, offset, ratio and insulin-on-board that were in force —
/// carried on a suppression as fully as on a suggestion, because Req 7.1
/// records suppressions too. A band whose ratio suppresses everything is a
/// finding, not an absence.
public struct SuggestionContext: Sendable, Equatable {

    public let band: DoseBand
    public let localHour: Int
    public let utcHour: Int
    public let utcOffsetSeconds: Int

    /// The ratio actually used, in the one canonical direction (Req 1.7).
    public let gramsPerUnit: Double

    /// True when no configured value existed for the band and its seed applied
    /// (Req 1.6, 9.4).
    public let ratioIsSeed: Bool

    public let iobUnits: Double
    public let incrementUnits: Double

    public init(
        band: DoseBand,
        localHour: Int,
        utcHour: Int,
        utcOffsetSeconds: Int,
        gramsPerUnit: Double,
        ratioIsSeed: Bool,
        iobUnits: Double,
        incrementUnits: Double
    ) {
        self.band = band
        self.localHour = localHour
        self.utcHour = utcHour
        self.utcOffsetSeconds = utcOffsetSeconds
        self.gramsPerUnit = gramsPerUnit
        self.ratioIsSeed = ratioIsSeed
        self.iobUnits = iobUnits
        self.incrementUnits = incrementUnits
    }
}

public struct SuggestedDose: Sendable, Equatable {

    /// Unrounded, retained so the rounding error stays measurable (Req 5.3).
    public let exactUnits: Double

    /// A whole multiple of the increment (Req 5.1).
    public let roundedUnits: Double

    /// What the stepper opens at (Req 6.4).
    public let seedUnits: Int

    /// Set when `roundedUnits` exceeded the control's maximum (Req 5.5).
    public let seedWasClamped: Bool

    public let context: SuggestionContext

    /// The dose rule that produced the number, so suggestions from different
    /// rules are never pooled by accident (Req 7.9).
    public static let ruleID = "cr-v0"
    public static let ruleVersion = 1

    public init(
        exactUnits: Double,
        roundedUnits: Double,
        seedUnits: Int,
        seedWasClamped: Bool,
        context: SuggestionContext
    ) {
        self.exactUnits = exactUnits
        self.roundedUnits = roundedUnits
        self.seedUnits = seedUnits
        self.seedWasClamped = seedWasClamped
        self.context = context
    }
}

public enum SuppressionReason: String, Sendable, Equatable {
    /// No carbohydrate total was available (Req 3.5).
    case noCarbTotal
    /// The unrounded value was below 0.5 U (Req 3.4).
    case belowMeaningfulDose
    /// The rounded value fell below what the control can represent (Req 5.4).
    case belowControlMinimum
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason, context: SuggestionContext)
}

public enum DoseSuggester {

    /// The smallest dose worth suggesting. Below this the suggestion is
    /// withheld rather than raised to the control's floor, because clamping
    /// 0.3 U up to 1 U would be an overdose invented by a user-interface
    /// constraint (Req 3.4, Decision 7).
    public static let meaningfulMinimumUnits = 0.5

    /// The whole rule, in order — and the order matters.
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome {
        // 2. Band and ratio, hoisted above step 1 because every exit needs the
        //    context: a suppression is recorded as fully as a suggestion
        //    (Req 7.1). Nothing here depends on the carbohydrate total, so the
        //    order of the two is not observable.
        let reading = DoseBand.reading(at: inputs.mealInstant, calendar: inputs.calendar)
        let (ratio, isSeed) = inputs.ratios.ratio(for: reading.band)

        let context = SuggestionContext(
            band: reading.band,
            localHour: reading.localHour,
            utcHour: reading.utcHour,
            utcOffsetSeconds: reading.utcOffsetSeconds,
            gramsPerUnit: ratio.gramsPerUnit,
            ratioIsSeed: isSeed,
            iobUnits: inputs.iobUnits,
            incrementUnits: inputs.increment.units
        )

        // 1. No carbohydrate total: suppressed, never defaulted (Req 3.5).
        guard let carbsG = inputs.carbsG, carbsG.isFinite else {
            return .suppressed(.noCarbTotal, context: context)
        }

        // 3. carbs ÷ ratio − insulin-on-board, floored at zero (Req 3.1). No
        //    fat, correction, confidence or activity term enters this line
        //    (Req 3.8) — that is the point, not an omission.
        let exact = max(0, carbsG / ratio.gramsPerUnit - inputs.iobUnits)

        // 4. Tested on the UNROUNDED value, so a 3 g quick-add at 10 g/U
        //    (0.30 U) is suppressed rather than becoming a 1 U dose invented
        //    by the stepper's floor (Req 3.4).
        guard exact >= meaningfulMinimumUnits else {
            return .suppressed(.belowMeaningfulDose, context: context)
        }

        // 5. Rounded half away from zero, applied ONCE to the final value,
        //    never to the carbohydrate term or the insulin-on-board term
        //    separately (Req 5.2).
        let increment = inputs.increment.units
        let rounded = (exact / increment).rounded(.toNearestOrAwayFromZero) * increment

        // 6. Below the control's floor: suppressed, not clamped up (Req 5.4).
        //    Reachable only at a 0.5 U increment.
        guard rounded >= inputs.bounds.minimumUnits else {
            return .suppressed(.belowControlMinimum, context: context)
        }

        // 7. Seed the control, recording whether it was clamped. `exactUnits`
        //    is recorded unchanged either way (Req 5.5, 5.7).
        let seedWasClamped = rounded > inputs.bounds.maximumUnits
        let seedUnits = Int(min(rounded, inputs.bounds.maximumUnits).rounded())

        return .suggested(
            SuggestedDose(
                exactUnits: exact,
                roundedUnits: rounded,
                seedUnits: seedUnits,
                seedWasClamped: seedWasClamped,
                context: context))
    }
}
