# Libre 3 / 3+ direct-device access (BLE) — feasibility

**Status: living document. The frontier moves ~monthly; every claim below is stamped. Re-verify
before acting.** This exists because the user asked for a way for the iPhone to read the
FreeStyle Libre 3 Plus *directly from the device they wear*, not via a cloud follower. The user
owns the sensor (installed in their body) and has authorised breaking Abbott's transport to
collect their own data. This note is the feasibility record; the spec that frames it is
`specs/data/<direct-cgm>` (to be created).

## The one distinction that governs everything

BLE to a Libre 3 buys two *different* things, and they have opposite feasibility:

1. **Heartbeat (wake signal only) — FEASIBLE ON iOS TODAY, proven in shipping code.**
   A second BLE central connects to the sensor *alongside* Abbott's own app. Every ~1 minute
   the sensor produces a reading and the connection/notify event fires. You learn *"a new
   reading exists now"* — you do **not** decrypt the value. The value still comes from the
   LibreLinkUp cloud.

   **What this buys, stated honestly — it does NOT license per-minute cloud polling.** The
   LibreLinkUp cloud has a shared ~5-minute rate budget (cgm-connect Decision 13); fetching it
   every minute is the ~3-min-and-faster rate that gets accounts *banned*. So the heartbeat's
   value is not "1-minute freshness from the cloud". It is:
   - **A reliable background wake.** A BLE reconnection wakes the app even while suspended. This
     is the actual root-cause fix for the 2026-08-05 hypo-latency event (cgm-connect Decision
     12): the reading *existed*, but iOS had **deferred** the `BGAppRefreshTask` and only ran it
     when the phone was unlocked. A BLE central wake does not depend on that deferral.
   - **Reading-aligned fetch, within the existing budget.** The (still rate-gated) fetch lands
     just after a new value is in the cloud rather than on a blind timer, and supplies the
     dormant adaptive-urgency machinery (Decision 12) a true "new reading now" trigger.
   True per-minute, network-free freshness is **Phase B only** — local decrypt has no cloud and
   no ban budget, so the 1-minute stream is free there.

2. **Full local decrypt (value on-device, zero cloud) — BLOCKED ON iOS as of 2026-06.**
   Decrypt the BLE payload so the mmol/L value is derived on-device with no network at all.
   This is the true "own the data" goal and the no-network-purity win. It is currently not
   achievable in a standalone iOS app. Details below.

## Evidence: heartbeat is real and shippable (JohanDegraeve/xdripswift, master, checked 2026-08-17)

`xDrip/BluetoothTransmitter/HeartBeat/Libre3HeartbeatBluetoothTransmitter.swift`:

- Scans for and connects to **any peripheral whose name starts with `ABBOTT`** (the
  transmitterID is a 3–5 char prefix; "It will connect to anything that starts with name
  ABBOTT").
- Receive characteristic (the one-minute reading): `0898177A-EF89-11E9-81B4-2A2AE2DBCCE4`.
  Write characteristic nominally `F001` (never written). Advertisement service UUID unknown —
  it scans with `servicesCBUUIDs: nil` and "that works."
- On `didConnect` **and** on `didUpdateValueFor` it fires `heartBeat()` — but throttled by
  `minimumTimeBetweenTwoHeartBeats = 30 s`, and it deliberately **waits 1 s "to allow the
  official app to upload to LibreView before triggering the heartbeat"**. So even xDrip's BLE
  path still reads the *value* from the cloud; BLE is purely the wake.
- `secondsUntilHeartBeatDisconnectWarningLibre3 = 70 s` — one missed minute-tick = warning.
- Runs in parallel with Abbott's app: iOS CoreBluetooth allows multiple centrals to connect to
  one peripheral. Abbott owns the authenticated session; the heartbeat central just observes
  connect/notify events. It does **not** need the blePIN to see connection events.

Implication for MeData: a `Libre3HeartbeatSource` is a realistic addition to the
`GlucoseIngestion` module — a BLE central that, on each heartbeat, triggers the existing
`LibreLinkUpGlucoseSource` fetch immediately. No estimation-path contact (Req 7). It is a
*latency* mechanism, not an independent data source; the value provenance stays LibreLinkUp.

## Evidence: full local decrypt is blocked on iOS (gui-dos/DiaBLE Discussion #22, read 2026-08-17)

DiaBLE is the reference iOS reverse-engineering effort. State as of ~2026-06:

- BLE is a certificate exchange + 23-byte challenge, ECDH on P-256, then AES-128-CCM on the
  1-minute data. The historical data lags ~17 min; only the 1-minute stream is realtime.
- **Blocker 1 — blePIN**: "without the blePIN, no stable connection is possible." The PIN is
  tied to the sensor's activation state and the user's Libre **accountID**. An *unactivated*
  sensor won't yield its blePIN unless the accountID is presented at activation.
- **Blocker 2 — key extraction**: the app's static private key ("appStaticPrivateKey blobs are
  WhiteCryption encrypted, we can't extract the raw scalar"). Protected by
  WhiteCryption/Zimperium SKB (a white-box crypto VM).
- **Blocker 3 — iOS injection**: gui-dos hasn't run the NFC init "in practice on iOS because of
  the technical impossibility of injecting into iOS native libraries" to run the white-box VM.
- **Frontier is moving**: `LibreCRKit` (a WhiteCryption VM *interpreter*) "showed promise" for
  key extraction; a contributor reported a Libre 3 ↔ Apple **Watch** "stable connection … for 3
  hours" (2026-06-17). So a pure-Swift white-box interpreter may eventually remove Blocker 2/3.
  Re-check DiaBLE + LibreCRKit each cycle.

## Why Android can and iOS can't (the asymmetry)

Juggluco (Android, juggluco.nl/Juggluco/libre3) reads Libre 3 fully locally. It works because
**Juggluco activates the sensor itself**: Settings → Exchange data → Libreview → Get Account ID
→ enter an (even arbitrary, "manual") accountID → NFC-scan to activate. Activating *as the owner*
is how it obtains the blePIN, and Android permits the native-lib execution the white-box needs.
Two consequences for any iOS attempt at full decrypt:

- You would have to let **MeData activate the sensor instead of the Abbott app** (or as a second
  reader), presenting an accountID at NFC activation. That displaces or competes with the
  official app's ownership of that sensor — a real usage tradeoff to confirm with the user.
- Even with activation, iOS still faces Blocker 3 until a pure-Swift white-box path (LibreCRKit)
  is proven on-device. Not there yet (2026-08).

**Owner decision (2026-08-17):** the user has chosen **MeData-can-activate** for Phase B —
MeData may NFC-activate the sensor as owner (Juggluco-style) to obtain the blePIN, accepting
that the official Abbott app loses that sensor and its **realtime hypo alarms** with it. This
removes Blocker 1 for Phase B by design. Blocker 3 (iOS white-box execution) remains the gate.
Because activation displaces Abbott's alarms, Phase A (coexisting heartbeat + cloud value, Abbott
app and its alarms intact) stays the everyday path until Phase B decrypt is actually proven on
iOS — do not activate-as-owner on the user's live sensor to chase Phase B until the on-device
decrypt works end-to-end on a test sensor first.

## Data-custody middlemen (context, not a dependency)

- **Abbott LibreView / LibreLinkUp** — current cgm-connect follower path. Pull-only, 5–15 min.
- **Ypsomed `mylife-software.net`** (user flagged, AU) — mylife/CamAPS-adjacent pump+CGM cloud
  that ingests Libre in some AU integrations. If it exposes a follower/API it is *another cloud
  custody source* on the same footing as LibreLinkUp — worth a separate spike **only** as a
  follower fallback. **Not yet investigated**; no API contract confirmed. The direct-BLE path is
  custody-independent and is the reason to prefer it over chasing whichever cloud holds the data.

## Recommendation (phasing)

- **Phase A — BLE heartbeat → immediate cloud fetch.** Shippable on iOS now, proven pattern,
  coexists with the Abbott app, no NFC, no crypto break. Turns the current best-effort 5-min
  poll into ~1-min freshness. This is the concrete near-term win.
- **Phase B — full on-device decrypt (no cloud).** Track as research against DiaBLE/LibreCRKit;
  gated on the white-box interpreter maturing on iOS and on the user accepting MeData-as-activator.
  Keep this note current; it *will* change.

## Re-verification checklist (run before trusting Phase B)

- [ ] DiaBLE Discussion #22 latest posts — is on-device iOS decrypt reported working yet?
- [ ] LibreCRKit — is a pure-Swift white-box key extraction shipping?
- [ ] Does connecting a second BLE central perturb the Abbott app / sensor on Libre 3 **Plus**
      specifically (this note's heartbeat evidence is Libre 3; verify on 3+)?
- [ ] Ypsomed mylife: is there a documented follower API for the AU account?
