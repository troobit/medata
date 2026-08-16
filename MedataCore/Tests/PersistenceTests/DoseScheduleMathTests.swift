import Foundation
import XCTest
@testable import Persistence

// Tests for the pure schedule arithmetic (specs/data/dose-schedule design.md
// section 8). Every case constructs its own `Calendar` and its own `Date`: no
// test here may read the host clock or the host time zone, because the whole
// point of the free-function shape is that the answer does not depend on where
// or when the test runs.

final class DoseScheduleMathTests: XCTestCase {

    // Europe/Dublin: spring forward 2026-03-29 01:00 -> 02:00, back
    // 2026-10-25 02:00 -> 01:00. Both transitions are in the small hours, so a
    // 07:30 schedule crosses them without its wall-clock time being disturbed —
    // which is exactly the claim Req 1.6 makes.
    private func dublin() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        calendar.locale = Locale(identifier: "en_IE")
        return calendar
    }

    private func instant(
        _ calendar: Calendar,
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts)!
    }

    private func wallClock(_ calendar: Calendar, _ date: Date) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!
        )
    }

    private func basal(
        _ hour: Int, _ minute: Int, id: UUID = UUID(), enabled: Bool = true
    ) -> ScheduledDose {
        ScheduledDose(
            id: id, hour: hour, minute: minute, nominalUnits: 15,
            kind: .basal, isEnabled: enabled
        )
    }

    // MARK: - Next occurrence (Req 1.6, 2.1)

    func testNextDueDateIsTheSameDayWhenTheTimeHasNotPassed() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(7, 30),
            after: instant(calendar, 2026, 6, 1, 6, 0),
            calendar: calendar
        )
        XCTAssertEqual(wallClock(calendar, next!), "2026-06-01 07:30")
    }

    func testNextDueDateRollsToTomorrowOnceTheTimeHasPassed() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(7, 30),
            after: instant(calendar, 2026, 6, 1, 7, 30),
            calendar: calendar
        )
        XCTAssertEqual(wallClock(calendar, next!), "2026-06-02 07:30")
    }

    // Req 1.6: 07:30 stays 07:30 across a daylight-saving transition, in BOTH
    // directions. If the schedule were stored as an instant rather than as a
    // wall-clock hour and minute, one of these two would read 06:30 or 08:30.
    func testNextDueDateHoldsWallClockAcrossSpringForward() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(7, 30),
            after: instant(calendar, 2026, 3, 28, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(wallClock(calendar, next!), "2026-03-29 07:30")
    }

    func testNextDueDateHoldsWallClockAcrossAutumnBack() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(19, 30),
            after: instant(calendar, 2026, 10, 24, 20, 0),
            calendar: calendar
        )
        XCTAssertEqual(wallClock(calendar, next!), "2026-10-25 19:30")
    }

    // The wall-clock time 01:30 does not exist on the spring-forward day: the
    // clock jumps 01:00 -> 02:00. The reminder must still land, at the next
    // instant that does exist, rather than being skipped for a day.
    func testNextDueDateSurvivesATimeThatDoesNotExist() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(1, 30),
            after: instant(calendar, 2026, 3, 28, 12, 0),
            calendar: calendar
        )
        XCTAssertNotNil(next)
        XCTAssertEqual(wallClock(calendar, next!), "2026-03-29 02:00")
    }

    // The wall-clock time 01:30 occurs TWICE on the autumn day. The earlier of
    // the two is taken, so the reminder is never an hour late.
    func testNextDueDateTakesTheFirstOfARepeatedTime() {
        let calendar = dublin()
        let next = DoseScheduleMath.nextDueDate(
            for: basal(1, 30),
            after: instant(calendar, 2026, 10, 24, 12, 0),
            calendar: calendar
        )
        let following = DoseScheduleMath.nextDueDate(
            for: basal(1, 30), after: next!, calendar: calendar
        )
        XCTAssertEqual(wallClock(calendar, next!), "2026-10-25 01:30")
        // The second 01:30 of the same day is one hour later in real time, and
        // taking `.first` means it is NOT what the schedule fired at.
        XCTAssertGreaterThan(following!.timeIntervalSince(next!), 3600)
    }

    // The same schedule resolves to a different INSTANT in a different zone,
    // and to the same WALL CLOCK in each. That pair is the whole of Req 1.6:
    // travel moves the instant and leaves 07:30 alone.
    func testTheSameScheduleInAnotherZoneIsAnotherInstant() {
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let calendar = dublin()
        let schedule = basal(7, 30)
        let from = instant(calendar, 2026, 6, 1, 6, 0)
        let dublinNext = DoseScheduleMath.nextDueDate(
            for: schedule, after: from, calendar: calendar
        )!
        let sydneyNext = DoseScheduleMath.nextDueDate(
            for: schedule, after: from, calendar: sydney
        )!
        XCTAssertTrue(wallClock(calendar, dublinNext).hasSuffix("07:30"))
        XCTAssertTrue(wallClock(sydney, sydneyNext).hasSuffix("07:30"))
        XCTAssertNotEqual(dublinNext, sydneyNext)
    }

    func testDisabledScheduleHasNoOccurrence() {
        let calendar = dublin()
        XCTAssertNil(DoseScheduleMath.nextDueDate(
            for: basal(7, 30, enabled: false),
            after: instant(calendar, 2026, 6, 1, 6, 0),
            calendar: calendar
        ))
    }

    // MARK: - The missed-successor rule (Req 2.3)

    // The rule closes exactly ONE occurrence, not a backlog. An occurrence left
    // open for a week is one missed dose in the ledger, not seven.
    func testMissedRuleClosesExactlyOneNotABacklog() {
        let calendar = dublin()
        let schedule = basal(7, 30)
        let open = DoseOccurrence(
            scheduleID: schedule.id,
            dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [open],
            schedules: [schedule],
            now: instant(calendar, 2026, 6, 8, 9, 0),
            calendar: calendar
        )
        XCTAssertEqual(missed, [open.id])
    }

    func testOccurrenceStaysOpenUntilItsSuccessorIsDue() {
        let calendar = dublin()
        let schedule = basal(7, 30)
        let open = DoseOccurrence(
            scheduleID: schedule.id,
            dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        // 22:00 on the same day: late, but the next 07:30 has not arrived.
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [open],
            schedules: [schedule],
            now: instant(calendar, 2026, 6, 1, 22, 0),
            calendar: calendar
        )
        XCTAssertTrue(missed.isEmpty)
    }

    // Two open rows for one schedule breaks Req 2.3's cap whatever the clock
    // says: the older one closes and the newest stays open.
    func testOlderOpenOccurrencesCloseEvenBeforeTheSuccessorIsDue() {
        let calendar = dublin()
        let schedule = basal(7, 30)
        let older = DoseOccurrence(
            scheduleID: schedule.id, dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        let newer = DoseOccurrence(
            scheduleID: schedule.id, dueAt: instant(calendar, 2026, 6, 2, 7, 30)
        )
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [newer, older],
            schedules: [schedule],
            now: instant(calendar, 2026, 6, 2, 8, 0),
            calendar: calendar
        )
        XCTAssertEqual(missed, [older.id])
    }

    func testEachScheduleIsJudgedSeparately() {
        let calendar = dublin()
        let morning = basal(7, 30)
        let evening = basal(19, 30)
        let staleMorning = DoseOccurrence(
            scheduleID: morning.id, dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        let freshEvening = DoseOccurrence(
            scheduleID: evening.id, dueAt: instant(calendar, 2026, 6, 2, 19, 30)
        )
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [staleMorning, freshEvening],
            schedules: [morning, evening],
            now: instant(calendar, 2026, 6, 2, 20, 0),
            calendar: calendar
        )
        XCTAssertEqual(missed, [staleMorning.id])
    }

    // A deleted schedule has no successor to compare against. Guessing one here
    // would close a row the developer never asked to close.
    func testAnOccurrenceWhoseScheduleIsGoneIsLeftAlone() {
        let calendar = dublin()
        let open = DoseOccurrence(
            scheduleID: UUID(), dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [open],
            schedules: [],
            now: instant(calendar, 2026, 6, 8, 9, 0),
            calendar: calendar
        )
        XCTAssertTrue(missed.isEmpty)
    }

    func testADisabledSchedulesOpenOccurrenceStaysOpen() {
        let calendar = dublin()
        let schedule = basal(7, 30, enabled: false)
        let open = DoseOccurrence(
            scheduleID: schedule.id, dueAt: instant(calendar, 2026, 6, 1, 7, 30)
        )
        let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
            outstanding: [open],
            schedules: [schedule],
            now: instant(calendar, 2026, 6, 8, 9, 0),
            calendar: calendar
        )
        XCTAssertTrue(missed.isEmpty)
    }

    // MARK: - Notification identifiers (Req 3.2, 3.3)

    func testIdentifiersDeriveDeterministically() {
        let calendar = dublin()
        let id = UUID(uuidString: "6D8E5F9C-1A2B-4C3D-8E9F-0A1B2C3D4E5F")!
        let due = instant(calendar, 2026, 6, 1, 7, 30)
        let first = DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: id, fireDate: due, index: 0, calendar: calendar
        )
        let again = DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: id, fireDate: due, index: 0, calendar: calendar
        )
        XCTAssertEqual(first, "dose.\(id.uuidString).2026-06-01.0")
        XCTAssertEqual(first, again)
    }

    // The date component is formatted from the SAME calendar the fire date was
    // computed against, so the identifier and the fire date cannot disagree
    // about which day it is. An evening dose is the case that exposes a
    // mismatch: 19:30 in Dublin is already the next day in Sydney.
    func testTheIdentifierDayFollowsTheCalendarNotTheHost() {
        let dublinCalendar = dublin()
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let id = UUID()
        let due = instant(dublinCalendar, 2026, 6, 1, 19, 30)
        XCTAssertTrue(DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: id, fireDate: due, index: 0,
            calendar: dublinCalendar
        ).hasSuffix("2026-06-01.0"))
        XCTAssertTrue(DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: id, fireDate: due, index: 0, calendar: sydney
        ).hasSuffix("2026-06-02.0"))
    }

    func testTheSeriesIsTheDueNotificationPlusKFollowUps() {
        let calendar = dublin()
        let id = UUID()
        let series = DoseScheduleMath.reminderIdentifierSeries(
            prefix: "dose", subjectID: id,
            fireDate: instant(calendar, 2026, 6, 1, 7, 30),
            followUpCount: 4, calendar: calendar
        )
        XCTAssertEqual(series.count, 5)
        XCTAssertTrue(series[0].hasSuffix(".0"))
        XCTAssertTrue(series[4].hasSuffix(".4"))
        XCTAssertEqual(Set(series).count, 5)
    }

    func testTwoSchedulesAtTheSameTimeGetDistinctIdentifiers() {
        let calendar = dublin()
        let due = instant(calendar, 2026, 6, 1, 7, 30)
        let a = DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: UUID(), fireDate: due, index: 0, calendar: calendar
        )
        let b = DoseScheduleMath.reminderIdentifier(
            prefix: "dose", subjectID: UUID(), fireDate: due, index: 0, calendar: calendar
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - The reminder plan

    // The cutoff of Req 3.3 is K x I and nothing else — it falls out of
    // scheduling the whole sequence up front, so no timer enforces it.
    func testCutoffIsTheIntervalTimesTheFollowUpCount() {
        XCTAssertEqual(ReminderPlan().cutoffSeconds, 2 * 3600)
        XCTAssertEqual(
            ReminderPlan(intervalMinutes: 15, followUpCount: 2).cutoffSeconds, 1800
        )
    }

    func testTheSeedIsThirtyMinutesTimesFour() {
        XCTAssertEqual(ReminderPlan.seedIntervalMinutes, 30)
        XCTAssertEqual(ReminderPlan.seedFollowUpCount, 4)
    }

    // MARK: - The seeded schedule (Req 1.2)

    func testSeedIsFifteenUnitsBasalTwiceDaily() {
        let seeds = ScheduledDose.seedSchedules()
        XCTAssertEqual(seeds.count, 2)
        XCTAssertEqual(seeds.map(\.hour), [7, 19])
        XCTAssertEqual(seeds.map(\.minute), [30, 30])
        XCTAssertTrue(seeds.allSatisfy { $0.kind == .basal })
        XCTAssertTrue(seeds.allSatisfy { $0.nominalUnits == 15 })
        XCTAssertTrue(seeds.allSatisfy(\.isEnabled))
    }
}
