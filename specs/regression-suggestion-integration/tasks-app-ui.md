---
references:
    - prd.md
---
# Insulin dose inflow (medreg integration) — App UI

## Dose entry

- [ ] 1. Dose entry sheet + model: large numeral, big +/− (tap = 1 U; hold ≈4 steps/s, after ~2 s accelerate to ≈10 steps/s), floor 1 U, hard max 60, default 10 U bolus now, one-tap save via core save API, dismiss + graph refresh via eventsDidChange — PRD App 2, 3

- [ ] 2. Bolus/basal toggle (bolus default, units preserved on switch) and compact back-dating time control; neither adds a tap to the happy path — PRD App 4

- [ ] 3. Graph toolbar syringe control presenting the sheet (accessibility id graph.insulin); sheet not a full-screen cover — PRD App 1

- [ ] 4. Settings section: per-kind insulin_type free-text defaults (bolus NovoRapid, basal Lantus); sheet never asks for product — PRD App 5

## Graph rendering

- [ ] 5. Chart insulin band: day = per-dose markers with legible unit counts, bolus/basal distinct, clear of glucose plot band; week/month = per-day total units in same band — PRD App 6

- [ ] 6. Current-time bar: assert none is drawn in any range; investigate the reported obstruction on the deployed build and record findings (no RuleMark exists at lineage f090898); do not add one — PRD App 7

- [ ] 7. Day-view insulin list (time, units, kind) beside Meals with swipe-to-delete; delete removes event and marker in same refresh — PRD App 8

- [ ] 8. Insulin metric chip toggling markers + insulin stat card (total units for range) — PRD App 9 (SHOULD)

## Deep link

- [ ] 9. Register custom URL scheme; medata://insulin/add presents dose sheet from any state, dismissing other covers — PRD App 10

## Register and verify

- [ ] 10. Register all new App/*.swift files in project.pbxproj (ShutterButton pattern); make build-app passes; make build/test/spell green
