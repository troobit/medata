import Foundation
import Testing

@testable import Dosing

// The cross-repository contract (specs/data/insulin-dosing Req 4.6, 9.8). The
// fixture table below is produced by
// `~/repos/medreg/src/medreg/models/insulin.py::ExponentialInsulinModel.iob`
// under the RAPID_ACTING preset and is reproduced verbatim in design.md. It is
// asserted to 1e-4 here, well inside the 0.01 U tolerance the requirement sets
// — a disagreement beyond that is a defect in one of the two implementations,
// not a tolerance to be widened.
@Suite("InsulinActivityModel")
struct InsulinActivityModelTests {

    private let model = InsulinActivityModel.rapidActing

    private static let fixture: [(minutes: Double, remaining: Double)] = [
        (0, 1.000000),
        (30, 0.929521),
        (75, 0.694263),
        (120, 0.449752),
        (180, 0.208171),
        (240, 0.072666),
        (300, 0.013918),
        (360, 0.000000)
    ]

    // MARK: - The shared fixture set (Req 4.6)

    @Test("The rapid-acting preset is medreg's: peak 75 min, duration 360 min")
    func presetMatchesMedreg() {
        #expect(model.peakMinutes == 75)
        #expect(model.durationMinutes == 360)
    }

    @Test("remainingFraction matches medreg's curve", arguments: InsulinActivityModelTests.fixture)
    func remainingFractionMatchesFixture(minutes: Double, remaining: Double) {
        #expect(abs(model.remainingFraction(after: minutes) - remaining) < 1e-4)
    }

    @Test("The curve is 1.0 at or before delivery")
    func fullBeforeDelivery() {
        #expect(model.remainingFraction(after: 0) == 1.0)
        #expect(model.remainingFraction(after: -1) == 1.0)
        #expect(model.remainingFraction(after: -600) == 1.0)
    }

    @Test("The curve is 0.0 at or beyond the duration of action")
    func emptyAtAndBeyondDuration() {
        #expect(model.remainingFraction(after: 360) == 0.0)
        #expect(model.remainingFraction(after: 361) == 0.0)
        #expect(model.remainingFraction(after: 10_000) == 0.0)
    }

    @Test("The curve is monotonically non-increasing across the duration")
    func monotonicallyNonIncreasing() {
        var previous = model.remainingFraction(after: 0)
        for minute in stride(from: 1.0, through: 400.0, by: 1.0) {
            let current = model.remainingFraction(after: minute)
            #expect(current <= previous + 1e-12)
            previous = current
        }
    }

    // MARK: - Summation (Req 4.2, 4.3, 4.4)

    @Test("An empty history yields zero and is not an error")
    func emptyHistoryIsZero() {
        #expect(insulinOnBoard([]) == 0)
    }

    @Test("Doses sum as units times remaining fraction")
    func dosesSum() {
        let boluses = [
            BolusHistoryEntry(minutesBefore: 30, units: 6),
            BolusHistoryEntry(minutesBefore: 180, units: 4)
        ]
        let expected = 6 * 0.929521 + 4 * 0.208171
        #expect(abs(insulinOnBoard(boluses) - expected) < 1e-4)
    }

    // Basal never appears in the array: the caller filters by kind before
    // building it, exactly as `bolus_iob` skips a dose whose kind is not
    // BOLUS. The assertion here is that a basal-sized dose left out changes
    // nothing about what the sum returns for the boluses that remain.
    @Test("Excluding basal from the array leaves the bolus sum untouched")
    func basalExcludedFromTheSum() {
        let bolusesOnly = [BolusHistoryEntry(minutesBefore: 60, units: 5)]
        let withBasalIncluded =
            bolusesOnly + [BolusHistoryEntry(minutesBefore: 60, units: 15)]

        #expect(insulinOnBoard(bolusesOnly) < insulinOnBoard(withBasalIncluded))
        #expect(
            abs(insulinOnBoard(bolusesOnly) - 5 * model.remainingFraction(after: 60)) < 1e-12)
    }

    @Test("A dose at exactly the duration of action contributes zero")
    func doseAtDurationContributesZero() {
        #expect(insulinOnBoard([BolusHistoryEntry(minutesBefore: 360, units: 10)]) == 0)
        #expect(insulinOnBoard([BolusHistoryEntry(minutesBefore: 361, units: 10)]) == 0)
    }

    @Test("A dose in the future of the reference instant contributes zero")
    func futureDoseContributesZero() {
        #expect(insulinOnBoard([BolusHistoryEntry(minutesBefore: -5, units: 10)]) == 0)
    }
}
