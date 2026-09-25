# Decision Log: Two-View Trust

## Decision 1: Fix and verify two-view geometry before building user confirmation on it

**Date**: 2026-09-25
**Status**: proposed

### Context

The product owner proposed letting the user identify the food in both photos on the two-view path ("the reference and size is powerful"), and asked why the ID-1 card path is not tracked as a problem. The night audit (`docs/agent-notes/two-view-geometry-audit.md`) established three facts: no two-view volume in the corpus has come from the carve (all are the 30 mm single-view extrusion); the stored inter-view transform is in metres against millimetre geometry and its rotation disagrees with the photos on both real bundles examined; and the card path has zero production observations, a fitter fed invented inputs, and unbuilt guidance that two specs mark as done.

### Decision

Order the work as the requirements number it: (1) instrument and verify the inter-view transform on the phone with a checkerboard or card, fix the units and frame convention, and flag two-view records degraded until the carve is shown to run; (2) reconcile a single food-like region across views by geometry, not label; (3) then add the two-tap confirm interaction with per-view silhouette provenance; (4) in parallel, make the card path honest (label, σ_scale, persisted residual) and verifiable from a LiDAR phone via a Debug switch, and file its unbuilt promises.

### Rationale

User-confirmed silhouettes only help a carve that intersects them; tonight's replay with user-quality silhouettes in both views still returned no volume, so the interaction would ship a number from the same 30 mm extrusion the user is trying to correct. The geometry verification is one tethered sitting and gates everything else. Cross-view reconciliation recovers the single-food case with no UI at all once the carve works, and is the fallback when the user skips confirmation. The card path is the metric spine of every non-LiDAR phone and currently produces plausible numbers from furniture; honesty (label, confidence) is cheap and must land before any non-LiDAR promise is repeated.

### Alternatives Considered

- **Build the two-tap confirmation first (Codex's ranking)**: The strongest lever for the segmenter half - Rejected as the first step because the carve does not run on real geometry; the demo would show the extrusion, not the hull.
- **Leave two-view as is and steer users to single-view LiDAR**: Rejected; it abandons the non-LiDAR devices Decision 26 (segmenter-foundation) retained, and the LiDAR phone's Double mode would keep shipping the same wrong number.
- **Recompute after the estimate from stored inputs**: Attractive for the developer phase - Deferred: there is no re-estimate entry point, the oblique photo is not persisted, and slimmed bundles drop the tensors; the confirm-before-shoot flow is cheaper and lets the second shot be guided to the same object.
- **Painting or lasso**: Rejected; meal-review Decision 4's measurements (~79 s per hand-painted mask, ~4 mm touch error) stand, and the carve needs a silhouette the user accepts, not one they draw.

### Consequences

**Positive:**
- The first sitting produces a yes/no on the geometry with numbers, and a fix that is a unit conversion plus a convention if the poses are sound.
- Every two-view record from now on says whether the carve ran.
- The card path stops looking healthy in telemetry.

**Negative:**
- The user-facing confirmation slips behind a geometry fix that may need more than one sitting if the poses themselves are wrong.
- Non-LiDAR phones remain unverified until the Debug switch and a card-only fitter with real inputs exist.

### Impact

`ARKitCaptureEngine` / `CaptureBundleRecorder` (pose logging), `PipelineBridges.transform1To2` and the carve's `applyMat4` (units, convention), `MaskMatcher` (single-region reconciliation), `CaptureFlowModel` / `CaptureFlowView` (confirm steps), `MetricScaleResolver` / `Pipeline.scaleSourceLabel` / `PipelineDiagnostics` (card honesty), `SupportPlaneFitter` card branch, `FixtureRunner` (no-depth replay), `specs/BACKLOG.md` 25–27.

---

## Decision 2: Fix the four two-view geometry defects now; device verification gates trust, not the fix

**Date**: 2026-09-25
**Status**: accepted

### Context

Decision 1 ordered geometry verification first. While preparing the offline demo, the causes turned out to be findable in code: `rigidInverse` did not transpose (so the inter-view rotation was R₂·R₁, a near-180° turn for two downward cameras), the pose translation stayed in metres, the ARKit +y-up frame was never conjugated into the §6.0 +y-down frame, and `VoxelGridSizer` built its grid under the plane by reading world-up as down. A fifth, the session reset between shots, was a plausible path with no evidence either way.

### Decision

Fix all four in one change with unit tests that pin each (`TwoViewTransformTests`, `VoxelGridSizerAxisTests`, `VoxelCarvePlaneExclusionTests` flipped to the correct state), stamp frames with a session generation and refuse cross-generation pairs, record both poses and the mm transform on every two-view outcome, and keep Req 1.3's device verification as the gate on trusting a two-view number. Old bundles are not re-carved: their transforms were composed with the defect and the poses were not stored.

### Rationale

Each defect is a one-line convention error with a test that fails before and passes after; waiting for a device sitting to confirm what the algebra already shows would cost a day. The device verification still matters because the fixes assume ARKit's frame convention, which only a checkerboard in both views can confirm.

### Alternatives Considered

- **Verify on device first, then fix**: Rejected; the algebra is unambiguous for the inverse and the grid sign, and tomorrow's captures would otherwise be taken with the broken composition and be useless for the check.
- **Convert units inside the carve (`applyMat4`)**: Rejected in favour of converting at the boundary in `transform1To2`, where the frame conjugation also lives, so the carve stays unit-agnostic.

### Consequences

**Positive:**
- The first two-view capture tomorrow can produce a carved volume, and its outcome row carries everything needed to audit it.
- `scaleSource`, σ_view and the review copy for two-view can stop describing an extrusion as a hull.

**Negative:**
- Every two-view number recorded before this date is the 30 mm extrusion and must be read as such; the field-truth note's two-view rows are re-annotated.
- A cross-generation pair now refuses where it used to produce a wrong number; the capture model's suspend reset costs the nadir shot after an interruption.

---

## Decision 3: A rectangle is the card only when LiDAR agrees; an accepted card is cleared from the nadir before volume

**Date**: 2026-09-25
**Status**: accepted

### Context

Every `card+lidar` row on the 2026-09-24 bundles was recorded with no ID-1 card in the frame: Vision's rectangle detector accepts anything inside the ID-1 aspect envelope, and the resolver's agreement term could only raise σ_scale, so a plate rim or a packet counted as corroboration. On the one sitting that did use a card (2026-08-11, bundle `1786439234576`) the segmenter labelled the card `cheese` and the two-view path integrated it as 43.7 g. The card's four image corners are solved for scale before segmentation runs, so the pipeline already knows which nadir pixels are card.

### Decision

`CardDetector.detect` returns every ranked rectangle (Vision, up to 8). `CardPoseSolver.solve` rotates a portrait corner list so the long edge is first. `CardPoseSolver.pick` keeps the candidates that reproject as an ID-1 card within `maxResidualPx` (20 px) and, on a LiDAR phone, whose scale is within `maxLidarDisagreement` (0.15) of the LiDAR scale, and takes the closest scale (the lowest residual without LiDAR); with none, there is no card. On the LiDAR path the pick therefore runs after the plane fit. `MetricScaleResolver` drops a card scale that disagrees with the LiDAR scale by more than `maxCardLidarDisagreement` (0.15, symmetric relative) and returns the LiDAR-only result. In `Pipeline`, a card the resolver kept has its quadrilateral cleared to background in both the nadir probability tensor and label map (`SegmentationResult.excluding(quad:)`) before coverage, growth and volume; the capture bundle keeps the segmenter's raw output. The picked card is recorded on the outcome row as `card {pnpResidualPx, distanceMm, scaleMmPerPx, lidarDisagreement, clearedPixels}` and every row carries `cardCandidateCount`. The oblique view is not cleared until Req 1.3 has verified the inter-view transform; the card's projection into the oblique depends on it.

### Rationale

The harness `cards` replay showed Vision's top-ranked rectangle was never the card, even on the two 2026-08-11 bundles that had one: it picked the bread (residual 85 px, 25 % off LiDAR) and a plate phantom (145 px, 38 %), while the real card was candidate 2 of 3 at 2.7 px and 9 % off LiDAR. On the first 2026-09-25 capture the card was portrait and solved at 86 px until the corner order was normalised, then at 14 px, while the bread on the same frame solved at 15 px: the residual alone cannot separate a real card from food, only from plate phantoms (44–158 px). The LiDAR scale can (2 % against 57 %), so with LiDAR the pick waits for the plane fit and the scale decides; a phone without LiDAR has only the residual and Req 4.3's live card gate. The two defects share a cause: a rectangle is trusted on aspect ratio alone. Cross-checking it against LiDAR costs one comparison the resolver already made, and gating the exclusion on that check means a false rectangle over the plate can never erase food. Clearing the probabilities as well as the labels is required because both estimators take the silhouette from the background probability. The 0.15 bound sits between the real cards' 2–9 % and the false picks' 25–94 %; the 20 px residual bound between real cards' 3–14 px and the phantoms' 44 px and up.

### Alternatives Considered

- **Exclude the card from the segmenter's palette (train it as a class)**: Rejected; a retrain per object is the wrong lever when the object's extent is already solved geometrically, and it would not help the non-LiDAR phones that need the card most.
- **Clear the oblique view by running the rectangle detector on it too**: Rejected for now; without a LiDAR cross-check on the oblique a false rectangle would clear food, and the transform-projected quad (Req 4.6) needs the Req 1.3 verification first.
- **Keep Vision's single top observation**: Rejected by measurement; on every corpus bundle it is food or a plate phantom, so the card path could never have run.
- **Refuse the estimate when the card and LiDAR disagree**: Rejected; the LiDAR scale is the one every single-view estimate already stands on, so a bad rectangle is noise to discard, not a reason to refuse.

### Consequences

**Positive:**
- A false rectangle can no longer raise σ_scale or masquerade as `card+lidar` on the outcome row.
- A real card no longer adds a food row on the single-view path or in the nadir silhouette of the carve.
- The card's residual, distance and disagreement are on every row (Req 4.2), so the bound can be tuned from the corpus.

**Negative:**
- The oblique silhouette still contains the card until Req 1.3 passes, so a two-view carve with a card in frame can still carve it.
- On a phone without LiDAR there is no cross-check: the card-only path accepts whatever rectangle Vision finds (Req 4.3's live card gate is the mitigation).

---

## Decision 4: The two-view transform is verified; two-view geometry is trusted from 2026-09-25

**Date**: 2026-09-25
**Status**: accepted

### Context

Decision 2 fixed four geometry defects from the algebra and left Req 1.3, a device check that corners seen in both views back-project within 10 px, as the gate on trusting any two-view number. The afternoon capture `1790310086654` had the ID-1 card flat on the table in both views and the poses recorded on its outcome row, so the check could be done offline on the bundle rather than in another sitting.

### Decision

Req 1.3 is passed and two-view geometry is trusted. The stored `transform1To2Mm` (rotation 23.9° about the image y axis, translation 146 mm) maps the nadir card's P4P corners onto the oblique card face with per-corner errors of 2.9, 9.2, 9.3 and 2.0 px (mean 5.8) when both quads are fitted to the card's gold face; the fixture's `t_1_to_2` equals the row's transform and both equal the transform recomputed from the stored poses. Every alternative convention (inverse, no F conjugation, metres, row-major) misses by 20 px to 700 px. The oblique card exclusion (task 8) and cross-view reconciliation (Req 2) may now build on the transform.

### Rationale

One real capture with a known planar object in both views is the test the requirement asked for, and the transform passes it while every alternative fails by an order of magnitude or more. The residual error is corner detection, not the transform: Vision's oblique rectangle follows the card's visible white side and shadow at 26°, sitting 15–20 px outside the gold face, and against that quad the same projection reads 17.5 px mean. An oblique card P4P scale from a Vision quad is therefore biased about 8 % near, which matters for the non-LiDAR path but not for the transform.

### Alternatives Considered

- **Another device sitting with a printed checkerboard**: Rejected; the card bundle already answers the question and the checkerboard would only tighten a number that is already inside the bound.
- **Accept the 17.5 px Vision-to-Vision figure as a fail and keep two-view untrusted**: Rejected; the excess is the card's thickness in the oblique detection, shown by the gold-face fit and by the oblique P4P depth matching the transform's to 0.3 % once the face is used.

### Consequences

**Positive:**
- Two-view records from this build onward carry a verified transform; the carve's numbers are geometry, not the 30 mm extrusion.
- The oblique half of the card exclusion can project the nadir quad instead of detecting the card again.

**Negative:**
- Oblique card detection over-segments by the card's thickness; any oblique-side card scale must use the projected nadir quad, not Vision's oblique quad.
- The two-view label split (nadir wholemeal, oblique white on the same roll) is now the visible blocker on every two-view estimate.

---

## Decision 5: Reconcile the two views to one class before the carve; a named class beats unknown, the nadir beats the oblique

**Date**: 2026-09-25
**Status**: accepted

### Context

With the transform verified (Decision 4) and the card cleared (Decision 3), every two-view capture of the roll still produced two rows: `1790310086654` gave bread_wholemeal (nadir) + bread_white (oblique), `1790313381100` gave unknown_food 1008 cm³ (nadir) + bread_wholemeal 289 cm³ (oblique). `MaskMatcher` matches classes by label only, so a roll the segmenter names differently in the two views never has a matched class, the carve has nothing to intersect, and each view's class is extruded alone at the 30 mm prior. The owner's note on the second: "1 seems correct, but is perhaps 100 % obscured by 2 unknown food."

### Decision

Before `MaskMatcher`, a reconciliation pass in Volume relabels both views to one carvable class when each view carries at most one named carvable class (unknown_food patches do not count): the chosen class is the named one when only one view has a name, the nadir's when both do, and the user's when Req 3 supplies one. Every carvable pixel in both views moves to that class, in the label map and in the probability tensor (mass of the other carvable channels added to the chosen channel), so the carve sees one matched class with both silhouettes. Views with two or more named classes are left alone (Req 2.3) and the row records `twoViewReconciliation {nadirClasses, obliqueClasses, chosenClass, applied}`.

### Rationale

The two-view path exists to carve, and the carve needs one class present in both views; on a single-food plate the two labels are the same object by construction, so unifying them is the honest reading of the photos. Preferring the named class over unknown_food keeps the nutrition lookup the segmenter did manage, and the user can still rename in review (unknown-food-nameable). Moving probability mass rather than only labels is required because the carve's silhouette test reads the background probability and its per-voxel class from the class channels. Relabelling in the tensors keeps `MaskMatcher` and `VoxelCarveEstimator` unchanged.

### Alternatives Considered

- **Take the nadir's class always (the original Req 2.1 wording)**: Rejected; on `1790313381100` the nadir said unknown_food and the oblique bread_wholemeal, so the rule would have thrown away the only name the segmenter produced.
- **Match by projected silhouette overlap instead of class count**: Deferred; it is what multi-food plates need (Req 2.3), and it needs the transform in the matcher. The single-named-class gate covers every two-view capture in the corpus today.
- **Carve class-agnostically and assign the class afterwards**: Rejected; a larger change to the carve for the same result on single-food plates.

### Consequences

**Positive:**
- A single-food two-view capture yields one row from the carve, with both silhouettes, for the first time.
- The row says what was reconciled, so a wrong merge is auditable.

**Negative:**
- Two named classes in one view disable the pass; a plate of roll plus butter still splits until instance matching exists.
- A confidently wrong nadir name overrides a right oblique name; the review's rename is the remedy.

---

## Decision 6: One connected object is one class; the class-count gate is replaced

**Date**: 2026-09-25
**Status**: accepted

### Context

Decision 5 gated reconciliation on each view carrying at most one named class. The first captures on that build failed the gate: the segmenter labelled the single roll `bread_white` + `bread_wholemeal` + `unknown_food` in the oblique (`1790315734391`, `1790315814452`), and the single-view path split it into `bread_wholemeal` 289 cm³ + `unknown_food` 121 cm³ (`1790315900185`). The owner's review notes: the unknown row hides the bread rows that are right; one roll is three rows.

### Decision

The gate becomes geometric: a view whose carvable pixels form one connected object (largest component at least 90 % of them after a small dilation that bridges speckle gaps) is a single object, and all its carvable pixels take the object's dominant class, the named class with the most pixels, else `unknown_food`. Cross-view choice then follows Decision 5's order (user, nadir's name, oblique's name, unknown). The same per-view step runs on the single-view path before region growth. A view with two or more separate objects is left alone. The record carries each view's classes, whether it was a single object, and the chosen class.

### Rationale

Class counts cannot distinguish "one roll with three labels" from "three foods", but connectivity can on the plates in the corpus: a roll is one blob whatever the segmenter calls its parts, while two foods on a plate are two blobs. Absorbing the scattered classes into the dominant name is what the owner does by eye and what the nutrition lookup needs. Running it on the single-view path too keeps the review consistent between modes and removes the phantom unknown row that made growth's seeds and the review's rows disagree.

### Alternatives Considered

- **Keep the class-count gate and widen it to "all bread classes"**: Rejected; a palette-specific list that fails on the next food the segmenter splits.
- **Instance matching by projected silhouette overlap across views**: Deferred; still the right tool for multi-food plates (Req 2.3), and it needs the per-view object step anyway.
- **Ask the user to tap the object (Req 3) before reconciling**: Rejected as the only path; the tap should refine, not be required for a single roll.

### Consequences

**Positive:**
- One roll is one row in both modes; the unknown row no longer hides the bread rows.
- The gate no longer depends on which classes the segmenter happens to emit.

**Negative:**
- Two foods that touch (a roll against a sausage) become one object under the dominant name until instance matching exists; the review's split and rename are the remedy.
- The 90 % and the dilation width are set by hand on today's captures.

---
