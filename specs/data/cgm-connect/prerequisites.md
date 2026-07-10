# Prerequisites: CGM Connect

Research and platform items that must be resolved (spikes) before or during design, surfaced
by the requirements critical review (2026-07-10).

## Platform capabilities (HealthKit)

- **HealthKit entitlement + Info.plist usage strings.** The app target needs the HealthKit
  capability and `NSHealthShareUsageDescription`. The OS authorisation sheet is a system prompt,
  not app disclaimer copy — it stays (the no-disclaimer rule does not override a platform prompt).
- **`#if canImport(HealthKit)` in the `GlucoseIngestion` target.** HealthKit is unavailable on the
  macOS test host, so the source compiles out there and the module still builds/tests under
  `make test` (Decision 8). Confirm the iOS build links HealthKit from the SwiftPM target.
- **Background delivery + ack ordering.** `HKObserverQuery` + `enableBackgroundDelivery(for:
  frequency:)` and the observer completion handler. The anchor is persisted and the completion
  handler called **only after** `sink.ingest` returns (commit durable) — see design (Req 2.5,
  Decision 7). Confirm the achievable `HKUpdateFrequency` for blood glucose and the background
  capability. Delivery is OS-governed; Req 2.6 catch-up is the backstop.
- **Native unit read.** Read glucose via the mmol/L `HKUnit` so no conversion is needed (Req 2.8).

## Platform capabilities (LibreLinkUp background)

- **`BGTaskScheduler`.** Background fetch needs a `BGAppRefreshTask`: register a
  `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist and the background-modes capability.
- **Keychain accessibility.** Store LibreLinkUp credentials with
  `kSecAttrAccessibleAfterFirstUnlock` so a background refresh on a locked device can read them
  (default `WhenUnlocked` would fail the background poll).

## LibreLinkUp source — open research (blocks Req 3 design)

- **No MeData backend.** SNAQ's "paste this identity into the Libre app" flow (IMG_0629/0630)
  works because *SNAQ's server* is the LibreLinkUp follower holding credentials. MeData has no
  backend, so the on-device source must authenticate directly against a LibreLinkUp account.
  The SNAQ connect screen therefore does not copy literally — the MeData flow captures account
  credentials on-device and stores them in Keychain (Req 3.1). Confirm this is acceptable, or
  defer the LibreLinkUp source until a mechanism is chosen. **HealthKit (primary) does not depend
  on this** — the feature ships useful without LibreLinkUp.
- **API contract.** LibreLinkUp is an unofficial/undocumented cloud API. Confirm: the auth flow,
  the reading payload shape and its unit (mmol/L vs mg/dL — feeds Req 5.5), the poll rate limit
  (feeds the ≤15-min interval in Req 3.2), and whether it returns a stable per-reading identifier
  (feeds Req 4.2 — if not, LibreLinkUp readings dedup on grid instant only).
- **Terms/robustness.** Note the API can change without notice; the source is expected to be
  iterated (Decision 2). Failure handling (Req 3.4) must degrade gracefully.

## Storage contract (already established, reused)

- `bsl` event row shape and keep-first dedup come from `specs/data/libre-ingestion` and the
  `BslReading` type in `MedataCore/Sources/Persistence`. This spec extends dedup across sources
  onto one 5-minute grid (Req 5.1, Decision 4) — no schema change expected, to be confirmed in
  design.
</content>
