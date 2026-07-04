# Handoff Manifest — design-handoff-00

**Handoff ID:** 00
**Date received:** 2026-07-04
**Source:** Claude-designed wireframes v1 + v2 (HTML/JSX) and SwiftUI scaffold (`MedataApp/`), produced in a claude.ai session and pasted into this repo.

---

## Contents

```
wireframes/   — HTML wireframes v1 and v2, React/JSX design canvas, screen components
MedataApp/    — SwiftUI scaffold (layout reference only; inert, no target membership)
README.md     — original handoff readme
MANIFEST.md   — this file
```

---

## Deviations from the handoff

Each row records where the shipped spec diverges from this archived reference.
Deviations are binding; the spec documents are the contract; this archive is inert.

| # | Handoff design | Shipped behaviour | Reason |
|---|---|---|---|
| 1 | Three-tier confidence chip (High ≥ 0.8 / Moderate 0.6–0.8 / Low < 0.6) | Four-tier scheme kept (High / Moderate / Low / Very Low at 0.75 / 0.5 / 0.2) with σ < 0.2 retake prompt | [Decision 5](../../../specs/ui/design-handoff-00/decision_log.md#decision-5-keep-the-four-tier-confidence-scheme) — handoff drawn against a stale requirements snapshot; shipped data-motivated behaviour wins |
| 2 | Photo-retention controls and `CoFID 2024 + IFCDB 2023 overlay` database section in Settings | Settings shows CoFID + AFCD (no retention controls) | [Decision 4](../../../specs/ui/design-handoff-00/decision_log.md#decision-4-settings-match-shipped-reality-not-the-handoffs-stale-items) — matches shipped reality; RetentionScheduler removed; IFCDB never shipped |
| 3 | σ_tilt% readout in the tilt indicator (Δθ + σ_tilt%) | σ_tilt% display dropped; telemetry capsule shows tilt°, distance cm, LiDAR dot only | [§16 supersession table row 2](../../../specs/ui/design-handoff-00/requirements.md#16-supersession-of-iphone-experience) — bubble level + telemetry tilt replace the prior readout; σ_tilt% has no display slot in the new chrome |
| 4 | Torch toggle in the top bar | Torch control removed from capture chrome | [Decision 14](../../../specs/ui/design-handoff-00/decision_log.md#decision-14-torch-control-dropped-from-capture-chrome) — Req 2.1's chrome enumeration is exhaustive; handoff does not include torch |
| 5 | Per-class σ column in class breakdown rows | Per-class σ dropped; rows show name / mass / volume / carbs only | [Decision 16](../../../specs/ui/design-handoff-00/decision_log.md#decision-16-per-class-σ-and-per-class-confidence-chips-dropped) — `PbPerClassMacros` carries no σ; pipeline computes confidence at meal level only |
| 6 | `Save to history` primary action on Result | `Done` (auto-persist at estimate; Delete is the discard path) | [Decision 17](../../../specs/ui/design-handoff-00/decision_log.md#decision-17-result-keeps-auto-persist-save-becomes-done-delete-is-the-discard-path) — meal is already persisted before Result renders; `Save to history` would be a no-op |
| 7 | Trends day-list rows open the Result screen | Day-list rows open Meal overview (Req 10.6), not Result | [Req 10.6](../../../specs/ui/design-handoff-00/requirements.md#10-trends) — Meal overview is the canonical history-detail entry point |
| 8 | Tab bar visible on all tabs (layout invariant in MASTER.md) | Capture-rooted shell with no tab bar; Data / Trends / Settings present as sheets | [Decision 12](../../../specs/ui/design-handoff-00/decision_log.md#decision-12-mastermd-amendments--no-palette-swap-two-new-tokens-tab-bar-invariant-deleted) — the handoff scaffold removes the TabView; MASTER.md tab-bar invariant deleted |
| 9 | Handoff scaffold UI copy (verbose wording throughout) | All user-facing strings rewritten to minimal form | [§14](../../../specs/ui/design-handoff-00/requirements.md#14-minimal-wording-and-indicator-rules) — minimal wording mandate; verbatim contract is `copy-inventory.md`, cited once here rather than per string |
