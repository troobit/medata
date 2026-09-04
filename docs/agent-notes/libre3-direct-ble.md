# Libre 3 / 3+ direct-device access (BLE) — feasibility

**Status: living document. The frontier moves ~monthly; every claim below is stamped. Re-verify
before acting.** This exists to support reading the FreeStyle Libre 3 Plus *directly from the
worn device*, not via a cloud follower. The user owns the sensor (installed in their body) and
has authorised breaking Abbott's transport to collect their own data. This note is the
feasibility record; the spec that frames it is `specs/data/cgm-direct`.

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
     dormant adaptive-urgency machinery (`cgm-connect` Decision 12) a true "new reading now" trigger.
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

- **Phase A — BLE heartbeat → reading-aligned, rate-gated cloud fetch.** Shippable on iOS now,
  proven pattern, coexists with the Abbott app, no NFC, no crypto break. Replaces the unbounded OS
  wake deferral with a bounded worst-case staleness of ~one gate interval plus one beat (~6 min) —
  NOT per-minute freshness (spec Req 3.5). This is the concrete near-term win.
- **Phase B — full on-device decrypt (no cloud).** Track as research against DiaBLE/LibreCRKit;
  gated on the white-box interpreter maturing on iOS and on the user accepting MeData-as-activator.
  Keep this note current; it *will* change.

## Re-verification checklist (run before trusting Phase B)

- [ ] DiaBLE Discussion #22 latest posts — is on-device iOS decrypt reported working yet?
- [ ] LibreCRKit — is a pure-Swift white-box key extraction shipping?
- [ ] Does connecting a second BLE central perturb the Abbott app / sensor on Libre 3 **Plus**
      specifically (this note's heartbeat evidence is Libre 3; verify on 3+)?
- [ ] Ypsomed mylife: is there a documented follower API for the AU account?
- [ ] Uploader route A — region-switch (spec Req 10.2/10.5, Decision 11, `docs/libre-app-region-setup.md`):
      are the App Store region-change steps and the sensor↔country lock still accurate? The worn 3+
      needs the LibreLink of its **country of purchase**; a region-mismatched iPhone can install it
      by switching App Store region (free app, Payment Method: None). This is a documented,
      recoverable route — never a block on reaching the user's own sensor.
- [ ] Uploader route B — Juggluco bridge (spec Req 10.2/10.4): can Juggluco on an Android device
      activate a 3+ and upload to LibreView (cloud path with no Abbott iOS app)? And can the MeData
      heartbeat central coexist with an **Android-held** session — the xdripswift coexistence
      evidence is same-phone only.

## Re-check log (Req 8.2 — record every re-check, moved verdict or not)

### 2026-08-18 — Phase B desk audit (cgm-direct task 12). LibreCRKit + LibreLoop read in depth for licence, protocol correctness, and adopt-vs-reimplement. Recommendation: DO NOT adopt or reimplement yet — WAIT. The verdict from the monthly re-check below ("on-device iOS decrypt is demonstrated") stands; this entry qualifies HOW it is demonstrated, and the qualification is decisive.

- **Licence is permissive but not the real constraint.** Both repos are MIT (`api.github.com/repos/airedev326/LibreCRKit/license`, `.../LoopKit/LibreLoop/license`) — no GPL/AGPL copyleft despite LibreLoop sitting under the LoopKit org. So the *wrapper* Swift is freely vendorable. That is a red herring.
- **How LibreCRKit passes the historical KDF blocker: it does not solve it — it side-steps it with extracted Abbott binary.** The old wall (feasibility section "Full local decrypt", Blocker 2) was the obfuscated WhiteCryption/Zimperium KDF that derives the data-plane AES key; gui-dos reported 70+ failed KDF-formula attempts and it is the target of his "inaccuracies and even real hallucinations" remark about `protocol.md`. LibreCRKit's `protocol.md` gives **no KDF formula**; instead the package ships ~3 MB of white-box AES lookup tables run through a 13-opcode bytecode VM (`CipherFn.swift`). The repo's own `Sources/LibreCRKit/Resources/RuntimeTables/README.md` states the `libaes_*.bin` tables "were extracted from static program regions" and are "fully determined by Abbott's lib" (verified verbatim, this audit). The key is embedded in those tables, so the VM reproduces Abbott's crypto byte-exact without anyone knowing the KDF. **Redistributing that package therefore redistributes extracted proprietary Abbott crypto — a copyright / DMCA §1201 anti-circumvention exposure that MIT cannot cure, and that reimplementing "from the documentation" cannot escape, because the KDF is not in the documentation; it is in the tables.**
- **The public-key half IS real and corroborated.** ECDSA-P256/SHA-256 sensor-certificate verification with two hardcoded Abbott patch-signing keys (`level0`/`level1`, actually present in `SensorCert.swift`), the P-256 ECDH ephemeral exchange, and AES-128-CCM as the data-plane cipher are all standard CryptoKit and independently corroborated by DiaBLE #22. The blePIN-from-NFC-activation claim is corroborated in shape. Only the KDF/table half is the extracted-binary problem.
- **Trust is genuinely split — and the credible half is real.** LibreCRKit is AI-agent-authored ("Reverse Engineer" / airedev326) with two commits by gui-dos; no independent party confirms it works standalone. But **LibreLoop is authored by Pete Schwamb (login `ps2`)** — the RileyLink designer and a core, long-standing Loop/LoopKit maintainer — whose commits cite dated worn-sensor field logs (verified: "sensor at lifeCount 21791 min (15.1 days)", 2026-07-25/26 refresh-timing logs, a 2026-07-23 ~5 h outage). That is real evidence of a working end-to-end run by a trusted party other than the LibreCRKit author — but LibreLoop works *because* it inherits LibreCRKit's extracted-table shortcut (EasyLars's independent PoC in DiaBLE #22 reaches the 23-byte challenge and still cannot pass the KDF), not because the KDF was cracked in the open.
- **Consequence for the Phase B plan.** The gate is no longer only "prove the decrypt on a test sensor" (Req 7.4, task 14). There is now a **provenance/legality gate that sits before any shipping build regardless of whether the decrypt works**: MeData cannot ship extracted Abbott lookup tables. Task 14 (test-sensor evaluation) may still verify the protocol is real; task 15 (Phase B build design) must confront table provenance as a first-class blocker — a shippable Phase B needs either a clean-room KDF derivation published openly (removing the table dependency) or an explicit, eyes-open owner decision to carry the same exposure the DIY community carries. Neither exists today, so Phase B stays unbuilt and Phase A remains the everyday path.
- **Claims to verify on a test sensor (task 14), asserted-only, not yet corroborated:** (a) the NFC-activation response actually returns a usable blePIN on a fresh pair and re-pair; (b) the bundled `level0`/`level1` keys verify a *real* sensor certificate, i.e. they are correct not placeholder; (c) the white-box VM + tables reproduce a byte-exact data-plane key and decrypt a live glucose frame — the one step with no clean-crypto fallback; (d) per-minute notifications decrypt from a locked/backgrounded state and sustain cadence on the iPhone 16 Pro floor. Independent of function, obtain legal sign-off on the extracted `RuntimeTables/*.bin` before any of this influences a shipping build.
- Caveat: file contents were read via a summarising fetch, not verified byte-for-byte; both repos were last pushed 2026-08-05 and may have moved. Nothing was cloned, run, or NFC-activated.

### 2026-08-18 — monthly frontier re-check. Verdict MOVED: on-device iOS decrypt is now demonstrated in open source. This supersedes the "BLOCKED ON iOS as of 2026-06" verdict in section "Full local decrypt" above and its Blocker 3 (iOS white-box execution).

- **On-device decrypt (Phase B) — the wall came down.** Two open-source repos now do the full
  Libre 3 / 3+ value derivation on iOS with no cloud on the value path:
  - `airedev326/LibreCRKit` (pushed 2026-08-05, last updated 2026-08-13) — a clean-room Swift
    package doing NFC activation → BLE authorization (ECDSA-P256/SHA-256 sensor-certificate verify
    with bundled Abbott patch-signing public keys, P-256 ECDH ephemeral exchange) → **post-auth
    data-plane AES-128-CCM decrypt** and realtime `glucoseData` / `patchStatus` parsing. Its own
    README states "A LibreView account is not a protocol requirement", i.e. the value path is
    network-free. `protocol.md` documents the NFC activation response carrying the `blePIN`, which
    is how the owner-activation path (this note's "MeData-can-activate" owner decision, 2026-08-17)
    removes Blocker 1.
  - `LoopKit/LibreLoop` (pushed 2026-08-05, 1 star) — a FreeStyle Libre 3/3+ `CGMManager` plugin
    for Loop, **built on LibreCRKit**. README: "Working end-to-end on iOS. The plugin pairs with a
    Libre 3 sensor via NFC, maintains a BLE session, and delivers glucose readings to Loop every 5
    minutes." Reconnect-after-restart, historical backfill, and sensor end-of-life tracking are all
    described as functional, and commit messages cite dated field logs against real worn sensors
    (2026-07-25 and 2026-07-26, one at lifeCount 21791 min = 15.1 days). It explicitly "bypasses the
    official Abbott FreeStyle Libre 3 app", which means the Abbott app's alarms are inactive while it
    runs — the same alarm-displacement tradeoff Req 7.4 already anticipates for owner activation.
  This is the first time the note's Req 7.1 gate condition — "on-device iOS decrypt is demonstrated
  (DiaBLE / LibreCRKit frontier)" — is met by a runnable, public implementation rather than a PoC
  that stops at the challenge. The 5-minute cadence LibreLoop uses is a Loop choice, not a limit;
  the decrypt is local, so the 1-minute stream is available network-free (does not license any
  per-minute cloud polling — Req 3.5 unchanged).
- **Caveats on the demonstration (why this is "gate met, now verify", not "ship Phase B today").**
  Both repos are young (LibreLoop 1 star) and substantially AI-agent-authored (airedev326 is an
  "Artificial Intelligence Reverse Engineering Development" coding agent); gui-dos noted on
  2026-06-17 that `LibreCRKit/protocol.md` still contains "several inaccuracies and even real
  hallucinations". No independent reproduction by this project yet, and none on the user's own 3+.
  Per Req 7.4 the owner-activation decrypt path must be proven end to end on a **separate test
  sensor** before it is run on the user's live sensor; that gate stands regardless of this move.
  Recommended next step for the owner: evaluate LibreCRKit/LibreLoop on a test sensor before
  committing any Phase B build.
- **DiaBLE Discussion #22 (`gui-dos/DiaBLE`, checked 2026-08-18)** — no new posts since the
  2026-08-17 entry; last comment is still 2026-06-17T20:51 (discussion `updatedAt` 2026-06-17). The
  standing thread (EasyLars' PoC reaching the 23-byte challenge but blocked at the KDF /
  WhiteCryption scalar; dugamarian's Libre 3 ↔ Apple Watch connection; gui-dos embedding LibreCRKit
  as a "LibreCR" tab) is unchanged. The forward motion this cycle is in the LibreCRKit/LibreLoop
  repos, not in the discussion.
- **39C3 / CCC 2025 xDrip4iOS Libre 3+ project (checked 2026-08-18)** — the assembly page
  (events.ccc.de, 39C3, Hamburg 27–30 Dec 2025) remains an announcement-only "is it possible?"
  investigation; no published decrypt result or media.ccc.de recording found. It is not the source
  of the moved verdict.
- **Juggluco / Libre 3+ (checked 2026-08-18)** — unchanged: `maheini/FreeStyle-Libre-3-patch` still
  archived (2026-02-22, "decryption was successfully cracked", points to Juggluco as the Android
  reference); no new 3+ reverse-engineering surfaced beyond it. Consistent with the "Android can"
  section.
- **Context, not evidence for our path:** mylife Loop (Ypsomed / CamAPS FX) received Health Canada
  approval in Jan 2026 for iOS with the Libre 3 Plus. That is a **regulated Abbott-partner vendor
  integration**, not a clean-room decrypt, so it does not bear on this note's feasibility verdict —
  but it does reinforce the Ypsomed data-custody line below as a potential follower/vendor cloud.

**Uploader-route desk-check (Req 10.5 — region-switch and sensor↔country lock currency; on-device
verification of the routes remains user-hardware work, not done here):**

- **Route A — App Store region switch (`docs/libre-app-region-setup.md`)** — the documented steps
  are still current as of 2026-08-18: Apple still requires a zero balance and no active
  subscriptions before a region change; the path (Settings → name → Media & Purchases → View Account
  → Country/Region → Change Country or Region) and the "Payment Method: None for free apps once an
  in-country address is given" allowance both still hold. One packaging drift worth recording:
  Abbott has shipped a **unified "Libre by Abbott" app in the US** (App Store id 6670330506) distinct
  from the country-specific "FreeStyle Libre 3" listings elsewhere, so the doc's "search FreeStyle
  Libre 3" step is region-dependent — match by publisher (Abbott) and supported sensor, not a fixed
  app name. `docs/libre-app-region-setup.md` updated accordingly this cycle.
- **Sensor↔country-of-purchase lock** — still accurate: Abbott's own travel FAQ confirms sensors
  and apps/readers from one market may not be compatible with another market's, i.e. the worn 3+
  needs the LibreLink of its country of purchase.
- **Route B — Juggluco Android bridge, and heartbeat coexistence with an Android-held session
  (Req 10.4)** — not verifiable here (requires an Android device activating a 3+ and an iPhone
  heartbeat central against that session). Still open; the xdripswift coexistence evidence remains
  same-phone only.

### 2026-08-17 — cgm-direct spec authoring re-check. Verdict UNCHANGED (Phase B still iOS-blocked).

- **Heartbeat (Phase A)** — re-confirmed against `xdripswift` master
  `Libre3HeartbeatBluetoothTransmitter.swift`: connect to `ABBOTT*` as a second central, notify on
  `0898177A-EF89-11E9-81B4-2A2AE2DBCCE4`, never write, never decrypt, 1 s pre-fetch delay, debounce.
  New GATT detail for the record: data service `FDE3`, device-info `180A`; write/login `F001`, read
  notify `F002`. No change to Phase A feasibility — still shippable today.
- **On-device decrypt (Phase B)** — the ECDH-P256 handshake is reproducible on iOS with CryptoKit
  (65-byte X9.63 uncompressed public keys are accepted); the wall remains the obfuscated KDF/key-wrap
  (WhiteCryption SKB / Zimperium, `liblibre3extension.so`, `generateEphemeralKeys()`). No public iOS
  clean-room decrypt yet. Blocker 3 stands.
- **Frontier moved (context, not verdict):** `maheini/FreeStyle-Libre-3-patch` was **archived
  2026-02-22** with "The decryption was successfully cracked", pointing to **Juggluco** (Android,
  offline, non-root) as the reference solution — consistent with this note's "Android can" section.
  A **39C3 / CCC 2025** project ("xDrip4iOS — extending Libre Sensor 3+") is actively investigating
  the iOS port. These are the two things to re-check next cycle.
- **Libre 3 vs 3+**: same BLE protocol and same decrypt path; the only 3+-specific concern is the
  heartbeat coexistence re-verify (checklist item 3), still open — no 3+ hardware evidence gathered
  yet.
- **Ypsomed mylife**: not investigated this cycle; still open.
