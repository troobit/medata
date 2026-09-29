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

**Date**: 2026-09-24
**Status**: accepted

### Context

With the dominance refusal gone (Decision 1), the residual-sliver case returns: a 0.21 % `cheese` fringe on a 10 % unknown region is about 5,800 pixels at capture resolution, far above the 12-pixel speckle floor, so it would get a volume and a confident carb figure of its own. The first draft merged only named fringes bordering unknown. The developer asked why the rule should not apply to every sliver: food sits in clumps, and the volume of a sliver of any class is not significant.

The fraction shipped at 0.10 pending a corpus measurement. That measurement has now run, and it also corrected where the measurement can be taken: the smolspec named Nutrition5k as the corpus for both halves of the gate, and Nutrition5k can supply neither. `tools/nutrition5k/ingest.py` records that N5k has no ground-truth masks, so `nadir_argmax` is left empty even in `--checkpoint` mode — there is no truth mask to score IoU against. Every one of the 3,485 fixtures is also stamped `estimator_path=mixture` with no probability tensor, so `HarnessCLI accuracy` skips all of them (`probsSizeMismatch(expected: 22118400, got: 0)`) and no carb MAE exists to compare. The corpus that does carry truth masks is the segmenter's leak-free held-out split, which `tools/segmenter/make_fixtures.py` turns into seg-bench fixtures.

### Decision

A food-like class whose total area is under a fraction of the frame's food-like area is a sliver. Every component of a sliver class is relabelled to the class dominating its border, background included, other slivers excluded. **The shipped fraction is 0.05**, carried by `MaskRegularisationConfig.standard`.

### Rationale

Per class rather than per component is what makes it safe: many small pieces of one food (peas, chips) sum to a large class and keep their row, while a fringe is small in total wherever it lands. Judging by area relative to the plate rather than by a pixel count keeps the rule independent of capture distance. Bounding the loss by the fraction of the plate is what makes "not significant" a checkable claim, and the corpus measurement checks it.

The measurement, over the 182-image leak-free held-out split (`data/foodseg103_remapped_v2/heldout_leakfree`) through the shipped checkpoint `ab812dc3aa9d`, 0 skips at every fraction:

| sliver fraction | reported mIoU | classes in mean | mIoU over the 27 classes present at every fraction | delta vs 0 |
|---|---|---|---|---|
| 0 | 0.3804 | 29 | 0.4086 | — |
| 0.05 | 0.4097 | 27 | 0.4097 | **+0.0011** |
| 0.10 | 0.4003 | 27 | 0.4003 | **-0.0083** |

The reported mean is not comparable across fractions and 0.05's apparent +0.029 jump is an artefact: `water` and `milk` are predicted somewhere on this split and score 0.0000 at fraction 0, and absorption removes them from the output entirely, so they leave the denominator (SegBench drops classes whose IoU denominator is 0) and two zeros stop dragging the mean down. Holding the denominator fixed at the 27 classes present at every fraction is the like-for-like comparison, and on it 0.05 is flat while 0.10 costs 0.0083. Per class at 0.10 the losses concentrate in the foods that present as thin or scattered regions — `salad_leaves` -0.057, `tomato` -0.057, `broccoli` -0.047 — which is the rule absorbing real food, not noise. `cheese` is the sharpest warning: 0.0201 at fraction 0, 0.0158 at 0.05, and 0.0000 at 0.10, i.e. at 0.10 the class the residual-sliver bugfix was about stops being predicted anywhere on the split. Absorbing that fringe is the point, but absorbing every cheese region on the corpus is further than the rule was meant to reach.

So 0.05 is the largest of the three that keeps mean food-class IoU from falling, and 0.10 fails that gate. The carb-MAE half of the gate could not be evaluated on any corpus (see Context); it is not evidence for 0.10 and was not treated as such. The five bundles in `tmp/device_captures` replay byte-identically at all three fractions — their stored argmax was already regularised on device, so no sliver class survives in them to absorb — which confirms the rule is inert on already-clean single-dominant plates rather than confirming any particular fraction.

Removing `water` and `milk` from the output is a benefit the IoU number cannot show: both were wholly spurious liquid predictions on a solid-food split, and at 0.05 they stop being emitted at all. That is the unknown-row-and-reject surface's problem shrinking, not just a mask detail.

### Alternatives Considered

- **Ship 0.10, the largest fraction that clears the original gate as literally worded**: The gate says "the largest of 0, 0.05, 0.10 that keeps mIoU from falling", and against the *reported* mean 0.10 (0.4003) does not fall below fraction 0 (0.3804) - Rejected because that comparison is against a different denominator; on the fixed denominator 0.10 measurably falls, and it is worse than 0.05 on both readings. Choosing more absorption than the evidence supports is what the measurement existed to prevent.
- **Ship 0, sliver absorption off**: Rejected because it leaves the residual-sliver case that motivated the rule, and 0.05 costs nothing measurable to avoid it.
- **Re-ingest N5k with `--checkpoint` to make the carb-MAE half measurable**: Would stamp dominant-solid plates `single_dominant` with a probability tensor, so segmentation and therefore the sliver rule would reach the carb figures - Rejected as out of scope for this task: it is the Bucket C regeneration `docs/agent-notes/n5k-calibration-harness.md` already gates on the model-production checkpoint, it would still not supply an IoU truth mask, and it does not change which of 0.05 and 0.10 the IoU evidence supports. Recorded as `specs/BACKLOG.md` item 23 instead.
- **Named fringe on unknown only** (first draft): Rejected because the same wobble happens between any two classes, and the fix should not know about unknown.
- **Per-component absolute pixel floor**: A component under N pixels is absorbed - Rejected because a real small food has no safe N across distances, and a food in many small pieces would vanish piece by piece.
- **Thinness test (border-to-area ratio)**: Distinguishes a fringe from a compact blob - Rejected for now as a second constant with no corpus to set it against; the 0.10 per-class losses on `salad_leaves` and `broccoli` are the evidence that would motivate it, so revisit if the fraction ever needs to rise.
- **Keep the refusal**: Rejected by Decision 1; a refusal yields nothing.

### Consequences

**Positive:**
- The sliver total cannot recur, for any class pair.
- One rule, one constant, reusing the deterministic pass and its test pattern.
- The constant is set by measurement, and the measurement is reproducible: `HarnessCLI seg-bench --sliver-fraction` sweeps it without a rebuild.
- Two spurious liquid classes stop being emitted on the held-out split.
- `SegBench.sample` and `FixtureRunner.run` now regularise exactly as the device does, so every offline number from here on describes the mask the app ships rather than a raw argmax.

**Negative:**
- A genuine side under 5 % of the plate is merged into its neighbour or dropped.
- Two adjacent slivers with no other border stay as they are.
- The carb-MAE half of the intended gate is unmeasured, so the fraction rests on IoU alone; the loss bound is still argued from construction rather than checked against carbs.
- Changing the harness default from "no regularisation" to `.standard` means offline numbers are not comparable with any recorded before this change.

### Impact

`MaskRegularisationConfig.standard`, `SegmenterPostProcessor.regularise` (new public entry point), `HarnessCore/SegBench.swift`, `HarnessCore/FixtureRunner.swift`, `HarnessCLI` (`--sliver-fraction` on `seg-bench` and `accuracy`).

---

## Decision 4: The device pass runs on the provisional sliver fraction; the measurement gates the merge

**Date**: 2026-09-23
**Status**: accepted

### Context

Task 3 (the N5k mean-IoU and carb-MAE sweep over 0, 0.05 and 0.10) is hours of harness time on the Mac. Task 8, the sesame-roll device pass, was blocked on it. The device session on 2026-09-23 exists to remove blockers to food recognition and recording, and the roll is the only field case in hand.

### Decision

Task 8 is blocked by tasks 6 and 7 only. The device pass runs with `MaskRegularisationConfig.standard` carrying the provisional 0.10. Task 3 stays open and gates the merge of `research` into `main`; its result is written into Decision 3 in place (repo `decision_mode` is `overwrite`).

### Rationale

The device pass answers a different question from the measurement: does an unknown-dominant capture reach review, name, and record. The fraction affects which fringes merge, not whether the row exists. Waiting on the sweep would spend the phone-in-hand session idle.

### Alternatives Considered

- **Keep task 8 blocked on task 3**: Honest to Req 10's "before ships" wording - Rejected because the session would end with no field evidence for the whole feature.
- **Device pass at fraction 0**: Passthrough, nothing provisional - Rejected because the sliver bugfix's case would return on the phone as a confident named row, which is the failure the rule exists to prevent.

### Consequences

**Positive:**
- The session yields the field trail for Req 1–9 today.
- The measurement still lands before any user-facing build.

**Negative:**
- The field note for 2026-09-23 records a build whose sliver constant may change.

---
