// The suggester (specs/data/insulin-dosing Req 3 and 5, Decisions 7, 17, 18).
//
// A pure function of its stated inputs — carbohydrate grams, ratio, band and
// unoffset insulin-on-board — with no dependence on ambient state beyond the
// calendar, which is supplied explicitly (Req 10.2). No network, no model, no
// clock of its own.
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

/// The dosable step. Fixed at whole units (Req 5.1, Decision 17): the type
/// survives with one permitted value rather than being replaced by a bare
/// constant, so `DoseInputs` and its call sites keep their shape.
public struct DosableIncrement: Sendable, Equatable {

    /// The only value accepted. The 0.5 U pen option is deleted (Req 5.6,
    /// superseded).
    public static let permitted: [Double] = [1.0]

    /// 1.0 U, the only increment there is (Req 5.1).
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

    /// The Req 4.8 remainder — boluses with no meal or intake behind them —
    /// and NOT the physiological insulin-on-board total. Insulin dosed for food
    /// already consumed is spoken for and never reduces a later meal's
    /// coverage (Decision 17).
    public let unoffsetIOBUnits: Double

    public let increment: DosableIncrement
    public let bounds: DoseControlBounds

    public init(
        carbsG: Double?,
        mealInstant: Date,
        calendar: Calendar,
        ratios: CarbRatioTable,
        unoffsetIOBUnits: Double,
        increment: DosableIncrement = .standard,
        bounds: DoseControlBounds = .doseSheet
    ) {
        self.carbsG = carbsG
        self.mealInstant = mealInstant
        self.calendar = calendar
        self.ratios = ratios
        self.unoffsetIOBUnits = unoffsetIOBUnits
        self.increment = increment
        self.bounds = bounds
    }
}

/// The band and the ratio that were in force — exactly what the working's base
/// line and the dose sheet's provenance caption render (Req 6.12). Nothing is
/// recorded, so no clock bookkeeping travels here (Decision 18).
public struct SuggestionContext: Sendable, Equatable {

    public let band: DoseBand

    /// The ratio actually used, in the one canonical direction (Req 1.1).
    public let gramsPerUnit: Double

    /// True when no configured value existed for the band and its seed applied
    /// (Req 1.6, 9.4).
    public let ratioIsSeed: Bool

    public init(band: DoseBand, gramsPerUnit: Double, ratioIsSeed: Bool) {
        self.band = band
        self.gramsPerUnit = gramsPerUnit
        self.ratioIsSeed = ratioIsSeed
    }
}

/// The number and every term behind it, so the working's lines sum exactly at
/// each step (Req 6.12).
public struct SuggestedDose: Sendable, Equatable {

    /// `carbs ÷ ratio`, unrounded — the working's first line.
    public let baseUnits: Double

    /// `min(unoffset insulin-on-board, baseUnits)`. The cap is what makes
    /// `baseUnits − reductionUnits == exactUnits` true at every input rather
    /// than only where the insulin-on-board happens to be the smaller of the
    /// two (Req 6.12).
    public let reductionUnits: Double

    /// `baseUnits − reductionUnits`, ≥ 0 by construction, which is Req 3.1's
    /// zero floor. Rendered to at least one decimal place (Req 5.3).
    public let exactUnits: Double

    /// A whole multiple of 1 U (Req 5.1). `0` is a result to render, not a
    /// refusal (Req 3.4).
    public let roundedUnits: Double

    /// What the stepper opens at (Req 6.4). `0` means no seed is armed — it
    /// sits outside the control's 1...60 by design and is never a clamp upward
    /// (Req 5.4).
    public let seedUnits: Int

    /// Set when `roundedUnits` exceeded the control's maximum (Req 5.5).
    public let seedWasClamped: Bool

    public let context: SuggestionContext

    public init(
        baseUnits: Double,
        reductionUnits: Double,
        exactUnits: Double,
        roundedUnits: Double,
        seedUnits: Int,
        seedWasClamped: Bool,
        context: SuggestionContext
    ) {
        self.baseUnits = baseUnits
        self.reductionUnits = reductionUnits
        self.exactUnits = exactUnits
        self.roundedUnits = roundedUnits
        self.seedUnits = seedUnits
        self.seedWasClamped = seedWasClamped
        self.context = context
    }
}

public enum SuppressionReason: String, Sendable, Equatable, CaseIterable {
    /// No carbohydrate total was available — the sole remaining case
    /// (Req 3.5). Every input with a total returns a number, `0 U` included.
    case noCarbTotal
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason)
}

public enum DoseSuggester {

    /// The whole rule, in order — and the order matters.
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome {
        // 1. No carbohydrate total: suppressed, never defaulted (Req 3.5).
        //    The only outcome that is not a number.
        guard let carbsG = inputs.carbsG, carbsG.isFinite else {
            return .suppressed(.noCarbTotal)
        }

        // 2. Band and ratio, from the meal's own instant on the supplied
        //    calendar (Req 2.2, 2.4).
        let band = DoseBand.band(at: inputs.mealInstant, calendar: inputs.calendar)
        let (ratio, isSeed) = inputs.ratios.ratio(for: band)

        let context = SuggestionContext(
            band: band, gramsPerUnit: ratio.gramsPerUnit, ratioIsSeed: isSeed)

        // 3. carbs ÷ ratio. No fat, correction, confidence or activity term
        //    enters this line (Req 3.8) — that is the point, not an omission.
        let base = carbsG / ratio.gramsPerUnit

        // 4. The reduction, capped at the base so the working's lines sum
        //    exactly at every step (Req 6.12); `exact` is then ≥ 0 by
        //    construction, which is Req 3.1's zero floor.
        //
        //    A non-finite insulin-on-board reduces the whole base, giving
        //    `0 U`. It is not reachable from the app's own writes — the dose
        //    sheet holds units as an Int clamped 1...60 — but the arithmetic
        //    must not depend on that: NaN would propagate through the rounding
        //    into the seed's Int conversion and trap. Reducing to zero is the
        //    one direction that cannot invent insulin.
        let unoffset = inputs.unoffsetIOBUnits.isFinite
            ? max(0, inputs.unoffsetIOBUnits) : base
        let reduction = min(unoffset, base)
        let exact = base - reduction

        // 5. Rounded half away from zero, applied ONCE to the final value,
        //    never to the carbohydrate term or the reduction separately
        //    (Req 5.1, 5.2). A rounded 0 is a result to render (Req 3.4).
        let increment = inputs.increment.units
        let rounded = (exact / increment).rounded(.toNearestOrAwayFromZero) * increment

        // 6. Seed the control, flagging a clamp. `exactUnits` passes to the
        //    working unchanged either way (Req 5.5).
        let seedWasClamped = rounded > inputs.bounds.maximumUnits
        let seedUnits = rounded == 0
            ? 0 : Int(min(rounded, inputs.bounds.maximumUnits).rounded())

        return .suggested(
            SuggestedDose(
                baseUnits: base,
                reductionUnits: reduction,
                exactUnits: exact,
                roundedUnits: rounded,
                seedUnits: seedUnits,
                seedWasClamped: seedWasClamped,
                context: context))
    }
}
