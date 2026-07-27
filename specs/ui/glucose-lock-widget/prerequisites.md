# Prerequisites for Glucose Lock Screen Widget

These steps require human intervention outside code (Xcode capabilities, signing, and on-device visual checks). The project's app/UI gate is build + looks-right on device — the widget and publisher have no executable test target, so their verification lives here.

## During Implementation

- [ ] **App Group capability (blocks task 10 provisioning).** In Xcode, add the **App Groups** capability with `group.rtob.MeData` to BOTH the `MeData` app target and the `MeDataWidgets` extension target. Ensure the signing profiles for `rtob.MeData` and `rtob.MeData.MeDataWidgets` include the App Group. The first device build after adding it may need `xcodebuild -allowProvisioningUpdates` once to mint the updated profiles (as the launcher-widget bundle id did originally).

## Before Testing

- [ ] **App→extension snapshot round-trip (the real safeguard for Req 1.7).** With a device install, confirm a reading written by the app is read back by the widget. Note the misprovisioning trap: a missing/mis-provisioned App Group does **not** make `UserDefaults(suiteName:)` return nil — it returns a non-nil *private* store, so the app writes where the widget cannot see and the widget shows never-recorded. This round-trip is the only reliable detector; the nil guard will not fire for it.
- [ ] The `CFPrefsPlistSource … detaching from cfprefsd` console warning is expected with App Group suites and is safe to ignore — do not treat it as a failure during bring-up.

## On-Device Verification (task 14 — STOP, not agent-executable)

- [ ] `make build-app` embeds `MeDataWidgets.appex` with the App Group entitlement; `make test` (both XCTest and swift-testing totals) and `make spell` are green.
- [ ] The glucose widget appears in the Lock Screen widget gallery as a **distinct kind**, separate from the two launcher widgets.
- [ ] **Monochrome render**: on the Lock Screen (vibrant mode), the low/in-range/high **status token is visible without relying on colour**; the trend arrow and value are legible in `accessoryCircular`, `accessoryRectangular`, and `accessoryInline`.
- [ ] **StandBy**: renders in StandBy; the per-status colour enhancement appears in StandBy **day** (full colour) and is absent in StandBy **night** (vibrant) — the token still carries status in both.
- [ ] **Staleness ladder** as a reading ages: full prominence ≤15 min → de-emphasised (reduced opacity, value + age, no status/arrow) >15–30 min → "last reading · Xh ago" (no number) >30 min, distinct from the never-recorded placeholder.
- [ ] **Tap** opens the Graph via `medata://graph` from both an unlocked device and a locked device (after unlock).
