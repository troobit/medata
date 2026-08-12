import Foundation
import GlucoseWidgetShared
import Persistence

// Routes every source's readings through one ingestion path (Req 1.2):
// snap each sample onto the 5-minute grid (Decision 4), collapse
// intra-batch collisions, write the batch once through
// `PersistenceStore.ingestLiveBsl`, and only then return — the durable ack
// a source needs before advancing its cursor (Decision 7). Store errors
// rethrow untouched so a failed write never advances anything.
public actor IngestionCoordinator: GlucoseIngestSink {

    private let store: any PersistenceStore

    // Registered sources (Req 1.3, 1.4). Phase 4 wires the real ones; until
    // a source connects and ingests, its state stays whatever `state()`
    // reported at registration (`.notConnected` for a fresh source — no
    // error, no event-log writes).
    private var sources: [String: any GlucoseSource] = [:]

    // Per-source state mirrored to the UI via stateStream().
    private var states: [String: GlucoseConnectionState] = [:]

    // In-session discrepancy tally per source (Req 5.4, Decision 9):
    // in-memory actor state only, reset on relaunch. Deliberately NOT part
    // of GlucoseConnectionState (the design fixes that shape); the Settings
    // UI reads it via `discrepancyCount(for:)`.
    private var discrepancyTallies: [String: Int] = [:]

    // Latest snapped instant a successful ingest has committed per source —
    // the derived `lastReadingAt` in the connected state.
    private var lastReadingMs: [String: Int64] = [:]

    private var stateContinuations:
        [UUID: AsyncStream<[String: GlucoseConnectionState]>.Continuation] = [:]

    public init(store: any PersistenceStore) {
        self.store = store
    }

    // MARK: - Source registry (Req 1.3, 1.4)

    public func register(_ source: any GlucoseSource) async {
        sources[source.id] = source
        states[source.id] = await source.state()
        emitStateSnapshot()
    }

    // MARK: - GlucoseIngestSink (Req 1.2, 4, 5)

    public func ingest(
        _ samples: [GlucoseSample], from sourceID: String
    ) async throws -> BslIngestSummary {
        // One bucket per snapped grid mark: keep the sample whose native
        // instant is closest to the mark; ties → earliest native instant.
        // Required because the store's keep-first loop reads only committed
        // rows — two same-mark samples in one batch would otherwise race.
        var buckets: [Int64: GlucoseSample] = [:]
        for sample in samples {
            let mark = Self.snapToGrid(Self.instantMs(sample.nativeInstant))
            if let incumbent = buckets[mark],
                !Self.wins(sample, over: incumbent, at: mark) {
                continue
            }
            buckets[mark] = sample
        }
        let readings = buckets
            .sorted { $0.key < $1.key }
            .map { mark, sample in
                LiveBslReading(
                    timestampMs: mark,
                    // The single rounding point (Req 5.5): one decimal,
                    // before the store's duplicate/discrepancy comparison.
                    mmolL: GlucoseGrid.roundedMmolL(sample.mmolL),
                    sourceID: sourceID,
                    nativeInstantMs: Self.instantMs(sample.nativeInstant),
                    nativeID: sample.nativeID
                )
            }

        // Durable-ack contract (Decision 7): a throw here propagates to the
        // source, which must NOT advance its cursor.
        let summary = try await store.ingestLiveBsl(readings)

        discrepancyTallies[sourceID, default: 0] += summary.discrepant.count
        if let latest = readings.map(\.timestampMs).max() {
            lastReadingMs[sourceID] = max(lastReadingMs[sourceID] ?? .min, latest)
        }
        let lastReadingAt = lastReadingMs[sourceID].map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        }
        // An unregistered sourceID minting a `.connected` entry here is
        // accepted behaviour: sources self-announce via their first
        // successful ingest.
        states[sourceID] = .connected(lastReadingAt: lastReadingAt)
        emitStateSnapshot()
        return summary
    }

    // State transitions outside the ingest path (Req 6.1, GlucoseIngestSink):
    // sources push `.failed` / `.notConnected` / `.connected` here so the UI
    // sees them without polling.
    public func reportState(_ state: GlucoseConnectionState, for sourceID: String) {
        states[sourceID] = state
        emitStateSnapshot()
    }

    // MARK: - State to UI (Req 1.4, 6.1)

    // Yields a snapshot dict (sourceID → state) on subscription and after
    // every state change. `bufferingNewest(1)` so a slow UI consumer sees
    // the latest snapshot, not a backlog — same policy as the store's
    // eventsDidChange broadcaster.
    public func stateStream() -> AsyncStream<[String: GlucoseConnectionState]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            stateContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeStateContinuation(id) }
            }
            continuation.yield(states)
        }
    }

    // In-session discrepancy tally for one source (Req 5.4, 6.1). Zero for
    // an unknown source.
    public func discrepancyCount(for sourceID: String) -> Int {
        discrepancyTallies[sourceID, default: 0]
    }

    // Req 6.2 / Decision 9: disconnecting a source resets its status
    // counters. The tally is in-memory session state, so dropping the key
    // is the whole reset.
    public func resetDiscrepancyTally(for sourceID: String) {
        discrepancyTallies[sourceID] = nil
    }

    private func removeStateContinuation(_ id: UUID) {
        stateContinuations[id] = nil
    }

    private func emitStateSnapshot() {
        for continuation in stateContinuations.values {
            continuation.yield(states)
        }
    }

    // MARK: - Grid snapping (Req 5.1, Decision 4)

    // Both moved to `GlucoseGrid` (GlucoseWidgetShared) so the widget's
    // extension-side fetch preprocesses vendor readings exactly as this path
    // does before deriving its snapshot (glucose-lock-widget Decision 16) —
    // otherwise the same data could yield a different arrow on the two
    // surfaces. Kept as forwards because the intra-batch bucketing below and
    // its tests speak in these names.
    static func snapToGrid(_ instantMs: Int64) -> Int64 {
        GlucoseGrid.snapToGrid(instantMs)
    }

    private static func instantMs(_ instant: Date) -> Int64 {
        GlucoseGrid.instantMs(instant)
    }

    // Intra-batch tiebreak: nearest to the mark wins; equal distance →
    // earliest native instant wins.
    private static func wins(
        _ challenger: GlucoseSample, over incumbent: GlucoseSample, at mark: Int64
    ) -> Bool {
        let challengerDistance = abs(instantMs(challenger.nativeInstant) - mark)
        let incumbentDistance = abs(instantMs(incumbent.nativeInstant) - mark)
        if challengerDistance != incumbentDistance {
            return challengerDistance < incumbentDistance
        }
        return challenger.nativeInstant < incumbent.nativeInstant
    }
}
