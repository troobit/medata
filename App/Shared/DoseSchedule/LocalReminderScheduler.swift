import Foundation
import OSLog
import UserNotifications

// A general local-reminder capability (specs/data/dose-schedule Req 8.1). This
// file contains no reference to doses, units, insulin or a schedule: it takes a
// reminder description — identifiers, fire dates, category, payload — and
// arms it. That is structural, not aspirational. `specs/data/insulin-dosing`
// tasks.md task 22 records the delayed fat follow-up as "blocked on machinery
// that does not exist: the app has no notification, timer or scheduling surface
// at all today"; it adopts this type as-is or Req 8.1 was not met.
//
// Everything here is local. There is no push service, no server and no network
// call anywhere in this file, and none may be added.

// One notification to arm: an identifier, an absolute instant, and what to say.
struct LocalReminderRequest: Sendable, Equatable {
    let identifier: String
    let fireAt: Date
    let title: String
    let body: String
    let categoryIdentifier: String
    // Carried through to the action handler so it can resolve what the
    // notification refers to without a second lookup. String-to-string because
    // `UNNotificationContent.userInfo` must survive being archived by the
    // system while the app is not running.
    let userInfo: [String: String]
}

// Arms and cancels local notifications. Nothing here runs in the background and
// nothing keeps a timer alive: the whole prompt sequence is scheduled up front
// and what is left of it is cancelled when the subject is discharged. That
// matters because `App/GlucoseConnectionsModel.swift` already spends the app's
// background budget on the CGM `BGAppRefreshTask`, and this must not compete
// with it.
@MainActor
final class LocalReminderScheduler {
    // iOS keeps at most this many pending notification requests per app and
    // silently discards the rest. Every horizon calculation is bounded by it.
    static let pendingRequestBudget = 64

    private let centre: UNUserNotificationCenter
    private let log = Logger(subsystem: "ie.medata.app", category: "Reminder")

    init(centre: UNUserNotificationCenter = .current()) {
        self.centre = centre
    }

    // MARK: - Authorisation

    // The live grant state, read rather than cached, so a revocation made in
    // system Settings is seen on the next foreground.
    func authorisationStatus() async -> UNAuthorizationStatus {
        await centre.notificationSettings().authorizationStatus
    }

    // Asked once, by the caller, at the moment the caller decides — never at
    // launch. `.alert`, `.sound` and `.badge` only: no provisional level, and
    // nothing that requires Apple entitlement review.
    func requestAuthorisation() async -> Bool {
        do {
            return try await centre.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.notice("event=reminder.authorisation error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    func register(categories: Set<UNNotificationCategory>) {
        centre.setNotificationCategories(categories)
    }

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        centre.delegate = delegate
    }

    // MARK: - Arming

    // Every request is a DATED one-shot `UNCalendarNotificationTrigger`, never a
    // repeating one. A repeating trigger cannot be cancelled for one day only,
    // and cancelling exactly one day's remaining prompts is the whole of
    // "the repeat stops when the dose is logged". The cost is that the plan has
    // a horizon and must be rebuilt; the reconciler does that on every
    // foreground, and the horizon is sized so the app can go unopened for days.
    func arm(_ requests: [LocalReminderRequest], calendar: Calendar) async {
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.categoryIdentifier = request.categoryIdentifier
            content.userInfo = request.userInfo
            // The default active band. A time-sensitive or critical level would
            // need Apple entitlement review and would present the prompt as a
            // medical alert, which this build does not do.
            content.interruptionLevel = .active
            content.sound = .default

            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: request.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: parts, repeats: false
            )
            do {
                try await centre.add(UNNotificationRequest(
                    identifier: request.identifier, content: content, trigger: trigger
                ))
            } catch {
                log.notice(
                    "event=reminder.arm.failed id=\(request.identifier, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    // MARK: - Cancelling

    // Takes an identifier set: pending requests are withdrawn and anything
    // already on screen is cleared, so discharging a subject removes both the
    // tail that has not fired and the prompt sitting in Notification Centre.
    func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        centre.removePendingNotificationRequests(withIdentifiers: identifiers)
        centre.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // Withdraws every pending request whose identifier starts with `prefix`.
    // The reconciler uses this to clear a plan before rebuilding it, which is
    // what stops a deleted or disabled subject leaving a stale identifier
    // behind.
    func cancelPending(withPrefix prefix: String) async {
        let pending = await centre.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !stale.isEmpty else { return }
        centre.removePendingNotificationRequests(withIdentifiers: stale)
    }

    func pendingIdentifiers(withPrefix prefix: String) async -> [String] {
        await centre.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
    }
}
