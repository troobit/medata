// HealthKit glucose source (specs/data/cgm-connect Req 2).
//
// Lives inside GlucoseIngestion behind `#if canImport(HealthKit)`
// (Decision 8): HealthKit compiles in for the iOS build and compiles out on
// the macOS test host, so all ingestion code stays in the one module the
// estimation firewall test polices. No network calls anywhere in this file
// (Req 7.2) — HealthKit access is entirely on-device.
#if canImport(HealthKit)
import Foundation
import HealthKit

public enum HealthKitGlucoseSourceError: Error {
    // The only error `connect` throws (Req 2.1 design note): HealthKit read
    // authorisation is opaque, so everything past availability is reported
    // through the connection state, not thrown.
    case healthDataUnavailable
}

public actor HealthKitGlucoseSource: GlucoseSource {

    public nonisolated let id = "healthkit"

    private static let backfillDays = 90.0
    private static let anchorDefaultsKey = "glucose.source.healthkit.anchor"

    // Req 2.8: read glucose natively in mmol/L — HealthKit performs the unit
    // conversion; we never do.
    private static let mmolPerLitre = HKUnit.moleUnit(
        with: .milli, molarMass: HKUnitMolarMassBloodGlucose
    ).unitDivided(by: HKUnit.liter())

    private let healthStore = HKHealthStore()
    private let glucoseType = HKQuantityType(.bloodGlucose)

    private var sink: (any GlucoseIngestSink)?
    private var observerQuery: HKObserverQuery?
    private var connectionState: GlucoseConnectionState = .notConnected
    // Newest native instant a committed ingest has delivered this session —
    // session-scoped delivery state, mirroring Decision 10.
    private var lastDeliveredAt: Date?

    public init() {}

    // MARK: - GlucoseSource

    public func state() async -> GlucoseConnectionState { connectionState }

    // Req 2.1–2.4: request read authorisation, then backfill 90 days as ONE
    // ingest batch (one transaction, one change notification — Req 4.4/4.5).
    // HealthKit read-authorisation status is opaque by design, so a
    // successful query returning zero samples is `connected(lastReadingAt:
    // nil)` (Req 2.4); denial simply yields no samples ever (Req 2.2).
    // Throws only when the health store is unavailable on this device.
    public func connect(sink: any GlucoseIngestSink) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitGlucoseSourceError.healthDataUnavailable
        }
        self.sink = sink
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [glucoseType])
            let backfill = try await queryBackfill()
            // Keep-first makes a reconnection's re-run idempotent (Req 2.3).
            _ = try await sink.ingest(backfill.map(Self.glucoseSample(from:)), from: id)
            noteDelivered(backfill)
        } catch {
            connectionState = .failed(
                reason: error.localizedDescription, lastSuccessAt: lastDeliveredAt)
            await sink.reportState(connectionState, for: id)
            return
        }
        startObserverQuery()
        // Best-effort (Req 2.5): background delivery is OS-governed and can
        // be unavailable (simulator); the foreground observer plus the
        // on-open catch-up (Req 2.6) still cover delivery.
        try? await healthStore.enableBackgroundDelivery(for: glucoseType, frequency: .immediate)
    }

    public func disconnect() async {
        if let observerQuery { healthStore.stop(observerQuery) }
        observerQuery = nil
        try? await healthStore.disableBackgroundDelivery(for: glucoseType)
        UserDefaults.standard.removeObject(forKey: Self.anchorDefaultsKey)
        connectionState = .notConnected
        lastDeliveredAt = nil
        await sink?.reportState(.notConnected, for: id)
        sink = nil
    }

    // Req 2.6: on app foreground, Phase 4 calls this — one anchored query
    // from the persisted anchor with the same durable-ack ordering, so
    // OS-deferred or missed background wakes cannot lose readings.
    public func catchUp() async {
        guard sink != nil else { return }
        do {
            try await ingestFromAnchor()
        } catch {
            connectionState = .failed(
                reason: error.localizedDescription, lastSuccessAt: lastDeliveredAt)
            await sink?.reportState(connectionState, for: id)
        }
    }

    // MARK: - Ongoing delivery (Req 2.5, Decision 7)

    private func startObserverQuery() {
        guard observerQuery == nil else { return }
        let query = HKObserverQuery(sampleType: glucoseType, predicate: nil) {
            [weak self] _, completionHandler, error in
            // Observer-level error: nothing to fetch — ack so iOS does not
            // re-deliver a wake we cannot act on; catch-up covers any gap.
            guard let self, error == nil else {
                completionHandler()
                return
            }
            Task { await self.deliver(completionHandler: completionHandler) }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    // Durable ack ordering (Decision 7): the anchor is persisted and the OS
    // completion handler called ONLY after `sink.ingest` returns (the write
    // committed). On throw neither advances — iOS re-delivers, and the
    // on-open catch-up (Req 2.6) re-fetches from the unmoved anchor.
    private func deliver(completionHandler: @escaping () -> Void) async {
        do {
            try await ingestFromAnchor()
            completionHandler()
        } catch {
            // Deliberately no ack and no anchor advance.
        }
    }

    private func ingestFromAnchor() async throws {
        guard let sink else { return }
        let (samples, newAnchor) = try await queryAnchored(from: Self.loadAnchor())
        _ = try await sink.ingest(samples.map(Self.glucoseSample(from:)), from: id)
        Self.saveAnchor(newAnchor)
        noteDelivered(samples)
    }

    private func noteDelivered(_ samples: [HKQuantitySample]) {
        if let latest = samples.map(\.startDate).max() {
            lastDeliveredAt = max(lastDeliveredAt ?? .distantPast, latest)
        }
        connectionState = .connected(lastReadingAt: lastDeliveredAt)
    }

    // MARK: - Queries

    // Req 2.3: one HKSampleQuery over [now − 90 days, now], no limit,
    // ascending — the whole backfill arrives as a single batch.
    private func queryBackfill() async throws -> [HKQuantitySample] {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-Self.backfillDays * 86_400), end: now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: glucoseType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    // The `deletedObjects` the anchored query reports are ignored entirely
    // (Req 2.7, Decision 3): stored readings are append-only.
    private func queryAnchored(
        from anchor: HKQueryAnchor?
    ) async throws -> ([HKQuantitySample], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: glucoseType, predicate: nil, anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: ((samples as? [HKQuantitySample]) ?? [], newAnchor))
                }
            }
            healthStore.execute(query)
        }
    }

    private static func glucoseSample(from sample: HKQuantitySample) -> GlucoseSample {
        GlucoseSample(
            nativeInstant: sample.startDate,
            mmolL: sample.quantity.doubleValue(for: mmolPerLitre),
            nativeID: sample.uuid.uuidString)
    }

    // MARK: - Anchor persistence (Req 2.5)

    private static func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorDefaultsKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func saveAnchor(_ anchor: HKQueryAnchor?) {
        guard let anchor,
            let data = try? NSKeyedArchiver.archivedData(
                withRootObject: anchor, requiringSecureCoding: true)
        else { return }
        UserDefaults.standard.set(data, forKey: anchorDefaultsKey)
    }
}
#endif
