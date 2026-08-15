import Foundation
import Testing

@testable import Dosing

// The maths the app-layer readout and seed depend on. Kept deliberately
// narrow: the exhaustive band/rounding/clamping matrix belongs to
// specs/data/insulin-dosing tasks 2.1–5.1, which build the same target.
// What is asserted here is the direction of the ratio and the two numbers
// every worked example in the spec quotes.

private func utcCalendar(hour: Int) -> (Calendar, Date) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 14
    components.hour = hour
    return (calendar, calendar.date(from: components)!)
}

@Suite("Carbohydrate ratio direction")
struct CarbRatioDirectionTests {
    @Test("2 U per 10 g is 5.0 g/U and renders back as 2.0")
    func reciprocalRenders() throws {
        let ratio = try #require(CarbRatio(gramsPerUnit: 5.0))
        #expect(abs(ratio.unitsPerTenGrams - 2.0) < 1e-12)
        let gentle = try #require(CarbRatio(gramsPerUnit: 10.0))
        #expect(abs(gentle.unitsPerTenGrams - 1.0) < 1e-12)
    }

    @Test("Bounds reject outside 1...60 and both endpoints are accepted")
    func bounds() {
        #expect(CarbRatio(gramsPerUnit: 0.9) == nil)
        #expect(CarbRatio(gramsPerUnit: 60.1) == nil)
        #expect(CarbRatio(gramsPerUnit: .nan) == nil)
        #expect(CarbRatio(gramsPerUnit: .infinity) == nil)
        #expect(CarbRatio(gramsPerUnit: 1.0) != nil)
        #expect(CarbRatio(gramsPerUnit: 60.0) != nil)
    }

    @Test("An unconfigured band falls back to its seed and says so")
    func seedFallback() {
        let table = CarbRatioTable(configured: [:])
        let breakfast = table.ratio(for: .breakfast)
        #expect(breakfast.value.gramsPerUnit == 5.0)
        #expect(breakfast.isSeed)
        let dinner = table.ratio(for: .dinner)
        #expect(dinner.value.gramsPerUnit == 10.0)
        #expect(dinner.isSeed)
    }
}

@Suite("Insulin on board")
struct InsulinOnBoardTests {
    // The shared cross-repository fixture set (design.md, Req 4.6), asserted
    // to 1e-4 — well inside the 0.01 U tolerance the requirement sets.
    @Test(
        "Rapid-acting remaining fraction matches the shared fixture table",
        arguments: [
            (0.0, 1.000000), (30.0, 0.929521), (75.0, 0.694263), (120.0, 0.449752),
            (180.0, 0.208171), (240.0, 0.072666), (300.0, 0.013918), (360.0, 0.000000)
        ]
    )
    func fixtureTable(minutes: Double, expected: Double) {
        let actual = InsulinActivityModel.rapidActing.remainingFraction(after: minutes)
        #expect(abs(actual - expected) < 1e-4)
    }

    @Test("A dose at exactly the duration of action contributes nothing")
    func expiredDose() {
        let iob = insulinOnBoard([BolusHistoryEntry(minutesBefore: 360, units: 10)])
        #expect(iob == 0)
    }
}

@Suite("Dose suggester")
struct DoseSuggesterTests {
    @Test("60 g at breakfast is 12 U")
    func workedBreakfast() throws {
        let (calendar, instant) = utcCalendar(hour: 8)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: 60, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 0
            )
        )
        guard case .suggested(let dose) = outcome else {
            Issue.record("expected a suggestion, got \(outcome)")
            return
        }
        #expect(dose.context.band == .breakfast)
        #expect(dose.context.carbRatioGPerU == 5.0)
        #expect(abs(dose.exactUnits - 12.0) < 1e-12)
        #expect(dose.seedUnits == 12)
        #expect(!dose.seedWasClamped)
    }

    @Test("108 g at dinner rounds 10.8 up to 11 U")
    func workedDinner() {
        let (calendar, instant) = utcCalendar(hour: 18)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: 108, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 0
            )
        )
        guard case .suggested(let dose) = outcome else {
            Issue.record("expected a suggestion, got \(outcome)")
            return
        }
        #expect(dose.context.band == .dinner)
        #expect(dose.roundedUnits == 11)
    }

    @Test("A 3 g quick-add at 10 g/U is suppressed, not floored up to 1 U")
    func belowMeaningful() {
        let (calendar, instant) = utcCalendar(hour: 12)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: 3, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 0
            )
        )
        #expect(outcome == .suppressed(.belowMeaningfulDose, context: outcome.context))
    }

    @Test("An absent carbohydrate total is suppressed, never defaulted")
    func absentCarbs() {
        let (calendar, instant) = utcCalendar(hour: 12)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: nil, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 0
            )
        )
        #expect(outcome == .suppressed(.noCarbTotal, context: outcome.context))
    }

    @Test("Above the stepper ceiling the seed clamps but exactUnits survives")
    func clamping() {
        let (calendar, instant) = utcCalendar(hour: 18)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: 900, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 0
            )
        )
        guard case .suggested(let dose) = outcome else {
            Issue.record("expected a suggestion, got \(outcome)")
            return
        }
        #expect(dose.exactUnits == 90)
        #expect(dose.seedUnits == 60)
        #expect(dose.seedWasClamped)
    }

    @Test("Insulin on board is subtracted before the single rounding step")
    func iobSubtraction() {
        let (calendar, instant) = utcCalendar(hour: 8)
        let outcome = DoseSuggester.suggest(
            DoseInputs(
                carbsG: 60, mealInstant: instant, calendar: calendar,
                ratios: CarbRatioTable(configured: [:]), iobUnits: 1.8
            )
        )
        guard case .suggested(let dose) = outcome else {
            Issue.record("expected a suggestion, got \(outcome)")
            return
        }
        #expect(abs(dose.exactUnits - 10.2) < 1e-12)
        #expect(dose.roundedUnits == 10)
    }
}
