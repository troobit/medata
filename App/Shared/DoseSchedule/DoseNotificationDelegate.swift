import Foundation
import OSLog
import Persistence
import UserNotifications

// The background write path (specs/data/dose-schedule Req 4.1, 4.2, 4.6, 7.3;
// design.md section 2). There is no precedent for this path in the tree: it
// runs with the app NOT running, under a short system deadline, and it must
// reach GRDB.
//
// The body is exactly five steps — resolve the occurrence, compare-and-set,
// write the event only if it transitioned, cancel the tail, call the completion
// handler — and nothing else. Explicitly forbidden here: any UI, any migration
// work, any CGM poll, any widget publish, and any work that can be deferred to
// the next foreground. The completion handler fires on every path, including
// every failure path, or iOS records the app as having hung.
//
// A stale follow-up delivered before the dose was logged elsewhere must write
// NOTHING. The compare-and-set in `closeOccurrence` is the only thing standing
// between this handler and a duplicate dose in the record.

// What the ADJUST action asks the app to open once it is foregrounded. Held
// here rather than acted on in the handler, because presenting anything is UI.
struct PendingDoseAdjust: Equatable, Sendable {
    let scheduleID: UUID
    let dueAt: Date
    let units: Double
    let kind: InsulinKind
}

@MainActor
@Observable
final class DoseAdjustRouter {
    // AppRoot observes this and raises the pre-seeded sheet through its
    // existing `pendingDeepLink` resume, so landing during a dismissing
    // presentation is not silently dropped.
    var pending: PendingDoseAdjust?
}

final class DoseNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let store: any PersistenceStore
    private let router: DoseAdjustRouter
    private let log = Logger(subsystem: "ie.medata.app", category: "Reminder")

    init(store: any PersistenceStore, router: DoseAdjustRouter) {
        self.store = store
        self.router = router
    }

    // The reminder is worth seeing while the app is open too: the dose is due
    // whether or not the developer happens to be looking at MeData.
    nonisolated func userNotificationCenter(
        _ centre: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ centre: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let payload = Payload(info) else {
            log.notice("event=dose.action.unreadable")
            return
        }

        switch response.actionIdentifier {
        case DoseNotificationCategory.logNominal:
            await logNominal(payload, centre: centre)
        case DoseNotificationCategory.adjust, UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                router.pending = PendingDoseAdjust(
                    scheduleID: payload.scheduleID, dueAt: payload.dueAt,
                    units: payload.units, kind: payload.kind
                )
            }
        default:
            break
        }
    }

    // Step 1-4. Step 5 — the completion handler — is the `async` form's return,
    // which fires on every path out of this function including the error ones,
    // because nothing here throws past it.
    private func logNominal(_ payload: Payload, centre: UNUserNotificationCenter) async {
        do {
            // Resolve. `openOccurrence` is INSERT OR IGNORE against the UNIQUE
            // (schedule_id, due_at) index, so it returns the existing
            // outstanding row when there is one and creates it otherwise — one
            // round trip, and it cannot manufacture a second row.
            let occurrence = try await store.openOccurrence(
                scheduleID: payload.scheduleID, dueAt: payload.dueAt
            )
            let recorded = await DoseDischarge.log(
                store: store,
                occurrenceID: occurrence.id,
                units: payload.units,
                kind: payload.kind,
                wasNominal: true,
                at: Date()
            )
            // Cancel the tail whether or not this call was the one that
            // recorded the dose: if it was already logged elsewhere, the
            // remaining prompts are stale either way.
            centre.removePendingNotificationRequests(withIdentifiers: payload.tailIdentifiers)
            centre.removeDeliveredNotifications(withIdentifiers: payload.tailIdentifiers)
            log.notice("event=dose.action.log recorded=\(recorded, privacy: .public)")
        } catch {
            log.notice(
                "event=dose.action.failed error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Payload

    // `nonisolated`: decoded inside the delegate's own `nonisolated`
    // callbacks, straight off the notification's userInfo. Pure translation
    // with nothing to isolate.
    nonisolated private struct Payload {
        let scheduleID: UUID
        let dueAt: Date
        let units: Double
        let kind: InsulinKind
        let tailIdentifiers: [String]

        init?(_ info: [AnyHashable: Any]) {
            guard let scheduleString = info[DoseReminderPayload.scheduleID] as? String,
                  let scheduleID = UUID(uuidString: scheduleString),
                  let dueString = info[DoseReminderPayload.dueAtMs] as? String,
                  let dueMs = Int64(dueString),
                  let unitsString = info[DoseReminderPayload.units] as? String,
                  let units = Double(unitsString),
                  let kindString = info[DoseReminderPayload.kind] as? String,
                  let kind = InsulinKind(rawValue: kindString) else { return nil }
            self.scheduleID = scheduleID
            self.dueAt = Date(timeIntervalSince1970: Double(dueMs) / 1000)
            self.units = units
            self.kind = kind
            let joined = info[DoseReminderPayload.tailIdentifiers] as? String ?? ""
            self.tailIdentifiers = joined
                .components(separatedBy: DoseReminderPayload.separator)
                .filter { !$0.isEmpty }
        }
    }
}
