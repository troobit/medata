# Settings Information Architecture

## Overview
`App/Pages/Settings/SettingsView.swift` has grown to one 704-line `Form` with
nine flat sections, so the developer-phase switches, the insulin dosing
settings and the ordinary preferences all compete for the same scroll. This
change turns the top level into a short list of `NavigationLink` rows —
following the `AboutView` pattern already in the file — with Glucose, Capture,
Insulin and Developer each owning a screen, and drops the "Food database"
section whose two rows are already attributed under About. Backlog item 31.

## Requirements
- The Settings top level MUST consist of rows that either open a submenu or
  perform one action; it MUST NOT carry any editable control inline.
- Every developer-phase control (the `DeveloperFlags` toggles, the demo-seed
  buttons, the clear-data button) MUST live on a single Developer screen
  reached from one top-level row.
- The insulin product defaults, the per-band carbohydrate ratios, the ratio
  source and the dose schedule with its reminder settings MUST live on a
  single Insulin screen.
- The "Food database" section listing CoFID and AFCD MUST be removed from
  Settings; those editions stay attributed under About.
- The outstanding-dose deep link (`scrollToDoseSchedule`) MUST still land on
  the dose-schedule controls without further taps.
- Every `accessibilityIdentifier` in use before this change MUST keep its
  identifier and its control; new submenu rows MAY add new identifiers.
- The compile gating MUST be unchanged in effect: `DeveloperFlags` and its
  toggles compile under `FIELD_LOOP` (Debug and Release, absent from
  ProductRelease), and the demo-seed and clear-data buttons compile under
  `DEBUG` nested inside that, because `seedDemoBslEvents` and `deleteAllData`
  are Debug-only store methods.
- Estimation log and Benchmark MUST stay outside the `FIELD_LOOP` guard —
  design-handoff-00 Req 2.3 requires them to operate in Release builds.
- New rows MUST carry plain labels with no reassurance or disclaimer copy
  (CLAUDE.md developer-phase copy rule).

## Implementation Approach
- **`App/Pages/Settings/SettingsView.swift`** keeps the top-level `Form`, the
  archive export and the shared properties, and loses every moved control.
  Rows: Account; Glucose / Capture / Insulin; Estimation log / Benchmark;
  Export / About; Developer (`#if FIELD_LOOP`).
- **New files under `App/Pages/Settings/`**, one screen each, following
  `App/Pages/About/AboutView.swift` (a `List`/`Form` with
  `.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`):
  `GlucoseSettingsView.swift`, `CaptureSettingsView.swift`,
  `InsulinSettingsView.swift` (carries `CarbRatioRow`), and
  `DeveloperSettingsView.swift` (whole file `#if FIELD_LOOP`, carrying the
  demo-meal builders and the mask fixture under a nested `#if DEBUG`).
  The `App` folder is a `PBXFileSystemSynchronizedRootGroup`, so new files
  need no `project.pbxproj` edit.
- **`App/Pages/Settings/DoseScheduleSettingsSection.swift`** re-targets its
  extension from `SettingsView` to `InsulinSettingsView`; its body is
  unchanged.
- The deep link stays in `SettingsView`: `scrollToDoseSchedule` drives a
  `.navigationDestination(isPresented:)` that pushes the Insulin screen, which
  owns the `ScrollViewReader` and scrolls to the `doseScheduleSection` anchor.
- **Dependencies:** `AppRoot` already wraps Settings in a `NavigationStack`,
  so pushed screens need no new navigation scaffolding, and `AppRoot`'s call
  site is unchanged.
- **Out of Scope:** the disabled Account row; the Estimation log and Benchmark
  screens themselves; `AboutView`'s content; any `SettingsKeys` or persisted
  value; `specs/OVERVIEW.md` and `specs/BACKLOG.md` bookkeeping.

## Risks and Assumptions
- **Risk:** moving the toggles behind a push could repeat today's failure
  where the switches compiled out of the field build. Mitigation: the
  Developer row and file are `#if FIELD_LOOP` and the seed/clear buttons
  `#if DEBUG` within it, verified by both `make build-release-check` and a
  Debug app compile.
- **Risk:** `.navigationDestination(isPresented:)` alongside destination-based
  `NavigationLink`s in one view. Mitigation: only the dose-schedule deep link
  uses it; the ordinary Insulin row is a plain `NavigationLink`.
- **Assumption:** no committed UI test target executes the app-target test
  files (CLAUDE.md), so identifier continuity matters for the field-loop notes
  rather than for a running suite; identifiers are preserved regardless.
- **Prerequisite:** `Debug` sets `DEBUG FIELD_LOOP` and `Release` sets
  `FIELD_LOOP` in `MeData/MeData.xcodeproj`, so `DEBUG` implies `FIELD_LOOP`.

## Escalation Note
This change was scoped as a smolspec. If implementation reveals ambiguity only
the user can resolve, an irreversible boundary (public API, persisted schema,
auth path), or a contested architectural choice, stop and escalate to the full
spec workflow rather than deciding it inline.
