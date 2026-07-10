# Design: CGM Connect

## Overview

Live glucose ingestion behind a source abstraction, writing `bsl` events (mmol/L) into the
existing event log. HealthKit is the primary source (on-device, no network); a LibreLinkUp
follower is a complement (on-device auth, network poll). All sources snap readings to the
5-minute grid and hand them to one coordinator, which writes them through `PersistenceStore`
where keep-first dedup handles cross-source and intra-batch duplicates. A source advances its
durable position (HealthKit anchor / LibreLinkUp cursor) **only after** the write commits, so a
background kill cannot lose readings. Ingestion lives in a module the estimation targets do not
depend on, enforced by a package-graph test.

Requirements traced: [1](requirements.md#1) abstraction, [2](requirements.md#2) HealthKit,
[3](requirements.md#3) LibreLinkUp, [4](requirements.md#4) storage, [5](requirements.md#5) dedup,
[6](requirements.md#6) UI, [7](requirements.md#7) firewall.

## Module layout and the firewall (Req 7)

New SwiftPM target **`GlucoseIngestion`**, added to `Package.swift`:

- Depends on: `Persistence`, `PortableContracts`. The HealthKit source lives **inside** this
  target behind `#if canImport(HealthKit)` — HealthKit compiles in for the iOS build and compiles
  out on the macOS test host (HealthKit is unavailable on macOS), so `canImport` keeps *all*
  ingestion code in the one dedicated module and still lets the coordinator, dedup, LibreLinkUp
  client, and firewall test build and run under `make test` (Decision 8). This closes the gap of
  an app-layer HealthKit adapter the package graph could not police.
- The estimation targets (`Pipeline`, `CaptureKit`, `Segmentation`, `Volume`, `Macros`,
  `MetricScale`, `SupportPlane`, `CardDetection`, `Confidence`, `Foods`) keep their current
  dependency lists — none gains `GlucoseIngestion`.
- **Firewall test** (Req 7.1): `GlucoseIngestionTests` runs `swift package dump-package`, parses
  the JSON target graph, and asserts that the **transitive** dependency closure of each estimation
  target excludes `GlucoseIngestion`. Transitive, not direct-edge — `Pipeline → Persistence` and
  `GlucoseIngestion → Persistence` both exist, so a direct-edge check would miss a
  `Pipeline → … → GlucoseIngestion` path. The generated `dump-package` graph is the single source
  of truth (no hand-maintained fixture, which would only assert the copy is clean). The test
  invokes the SwiftPM subprocess from the test process; the toolchain is on PATH under `make test`.

```
GlucoseIngestion (SwiftPM target; macOS-testable, HealthKit #if canImport)      Persistence
  GlucoseSource (protocol)   HealthKitGlucoseSource  (#if canImport(HealthKit))    ingestLiveBsl([LiveBslReading])
  IngestionCoordinator (actor, is the GlucoseIngestSink) ───────────────────────▶  (keep-first txn, per-row metadata)
  LibreLinkUpGlucoseSource   grid-snap · mmol/L normalise                          eventsDidChange (once per batch)
        │
  App (iOS): SettingsGlucoseView + @MainActor GlucoseConnectionsModel (mirrors coordinator state stream)
```

## GlucoseSource protocol and the ingest ack (Req 1, 2.5)

Delivery is **pull-with-ack**, not fire-and-forget, so a source only advances its durable cursor
after the readings are committed.

```swift
public enum GlucoseConnectionState: Sendable, Equatable {
    case notConnected
    case connected(lastReadingAt: Date?)          // lastReadingAt derived from the event log
    case failed(reason: String, lastSuccessAt: Date?)
}

public struct GlucoseSample: Sendable, Equatable {
    public let nativeInstant: Date      // pre-snap; kept in metadata (Req 4.2)
    public let mmolL: Double            // already normalised (Req 5.5)
    public let nativeID: String?        // HK sample UUID / LibreLinkUp key, if any
}

// The coordinator implements this. `ingest` returns only after the transaction
// commits; it throws if the write failed. A source calls it and, on success,
// advances its cursor and (HealthKit) calls the OS completion handler.
public protocol GlucoseIngestSink: Sendable {
    func ingest(_ samples: [GlucoseSample], from sourceID: String) async throws -> BslIngestSummary
}

public protocol GlucoseSource: Sendable {
    var id: String { get }
    func state() async -> GlucoseConnectionState
    func connect(sink: GlucoseIngestSink) async throws   // source drives, acks via sink
    func disconnect() async
}
```

Each source owns its own scheduling (HealthKit observer callbacks; LibreLinkUp timer/refresh),
calls `sink.ingest(batch, from: id)`, and treats a successful return as the durable commit.

## IngestionCoordinator (Req 1.2, 4, 5)

An `actor` implementing `GlucoseIngestSink` and owning the connected sources.

`ingest(samples, from:)`:
1. Normalise (already mmol/L one-decimal; convert mg/dL per Req 5.5) and snap each `nativeInstant`
   to the nearest 5-minute grid mark → `timestampMs` (Decision 4). Tiebreak for a sample exactly
   between two marks: round half to the later mark (deterministic).
2. **Collapse intra-batch collisions:** group by snapped `timestampMs`; for a bucket with more
   than one sample, keep the one whose `nativeInstant` is closest to the mark (ties → earliest
   `nativeInstant`). This is required because the store's keep-first loop reads only committed
   rows, so two same-mark samples in one batch would otherwise both insert (finding #5; the
   `events` table has no `(timestamp,event_type)` unique constraint).
3. Build `[LiveBslReading]` (grid `timestampMs`, mmol/L value, `sourceID`, `nativeInstantMs`,
   `nativeID?`) and call `PersistenceStore.ingestLiveBsl` once for the batch.
4. Await the returned `BslIngestSummary`; add its `discrepant.count` to the source's in-session
   discrepancy tally (Decision 9) and update the derived `lastReadingAt`. Emit a new state
   snapshot on the coordinator's state stream (below).

Because readings are snapped onto `timestampMs`, the store's existing keep-first keys on the grid
instant, so a screenshot reading and a live reading at the same mark collide across batches for
free (Req 5.1, 5.2). Intra-batch collisions are handled in step 2.

**State to UI:** the coordinator exposes `func stateStream() -> AsyncStream<[String: GlucoseConnectionState]>`.
A `@MainActor @Observable GlucoseConnectionsModel` consumes it in a `.task` and mirrors the
snapshot for `SettingsGlucoseView`, so `.failed`/`.connected` transitions push to the UI without
polling (finding #10).

## Persistence: extract the keep-first helper, add live ingestion (Req 4)

`ingestBsl` today **inlines** the keep-first merge inside its `queue.write` closure. Refactor that
body into a private helper both paths call, so the dedup rule has one implementation (finding #1):

```swift
// Private to GRDBPersistenceStore. Runs inside an open write txn. Keep-first at
// timestampMs, per-row metadata, tracks in-batch inserts so two same-mark rows
// cannot both write. Returns counts + discrepancies. No processed-image marker.
private func mergeBslKeepFirst(
    _ db: Database, _ rows: [(timestampMs: Int64, value: Double, metadataJSON: String)]
) throws -> (stored: Int, agreeing: Int, discrepant: [BslIngestSummary.Discrepancy])
```

The helper seeds `covered` from committed rows (the existing `SELECT … timestamp IN (…)`) **and
adds each freshly inserted `timestampMs` to `covered`** before the next iteration, closing the
intra-batch hole. `ingestBsl` calls it with the same metadata JSON for every row and then writes
the `processed_images` marker; the new sibling calls it with per-row metadata and no marker:

```swift
// PersistenceStore. Typed input; the STORE serialises metadata (matching
// saveInsulinDose), so GlucoseIngestion never builds event JSON (finding #2).
// One transaction; notifies eventsDidChange once iff ≥1 row inserted (Req 4.4).
func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary

public struct LiveBslReading: Sendable, Equatable {
    public let timestampMs: Int64        // 5-minute grid
    public let mmolL: Double             // one decimal
    public let sourceID: String
    public let nativeInstantMs: Int64
    public let nativeID: String?
}
```

The store builds each row's `metadata` = `{"source_id":…,"native_instant_ms":…,"native_id":…}`
(`native_id` key omitted when nil), mirroring how `saveInsulinDose` owns its JSON. No schema
change — `events.metadata` is free-form JSON, `id` is the only key.

## HealthKit source (Req 2) — in-module, `#if canImport(HealthKit)`

- **Auth (2.1, 2.2):** `requestAuthorization(toShare: [], read: [glucoseType])`. HealthKit read
  status is opaque by design, so "granted but empty" is indistinguishable from "some data" until
  a query runs — treat a successful query returning zero samples as `connected(lastReadingAt: nil)`
  (2.4); `connect` throws only when the store is unavailable.
- **Unit (2.8):** read via the mmol/L `HKUnit` (`.moleUnit(with:.milli, molarMass:
  HKUnitMolarMassBloodGlucose).unitDivided(by:.liter())`); no conversion.
- **Backfill (2.3):** one `HKSampleQuery` over `[now−90d, now]` with no result limit returns all
  matching samples in a single callback → delivered as **one** `ingest` batch → one transaction →
  one `eventsDidChange` tick (finding #7). A reconnection re-runs it; keep-first skips stored rows.
- **Ongoing (2.5) with durable ack:** `HKObserverQuery` + `enableBackgroundDelivery(…,
  frequency:.immediate)`. On each wake: run an `HKAnchoredObjectQuery` from the persisted anchor →
  `try await sink.ingest(newSamples, from: id)`; **only if that returns** (commit durable) persist
  the returned anchor and then call the observer completion handler. On throw: neither the anchor
  nor the completion handler advances, so iOS re-delivers and Req 2.6 catch-up re-fetches (finding
  #8). Anchor stored in `UserDefaults` keyed by source.
- **Catch-up (2.6):** on foreground, run the anchored query once from the persisted anchor.
- **Deletions (2.7):** anchored-query deletion objects ignored — append-only (Decision 3).
- Capability + `NSHealthShareUsageDescription` per `prerequisites.md`.

## LibreLinkUp source (Req 3) — in-module

- **Credentials (3.1):** captured in the connect screen, stored in Keychain
  (`kSecClassGenericPassword`, accessibility `kSecAttrAccessibleAfterFirstUnlock` so a locked-device
  background refresh can read them — `prerequisites.md`), never in the event log/metadata; cleared
  on disconnect (6.2).
- **Poll (3.2):** a timer fetch at ≤15 min while foregrounded; a `BGAppRefreshTask` (identifier in
  `prerequisites.md`) for best-effort background; a catch-up fetch on foreground. Interval + rate
  limits confirmed by the prerequisites spike.
- **Fetch → ack (3.3):** map the payload to `[GlucoseSample]` (mg/dL → mmol/L at 18.0182 when the
  account reports mg/dL, Req 5.5; `nativeID` set if the API exposes a stable key, else nil), call
  `sink.ingest`; on success update the persisted last-success time and cursor.
- **Failure (3.4):** network/credential/sharing failure → `state = .failed(reason, lastSuccessAt)`;
  readings retained; retry next schedule.
- **Firewall (3.5, 7):** all `URLSession` use is confined to this type in `GlucoseIngestion`.

## Settings UI (Req 6)

`SettingsGlucoseView` (app), reached from the existing Settings surface. A list of source rows;
each shows name, state (connected + last-reading time; LibreLinkUp also last-success time and the
in-session discrepancy count), and a connect/disconnect control. Connect presents the HealthKit
auth sheet or the LibreLinkUp credential form. Copy is functional only — no disclaimer/consent/
reassurance text (6.3, Decision 6); mmol/L only (6.4). Follows the existing settings-row pattern
rather than new styling. State comes from `GlucoseConnectionsModel` (the coordinator's state
stream), so rows update live on `.failed`/`.connected`.

## Data flow (HealthKit, ongoing)

```
CGM app → Apple Health → HKObserverQuery wake → anchored query from anchor (mmol/L)
   → HealthKitGlucoseSource: try await sink.ingest(newSamples, id)
        → IngestionCoordinator: snap→grid, collapse intra-batch, build [LiveBslReading]
        → PersistenceStore.ingestLiveBsl (keep-first txn) → eventsDidChange (once)
        → returns BslIngestSummary  ── commit durable ──▶ back to source
   → source persists anchor, calls observer completion handler
   → Trends chart refreshes (unchanged)
```

## Testing strategy

Per the project minimal-test gate (keep MedataCore logic tests green; no app-UI test target). New
`GlucoseIngestionTests`:

- **Grid-snap** boundary cases (exact mark, +2:29, +2:30 half-to-later, −2:30) → expected
  `timestampMs`.
- **Intra-batch collapse:** a batch with two samples snapping to one mark stores exactly one row
  (nearest-to-mark wins; tie → earliest instant).
- **Unit convert:** mg/dL → mmol/L at 18.0182, one decimal, incl. the 0.3-threshold boundary.
- **Cross-source dedup/discrepancy:** pre-seed a screenshot reading at a grid instant; a live
  reading at the same instant stores nothing and (if >0.3 apart) increments the discrepancy tally;
  stored value unchanged; single `eventsDidChange`.
- **`mergeBslKeepFirst` refactor parity:** `ingestBsl`'s existing behaviour (and its accuracy/dedup
  tests) stay green after extraction.
- **Ack semantics:** a sink that throws leaves the source's anchor/cursor unadvanced (fake sink).
- **Firewall (7.1):** the `dump-package` transitive-closure assertion above.
- HealthKit and LibreLinkUp live network/store I/O are not unit-tested against real services; the
  sources are thin adapters over the tested coordinator, and the LibreLinkUp client is validated in
  the prerequisites spike.

## Out of scope (design confirms)

No chart changes (Trends already reads `bsl`); no estimation changes; no activity/weight; no
favourites/logbook/text-search. Screenshot importer behaviour unchanged — it shares the extracted
keep-first helper but keeps its processed-image marker and per-image summary.
</content>
