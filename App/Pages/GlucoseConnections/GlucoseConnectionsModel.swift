#if os(iOS)
import BackgroundTasks
import UIKit
#endif
import Foundation
import GlucoseIngestion
import GlucoseWidgetShared
import LibreLinkUpKit
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

    // Observable mirror of the heartbeat's persisted enabled flag (cgm-direct
    // Req 6.1) — same rule as connectedSourceIDs: the view reads only this.
    private(set) var heartbeatEnabled = false
    #if os(iOS)
    // BLE heartbeat wake (specs/data/cgm-direct). NOT a glucose source: never
    // registered with the coordinator, never in connectedSourceIDs — its only
    // effect is the rate-gated fetch in heartbeatFired(). Constructed in init
    // iff the enabled flag is set, so a restoration relaunch always finds a
    // central whose trigger closure is already attached (Req 2.7), and a
    // disabled heartbeat constructs no central and prompts for no Bluetooth
    // permission (Req 6.1).
    private(set) var heartbeat: Libre3HeartbeatSource?
    #endif

    // Every Apple Health app that has contributed a glucose sample, with its
    // classification (fingerprick-glucose Req 1.5). Mirrored here for the same
    // reason `connectedSourceIDs` is: a UserDefaults read inside a view body is
    // invisible to @Observable tracking, so the picker would not move.
    //
    // This list is the whole reason no Contour bundle identifier is hard-coded
    // anywhere — the literal is read off a real sample on device and set here,
    // without a rebuild.
    private(set) var healthKitWriters: [HealthKitGlucoseWriter] = []

    private let writerRegistry = HealthKitWriterRegistry()
    private let coordinator: IngestionCoordinator
    private let healthKit = HealthKitGlucoseSource()
    private let libreLinkUp = LibreLinkUpGlucoseSource()
    private var subscription: Task<Void, Never>?
    private var startTask: Task<Void, Never>?

    // Req 1.5. Takes effect on SUBSEQUENTLY arriving samples only: rows already
    // recorded keep the provenance they were written with, and a mistake is
    // corrected by deleting the row, never by rewriting it (Decision 2).
    func classifyHealthKitWriter(_ bundleID: String, as classification: GlucoseProvenance?) {
        writerRegistry.classify(bundleID: bundleID, as: classification)
        healthKitWriters = writerRegistry.writers()
    }

    var healthKitID: String { healthKit.id }
    var libreLinkUpID: String { libreLinkUp.id }

    init(store: any PersistenceStore) {
        coordinator = IngestionCoordinator(store: store)
        for id in [healthKit.id, libreLinkUp.id] where Self.connectedFlag(for: id) {
            connectedSourceIDs.insert(id)
        }
        healthKitWriters = writerRegistry.writers()
        heartbeatEnabled = UserDefaults.standard.bool(forKey: Self.heartbeatEnabledKey)
        #if os(iOS)
        if heartbeatEnabled {
            heartbeat = Libre3HeartbeatSource(onHeartbeat: { [weak self] in self?.heartbeatFired() })
        }
        #endif
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
                // A batch may have observed a writer this list has never seen.
                // Refreshed off the same tick rather than polled, so a Contour
                // sample arriving while Settings is open makes its writer
                // appear without a reopen.
                self.healthKitWriters = self.writerRegistry.writers()
            }
        }
        #if os(iOS)
        // Reconnect the heartbeat to the persisted sensor (cgm-direct). On a
        // restoration relaunch the OS already holds the connection and this
        // re-arms the notify subscription; issued before the awaited source
        // connects so the central is not kept waiting on network round trips.
        heartbeat?.resume()
        // Req 3.7: an OS-driven background launch (CoreBluetooth state
        // restoration) must not spend the gate-ignoring validation fetch —
        // that request would race Abbott's ~1 s upload and close the gate
        // against the properly-delayed heartbeat fetch. The first fetch is
        // left to the heartbeat path; foreground launches keep today's
        // immediate validation.
        let launchedIntoBackground = UIApplication.shared.applicationState == .background
        #else
        let launchedIntoBackground = false
        #endif
        if connectedSourceIDs.contains(healthKitID) {
            await connectHealthKitNow()
        }
        if connectedSourceIDs.contains(libreLinkUpID) {
            await connectLibreLinkUpNow(runValidationFetch: !launchedIntoBackground)
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

    // MARK: - BLE heartbeat wake (specs/data/cgm-direct Req 5.1, 5.3, 6.1)

    #if os(iOS)
    // Enable is the explicit developer-phase action (Req 6.1): constructing
    // the central triggers the Bluetooth permission prompt, the flag makes the
    // next launch reconstruct it, and the foreground wildcard pairing scan
    // starts (Req 2.1). Re-pairing after a sensor swap re-runs this same flow
    // (Req 2.4a) — the enable is idempotent.
    func enableHeartbeat() {
        setHeartbeatEnabledFlag(true)
        if heartbeat == nil {
            heartbeat = Libre3HeartbeatSource(onHeartbeat: { [weak self] in self?.heartbeatFired() })
        }
        heartbeat?.startPairing()
    }

    func confirmHeartbeatPairing() {
        heartbeat?.confirmPairing()
    }

    // Additive-off (Req 5.3): stop() cancels the connection and scanning, the
    // cleared flag keeps the next launch from constructing the central, and
    // the persisted identifier is kept so a re-enable pairs the same sensor.
    // The LibreLinkUp source and stored readings are untouched.
    func disableHeartbeat() {
        heartbeat?.stop()
        setHeartbeatEnabledFlag(false)
    }

    // One debounced beat = one gate-checked fetch attempt (cgm-direct
    // Decision 5). The gate peek is a single UserDefaults read — roughly four
    // of five beats find the gate closed and end here, spending no background
    // assertion and no actor hop; the source already recorded the beat, so
    // its meaning ("a reading exists now") survives the early return.
    private func heartbeatFired() {
        guard LibreLinkUpRateGate.isOpen() else { return }
        // A CoreBluetooth event wake grants ~10 s of runtime. Expiration
        // cancels the work Task (same discipline as the BGTask handler);
        // cancellation surfaces through the URLSession await as a failed
        // fetch, nothing is acked, and the next open-gate beat retries.
        let work = CancellableWorkBox()
        let assertion = UIApplication.shared.beginBackgroundTask { work.cancel() }
        work.task = Task { [weak self] in
            defer { UIApplication.shared.endBackgroundTask(assertion) }
            guard let self else { return }
            // Req 3.6: lose the cold-launch race — the launch reconnect must
            // attach the sink first, and the fetch runs only while
            // LibreLinkUp is connected.
            await self.startTask?.value
            guard self.connectedSourceIDs.contains(self.libreLinkUpID) else { return }
            // Req 3.3: give Abbott's app its ~1 s upload of the just-produced
            // reading, so the fetch returns the newest value, not the previous.
            try? await Task.sleep(for: .seconds(Libre3Heartbeat.Constants.preFetchDelay))
            await self.libreLinkUp.catchUp()
        }
    }
    #endif

    private static let heartbeatEnabledKey = "glucose.source.libre3-heartbeat.enabled"

    private func setHeartbeatEnabledFlag(_ enabled: Bool) {
        heartbeatEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.heartbeatEnabledKey)
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
    //
    // LibreLinkUp's flag lives in the App Group suite rather than
    // `UserDefaults.standard`, because the widget gates its own fetch on it
    // (glucose-lock-widget Decision 16) and cannot see the app's private store.
    // HealthKit's stays private — nothing outside this process reads it.
    private func setConnectedFlag(_ connected: Bool, for sourceID: String) {
        if connected {
            connectedSourceIDs.insert(sourceID)
        } else {
            connectedSourceIDs.remove(sourceID)
        }
        if sourceID == LibreLinkUpSharedState.sourceID {
            LibreLinkUpSharedState.setConnected(connected)
        } else {
            UserDefaults.standard.set(connected, forKey: Self.connectedKey(sourceID))
        }
    }

    private static func connectedFlag(for sourceID: String) -> Bool {
        sourceID == LibreLinkUpSharedState.sourceID
            ? LibreLinkUpSharedState.isConnected()
            : UserDefaults.standard.bool(forKey: connectedKey(sourceID))
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
    private func connectLibreLinkUpNow(runValidationFetch: Bool = true) async {
        do {
            try await libreLinkUp.connect(sink: coordinator, runValidationFetch: runValidationFetch)
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
// `nonisolated` throughout, deliberately: this box exists to be touched from
// the BGTask expiration handler, which the system calls on its own thread. Its
// own `NSLock` is what makes that safe — the default MainActor isolation this
// file otherwise gets would contradict the `@unchecked Sendable` it declares,
// and would mean the expiration handler could not cancel anything.
private final class CancellableWorkBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var _task: Task<Void, Never>?

    nonisolated var task: Task<Void, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); defer { lock.unlock() }; _task = newValue }
    }

    nonisolated func cancel() { task?.cancel() }
}
#endif
