import Foundation
import Observation
import OSLog
import Persistence
import UserNotifications

// The dose-specific half of the reminder feature (specs/data/dose-schedule).
// `LocalReminderScheduler` knows nothing about insulin; everything that does
// lives here.
//
// Three things share one write path deliberately: the notification's
// LOG_NOMINAL action, the in-app outstanding row, and the ADJUST sheet. A
// parallel copy of the discharge logic is exactly how a duplicate dose gets
// into the record, so there is one `DoseDischarge.log` and all three call it.

// MARK: - The notification payload

// `userInfo` is `[String: String]` because the system archives it while the app
// is not running. The tail identifiers travel with the notification rather than
// being re-derived in the handler: it keeps the handler's body to the five
// steps task 13 permits, and it makes it impossible for what is cancelled to
// disagree with what was armed.
nonisolated enum DoseReminderPayload {
    static let occurrenceID = "occurrenceID"
    static let scheduleID = "scheduleID"
    static let units = "units"
    static let kind = "kind"
    static let dueAtMs = "dueAtMs"
    static let tailIdentifiers = "tailIdentifiers"
    static let separator = ","
}

// The category and its two actions (Req 4.1, 5.1; Decision 2).
nonisolated enum DoseNotificationCategory {
    static let identifier = "MEDATA_DOSE_DUE"
    static let logNominal = "LOG_NOMINAL"
    static let adjust = "ADJUST"

    static func make() -> UNNotificationCategory {
        // LOG_NOMINAL carries NO options. Deliberately omitting `.foreground`
        // IS the mechanism: iOS launches the app in the background, the
        // delegate runs, the row is written, and nothing appears on screen.
        let log = UNNotificationAction(
            identifier: logNominal, title: "Log", options: []
        )
        // ADJUST is the exception path, for the days the amount differs.
        let adjustAction = UNNotificationAction(
            identifier: adjust, title: "Adjust", options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: identifier,
            actions: [log, adjustAction],
            intentIdentifiers: [],
            options: []
        )
    }
}

// MARK: - The one write path

// Resolve, compare-and-set, write only on transition. Everything that records a
// scheduled dose goes through here.
nonisolated enum DoseDischarge {
    // Returns true when this call was the one that recorded the dose. A second
    // action on the same occurrence — a stale follow-up tapped after the dose
    // was logged in-app — finds the occurrence already closed and returns false
    // having written nothing at all (Req 4.6).
    //
    // The insulin event is an ORDINARY `insulin` row, byte-identical in shape
    // to one entered through the dose sheet (Req 4.2): same `saveInsulinDose`,
    // same metadata keys, nothing added. medreg's convention is untouched and
    // no consumer learns a new row type. The link to the schedule lives on the
    // OCCURRENCE row via `insulinEventID`, never on the event.
    @discardableResult
    static func log(
        store: any PersistenceStore,
        occurrenceID: UUID,
        units: Double,
        kind: InsulinKind,
        wasNominal: Bool,
        at instant: Date
    ) async -> Bool {
        // The event id is minted BEFORE the compare-and-set so the occurrence
        // row records which event discharges it even if the process dies
        // between the two writes. A close with no matching event is then a
        // recoverable inconsistency rather than an anonymous one.
        let eventID = UUID()
        do {
            let transitioned = try await store.closeOccurrence(
                id: occurrenceID,
                outcome: .logged,
                // The moment the dose was LOGGED, never the scheduled time
                // (Req 4.3). `dueAt` minus this is the lateness.
                closedAt: instant,
                insulinEventID: eventID,
                wasNominal: wasNominal
            )
            guard transitioned else { return false }
            try await store.saveInsulinDose(InsulinDose(
                id: eventID,
                timestamp: instant,
                units: units,
                kind: kind,
                insulinType: InsulinProduct.name(for: kind)
            ))
            return true
        } catch {
            Logger(subsystem: "ie.medata.app", category: "Reminder")
                .notice("event=dose.discharge.failed error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    // Closes the occurrence as skipped, ending the reminder and writing no
    // insulin event of any amount, including zero (Req 6.3). No reason is
    // asked for and there is nowhere to record one (Req 6.4). The sole caller
    // is `delete(scheduleID:)` — a schedule removed while its occurrence is
    // outstanding releases that occurrence as skipped (Req 6.1); there is no
    // per-occurrence Skip in the UI.
    @discardableResult
    static func skip(
        store: any PersistenceStore, occurrenceID: UUID, at instant: Date
    ) async -> Bool {
        do {
            return try await store.closeOccurrence(
                id: occurrenceID, outcome: .skipped, closedAt: instant,
                insulinEventID: nil, wasNominal: nil
            )
        } catch {
            return false
        }
    }
}

// MARK: - The orchestrator

// One outstanding occurrence paired with the schedule it discharges, which is
// what every surface actually needs to render or act.
struct OutstandingDose: Identifiable, Equatable, Sendable {
    let occurrence: DoseOccurrence
    let schedule: ScheduledDose

    var id: UUID { occurrence.id }
    var nominalUnits: Int { Int(schedule.nominalUnits.rounded()) }
    var lateness: TimeInterval { Date().timeIntervalSince(occurrence.dueAt) }
}

@Observable
@MainActor
final class DoseScheduleModel {
    private(set) var schedules: [ScheduledDose] = []
    private(set) var plan = ReminderPlan()
    private(set) var outstanding: [OutstandingDose] = []
    // Live authorisation state, refreshed on every foreground rather than
    // cached, so a revocation made in system Settings is seen (Req 7.2).
    private(set) var notificationsAuthorised = false
    // Which of the two in-app attempts Home renders. A developer-phase
    // comparison switch so both can be judged on one build, not a preference
    // the feature depends on.
    var surfaceStyle: DoseScheduleSettings.SurfaceStyle = .banner {
        didSet { DoseScheduleSettings.save(surfaceStyle) }
    }

    private let store: any PersistenceStore
    private let scheduler: LocalReminderScheduler
    private let calendar: Calendar
    private let log = Logger(subsystem: "ie.medata.app", category: "Reminder")

    init(
        store: any PersistenceStore,
        scheduler: LocalReminderScheduler? = nil,
        calendar: Calendar = .current
    ) {
        self.store = store
        // Constructed here rather than as a default argument: a default
        // argument is evaluated in a nonisolated context, and the scheduler is
        // main-actor bound.
        self.scheduler = scheduler ?? LocalReminderScheduler()
        self.calendar = calendar
    }

    // MARK: - Reading

    // The lazy pass (design.md section 5). Everything happens at read time —
    // app foreground, or a schedule edit — and never on a timer or a background
    // task, because the CGM `BGAppRefreshTask` already spends that budget.
    //
    // Order matters: open what is due, close what the successor rule says is
    // missed, then read what remains outstanding.
    func refresh(now: Date = Date()) async {
        schedules = DoseScheduleSettings.seedIfNeeded()
        plan = DoseScheduleSettings.reminderPlan()
        if surfaceStyle != DoseScheduleSettings.surfaceStyle() {
            surfaceStyle = DoseScheduleSettings.surfaceStyle()
        }
        notificationsAuthorised = await scheduler.authorisationStatus() == .authorized

        await openDueOccurrences(now: now)
        await closeMissedOccurrences(now: now)
        await loadOutstanding()
        await reconcileNotificationPlan(now: now)
    }

    // Opens the occurrence for the most recent due instant of each enabled
    // schedule that has already passed. Opening is idempotent at the store, so
    // running this on every foreground costs one INSERT OR IGNORE per schedule
    // and can never produce a second row for the same instant.
    private func openDueOccurrences(now: Date) async {
        for schedule in schedules where schedule.isEnabled {
            guard let due = mostRecentDueInstant(for: schedule, at: now) else { continue }
            do {
                _ = try await store.openOccurrence(scheduleID: schedule.id, dueAt: due)
            } catch {
                log.notice("event=dose.open.failed error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    // The last due instant at or before `now`. Derived by stepping back one day
    // from the next one, so the daylight-saving handling in `nextDueDate` is
    // reused rather than reimplemented.
    private func mostRecentDueInstant(for schedule: ScheduledDose, at now: Date) -> Date? {
        guard let next = DoseScheduleMath.nextDueDate(
            for: schedule, after: now, calendar: calendar
        ) else { return nil }
        guard let dayEarlier = calendar.date(byAdding: .day, value: -1, to: next) else {
            return nil
        }
        return DoseScheduleMath.nextDueDate(
            for: schedule, after: dayEarlier.addingTimeInterval(-1), calendar: calendar
        ).flatMap { $0 <= now ? $0 : nil }
    }

    private func closeMissedOccurrences(now: Date) async {
        do {
            let open = try await store.outstandingOccurrences()
            let missed = DoseScheduleMath.occurrencesToCloseAsMissed(
                outstanding: open, schedules: schedules, now: now, calendar: calendar
            )
            _ = try await store.closeOccurrencesAsMissed(ids: missed, closedAt: now)
        } catch {
            log.notice("event=dose.missed.failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private func loadOutstanding() async {
        let byID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
        do {
            outstanding = try await store.outstandingOccurrences()
                .compactMap { occurrence in
                    byID[occurrence.scheduleID].map {
                        OutstandingDose(occurrence: occurrence, schedule: $0)
                    }
                }
                // Only occurrences that have actually come due are surfaced: an
                // occurrence is opened at its due instant, so this holds by
                // construction, but the guard makes it independent of that.
                .filter { $0.occurrence.dueAt <= Date() }
        } catch {
            outstanding = []
        }
    }

    // MARK: - Acting

    // Req 4.5: the same one-tap discharge as the notification's LOG_NOMINAL,
    // through the same code path, for the days the developer took the dose
    // without the reminder.
    func logNominal(_ dose: OutstandingDose, at instant: Date = Date()) async {
        let recorded = await DoseDischarge.log(
            store: store,
            occurrenceID: dose.occurrence.id,
            units: dose.schedule.nominalUnits,
            kind: dose.schedule.kind,
            wasNominal: true,
            at: instant
        )
        if recorded {
            scheduler.cancel(identifiers: tailIdentifiers(for: dose))
        }
        await refresh(now: instant)
    }

    // Saving through the pre-seeded sheet closes the occurrence with
    // `wasNominal` false, so a fit can tell a default-accepted dose from a
    // deliberately chosen one (Req 5.2). The sheet writes its own insulin
    // event, so this closes the occurrence and links it rather than writing a
    // second one.
    func recordAdjusted(
        _ dose: OutstandingDose, insulinEventID: UUID, at instant: Date = Date()
    ) async {
        do {
            let transitioned = try await store.closeOccurrence(
                id: dose.occurrence.id, outcome: .logged, closedAt: instant,
                insulinEventID: insulinEventID, wasNominal: false
            )
            if transitioned {
                scheduler.cancel(identifiers: tailIdentifiers(for: dose))
            }
        } catch {
            log.notice("event=dose.adjust.failed error=\(String(describing: error), privacy: .public)")
        }
        await refresh(now: instant)
    }

    // MARK: - Editing the schedule (Req 1.3, 1.4)

    func save(schedules updated: [ScheduledDose]) async {
        let hadEnabled = schedules.contains(where: \.isEnabled)
        schedules = updated
        DoseScheduleSettings.save(updated)
        // Req 7.1: authorisation is requested when the developer FIRST enables a
        // scheduled dose, and at no other moment. Nothing in App.swift or
        // AppRoot triggers it, and a refusal is never re-prompted.
        if !hadEnabled, updated.contains(where: \.isEnabled) {
            await requestAuthorisationOnceIfNeeded()
        }
        await refresh()
    }

    func save(plan updated: ReminderPlan) async {
        plan = updated
        DoseScheduleSettings.save(updated)
        await refresh()
    }

    // Deleting a schedule closes any occurrence still open against it as
    // skipped. The pure successor rule deliberately leaves such rows alone —
    // a deleted schedule has no successor to compare against — so the delete
    // path, which knows the intent, closes them instead of leaving a row that
    // can never be discharged.
    func delete(scheduleID: UUID) async {
        if let open = outstanding.first(where: { $0.schedule.id == scheduleID }) {
            _ = await DoseDischarge.skip(
                store: store, occurrenceID: open.occurrence.id, at: Date()
            )
            scheduler.cancel(identifiers: tailIdentifiers(for: open))
        }
        await save(schedules: schedules.filter { $0.id != scheduleID })
    }

    private func requestAuthorisationOnceIfNeeded() async {
        guard !DoseScheduleSettings.hasAskedForNotifications() else { return }
        DoseScheduleSettings.markAskedForNotifications()
        notificationsAuthorised = await scheduler.requestAuthorisation()
    }

    // MARK: - The notification plan (task 14)

    // The plan is DERIVED, never authoritative. It is torn down and rebuilt
    // from the enabled schedules plus the outstanding occurrences, so a schedule
    // that was deleted, disabled or re-timed leaves no pending request behind —
    // a stale identifier surviving a delete is the defect this prevents.
    //
    // Nothing is armed when authorisation is absent (Req 7.2): the ledger and
    // the in-app surface carry the whole feature in that state, and this is the
    // only line that differs.
    func reconcileNotificationPlan(now: Date = Date()) async {
        await scheduler.cancelPending(withPrefix: "\(DoseScheduleMath.doseIdentifierPrefix).")
        guard notificationsAuthorised else { return }
        await scheduler.arm(plannedRequests(now: now), calendar: calendar)
    }

    // How many days ahead the plan reaches. Every request is a dated one-shot,
    // so the sequence has to be rebuilt periodically; sizing the horizon against
    // the system's pending-request budget is what lets the app go unopened for
    // days without the reminder stopping (Req 7.3).
    func horizonDays(enabledCount: Int) -> Int {
        let perDay = max(1, enabledCount * (plan.followUpCount + 1))
        return max(1, min(7, LocalReminderScheduler.pendingRequestBudget / perDay))
    }

    func plannedRequests(now: Date) -> [LocalReminderRequest] {
        let enabled = schedules.filter(\.isEnabled)
        guard !enabled.isEmpty else { return [] }
        var requests: [LocalReminderRequest] = []

        // The tail of an occurrence that is due and still outstanding right
        // now: whatever of its sequence has not yet fired keeps firing.
        for dose in outstanding where dose.schedule.isEnabled {
            requests += makeRequests(
                for: dose.schedule, dueAt: dose.occurrence.dueAt,
                occurrenceID: dose.occurrence.id, after: now
            )
        }

        // Then the coming days. An occurrence that has not opened yet has no id
        // to carry, so the handler resolves it from the schedule and the due
        // instant instead — the same pair the ledger's UNIQUE index is on.
        for schedule in enabled {
            var cursor = now
            for _ in 0..<horizonDays(enabledCount: enabled.count) {
                guard let due = DoseScheduleMath.nextDueDate(
                    for: schedule, after: cursor, calendar: calendar
                ) else { break }
                requests += makeRequests(
                    for: schedule, dueAt: due, occurrenceID: nil, after: now
                )
                cursor = due
            }
        }
        return requests
    }

    private func makeRequests(
        for schedule: ScheduledDose, dueAt: Date, occurrenceID: UUID?, after now: Date
    ) -> [LocalReminderRequest] {
        let identifiers = DoseScheduleMath.reminderIdentifierSeries(
            prefix: DoseScheduleMath.doseIdentifierPrefix,
            subjectID: schedule.id,
            fireDate: dueAt,
            followUpCount: plan.followUpCount,
            calendar: calendar
        )
        var info: [String: String] = [
            DoseReminderPayload.scheduleID: schedule.id.uuidString,
            DoseReminderPayload.units: String(schedule.nominalUnits),
            DoseReminderPayload.kind: schedule.kind.rawValue,
            DoseReminderPayload.dueAtMs: String(Int64(dueAt.timeIntervalSince1970 * 1000)),
            DoseReminderPayload.tailIdentifiers:
                identifiers.joined(separator: DoseReminderPayload.separator)
        ]
        if let occurrenceID {
            info[DoseReminderPayload.occurrenceID] = occurrenceID.uuidString
        }
        return identifiers.enumerated().compactMap { index, identifier in
            let fireAt = dueAt.addingTimeInterval(
                TimeInterval(index * plan.intervalMinutes * 60)
            )
            guard fireAt > now else { return nil }
            return LocalReminderRequest(
                identifier: identifier,
                fireAt: fireAt,
                // A kind, a quantity and a time. No reassurance, encouragement,
                // warning or coaching text — the developer-phase copy rule is
                // not softened by the notification being outside the app
                // (Req 3.4).
                title: Self.reminderTitle(for: schedule),
                body: Self.reminderBody(for: schedule, dueAt: dueAt, calendar: calendar),
                categoryIdentifier: DoseNotificationCategory.identifier,
                userInfo: info
            )
        }
    }

    private func tailIdentifiers(for dose: OutstandingDose) -> [String] {
        DoseScheduleMath.reminderIdentifierSeries(
            prefix: DoseScheduleMath.doseIdentifierPrefix,
            subjectID: dose.schedule.id,
            fireDate: dose.occurrence.dueAt,
            followUpCount: plan.followUpCount,
            calendar: calendar
        )
    }

    // MARK: - Copy

    static func reminderTitle(for schedule: ScheduledDose) -> String {
        "\(unitsLabel(schedule.nominalUnits)) \(schedule.kind.rawValue)"
    }

    static func reminderBody(
        for schedule: ScheduledDose, dueAt: Date, calendar: Calendar
    ) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: dueAt)
        return String(format: "Due %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func unitsLabel(_ units: Double) -> String {
        MedataFormat.quantity(units, unit: "U")
    }
}
