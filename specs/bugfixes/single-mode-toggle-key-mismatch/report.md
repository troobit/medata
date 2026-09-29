# Bugfix Report: Single-Mode Toggle Key Mismatch

**Date:** 2026-06-19
**Status:** Fixed (code + regression test; App-target test follows the project's non-CI convention — see Regression Test)

## Description of the Issue

On iPhone 13 Pro Max iOS 26.5, selecting **Single** on the capture-mode pill had no
effect: every capture still ran as **Double** (`event=fired … mode=double`), so the
user was forced through the two-view nadir→oblique flow even after explicitly choosing
single-view. The toggle's accent pill animated to "Single", but the capture flow ignored
it.

**Reproduction steps:**
1. Launch the app on a LiDAR device.
2. Tap the **Single** segment of the capture-mode pill (it visibly selects).
3. Take a nadir shot.
4. Observe the shutter log: `mode=double` — and the flow stashes the nadir and waits
   for an oblique tap instead of estimating immediately.

## Investigation Summary

- **Symptom:** `mode=double` in every `event=fired` line regardless of the toggle state.
- **Code inspected:**
  - `App/CaptureModeToggle.swift` — persists the selection via
    `@AppStorage(CaptureModeStorage.key)`, where `CaptureModeStorage.key = "captureMode"`.
  - `App/CaptureFlowModel.swift:19` — `defaultCaptureModeReader()` resolves the mode via
    `UserDefaults.standard.string(forKey: SettingsKeys.captureMode)`.
  - `App/SettingsKeys.swift:13` — `SettingsKeys.captureMode = "medata.captureMode"`.
  - `MedataCore/Sources/PortableContracts/CaptureMode.swift` — documents
    `SettingsKeys.captureMode` as the canonical persistence location.

## Discovered Root Cause

A **UserDefaults key mismatch**. The toggle wrote the user's selection under the bare key
`"captureMode"`, but the capture flow read the namespaced key `"medata.captureMode"`. The
two keys never coincided, so `defaultCaptureModeReader()` always read an unset key, fell
through to its `?? .double` default, and the toggle's write was dead state that nothing
consumed.

**Defect type:** Wrong constant. Two independently-declared key strings for the same
persisted value drifted apart; `CaptureMode.swift` documents the namespaced key as
canonical, so the toggle's bare `"captureMode"` was the incorrect side.

**Why the existing test missed it:** `CaptureModeToggleTests.roundTripUserDefaults` both
wrote *and* read `CaptureModeStorage.key`, so it round-tripped within the wrong key and
passed — it never bridged the toggle's storage key to the reader the capture flow actually
uses.

## Resolution for the Issue

`App/CaptureModeToggle.swift` — `CaptureModeStorage.key` now references
`SettingsKeys.captureMode` (the single canonical key the reader uses) instead of the bare
`"captureMode"` literal. One source of truth; the `@AppStorage` write now lands on the key
`defaultCaptureModeReader()` reads.

No migration is required: because the reader never observed the old key, no install ever
had effective non-default state to preserve — the app always behaved as `.double`.

## Regression Test

`MeData/Tests/CaptureModeToggleTests.swift` gains two cases:

- **`toggleSelectionReachesReader`** — writes `.single` under `CaptureModeStorage.key`, then
  asserts `defaultCaptureModeReader() == .single`. This bridges the writer's key to the real
  reader and fails on the pre-fix code (reader sees the unset namespaced key → `.double`).
- **`toggleAndReaderKeysAreUnified`** — asserts `CaptureModeStorage.key == SettingsKeys.captureMode`
  as a cheap guard against the keys drifting apart again.

**Test-runner note:** the App target has no committed XCTest/Testing host
(`docs/agent-notes/ui-capture-flow.md:85` — "no test targets exist"), so these App-target
cases are validated by inspection + a clean app build, matching every other suite under
`MeData/Tests/`. They run when a temporary test target is scaffolded.

## Affected Files

| File | Change |
|------|--------|
| `App/CaptureModeToggle.swift` | `CaptureModeStorage.key` unified onto `SettingsKeys.captureMode` |
| `MeData/Tests/CaptureModeToggleTests.swift` | Two regression cases bridging the toggle key to the reader |

## Verification

- [x] `swift build` (MedataCore) — clean.
- [x] `swift test` (MedataCore) — 313 tests, 3 skipped, 0 failures.
- [x] Device build + install on iPhone 13 Pro Max iOS 26.5.
- [x] **On-device (2026-06-19):** after the fix, selecting Single produced
  `event=fired … mode=single stage=nadir`, and a single nadir tap ran the estimate
  immediately (`capturePath=single_view_lidar` → `estimate.end success=true`). Confirmed
  the toggle now takes effect.

## Prevention

- Declare a persisted-key string exactly once and reference it everywhere; never re-declare
  the same logical key as a second literal in a different module.
- A persistence round-trip test must exercise the **production reader**, not re-read the
  same key the test itself wrote — otherwise a writer/reader key divergence passes unseen.
