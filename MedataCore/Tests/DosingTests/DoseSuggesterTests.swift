import Foundation
import Testing

@testable import Dosing

// The amended rule (specs/data/insulin-dosing Req 3, 5, Decisions 17/18):
// carbs ÷ ratio − unoffset insulin-on-board, floored at zero, rounded half away
// from zero ONCE on the final value, in whole units only. Every input with a
// carbohydrate total returns `.suggested` — `0 U` included.
//
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
        unoffsetIOBUnits: Double = 0,
        ratios: CarbRatioTable = CarbRatioTable()
    ) -> DoseInputs {
        DoseInputs(
            carbsG: carbsG,
            mealInstant: at(hour: hour),
            calendar: utc,
            ratios: ratios,
            unoffsetIOBUnits: unoffsetIOBUnits,
            increment: .standard,
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
        #expect(abs(dose.baseUnits - 12.0) < 1e-12)
        #expect(dose.reductionUnits == 0)
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

    // MARK: - No carbohydrate total, the sole suppression (Req 3.5)

    @Test("An absent carbohydrate total suppresses rather than defaulting")
    func absentCarbsSuppress() {
        let outcome = DoseSuggester.suggest(
            inputs(carbsG: nil, hour: 8, unoffsetIOBUnits: 2.5))

        // The suppression carries its typed reason and nothing else: no
        // context payload survives Decision 18.
        #expect(outcome == .suppressed(.noCarbTotal))
    }

    @Test("noCarbTotal is the only suppression reason there is")
    func oneSuppressionReasonOnly() {
        #expect(Set(SuppressionReason.allCases) == [.noCarbTotal])
    }

    // MARK: - Every carbohydrate total renders a number (Req 3.4)

    // The case that used to be `.belowMeaningfulDose`. A 3 g quick-add at
    // 10 g/U is 0.30 U: it renders `0 U` with its working inspectable, and it
    // arms no seed. Neither an absent readout nor a 1 U dose invented by the
    // stepper's floor.
    @Test("A 3 g quick-add at 10 g/U suggests 0 U and seeds nothing")
    func smallQuickAddRendersZero() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 3, hour: 13)))

        #expect(abs(dose.exactUnits - 0.3) < 1e-12)
        #expect(dose.roundedUnits == 0)
        #expect(dose.seedUnits == 0)
        #expect(dose.context.gramsPerUnit == 10.0)
    }

    // The case that used to be `.belowControlMinimum`: 0.49 U rounds to 0 U.
    @Test("An exact 0.49 U rounds to 0 U rather than suppressing")
    func justBelowTheHalfUnitRendersZero() throws {
        let dose = try suggested(DoseSuggester.suggest(inputs(carbsG: 4.9, hour: 13)))

        #expect(abs(dose.exactUnits - 0.49) < 1e-12)
        #expect(dose.roundedUnits == 0)
        #expect(dose.seedUnits == 0)
    }

    @Test("Unoffset insulin-on-board exceeding the carbohydrate term floors at 0 U")
    func unoffsetIOBFloorsAtZero() throws {
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 20, hour: 13, unoffsetIOBUnits: 9)))

        // The reduction is capped at the base so the working's lines still sum:
        // 2.0 − 2.0 = 0.0, never 2.0 − 9.0 = −7.0 displayed as 0.
        #expect(abs(dose.baseUnits - 2.0) < 1e-12)
        #expect(abs(dose.reductionUnits - 2.0) < 1e-12)
        #expect(dose.exactUnits == 0)
        #expect(dose.roundedUnits == 0)
        #expect(dose.seedUnits == 0)
    }

    // Not reachable from the app's own writes — the dose sheet holds units as
    // an Int clamped 1...60 — but the arithmetic must not depend on that: a
    // non-finite value would propagate through the rounding into the seed's
    // Int conversion and trap.
    @Test("A non-finite insulin-on-board yields 0 U rather than trapping")
    func nonFiniteIOBFloorsAtZero() throws {
        for iob in [Double.nan, .infinity] {
            let dose = try suggested(
                DoseSuggester.suggest(inputs(carbsG: 60, hour: 13, unoffsetIOBUnits: iob)))

            #expect(dose.exactUnits == 0)
            #expect(dose.roundedUnits == 0)
            #expect(dose.seedUnits == 0)
            #expect(dose.reductionUnits == dose.baseUnits)
        }
    }

    // MARK: - Rounding half away from zero, applied once (Req 5.1, 5.2)

    // Req 5.2's own three examples, driven through the carbohydrate term.
    @Test("3.5 U rounds to 4 U, 3.4 U to 3 U, and 0.6 U to 1 U")
    func req52Examples() throws {
        let midpoint = try suggested(DoseSuggester.suggest(inputs(carbsG: 35, hour: 13)))
        #expect(abs(midpoint.exactUnits - 3.5) < 1e-12)
        #expect(midpoint.roundedUnits == 4.0)
        #expect(midpoint.seedUnits == 4)

        let below = try suggested(DoseSuggester.suggest(inputs(carbsG: 34, hour: 13)))
        #expect(abs(below.exactUnits - 3.4) < 1e-12)
        #expect(below.roundedUnits == 3.0)

        // 0.6 U rounds UP to 1 U, and that 1 U renders and seeds: the round-up
        // at small carb loads is deliberate (Req 5.2, 3.4).
        let small = try suggested(DoseSuggester.suggest(inputs(carbsG: 6, hour: 13)))
        #expect(abs(small.exactUnits - 0.6) < 1e-12)
        #expect(small.roundedUnits == 1.0)
        #expect(small.seedUnits == 1)
    }

    // 27 g at 10 g/U is 2.7 U and the unoffset insulin-on-board is 1.4 U.
    // Rounding once, at the end, gives 1 U. Rounding the two terms separately
    // would give 3 − 1 = 2 U — a whole extra unit, from the rounding alone.
    @Test("Rounding is applied once to the final value, not to each term")
    func roundingAppliedOnce() throws {
        let dose = try suggested(
            DoseSuggester.suggest(inputs(carbsG: 27, hour: 13, unoffsetIOBUnits: 1.4)))

        let roundedSeparately =
            (2.7).rounded(.toNearestOrAwayFromZero) - (1.4).rounded(.toNearestOrAwayFromZero)
        #expect(roundedSeparately == 2.0)

        #expect(abs(dose.exactUnits - 1.3) < 1e-9)
        #expect(dose.roundedUnits == 1.0)
        #expect(dose.seedUnits == 1)
    }

    // MARK: - The working's lines sum exactly (Req 6.12)

    // The cap is what makes `base − reduction = exact` true at EVERY input,
    // not merely where the insulin-on-board happens to be smaller.
    @Test("base − reduction is exactly the unrounded result at every input")
    func workingLinesSumAtEveryInput() throws {
        for carbs in stride(from: 0.0, through: 120.0, by: 3.0) {
            for iob in stride(from: 0.0, through: 15.0, by: 1.5) {
                let dose = try suggested(
                    DoseSuggester.suggest(
                        inputs(carbsG: carbs, hour: 13, unoffsetIOBUnits: iob)))

                #expect(abs(dose.baseUnits - dose.reductionUnits - dose.exactUnits) < 1e-12)
                #expect(dose.reductionUnits <= dose.baseUnits + 1e-12)
                #expect(dose.reductionUnits >= 0)
                #expect(dose.exactUnits >= 0)
            }
        }
    }

    // MARK: - The control's floor and ceiling (Req 5.4, 5.5)

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
        let first = DoseSuggester.suggest(
            inputs(carbsG: carbs, hour: 8, unoffsetIOBUnits: 2.25))
        for _ in 0..<10 {
            #expect(
                DoseSuggester.suggest(inputs(carbsG: carbs, hour: 8, unoffsetIOBUnits: 2.25))
                    == first)
        }
    }

    // MARK: - Configured ratios (Req 1.6)

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

    // MARK: - Whole units only (Req 5.1)

    @Test("1 U is the only permitted increment — no half-unit path survives")
    func incrementIsWholeUnitsOnly() {
        #expect(DosableIncrement.permitted == [1.0])
        #expect(DosableIncrement(units: 1.0) != nil)
        #expect(DosableIncrement(units: 0.5) == nil)
        #expect(DosableIncrement(units: 0.1) == nil)
        #expect(DosableIncrement(units: 2.0) == nil)
        #expect(DosableIncrement(units: 0) == nil)
        #expect(DosableIncrement(units: .nan) == nil)
        #expect(DosableIncrement.standard.units == 1.0)
    }
}
