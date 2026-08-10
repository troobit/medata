# Decision Log: Mass Readout

## Decision 1: Reconcile the smolspec to the shipped meal-review architecture; the remaining work is one line on MealReviewView

**Date**: 2026-08-10
**Status**: accepted

### Context

The smolspec was written before the meal-review spec shipped. It named `ResultView`'s hero as the at-capture surface, because at authoring time the post-capture flow was the review/result split. Meal-review replaced that split with a single post-capture surface (`MealReviewView`); `ResultView` collapsed to the history read path. Meanwhile two of the smolspec's three requirements were implemented *during* the meal-review work: `ResultView` renders "≈ N g on plate" in its hero stack (`result.massLine`, live pending sum), and `RecordsView` meal rows show "N g carbs · ≈ M g". `MealReviewModel` even gained a `pendingTotalMassG` property — but no view consumes it, so the surface where the motivating scenario happens (checking the estimate against a kitchen scale at the moment of capture) is exactly the one without the readout.

### Decision

Reconcile the smolspec's requirements to the current architecture rather than leaving them pointing at superseded surfaces: the at-capture requirement transfers to `MealReviewView` (rendering the existing `pendingTotalMassG`, accessibility id `mealReview.massLine`); the `ResultView` and `RecordsView` requirements are recorded as shipped. The task ledger records the shipped parts as completed tasks so it tells the truth about how the capability landed.

### Rationale

PROCESS.md §1: when code and spec disagree, that is a defect to reconcile, not a state to leave standing. The disagreement here is architectural drift, not intent drift — the smolspec's intent ("show the mass where validation happens, in real time") maps unambiguously onto `MealReviewView` now that it is the at-capture surface. The dangling model property confirms the intent was carried into meal-review but the view wiring was dropped.

### Alternatives Considered

- **Leave the smolspec as written and call the capability shipped**: `ResultView` does show the line — Rejected: `ResultView` is the *history* path now; the motivating scenario (scale on the counter, meal just captured) plays out on `MealReviewView`, which shows nothing. The capability's point would be missed exactly where it matters.
- **Fold the remaining line into the meal-review spec as an extension**: it touches only meal-review surfaces — Rejected: meal-review is 21/22 closed with only a human-gated device sheet left; reopening it for a requirement it never owned muddies its ledger. The capability has its own spec; it keeps its own acceptance.

### Consequences

**Positive:**
- The spec names the real surfaces; the ledger records what actually shipped where.
- The remaining work is minimal and precisely scoped: one view line consuming an existing model property.

**Negative:**
- The shipped parts' history lives in the meal-review implementation commits, not in this spec's — the completed ledger entries point across rather than at their own diffs.

---
