---
references:
    - specs/regression-suggestion-integration/prd.md
---
# Insulin dose inflow (medreg integration) — App UI

## Dose entry

- [x] 1. Dose entry sheet + model: large numeral, big +/− (tap = 1 U; hold ≈4 steps/s, after ~2 s accelerate to ≈10 steps/s), floor 1 U, hard max 60, default 10 U bolus now, one-tap save via core save API, dismiss + graph refresh via eventsDidChange — PRD App 2, 3

- [x] 2. Bolus/basal toggle (bolus default, units preserved on switch) and compact back-dating time control; neither adds a tap to the happy path — PRD App 4

- [x] 3. Graph toolbar syringe control presenting the sheet (accessibility id graph.insulin); sheet not a full-screen cover — PRD App 1

- [x] 4. Settings section: per-kind insulin_type free-text defaults (bolus NovoRapid, basal Lantus); sheet never asks for product — PRD App 5

## Graph rendering

- [x] 5. Chart insulin band: day = per-dose markers with legible unit counts, bolus/basal distinct, clear of glucose plot band; week/month = per-day total units in same band — PRD App 6

- [x] 6. Current-time bar: assert none is drawn in any range; investigate the reported obstruction on the deployed build and record findings (no RuleMark exists at lineage f090898); do not add one — PRD App 7
  - Verified: no RuleMark or any current-time mark exists in App/ or MeData/ (grep RuleMark = zero hits; the only vertical-ish marks are carb BarMarks; the RectangleMark target band is horizontal)
  - Likely source of the reported obstruction: the chart set no chartXScale domain so the x-axis collapsed to the data extent; with sparse day data the carb BarMark automatic width (plot width divided by mark count) rendered a fresh meal as a very wide full-column bar at its timestamp — which is near now right after a capture — reading as an obstructive vertical bar at the current time
  - Low-risk fix applied: chartXScale(domain: model.interval.start...end) pins the axis to the full selected range in all three ranges and day-range carb bars use width .fixed(6)
  - No current-time indicator was added

- [x] 7. Day-view insulin list (time, units, kind) beside Meals with swipe-to-delete; delete removes event and marker in same refresh — PRD App 8

- [x] 8. Insulin metric chip toggling markers + insulin stat card (total units for range) — PRD App 9 (SHOULD)

## Deep link

- [x] 9. Register custom URL scheme; medata://insulin/add presents dose sheet from any state, dismissing other covers — PRD App 10
  - Covers BOTH medata-scheme deep links per the PRD amendment: medata://insulin/add presents the dose-entry sheet and medata://capture opens the Capture cover (AppRoot ActiveSheet .capture) — each from any state within one screen transition
  - Conflicting presentations are dismissed first via AppRoot.pendingDeepLink: a cover resumes the target from fullScreenCover onDismiss; an open dose sheet resumes medata://capture from TrendsView's onInsulinSheetDismiss
  - Scheme registered once via CFBundleURLTypes in MeData/Info.plist (cannot be an INFOPLIST_KEY_ build setting); verified present in the built product's Info.plist

## Register and verify

- [x] 10. Register all new App/*.swift files in project.pbxproj (ShutterButton pattern); make build-app passes; make build/test/spell green
