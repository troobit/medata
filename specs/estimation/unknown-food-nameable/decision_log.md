# Decision Log: Unknown Food Nameable

## Decision 1: Carry unknown food as a nameable row instead of refusing

**Date**: 2026-09-23
**Status**: accepted

### Context

Bugfix `unrecognised-food-estimated-as-residual-sliver` (2026-07-26) made an unknown-dominant scene refuse `unrecognisedFood` so a residual sliver could not drive a confident wrong estimate. The 2026-09-23 field session showed the pre-shutter plane-fitter gate refuses such a scene earlier still, as `noFoodPixels`, on both capture paths. Either way an out-of-palette food never reaches review, and version 1 users will photograph such foods routinely.

### Decision

Treat `unknown_food` as a volumetric class end to end and surface it in review as a row named "Unknown food" with 0 g carbohydrate, to be relabelled from the palette list or rejected. Retire the `unrecognisedFood` refusal.

### Rationale

The review surface already has relabel-from-list with mass derived from stored pre-β volume, and reject. Naming a measured region is the cheapest path to a carb figure for a food the model has not learnt, and it exercises the correction corpus that future training needs. The sliver bug is handled by Decision 3: a named fringe on an unknown region is merged into it before volume, so it never becomes a row of its own.

### Alternatives Considered

- **Keep refusing, retrain the model**: Adds classes per field session - Rejected because a refusal yields no record, no correction, and no carb figure today.
- **Refuse, but let the user name the region from the refusal overlay**: New UI on the overlay - Rejected because review already has the naming and reject controls; duplicating them is more UI for the same outcome.
- **Block Record while a row is unnamed**: Guarantees no 0 g rows - Rejected by the developer for friction; the accessory line and history relabel cover the case.

### Consequences

**Positive:**
- Out-of-palette foods produce a record and a correction instead of a refusal.
- One predicate change covers single-view and two-view.

**Negative:**
- Non-food regions labelled unknown now appear as rows and need a reject tap.
- An unnamed row records as 0 g until relabelled.

### Impact

`Segmentation`, `Pipeline`, `Volume`, `Macros` in MedataCore; capture and review pages in the app. Supersedes the refusal-ordering part of the sliver bugfix; its coverage floor and ratio constants are deleted with the gate.

---

## Decision 2: Smolspec despite exceeding the size guide

**Date**: 2026-09-23
**Status**: accepted

### Context

The change touches about eight files and well over the 80-line smolspec guide, which the workflow says should escalate to a full spec.

### Decision

Write it as a smolspec.

### Rationale

The developer asked for the smallest change and smallest UI inclusion during a live device session. The requirements are settled (two clarifying questions answered), every touch point reuses an existing pattern, and the risk is a one-line predicate applied consistently. A full spec would add documents, not decisions.

### Alternatives Considered

- **Full spec (requirements, design, tasks)**: The workflow's default at this size - Rejected for the session's pace; nothing here needs a design document beyond the approach section.
- **Bugfix report under `specs/bugfixes/`**: Fits the refusal symptom - Rejected because the row and its review behaviour are a feature, not a fix.

### Consequences

**Positive:**
- Spec written and approved within the session.

**Negative:**
- Fewer places to record design detail if the review-row work grows.

---

## Decision 3: Absorb sliver classes of any kind before volume, per class, by area fraction

**Date**: 2026-09-23
**Status**: accepted

### Context

With the dominance refusal gone (Decision 1), the residual-sliver case returns: a 0.21 % `cheese` fringe on a 10 % unknown region is about 5,800 pixels at capture resolution, far above the 12-pixel speckle floor, so it would get a volume and a confident carb figure of its own. The first draft merged only named fringes bordering unknown. The developer asked why the rule should not apply to every sliver: food sits in clumps, and the volume of a sliver of any class is not significant.

### Decision

A food-like class whose total area is under a fraction of the frame's food-like area is a sliver. Every component of a sliver class is relabelled to the class dominating its border, background included, other slivers excluded. The fraction starts at 0.10 and is fixed by the N5k IoU and carb-error measurement before shipping.

### Rationale

Per class rather than per component is what makes it safe: many small pieces of one food (peas, chips) sum to a large class and keep their row, while a fringe is small in total wherever it lands. Judging by area relative to the plate rather than by a pixel count keeps the rule independent of capture distance. Bounding the loss by the fraction of the plate is what makes "not significant" a checkable claim, and the corpus measurement checks it.

### Alternatives Considered

- **Named fringe on unknown only** (first draft): Rejected because the same wobble happens between any two classes, and the fix should not know about unknown.
- **Per-component absolute pixel floor**: A component under N pixels is absorbed - Rejected because a real small food has no safe N across distances, and a food in many small pieces would vanish piece by piece.
- **Thinness test (border-to-area ratio)**: Distinguishes a fringe from a compact blob - Rejected for now as a second constant with no corpus to set it against; revisit if the measurement shows compact small foods being lost.
- **Keep the refusal**: Rejected by Decision 1; a refusal yields nothing.

### Consequences

**Positive:**
- The sliver total cannot recur, for any class pair.
- One rule, one constant, reusing the deterministic pass and its test pattern.
- The constant is set by measurement, not by hand.

**Negative:**
- A genuine side under the fraction of the plate is merged into its neighbour or dropped.
- Two adjacent slivers with no other border stay as they are.

---
