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

`CardDetector.detect` returns every ranked rectangle (Vision, up to 8) and `CardPoseSolver.pick` takes the first that reprojects as an ID-1 card within `maxResidualPx` (6 px); with none, there is no card. `MetricScaleResolver` drops a card scale that disagrees with the LiDAR scale by more than `maxCardLidarDisagreement` (0.15, symmetric relative) and returns the LiDAR-only result. In `Pipeline`, a card the resolver kept has its quadrilateral cleared to background in both the nadir probability tensor and label map (`SegmentationResult.excluding(quad:)`) before coverage, growth and volume; the capture bundle keeps the segmenter's raw output. Every detected rectangle is recorded on the outcome row as `card {pnpResidualPx, distanceMm, scaleMmPerPx, lidarDisagreement, accepted, clearedPixels}`. The oblique view is not cleared until Req 1.3 has verified the inter-view transform; the card's projection into the oblique depends on it.

### Rationale

The harness `cards` replay showed Vision's top-ranked rectangle was never the card, even on the two 2026-08-11 bundles that had one: it picked the bread (residual 85 px, 25 % off LiDAR) and a plate phantom (145 px, 38 %), while the real card was candidate 2 of 3 at 2.7 px and 9 % off LiDAR. The residual separates them by a factor of four or more, so it is the first gate and the only one a phone without LiDAR has. The two defects share a cause: a rectangle is trusted on aspect ratio alone. Cross-checking it against LiDAR costs one comparison the resolver already made, and gating the exclusion on that check means a false rectangle over the plate can never erase food. Clearing the probabilities as well as the labels is required because both estimators take the silhouette from the background probability. The 0.15 bound sits between the real card's 9 % and the false picks' 25–94 %; the 6 px residual bound between 2.7 px and 12 px.

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
