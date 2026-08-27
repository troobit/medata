import Foundation
import Testing

@testable import Dosing

// Unoffset membership (specs/data/insulin-dosing Req 4.8, Decisions 17/18).
//
// A bolus is offset by food when a logged meal or carbohydrate intake sits
// within 45 minutes EITHER SIDE of it — the symmetric window deliberately
// covers pre-bolusing. Offset boluses never reduce a later meal's coverage;
// only the freestanding remainder does.
@Suite("Food-offset membership")
struct FoodOffsetTests {

    private let subject = Date(timeIntervalSince1970: 1_786_000_000)

    private func minutes(_ value: Double) -> TimeInterval { value * 60 }

    /// An instant `value` minutes before the subject meal.
    private func before(_ value: Double) -> Date {
        subject.addingTimeInterval(-minutes(value))
    }

    // MARK: - The predicate (Req 4.8)

    @Test("A bolus with no meal or intake near it is freestanding, so it counts")
    func freestandingCorrectionCounts() {
        let bolus = before(120)
        let meals = [before(400), subject.addingTimeInterval(minutes(600))]

        #expect(isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: meals) == false)
    }

    @Test("A bolus taken just after a meal is offset by it")
    func bolusAfterMealIsOffset() {
        let meal = before(130)
        let bolus = before(120)  // 10 minutes after the meal

        #expect(isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [meal]) == true)
    }

    // The symmetric half is the whole reason the window is not forward-only:
    // insulin taken 20 minutes BEFORE eating is a pre-bolus, and the food it
    // covers has already been logged.
    @Test("A pre-bolus 20 minutes before a meal is offset by that meal")
    func preBolusIsOffset() {
        let meal = before(100)
        let bolus = before(120)  // 20 minutes before the meal

        #expect(isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [meal]) == true)
    }

    @Test("The ±45-minute boundary is inclusive on both sides")
    func boundaryIsInclusive() {
        let bolus = before(120)

        let exactlyAfter = bolus.addingTimeInterval(minutes(45))
        let exactlyBefore = bolus.addingTimeInterval(-minutes(45))
        let justOutsideAfter = bolus.addingTimeInterval(minutes(45.01))
        let justOutsideBefore = bolus.addingTimeInterval(-minutes(45.01))

        #expect(
            isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [exactlyAfter]) == true)
        #expect(
            isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [exactlyBefore]) == true)
        #expect(
            isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [justOutsideAfter])
                == false)
        #expect(
            isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: [justOutsideBefore])
                == false)
    }

    @Test("An empty food log offsets nothing")
    func emptyFoodLogOffsetsNothing() {
        #expect(isOffsetByFood(bolusInstant: before(30), mealOrIntakeInstants: []) == false)
    }

    @Test("Any one qualifying instant is enough")
    func anyInstantQualifies() {
        let bolus = before(120)
        let instants = [before(500), before(115), before(10)]

        #expect(isOffsetByFood(bolusInstant: bolus, mealOrIntakeInstants: instants) == true)
    }

    // MARK: - The unoffset sum (Req 3.1, 4.8)

    @Test("A meal followed by a snack each gets its own full coverage")
    func offsetBolusesDoNotReduceALaterMeal() {
        // 60 minutes ago: a meal, and the bolus that covered it.
        let earlierMeal = before(60)
        let boluses = [DatedBolus(instant: before(60), units: 6)]

        let unoffset = unoffsetInsulinOnBoard(
            boluses, mealOrIntakeInstants: [earlierMeal], at: subject)

        #expect(unoffset == 0)
    }

    @Test("A freestanding correction bolus reduces the next meal's coverage")
    func freestandingBolusContributes() {
        let boluses = [DatedBolus(instant: before(60), units: 6)]

        let unoffset = unoffsetInsulinOnBoard(boluses, mealOrIntakeInstants: [], at: subject)

        // 60 minutes into a 75-minute peak, most of the dose is still active.
        let expected = insulinOnBoard([BolusHistoryEntry(minutesBefore: 60, units: 6)])
        #expect(abs(unoffset - expected) < 1e-12)
        #expect(unoffset > 0)
    }

    @Test("Only the unoffset boluses are summed, on the same decay curve")
    func mixedHistorySumsOnlyTheUnoffsetShare() {
        let mealCovered = DatedBolus(instant: before(90), units: 8)
        let correction = DatedBolus(instant: before(30), units: 2)
        let meals = [before(85)]

        let unoffset = unoffsetInsulinOnBoard(
            [mealCovered, correction], mealOrIntakeInstants: meals, at: subject)

        let expected = insulinOnBoard([BolusHistoryEntry(minutesBefore: 30, units: 2)])
        #expect(abs(unoffset - expected) < 1e-12)
    }

    @Test("A bolus older than the duration of action contributes zero")
    func expiredBolusContributesZero() {
        let boluses = [DatedBolus(instant: before(400), units: 10)]

        #expect(unoffsetInsulinOnBoard(boluses, mealOrIntakeInstants: [], at: subject) == 0)
    }

    @Test("An empty bolus history is an ordinary answer of zero")
    func emptyHistoryIsZero() {
        #expect(unoffsetInsulinOnBoard([], mealOrIntakeInstants: [], at: subject) == 0)
    }

    // MARK: - The spans a caller must query (design "Data flow" step 2)

    @Test("The bolus span is exactly the duration of action, back from the subject")
    func bolusSpan() {
        let span = FoodOffsetWindow.bolusSpan(at: subject)

        #expect(span.lowerBound == subject.addingTimeInterval(-minutes(360)))
        #expect(span.upperBound == subject)
    }

    // The bolus span widened by the association window at BOTH ends, because
    // the ±45-minute test is symmetric: a meal 30 minutes AFTER the subject
    // instant can still offset a bolus that fell before it.
    @Test("The food span widens the bolus span by 45 minutes at both ends")
    func foodSpan() {
        let span = FoodOffsetWindow.mealOrIntakeSpan(at: subject)

        #expect(span.lowerBound == subject.addingTimeInterval(-minutes(360 + 45)))
        #expect(span.upperBound == subject.addingTimeInterval(minutes(45)))
    }

    // One association rule, not three: the same 45 minutes as the seed
    // lifetime and the Req 11.2 pairing window.
    @Test("The window constant is 45 minutes")
    func windowConstant() {
        #expect(FoodOffsetWindow.window == 45 * 60)
    }
}
