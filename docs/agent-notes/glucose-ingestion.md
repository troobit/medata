# GlucoseIngestion Module

Live glucose ingestion (specs/data/cgm-connect). Separate SwiftPM target + library product,
deliberately NOT reachable via the `MedataCore` product — same rationale as `GlucoseGraph`:
a data stream beside the estimation pipeline. Depends on `Persistence` + `PortableContracts`
only. Contains the coordinator plus both concrete sources: `HealthKitGlucoseSource`
(`#if canImport(HealthKit)`, compiles out on macOS) and `LibreLinkUpGlucoseSource` +
`LibreLinkUpClient` (cross-platform; the module's ONLY network code, Req 3.5/7.2).

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
(÷ 18.0182, UNROUNDED). The coordinator's step 3 is the single rounding point (one
decimal, before the store's duplicate/discrepancy comparison) — do not add rounding
back to the init or the value would round twice.

**Discrepancy tally exposure**: NOT part of `GlucoseConnectionState` (design fixes that
enum's shape). Read via `coordinator.discrepancyCount(for: sourceID)` — the Phase 4
Settings UI calls this alongside consuming `stateStream()`. Session-only, in-memory
(Decision 9); resets on relaunch.

`stateStream()` yields `[String: GlucoseConnectionState]` snapshots via multi-subscriber
continuation fan-out (same `bufferingNewest(1)` policy as the store's ChangeBroadcaster),
with an immediate initial snapshot on subscribe.

`reportState(_:for:)` (also on the `GlucoseIngestSink` protocol) is how sources push
`.failed`/`.notConnected` transitions to the UI — a successful `ingest` already implies
`.connected`, including for a sourceID that never registered (sources self-announce via
their first successful ingest; accepted behaviour).

## HealthKitGlucoseSource (Phase 3, task 8)

Actor, entire file behind `#if canImport(HealthKit)` (Decision 8) — never exercised by
`make test`; verified by the iOS build. Gotchas:

- **Ack ordering is load-bearing (Decision 7)**: on an observer wake, the anchored query
  runs from the persisted anchor → `sink.ingest` → ONLY on normal return (a) persist the
  new anchor, (b) call the OS completion handler. On throw, neither — iOS re-delivers and
  `catchUp()` re-fetches from the unmoved anchor. Do not reorder.
- Anchor lives in `UserDefaults.standard` under `glucose.source.healthkit.anchor`
  (`NSKeyedArchiver` secure-coding round-trip of `HKQueryAnchor`). Cleared on disconnect.
- `connect` throws ONLY for `HKHealthStore.isHealthDataAvailable() == false`. Everything
  else (auth-request errors, backfill failure) becomes a `.failed` state — HealthKit read
  denial is opaque, so "denied" just looks like zero samples (`connected(lastReadingAt:
  nil)`, Req 2.4).
- The first anchored query (nil anchor) returns ALL history, not 90 days — keep-first
  dedup absorbs the overlap with the backfill; accepted cost, once per connect.
- `enableBackgroundDelivery` is `try?` — it throws on simulator; foreground observer +
  catch-up still cover delivery.
- Deletions from the anchored query are ignored entirely (Req 2.7, append-only).

## LibreLinkUpGlucoseSource + LibreLinkUpClient (Phase 3, task 9)

Contract in `docs/agent-notes/librelinkup-api.md`; client is a thin adapter — decode-level
tests only (`LibreLinkUpMappingTests`), no URLSession stubbing. Gotchas:

- **Keychain** (`LibreLinkUpKeychain`, service `com.medata.librelinkup`): two generic
  passwords — `credentials` (email/password) and `session` (resolved host + bearer token +
  expiry + SHA-256 account-id hash), both `kSecAttrAccessibleAfterFirstUnlock` so a locked-
  device background refresh can read them. `disconnect()` wipes both plus the UserDefaults
  host/patientId/lastSuccess keys (`glucose.source.librelinkup.*`).
- Login follows at most ONE region redirect (`status==0` + `data.redirect` →
  `api-{region}.libreview.io`); the RESOLVED host is persisted so later logins skip the hop.
  `status==4` = pending account step (surfaced, never automated); status 920 / HTTP 403
  body-status 920 = version floor (bump `LibreLinkUpClient.versionHeader`).
- 401 gets exactly one re-login retry (drop cached session → `fetchOnce()` again); a second
  401 lands in `.failed`.
- Readings: `ValueInMgPerDl` ONLY (converted via the mgPerDl init, coordinator rounds);
  `FactoryTimestamp` parsed as UTC `"M/d/yyyy h:mm:ss a"` en_US_POSIX and doubles as
  `nativeID` (no stable per-reading id). Latest measurement + graphData dedup on it.
- First followed patient wins when the account follows several — documented minimal
  developer-phase behaviour.

### Phase 4 hand-off points

- Construct sources (`HealthKitGlucoseSource()`, `LibreLinkUpGlucoseSource()`), register
  with the coordinator, `connect(sink: coordinator)`.
- LibreLinkUp UI must call `setCredentials(email:password:)` BEFORE `connect`.
- On app foreground: call each source's `catchUp()` (Req 2.6 / 3.2).
- BGTask: register `LibreLinkUpGlucoseSource.backgroundTaskIdentifier`
  (`com.medata.librelinkup.refresh`) in Info.plist + background-modes, handler calls
  `performBackgroundFetch() async -> Bool` → `setTaskCompleted(success:)`. BGTask
  registration deliberately does NOT live in this module.
- HealthKit needs the entitlement + `NSHealthShareUsageDescription` (task 12).
