// LibreLinkUp follower glucose source (specs/data/cgm-connect Req 3).
//
// Owns scheduling (15-minute foreground poll + catch-up + background-fetch
// entry point) and the durable-ack fetch cycle; the HTTP contract lives in
// LibreLinkUpClient. Credentials are captured by the Phase 4 UI via
// setCredentials(email:password:) BEFORE connect and live only in the
// Keychain (Req 3.1); disconnect wipes them (Req 6.2).
import Foundation
// For TrendsMath / GlucoseReading — the adaptive poll interval reuses the
// display's own rate maths so "falling fast" means the same thing to the
// scheduler as to the arrow the user is looking at. GlucoseIngestion already
// depends on Persistence.
import Persistence

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
    static let pollInterval: TimeInterval = 15 * 60

    // The tightened interval used while glucose is low or falling fast
    // (see `nextPollInterval`). Deliberately 5 minutes, not 3: 3-minute
    // polling is the rate that has caused bans, so this stays clear of it
    // even during a sustained hypo.
    static let urgentPollInterval: TimeInterval = 5 * 60

    // Below this the next poll tightens. Set at the top of the target band
    // (`TrendsMath.targetLowMmolL` = 3.9) plus a margin, so the tightening
    // starts on the approach to a low rather than after arriving at one —
    // which is the whole point, given the poll is what makes the display
    // late.
    static let urgentThresholdMmolL = 5.0

    // …or if glucose is dropping at least this fast, whatever the level:
    // `TrendsMath.mediumRateThreshold`, the edge of the plain "falling"
    // arrow. From 8.0 that reaches 3.9 in about 37 minutes — two 15-minute
    // polls, i.e. exactly the case where the baseline interval would show a
    // comfortable number while the real one crossed the band.
    static let urgentFallRateMmolLPerMin = -TrendsMath.mediumRateThreshold

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
    // The wait the poll loop uses next. Updated after every successful fetch
    // by `nextPollInterval`; starts at the baseline so a first fetch that
    // fails cannot leave the loop spinning at the urgent rate.
    private var currentPollInterval: TimeInterval = LibreLinkUpGlucoseSource.pollInterval
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
            currentPollInterval = Self.nextPollInterval(after: samples, now: Date())
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

    // Adaptive interval (cgm-connect Decision 12). Pure and `static` so every
    // branch is unit-tested without a network or an actor.
    //
    // Motivated by a field event on 2026-08-05: the Abbott app alarmed on a
    // low while MeData displayed 4.2 mmol/L measured eight minutes earlier —
    // recent enough to render as FRESH and above the 3.9 target low, so it
    // showed a confident in-range value during a genuine hypo. The staleness
    // ladder cannot detect that; only asking sooner can.
    //
    // The trade this encodes: spend the vendor's rate-limit budget where
    // staleness does harm, and nowhere else. Glucose is unremarkable the vast
    // majority of the time, so the long-run average request rate stays near
    // the 15-minute baseline and the ban exposure is a short burst during a
    // hypo rather than a permanent tripling.
    //
    // `readings` is whatever the last fetch returned, in any order.
    static func nextPollInterval(after readings: [GlucoseSample], now: Date) -> TimeInterval {
        let sorted = readings.sorted { $0.nativeInstant < $1.nativeInstant }
        guard let latest = sorted.last else { return pollInterval }
        if latest.mmolL < urgentThresholdMmolL { return urgentPollInterval }
        // Reuse the display's own rate maths so "falling fast" means the same
        // thing here as the arrow the user is looking at. A nil rate (too few
        // readings, or too short a span) is not evidence of a fall.
        let rate = TrendsMath.glucoseRate(
            sorted.map { GlucoseReading(timestamp: $0.nativeInstant, mmolL: $0.mmolL) },
            now: now)
        if let rate, rate <= urgentFallRateMmolLPerMin { return urgentPollInterval }
        return pollInterval
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Read the interval BEFORE sleeping so the value chosen by the
                // fetch that just landed governs the wait that follows it.
                guard let interval = await self?.currentPollInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
