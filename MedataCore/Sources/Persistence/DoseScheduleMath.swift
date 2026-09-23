import Foundation

// The pure arithmetic of the dose schedule (specs/data/dose-schedule design.md
// section 7). Every function here is a free function over an explicitly-passed
// `Calendar` and `Date`. Nothing reads `Calendar.current`, `Date()` or
// `TimeZone.current` — that is what makes the whole surface testable without a
// device, a clock or a notification centre, and it is the same rule the
// `Dosing` target already follows.

public enum DoseScheduleMath {
    // MARK: - Next occurrence (Req 1.6, 2.1)

    // The next instant at which `schedule` becomes due, strictly after
    // `instant`. Returns nil for a disabled schedule — nil rather than a
    // sentinel date, so a disabled schedule cannot be accidentally armed by a
    // caller that forgot to check the flag.
    //
    // The hour and minute are resolved against the calendar's own time zone, so
    // 07:30 stays 07:30 across travel and across a daylight-saving transition.
    // The two awkward days are handled by the matching policies rather than by
    // special cases: on a spring-forward day a wall-clock time inside the
    // skipped hour does not exist, and `.nextTime` takes the next instant that
    // does; on an autumn day the time occurs twice, and `.first` takes the
    // earlier of the two so the reminder is never delayed by an hour.
    public static func nextDueDate(
        for schedule: ScheduledDose,
        after instant: Date,
        calendar: Calendar
    ) -> Date? {
        guard schedule.isEnabled else { return nil }
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0
        return calendar.nextDate(
            after: instant,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    // MARK: - The missed-successor rule (Req 2.3, 6.2)

    // Which outstanding occurrences must be closed as `missed`, given the
    // schedules they belong to and the current instant.
    //
    // Req 2.3 caps outstanding occurrences at ONE per schedule. Two things can
    // break that cap and both are handled here:
    //
    //   1. An occurrence whose successor is already due. It is superseded by
    //      the day that has arrived, so it closes.
    //   2. More than one open row for the same schedule. Every row but the
    //      newest closes, whatever the clock says.
    //
    // What this deliberately does NOT do is manufacture a backlog. Only rows
    // that exist can be closed: an occurrence left open for a week closes as
    // exactly one `missed`, not as seven. Nothing acts on a missed outcome
    // beyond recording it, so the latency of evaluating this lazily — at app
    // foreground, or when a notification handler resolves its occurrence — is
    // harmless and must not be engineered away with a timer or a background
    // task.
    //
    // An occurrence whose schedule is absent from `schedules` (the schedule was
    // deleted) has no successor to compare against and is left alone. Closing
    // out a deleted schedule's open occurrence belongs to the delete path,
    // which knows the developer's intent; inferring it here would be guessing.
    public static func occurrencesToCloseAsMissed(
        outstanding: [DoseOccurrence],
        schedules: [ScheduledDose],
        now: Date,
        calendar: Calendar
    ) -> [UUID] {
        let byID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
        var missed: [UUID] = []
        let grouped = Dictionary(grouping: outstanding, by: \.scheduleID)
        for (scheduleID, group) in grouped {
            guard let schedule = byID[scheduleID] else { continue }
            let ordered = group.sorted { ($0.dueAt, $0.id.uuidString) < ($1.dueAt, $1.id.uuidString) }
            guard let newest = ordered.last else { continue }
            // Rule 2: everything older than the newest open row is superseded.
            missed.append(contentsOf: ordered.dropLast().map(\.id))
            // Rule 1: the newest closes only once its own successor is due.
            // `isEnabled` is false for a disabled schedule, so `nextDueDate`
            // returns nil and a disabled schedule's open occurrence stays open
            // rather than being silently discarded.
            if let successor = nextDueDate(for: schedule, after: newest.dueAt, calendar: calendar),
               successor <= now {
                missed.append(newest.id)
            }
        }
        return missed.sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: - Notification identifiers (Req 3.2, 3.3)

    // `<prefix>.<subjectID>.<yyyy-MM-dd>.<n>` where n is 0 for the due
    // notification and 1...K for the follow-ups (design.md section 1).
    //
    // Identifiers are DERIVED, never stored. That is the property that matters:
    // an app killed between a notification being delivered and the dose being
    // discharged can still cancel the tail, because cancelling never depends on
    // having persisted a notification handle.
    //
    // The date component is formatted from the SAME calendar the fire date was
    // computed against — via `dateComponents`, not a `DateFormatter`, so no
    // ambient locale or time zone can make the identifier and the fire date
    // disagree about which day it is.
    public static func reminderIdentifier(
        prefix: String,
        subjectID: UUID,
        fireDate: Date,
        index: Int,
        calendar: Calendar
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: fireDate)
        let day = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
        return "\(prefix).\(subjectID.uuidString).\(day).\(index)"
    }

    // The whole prompt sequence for one occurrence: the due notification at
    // index 0 followed by `followUpCount` repeats. Scheduling the sequence up
    // front is what gives Req 3.3's cutoff without a timer — the cutoff simply
    // IS K x I, and nothing has to stay alive to enforce it.
    public static func reminderIdentifierSeries(
        prefix: String,
        subjectID: UUID,
        fireDate: Date,
        followUpCount: Int,
        calendar: Calendar
    ) -> [String] {
        (0...max(0, followUpCount)).map {
            reminderIdentifier(
                prefix: prefix, subjectID: subjectID, fireDate: fireDate,
                index: $0, calendar: calendar
            )
        }
    }

    // The identifier prefix the dose schedule uses. The scheduler itself takes
    // the prefix as data (Req 8.1) so the delayed fat follow-up can adopt the
    // same machinery with a prefix of its own.
    public static let doseIdentifierPrefix = "dose"
}

// How persistently a reminder repeats (Reqs 3.2, 3.3). K follow-ups at interval
// I, so the hard cutoff is K x I and no background execution is involved.
//
// The seeds — 30 minutes and 4, a two-hour tail — are REASONED, NOT MEASURED
// (design.md open question 1). Once occurrences carry `dueAt` and `closedAt`
// over real use, the distribution of how long a dose actually stays outstanding
// is directly measurable and both values should be set from it. Nothing in the
// UI may present them as recommended values.
public struct ReminderPlan: Sendable, Equatable, Codable {
    public static let seedIntervalMinutes = 30
    public static let seedFollowUpCount = 4

    public var intervalMinutes: Int
    public var followUpCount: Int

    public init(
        intervalMinutes: Int = ReminderPlan.seedIntervalMinutes,
        followUpCount: Int = ReminderPlan.seedFollowUpCount
    ) {
        self.intervalMinutes = intervalMinutes
        self.followUpCount = followUpCount
    }

    // Req 3.3's cutoff, in seconds after the due instant. Derived, never
    // configured separately — a cutoff that could disagree with the schedule
    // that produces it would be a second source of truth.
    public var cutoffSeconds: TimeInterval {
        TimeInterval(intervalMinutes * 60 * followUpCount)
    }
}
