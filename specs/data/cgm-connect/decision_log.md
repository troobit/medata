# Decision Log: CGM Connect

## Decision 1: Live glucose connection is a new spec, not an extension of libre-ingestion

**Date**: 2026-07-10
**Status**: accepted

### Context

MeData already has a glucose importer: `specs/data/libre-ingestion` extracts readings from
LibreLink screenshots via on-device OCR. The SNAQ study surfaced a live "connect once, keep
access" connection as the headline value item. The question was whether to extend
libre-ingestion or open a new spec.

### Decision

Open a new spec `specs/data/cgm-connect` for the live connection. It reuses libre-ingestion's
`bsl` event contract and keep-first dedup semantics but is a distinct feature; the screenshot
importer remains as a fallback and is not modified beyond the shared contract.

### Rationale

libre-ingestion explicitly lists "CGM/HealthKit/third-party sync" as a Non-Goal — it was scoped
to screenshots on purpose. The live path has a different mechanism (authorisation, background
delivery, network sync), a different failure surface, and a different UI. Folding it into
libre-ingestion would blur a clean boundary and bloat a completed spec. PROCESS.md §3 ("is it a
new spec or an extension?") favours a new spec when the mechanism and lifecycle differ this much.

### Alternatives Considered

- **Extend libre-ingestion**: Add live sources to the existing spec — Rejected: overloads a
  spec whose whole premise is on-device screenshot extraction; the Non-Goal was deliberate.
- **One monolithic "glucose" spec** replacing both: Rejected: discards a shipped, tested
  screenshot path and its accuracy corpus for no gain; the two coexist cleanly via `bsl` events.

### Consequences

**Positive:**
- Clean boundary; the screenshot path stays a documented fallback.
- Both sources converge on the same event-log contract, so the chart and dedup are shared.

**Negative:**
- Cross-source dedup is now a real requirement (Req 5) — a reading can arrive from screenshot
  import and a live source.

---

## Decision 2: HealthKit as the primary source, LibreLinkUp as the complement, behind one abstraction

**Date**: 2026-07-10
**Status**: accepted

### Context

SNAQ ingests glucose two ways: a LibreLinkUp follower connection (paste a generated identity
into the Libre app) and an Apple Health read. The "connect once" screens (IMG_0629/0630) match
the LibreLinkUp pattern literally, but HealthKit is the route more devices converge on over time.
The user was asked which route the spec should assume.

### Decision

Build a glucose-source abstraction (Req 1) and treat **HealthKit as the primary, extensible
source** (Req 2), with a **LibreLinkUp follower source** (Req 3) as a complement for devices that
do not yet write to Health. Adding a future source is a normal extension behind the same
interface.

### Rationale

The user chose "spike both, HealthKit-forward, iterate as more devices write to HealthKit
(Libre 3)". HealthKit keeps ingestion on-device (no network), aligns with the offline-core
invariant, and is the same bridge a later activity/weight extension would use. LibreLinkUp still
matters now for devices not yet writing to Health, so it ships as a peer source rather than being
dropped — but the network dependency is confined to that one source and firewalled from
estimation.

### Alternatives Considered

- **LibreLinkUp only**: Matches the SNAQ screens most literally — Rejected: puts a network
  dependency on the critical path for all users and does not generalise to other CGMs; ages
  poorly as devices move to HealthKit.
- **HealthKit only**: Simplest, fully offline — Rejected: strands users whose device/app does
  not write glucose to Health today; the user explicitly wanted the LibreLinkUp route available.

### Consequences

**Positive:**
- Primary path is offline and generalises across CGM vendors.
- Network scope is isolated to one source and one code path, easing the estimation firewall.

**Negative:**
- Two ingestion mechanisms to maintain, with different authorisation and failure models.
- Background delivery (HealthKit) and scheduled fetch (LibreLinkUp) are different runtime shapes.

---

## Decision 3: Append-only readings; no deletion mirroring

**Date**: 2026-07-10
**Status**: accepted

### Context

HealthKit samples can be deleted by the user or another app; LibreLinkUp can revoke sharing.
The question was whether MeData should mirror upstream deletions.

### Decision

Stored `bsl` events are append-only. A deletion or revocation upstream stops future ingestion
but never deletes stored readings (Req 2.5, Req 3.3).

### Rationale

This matches the screenshot importer, which never deletes on re-import, and preserves the data
owner's record as the single source of truth. Mirroring deletions would let an external app
silently destroy MeData's history, which contradicts the event-log "never silently destroy"
principle.

### Alternatives Considered

- **Mirror upstream deletions**: Keep MeData in lock-step with Health — Rejected: cedes control
  of the record to external apps and breaks the append-only guarantee the event log relies on.

### Consequences

**Positive:**
- Predictable, non-destructive history; consistent with libre-ingestion.

**Negative:**
- A reading deleted upstream as erroneous stays in MeData until a future editing feature exists
  (out of scope here).

---

## Decision 4: Snap live readings to the nearest 5-minute grid for one shared dedup key

**Date**: 2026-07-10
**Status**: accepted

### Context

The screenshot importer emits readings on exact 5-minute wall-clock marks and dedups on that
`timestamp`. Live sources do not: a HealthKit/LibreLinkUp sample is stamped whenever the sensor
reported (e.g. 14:03:47). Cross-source dedup (Req 5) is only well-defined if all sources share
one timestamp domain — otherwise a screenshot reading at 14:05:00 and a live reading at 14:03:47
for the same physical measurement never collide.

### Decision

On ingest, snap each live reading's instant to the nearest 5-minute grid mark and store that as
the event `timestamp` (Req 4.1, Req 5.1). The native pre-snap instant is preserved in `metadata`
(Req 4.2). Dedup and discrepancy checks operate on the grid instant for every source.

### Rationale

Screenshot readings are already on the grid; snapping live readings onto the same grid makes the
keep-first rule apply uniformly across sources with no special cases. Five minutes is the CGM
native cadence, so nearest-mark snapping introduces at most ~2.5 minutes of timestamp shift while
retaining the true instant in metadata for anyone who needs it. It reuses libre-ingestion's dedup
semantics rather than inventing a windowed comparison.

### Alternatives Considered

- **Store native instants, dedup on a ±window**: Keeps exact timestamps — Rejected: introduces a
  windowed-match algorithm that diverges from libre-ingestion's exact-key dedup and makes
  cross-source collisions ambiguous at window edges.
- **Snap only LibreLinkUp, leave HealthKit native**: Rejected: two grids again; HealthKit vs
  screenshot readings would not dedup.

### Consequences

**Positive:**
- One dedup key across all sources; libre-ingestion's rule reused unchanged.
- Native instant retained in metadata, so no information is lost.

**Negative:**
- The stored `timestamp` differs from the sensor's native instant by up to ~2.5 minutes.
- Two genuine samples within one 5-minute bucket collapse to one stored reading (acceptable at
  CGM cadence).

---

## Decision 5: LibreLinkUp authenticates on-device; no MeData follower backend

**Date**: 2026-07-10
**Status**: accepted

### Context

SNAQ's "connect once" LibreLinkUp screens (IMG_0629/0630) generate a follower identity the user
pastes into the Libre app; SNAQ's own server is the follower that then holds credentials and
polls LibreLinkUp. MeData has no backend and the estimation core is offline-first, so the SNAQ
pattern cannot be copied literally.

### Decision

The LibreLinkUp source authenticates directly against a LibreLinkUp account from the device and
stores credentials in the system Keychain (Req 3.1). No MeData-hosted follower service is built.
The exact on-device flow is a prerequisites research item (`prerequisites.md`); HealthKit
(primary) does not depend on it, so the feature ships without LibreLinkUp if the research stalls.

### Rationale

A hosted follower service would add a backend, a network dependency for a core data path, and a
credential-custody burden that contradict MeData's offline, single-user, no-backend posture.
On-device auth keeps the network scope inside the one LibreLinkUp source, firewalled from
estimation (Req 7). Making HealthKit primary means LibreLinkUp can be deferred without blocking
the feature.

### Alternatives Considered

- **Build a hosted follower service (SNAQ's model)**: Literal parity with the SNAQ screens —
  Rejected: adds a backend and standing credential custody for a single-user developer app;
  contradicts the offline-core invariant.
- **Drop LibreLinkUp entirely, HealthKit only**: Simplest — Rejected: the user explicitly wanted
  the LibreLinkUp route available for devices not yet writing to Health.

### Consequences

**Positive:**
- No backend; network confined to one on-device source.
- LibreLinkUp is decoupled from the feature's ship-readiness.

**Negative:**
- The on-device LibreLinkUp API flow is unofficial and undocumented — a real research/robustness
  risk carried in `prerequisites.md`.
- The MeData connect UX diverges from the SNAQ screens (credentials captured on-device, not a
  paste-identity handoff).

---

## Decision 6: Keep the no-disclaimer rule as an AC; move the SNAQ image citations here

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 6.3 forbids disclaimer/consent/reassurance copy on the connection screens. An earlier draft
cited specific SNAQ screenshots (IMG_0624, IMG_0680–0681) inside the AC, which would be opaque to
a future reader of the spec in isolation.

### Decision

Keep the behavioural rule in Req 6.3 and record the SNAQ provenance here instead: the excluded
patterns are SNAQ's intended-use gate (IMG_0624) and its "I agree not to use estimates for
insulin dosing" consent checkbox (IMG_0680/0681), plus the recurring "we never share or sell your
data" reassurance line. This enforces the project developer-phase no-disclaimer invariant.

### Rationale

Requirements should read standalone; provenance belongs in the decision log. The rule itself is a
standing CLAUDE.md invariant, so the AC states the behaviour and the log carries the "why/from
where".

### Alternatives Considered

- **Leave image numbers in the AC**: Rejected: couples the requirement to an external screenshot
  set a future reader will not have.

### Consequences

**Positive:**
- Req 6.3 reads standalone; provenance preserved without cluttering the requirement.

**Negative:**
- The tie back to specific SNAQ screens now lives one hop away, in this log.

---

## Decision 7: Durable-ack ingestion (advance source cursor only after commit)

**Date**: 2026-07-10
**Status**: accepted

### Context

HealthKit background delivery hands the app an observer completion handler and an anchored query
whose anchor advances as samples are read. A first design sketch used a fire-and-forget
`AsyncStream` from source to coordinator. The design review showed that persisting the anchor (or
calling the OS completion handler) before the database write commits loses readings if the app is
killed mid-ingest: the anchor has advanced, so neither background re-delivery nor the on-open
catch-up (Req 2.6) re-fetches them.

### Decision

Model delivery as pull-with-ack: the coordinator implements a `GlucoseIngestSink` whose `ingest`
returns only after the write transaction commits. A source calls `try await sink.ingest(...)` and
advances its durable cursor (HealthKit anchor, LibreLinkUp last-success) and calls the OS
completion handler **only on success**; on throw it advances nothing and retries.

### Rationale

Tying cursor advancement to commit durability is the only way to make Req 2.5/2.6 lossless. An
`AsyncStream` cannot express the acknowledgement, and its buffering policy would silently drop or
queue batches under back-pressure. The ack model is also simpler to test (a throwing fake sink
proves the cursor does not advance).

### Alternatives Considered

- **Fire-and-forget `AsyncStream<[GlucoseSample]>`**: Simplest to wire — Rejected: no commit
  acknowledgement, so background delivery can lose readings; buffering behaviour undefined.
- **Persist anchor first, reconcile later**: Rejected: requires a separate reconciliation pass and
  still has a loss window.

### Consequences

**Positive:**
- Lossless background ingestion; cursor and event log cannot diverge.
- Clear, testable contract between source and coordinator.

**Negative:**
- Sources must hold their scheduling logic and await the sink, rather than emitting passively.

---

## Decision 8: HealthKit source lives in the ingestion module behind `#if canImport(HealthKit)`

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 7.1 requires all ingestion code to live in a dedicated module the estimation targets do not
depend on, enforced by a package-graph test. HealthKit is unavailable on the macOS test host, so a
first sketch put the HealthKit source in the iOS app target — but the package-graph test cannot see
the app target's imports, leaving the most import-prone source outside the firewall it is meant to
enforce.

### Decision

Keep the HealthKit source inside the `GlucoseIngestion` SwiftPM target, guarded by
`#if canImport(HealthKit)`. It compiles in for the iOS build and compiles out on macOS, so the
module still builds and its coordinator/dedup/firewall tests run under `make test`.

### Rationale

`canImport` gives cross-platform source in one target without an app-layer split, so Req 7.1's
"dedicated module" holds for *all* ingestion code and the package-graph test actually covers the
HealthKit source. The macOS test host simply sees an empty source; its logic is exercised through
the platform-agnostic coordinator.

### Alternatives Considered

- **HealthKit source in the app target**: Rejected: outside the package graph the firewall test
  inspects, so the test cannot police it — contradicts Req 7.1.
- **A separate iOS-only HealthKit target**: Rejected: an extra target and dependency edge for one
  adapter; `canImport` achieves the same isolation in-module.

### Consequences

**Positive:**
- All ingestion, including HealthKit, sits in the module the firewall test guards.

**Negative:**
- HealthKit code paths are not exercised on the macOS test host (unchanged from any iOS-only code);
  covered by the coordinator tests plus on-device verification.

---

## Decision 9: Discrepancy count is per-session, not persisted

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 6.1 surfaces a discrepancy count (readings that arrive differing >0.3 mmol/L from a stored
value). An earlier draft said "cumulative since connection", which implies storage surviving
relaunch and a reset on disconnect — machinery for a single-user developer-phase app.

### Decision

Accumulate the discrepancy count in memory over the current app session; reset it on relaunch or
disconnect. The readings themselves persist (the event log is the source of truth); only the
convenience counter is ephemeral.

### Rationale

The count is a diagnostic signal for one developer, not a stored record. A session-scoped in-memory
tally needs no persistence layer and no reset bookkeeping, matching the project's minimal-machinery
posture. Anyone needing the full history can query the event log.

### Alternatives Considered

- **Persist the count across launches**: Rejected: storage + reset lifecycle for a throwaway
  diagnostic; over-engineered for the audience.

### Consequences

**Positive:**
- No persistence or reset machinery; the counter is trivial.

**Negative:**
- The count resets on relaunch, so it reflects the current session only (documented in Req 6.1).
</content>

---

## Decision 10: lastReadingAt is session-scoped delivery state, not event-log-derived

**Date**: 2026-07-10
**Status**: accepted

### Context

The design sketch annotated `GlucoseConnectionState.connected(lastReadingAt:)` with "derived
from the event log". The Phase 2 implementation instead tracks, in coordinator memory, the
newest grid instant each source has successfully delivered through a committed ingest this
session — advancing even when keep-first stored zero new rows. The Phase 2 design-critic
review flagged the two documents as disagreeing: after a relaunch the value is nil until the
first ingest, and a fully-deduplicated batch still advances it.

### Decision

The implementation's semantics are authoritative: `lastReadingAt` is the newest snapped
instant the source delivered through a committed `ingest` in the current app session. It is
not persisted and not re-derived from the event log; the design sketch's annotation is
superseded by this entry.

### Rationale

Keep-first dedup means a second connected source may never win a stored row, so an
event-log-derived value would sit permanently stale for a healthy source — misreporting the
"is it delivering?" signal Req 6.1 exists to surface. Delivery-time semantics answer that
question directly. Session scope matches Decision 9 (the discrepancy tally): both are
diagnostic conveniences for one developer, repopulated within minutes by the on-open
catch-up, and need no persistence or reset machinery. Attributing rows per source from the
event log would also require a metadata-querying store API that exists for no other purpose.

### Alternatives Considered

- **Query the store for the source's latest bsl row (design sketch's wording)**: Rejected:
  needs a new metadata-filtered query API, and keep-first attribution leaves the losing
  source permanently stale despite healthy delivery.
- **Persist lastReadingAt per source across launches**: Rejected: storage and reset
  lifecycle for a throwaway diagnostic — the same over-engineering Decision 9 declined.

### Consequences

**Positive:**
- Reflects actual delivery, unaffected by which source wins the keep-first race.
- No new store API, no persistence machinery; consistent with Decision 9.

**Negative:**
- Nil after relaunch until the first ingest, even though readings exist in the log (the
  on-open catch-up repopulates it promptly).

## Decision 12: Adaptive poll interval — tighten to 5 minutes while low or falling fast

**Date**: 2026-08-05
**Status**: accepted

### Context

The LibreLinkUp poll interval was fixed at 15 minutes (Req 3.2), chosen because ~3-minute polling has caused LibreLinkUp account bans. A field event on 2026-08-05 showed what that costs at the worst possible moment.

The Abbott app alarmed on a low. At that instant MeData was displaying **4.2 mmol/L, measured at 01:22:45** — about eight minutes old. Eight minutes is well inside `GlucoseTimeline.staleAge` (15 min), so the reading rendered as **fresh**, and 4.2 is above the 3.9 target low, so it rendered **in-range**: no `LO` token, no warning colour. The next measurement, 3.7 at 01:30:43, was already available from LibreLinkUp; the app simply had not asked. It arrived within a minute of the device being unlocked to dismiss the alarm, which appears to have prompted iOS to run the pending `BGAppRefreshTask`.

So this was not a display bug. The staleness ladder behaved exactly as specified, and there is nothing the render layer can inspect to know the feed is behind — a reading's *age* is knowable, its *obsolescence* is not. Only fetching sooner helps.

### Decision

The poll interval is chosen after each successful fetch by a pure function of the readings it returned:

- **5 minutes** when the newest reading is below **5.0 mmol/L**, or the fetched readings are falling at or faster than **0.111 mmol/L per minute** (`TrendsMath.mediumRateThreshold`).
- **15 minutes** otherwise.

The 15-minute baseline is unchanged, and 5 minutes is a floor.

### Rationale

The premise is that requests are a budget and staleness is not uniformly harmful. At 7 mmol/L and flat, a 15-minute-old reading costs nothing. Approaching 4, it is the difference between a number that describes the user and one that does not. Spending the budget only in the second case leaves the long-run average request rate close to today's — glucose is unremarkable the large majority of the time — so the ban exposure is a short burst during a hypo rather than a permanent tripling of traffic. That is what makes this acceptable where a uniform 5-minute poll is not.

The threshold sits at 5.0 rather than at the 3.9 band edge deliberately: tightening *after* arriving at a low would reproduce the failure, because the poll is what makes the display late in the first place. 5.0 starts the tightening on the approach. The fall-rate trigger covers the case the level test cannot — a 9.0 falling hard is comfortable now and will not be in twenty minutes, and at 15-minute polling the display would show the comfortable number across the whole descent.

Reusing `TrendsMath.glucoseRate` rather than writing a second rate calculation means "falling fast" means the same thing to the scheduler as to the arrow the user is looking at; a divergence between those two would be very hard to reason about in the field.

5 minutes rather than 3: 3 is the rate known to have caused bans, so the urgent path stays clear of it even during a sustained hypo. A test asserts that floor, since this constant governs behaviour against a third party that can revoke access entirely.

### Alternatives Considered

- **Uniform 5-minute poll**: simplest, uniformly fresher — Rejected: triples the *sustained* request rate against a service that bans at ~3 minutes. A ban costs the entire data stream, which is strictly worse than a 15-minute lag.
- **Leave it at 15 minutes and document the limitation**: no vendor exposure at all — Rejected after the field event. The failure is not a lag the user can mentally correct for; the app showed a confident in-range value during a hypo, and the user's decision was to fix it.
- **Trigger only on the band status (`< 3.9`)**: reuses an existing concept, no new constant — Rejected: it tightens only after the low has arrived, which is exactly too late given the poll is the source of the delay.
- **Push or webhook from LibreLinkUp**: no polling at all — Not available; LibreLinkUp is a pull-only follower API.
- **Use HealthKit for low-latency delivery instead**: OS-driven immediate wakes, already entitled and implemented — Rejected on evidence: Abbott does not write to Apple Health as readings are measured, so an immediate `HKObserverQuery` wake still carries stale data. The device DB held zero `healthkit` rows before and after the event, confirming it was not the mechanism for the observed update either.

### Consequences

**Positive:**
- During the window where staleness does harm, the display is at most ~5 minutes behind instead of ~15.
- The long-run average request rate stays close to the 15-minute baseline, so ban exposure barely moves.
- The trigger reuses the display's own rate maths, so scheduler and arrow cannot disagree.
- Nine tests pin every branch, including a floor assertion on the urgent interval.

**Negative:**
- Request rate is now data-dependent, so vendor-facing traffic is harder to predict — a long hypo sustains 5-minute polling for its duration.
- Two more tuned constants (5.0 mmol/L, 0.111 mmol/L/min) with no field validation behind the specific values yet.
- A noisy sensor oscillating around 5.0 will flap between intervals. Harmless, but no hysteresis.
- Battery and data use rise slightly during lows; not measured.
- **This does not make MeData safe to rely on for hypo detection.** The Abbott app alarms from a direct BLE link to the sensor; MeData reads a cloud follower. Five minutes is better than fifteen and is still not real time.

### Impact

`LibreLinkUpGlucoseSource` (`pollInterval`, new `urgentPollInterval` / `urgentThresholdMmolL` / `urgentFallRateMmolLPerMin` / `nextPollInterval` / `currentPollInterval`, poll loop), Req 3.2a, and a new `GlucoseIngestion` → `Persistence` use of `TrendsMath`. The background-fetch `earliestBeginDate` is unchanged at 15 minutes — iOS governs that delivery and does not honour a request as a schedule, so tightening it would add vendor exposure without adding freshness.

---
