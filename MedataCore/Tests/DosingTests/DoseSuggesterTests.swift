import Foundation
import Testing

@testable import Dosing

// The seven ordered steps (specs/data/insulin-dosing Req 3, 5, Decision 7).
// Every instant is built from an explicit UTC calendar so the band is decided
// by the hour written here and nothing else.
@Suite("DoseSuggester")
struct DoseSuggesterTests {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func at(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 14
        components.hour = hour
        return utc.date(from: components)!
    }

    private func inputs(
        carbsG: Double?,
        hour: Int = 8,
        iobUnits: Double = 0,
        incrementUnits: Double = 1.0,
        ratios: CarbRatioTable = CarbRatioTable()
    ) -> DoseInputs {
        DoseInputs(
            carbsG: carbsG,
            mealInstant: at(hour: hour),
            calendar: utc,
            ratios: ratios,
            iobUnits: iobUnits,
            increment: DosableIncrement(units: incrementUnits)!,
            bounds: .doseSheet)
    }

    private func suggested(_ outcome: DoseOutcome) throws -> SuggestedDose {
        guard case .suggested(let dose) = outcome else {
            Issue.record("expected a suggestion, got \(outcome)")
            throw DoseSuggesterTestError.notSuggested
        }
        return dose
    }

    private enum DoseSuggesterTestError: Error { case notSuggested }

    // MARK: - The direction of the ratio (Req 1.1, 3.1)

    // The developer's rule is "2 U per 10 g in the morning", which IS 5.0 g/U.
    // A 60 g breakfast on that ratio is 12 U — carbs DIVIDED by grams per
    // unit. If this assertion ever reads 300, the ratio has been inverted.
    @Test("A 60 g breakfast at the 5.0 g/U seed suggests 12 U")
    func breakfastArithmetic() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 60, hour: 8)))

        #expect(dose.context.band == .breakfast)
        #expect(dose.context.gramsPerUnit == 5.0)
        #expect(dose.context.ratioIsSeed == true)
        #expect(abs(dose.exactUnits - 12.0) < 1e-12)
        #expect(dose.roundedUnits == 12.0)
        #expect(dose.seedUnits == 12)
        #expect(dose.seedWasClamped == false)
    }

    // The same 60 g at lunch falls on the 10.0 g/U seed and halves.
    @Test("The same 60 g at lunch suggests 6 U on the 10.0 g/U seed")
    func lunchArithmetic() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 60, hour: 13)))

        #expect(dose.context.band == .lunch)
        #expect(dose.context.gramsPerUnit == 10.0)
        #expect(abs(dose.exactUnits - 6.0) < 1e-12)
        #expect(dose.seedUnits == 6)
    }

    // MARK: - No carbohydrate total (Req 3.5)

    @Test("An absent carbohydrate total suppresses rather than defaulting")
    func absentCarbsSuppress() {
        guard case .suppressed(let reason, let context) =
            DoseSuggester.suggest(inputs(carbsG: nil, hour: 8, iobUnits: 2.5))
        else {
            Issue.record("expected a suppression")
            return
        }
        #expect(reason == .noCarbTotal)
        // A suppression is recorded as fully as a suggestion (Req 7.1).
        #expect(context.band == .breakfast)
        #expect(context.localHour == 8)
        #expect(context.utcHour == 8)
        #expect(context.utcOffsetSeconds == 0)
        #expect(context.gramsPerUnit == 5.0)
        #expect(context.ratioIsSeed == true)
        #expect(context.iobUnits == 2.5)
        #expect(context.incrementUnits == 1.0)
    }

    // MARK: - The half-unit floor, tested unrounded (Req 3.4)

    @Test("An exact 0.49 U is suppressed")
    func justBelowTheFloorSuppressed() {
        guard case .suppressed(let reason, _) =
            DoseSuggester.suggest(inputs(carbsG: 4.9, hour: 13))
        else {
            Issue.record("expected a suppression")
            return
        }
        #expect(reason == .belowMeaningfulDose)
    }

    @Test("An exact 0.50 U is suggested and rounds up to the control floor")
    func exactlyAtTheFloorSuggested() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 5.0, hour: 13)))

        #expect(abs(dose.exactUnits - 0.5) < 1e-12)
        #expect(dose.roundedUnits == 1.0)
        #expect(dose.seedUnits == 1)
    }

    // The dangerous case: 0.30 U must produce nothing, not a 1 U dose invented
    // by the stepper's floor.
    @Test("A 3 g quick-add at 10 g/U is suppressed rather than clamped up")
    func smallQuickAddSuppressedNotClamped() {
        let outcome = DoseSuggester.suggest(inputs(carbsG: 3, hour: 13))

        guard case .suppressed(let reason, let context) = outcome else {
            Issue.record("expected a suppression, got \(outcome)")
            return
        }
        #expect(reason == .belowMeaningfulDose)
        #expect(context.gramsPerUnit == 10.0)
    }

    @Test("Insulin-on-board exceeding the carbohydrate term floors at zero")
    func iobFloorsAtZero() {
        guard case .suppressed(let reason, _) =
            DoseSuggester.suggest(inputs(carbsG: 20, hour: 13, iobUnits: 9))
        else {
            Issue.record("expected a suppression")
            return
        }
        #expect(reason == .belowMeaningfulDose)
    }

    // MARK: - Rounding half away from zero, applied once (Req 5.2)

    @Test("At a 1 U increment a midpoint rounds to the larger increment")
    func roundsHalfAwayAtWholeUnits() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 25, hour: 13)))

        #expect(abs(dose.exactUnits - 2.5) < 1e-12)
        #expect(dose.roundedUnits == 3.0)
        #expect(dose.seedUnits == 3)
    }

    @Test("At a 0.5 U increment a midpoint rounds to the larger increment")
    func roundsHalfAwayAtHalfUnits() throws {
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 27.5, hour: 13, incrementUnits: 0.5)))

        #expect(abs(dose.exactUnits - 2.75) < 1e-12)
        #expect(dose.roundedUnits == 3.0)
        // Req 5.7: the increment is finer than the control, so the seed rounds
        // again to what the control can represent while exactUnits is kept.
        #expect(dose.seedUnits == 3)
    }

    @Test("A 0.5 U increment keeps a half-unit result the control cannot show")
    func halfUnitResultKeepsPrecision() throws {
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 22.5, hour: 13, incrementUnits: 0.5)))

        #expect(abs(dose.exactUnits - 2.25) < 1e-12)
        #expect(dose.roundedUnits == 2.5)
        #expect(dose.seedUnits == 3)
    }

    // 27 g at 10 g/U is 2.7 U and insulin-on-board is 1.4 U. Rounding once, at
    // the end, gives 1 U. Rounding the two terms separately would give 3 − 1 =
    // 2 U — a whole extra unit, from the rounding alone.
    @Test("Rounding is applied once to the final value, not to each term")
    func roundingAppliedOnce() throws {
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 27, hour: 13, iobUnits: 1.4)))

        let roundedSeparately =
            (2.7).rounded(.toNearestOrAwayFromZero) - (1.4).rounded(.toNearestOrAwayFromZero)
        #expect(roundedSeparately == 2.0)

        #expect(abs(dose.exactUnits - 1.3) < 1e-9)
        #expect(dose.roundedUnits == 1.0)
        #expect(dose.seedUnits == 1)
    }

    // MARK: - The control's floor and ceiling (Req 5.4, 5.5)

    // Reachable only at a 0.5 U increment: 0.6 U clears the half-unit floor,
    // rounds to 0.5 U, and 0.5 U is below the stepper's minimum of 1 U.
    @Test("A rounded value below the control minimum suppresses rather than clamping up")
    func belowControlMinimumSuppresses() {
        let outcome = DoseSuggester.suggest(inputs(carbsG: 6, hour: 13, incrementUnits: 0.5))

        guard case .suppressed(let reason, _) = outcome else {
            Issue.record("expected a suppression, got \(outcome)")
            return
        }
        #expect(reason == .belowControlMinimum)
    }

    @Test("A value above the control maximum clamps the seed and keeps exactUnits")
    func aboveControlMaximumClamps() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 400, hour: 8)))

        #expect(abs(dose.exactUnits - 80.0) < 1e-12)
        #expect(dose.roundedUnits == 80.0)
        #expect(dose.seedUnits == 60)
        #expect(dose.seedWasClamped == true)
    }

    @Test("A value at the control maximum is not flagged as clamped")
    func atControlMaximumIsNotClamped() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 300, hour: 8)))

        #expect(dose.roundedUnits == 60.0)
        #expect(dose.seedUnits == 60)
        #expect(dose.seedWasClamped == false)
    }

    // MARK: - Determinism (Req 3.6, 10.2)

    @Test("Identical inputs always yield the identical outcome")
    func deterministic() {
        let carbs = 63.4
        let first = DoseSuggester.suggest(inputs(carbsG: carbs, hour: 8, iobUnits: 2.25))
        for _ in 0..<10 {
            #expect(DoseSuggester.suggest(inputs(carbsG: carbs, hour: 8, iobUnits: 2.25)) == first)
        }
    }

    // MARK: - Configured ratios (Req 1.6, 1.7)

    @Test("A configured band ratio overrides its seed and is reported as configured")
    func configuredRatioOverridesSeed() throws {
        let table = CarbRatioTable(configured: [.breakfast: CarbRatio(gramsPerUnit: 4.0)!])
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 60, hour: 8, ratios: table)))

        #expect(dose.context.gramsPerUnit == 4.0)
        #expect(dose.context.ratioIsSeed == false)
        #expect(abs(dose.exactUnits - 15.0) < 1e-12)
        #expect(dose.seedUnits == 15)
    }

    // MARK: - The increment is a fixed set (Req 5.6)

    @Test("Only 0.5 and 1.0 are accepted as dosable increments")
    func incrementIsAFixedSet() {
        #expect(DosableIncrement(units: 0.5) != nil)
        #expect(DosableIncrement(units: 1.0) != nil)
        #expect(DosableIncrement(units: 0.1) == nil)
        #expect(DosableIncrement(units: 2.0) == nil)
        #expect(DosableIncrement(units: 0) == nil)
        #expect(DosableIncrement(units: .nan) == nil)
        #expect(DosableIncrement.standard.units == 1.0)
    }
}
