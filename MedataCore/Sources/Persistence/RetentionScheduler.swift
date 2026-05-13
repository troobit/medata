import Foundation

// Artefact retention per Req 17. Default window: 30 days.
// `sweepIfDue()` runs on every app foregrounding and on pipeline completion
// (foreground fallback per design §2.3). iOS also registers a BGProcessingTask
// (guarded #if os(iOS)) for opportunistic background sweeps.
public final class RetentionScheduler: Sendable {

    private let store: any PersistenceStore
    public let retentionDays: Int

    public init(store: any PersistenceStore, retentionDays: Int = 30) {
        self.store = store
        self.retentionDays = retentionDays
    }

    // Sweeps artefacts older than retentionDays if the store's last sweep
    // was more than 24 hours ago (delegated to GRDBPersistenceStore.sweepIfDue).
    public func sweepIfDue() async throws {
        try await store.sweepIfDue()
    }

    // Unconditional sweep — used by BGProcessingTask and tests.
    public func sweep(relativeTo now: Date = Date()) async throws {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        try await store.deleteArtefacts(olderThan: cutoff)
    }
}

#if os(iOS)
import BackgroundTasks

public extension RetentionScheduler {
    static let bgTaskIdentifier = "com.medata.retention.sweep"

    // Register BGProcessingTask. Call once at app launch.
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
