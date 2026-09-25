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

## Decision 7: One tap per view anchors the growth seed; the silhouette it tightens is not where the two-view over-read lives

**Date**: 2026-09-25
**Status**: accepted

### Context

The product owner's original proposal for this spec was that the user identifies the food in both photos, and Req 3 was a stub. The prompt for filling it in was the two-view over-read: with the transform verified (Decision 4), the card cleared from both views (Decision 3) and the views reconciled to one class (Decision 6), the same sesame roll carved at 851, 920, 926.9 and 930 cm³ against 266.9–272.0 cm³ from the single-view LiDAR path minutes apart. Three terms were suspected — an over-wide nadir mask, an oblique only 26° from vertical bounding height near its far edge alone, and the grid's 120 mm `verticalExtentMm`.

The measurement has since landed and settles it. A synthetic control on `1790318627741` (exact silhouettes, real intrinsics, real baseline, voxelised truth 337 cm³ for a 120 × 70 × 40 mm box) returns 800.7 cm³ at 26° tilt, 832.8 at the real 22.2° inter-view rotation, 712.0 at 40° and 552.0 at 60°. Below the object's true height the carve is accurate — capping the grid at 40 mm gives ~375 cm³ against 337 — and everything above is un-carved hull, because two cones close only once h·tan(θ) exceeds the object's extent along the tilt direction: 139 mm / tan 22.2° ≈ 340 mm, far beyond the grid. On the real bundle the cumulative volume by cap is 40 mm → 379, 62 → 587, 86 → 756, 120 → 927 cm³, and the top layer at 118.5 mm still keeps 42 % of the base layer. Attribution: **grid vertical cap ~92 %, over-wide nadir mask ~7 % (92.6 cm² measured against ~84 cm² real), oblique mask 0–10 cm³.** The shutter's aim band is 25° ± 15° (`CaptureFlowModel.obliqueTiltOk`), so no tilt a user is allowed to take closes the hull.

Separately, the single-view path leaks in a way geometry does not fix: `1790315900185` grew 89 k → 242 k px and `1790315865030` 122 k → 236 k px, with the owner's note "the highlighted regions show the plate as food items".

### Decision

The identification is **one tap per view on the frozen frame**, in both modes — single-view after the shutter, Double between the shots for the nadir and after the oblique shutter for the oblique — and nothing else: no drag, box, pinch, lasso, brush or boundary handle. The tap is a point in sensor-buffer coordinates, and it does two things: every carvable connected component that does not contain it is cleared from that view's silhouette, and the region growth's seed set is restricted to the component that survives.

Its claimed benefit is the **second** mechanism only. The tap is a growth seed anchor, and the single-view leak is what it is built to cut; the silhouette it tightens is worth ~7 % of the two-view over-read and is not a reason to build anything. The two-view over-read is a height problem and is bounded by capping the grid at the height the nadir LiDAR already measures — a separate change this decision does not claim. The oblique seed is still projected from the nadir seed through the verified transform so the common case costs one tap, a seeded view still bypasses Decision 6's connectivity gate, skipping still never refuses the estimate, and disagreeing seeds still refuse the carve rather than carve a mismatch. Both seeds, their sources and the resulting pixel counts go on the outcome row and into the fixture, so the harness replays a tap from the record and can be given one on the command line.

### Rationale

The growth leak has a single root cause: the seed set is every pixel the segmenter called food-like, which on these captures includes speckles out on the plate, so the fill starts on the plate and the seed-height band is anchored to plate height. One user point replaces that seed set with a point certainly on the food, which makes the already-shipped floor and band rules (depth-grown-food-region Decisions 3–4) bite for the first time. That is a benefit measurable offline, on two bundles that already exist, with no UI and no device sitting — which is why Req 3.15's gate is now those two single-view bundles and not the two-view volumes.

A point is also the only input that survives replay cleanly. Storing a mask would freeze a silhouette against a growth rule that is still moving; storing two integers lets any future build re-derive the region from the same user intent.

The interaction is unchanged from the version written before the measurement because the measurement falsified the claim, not the gesture: a tap is still the cheapest way to say "the food is here", it is still the only lever a phone without LiDAR has, and the component rule still removes a card or a neighbouring item for free. What changed is the honesty of what it is sold as. Making it optional keeps Decision 6's rejection of "ask the user before reconciling" intact.

### Alternatives Considered

- **Tap to select one connected component, with no re-seeding**: The smallest possible change, and enough to drop the card or a second food - Rejected as sufficient: the measurement puts the whole silhouette term at ~7 % of the two-view excess, and on the single-view leak the plate blob is often contiguous with the roll, so selection alone changes neither number. It is kept as half of the chosen interaction.
- **Drag a box round the food**: Bounds extent directly, including a contiguous excess - Rejected: it imposes a rectangle on a 12 × 7 × 4 cm roll, asks the user to guess a boundary at arm's length instead of pointing at a thing they can see, and buys a term now measured at ~7 %.
- **Pinch to size a circular region**: One gesture, gives a radius - Rejected: a two-finger gesture on a phone held over a plate, a disc prior on an oblong food, and the same boundary-guessing for the same small term.
- **Freehand paint or lasso**: The most expressive silhouette a user can give - Rejected on measurement twice over: meal-review Decision 4 recorded ~79 s per hand-painted mask and ~4 mm touch error, and a perfect silhouette is now known to leave 800.7 cm³ of the 927 standing.
- **Confirm or retake, with no region input at all**: Zero new surface, honest about what a user can judge - Rejected: a confirmation with no lever cannot change a number, and it would leave the single-view growth leak with no lever either.
- **Ask the user to indicate the food's height, or to tilt further**: The term that actually dominates - Rejected: 60° still returns 552 cm³ against 337, the shutter's aim band tops out at 40°, and a height typed by a user is a guess where the nadir LiDAR already holds a measurement. The grid bound belongs in geometry, not in the interaction.
- **Ask only on the view where the masks disagree**: Targets the prompt at an observed failure - Rejected as the trigger: label disagreement is what Decision 6 already absorbs, and the growth leak appears on captures where nothing disagrees.
- **Require the tap before any estimate**: Guarantees a good seed every time - Rejected: it contradicts Decision 6, which reconciles a single roll with no input, and taxes the common case to fix the uncommon one.

### Consequences

**Positive:**
- The single-view growth leak gets a lever that no geometry change has given it: a seed certainly on the food, anchoring the height band to food height rather than plate height.
- The benefit is testable with no UI at all — two existing fixtures, a hand-placed seed, a pixel count — so the premise is falsifiable before a line of capture code is written (Req 3.15).
- The same gesture still clears a card or a neighbouring blob from either view, and still supplies the class when the segmenter scatters labels.
- The estimate never depends on the user, so Decision 6's unaided path stands.
- The two-view over-read now has a named owner (the grid height bound) rather than being absorbed into a UI change that would not have fixed it.

**Negative:**
- This decision's original claim — that a tighter silhouette would halve the two-view over-read — was wrong by roughly an order of magnitude, and the interaction survives only because its second mechanism does different work. Any future "the user can fix this by pointing at it" argument should be measured against a synthetic control first.
- **On a phone without LiDAR the tap rescues nothing.** With no depth there is no height bound at any tilt the shutter allows, so the hull stays open above the food, and the tap moves only the ~7 % the silhouette owns. The retained non-LiDAR path needs a card-plane or two-view-derived height bound of its own before it can be called trustworthy (Req 3.19).
- The preview outline is grown at preview resolution while the estimate re-grows at full resolution, so a user can accept an outline slightly different from the one integrated.
- One seed per view cannot describe two foods; a multi-food plate still waits on instance matching (Req 2.3).
- A seed on a highlight, a shadow or a sesame seed can under-grow where there is no depth to stop the fill; the only remedy offered is another tap.
- A wrong tap is a silent input to the geometry — nothing on screen says the number moved because of where the finger landed, and only the outcome row records it.

### Impact

`CaptureFlowModel` / `CapturedFramesView` (the per-view tap step and the frozen-frame outline, now on both paths), `FoodRegionGrowth` (seed-set restriction — the load-bearing change), `ObjectReconciler` (connectivity-gate bypass, seeded class order), `SegmentationResult.excluding` (component clearing, reused from the card path), `PipelineBridges` (projecting the nadir seed into the oblique), `PipelineDiagnostics` (the `userRegion` block and the hull-extent audit field), `PbMealFixture` (two seed fields), `FixtureRunner` / `HarnessCLI volumes` (seed replay and command-line seeds), `meal_artefacts` (per-view `user_confirmed` silhouettes). Not in scope and not fixed here: `VoxelGridSizer`'s vertical extent, which owns ~92 % of the two-view over-read.

---
