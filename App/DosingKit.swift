import Foundation

// Pure dose arithmetic, exactly the shapes given in
// `specs/data/insulin-dosing/design.md` — the ratio, the bands, the
// insulin-on-board curve and the seven-step suggester.
//
// TEMPORARY LOCATION, NOT A NEW MODULE. This belongs in the zero-dependency
// `Dosing` SwiftPM target that insulin-dosing task 1 adds; that target is not
// on this branch, so the UI phase carries the calculator here to stay
// buildable. Moving it is a file move plus `import Dosing` at four call sites
// — no signature changes, and every name below matches the design document.
//
// Nothing here reads a store, a network or a clock it was not handed
// (Req 10.2). `nonisolated` throughout because the project sets
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would otherwise make these
// value types MainActor-isolated and unusable as `Sendable` inputs.

// MARK: - The ratio (Req 1)

/// Grams of carbohydrate covered by one unit of insulin — the clinical
/// carbohydrate ratio, and the direction medreg fits in. The reciprocal
/// (units per gram) is NEVER stored; `unitsPerTenGrams` is a display
/// derivation only (Req 1.1, 1.2).
nonisolated struct CarbRatio: Sendable, Equatable, Hashable {
    static let permitted: ClosedRange<Double> = 1.0...60.0  // Req 1.5

    let gramsPerUnit: Double

    /// nil for a value outside `permitted` or a non-finite value; the caller
    /// keeps whatever was previously in force (Req 1.5).
    init?(gramsPerUnit: Double) {
        guard gramsPerUnit.isFinite, Self.permitted.contains(gramsPerUnit) else { return nil }
        self.gramsPerUnit = gramsPerUnit
    }

    /// Display only. 5.0 g/U renders "= 2.0 U per 10 g" (Req 1.2).
    var unitsPerTenGrams: Double { 10.0 / gramsPerUnit }
}

// MARK: - Bands (Req 2)

nonisolated enum DoseBand: String, Sendable, Equatable, CaseIterable {
    case overnight, breakfast, lunch, dinner

    /// Half-open local-hour ranges; the boundary hour opens the band it
    /// starts (Req 2.3). Exactly medreg's `TimeOfDaySegment` boundaries.
    var localHours: Range<Int> {
        switch self {
        case .overnight: 0..<6
        case .breakfast: 6..<11
        case .lunch: 11..<16
        case .dinner: 16..<24
        }
    }

    var label: String {
        switch self {
        case .overnight: "Overnight"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    /// "06:00–11:00" — a fact about which meals the row governs, rendered as
    /// the Settings row's secondary text (design-direction §5).
    var windowLabel: String {
        String(format: "%02d:00–%02d:00", localHours.lowerBound, localHours.upperBound)
    }

    /// Calendar (and therefore time zone) is injected, never reached for
    /// (Req 2.2, 10.2).
    static func band(at instant: Date, calendar: Calendar) -> DoseBand {
        let hour = calendar.component(.hour, from: instant)
        return allCases.first { $0.localHours.contains(hour) } ?? .dinner
    }
}

nonisolated struct CarbRatioTable: Sendable, Equatable {
    /// Seeds reproducing the developer's stated rule — 2 U per 10 g at
    /// breakfast (5.0 g/U), 1 U per 10 g otherwise (10.0 g/U) (Req 1.4).
    static let seed: [DoseBand: CarbRatio] = [
        .overnight: CarbRatio(gramsPerUnit: 10.0)!,
        .breakfast: CarbRatio(gramsPerUnit: 5.0)!,
        .lunch: CarbRatio(gramsPerUnit: 10.0)!,
        .dinner: CarbRatio(gramsPerUnit: 10.0)!
    ]

    private let configured: [DoseBand: CarbRatio]

    init(configured: [DoseBand: CarbRatio]) {
        self.configured = configured
    }

    /// Falls back to the seed for an unconfigured band and reports which
    /// applied, so the row can record it (Req 1.6, 1.7, 9.4).
    func ratio(for band: DoseBand) -> (value: CarbRatio, isSeed: Bool) {
        if let value = configured[band] { return (value, false) }
        return (Self.seed[band] ?? CarbRatio(gramsPerUnit: 10.0)!, true)
    }
}

// MARK: - Insulin-on-board (Req 4)

/// The oref0 / LoopKit exponential model, ported from medreg's
/// `ExponentialInsulinModel` term for term. Only the `iob` branch is needed.
nonisolated struct InsulinActivityModel: Sendable, Equatable {
    let peakMinutes: Double
    let durationMinutes: Double

    /// medreg's RAPID_ACTING preset (peak 75 min, DIA 360 min), Req 4.1.
    /// Derived constants: tau 101.785714, a 0.565476, S 2.082955.
    static let rapidActing = InsulinActivityModel(peakMinutes: 75, durationMinutes: 360)

    /// Fraction of one unit still on board after `minutes`. 1.0 at or before
    /// delivery, 0.0 at or beyond the duration of action (Req 4.3).
    func remainingFraction(after minutes: Double) -> Double {
        guard minutes > 0 else { return 1 }
        guard minutes < durationMinutes else { return 0 }
        let tp = peakMinutes
        let td = durationMinutes
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))
        let t = minutes
        let bracket = (t * t / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1
        return 1 - s * (1 - a) * bracket
    }
}

nonisolated struct BolusHistoryEntry: Sendable, Equatable {
    let minutesBefore: Double  // positive = in the past
    let units: Double
}

/// Sum of units times remaining fraction over prior boluses (Req 4.1–4.4).
/// Basal is excluded by the caller; an empty history yields 0 and is not an
/// error.
nonisolated func insulinOnBoard(
    _ boluses: [BolusHistoryEntry],
    model: InsulinActivityModel = .rapidActing
) -> Double {
    boluses.reduce(0.0) { total, entry in
        guard entry.minutesBefore >= 0, entry.minutesBefore < model.durationMinutes else {
            return total
        }
        return total + entry.units * model.remainingFraction(after: entry.minutesBefore)
    }
}

// MARK: - The suggester (Req 3, 5)

nonisolated struct DoseControlBounds: Sendable, Equatable {
    /// What the dose sheet's stepper can represent: 1...60 U today.
    let minimumUnits: Double
    let maximumUnits: Double

    static let doseSheet = DoseControlBounds(minimumUnits: 1, maximumUnits: 60)
}

nonisolated struct DosableIncrement: Sendable, Equatable {
    static let permitted: [Double] = [0.5, 1.0]  // Req 5.6
    static let standard = DosableIncrement(units: 1.0)!  // Req 5.1

    let units: Double

    init?(units: Double) {
        guard Self.permitted.contains(units) else { return nil }
        self.units = units
    }
}

nonisolated enum CarbsSource: String, Sendable, Equatable {
    case meal
    case mealCorrected = "meal_corrected"
    case intake
    case quickPreset = "quick_preset"
}

nonisolated struct SuggestionContext: Sendable, Equatable {
    let band: DoseBand
    let localHour: Int
    let utcHour: Int
    let utcOffsetS: Int
    let ratio: CarbRatio
    let ratioIsSeed: Bool
    let iobUnits: Double
}

nonisolated struct SuggestedDose: Sendable, Equatable {
    let exactUnits: Double  // unrounded, >= 2 dp retained (Req 5.3)
    let roundedUnits: Double  // multiple of the increment (Req 5.1)
    let seedUnits: Int  // what the stepper opens at (Req 6.4)
    let seedWasClamped: Bool  // rounded exceeded bounds.maximum (Req 5.5)
    let context: SuggestionContext

    static let ruleID = "cr-v0"  // Req 7.9
    static let ruleVersion = 1
}

nonisolated enum SuppressionReason: String, Sendable, Equatable {
    case noCarbTotal = "no_carb_total"  // Req 3.5
    case belowMeaningfulDose = "below_meaningful_dose"  // exact < 0.5 U, Req 3.4
    case belowControlMinimum = "below_control_minimum"  // Req 5.4
}

nonisolated enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason, context: SuggestionContext)
}

nonisolated struct DoseInputs: Sendable {
    let carbsG: Double?  // nil -> suppressed, never defaulted (Req 3.5)
    let mealInstant: Date
    let calendar: Calendar  // supplied, never ambient (Req 10.2)
    let ratios: CarbRatioTable
    let iobUnits: Double
    let increment: DosableIncrement
    let bounds: DoseControlBounds
}

nonisolated enum DoseSuggester {
    /// The whole rule, in order — and the order matters (design.md
    /// "The suggester"). No fat, correction, confidence or activity term
    /// enters the arithmetic (Req 3.8).
    static func suggest(_ inputs: DoseInputs) -> DoseOutcome {
        let band = DoseBand.band(at: inputs.mealInstant, calendar: inputs.calendar)
        let (ratio, isSeed) = inputs.ratios.ratio(for: band)
        let context = SuggestionContext(
            band: band,
            localHour: inputs.calendar.component(.hour, from: inputs.mealInstant),
            utcHour: Self.utcHour(of: inputs.mealInstant),
            utcOffsetS: inputs.calendar.timeZone.secondsFromGMT(for: inputs.mealInstant),
            ratio: ratio,
            ratioIsSeed: isSeed,
            iobUnits: inputs.iobUnits
        )

        // 1. Absent carbohydrate total suppresses; it is never defaulted.
        guard let carbsG = inputs.carbsG, carbsG.isFinite else {
            return .suppressed(.noCarbTotal, context: context)
        }
        // 3. exact = max(0, carbs / gramsPerUnit - iob).
        let exact = max(0, carbsG / ratio.gramsPerUnit - inputs.iobUnits)
        // 4. Tested on the UNROUNDED value, so a 3 g quick-add at 10 g/U
        //    (0.30 U) is suppressed rather than becoming a 1 U dose invented
        //    by the stepper's floor (Req 3.4).
        guard exact >= 0.5 else {
            return .suppressed(.belowMeaningfulDose, context: context)
        }
        // 5. Rounding half away from zero, applied ONCE to the final value.
        let step = inputs.increment.units
        let rounded = (exact / step).rounded(.toNearestOrAwayFromZero) * step
        // 6. Below what the control can represent.
        guard rounded >= inputs.bounds.minimumUnits else {
            return .suppressed(.belowControlMinimum, context: context)
        }
        // 7. Seed the stepper, recording the clamp; exactUnits is unchanged.
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

    private static func utcHour(of instant: Date) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return utc.component(.hour, from: instant)
    }
}
