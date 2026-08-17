# Decision Log: CGM Direct

## Decision 1: New spec, sibling to cgm-connect, not an extension of it

**Date**: 2026-08-17
**Status**: accepted

### Context

The user asked for a way for the iPhone to read the FreeStyle Libre 3+ patient data directly from
the worn device (BLE or other). A live-glucose ingestion feature already exists and ships:
`specs/data/cgm-connect` pulls readings from the LibreLinkUp cloud on a rate-limited poll, behind a
`GlucoseSource` abstraction, writing `bsl` events. The question is whether direct-device access is
a new requirement section on that spec or its own capability.

### Decision

Create a new spec `specs/data/cgm-direct` in the `data` domain, as the direct-from-device sibling of
`specs/data/cgm-connect`. It references cgm-connect's storage, dedup, and firewall contracts rather
than duplicating them.

### Rationale

Per `specs/PROCESS.md` §3, a new spec is warranted when the work delivers a new acceptance bar.
Direct-device BLE access has its own bar — a BLE transport, a background-wake mechanism, and a
research track toward on-device decryption — none of which cgm-connect's cloud-follower criteria
cover. The two share the `bsl` output contract, which is exactly the "reference, don't duplicate"
cross-spec relationship §3 prescribes.

### Alternatives Considered

- **Extend cgm-connect with BLE requirements**: Add sections to the existing spec - Rejected: it
  would mix two acceptance bars (cloud-follower vs direct-device) in one folder, against §3, and
  bloat a spec that is already shipped and stable.
- **A bugfix/smolspec against the staleness problem**: Treat this as tuning cgm-connect's poll -
  Rejected: the mechanism is a new BLE subsystem with background execution and a safety tradeoff,
  far past the smolspec bar (§5).

### Consequences

**Positive:**
- Clean separation; cgm-connect stays a stable cloud-follower spec.
- The BLE work has its own decision log and can carry the fast-moving feasibility record.

**Negative:**
- Two glucose specs to keep coherent; cross-references must stay correct as either evolves.

---

## Decision 2: The heartbeat is a wake source, not a reading GlucoseSource

**Date**: 2026-08-17
**Status**: accepted

### Context

Phase A connects a second BLE central to the sensor. In Phase A the BLE payload is **not**
decrypted — the connection/notify event carries no usable glucose value; the value is still fetched
from the LibreLinkUp cloud. The existing `GlucoseSource` protocol
(`MedataCore/Sources/GlucoseIngestion/GlucoseSource.swift`) is defined around producing
`GlucoseSample` batches and delivering them to the sink.

### Decision

Model the heartbeat as a distinct wake-source type that emits a value-less heartbeat signal and
triggers the existing `LibreLinkUpGlucoseSource` fetch entry point. It does not conform to
`GlucoseSource` and never writes to the event log itself.

### Rationale

A `GlucoseSource` that returned no samples, or synthesised a value it did not measure, would be a
lie in the type system and would risk writing an unattributable reading. Separating "a reading
exists now" (the heartbeat) from "here is the reading" (the cloud fetch) keeps provenance truthful:
the stored row stays attributed to `librelinkup` because the cloud is still where the value came
from (Req 4.1).

### Alternatives Considered

- **Make the heartbeat a GlucoseSource that fetches internally**: Fold the cloud fetch into a new
  source - Rejected: duplicates `LibreLinkUpGlucoseSource`'s fetch/dedup/rate-gate logic and would
  double-count against the shared vendor budget.
- **Synthesise a sample from the notify payload**: Emit a placeholder reading on heartbeat -
  Rejected: the payload is encrypted in Phase A; any value would be fabricated.

### Consequences

**Positive:**
- Truthful provenance; no new stored source id in Phase A; the shared budget stays one budget.
- The wake mechanism is reusable for another vendor's transmitter later.

**Negative:**
- A second abstraction beside `GlucoseSource` to hold; the wiring between wake and reading source
  must be explicit.

---

## Decision 3: Phase A respects the vendor rate budget — no per-minute cloud freshness claim

**Date**: 2026-08-17
**Status**: accepted

### Context

The heartbeat fires ~every minute. The naive read is "fetch the cloud every minute → 1-minute
freshness". But the LibreLinkUp cloud carries a shared ~5-minute rate budget (`cgm-connect`
Decision 13); ~3-minute-and-faster polling is the rate with known account-ban evidence. An early
framing of this feature claimed "~1-minute freshness", which is not safely achievable from the
cloud.

### Decision

Phase A's heartbeat-triggered fetch remains subject to the existing shared `LibreLinkUpRateGate`.
The honest Phase A value is (a) a reliable background wake that does not depend on iOS running a
deferred `BGAppRefreshTask`, and (b) a reading-aligned, budget-bounded fetch. No code, copy, or log
may claim per-minute cloud freshness. True per-minute network-free freshness is a Phase B property
only, because on-device decrypt has no cloud and no ban budget.

### Rationale

The 2026-08-05 field failure (`cgm-connect` Decision 12) was fundamentally a *missed wake*: the
reading existed in the cloud but iOS had deferred the refresh task, running it only when the phone
was unlocked. A BLE connection event is a reliable background wake and fixes that root cause without
increasing request rate. Increasing request rate to chase 1-minute cloud values would trade a
staleness problem for a ban problem — strictly worse, since a banned account loses all readings.

### Alternatives Considered

- **Bypass the rate gate on heartbeat for 1-minute polling**: Highest freshness - Rejected: this is
  the banned rate; a ban ends all ingestion, the opposite of the goal.
- **Raise the shared budget**: Poll faster but sub-1-minute - Rejected: still moves toward the ban
  rate for a gain Phase B delivers for free once unblocked.

### Consequences

**Positive:**
- No new ban exposure; the biggest real win (reliable background wake) is preserved.
- Sets an honest expectation that the network-free freshness goal is Phase B.

**Negative:**
- Phase A does not, by itself, guarantee sub-5-minute freshness; the urgent-fetch benefit depends on
  the adaptive-urgency machinery (Decision 12) being re-armed.

---

## Decision 4: MeData-can-activate for Phase B, gated behind a test sensor and Phase A default

**Date**: 2026-08-17
**Status**: accepted

### Context

Phase B (on-device decrypt) needs the sensor's blePIN. On Android (Juggluco) the blePIN is obtained
by the app **activating the sensor itself** as owner (feasibility note "Why Android can and iOS
can't"). Doing that displaces the official Abbott app's ownership of that sensor, and with it
Abbott's realtime hypo alarms. The user was asked and chose to allow MeData to activate the sensor.

### Decision

Phase B may NFC-activate the sensor as owner to obtain the blePIN, accepting loss of Abbott's alarms
on that sensor. This is gated: it is a deliberate, user-confirmed act (Req 7.4); it SHALL NOT run on
the user's live sensor until the full decrypt path is proven end-to-end on a separate test sensor;
and Phase A (coexisting heartbeat + cloud value, Abbott app and alarms intact) remains the everyday
path until then.

### Rationale

Activation-as-owner is the only known route past Blocker 1 (blePIN) on iOS, so foreclosing it would
foreclose Phase B. But displacing Abbott's alarms is a genuine safety cost, so it is bounded by a
test-sensor-first gate and kept off the everyday path. This gives the research route a door without
putting the user's live hypo alarms at risk before the path actually works.

### Alternatives Considered

- **Must-coexist only (never activate)**: Keep Abbott's alarms always - Rejected by the user: it
  leaves Phase B permanently blocked on the blePIN.
- **Activate the live sensor now**: Fastest path to attempt decrypt - Rejected: sacrifices working
  alarms for an iOS path that is not yet proven (feasibility note Blocker 3).

### Consequences

**Positive:**
- Phase B has a viable route; the safety cost is bounded and reversible (use a test sensor).

**Negative:**
- When Phase B is eventually exercised on the live sensor, Abbott's official alarms are lost on it;
  the user accepts this tradeoff knowingly.

---
