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
- A failed `connect` (auth request or backfill throw) never arms ongoing delivery, so a
  successful `catchUp()` re-arms it: after `ingestFromAnchor()` returns it calls
  `startObserverQuery()` (guarded to run once) and retries `enableBackgroundDelivery`.
- `ingestFromAnchor` has an `isIngesting` reentrancy guard — an observer wake and a
  catch-up interleaving on the actor both load the same anchor; the overlapping run is
  skipped (never lossy, keep-first absorbs the re-fetch).
- A failed observer-wake ingest is un-acked but surfaces NO `.failed` state — deliberate
  asymmetry with `catchUp()`: iOS re-delivery + on-open catch-up retry it, and transient
  background failures should not flap Settings.
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

## App wiring (Phase 4, tasks 10–12)

`App/GlucoseConnectionsModel.swift` (`@Observable @MainActor`) owns the one
`IngestionCoordinator` plus both sources for the whole app; constructed in
`MedataApp.init` right after the store, threaded MedataApp → AppRoot → SettingsView →
`GlucoseConnectionsView` (a plain `.sheet` off the "Glucose data" section, same pattern
as the screenshot-import row).

- **Launch reconnect flags**: `glucose.source.healthkit.connected` /
  `glucose.source.librelinkup.connected` (UserDefaults bools, set on connect, cleared on
  disconnect). The flags are mirrored observably in the model as `connectedSourceIDs`
  (seeded from UserDefaults at init, mutated wherever the flag is persisted) —
  **UserDefaults is persistence only and is never read in view bodies**: `@Observable`
  cannot track a defaults read, so the rows would not re-render. `start()` (called from
  `MedataApp.init` so a background BGTask launch still runs it; the Task is retained as
  `startTask`) registers both sources, subscribes `stateStream()`, then calls
  `connect(sink:)` for each flagged source — the LLU branch through the same
  do/catch → `.failed` mapping as HealthKit's, no silent swallow. This reconnect is
  load-bearing: sources hold no cross-launch sink and the observer/anchor and poll
  lifecycles all hang off `connect`; without it, `catchUp()` no-ops and nothing ingests.
- **Intent guards**: `busySourceIDs` marks sources with a connect/disconnect Task in
  flight; the view disables the buttons so a slow LibreLinkUp connect cannot be
  double-tapped into concurrent `setCredentials`/`connect`. A `setCredentials` throw
  clears the connected flag again in the catch.
- **`.failed` re-exposes the LLU credential form**: the credential fields show not only
  when disconnected but also when the source is flagged-connected AND its state is
  `.failed`, so wrong credentials are correctable in place (re-connect stores the new
  credentials and retries) without knowing that Disconnect resets them.
- **Generation-counter guard on connect/disconnect**: both sources hold a
  `connectionGeneration` that `disconnect()` increments; `connect` (and LLU's
  `fetchAndIngest`) captures it at entry and bails out of post-await continuations —
  starting polling, arming the observer, reporting `.connected` — when it changed. A
  disconnect that interleaves an in-flight connect therefore leaves no poll loop, no
  armed observer, and no zombie `.connected` state.
- **Foreground catch-up**: `scenePhase == .active` in App.swift →
  `catchUpConnectedSources()` (guarded by the flags; racing the launch reconnect is
  harmless — nil sink no-ops, HealthKit has the reentrancy guard).
- **BGTask registration point**: `registerBackgroundRefresh()` is called from
  `MedataApp.init()` (must precede didFinishLaunching), `using: .main` so the launch
  handler matches the model's MainActor isolation. Handler: re-schedule the next
  `BGAppRefreshTaskRequest` (15 min) FIRST, then `performBackgroundFetch()` →
  `setTaskCompleted(success:)`; a not-connected LibreLinkUp completes as a successful
  no-op. Initial request submitted when LibreLinkUp connects (including launch
  reconnect); pending request cancelled on disconnect. The expiration handler is armed
  BEFORE the work Task starts (via a locked box holding the Task) and cancels it —
  cancellation surfaces through the URLSession await as a failed fetch, so the task
  still completes. The handler awaits `startTask` first, so a background cold launch
  cannot fetch before the reconnect attached the sink.
- **Counters on disconnect** (Req 6.2): the model calls the coordinator's
  `resetDiscrepancyTally(for:)` (added in Phase 4) before the source's `disconnect()`.
- **LibreLinkUp last-fetch display**: `LibreLinkUpGlucoseSource.persistedLastSuccessAt()`
  (static, nonisolated) reads the persisted UserDefaults value so the Settings sheet
  shows it without hopping onto the actor.
- **Capabilities**: `MeData/MeData.entitlements` (`com.apple.developer.healthkit` +
  `.healthkit.background-delivery`), `CODE_SIGN_ENTITLEMENTS = MeData.entitlements` in
  both app-target configs; `INFOPLIST_KEY_NSHealthShareUsageDescription` beside the other
  usage strings; `BGTaskSchedulerPermittedIdentifiers` (`com.medata.librelinkup.refresh`)
  and `UIBackgroundModes = fetch` in the partial `MeData/Info.plist` (arrays cannot be
  `INFOPLIST_KEY_` settings). Entitlements are NOT validated by the
  `CODE_SIGNING_ALLOWED=NO` simulator build — a device install needs a signing profile
  with HealthKit enabled.
- LibreLinkUp UI calls `setCredentials(email:password:)` BEFORE `connect` (the model's
  `connectLibreLinkUp(email:password:)` sequences this).

## Update cadence — what actually limits it (investigated 2026-08-05)

Prompted by the device question "is the app updating in real time, and is there a
medical-priority claim we can make in Xcode that would help?". Short answer: **the
mechanism that entitlement question is reaching for already exists, is already claimed,
and is not the bottleneck.** The bottleneck is a vendor rate limit and which source is
connected.

### Measured reality on the primary device

`Documents/meals.sqlite` pulled 2026-08-05 (see `device-build-and-test.md` for the
`devicectl copy from` recipe): **396 `bsl` rows — 282 `librelinkup`, 114 screenshot-import,
`healthkit` ZERO.** Gaps between consecutive live rows: 15 min ×152, 5 min ×96, 10 min ×31,
25 min ×1, 515 min ×1 (a sensor outage).

The modal 15-minute gap is **the app's own poll interval**, not the sensor's:
`LibreLinkUpGlucoseSource.pollInterval = 15 * 60`, chosen because 3-minute polling has
caused LibreLinkUp account bans. That is a **vendor-side** limit; no iOS entitlement
touches it. (This is also what forced the trend window from 15 to 30 minutes —
`glucose-lock-widget` Decision 15.)

### The three delivery paths, and what governs each

| Path | Mechanism | Governed by |
|---|---|---|
| Foreground LibreLinkUp | `pollTask` every 15 min while foregrounded | Vendor rate limit (ban risk below ~3 min) |
| Background LibreLinkUp | `BGAppRefreshTaskRequest`, `earliestBeginDate` +15 min | iOS, best-effort. `earliestBeginDate` is a floor, not a schedule — Apple's own forum guidance is that BackgroundTasks offers no frequency guarantee and is driven by device conditions and app-usage patterns |
| HealthKit | `HKObserverQuery` + `enableBackgroundDelivery(frequency: .immediate)` | The OS wakes the app when a sample is written — the closest thing iOS has to push |

### On "declare it medical for priority"

There is no entitlement that raises background-refresh priority for medical apps. What
exists, and why each does not apply here:

- **`com.apple.developer.healthkit.background-delivery`** — the real mechanism, and it is
  **already in `MeData.entitlements`**, already paired with `frequency: .immediate` in
  `HealthKitGlucoseSource`. Nothing to add.
- **Critical Alerts** (`com.apple.developer.usernotifications.critical-alerts`) — Apple
  approval required; lets a notification break through silent/Focus. It governs *alerting*,
  not data-refresh cadence. Irrelevant until the app has glucose alarms.
- **Bluetooth background entitlements** (`com.apple.developer.bluetooth-central-background`
  and the screen-off scanning pair) — restricted entitlements: the former is the **watchOS**
  gate, the latter governs screen-off scanning. NEITHER is needed for an iPhone app to be
  woken by BLE connection/notify events — the self-service `bluetooth-central`
  `UIBackgroundModes` value suffices (cgm-direct Decision 4). Do not re-read this bullet as
  "direct BLE needs special approval"; it does not, and `specs/data/cgm-direct` Phase A builds
  on exactly that.
- **Regulated-medical-device declaration** (App Store Connect) — a disclosure for review,
  not a runtime capability. Confers no scheduling priority.
- **`NSSupportsLiveActivitiesFrequentUpdates`** — raises the push budget for Live
  Activities. The app has no Live Activity; it would be a real option if a
  during-the-day glucose Live Activity were ever wanted.

### HealthKit is NOT the real-time lever for Abbott — corrected 2026-08-05

An earlier version of this note recommended connecting HealthKit to get OS-driven
immediate wakes. **That is wrong for this sensor and is recorded here so it is not
re-proposed.** Abbott's Libre app does not integrate with Apple Health in a way that
delivers readings as they are measured — whatever reaches HealthKit arrives late and
batched, so `HKObserverQuery` + `frequency: .immediate` fires promptly on a write that was
itself already stale. The iOS mechanism is genuinely immediate; the vendor's write is not,
and no entitlement or query configuration changes that.

HealthKit remains worth connecting for **completeness** — a second source, backfill, and
resilience if LibreLinkUp auth breaks — which is what `specs/data/cgm-connect` task 14
verifies. It is not a latency fix.

### So what actually bounds freshness

`LibreLinkUpGlucoseSource.pollInterval`, and nothing else. Every other path is either
slower (BGAppRefreshTask, unguaranteed) or not real-time at source (HealthKit, above).
Reducing it is the only lever, and it is a **judgement call with account-ban risk, not an
engineering decision**: the 15 minutes was chosen because ~3-minute polling has caused
LibreLinkUp account bans. The middle ground (5–10 min) is untested against the vendor's
tolerance. Do not change it without an explicit decision recorded — a ban costs the data
stream entirely, which is strictly worse than a 15-minute lag.

The sensor itself measures far more often than the app can safely ask, so the ceiling here
is the vendor's rate limit, not the hardware.

### Field event 2026-08-05 01:30 UTC — in-range value displayed during a low alarm

The sharpest evidence yet of what the poll interval costs, and it is not a latency
inconvenience — it is a wrong reading at the moment the reading matters most.

| Time (UTC) | Event |
|---|---|
| 01:22:45 | Libre measures **4.2** (ingested, snapped to the 01:25 mark) |
| ~01:28–01:30 | Sensor goes low; **the Abbott app alarms** |
| 01:30:43 | Libre measures **3.7** |
| ~01:31 | Developer opens the Abbott app to dismiss the alarm; MeData fetches within ~1 min and the Lock Screen widget updates immediately |

At alarm time MeData held 4.2 from 01:22:45 — roughly 8 minutes old, therefore **inside**
`GlucoseTimeline.staleAge` (15 min). So it rendered **fresh, in-range** (4.2 > the 3.9 target
low), with no `LO` token and no warning colour, while the sensor was low enough to alarm. The
staleness ladder did not misfire; the value genuinely was recent by ingestion age. The display
was wrong because the *feed* was behind, and nothing in the render layer can detect that.

**HealthKit was not the mechanism for the immediate update** — the DB still held zero
`healthkit` rows afterwards, confirming the correction above. The likely trigger is the device
unlock to dismiss the alarm prompting iOS to run the pending `BGAppRefreshTask`; the 01:30
reading was already available from LibreLinkUp, MeData simply had not asked yet.

**Structural limit, stated plainly:** the Abbott app alarms from a direct BLE link to the
sensor. MeData reads LibreLinkUp, a cloud follower, on a 15-minute poll. MeData cannot match
that latency by any configuration and must never be the surface relied on to catch a hypo.
That is a property of the data path, not a bug to fix.

**The one lever that would have helped here** is adaptive polling: keep the 15-minute interval
while glucose is unremarkable, and tighten it when the last reading is low or falling fast —
concentrating the vendor rate-limit budget on exactly the window where staleness does damage,
while leaving the long-run average request rate near today's. This WAS then implemented as cgm-connect
Decision 12 (2026-08-05: 5-minute urgent interval while below 5.0 mmol/L or falling ≥ 0.111
mmol/L/min, nine tests) — and subsequently superseded by Decision 13 (see the update below).

## Update 2026-08-13 — uniform 5-minute baseline (cgm-connect Decision 13)

The explicit decision the paragraphs above demanded now exists, twice over. cgm-connect
Decision 12 implemented adaptive polling; cgm-connect **Decision 13 supersedes it with a uniform
5-minute baseline** — one shared constant in `LibreLinkUpKit`, honoured by both the app's poll
loop and the widget's shared rate gate (glucose-lock-widget Decision 16, extension-side refresh).
Decision 12's adaptive machinery stays in code but dormant (every branch yields 5 minutes); it is
the designated **rollback position** — if the account is rate-limited or banned, restore the
15-minute baseline and the adaptive tightening resumes governing without new code. The statements
above that "the modal 15-minute gap is the app's own poll interval" and "pollInterval = 15 * 60"
describe the pre-Decision-13 state.

As landed (task 16), the symbols are:

- `LibreLinkUpPolling.interval` (`MedataCore/Sources/LibreLinkUpKit/LibreLinkUpSharedState.swift`) —
  the one interval. `LibreLinkUpGlucoseSource.pollInterval` forwards to it; rollback is editing
  this single constant back to `15 * 60`.
- `LibreLinkUpRateGate` — one timestamp in the App Group suite, written by whichever process
  fetched. `fetchAndIngest` skips while it is closed; `connect()` alone passes
  `ignoringRateGate: true`, because a user who just typed a password must get a connection state
  rather than silence.
- `LibreLinkUpSharedState` — connected flag, resolved host and patient id, moved out of
  `UserDefaults.standard` into the App Group suite so the widget can read them; the keychain items
  moved to the shared access group for the same reason.
  `migrateFromAppPrivateStorage()` runs once at launch and is a no-op thereafter.
- `LibreLinkUpPollIntervalTests.testAdaptiveMachineryIsDormantAtTheSharedInterval` pins the
  dormancy; the branch tests around it are the rollback contract, not dead weight.

The client itself (`LibreLinkUpClient`, `LibreLinkUpKeychain`) moved out of `GlucoseIngestion`
into the Foundation-only `LibreLinkUpKit` so the widget extension can link it without GRDB.
`LibreLinkUpClient.readings(from:)` stops at the vendor's own reading type; the
`GlucoseSample` step stayed in `GlucoseIngestion`
(`MedataCore/Sources/GlucoseIngestion/LibreLinkUpSamples.swift`).
