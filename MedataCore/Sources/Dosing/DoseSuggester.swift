import Foundation

/// What the dose sheet's stepper can represent: 1...60 U today.
public struct DoseControlBounds: Sendable, Equatable {
    public static let stepper = DoseControlBounds(minimumUnits: 1, maximumUnits: 60)

    public let minimumUnits: Double
    public let maximumUnits: Double

    public init(minimumUnits: Double, maximumUnits: Double) {
        self.minimumUnits = minimumUnits
        self.maximumUnits = maximumUnits
    }
}

/// The pen's dosable increment (Req 5.1, 5.6).
public struct DosableIncrement: Sendable, Equatable {
    public static let permitted: [Double] = [0.5, 1.0]
    public static let standard = DosableIncrement(units: 1.0)!

    public let units: Double

    public init?(units: Double) {
        guard Self.permitted.contains(units) else { return nil }
        self.units = units
    }
}

/// Everything that was in force when a suggestion was computed, carried on
/// suppressions as fully as on suggestions — a band whose ratio suppresses
/// everything is a finding, not an absence (Req 7.1).
public struct SuggestionContext: Sendable, Equatable {
    public let band: DoseBand
    public let localHour: Int
    public let utcHour: Int
    public let utcOffsetSeconds: Int
    public let carbRatioGPerU: Double
    public let carbRatioIsSeed: Bool
    public let iobUnits: Double
    public let carbsG: Double?
}

public enum SuppressionReason: String, Sendable, Equatable {
    case noCarbTotal  // Req 3.5
    case belowMeaningfulDose  // exact < 0.5 U, Req 3.4
    case belowControlMinimum  // rounded < bounds.minimumUnits, Req 5.4
}

public struct SuggestedDose: Sendable, Equatable {
    /// Req 7.9 — every ledger row is stamped with the rule that produced it.
    public static let ruleID = "cr-v0"
    public static let ruleVersion = 1

    public let exactUnits: Double  // unrounded, Req 5.3
    public let roundedUnits: Double  // multiple of the increment, Req 5.1
    public let seedUnits: Int  // what the stepper opens at, Req 6.4
    public let seedWasClamped: Bool  // rounded exceeded bounds.maximum, Req 5.5
    public let context: SuggestionContext
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason, context: SuggestionContext)

    public var context: SuggestionContext {
        switch self {
        case .suggested(let dose): dose.context
        case .suppressed(_, let context): context
        }
    }
}

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

/// `carbs ÷ ratio − insulin-on-board`, banded by local time, rounded once, at
/// the pen's increment (specs/data/insulin-dosing Req 3, 5). Nothing else
/// enters the arithmetic — no fat term, no correction term, no confidence
/// gate (Req 3.8): while the dose is exactly this, a recorded outcome
/// attributes to the ratio.
public enum DoseSuggester {
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome {
        let band = DoseBand.band(at: inputs.mealInstant, calendar: inputs.calendar)
        let (ratio, isSeed) = inputs.ratios.ratio(for: band)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? inputs.calendar.timeZone
        let context = SuggestionContext(
            band: band,
            localHour: inputs.calendar.component(.hour, from: inputs.mealInstant),
            utcHour: utcCalendar.component(.hour, from: inputs.mealInstant),
            utcOffsetSeconds: inputs.calendar.timeZone.secondsFromGMT(for: inputs.mealInstant),
            carbRatioGPerU: ratio.gramsPerUnit,
            carbRatioIsSeed: isSeed,
            iobUnits: inputs.iobUnits,
            carbsG: inputs.carbsG
        )

        guard let carbsG = inputs.carbsG, carbsG.isFinite else {
            return .suppressed(.noCarbTotal, context: context)
        }
        // 60 g ÷ 5.0 g/U = 12.0 U. Division, not multiplication — the stored
        // direction is grams per unit.
        let exact = max(0, carbsG / ratio.gramsPerUnit - inputs.iobUnits)
        // Tested on the UNROUNDED value, so a 3 g quick-add at 10 g/U
        // (0.30 U) is suppressed rather than becoming a 1 U dose invented by
        // the stepper's floor (Req 3.4).
        guard exact >= 0.5 else {
            return .suppressed(.belowMeaningfulDose, context: context)
        }
        // Applied ONCE, to the final value, never to the carb term and the
        // insulin-on-board term separately (Req 5.2).
        let increment = inputs.increment.units
        let rounded = (exact / increment).rounded(.toNearestOrAwayFromZero) * increment
        guard rounded >= inputs.bounds.minimumUnits else {
            return .suppressed(.belowControlMinimum, context: context)
        }
        let clamped = min(rounded, inputs.bounds.maximumUnits)
        return .suggested(
            SuggestedDose(
                exactUnits: exact,
                roundedUnits: rounded,
                seedUnits: Int(clamped.rounded()),
                seedWasClamped: rounded > inputs.bounds.maximumUnits,
                context: context
            )
        )
    }
}
