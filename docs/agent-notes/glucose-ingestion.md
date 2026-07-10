# GlucoseIngestion Module

Live glucose ingestion (specs/data/cgm-connect). Separate SwiftPM target + library product,
deliberately NOT reachable via the `MedataCore` product — same rationale as `GlucoseGraph`:
a data stream beside the estimation pipeline. Depends on `Persistence` + `PortableContracts`
only. No network code and no HealthKit code yet (Phase 3 adds the sources).

## Firewall (Req 7.1)

The estimation targets (Pipeline, CaptureKit, Segmentation, Volume, Macros, MetricScale,
SupportPlane, CardDetection, Confidence, Foods) must never gain `GlucoseIngestion` in their
transitive dependency closure. `EstimationFirewallTests` enforces this by running
`swift package dump-package` as a subprocess (macOS test host only; skips elsewhere) and
walking the JSON target graph — transitive closure, not direct edges. dump-package encodes
each dependency as a one-key object (`{"byName": [name, null]}` / `{"product": [name,
package, null, null]}`); the first array element is always the name.

## IngestionCoordinator (actor, implements GlucoseIngestSink)

`ingest(_:from:)` pipeline order matters:
1. Snap each sample's `nativeInstant` to the nearest 5-minute mark (`snapToGrid`, internal
   static for tests). Tiebreak: exactly halfway (+2:30) rounds to the LATER mark.
2. Intra-batch collapse per snapped mark — nearest-to-mark wins; distance tie → earliest
   native instant. Needed because the store's keep-first covered set only sees committed
   rows plus its own in-batch inserts; the coordinator picks WHICH same-mark sample wins,
   the store guard alone would keep whichever arrived first in array order.
3. Build `[LiveBslReading]` (mmolL re-rounded to one decimal — idempotent for already-
   normalised sources) and call `store.ingestLiveBsl` once per batch.
4. Only after the commit returns: bump the per-source in-session discrepancy tally, update
   the derived `lastReadingAt` (max snapped instant committed this session), emit a state
   snapshot. Store errors rethrow untouched — durable-ack contract (Decision 7): a throwing
   ingest means the source must NOT advance its cursor/anchor.

mg/dL → mmol/L conversion lives on `GlucoseSample.init(nativeInstant:mgPerDl:nativeID:)`
(÷ 18.0182, one decimal) so it happens exactly once, before dedup (Req 5.5).

**Discrepancy tally exposure**: NOT part of `GlucoseConnectionState` (design fixes that
enum's shape). Read via `coordinator.discrepancyCount(for: sourceID)` — the Phase 4
Settings UI calls this alongside consuming `stateStream()`. Session-only, in-memory
(Decision 9); resets on relaunch.

`stateStream()` yields `[String: GlucoseConnectionState]` snapshots via multi-subscriber
continuation fan-out (same `bufferingNewest(1)` policy as the store's ChangeBroadcaster),
with an immediate initial snapshot on subscribe.
