import Foundation
import Testing

@testable import Dosing

// Maths tests for the pure dose calculator (specs/data/insulin-dosing).
// Everything here is a pure function over supplied values — no store, no
// clock, no UI.

private func calendar(_ identifier: String) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: identifier)!
    return cal
}

private func instant(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

@Suite("Carbohydrate ratio direction and bounds")
struct CarbRatioTests {
    @Test("Rejects values outside the permitted interval and non-finite values")
    func rejects() {
        #expect(CarbRatio(gramsPerUnit: 0.9) == nil)
        #expect(CarbRatio(gramsPerUnit: 60.1) == nil)
        #expect(CarbRatio(gramsPerUnit: .nan) == nil)
        #expect(CarbRatio(gramsPerUnit: .infinity) == nil)
        #expect(CarbRatio(gramsPerUnit: 1.0) != nil)
        #expect(CarbRatio(gramsPerUnit: 60.0) != nil)
    }

    // The developer's phrasing "2 U per 10 g in the morning" IS 5.0 g/U
    // (Decision 13). This is the reciprocal trap, asserted.
    @Test("5.0 g/U renders as 2.0 U per 10 g, and the reciprocal is display-only")
    func reciprocal() {
        #expect(CarbRatio(gramsPerUnit: 5.0)!.unitsPerTenGrams == 2.0)
        #expect(CarbRatio(gramsPerUnit: 10.0)!.unitsPerTenGrams == 1.0)
    }

    @Test("An unconfigured band falls back to its seed and reports it")
    func seedFallback() {
        let table = CarbRatioTable(configured: [.dinner: CarbRatio(gramsPerUnit: 8.0)!])
        let breakfast = table.ratio(for: .breakfast)
        #expect(breakfast.value.gramsPerUnit == 5.0)
        #expect(breakfast.isSeed)
        let dinner = table.ratio(for: .dinner)
        #expect(dinner.value.gramsPerUnit == 8.0)
        #expect(!dinner.isSeed)
    }
}

@Suite("Time bands")
struct DoseBandTests {
    @Test(
        "The boundary hour opens the band it starts",
        arguments: [
            ("2026-08-14T00:00:00Z", DoseBand.overnight),
            ("2026-08-14T05:59:00Z", DoseBand.overnight),
            ("2026-08-14T06:00:00Z", DoseBand.breakfast),
            ("2026-08-14T10:59:00Z", DoseBand.breakfast),
            ("2026-08-14T11:00:00Z", DoseBand.lunch),
            ("2026-08-14T15:59:00Z", DoseBand.lunch),
            ("2026-08-14T16:00:00Z", DoseBand.dinner),
            ("2026-08-14T23:59:00Z", DoseBand.dinner)
        ]
    )
    func boundaries(iso: String, expected: DoseBand) {
        #expect(DoseBand.band(at: instant(iso), calendar: calendar("UTC")) == expected)
    }

    // The band follows the wall clock the person read, not UTC — and the
    // recorded pair measures the disagreement (Req 2.5).
    @Test("A non-UTC zone bands on local time and records both hours")
    func nonUTC() {
        let date = instant("2026-08-14T23:30:00Z")  // 09:30 next day in Sydney
        let sydney = calendar("Australia/Sydney")
        #expect(DoseBand.band(at: date, calendar: sydney) == .breakfast)
        let clock = BandClock(instant: date, calendar: sydney)
        #expect(clock.localHour == 9)
        #expect(clock.utcHour == 23)
        #expect(clock.utcOffsetSeconds == 36000)
    }
}

@Suite("Insulin on board")
struct InsulinOnBoardTests {
    // The shared cross-repository fixture table (design.md, Req 4.6),
    // produced by medreg's ExponentialInsulinModel. Asserted to 1e-4, well
    // inside the 0.01 U tolerance the requirement sets.
    @Test(
        "The rapid-acting curve matches medreg's fixtures",
        arguments: [
            (0.0, 1.000000), (30.0, 0.929521), (75.0, 0.694263), (120.0, 0.449752),
            (180.0, 0.208171), (240.0, 0.072666), (300.0, 0.013918), (360.0, 0.000000)
        ]
    )
    func fixtures(minutes: Double, expected: Double) {
        let actual = InsulinActivityModel.rapidActing.remainingFraction(after: minutes)
        #expect(abs(actual - expected) < 1e-4)
    }

    @Test("A dose at exactly the duration of action contributes zero")
    func atDuration() {
        let sum = insulinOnBoard([BolusHistoryEntry(minutesBefore: 360, units: 12)])
        #expect(sum == 0)
    }

    @Test("Empty history yields zero rather than an error")
    func empty() {
        #expect(insulinOnBoard([]) == 0)
    }

    @Test("Contributions sum over multiple boluses")
    func sums() {
        let sum = insulinOnBoard([
            BolusHistoryEntry(minutesBefore: 120, units: 10),
            BolusHistoryEntry(minutesBefore: 240, units: 6)
        ])
        #expect(abs(sum - (10 * 0.449752 + 6 * 0.072666)) < 1e-3)
    }
}

@Suite("The suggester")
struct DoseSuggesterTests {
    private func inputs(
        carbsG: Double?,
        at iso: String = "2026-08-14T08:41:00Z",
        iob: Double = 0,
        increment: Double = 1.0
    ) -> DoseInputs {
        DoseInputs(
            carbsG: carbsG,
            mealInstant: instant(iso),
            calendar: calendar("UTC"),
            ratios: CarbRatioTable(configured: [:]),
            iobUnits: iob,
            increment: DosableIncrement(units: increment)!
        )
    }

    // The worked figure throughout the spec: 60 g at breakfast, seed 5.0 g/U.
    @Test("60 g at breakfast on the 5.0 g/U seed is 12 U")
    func workedExample() {
        guard case .suggested(let dose) = DoseSuggester.suggest(inputs(carbsG: 60)) else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(dose.exactUnits == 12.0)
        #expect(dose.roundedUnits == 12.0)
        #expect(dose.seedUnits == 12)
        #expect(dose.context.band == .breakfast)
        #expect(dose.context.ratio.gramsPerUnit == 5.0)
        #expect(dose.context.ratioWasSeed)
    }

    @Test("108 g at dinner on the 10.0 g/U seed rounds 10.8 to 11 U")
    func dinnerRounding() {
        guard case .suggested(let dose) =
            DoseSuggester.suggest(inputs(carbsG: 108, at: "2026-08-14T18:20:00Z"))
        else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(abs(dose.exactUnits - 10.8) < 1e-9)
        #expect(dose.roundedUnits == 11.0)
        #expect(dose.context.band == .dinner)
    }

    // A 3 g quick-add at 10 g/U is 0.30 U and must not become a 1 U dose
    // invented by the stepper's floor (Req 3.4).
    @Test("A 3 g quick-add at lunch is suppressed, not clamped up")
    func tinyIntake() {
        let outcome = DoseSuggester.suggest(inputs(carbsG: 3, at: "2026-08-14T12:02:00Z"))
        #expect(outcome == .suppressed(.belowMeaningfulDose, context: context(of: outcome)))
    }

    @Test("Suppression is tested on the unrounded value at exactly 0.49 and 0.50")
    func meaningfulBoundary() {
        // 4.9 g ÷ 10 g/U = 0.49 U; 5.0 g ÷ 10 g/U = 0.50 U.
        let below = DoseSuggester.suggest(inputs(carbsG: 4.9, at: "2026-08-14T12:00:00Z"))
        if case .suggested = below { Issue.record("0.49 U should suppress") }
        let atFloor = DoseSuggester.suggest(inputs(carbsG: 5.0, at: "2026-08-14T12:00:00Z"))
        guard case .suggested(let dose) = atFloor else {
            Issue.record("0.50 U should suggest")
            return
        }
        #expect(dose.roundedUnits == 1.0)  // rounds half away from zero
    }

    // At a 0.5 U increment, 0.5–0.74 U rounds to 0.5 — below the stepper's
    // 1 U floor (Req 5.4).
    @Test("A half-unit result below the control floor is suppressed")
    func belowControlMinimum() {
        let outcome = DoseSuggester.suggest(
            inputs(carbsG: 6, at: "2026-08-14T12:00:00Z", increment: 0.5)
        )
        if case .suggested = outcome { Issue.record("0.5 U is below the 1 U stepper floor") }
    }

    // Rounding is applied ONCE, to the final value (Req 5.2): rounding the
    // carb term and the insulin-on-board term separately would give 12 − 2 =
    // 10, not 11.
    @Test("Rounding is applied once, to the final value")
    func roundsOnce() {
        guard case .suggested(let dose) =
            DoseSuggester.suggest(inputs(carbsG: 57.5, iob: 1.5))
        else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(abs(dose.exactUnits - 10.0) < 1e-9)  // 11.5 − 1.5
        #expect(dose.roundedUnits == 10.0)
    }

    @Test("Insulin on board can never drive the result below zero")
    func iobFloor() {
        let outcome = DoseSuggester.suggest(inputs(carbsG: 20, iob: 99))
        if case .suggested = outcome { Issue.record("expected suppression") }
    }

    @Test("A result above the control maximum clamps the seed and keeps exactUnits")
    func clamping() {
        guard case .suggested(let dose) =
            DoseSuggester.suggest(inputs(carbsG: 400, at: "2026-08-14T18:00:00Z"))
        else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(dose.exactUnits == 40.0)
        #expect(!dose.seedWasClamped)
        guard case .suggested(let big) =
            DoseSuggester.suggest(inputs(carbsG: 800, at: "2026-08-14T18:00:00Z"))
        else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(big.exactUnits == 80.0)
        #expect(big.seedUnits == 60)
        #expect(big.seedWasClamped)
    }

    @Test("An absent carbohydrate total is suppressed, never defaulted to zero")
    func absentCarbs() {
        let outcome = DoseSuggester.suggest(inputs(carbsG: nil))
        #expect(outcome == .suppressed(.noCarbTotal, context: context(of: outcome)))
    }

    @Test("Repeated identical inputs give an identical result")
    func deterministic() {
        let first = DoseSuggester.suggest(inputs(carbsG: 73, iob: 2.25))
        let second = DoseSuggester.suggest(inputs(carbsG: 73, iob: 2.25))
        #expect(first == second)
    }

    private func context(of outcome: DoseOutcome) -> SuggestionContext {
        switch outcome {
        case .suggested(let dose): dose.context
        case .suppressed(_, let context): context
        }
    }
}
