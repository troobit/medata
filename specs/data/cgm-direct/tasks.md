---
references:
    - specs/data/cgm-direct/requirements.md
    - specs/data/cgm-direct/design.md
    - specs/data/cgm-direct/decision_log.md
---
# Tasks: CGM Direct

## Phase A — Wake-source core (MedataCore, macOS-testable)

- [x] 1. Write failing swift-testing tests for the heartbeat decision logic <!-- id:usr54m5 -->
  - New test file in MedataCore/Tests/GlucoseIngestionTests: shouldFire (beats under 30 s apart yield one fire; 30 s or more yields two; first beat with nil lastBeatAt fires), isStale (boundary at exactly staleWindow; nil lastBeatAt), matchesSensor (ABBOTT-prefixed names match; other prefixes and nil do not)
  - Example tables, no PBT (design Testing Strategy); tests must fail against the not-yet-created type
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.5](requirements.md#2.5), [5.2](requirements.md#5.2)

- [x] 2. Implement HeartbeatWakeSource protocol, HeartbeatConnectionState, and the pure statics to pass the tests <!-- id:usr54m6 -->
  - New file(s) in MedataCore/Sources/GlucoseIngestion (Req 1.4/9.1 placement); MainActor protocol, enum states idle/unavailable/pairing/connected/stale/repairNeeded, Constants (namePrefix, notifyCharacteristicUUID, restoreIdentifier, minInterval 30, staleWindow 70, preFetchDelay 1)
  - No CoreBluetooth types in the pure statics so they compile on the macOS test host (Decision 6)
  - make test green, both totals reported
  - Blocked-by: usr54m5 (Write failing swift-testing tests for the heartbeat decision logic)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.5](requirements.md#2.5), [5.2](requirements.md#5.2)

- [x] 3. Implement the Libre3HeartbeatSource CoreBluetooth central behind os(iOS) <!-- id:usr54m7 -->
  - Also covers Req 2.4a (sensor swap: no background rediscovery, repairNeeded state, foreground re-pair) — anchor unsupported by the rune requirements field
  - Observable MainActor final class, NSObject, CBCentralManagerDelegate plus CBPeripheralDelegate, CBCentralManager(queue: nil, restore identifier) — Decision 10 shape; onHeartbeat closure is a constructor argument
  - Pairing scan (foreground wildcard, ABBOTT prefix, candidate surfaced then confirmPairing persists identifier); subsequent connects via retrievePeripherals(withIdentifiers:); retrieve-empty means repairNeeded
  - Connect and restore both end in notify arming: discoverServices then discoverCharacteristics then setNotifyValue(true) on the notify characteristic; retrieve/connect issued only from centralManagerDidUpdateState at poweredOn
  - willRestoreState recovers the peripheral and re-arms; didDisconnect and didFailToConnect re-issue connect; non-poweredOn means unavailable(reason); lastBeatAt persisted under glucose.source.libre3-heartbeat.lastBeatAt
  - Device-verified only (Decision 6) — no new test scaffolding; EstimationFirewallTests must stay green (Req 9.1)
  - Blocked-by: usr54m6 (Implement HeartbeatWakeSource protocol, HeartbeatConnectionState, and the pure statics to pass the tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.7](requirements.md#2.7), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [9.1](requirements.md#9.1), [9.2](requirements.md#9.2)

## Phase A — App wiring (device-verified)

- [x] 4. Gate the LibreLinkUp launch validation fetch on OS-driven background launches <!-- id:usr54m8 -->
  - Add runValidationFetch parameter to LibreLinkUpGlucoseSource.connect(sink:) (MedataCore/Sources/GlucoseIngestion/LibreLinkUpGlucoseSource.swift); false means attach sink and startPolling, skipping the fetchAndIngest(ignoringRateGate: true) call — Decision 7
  - Existing call sites keep current behaviour (credential entry, foreground opens); wiring change, no new scaffolding; existing GlucoseIngestionTests stay green
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7)

- [x] 5. Wire the heartbeat into GlucoseConnectionsModel <!-- id:usr54m9 -->
  - App/GlucoseConnectionsModel.swift: construct Libre3HeartbeatSource in init iff glucose.source.libre3-heartbeat.enabled is set (synchronous UserDefaults read — Decision 10); enableHeartbeat, confirmHeartbeatPairing, disableHeartbeat (disable calls stop() including cancelPeripheralConnection and clears the flag; identifier kept)
  - heartbeatFired(): gate peek (LibreLinkUpRateGate.isOpen) then UIApplication.beginBackgroundTask via CancellableWorkBox, await startTask, connectedSourceIDs guard, sleep preFetchDelay, libreLinkUp.catchUp() — Decision 5; weak self in the closure (no model retain cycle)
  - runStart(): heartbeat resume() when flag set; pass runValidationFetch false when applicationState is background during start()
  - Blocked-by: usr54m7 (Implement the Libre3HeartbeatSource CoreBluetooth central behind osiOS), usr54m8 (Gate the LibreLinkUp launch validation fetch on OS-driven background launches)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [5.3](requirements.md#5.3), [6.1](requirements.md#6.1), [10.1](requirements.md#10.1), [10.3](requirements.md#10.3)

- [x] 6. Declare the Bluetooth capability in MeData/Info.plist <!-- id:usr54ma -->
  - Add bluetooth-central to the existing UIBackgroundModes array; add NSBluetoothAlwaysUsageDescription with functional copy (no disclaimer — Req 5.4); no entitlement change (Decision 4)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [6.3](requirements.md#6.3)

- [x] 7. Add the heartbeat section to GlucoseConnectionsView <!-- id:usr54mb -->
  - App/GlucoseConnectionsView.swift: new Form section matching the LibreLinkUp section patterns (LabeledContent rows, en_IE timeString, accessibility ids under glucose.heartbeat)
  - State row (Pairing / Connected / Stale / Re-pair sensor / Bluetooth off) inside TimelineView periodic every 10 s deriving Stale via isStale; Last heartbeat row from persisted lastBeatAt; Enable, Confirm, Disable buttons; stale row carries the Re-pair action (design: swap detection is manual)
  - Functional copy only; disabled by default behind the developer-phase enable (Req 6.1)
  - Blocked-by: usr54m9 (Wire the heartbeat into GlucoseConnectionsModel)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [6.1](requirements.md#6.1)

## Phase A — Verify (on-device, gated)

- [ ] 8. STOP — on-device pairing and coexistence verification on the worn Libre 3+ <!-- id:usr54mc -->
  - make deploy-device; match buildStamp; enable heartbeat in Settings, confirm the ABBOTT sensor, verify beats arrive about once a minute while the Abbott app keeps its session and alarms (Req 2.6 — first 3+ hardware evidence; log the outcome and date in the re-check log of docs/agent-notes/libre3-direct-ble.md per Req 8.2)
  - Verify background wake: lock the phone, confirm heartbeat-triggered fetches land in the event log without unlocking; verify stale then reconnect on walking out of and back into range
  - Manual gate: requires the user wearing the sensor (prerequisites.md)
  - Blocked-by: usr54m9 (Wire the heartbeat into GlucoseConnectionsModel), usr54ma (Declare the Bluetooth capability in MeData/Info.plist), usr54mb (Add the heartbeat section to GlucoseConnectionsView)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.6](requirements.md#2.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [9.3](requirements.md#9.3)

- [ ] 9. STOP — 24 h measured close-out: heartbeat on vs off <!-- id:usr54md -->
  - At least 24 h with the app never foregrounded, heartbeat on: compare bsl row count and max inter-reading gap against a heartbeat-off baseline day (devicectl DB pull recipe in docs/agent-notes/device-build-and-test.md); record battery delta and widget refresh behaviour (Decision 9 measurement)
  - Confirms the bounded roughly-6-minute worst-case staleness claim and that the vendor request rate stayed within the shared budget (Req 3.2); record outcomes in the decision log
  - Looks-right-on-device cannot see a wake that did not happen — this measurement is the real gate
  - Blocked-by: usr54mc (STOP — on-device pairing and coexistence verification on the worn Libre 3+)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.5](requirements.md#3.5)

## Phase B — Research continuity (parallel stream)

- [x] 10. Run the Phase B re-verification sweep and log it, whether or not the verdict moves <!-- id:usr54me -->
  - Check DiaBLE Discussion #22, LibreCRKit, and the 39C3/CCC 2025 xDrip4iOS Libre 3+ project for on-device iOS decrypt progress; append a dated entry to the re-check log in docs/agent-notes/libre3-direct-ble.md
  - Independent of stream 1 — run concurrently with the Phase A build; repeat roughly monthly (the frontier cadence); Phase B remains gated on this log (Req 7.1)
  - No implementation: Phase B code is not written until the note records on-device iOS decrypt demonstrated (Req 6.2, 7.1)
  - Stream: 2
  - Requirements: [4.3](requirements.md#4.3), [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)

- [ ] 11. Verify the uploader routes: region-switch LibreLink and the Juggluco bridge <!-- id:usr54mf -->
  - Route A (primary): verify docs/libre-app-region-setup.md end to end — identify the sensor country of purchase, switch the iPhone App Store region, install the matching (free) LibreLink, confirm activation and LibreView upload feed cgm-connect; correct the doc where the steps have drifted (Req 10.5)
  - Route B: verify the Juggluco bridge on an Android device (activate a 3+, upload to LibreView, cgm-connect keeps reading with no Abbott iOS app); note it moves Abbott alarms to the Android device
  - Determine whether the MeData heartbeat central can coexist with an Android-held session (xdripswift evidence is same-phone only — Req 10.4); log all findings, dated, in the re-check log of docs/agent-notes/libre3-direct-ble.md per Req 8.2
  - Documentation and verification only; no MeData code changes fall out of this task
  - Stream: 2
  - Requirements: [10.2](requirements.md#10.2), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5)

## Phase B — Decrypt evaluation (test-sensor gated)

- [ ] 12. Desk audit of LibreCRKit and LibreLoop — licence, protocol correctness, adopt-vs-reimplement <!-- id:usr54mg -->
  - Read airedev326/LibreCRKit and LoopKit/LibreLoop as source: exact licences (can MeData vendor or must it reimplement?), the AES-128-CCM data-plane path, ECDSA-P256 cert verify with the bundled Abbott patch-signing keys, the P-256 ECDH exchange, and the NFC-activation response that carries the blePIN (protocol.md)
  - Cross-check protocol.md against DiaBLE Discussion #22 — gui-dos flagged inaccuracies/hallucinations in it on 2026-06-17; note every claim not independently corroborated so the test-sensor run (task 14) targets them
  - Output an adopt-vs-reimplement recommendation with the licence and correctness evidence behind it; append dated to the re-check log (Req 8.2). No MeData code and no NFC activation in this task
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)

- [ ] 13. STOP — acquire a separate Libre 3+ test sensor and a ground-truth reader for it <!-- id:usr54mh -->
  - Manual gate (prerequisites.md): a SECOND Libre 3+, distinct from the worn sensor, is required — Req 7.4 forbids the live-sensor decrypt attempt until the path is proven on a test sensor, because owner-activation displaces Abbott alarms (Decision 3)
  - Also obtain an independent ground-truth reference for that sensor (a reader or region-matched LibreLink) so decrypted values in task 14 can be checked against a known-good source
  - Note the sensor country of purchase — the blePIN/activation path and any uploader fallback are country-locked (Req 10.2)
  - Stream: 2
  - Requirements: [7.4](requirements.md#7.4)

- [ ] 14. STOP — test-sensor end-to-end decrypt evaluation: activate as owner, hold the BLE session, verify decrypted readings <!-- id:usr54mi -->
  - On the TEST sensor only (never the worn one — Req 7.4): NFC-activate as owner to obtain the blePIN (Decision 3), hold a BLE session across a reconnect, decrypt the 1-minute data plane, and confirm the mmol/L values track the ground-truth reader
  - Confirm the alarm-displacement tradeoff in practice: activating as owner takes the sensor from the Abbott app (Req 7.4, Decision 3) — record it
  - Verify the value path is genuinely network-free (Req 7.2) — no LibreView account needed, per the LibreCRKit README claim; capture what breaks if offline
  - Record the full outcome, dated, in the re-check log (Req 8.2). This is the Req 7.1 end-to-end proof the Phase B build gates on; a negative result keeps Phase B unbuilt and Phase A the everyday path
  - Blocked-by: usr54mg (Desk audit of LibreCRKit and LibreLoop — licence, protocol correctness, adopt-vs-reimplement), usr54mh (STOP — acquire a separate Libre 3+ test sensor and a ground-truth reader for it)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4), [8.2](requirements.md#8.2)

- [ ] 15. Author the Phase B build design and task list from the evaluation evidence <!-- id:usr54mj -->
  - Only after task 14 proves the decrypt end-to-end (Req 7.1): author the Phase B build design and task list against this spec — the value path stays inside GlucoseIngestion and outside every estimation target closure (Req 7.3, 9.1, EstimationFirewallTests), stores under the distinct libre3-ble source identifier snapped/deduped on the shared 5-minute grid (Req 4.3, 7.2), and treats owner activation as the deliberate user-confirmed act Req 7.4 requires
  - The AES-128-CCM decrypt is the property-based-test candidate the design Testing Strategy named (round-trip against vectors) — unlike the Phase A boundary checks
  - Design-and-planning task, not a build: it produces design.md/tasks.md updates for the Phase B implementation stream, which starts only when this lands
  - Blocked-by: usr54mi (STOP — test-sensor end-to-end decrypt evaluation: activate as owner, hold the BLE session, verify decrypted readings)
  - Stream: 2
  - Requirements: [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [4.3](requirements.md#4.3)
