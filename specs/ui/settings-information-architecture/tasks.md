---
references:
    - specs/ui/settings-information-architecture/smolspec.md
---
# Settings Information Architecture — Implementation Tasks

- [x] 1. Glucose and Capture screens exist behind top-level rows
  - The glucose-source link, the LibreLink import link, the blood-hold stepper and the renders-stale row are reachable only through a Glucose row; the default-path picker and always-include-card toggle only through a Capture row.
  - `settings.glucoseSources` and `settings.glucoseHoldWindow` keep their identifiers and controls.
  - Verify: the app compiles and both screens push from Settings.
  - References: specs/ui/settings-information-architecture/smolspec.md, App/Pages/Settings/SettingsView.swift

- [x] 2. Insulin screen carries the products, the per-band ratios and the dose schedule
  - Insulin product defaults, the four `CarbRatioRow`s, the ratio-source picker, the medreg fit field, the dose-schedule list and the reminder settings all sit on one pushed screen.
  - `DoseScheduleSettingsSection.swift` extends the Insulin screen instead of `SettingsView`; every `settings.insulin*`, `settings.ratio*` and `settings.dose*` identifier is unchanged.
  - Verify: the app compiles and editing a ratio still persists through `SettingsKeys.ratioKey(for:)`.
  - References: App/Pages/Settings/DoseScheduleSettingsSection.swift

- [ ] 3. The outstanding-dose deep link lands on the dose schedule
  - Opening Settings with `scrollToDoseSchedule` set pushes the Insulin screen and scrolls it to the dose-schedule anchor with no extra tap; opening Settings normally shows the top level.
  - Verify: on device, the outstanding-dose gear reaches the schedule controls.
  - References: App/Shell/AppRoot.swift

- [x] 4. Developer screen holds every developer-phase control with its gating intact
  - The three `DeveloperFlags` toggles, the four demo-seed buttons and the clear-data button, plus the demo-review destination and clear confirmation, live on one pushed Developer screen; the demo-meal builders move with them.
  - The Developer row and screen compile under `FIELD_LOOP`; the seed and clear buttons under `DEBUG` nested inside it. Estimation log and Benchmark stay outside both guards.
  - Verify: `make build-release-check` passes and a Debug app compile passes, proving neither guard broke.
  - References: App/Shared/DeveloperFlags.swift

- [x] 5. Top level is rows only and the duplicated food-database section is gone
  - Settings shows Account, Glucose, Capture, Insulin, Estimation log, Benchmark, Export, About and (field builds) Developer — no inline editable control, and no CoFID/AFCD section.
  - `settings.account`, `settings.estimationLog`, `settings.benchmark`, `settings.export` and `settings.about` are unchanged.
  - Verify: `make build-release-check`, a Debug app compile and `make spell` all pass.
  - References: specs/ui/settings-information-architecture/smolspec.md
