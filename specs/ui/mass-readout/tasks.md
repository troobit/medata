---
references:
    - smolspec.md
    - decision_log.md
---
# Mass Readout

## Shipped with meal-review (recorded, Decision 1)

- [x] 1. ResultView hero mass line
  - Shipped during meal-review: ≈ N g on plate in the carbTotal hero stack, live pendingTotalMassG sum, accessibility id result.massLine (App/ResultView.swift). Recorded here per Decision 1; implementation history lives in the meal-review commits.

- [x] 2. Records meal rows show mass beside carbs
  - Shipped during meal-review: MealRecordRow computes massG from record.macros.perClass and renders N g carbs · ≈ M g (App/RecordsView.swift). Recorded here per Decision 1.

## Remaining

- [x] 3. Render live total mass line on MealReviewView <!-- id:iag505q -->
  - Rendered model.pendingTotalMassG beside the running carb total in App/MealReviewView.swift totalRow, visible without scrolling.
  - Monospaced digits, contentTransition/animation matching the running total, reduce-motion respected; accessibility id review.massLine (the view uses the review. prefix — smolspec reconciled).
  - Tracks serving/gram steppers, reject/restore, and whole-meal scaling live via the existing model property; equals the original estimate until adjusted.
  - Display-only over persisted massG — no schema or pipeline change.
  - Gate met: make build-app green.

- [ ] 4. Device look check (human-gated) <!-- id:iag505r -->
  - make deploy-device; verify the line is visible without scrolling on the 16 Pro, tracks stepper/reject/meal-scale adjustments live, and reads sensibly against a weighed plate.
  - Folds into the next tethered device session alongside the meal-review task 22 sheet.
  - Blocked-by: iag505q (Render live total mass line on MealReviewView)
