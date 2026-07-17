---
references:
    - prd.md
---
# Serving-based portion adjustment — iOS app

## Serving rows

- [x] 1. Replace the portion card with per-food serving stepper rows <!-- id:p00c98h -->
  - Remove the PORTION card and PortionStepper pair from ResultView; the Per food rows become the adjustment surface
  - Row: food name, serving-first amount (unit_singular/plural, nearest displayable half-unit), gram mass secondary, per-row carbs; inline minus/plus stepping by the class step, floored at 0
  - Hero carb total updates live (.numericText()); 'estimated N g' line shows the untouched estimate whenever pending state diverges
  - No solid_servings row or liquid class falls back to a gram stepper on the same row — never a dead row
  - Serving-to-gram conversion arithmetic lives in MedataCore (Foods or a small pure helper) with executed-suite coverage
  - Load the frontend-design skill before reshaping the screen

- [x] 2. Add the plate-fraction quick control <!-- id:p00c98i -->
  - Compact control (e.g. segmented All/three-quarters/half/quarter) scales every row's pending amount from the original estimate in one tap
  - Fraction first, per-row refinement second: nudging one row keeps others at the fraction
  - Default All writes nothing
  - Blocked-by: p00c98h (Replace the portion card with per-food serving stepper rows)

- [x] 3. Add the per-row gram reveal <!-- id:p00c98j -->
  - Tapping a row's amount (not the steppers) reveals an editable gram value, two-way bound with the serving display
  - Digits-only clamp convention from the existing carb-entry surfaces
  - Blocked-by: p00c98h (Replace the portion card with per-food serving stepper rows)

## Persistence and retirement

- [x] 4. Persist adjustments via appendCorrection, edit-by-exception <!-- id:p00c98k -->
  - Untouched result writes nothing; Done unchanged (zero extra taps)
  - Single confirm pill (existing Log N g pattern) appends one PbUserCorrection: scaled total, per-class carbs scaled per row, machine-readable serving-count note extending PortionFormat; legacy 'portion N/M' notes still parse
  - Scaling always derives from the ORIGINAL estimate (never compounds); history reopen seeds from latest correction; re-adjusting appends
  - Graph/Records/Meal overview corrected wiring stays green
  - Blocked-by: p00c98h (Replace the portion card with per-food serving stepper rows), p00c98i (Add the plate-fraction quick control), p00c98j (Add the per-row gram reveal)

- [x] 5. Retire ManualCorrectionView and the Adjust action <!-- id:p00c98l -->
  - Delete ManualCorrectionView.swift, remove the Adjust button (Done remains) and route references; free-text note entry dropped
  - pbxproj references removed per the four-section checklist in docs/agent-notes/ui-capture-flow.md
  - Blocked-by: p00c98k (Persist adjustments via appendCorrection, edit-by-exception)

- [x] 6. Design-system, copy, and truncation pass with full gates <!-- id:p00c98m -->
  - Capture palette, contentShape inside Button labels, monospaced digits, no disclaimer copy, make spell clean
  - No ellipsis truncation in portrait at default Dynamic Type; longest unit strings survive
  - make build, make test (both totals), simulator app compile check with CODE_SIGNING_ALLOWED=NO
  - Blocked-by: p00c98k (Persist adjustments via appendCorrection, edit-by-exception), p00c98l (Retire ManualCorrectionView and the Adjust action)

- [ ] 7. STOP — on-device looks-right pass on the iPhone 16 Pro <!-- id:p00c98n -->
  - Serving stepper ergonomics, fraction control, gram reveal, no truncation — user's call after the build lands
  - Blocked-by: p00c98m (Design-system, copy, and truncation pass with full gates)
