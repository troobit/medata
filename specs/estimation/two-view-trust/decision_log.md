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

## Decision 7: One tap per view does not cut the single-view growth leak; the gate fails and Req 3 is re-decided

**Date**: 2026-09-25
**Status**: rejected

### Context

This decision previously proposed one tap per view on the frozen frame, doing two things: clearing every carvable component the tap does not name from that view's silhouette, and restricting the region growth's seed set to the component that survives. Its claimed benefit was the **second** mechanism only — the silhouette term was already measured at ~7 % of the two-view over-read and disclaimed as a reason to build anything. The claim was that the seed set today is every pixel the segmenter called food-like, that on the leaking captures it includes speckles out on the plate, and that one point certainly on the food removes those speckles and so removes the leak.

Req 3.15 made that claim a hard gate before any capture-surface code: replay the two documented single-view leak bundles from a hand-placed seed and compare against the 267–302 cm³ the same roll reads elsewhere. The gate has now been run. `FoodRegionGrowth.grow` takes a `seedPoints:` restriction (4-connected volumetric components containing a point survive; the rest become background, in the map the fill seeds from, in the map `prune`'s seed band is measured on, and in the map the integrator reads), `FixtureRunner.run` takes `nadirSeed:`, and `HarnessCLI volumes` takes `--seed-x/--seed-y` in nadir colour-grid pixels. Default behaviour with no point is byte-identical.

Seeds were placed at the centre of the roll as a person sees it in the nadir frame and confirmed by eye on the rendered frame before any number was read. Shipped config (floor 5 mm, band 10 mm):

| bundle | food px before → after, unseeded | volume | food px before → after, seeded | volume |
|---|---|---|---|---|
| `1790315900185` (leak) | 88,513 → 141,758 | 298.9 cm³ | 84,293 → 137,072 | 291.6 cm³ |
| `1790315865030` (leak) | 121,881 → 137,871 | 309.5 cm³ | 121,479 → 138,831 | 315.9 cm³ |
| `1790310107431` (clean) | 112,439 → 155,916 | 219.4 cm³ | 112,439 → 155,916 | 219.4 cm³ |
| `1790232681422` (clean) | 146,278 → 152,460 | 283.5 cm³ | 146,278 → 152,460 | 283.5 cm³ |

With the seed band disabled (`--growth-band-mm 0`), the configuration in which the leak is actually visible, the seed changes nothing at all:

| bundle | unseeded | seeded |
|---|---|---|
| `1790315900185` | 241,743 px, 410.2 cm³ | 241,779 px, 410.3 cm³ |
| `1790315865030` | 236,464 px, 428.8 cm³ | 236,572 px, 438.0 cm³ |

Sensitivity, seed moved 20, 40 and 80 px in four directions from the chosen point: on both leak bundles every result is identical to the centred one to the last digit, with one exception — 80 px left of centre on `1790315900185` the point lands on a pixel the segmenter labelled background, the restriction is inert by design, and the run returns the unseeded number.

### Decision

**The gate fails.** One hand-placed seed does not materially cut the grown region on either leak bundle, does not move either volume into a place the 267–302 cm³ reference distinguishes from where it already was, and moves `1790315865030` the wrong way (+6.4 cm³, further from the reference). Decision 7's claimed mechanism is false and this decision is rejected. Req 3 MUST be re-decided before any capture-surface code is written; the tap is not carried forward on the strength of the growth seed.

The seed-restriction code and the `--seed-x/--seed-y` replay stay in the tree as the measurement instrument that produced this result, unused by the shipping path.

### Rationale

The premise was wrong about where the leaking seeds are. Restricting the seed set to the tapped component removes 4,220 of 88,513 seed pixels on `1790315900185` (4.8 %) and 402 of 121,881 on `1790315865030` (0.3 %), and removes nothing on the two clean bundles. Those stray speckles are not what the fill runs on. The plate region is reached from the **roll's own component**, across the gentle food-to-plate depth slope that depth-grown-food-region Decision 1 already measured and named — the fill leaves the roll and walks down onto the plate because no cliff stops it. A seed rule cannot cut a leak whose seed is the food itself, and the band-off table is the direct proof: 241,743 px unseeded against 241,779 px seeded on the same bundle, the seeded run marginally **larger**.

The two clean bundles confirm the other half: the seed does not hurt them, because on a well-segmented plate there is only one component and the restriction is a no-op. That is a null result on both sides, not a trade.

The sensitivity result is the same finding seen from the user's end. The volume is perfectly flat to ±80 px of thumb wobble not because the seed is robust but because it is inert: nothing downstream depends on which of the food's pixels was named. The one non-flat cell is a failure mode rather than a gradient — a tap 80 px from centre, visibly still on the roll, landed on a pixel the segmenter had labelled background (the labelled mask is 88.5 k px on a roll whose true footprint is larger and patchily labelled), so the seed did nothing at all. An interaction whose only observable behaviour is "no effect, or silently no effect" cannot be sold to a user.

What remains true from the previous version is what it had already conceded: the silhouette-clearing half is worth ~7 % of the two-view over-read and was explicitly not a reason to build anything, and the grid vertical cap still owns ~92 % of it (Decision 8). With the growth-seed half now measured at zero, nothing load-bearing is left.

### Alternatives Considered

- **Keep the tap and re-argue it on the silhouette term**: The component-clearing half still removes a card or a second food for free - Rejected: this decision already measured that term at ~7 % of the two-view excess and declined to build for it, and the two clean bundles show it is a no-op on a single-food plate. Re-adopting it now would be choosing the interaction first and the justification second.
- **Move the seed rule earlier, to the plane fit**: Anchoring the first support-plane fit to the tapped component would change the plate-versus-food height reference, which is the term the leak actually turns on - Not rejected, not tested: it is a different mechanism from the one Decision 7 claimed and belongs in a decision of its own under depth-grown-food-region, measured the same way. It is the most promising direction this gate turned up.
- **Tune the seed rule until the numbers improve** (8-connectivity, a seed disc, a seed-anchored band floor): Rejected on principle; the gate exists to test a stated mechanism, and the band-off table shows the mechanism is absent, not weak. Tuning until it looks positive is the failure mode Req 3.15 was written to prevent.
- **Declare the gate passed because both leak bundles already read 291–316 cm³**: Rejected as dishonest. They read 298.9 and 309.5 cm³ **unseeded**, on the shipped floor-5/band-10 config — Decisions 3 and 4 of depth-grown-food-region had already cut the leak that the 410 cm³ and 428.8 cm³ figures describe. The seed is not what put them there.
- **Run the gate on the four two-view bundles instead**: Rejected by Req 3.15 itself, which forbids using them as the criterion; Decision 8 shows the grid height cap owns those numbers.

### Consequences

**Positive:**
- Req 3 is falsified before a line of capture UI was written, which is exactly what Req 3.15 was for. The cost was one afternoon of replay, not a device sitting and two tagged UI attempts.
- The leak now has a correctly identified cause: the fill crosses the food-to-plate slope from the food's own component, so any fix must act on the growth's stopping rule or on the plane the heights are measured against, not on which pixels seed it.
- `grow(seedPoints:)`, `FixtureRunner.run(nadirSeed:)` and `volumes --seed-x/--seed-y` exist and are tested, so the next "the user can point at it" proposal can be measured the same way in minutes.
- The two clean bundles are byte-identical seeded and unseeded, so nothing shipped regressed.

**Negative:**
- The single-view growth leak has no lever at all now; the 5 mm floor and the 10 mm seed-relative band remain the only things holding it, and on `1790315865030` the shipped number (309.5 cm³) still sits above the 267–302 cm³ reference.
- The non-LiDAR path loses the one mitigation this decision offered it (Req 3.19), leaving Decision 8's degraded flag as the whole story there.
- Dead-but-kept code: the seed restriction is in `Volume` with no caller on the shipping path. It is small and tested, but it is a measurement instrument in a production module and should be removed if nothing claims it.
- Requirement 3 and its tasks are now stale in a spec that has shipped work either side of them; the re-decision has to say what, if anything, replaces "the user identifies the food".

### Impact

`MedataCore/Sources/Volume/FoodRegionGrowth.swift` (`restrictToSeededComponents`, `grow(seedPoints:)`), `HarnessCore/FixtureRunner.swift` (`run(nadirSeed:)`), `HarnessCLI` (`volumes --seed-x/--seed-y`), `MedataCore/Tests/VolumeTests/FoodRegionGrowthTests.swift`. Nothing in `App/`, `Pipeline/` or `SupportPlane/` changed, and no capture-surface work starts from this decision. Req 3.1–3.19 are held pending the re-decision; Req 3.15 is discharged.

---

## Decision 8: A non-LiDAR two-view volume is not defensible until a height bound exists

**Date**: 2026-09-25
**Status**: proposed

### Context

The two-view shape-from-silhouette carve now runs end to end: the inter-view transform is verified (Decision 4), the reference card is excluded from both views (Decisions 3 and 6), and the two views are reconciled to one object and one class (Decision 6). What it returns is still wrong by a factor of three, and the cause is not any of those things.

Measured 2026-09-25 with a synthetic control — exact silhouettes of a 120 x 70 x 40 mm box, the real camera intrinsics and the real inter-view baseline, carved through the shipping `VoxelGridSizer` and `VoxelCarveEstimator` against a voxelised truth of 337 cm³:

| oblique tilt from vertical | carved | vs truth | with the grid capped at the object's real height |
|---|---|---|---|
| 26° | 800.7 cm³ | 2.38x | ~375 cm³ |
| 22.2° (this capture's inter-view rotation) | 832.8 cm³ | 2.47x | ~372 cm³ |
| 40° | 712.0 cm³ | 2.11x | ~375 cm³ |
| 60° | 552.0 cm³ | 1.64x | ~376 cm³ |

Below the object's true height the carve is accurate. Above it, the two silhouette cones never meet: a voxel at height h leaves the oblique silhouette only once h·tan(θ) exceeds the object's extent along the tilt direction, which for this roll is 139 mm / tan(22.2°) ≈ 340 mm — far beyond any plausible grid. The voxel grid's vertical extent is therefore the only thing that stops the carve, and it is what sets the answer: on the real bundle the cumulative volume runs 238 cm³ at a 24 mm cap, 460 at 48 mm, 656 at 72 mm, 810 at 96 mm and 927 at the shipped 120 mm, with the topmost layer still keeping 42 % of the base layer's voxels. Closing the hull on this roll would need about 74° of tilt, and the shutter arms only between 10° and 40° (`CaptureFlowModel.obliqueTiltOk`).

With LiDAR this is solvable and is being solved: the nadir frame already carries the depth the single-view path uses to read the same roll at 267–302 cm³, so the grid can be bounded by a measured food height. Without LiDAR there is no height information in the capture at all, at any tilt the app allows. That is the path every phone without LiDAR must use, and the one the ID-1 card exists for.

**Confirmed against weighed truth, and re-ordered, 2026-09-29.** The roll was
weighed at 104 g (`benchmark_meals` row `backfill-1790655037216-roll`), which at
the measured bread_wholemeal density of 0.4 g/cm³ puts truth volume at
**260 cm³**. The historical two-view rows of 851 / 920 / 930 cm³ are therefore
**3.3–3.6× truth** — the "factor of three" above is now measured against a
weighed object rather than inferred from a synthetic control, and the
single-view band of 267–302 cm³ is **+3 % to +16 %**, so the asymmetry this
decision rests on is real.

The same session also moved what blocks first. Seven two-view captures on build
`2d39910`, six refused, and every logged estimate ran the same chain:

```
supportplane.end success=false failure=noLowerSilhouetteEdges stats=unfitted
estimate.end     success=false failure=noSupportPlaneWithoutDepth
estimate.degraded reason=unbounded_carve_height   (stamped earlier, see below)
```

Both photographs were good every time (`capture.end success=true`, 1920×1440), so
this is not a capture or framing fault. **The no-depth branch refuses before any
candidate collection**: `SupportPlaneFitter` returns `.noLowerSilhouetteEdges`
unconditionally when `nadir.depth == nil`, so the estimate dies before any height
bound — including Decision 11's per-class cap and the footprint-scaled cap —
could apply.

**Two readings of that transcript are wrong and were corrected the same day.**
The lines first recorded here carried `candidates=0 inliers=0` and bbox −1, read
as a detector that had searched and found nothing. Those are a
default-constructed `SupportPlaneFitStats`: nothing ran, and `-1` is the
documented sentinel for "refused before a residual was computed". The refusal now
logs `stats=unfitted` with no numbers. Nor are the three lines a cascade —
`unbounded_carve_height` is stamped from `twoViewSfS && depth == nil` before any
stage can refuse, so it is a property of the capture, not a consequence of the
plane fit. This decision's conclusion is unaffected: the plane fit is what blocks
first, and it blocks by construction rather than by measurement. The capture-side experiment this decision asks for (oblique at 70–80°)
therefore cannot return a number yet, and it is not the next thing to try: the
plane fit is. The status stays **proposed** for that reason, and the ID-1 card is
the obvious plane source, since an accepted card supplies three coplanar points
on the table.

### Decision

Until a height bound exists for the non-LiDAR path, a two-view estimate taken without depth MUST NOT be presented as a measurement: it is recorded, flagged degraded on the row and in review, and the carb figure it produces is not offered as a dosing number. The capture-side experiment that decides what to build is a single capture of a known object with the oblique deliberately near side-on, which requires a developer-phase way to arm the shutter outside the present band.

### Rationale

The measurement is unambiguous about where the error lives, and it is not anywhere that more careful segmentation, a better transform or a tighter mask can reach. Shipping a number that is three times the truth, on the path taken by the phones least able to check it, is the dangerous direction for a tool whose output informs an insulin dose. Flagging it costs nothing and is honest about what the geometry can support.

The options for actually fixing it differ by an order of magnitude in cost, and the cheapest one has not been tested. A wider aim band is free if it works: the same carve, the same code, a different instruction to the user. At 60° the synthetic hull does close (both silhouettes reach zero by about 90 mm), so the question is not whether steep tilt bounds height — it does — but whether a near-side-on photograph of a plate keeps the food in frame, keeps the card's PnP pose solvable, and leaves the support plane fittable. One capture answers all three.

### Alternatives Considered

- **Widen the capture band toward side-on**: The hull provably closes by 60° on this geometry and the code needs no change. Not yet chosen because no capture has been taken past 40° — the shutter will not arm — so nothing is known about whether the food stays framed, whether the card remains solvable at that obliquity (Decision 4 already measured Vision over-segmenting the card by 15–27 px at 26°), or whether the plate occludes the food's base. This is the option to test first.
- **A third photograph from a second azimuth**: Adds silhouettes but not height information — three shallow cones still fail to close the top. Rejected on the same geometry that rejects the current pair.
- **A height-from-footprint prior per food class**: Deterministic and offline, and it would bound the grid. Rejected as the first move because its error is unbounded in exactly the cases that matter — a roll and a bowl of rice with the same footprint differ several-fold in height — and it would silently substitute a table lookup for a measurement while the row still claimed to be a carve.
- **Stand the ID-1 card upright beside the food as a vertical ruler**: Gives a true metric height reference in the image. Rejected for now as a first move: it changes the card's role mid-capture, the card must then be detected in a pose the solver treats as too oblique, and it asks the user to balance a card on a table beside their dinner.
- **Refuse a volume on non-LiDAR and offer a portion picker instead**: Honest and cheap, and it is what the degraded flag approximates. Rejected as the end state because it abandons the capability the non-LiDAR path exists to provide (segmenter-foundation Decision 26 retains that path deliberately), but it is the fallback if the tilt experiment fails.
- **Shading or focus cues to infer height**: Rejected; not deterministic, not robust to a kitchen table, and far beyond the offline-geometry budget this estimator is built on.

### Consequences

**Positive:**
- No phone without LiDAR reports a three-times-high carbohydrate figure as though it were measured.
- The next decision rests on one capture rather than on an architecture argument.
- The LiDAR path is unaffected and keeps its measured height bound.

**Negative:**
- The non-LiDAR path has no usable volume until the experiment is run and something is built, which is a real reduction in what the app claims to do on those devices.
- A developer-phase shutter that arms outside the tilt band exists only to take an experimental capture, and must not leak into a Release build.
- The degraded flag is a promise to come back; if the tilt experiment fails and no prior is acceptable, the honest outcome is removing the non-LiDAR volume claim rather than leaving a flag on it indefinitely.

---

## Decision 9: No two-view correction factor and no height-bound tuning; the residual is accounted for

**Date**: 2026-09-25

**Status**: accepted

### Context

After the two fixes of the 2026-09-25 evening — the grid sized to the measured
food height instead of a flat 120 mm, and the silhouette taken from the
regularised argmax instead of the raw tensor at 50 % non-background — three real
bundles replayed at 397, 510 and 351 cm³ against a single-view LiDAR reference
of 267–302 cm³ for the same roll. That is 1.3–1.9x high, and three candidate
causes were open: the visual hull's own bias, a nadir silhouette still wider
than the food, and a height bound reading high (the P98 measured 47.3, 50.4 and
36.0 mm on rolls of about 40 mm). The obvious next moves were to lower the
height percentile, to tighten the mask, or to introduce a two-view β — the
per-class correction factor the codebase already applies on both estimators.

`HarnessCLI carve-audit` (added with this decision) measured all three on five
two-view bundles. The accounting is in `docs/agent-notes/two-view-geometry-audit.md`
§7. Three findings change the question.

First, the 267–302 cm³ band is a different capture. The like-for-like reference
is the height-field integral over the same nadir frame, the same plane and the
same silhouette the carve used. Against that, the carve reads 1.10, 1.19, 1.25,
1.10 and 1.37. A synthetic control at each bundle's own geometry — exact
silhouettes of a box of known size, real intrinsics, the real stored transform,
through the shipping sizer and estimator — puts the hull's unavoidable bias at
1.05–1.17. The unexplained part is 0–24 %, and zero on the bundle the earlier
analysis was built around.

Second, the footprint is not wide. A raised object's silhouette back-projected
to the support plane exceeds its footprint by (d / (d − h))² from perspective
alone; the synthetic control measures a true 84 cm² x 40 mm object at 108–119
cm² by the identical rule, and four of the five real rolls measure at or below
that.

Third, the height percentile has no leverage. P90 to the raw maximum spans
0.8–1.9 mm on every bundle, under one 3 mm voxel, and after rounding to whole
voxels P90, P95, P98 and the maximum give the identical carve on four of five.
The P98 reads high because the MEDIAN reads high (44.7 mm where the P98 reads
47.3) — the whole smoothed surface sits near the apex — not because the
percentile is reaching into a tail.

### Decision

Change no constant. `heightPercentile` stays at 0.98 and `heightMarginMm` at
5 mm, the silhouette rule stays as it is, and no two-view β is introduced.
Ship the measurement instead: `HarnessCLI carve-audit` and the accounting in the
agent note, so the next person arrives at the numbers rather than the
hypotheses. Record that the one structural difference found between the paths —
the single-view branch refits its support plane from the grown food region and
the two-view branch never refits — is the next lever, worth 6–23 % on two of
five bundles and nothing on the other three, and that it is a `Pipeline` change
to be taken deliberately rather than folded into this accounting.

### Rationale

A β exists to absorb a systematic, geometric bias, and the hull's
circumscription is exactly that shape of error. But β is calibrated from weighed
truth, the corpus holds three weighed plates, and none of them are two-view. A
two-view β fitted today would be one number derived from one bread roll
photographed five times, dressed as a calibration. The measured spread of the
unexplained excess across those five captures is 1.00 to 1.24 — wider than any
constant could usefully split — which is itself the evidence that the input is
too thin.

The height bound cannot be tuned because the quantity it reads has no tail to
trim. Lowering the percentile moves the answer by less than the voxel edge.
Lowering the 5 mm margin does move it, by about 11 %, but at 0 mm it clips real
food on three of five bundles (1.9 %, 5.7 % and 8.0 % of the height samples sit
above the resulting extent), and the only clip-free reduction, 2 mm, is below
the measured plane residual of 2.0–3.2 mm the margin exists to cover. Spending
it would buy a better-looking number by discarding measured food, which is the
failure mode the percentile was deliberately left untuned to avoid.

What remains after the hull bias is the difference between a food's volume and
the convex hull two near-vertical silhouettes can describe of it. A roll is
roughly 83 % of its bounding prism and cones at the tilts the aim guide allows
cannot see the taper. Nothing offline distinguishes that from a systematic
estimator error; only weighed truth on two-view captures can.

### Alternatives Considered

- **Introduce a two-view β from the current corpus**: Directly targets a
  systematic geometric bias, which is what β is for, and would land the roll in
  the reference band. Rejected: the only truth available is three weighed
  plates, none two-view, so the constant would be fitted to one roll and would
  then be indistinguishable from the hull bias it is meant to correct. It also
  bakes today's plane-fit inconsistency into the coefficient, so fixing the
  plane later would silently double-correct.
- **Lower `heightPercentile` to P90 or P95**: The cheapest change available and
  the one the earlier analysis implied. Rejected on measurement: the top decile
  of the height distribution spans under one voxel, so the carve is unchanged on
  four of five bundles, and on the fifth P90 is the setting that clips 8.0 % of
  the food.
- **Lower `heightMarginMm` from 5 mm to 2 mm**: Worth about 5 %, clips nothing
  on any of the five bundles. Rejected because 2 mm is below the plane residual
  measured on the same bundles (2.0–3.2 mm); the margin covers quantisation and
  the plane's own fit error, and both are larger than the saving.
- **Tighten the nadir silhouette further**: Rejected on measurement — the
  synthetic control shows the silhouettes are already at or below what a
  geometrically perfect object of the roll's size produces, so tightening would
  remove real food.
- **Refit the two-view support plane from the grown region now**: The one lever
  the audit did find, worth 6–23 % on two bundles. Deferred, not rejected: it is
  a change in `Pipeline`'s two-view branch, it changes what every future
  two-view row means, and it deserves its own decision with its own device
  round rather than being carried in on an accounting pass.
- **Keep chasing the 267–302 cm³ band**: Rejected once the band was shown to
  come from different captures whose own nadir depth reads the food at 258–430
  cm³. Closing a gap to a reference that disagrees with itself by 1.7x is
  fitting to noise.

### Consequences

**Positive:**
- No constant in the estimation path is tuned to one food, and the two-view
  number stays traceable to geometry rather than to a fitted correction.
- The residual is now split into a part that is measured and unavoidable (the
  hull's 5–17 % circumscription) and a part that is not (0–24 %), so a future
  β has a defined job instead of absorbing everything.
- `carve-audit` re-runs the whole accounting on any bundle in about a second,
  so the next round starts from numbers.
- The plane-refit asymmetry between the single-view and two-view branches is now
  measured and recorded rather than latent.

**Negative:**
- The two-view carve still reads above the single-view one on the same food, and
  this decision does not close that gap — it explains it and declines to paper
  over it.
- The gap can only be closed with weighed truth on two-view captures, which is a
  kitchen-scale session that has not happened.
- `carve-audit` is a diagnostic with no production consumer; it is code to carry
  and will rot unless a later round uses it.

### Impact

`MedataCore/Sources/Volume/VoxelGridSizer.swift` (`foodHeightSamplesMm`,
`percentile` — a refactor, `measuredFoodHeightMm` is unchanged in behaviour),
`MedataCore/Sources/Volume/FoodRegionGrowth.swift` (`heightAboveSupportPlaneMm`
made public so the diagnostic measures the production height rather than a
copy), `HarnessCore/CarveResidualAudit.swift`, `HarnessCLI` (`carve-audit`),
`MedataCore/Tests/VolumeTests/VoxelGridHeightSamplesTests.swift`,
`MedataCore/Tests/HarnessCLITests/CarveResidualAuditTests.swift`,
`docs/agent-notes/two-view-geometry-audit.md` §7. Nothing in `App/`,
`Pipeline/` or `SupportPlane/` changed, and no device behaviour changed.

---

## Decision 10: The two-view branch refits its support plane from the grown region, plane only

**Date**: 2026-09-27

**Status**: proposed (until a device round; the offline replay is in, the
phone has not run it)

### Context

Decision 9 closed the carve-residual accounting with one lever left on the
table: the single-view branch grows the nadir food region from its first
plane and refits the plane from the grown mask (depth-grown-food-region
Decisions 1, 3, 4), while the two-view branch fitted its plane once from the
pre-shutter mask and never refitted. `docs/agent-notes/two-view-geometry-audit.md`
§7 (c) measured that asymmetry on five two-view bundles as worth −23 % and
−5.7 % on the two bundles where the refit changes the plane, and under 1 %
on the other three. Decision 9 deferred it deliberately: it changes what every
future two-view row means and deserves its own decision.

Since then `specs/DECISIONS.md` MD-29 made volume correctness on the two-view
and LiDAR paths the top priority of estimation work, above class accuracy.
The plane is the one measured, structural, offline-verifiable difference
between the two paths, and it is a `Pipeline` change, not a `Volume` one.

### Decision

The two-view branch runs the same grow → refit → prune → adopt sequence as
the single-view branch, after reconciliation and before the carve, and takes
the **plane only**: `plane`, `planeReference` and the LiDAR metric scale
follow an adopted `foodSupport` refit exactly as on the single-view branch,
and the carve silhouette, the review outline and the persisted mask stay the
segmenter's own reconciled map. The sequence moves into one shared function,
`Volume/GrownRegionPlaneRefit.refit`, called by both `Pipeline` branches, by
`FixtureRunner`'s replay of both, and by `CarveResidualAudit`'s `grownRefit`
variant, with the plane fitter injected. Decision 3's guard (a table refit is
never adopted) and the prune apply on the two-view branch unchanged. The
outcome row's `regionGrowth` gains `planeOnly` (`true` two-view, `false`
single-view, absent on older rows).

Fallback rule: if growth is later gated or retired, the two-view refit falls
back to a refit from the reconciled argmax, never silently to the first
plane. The branch must not quietly return to fitting once.

### Rationale

The plane is both the carve's floor and the origin the grid's vertical extent
is measured from (`VoxelGridSizer.measuredFoodHeightMm`), so a first plane on
the table under a plate hands the carve a slab of hull the height of the
plate rim across the whole footprint — about 90 cm³ at these footprints. The
single-view branch already corrects this; the two-view branch measured the
same food 6–23 % higher for want of it. Sharing one function is what makes
the two branches adopt a plane by one rule, so a future change to the rule
(a floor, a band, a guard) cannot land on one path and not the other.

Plane only, because the growth pass's plate leak (backlog 30, Decision 4's
open defect) would otherwise widen the two-view silhouette, and nothing has
measured a grown two-view outline. The plane is the lever the audit measured;
the silhouette is not.

Measured offline, `HarnessCLI carve-audit` and `volumes` on the five §7
bundles, before (untouched `research` at f6046b3) and after this change. The
first two columns are the audit's as-fitted plane, which the change does not
touch; `grownRefit` is now the plane production adopts; the last column is
the `volumes` replay of the shipped two-view path:

| bundle | as fitted | carved before | grownRefit after (refit) | dist mm | residual mm | extent mm | carved | height field | hull ÷ surface | production after |
|---|---|---|---|---|---|---|---|---|---|---|
| `1790318627741` | edgeBand | 397.1 | edgeBand (edgeBand, held) | −401.3 | 2.59 | 54.0 | 397.1 | 358.0 | 1.109 | **397.1** |
| `1790315814452` | edgeBand | 509.8 | **foodSupport** | −386.5 | 2.27 | 45.0 | 390.1 | 317.2 | 1.230 | **390.1** |
| `1790310086654` | foodSupport | 351.4 | foodSupport | −395.6 | 2.18 | 42.0 | 350.3 | 283.3 | 1.237 | **350.3** |
| `1790315734391` | foodSupport | 284.1 | **foodSupport** | −358.1 | 2.30 | 36.0 | 268.0 | 244.0 | 1.099 | **268.0** |
| `1790325380366` | foodSupport | 358.8 | foodSupport | −383.4 | 2.02 | 36.0 | 358.9 | 261.8 | 1.371 | **358.9** |

Every production figure equals the `grownRefit` figure §7 predicted, and
`1790318627741` is held at 397.1 by the Decision 3 guard where the earlier
raw-refit reading was 396.5 (the audit's `grownRefit` used to skip the guard
and the prune; it no longer does, and prints the refit's own reference as
`refit=` beside the plane it adopted). The hull-over-surface ratio stays
above 1 on every bundle, the acceptance check that the plane did not rise
into the food. The single-view control rows in the same directories replay
byte-identically: `1790315900185` 298.9 cm³, `1790315865030` 309.5 cm³,
`1790310107431` 219.4, `1790318604792` 272.0, `1790318616477` 266.9.

### Alternatives Considered

- **Full parity — grow the two-view silhouette too**: The simplest statement
  ("the two branches are the same up to the estimator"). Rejected for now: it
  changes the outline the owner reviews and imports backlog 30's plate leak
  into a branch whose silhouette is intersected from two views, and no
  measurement exists of a grown two-view outline. Plane only is the measured
  part; the silhouette can follow its own decision.
- **Refit from the reconciled argmax without growth**: Cheaper and free of the
  growth pass's failure modes. Rejected as the default because it is
  unmeasured and leaves the branches adopting planes by different rules; it
  is the fallback if growth is gated or retired.
- **Defer until weighed two-view truth exists (Decision 9's position)**:
  Rejected because MD-29 makes volume the priority, the change is offline
  measurable to the tenth of a cm³ on the bundles already in the corpus, and
  weighed truth would decide the hull bias, not the plane.
- **Change the two-view first fit instead (a plate-aware pre-shutter mask)**:
  Would move the same bundles without a second fit. Rejected: the pre-shutter
  mask is the segmenter's live output before the shutter and has no depth
  grown region to fit from; the refit exists precisely because the first fit
  is made before the food is known.

### Consequences

**Positive:**
- The two bundles §7 flagged drop 23 % and 5.7 %; the other three move by
  under 0.4 %, so the change is targeted where the plane was wrong.
- Both branches, the harness replay and the audit adopt a plane through one
  function, so the Decision 3 guard and the prune cannot drift apart between
  paths.
- The `carve-audit` `grownRefit` variant is now production-faithful.
- The single-view path is byte-identical (regression bar met on eight
  corpus bundles and the existing replay tests).

**Negative:**
- Two-view rows written before and after this change are not comparable
  where the refit lands `foodSupport`; `regionGrowth.planeOnly` marks the
  new rows, absent marks the old.
- A wrongly grown region can now move a two-view plane. The Decision 3 guard
  and the prune bound it (a table refit is held, a region pruned to nothing
  holds the first plane), but a `foodSupport` refit from a leaked region is
  adopted on both branches alike.
- One more plane fit per two-view estimate on device; unmeasured, expected
  to be the same cost the single-view branch already pays.
- Status stays proposed until a device round reads `event=region.grow
  planeOnly=true` on a Double-mode capture of the roll (task 21.2).

### Impact

`MedataCore/Sources/Volume/GrownRegionPlaneRefit.swift` (new),
`MedataCore/Sources/Pipeline/Pipeline.swift` (both volume branches call
`refitPlaneFromGrownRegion`), `MedataCore/Sources/Pipeline/PipelineDiagnostics.swift`
(`RegionGrowthMeasurements.planeOnly`), `HarnessCore/FixtureRunner.swift`
(both replay branches; reconciliation hoisted out of `runVoxelCarve` so the
refit sees the reconciled map, as on device), `HarnessCore/CarveResidualAudit.swift`
(`grownRefit` through the shared helper, `PlaneVariant.refitReference`),
`HarnessCLI` (`refit=` on the variant line),
`MedataCore/Tests/VolumeTests/GrownRegionPlaneRefitTests.swift`,
`MedataCore/Tests/VolumeTests/VoxelGridMeasuredHeightTests.swift`,
`MedataCore/Tests/HarnessCLITests/FoodRegionGrowthReplayTests.swift`,
`docs/agent-notes/depth-grown-food-region.md`,
`docs/agent-notes/two-view-geometry-audit.md` §7 (c).

---

## Decision 11: A per-class height cap bounds the carve where no height is measured

**Date**: 2026-09-27

**Status**: accepted

### Context

Decision 8 measured where the non-LiDAR two-view error lives: two silhouette
cones at the tilts the aim guide allows never close over a low food, so the
voxel grid's vertical extent is not a safety cap on the carve, it is the
answer. With nadir depth the grid is sized to the measured food height
(task 16); without it the shipped 120 mm constant stands and a bread roll
reads 2.5x. Decision 8 rejected a height-from-footprint prior as the first
move because its error was unbounded, and asked for a height bound before a
no-depth two-view number could be called a measurement.

`docs/research/on-device-models-2026-09.md` ("Job B") found no monocular
depth model whose absolute error at 20–60 cm is small beside a 2–5 cm food
height, and ranked a class height prior first: zero bytes, deterministic,
offline. `tools/metafood3d/HEIGHT_PRIORS.md` then measured every MetaFood3D
mesh seated on its support plane and read the result plainly: a P90 cap
bites the Decision 8 sweep by about 18 % and does not solve it, because the
bread category spans a 17 mm slice, a 32 mm roll and a 104 mm loaf and the
palette does not carry form. The five §7 audit bundles are all rolls; their
LiDAR maxima run 30–51 mm against a class P50 of 31.6, so a P50 cap would
clip three of them.

### Decision

The voxel carve takes a per-class height cap, `ClassHeightPriors`, from the
bundled `height_priors.json` (a byte-identical copy of the MetaFood3D
output): `cap = class max-height P90 + the shipped 5 mm margin`, and the
global P90 (71.8 mm) plus the margin for a class with no meshes or fewer
than four, `unknown_food` included. The cap is the loosest of the caps of the
carvable classes the reconciled nadir map carries. Where no height is
measured the cap is the grid's vertical extent; where one is, the extent is
`min(measured + margin, cap)` and the cap can never raise it
(`VoxelGridSizer.verticalBound`). `Pipeline`'s two-view branch and the
harness replay size the grid by the same rule, the outcome row's `voxelGrid`
records `classCapMm` and `capSource` (`measured` / `classPrior` / `global` /
`constant`), and `event=grid.height` prints `cap_mm` and `cap_source`.

The Decision 8 flag stands: a two-view estimate without depth is still
`unbounded_carve_height`, degraded, and not offered for dosing. The cap
bounds that number; it does not make it a measurement.

### Rationale

Measured offline with `HarnessCLI carve-audit --no-depth --tilts
22.2,26,40,60 --caps 120,85.9,40` and `volumes`, on the five §7 bundles and
the two single-view controls, before and after.

**The LiDAR path is unchanged.** Every two-view bundle replays to the
Decision 10 figure — 397.1, 390.1, 350.3, 268.0, 358.9 cm³ — and the
single-view controls `1790315900185` and `1790315865030` stay 298.9 and
309.5. The measured P98 extents (36–54 mm) all sit under the 85.9 mm bread
cap, so the cap never bites where a height was measured, and it is written
so that it cannot raise an extent.

**The no-depth carve, at the plane production adopts** (depth withheld from
the sizer only; no card-only plane replay exists, `two-view-geometry-audit.md`
§4, so the plane is held fixed and only the height bound varies):

| bundle | class | 120 mm cap | class cap (85.9 → 87 mm) | LiDAR reference (Decision 10) | 120 ÷ LiDAR | cap ÷ LiDAR |
|---|---|---|---|---|---|---|
| `1790318627741` | bread_wholemeal | 709.8 | 583.1 | 397.1 | 1.79 | **1.47** |
| `1790315814452` | bread_wholemeal | 690.0 | 610.7 | 390.1 | 1.77 | **1.57** |
| `1790310086654` | bread_wholemeal | 678.9 | 595.4 | 350.3 | 1.94 | **1.70** |
| `1790315734391` | bread_white | 632.8 | 534.7 | 268.0 | 2.36 | **2.00** |
| `1790325380366` | bread_wholemeal | 749.6 | 663.6 | 358.9 | 2.09 | **1.85** |

The cap takes 11–18 % off every bundle and the ratio improves on all five.
The research's pass line — two-view ÷ LiDAR under 1.3 on at least four of
five — is met on **none**: a roll is a third of the bread class's P90, and
the cap cannot know that.

**The Decision 8 synthetic control**, a 120 x 70 x 40 mm box with exact
silhouettes on `1790310086654`'s intrinsics and plane (voxelised truth
337.0 cm³), the oblique orbited about the grid's x axis through the food
point at each tilt, plus the bundle's own stored transform (23.9°):

| oblique tilt | 120 mm cap | class cap (87 mm) | truth cap (42 mm) |
|---|---|---|---|
| stored (23.9°) | 806.9 | 675.8 | 379.1 |
| 22.2° | 735.0 | 643.4 | 372.6 |
| 26° | 705.2 | 632.0 | 373.3 |
| 40° | 596.3 | 584.6 | 374.5 |
| 60° | 481.4 | 481.4 | 375.4 |

The truth-cap column reproduces Decision 8's ~372–376. The class cap is
worth 12–16 % at the aim-guide tilts and nothing at 60°, where the hull
closes below the cap on its own, which is the same geometry Decision 8
described. The 120 mm column sits below Decision 8's own figures (833 → 552);
that sweep's orbit axis and baseline were not recorded, so the columns are
not like for like, but the ordering and the truth column agree.

Why P90 and not a tighter statistic: a cap must not clip real food, and P90
of per-item maximum height is the loosest choice that is still
class-specific. On the one-form classes it is within 5 mm of every item
(egg 44, apple 81, banana 46 mm) and the cap acts as a near-measurement; on
the mixed-form classes it is the tallest common form, the honest ceiling
when the form is unknown. Why the global P90 for thin classes: 72 mm is
below the shipped constant for every unmapped class and above every mesh
outside the tall tail.

### Alternatives Considered

- **A P50 cap (class median, 31.6 mm on bread)**: Would land the audited
  rolls near the LiDAR figure. Rejected because it clips three of the five
  real rolls (LiDAR maxima 47.6, 50.7 and 37.1 mm): the category's median
  is a slightly flatter roll than the ones photographed, and a cap that
  removes measured food is the failure mode Decision 9 declined.
- **No cap; wait for a height model**: Keeps the no-depth number purely
  geometric. Rejected because the research found no credible on-device
  height source at 2–5 cm — absolute monocular depth error at tabletop
  range equals the food height — and the 120 mm constant is itself a prior,
  just a worse one.
- **Form-level priors through the swap list (slice / roll / loaf, handful /
  basket)**: The real lever; a roll-level cap would put every bundle above
  within the hull bias. Deferred, not rejected: the palette does not carry
  form, so this is a review-loop question — the swap-and-record loop can
  seed a form and the cap follows the label — and it needs its own decision.
- **Cap at the class P98 or maximum**: Looser still, safer against
  clipping. Rejected because on bread it is the loaf (104 mm), above the
  measured constant's useful range and worth under 5 % on the sweep.

### Consequences

**Positive:**
- The no-depth two-view carve has a bound that follows the class: 87 mm on
  bread instead of 120, 49 mm on egg, 77 mm on an unmapped class.
- The LiDAR path is byte-identical on all seven corpus bundles, by
  construction: the cap can only lower a measured extent.
- What bounded the carve is on every row and in the log, so a capped row is
  distinguishable from a measured one.
- `carve-audit --no-depth` and the tilt/cap sweep re-run the accounting on
  any bundle.

**Negative:**
- It bounds, it does not fix. The non-LiDAR path still reads 1.5–2x the
  LiDAR figure on a roll, and any tall-form class (bread, chips, broccoli)
  keeps that over-read until a form-level prior exists.
- An item taller than its class P90 is clipped: a loaf photographed without
  LiDAR reads as an 87 mm object. The cap is a ceiling on what the carve
  can see, and `capSource` is the only witness.
- A regenerated `height_priors.json` changes every no-depth row's meaning;
  the copy under `Volume/Resources` must stay byte-identical to the tool's
  output, and `ClassHeightPriorsTests` pins the numbers on purpose.
- The rule is measured against the LiDAR plane; the card-only plane a
  non-LiDAR phone would fit is still unmeasured (§4), and today that path
  refuses before the carve (§6), so the cap is exercised offline and by
  tests, not yet on a phone.

### Impact

`MedataCore/Sources/Volume/ClassHeightPriors.swift` (new),
`MedataCore/Sources/Volume/Resources/height_priors.json` (new, bundled),
`Package.swift` (Volume resource), `MedataCore/Sources/Volume/VoxelGridSizer.swift`
(`Inputs.classCap`, `verticalBound`), `MedataCore/Sources/Pipeline/Pipeline.swift`
(two-view branch), `MedataCore/Sources/Pipeline/PipelineDiagnostics.swift`
(`VoxelGridMeasurements.classCapMm`, `capSource`), `HarnessCore/FixtureRunner.swift`
(`runVoxelCarve`), `HarnessCore/CarveResidualAudit.swift` (`NoDepthRow`,
tilt and cap sweeps, `orbitTransform`), `HarnessCLI` (`--no-depth`,
`--tilts`, `--caps`), `MedataCore/Tests/VolumeTests/ClassHeightPriorsTests.swift`,
`MedataCore/Tests/PipelineTests/EstimationAttemptRecordTests.swift`,
`docs/agent-notes/two-view-geometry-audit.md` §8.

---

## Decision 12: A footprint-scaled class height cap where the class's form scales with its size

**Date**: 2026-09-27

**Status**: proposed (the LiDAR path is unchanged; the pass line — non-LiDAR
÷ LiDAR under 1.3 on at least four of five bundles — is met on two of five)

### Context

Decision 11 bounded the no-depth two-view carve with a per-class absolute
cap, class max-height P90 plus the margin, and measured it: 11–18 % off every
audit bundle, none under the 1.3 pass line, because the bread class's P90 is
a loaf (80.9 mm) and the five audited rolls are 30–51 mm tall. The cap could
not know which form was on the plate.

`tools/metafood3d/height_priors_items.csv` carries each mesh's seated
footprint beside its height, and for several classes the ratio
`r = max_height / sqrt(footprint)` is far tighter than the height. On the
nine `Yeast_bread` meshes the height's P90/P50 spread is 2.56 and the ratio's
1.20: rolls sit at r 0.39–0.49, loaves at 0.44–0.61, and only the slices fall
out at 0.16–0.19. A roll and a loaf are one shape at two sizes. Broccoli
(2.19 against 1.11), carrot (1.65 against 1.36), tomato (1.48 against 1.25)
and pork (1.16 against 1.14) tell the same story; chips (1.79 against 2.30)
and rice (1.47 against 1.66) the opposite — a handful and a basket, a spread
and a domed bowl, differ in height at one footprint. The non-LiDAR path
measures a footprint for free: the nadir silhouette back-projected onto the
support plane, the same geometry the grid sizer already uses for its
horizontal extent.

### Decision

`height_priors.json` moves to schema `height_priors.v2`, every v1 field
kept, with `ratio_p50`, `ratio_p90` and a `cap_mode` per class: `ratio`
when the ratio's P90/P50 spread is smaller than the height's on at least
four meshes, else `height`. Six classes take ratio mode — bread_white,
bread_wholemeal, broccoli, carrot, tomato, pork — the rest stay in height
mode.

`ClassHeightPriors.cap(forPaletteIndex:footprintMm2:)`: in ratio mode
`cap = r_P90 × sqrt(footprint mm²) + margin`, clamped to
`[10 mm, the Decision 11 cap]`, source `classRatio`; in height mode the
Decision 11 cap, unchanged; the global fallback as before. The footprint is
`VoxelGridSizer.silhouetteFootprintMm2`, the nadir carvable silhouette's area
on the support plane (per-pixel back-projection; on a single-object view
after `ObjectReconciler` that is the object). The carve takes the ratio cap
**only where no height is measured** (`carveCap`): with nadir depth the
extent is `min(measured + margin, Decision 11 cap)` exactly as before, so a
LiDAR grid is never sized by a prior about form. `Pipeline`, `FixtureRunner`
and `carve-audit` size by the one function; the row's `voxelGrid` gains
`footprintMm2`, `capSource` gains `classRatio`, and `event=grid.height`
prints `footprint_mm2`.

The Decision 8 flag stands: a no-depth two-view row is still
`unbounded_carve_height` and not offered for dosing.

### Rationale

Measured offline with `HarnessCLI carve-audit --no-depth --tilts
22.2,26,40,60 --caps 120,85.9,59.5,51.8,42` and `volumes`, on the five §7
bundles and the two single-view controls, before and after.

**The LiDAR path is unchanged.** The `volumes` replay of all seven bundles is
byte-identical before and after: 397.1, 390.1, 350.3, 268.0, 358.9 cm³ on the
two-view bundles and 298.9, 309.5 on the single-view controls. By
construction — the ratio cap is not consulted when a height is measured —
and by measurement.

**The no-depth carve, at the plane production adopts** (depth withheld from
the sizer only, as Decision 11 measured it). The footprint is the
silhouette's on that plane; the extent is the cap rounded up to whole 3 mm
voxels; the LiDAR maximum is the food's measured top:

| bundle | class | footprint mm² | LiDAR max mm | ratio cap mm (extent) | 120 mm | class cap (87) | ratio cap | LiDAR ref | 120 ÷ | class ÷ | ratio ÷ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `1790318627741` | bread_wholemeal | 10 267 | 47.6 | 56.8 (57) | 709.8 | 583.1 | **416.5** | 397.1 | 1.79 | 1.47 | **1.05** |
| `1790315814452` | bread_wholemeal | 12 051 | 50.7 | 61.1 (63) | 690.0 | 610.7 | **502.3** | 390.1 | 1.77 | 1.57 | **1.29** |
| `1790310086654` | bread_wholemeal | 12 234 | 37.1 | 61.5 (63) | 678.9 | 595.4 | **485.2** | 350.3 | 1.94 | 1.70 | 1.39 |
| `1790315734391` | bread_white | 10 635 | 33.8 | 57.7 (60) | 632.8 | 534.7 | **412.7** | 268.0 | 2.36 | 2.00 | 1.54 |
| `1790325380366` | bread_wholemeal | 12 417 | 30.5 | 61.9 (63) | 749.6 | 663.6 | **550.2** | 358.9 | 2.09 | 1.85 | 1.53 |

The ratio cap takes a further 18–29 % off Decision 11's figure on every
bundle and never clips: it sits 6–31 mm above each roll's measured top. Two
bundles pass the 1.3 line, three do not. The reason is in the two columns
side by side: the two rolls that pass are as tall as the prior expects
(r = 0.47, 0.46 — the MetaFood3D rolls' band), the three that fail are
flatter rolls of the same footprint (r = 0.33, 0.33, 0.27), and a P90 cap
must leave room for the tall ones. The cap follows the object's size; it
cannot see whether this roll is a flat one.

**The Decision 8 synthetic control** on `1790310086654` (120 x 70 x 40 mm
box, exact silhouettes, voxelised truth 337.0 cm³). The box's true footprint
is 8 400 mm², cap 0.511 x 91.7 + 5 = 51.8 mm; the footprint the silhouette
rule measures is 10 720 mm² (a 40 mm top face 390 mm from the camera
projects 24 % larger than its base), cap ≈ 58 mm, the 59.5 column:

| oblique tilt | 120 mm cap | class cap (87) | ratio cap, silhouette footprint (59.5) | ratio cap, true footprint (51.8) | truth cap (42) |
|---|---|---|---|---|---|
| stored (23.9°) | 806.9 | 675.8 | 516.6 | 474.1 | 379.1 |
| 22.2° | 735.0 | 643.4 | 504.4 | 464.2 | 372.6 |
| 26° | 705.2 | 632.0 | 502.3 | 463.3 | 373.3 |
| 40° | 596.3 | 584.6 | 495.5 | 461.2 | 374.5 |
| 60° | 481.4 | 481.4 | 466.2 | 445.9 | 375.4 |

The 120, 87 and 42 columns reproduce Decision 11's. The ratio cap is worth
20–24 % over the class cap at the aim-guide tilts and, unlike the class cap,
still bites at 60° (466 against 481), because it sits below where the hull
closes on its own. The 24 % footprint inflation is a real, bounded bias in
the rule: a food of height h at distance d reads (d ÷ (d − h))² too large in
area, ~12 % on the cap's sqrt term at these ranges. It is on the safe side
(a looser cap) and it is the same on every no-depth row.

**The LiDAR regression table** (`volumes`, all seven bundles):

| bundle | path | before | after |
|---|---|---|---|
| `1790318627741` | two-view | 397.1 | 397.1 |
| `1790315814452` | two-view | 390.1 | 390.1 |
| `1790310086654` | two-view | 350.3 | 350.3 |
| `1790315734391` | two-view | 268.0 | 268.0 |
| `1790325380366` | two-view | 358.9 | 358.9 |
| `1790315900185` | single-view | 298.9 | 298.9 |
| `1790315865030` | single-view | 309.5 | 309.5 |

Why the ratio yields to a measurement rather than capping it too: on
`1790315814452` the ratio cap (61.1) sits above the measured extent (45.0)
and would not bite, but on a taller roll of the same footprint it would, and
a cap that replaces a LiDAR reading of the food's own top with a table
lookup is the failure Decision 8 named. The ratio is a statement about form
for a phone that cannot measure; the phone that can measure keeps
Decision 11's ceiling.

### Alternatives Considered

- **The absolute class cap only (Decision 11)**: The shipped state. Rejected
  as the end point because it measured 1.47–2.00x on rolls and cannot
  improve: the class P90 is a loaf whatever sits on the plate, and the
  footprint that distinguishes a roll from a loaf was already in the
  capture, unused.
- **Per-form priors through the swap list (slice / roll / loaf)**: Still the
  lever for the case the ratio cannot reach. The ratio collapses roll and
  loaf because they are one shape; it does NOT cover slices, whose ratio is a
  third of a roll's, so a slice on the non-LiDAR path is capped as a roll of
  its footprint. Only a form label from the review loop can seed a slice-
  level cap, and the palette does not carry form. Deferred, not rejected; it
  composes with this decision (a form label would pick the ratio band).
- **A footprint-to-volume regression, skipping the carve**: Fit V against
  footprint per class from the meshes and report that. Rejected: it is a
  model of the prior, not a measurement — the oblique silhouette and the
  plane would contribute nothing, and the row would claim a carve it did not
  do. The cap keeps the carve as the measurement and the prior as its bound.
- **Cap at the ratio P50 (0.427)**: Would land 48–52 mm on these bundles and
  bring more of them under 1.3. Rejected for the reason Decision 11 rejected
  the height P50: it clips the two rolls that are as tall as the prior
  (r = 0.46–0.47), and a cap that removes measured food is the wrong
  direction for a dosing number.

### Consequences

**Positive:**
- The no-depth bread carve drops from 1.47–2.00x to 1.05–1.54x the LiDAR
  figure, 18–29 % under Decision 11 on every bundle, with no bundle clipped.
- The bound now depends on the object photographed, not only its class; a
  small roll and a loaf get different caps from the same label.
- The LiDAR path is byte-identical on all seven corpus bundles, by
  construction and by replay.
- Every no-depth row records the footprint and `classRatio`, so the bound
  can be re-derived from the row.

**Negative:**
- The pass line is not met: three of five rolls still read 1.39–1.54x,
  because they are flatter than the class's P90 ratio. The status stays
  proposed; the residual on these needs a form label (swap list) or a
  measurement, not a tighter statistic.
- A slice on the non-LiDAR path is capped as a roll of its footprint, about
  2.5x too tall (r 0.51 against 0.16–0.19); the ratio rule does not know a
  slice from a roll and nothing in the capture tells it.
- Classes in height mode (rice, chips, chicken, egg, apple, banana, beef,
  mashed potato, and every unmapped class on the global cap) gain nothing:
  their forms do not scale with their footprint, and they keep Decision 11's
  over-read.
- The silhouette footprint is inflated by the food's own height (≈ 24 % in
  area at 40 mm and 390 mm), which loosens the cap by ~12 % of its scaled
  term; safe, but a bias a future rule could remove by iterating once.
- A multi-food plate (reconciliation not applied) uses the whole carvable
  silhouette's footprint for every class present, a looser cap than the
  dominant object's own; safe, unmeasured.
- The card-only plane a non-LiDAR phone would fit is still unmeasured (§4)
  and that path refuses before the carve today (§6): the rule is exercised
  offline and by tests, not on a phone.
- Regenerating `height_priors.json` from the item CSV rounds three v1 fields
  the app does not read by 0.1 (`HEIGHT_PRIORS.md`); a full mesh scan
  restores them.

### Impact

`tools/metafood3d/height_priors.py` (`ratio_p50`, `ratio_p90`, `cap_mode`,
`--from-items-csv`, schema v2), `tools/metafood3d/height_priors.json` and its
byte-identical copy `MedataCore/Sources/Volume/Resources/height_priors.json`,
`tools/metafood3d/HEIGHT_PRIORS.md`, `MedataCore/Sources/Volume/ClassHeightPriors.swift`
(`cap(forPaletteIndex:footprintMm2:)`, `carveCap`, `CapSource.classRatio`),
`MedataCore/Sources/Volume/VoxelGridSizer.swift` (`silhouetteFootprintMm2`,
`VerticalBoundSource.classRatio`), `MedataCore/Sources/Pipeline/Pipeline.swift`
(two-view branch), `MedataCore/Sources/Pipeline/PipelineDiagnostics.swift`
(`VoxelGridMeasurements.footprintMm2`), `HarnessCore/FixtureRunner.swift`,
`HarnessCore/CarveResidualAudit.swift` (`NoDepthRow` ratio columns, footprint
through the production rule), `HarnessCLI` (`noDepthRatio` line),
`MedataCore/Tests/VolumeTests/ClassHeightPriorsTests.swift`,
`docs/agent-notes/two-view-geometry-audit.md` §8.

### Follow-up measurement (2026-09-27, after merge)

The P50 ratio (0.427 for both bread classes) would set caps of 48–53 mm on the five rolls, above every LiDAR maximum (47.6 / 50.7 / 37.1 / 33.8 / 30.5), so it clips nothing here. Extrapolating the audit's near-linear extent-to-volume relation (about 6.5 cm³ per mm of extent on these hulls), a P50 cap lands the rolls near 0.95 / 1.2 / 1.25 / 1.4 / 1.35 times LiDAR against the P90 cap's 1.05 / 1.29 / 1.39 / 1.54 / 1.53. Lower on average, still over 1.3 on the two flattest rolls: a flat roll and a tall roll share a footprint, so no footprint prior separates them. That residual is the non-LiDAR path's structural limit until either the oblique-tilt experiment (Decision 8) closes the hull or the review loop carries a form choice. Measuring the P50 variant exactly needs a percentile flag on `carve-audit`; not built, since the choice between P50 and P90 is a bias trade the weighed sitting should settle.

### Follow-up against weighed truth, and a reachability caveat (2026-09-29)

A 2026-09-29 field session weighed the bread roll at **104 g**, which at bread_wholemeal's
0.4 g/cm³ is **260 cm³** — the first truth any of these numbers can be scored against. Taking the
five audit bundles as the same roll (the reading the field pull itself uses when it calls the
historical two-view rows of 851/920/930 cm³ "3.3–3.6× truth"), Decision 10's refit leaves the
LiDAR two-view carve at 268–397 cm³, which is **+3 % to +53 % of truth**: the refit removed a
large error and did not remove the bias. Single-view over the same roll, 267–302 cm³, is +3 % to
+16 %. So the remaining two-view excess is real and larger than the hull bias alone predicts.

**Decisions 11 and 12 are currently unreachable on device.** The same session found that without
depth the plane fit **refuses before collecting any candidate**: `SupportPlaneFitter` returns
`.noLowerSilhouetteEdges` unconditionally on `nadir.depth == nil`, so the non-LiDAR estimate dies
at `noSupportPlaneWithoutDepth` before a grid is ever sized.

*(This paragraph first read "returns zero candidates (`… candidates=0`)". It does not: that
figure was a default-constructed `SupportPlaneFitStats` on a branch that never searched, and the
refusal now logs `stats=unfitted` with no counters — see the correction earlier in this entry.
The conclusion is unchanged; only the mechanism is. Two sessions reached for the same phantom
number within a day of each other, which is why the log stopped printing it.)*

Both height caps remain correct as measured, but note where they were measured: Decision 11's
figures come from LiDAR bundles with depth withheld from the sizer only, and `carve-audit
--no-depth` replays on `FixtureRunner`'s nominal −300 mm plane, which production refuses. So the
offline result is not evidence of device behaviour. Neither can bite in the field until the plane
fit produces a candidate — the card-derived plane is the obvious fallback. Neither decision
changes; what changes is that they are not the head of the chain.


---
