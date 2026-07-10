// LibreLinkUp follower glucose source (specs/data/cgm-connect Req 3).
//
// Owns scheduling (15-minute foreground poll + catch-up + background-fetch
// entry point) and the durable-ack fetch cycle; the HTTP contract lives in
// LibreLinkUpClient. Credentials are captured by the Phase 4 UI via
// setCredentials(email:password:) BEFORE connect and live only in the
// Keychain (Req 3.1); disconnect wipes them (Req 6.2).
import Foundation

public actor LibreLinkUpGlucoseSource: GlucoseSource {

    public nonisolated let id = "librelinkup"

    // Phase 4 registers this identifier with BGTaskScheduler (Info.plist
    // BGTaskSchedulerPermittedIdentifiers) and has the handler call
    // performBackgroundFetch(). BGTask registration deliberately does NOT
    // live in this module — it is app-lifecycle wiring.
    public static let backgroundTaskIdentifier = "com.medata.librelinkup.refresh"

    // Req 3.2: fetch at an interval no longer than 15 minutes while
    // foregrounded. The spike confirmed ≤15 min is comfortably inside the
    // API's rate limits (3-minute polling has caused account bans).
    private static let pollInterval: TimeInterval = 15 * 60

    // Non-secret persisted state; the token lives in the Keychain with the
    // credentials.
    private static let hostDefaultsKey = "glucose.source.librelinkup.host"
    private static let patientIDDefaultsKey = "glucose.source.librelinkup.patientId"
    private static let lastSuccessDefaultsKey = "glucose.source.librelinkup.lastSuccessAt"

    private let client: LibreLinkUpClient
    private let keychain = LibreLinkUpKeychain()

    private var sink: (any GlucoseIngestSink)?
    private var session: LibreLinkUpSession?
    private var pollTask: Task<Void, Never>?
    private var connectionState: GlucoseConnectionState = .notConnected
    // Newest native instant a committed ingest has delivered this session
    // (Decision 10 semantics).
    private var lastDeliveredAt: Date?
    // Bumped by disconnect(). Awaiting code captures the value at entry and
    // bails out of its continuations when it changed, so a disconnect that
    // interleaves an in-flight connect leaves no poll loop and no
    // `.connected` state behind.
    private var connectionGeneration = 0

    public init() {
        self.client = LibreLinkUpClient()
    }

    // MARK: - Credentials (Req 3.1)

    // Called by the connect UI before connect(sink:). Stored as a Keychain
    // generic password (AfterFirstUnlock); never in event metadata. A stale
    // session for a previous account is dropped alongside.
    public func setCredentials(email: String, password: String) throws {
        try keychain.saveCredentials(LibreLinkUpCredentials(email: email, password: password))
        keychain.deleteSession()
        session = nil
    }

    // MARK: - GlucoseSource

    public func state() async -> GlucoseConnectionState { connectionState }

    // First fetch runs immediately (validating the stored credentials);
    // the 15-minute poll loop starts only when credentials exist. Fetch
    // failures surface through the connection state (Req 3.4), not throws.
    public func connect(sink: any GlucoseIngestSink) async throws {
        let generation = connectionGeneration
        self.sink = sink
        guard keychain.credentials() != nil else {
            connectionState = .failed(
                reason: "No LibreLinkUp credentials stored — enter the account email and password",
                lastSuccessAt: lastSuccessAt)
            await sink.reportState(connectionState, for: id)
            return
        }
        await fetchAndIngest()
        // A disconnect that interleaved the fetch must not resurrect polling.
        guard generation == connectionGeneration else { return }
        startPolling()
    }

    // Req 6.2: stops ingestion, clears stored credentials + token and the
    // cached host/patient, leaves stored readings intact.
    public func disconnect() async {
        connectionGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        session = nil
        keychain.deleteAll()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.hostDefaultsKey)
        defaults.removeObject(forKey: Self.patientIDDefaultsKey)
        lastSuccessAt = nil
        connectionState = .notConnected
        lastDeliveredAt = nil
        await sink?.reportState(.notConnected, for: id)
        sink = nil
    }

    // Req 3.2: Phase 4 calls this on app foreground.
    public func catchUp() async {
        await fetchAndIngest()
    }

    // Req 3.2: called by Phase 4's app-level BGAppRefreshTask handler
    // (registered under backgroundTaskIdentifier). Returns whether the
    // fetch-and-ingest cycle succeeded, for setTaskCompleted(success:).
    public func performBackgroundFetch() async -> Bool {
        await fetchAndIngest()
    }

    // MARK: - Fetch cycle (Req 3.3, 3.4, Decision 7)

    @discardableResult
    private func fetchAndIngest() async -> Bool {
        guard let sink else { return false }
        let generation = connectionGeneration
        do {
            let samples = try await fetchSamples()
            // A disconnect that interleaved the fetch must not ingest or
            // report `.connected` for a source that no longer is.
            guard generation == connectionGeneration else { return false }
            // Durable ack (Decision 7): only a normal return advances
            // anything — last-success time and delivery state.
            _ = try await sink.ingest(samples, from: id)
            guard generation == connectionGeneration else { return false }
            lastSuccessAt = Date()
            if let latest = samples.map(\.nativeInstant).max() {
                lastDeliveredAt = max(lastDeliveredAt ?? .distantPast, latest)
            }
            connectionState = .connected(lastReadingAt: lastDeliveredAt)
            return true
        } catch {
            guard generation == connectionGeneration else { return false }
            // Req 3.4: surface the failure and the last-success time; stored
            // readings are untouched; the next scheduled fetch retries.
            connectionState = .failed(
                reason: Self.failureReason(for: error), lastSuccessAt: lastSuccessAt)
            await sink.reportState(connectionState, for: id)
            return false
        }
    }

    // One re-login retry on 401 (agent-note "Failure modes"): drop the
    // cached token and log in again with the stored credentials; a second
    // 401 propagates to the failed state.
    private func fetchSamples() async throws -> [GlucoseSample] {
        do {
            return try await fetchOnce()
        } catch LibreLinkUpError.unauthorised {
            session = nil
            keychain.deleteSession()
            return try await fetchOnce()
        }
    }

    private func fetchOnce() async throws -> [GlucoseSample] {
        let session = try await ensureSession()
        let patientID = try await ensurePatientID(session: session)
        do {
            let graph = try await client.graph(session: session, patientID: patientID)
            return LibreLinkUpClient.samples(from: graph)
        } catch {
            // The cached patient id may be stale (patient unfollowed, account
            // changed) — drop it so the next cycle re-runs the connections
            // lookup instead of failing forever.
            UserDefaults.standard.removeObject(forKey: Self.patientIDDefaultsKey)
            throw error
        }
    }

    // In-memory session, else the Keychain-cached one, else a fresh login
    // at the persisted regional host (default api-eu; the login redirect
    // resolves and persists the right one).
    private func ensureSession() async throws -> LibreLinkUpSession {
        if let session, Self.isUsable(session) { return session }
        if let cached = keychain.session(), Self.isUsable(cached) {
            session = cached
            return cached
        }
        guard let credentials = keychain.credentials() else {
            throw LibreLinkUpError.noCredentials
        }
        let host =
            UserDefaults.standard.string(forKey: Self.hostDefaultsKey)
            ?? LibreLinkUpClient.defaultHost
        let fresh = try await client.login(credentials, host: host)
        session = fresh
        keychain.saveSession(fresh)
        UserDefaults.standard.set(fresh.host, forKey: Self.hostDefaultsKey)
        return fresh
    }

    private static func isUsable(_ session: LibreLinkUpSession) -> Bool {
        guard let expires = session.expires else { return true }
        return expires > Date()
    }

    // First followed patient wins — documented minimal behaviour for the
    // single-user developer phase; an account following several patients
    // would need a picker (out of scope). Cached so later fetches skip the
    // connections call.
    private func ensurePatientID(session: LibreLinkUpSession) async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: Self.patientIDDefaultsKey) {
            return cached
        }
        let patients = try await client.connections(session: session)
        guard let first = patients.first else {
            throw LibreLinkUpError.noPatients
        }
        UserDefaults.standard.set(first.patientId, forKey: Self.patientIDDefaultsKey)
        return first.patientId
    }

    // MARK: - Scheduling (Req 3.2)

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                // `self` gone means the source deallocated without
                // disconnect() — end the loop rather than spin forever.
                guard !Task.isCancelled, let self else { break }
                await self.fetchAndIngest()
            }
        }
    }

    // MARK: - Persisted last-success (Req 3.3)

    // Also read by the Settings UI (Req 6.1) — static and nonisolated so the
    // MainActor model shows the persisted last-fetch time without hopping
    // onto the actor. Survives relaunch, unlike the session-scoped
    // connection state (Decision 10).
    public static func persistedLastSuccessAt() -> Date? {
        let stored = UserDefaults.standard.double(forKey: lastSuccessDefaultsKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    private var lastSuccessAt: Date? {
        get {
            Self.persistedLastSuccessAt()
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue.timeIntervalSince1970, forKey: Self.lastSuccessDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSuccessDefaultsKey)
            }
        }
    }

    // Functional copy only — what happened and what to do, no disclaimers.
    private static func failureReason(for error: Error) -> String {
        switch error {
        case LibreLinkUpError.pendingAccountStep:
            return "Complete the pending step in the LibreLinkUp app, then retry"
        case LibreLinkUpError.clientVersionTooOld:
            return "LibreLinkUp client version too old"
        case LibreLinkUpError.unauthorised, LibreLinkUpError.loginRejected:
            return "LibreLinkUp sign-in failed — check the email and password"
        case LibreLinkUpError.noCredentials:
            return "No LibreLinkUp credentials stored — enter the account email and password"
        case LibreLinkUpError.noPatients:
            return "No followed patient on this LibreLinkUp account"
        case LibreLinkUpError.malformedResponse:
            return "Unexpected LibreLinkUp response"
        case let LibreLinkUpError.httpFailure(code):
            return "LibreLinkUp request failed (HTTP \(code))"
        case let LibreLinkUpError.keychainFailure(status):
            return "Keychain access failed (\(status))"
        default:
            return error.localizedDescription
        }
    }
}
