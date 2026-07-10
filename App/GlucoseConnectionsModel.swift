#if os(iOS)
import BackgroundTasks
#endif
import Foundation
import GlucoseIngestion
import Observation
import Persistence

// App-side owner of live glucose ingestion (specs/data/cgm-connect Phase 4).
// Holds the one IngestionCoordinator plus the two sources, mirrors the
// coordinator's state stream for GlucoseConnectionsView (Req 6.1), and owns
// the lifecycle the sources cannot: which sources the user has connected
// (UserDefaults flags), the every-launch reconnect (sources hold no
// cross-launch sink — without connect(sink:), catchUp() no-ops and nothing
// ingests), the on-foreground catch-up (Req 2.6/3.2), and the LibreLinkUp
// BGAppRefreshTask cycle.
@Observable
@MainActor
final class GlucoseConnectionsModel {

    // Latest coordinator snapshot (sourceID → state), mirrored for the UI.
    private(set) var states: [String: GlucoseConnectionState] = [:]
    // In-session discrepancy tallies (Req 5.4/6.1, Decision 9), polled from
    // the coordinator whenever a snapshot arrives.
    private(set) var discrepancyCounts: [String: Int] = [:]
    // Observable mirror of the persisted connected flags — the view reads
    // ONLY this (UserDefaults reads inside a view body are invisible to
    // @Observable tracking). Seeded from UserDefaults at init, mutated in
    // setConnectedFlag alongside the persisted write.
    private(set) var connectedSourceIDs: Set<String> = []
    // Sources with a connect/disconnect intent Task in flight — the view
    // disables the buttons so a slow connect cannot be double-tapped into
    // concurrent setCredentials/connect calls.
    private(set) var busySourceIDs: Set<String> = []

    private let coordinator: IngestionCoordinator
    private let healthKit = HealthKitGlucoseSource()
    private let libreLinkUp = LibreLinkUpGlucoseSource()
    private var subscription: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    var healthKitID: String { healthKit.id }
    var libreLinkUpID: String { libreLinkUp.id }

    init(store: any PersistenceStore) {
        coordinator = IngestionCoordinator(store: store)
        for id in [healthKit.id, libreLinkUp.id]
        where UserDefaults.standard.bool(forKey: Self.connectedKey(id)) {
            connectedSourceIDs.insert(id)
        }
    }

    // MARK: - Launch (Req 1.3, 1.4)

    // Called once from MedataApp. Registers both sources (a fresh source
    // surfaces as `.notConnected` without error and never touches the event
    // log — Req 1.4), starts mirroring the state stream, then reconnects
    // every source the user has previously connected (the agent-note
    // contract: the observer/anchor and poll lifecycles all hang off
    // `connect`, every launch). The Task is retained so the background-
    // refresh handler can await it — a background cold launch must not run
    // performBackgroundFetch() before the reconnect has attached the sink.
    func start() {
        guard startTask == nil else { return }
        startTask = Task { await runStart() }
    }

    private func runStart() async {
        await coordinator.register(healthKit)
        await coordinator.register(libreLinkUp)
        let stream = await coordinator.stateStream()
        subscription = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                var counts: [String: Int] = [:]
                for id in snapshot.keys {
                    counts[id] = await self.coordinator.discrepancyCount(for: id)
                }
                self.states = snapshot
                self.discrepancyCounts = counts
            }
        }
        if connectedSourceIDs.contains(healthKitID) {
            await connectHealthKitNow()
        }
        if connectedSourceIDs.contains(libreLinkUpID) {
            await connectLibreLinkUpNow()
        }
    }

    // MARK: - Connect / disconnect intents (Req 6.2)

    // Triggers the OS authorisation sheet via the source's connect (Req 2.1).
    func connectHealthKit() {
        guard !busySourceIDs.contains(healthKitID) else { return }
        setConnectedFlag(true, for: healthKitID)
        busySourceIDs.insert(healthKitID)
        Task {
            await connectHealthKitNow()
            busySourceIDs.remove(healthKitID)
        }
    }

    // Credentials go to the Keychain via the source BEFORE connect (Req 3.1);
    // fetch failures surface through the source's `.failed` state. A failed
    // credential store clears the connected flag again — nothing was stored,
    // so a launch reconnect would only re-surface "no credentials".
    func connectLibreLinkUp(email: String, password: String) {
        guard !busySourceIDs.contains(libreLinkUpID) else { return }
        setConnectedFlag(true, for: libreLinkUpID)
        busySourceIDs.insert(libreLinkUpID)
        Task {
            defer { busySourceIDs.remove(libreLinkUpID) }
            do {
                try await libreLinkUp.setCredentials(email: email, password: password)
            } catch {
                setConnectedFlag(false, for: libreLinkUpID)
                await coordinator.reportState(
                    .failed(
                        reason: "Could not store the credentials (\(error.localizedDescription))",
                        lastSuccessAt: nil),
                    for: libreLinkUpID)
                return
            }
            await connectLibreLinkUpNow()
        }
    }

    // Stops ingestion and clears the source's stored credentials/cursor via
    // its disconnect(); resets the status counters (Decision 9); flips the
    // launch-reconnect flag. Stored readings remain (Req 6.2).
    func disconnect(_ sourceID: String) {
        guard !busySourceIDs.contains(sourceID) else { return }
        setConnectedFlag(false, for: sourceID)
        busySourceIDs.insert(sourceID)
        Task {
            defer { busySourceIDs.remove(sourceID) }
            await coordinator.resetDiscrepancyTally(for: sourceID)
            if sourceID == healthKitID {
                await healthKit.disconnect()
            } else if sourceID == libreLinkUpID {
                await libreLinkUp.disconnect()
                #if os(iOS)
                BGTaskScheduler.shared.cancel(
                    taskRequestWithIdentifier: LibreLinkUpGlucoseSource.backgroundTaskIdentifier)
                #endif
            }
        }
    }

    // MARK: - Foreground catch-up (Req 2.6, 3.2)

    // Called on scenePhase == .active. Guards inside the sources make racing
    // the launch reconnect harmless (nil sink no-ops; HealthKit's anchored
    // ingest has a reentrancy guard).
    func catchUpConnectedSources() {
        Task {
            if connectedSourceIDs.contains(healthKitID) { await healthKit.catchUp() }
            if connectedSourceIDs.contains(libreLinkUpID) { await libreLinkUp.catchUp() }
        }
    }

    // MARK: - Settings display helpers (Req 6.1)

    // Persisted time of the last successful LibreLinkUp fetch — survives
    // relaunch, unlike the session-scoped connection state (Decision 10).
    var libreLinkUpLastSuccessAt: Date? {
        LibreLinkUpGlucoseSource.persistedLastSuccessAt()
    }

    // MARK: - Connected-source flags

    // One bool per source under `glucose.source.<id>.connected` (the
    // GlucoseIngestion module's key namespace): set when the user connects in
    // Settings, cleared on disconnect, seeded into `connectedSourceIDs` at
    // init to know which sources to reconnect at launch. With no flag set,
    // nothing runs at launch (Req 1.4). UserDefaults is persistence only —
    // all live reads go through the observable mirror.
    private func setConnectedFlag(_ connected: Bool, for sourceID: String) {
        if connected {
            connectedSourceIDs.insert(sourceID)
        } else {
            connectedSourceIDs.remove(sourceID)
        }
        UserDefaults.standard.set(connected, forKey: Self.connectedKey(sourceID))
    }

    private static func connectedKey(_ sourceID: String) -> String {
        "glucose.source.\(sourceID).connected"
    }

    // connect throws only when health data is unavailable on the device;
    // everything else surfaces through the source's own `.failed` state.
    private func connectHealthKitNow() async {
        do {
            try await healthKit.connect(sink: coordinator)
        } catch {
            await coordinator.reportState(
                .failed(reason: "Health data is not available on this device", lastSuccessAt: nil),
                for: healthKitID)
        }
    }

    // LibreLinkUp's connect surfaces fetch failures through its own `.failed`
    // state rather than throws today, but map a throw the same way the
    // HealthKit branch does — no silent-swallow path.
    private func connectLibreLinkUpNow() async {
        do {
            try await libreLinkUp.connect(sink: coordinator)
            scheduleBackgroundRefresh()
        } catch {
            await coordinator.reportState(
                .failed(
                    reason: error.localizedDescription,
                    lastSuccessAt: LibreLinkUpGlucoseSource.persistedLastSuccessAt()),
                for: libreLinkUpID)
        }
    }

    // MARK: - LibreLinkUp background refresh (Req 3.2)

    #if os(iOS)
    // Must run before the application finishes launching — called from
    // MedataApp.init(). `using: .main` keeps the launch handler on the main
    // queue, matching this model's MainActor isolation. The handler
    // re-schedules the next refresh first (BGTask requests are one-shot),
    // then runs the fetch; a not-connected LibreLinkUp completes immediately
    // as a successful no-op.
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LibreLinkUpGlucoseSource.backgroundTaskIdentifier,
            using: .main
        ) { [weak self] task in
            guard let self, let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // The expiration handler must be in place BEFORE the work starts,
            // so the box holds the Task it will cancel. Cancellation
            // propagates through the URLSession await; the fetch surfaces it
            // as a failure and the task still completes.
            let work = CancellableWorkBox()
            refresh.expirationHandler = { @Sendable in work.cancel() }
            work.task = Task { await self.handleBackgroundRefresh(refresh) }
        }
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        // A background cold launch races start()'s reconnect — without the
        // sink attached, performBackgroundFetch() would no-op as a failure.
        await startTask?.value
        guard connectedSourceIDs.contains(libreLinkUpID) else {
            task.setTaskCompleted(success: true)
            return
        }
        scheduleBackgroundRefresh()
        let success = await libreLinkUp.performBackgroundFetch()
        task.setTaskCompleted(success: success)
    }

    // Submitted when LibreLinkUp connects and after each background fetch.
    // 15 minutes matches the foreground poll ceiling; delivery is OS-governed
    // and best-effort. A denied or duplicate submission is non-fatal — the
    // foreground poll and the on-open catch-up still cover delivery.
    private func scheduleBackgroundRefresh() {
        guard connectedSourceIDs.contains(libreLinkUpID) else { return }
        let request = BGAppRefreshTaskRequest(
            identifier: LibreLinkUpGlucoseSource.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    #else
    func registerBackgroundRefresh() {}
    private func scheduleBackgroundRefresh() {}
    #endif
}

#if os(iOS)
// Lets the BGTask expiration handler be assigned before the work Task exists
// (the handler must be armed first — expiry can fire the moment work starts).
// NSLock because the expiration handler can arrive off the main queue.
private final class CancellableWorkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Never>?

    var task: Task<Void, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); defer { lock.unlock() }; _task = newValue }
    }

    func cancel() { task?.cancel() }
}
#endif
