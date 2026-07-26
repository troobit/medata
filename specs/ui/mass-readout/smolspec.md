# Mass Readout — Estimated Grams Beside Carbs

## Overview
Field validation runs against a kitchen scale, and a scale reads total mass —
not carbs. The estimate already computes per-class and total mass (`massG` in
`PbPerClassMacros`), but the prominent surfaces show carbs only: the Result
hero is the carb number (mass sits below the fold in the summary card) and
Records meal rows show carbs alone. This change surfaces the estimated mass
where validation happens, in real time.

Motivating session (2026-07-26, field truth): 208 g white rice estimated as
440 g / 141 g carbs — the 2.1× over-read is only checkable against the scale
if the app shows 440 g at the moment of capture.

## Requirements
- The Result hero MUST show the estimated total plate mass ("≈ N g on
  plate") directly beneath the carb total, visible without scrolling, and it
  MUST track row adjustments live (pending grams sum; equals the original
  estimate until adjusted).
- Records meal rows MUST show the estimated mass beside the carb figure
  ("N g carbs · ≈ M g").
- Per-class grams stay as-is (already shown in the Result plate-card rows and
  the meal-overview per-class rows).
- No schema or pipeline change — display-only over the persisted `massG`.

## Implementation Approach
- `App/ResultView.swift` — `pendingTotalMassG` (sum of `pendingGramsFor` over
  `foodRows`) rendered in the `carbTotal` hero stack with the established
  `contentTransition`/`animation` treatment; accessibility id
  `result.massLine`.
- `App/RecordsView.swift` — `MealRecordRow` gains a `massG` computed from
  `record.macros.perClass` and renders it beside the carb text.
- **Out of Scope:** correcting the mass estimate itself (β_c calibration is
  deferred past MVP — the readout exists precisely to collect that evidence).

## Risks and Assumptions
- **Assumption:** `massG` sums are meaningful even when β = 1.0 over-reads —
  that is the point: the readout exposes the bias against scale truth.
- **Risk:** none beyond copy — display-only change; build + device look is
  the gate.
