#if RETENTION_SCHEDULER_ENABLED
import Foundation

// Artefact retention per Req 17.6. Default window: 30 days.
// Disabled in v1 — re-enable via the RETENTION_SCHEDULER_ENABLED compile flag
// when cloud storage handoff (Req 17.5) is designed.
// `sweepIfDue()` runs on every app foregrounding and on pipeline completion;
// iOS also registers a BGProcessingTask for opportunistic background sweeps.
public final class RetentionScheduler: Sendable {

    private let store: any PersistenceStore
    public let retentionDays: Int

    public init(store: any PersistenceStore, retentionDays: Int = 30) {
        self.store = store
        self.retentionDays = retentionDays
    }

    public func sweepIfDue() async throws {
        try await store.sweepIfDue()
    }

    public func sweep(relativeTo now: Date = Date()) async throws {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        try await store.deleteArtefacts(olderThan: cutoff)
    }
}

#if os(iOS)
import BackgroundTasks

public extension RetentionScheduler {
    static let bgTaskIdentifier = "com.medata.retention.sweep"

    static func registerBackgroundTask(scheduler: RetentionScheduler) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            Task {
                do {
                    try await scheduler.sweep()
                    processingTask.setTaskCompleted(success: true)
                } catch {
                    processingTask.setTaskCompleted(success: false)
                }
            }
            processingTask.expirationHandler = { task.setTaskCompleted(success: false) }
            RetentionScheduler.scheduleBackgroundTask()
        }
        scheduleBackgroundTask()
    }

    static func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: bgTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif

#endif // RETENTION_SCHEDULER_ENABLED
