import Foundation
import Persistence

// The schedule as configuration (specs/data/dose-schedule Req 1.1-1.4,
// design.md section 4). A `[ScheduledDose]` array behind one `SettingsKeys`
// entry, not a table: giving it a table would imply a history it does not have,
// and it is precisely because it has no history that editing a scheduled dose
// cannot alter a dose already recorded (Req 1.5).
//
// `nonisolated` for the same reason `SettingsKeys` is: the project sets
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the notification handler
// reads this with the app not running and no main-actor context to borrow.
nonisolated enum DoseScheduleSettings {

    // MARK: - The schedule

    static func schedules(_ defaults: UserDefaults = .standard) -> [ScheduledDose] {
        guard let data = defaults.data(forKey: SettingsKeys.doseSchedules) else { return [] }
        // A decode failure reads as no schedule rather than throwing. The
        // feature is inert with an empty schedule (Req 1.7), which is a far
        // better outcome than a launch-time crash over a settings blob.
        return (try? JSONDecoder().decode([ScheduledDose].self, from: data)) ?? []
    }

    static func save(_ schedules: [ScheduledDose], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        defaults.set(data, forKey: SettingsKeys.doseSchedules)
    }

    // Req 1.2. Writes the two standing entries — 15 U basal at 07:30 and 15 U
    // basal at 19:30 — at most ONCE per install, gated on the seeded marker
    // rather than on the list being empty. That distinction is the requirement:
    // a developer who deletes both entries has an empty schedule, and an empty
    // schedule must stay empty across relaunches.
    @discardableResult
    static func seedIfNeeded(_ defaults: UserDefaults = .standard) -> [ScheduledDose] {
        let existing = schedules(defaults)
        guard !defaults.bool(forKey: SettingsKeys.doseSchedulesSeeded) else {
            return existing
        }
        defaults.set(true, forKey: SettingsKeys.doseSchedulesSeeded)
        guard existing.isEmpty else { return existing }
        let seeds = ScheduledDose.seedSchedules()
        save(seeds, defaults)
        return seeds
    }

    // MARK: - The reminder plan (Reqs 3.2, 3.3)

    static func reminderPlan(_ defaults: UserDefaults = .standard) -> ReminderPlan {
        let interval = defaults.object(forKey: SettingsKeys.doseReminderIntervalMinutes) as? Int
        let followUps = defaults.object(forKey: SettingsKeys.doseReminderFollowUps) as? Int
        return ReminderPlan(
            intervalMinutes: interval ?? ReminderPlan.seedIntervalMinutes,
            followUpCount: followUps ?? ReminderPlan.seedFollowUpCount
        )
    }

    static func save(_ plan: ReminderPlan, _ defaults: UserDefaults = .standard) {
        defaults.set(plan.intervalMinutes, forKey: SettingsKeys.doseReminderIntervalMinutes)
        defaults.set(plan.followUpCount, forKey: SettingsKeys.doseReminderFollowUps)
    }

    // MARK: - Authorisation bookkeeping (Req 7.1, 7.2)

    // Whether the one authorisation prompt has already been shown. The GRANT
    // state is deliberately NOT cached: it is read live from
    // `notificationSettings` so a revocation made in system Settings is seen on
    // the next foreground rather than believed away.
    static func hasAskedForNotifications(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: SettingsKeys.doseNotificationAsked)
    }

    static func markAskedForNotifications(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: SettingsKeys.doseNotificationAsked)
    }

    // MARK: - Which in-app surface is showing

    // The two attempts at the outstanding-dose surface, tagged
    // `dose-schedule-ui-attempt-1` and `-2`. A comparison switch for the phone,
    // not a preference: it exists so both can be seen on the same build.
    enum SurfaceStyle: String, CaseIterable {
        // Attempt 1: a banner on Home, above the routes.
        case banner
        // Attempt 2: the Dose route itself becomes the discharge control.
        case doseRoute
    }

    static func surfaceStyle(_ defaults: UserDefaults = .standard) -> SurfaceStyle {
        SurfaceStyle(rawValue: defaults.string(forKey: SettingsKeys.doseSurfaceStyle) ?? "")
            ?? .banner
    }

    static func save(_ style: SurfaceStyle, _ defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: SettingsKeys.doseSurfaceStyle)
    }
}
