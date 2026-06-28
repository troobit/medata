# Decision Log: LiDAR Plane Fit Degenerate on Clean Capture

## Decision 1: Replace the all-ones rough mask with a centred-rectangle approximation

**Date**: 2026-06-03
**Status**: accepted

### Context

`Pipeline.fitSupportPlane` (`MedataCore/Sources/Pipeline/Pipeline.swift:372-391`) constructs a `BinaryMask` of all‑ones over the full image dimensions and passes it as `foodRegionMask` to `LiDARPlaneFitter.fit(_:)`. `LiDARPlaneFitter.collectCandidatePoints` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:85-129`) interprets the mask as a *food* region and scans the band *below* its bounding box for *non‑food* pixels (the table surrounding the plate). With an all‑ones mask the bounding box covers the whole image, the scan band collapses to the bottom row, and every pixel in that row is "food" → zero candidate points → `SupportPlaneError.noLidarPoints` → caught at `Pipeline.swift:389-391` as `EstimationFailure.lidarFitDegenerate` → the "Unable to detect a flat surface" modal.

On iPhone 13 Pro Max iOS 26.5, on‑device verification (2026‑06‑03 device log at `nextup.md`) confirms this fires on every shutter tap even with live LiDAR coverage at 87.5 % and both capture stages succeeding at 1920×1440. The wired Phase 1 `Pipeline.makeForDevice` factory (Decision 42 of the device‑MVP work, landed 2026‑05‑30) makes this a release‑path failure in Debug builds; pre‑factory builds wired `PendingPipeline` which short‑circuited the LiDAR fit entirely.

### Decision

Construct a centred‑rectangle `BinaryMask` for the `roughMask` argument in `Pipeline.fitSupportPlane`: `1` pixels form an axis‑aligned rectangle covering the middle 70 % × 70 % of the image, `0` pixels form the surrounding border. Implement the construction as a private helper `makeCentreRectangleMask(width:height:fillFraction:)` so the constant is unit‑testable and adjustable in one place. The fill fraction is parameterised as a named constant so the value is discoverable; the chosen default is 0.7. `LiDARPlaneFitter` is unchanged — its contract is preserved.

### Rationale

The fitter's design intent is to find the table around the plate by scanning the lower-edge band *below* the food region. With no real food segmentation available pre‑shutter under the Phase 1 dev‑stub, the closest correct approximation is the *spatial* prior the capture flow already enforces: the user is gated into a centred, near‑0° tilt, ~30‑40 cm framing at the nadir stage (`App/CaptureFlowModel.swift` gating, `App/LiveSampleObserver.swift:65-67`'s `cropFraction: Float = 0.2` for the live distance‑median crop), so the plate is reliably in the centre and the table border is reliably below it. A centred rectangle calibrated to that envelope puts the fitter's lower-edge scan band precisely over the surrounding table — the region the fitter was designed to consume.

Geometric justification for the chosen default `fillFraction = 0.7`: iPhone 13 Pro Max main wide camera has ~67° horizontal FOV; at 30 cm the horizontal field is ~40 cm and a ~25 cm plate occupies ~63 % of image width and height. A 70 % rectangle contains the plate with a small margin so the lower-edge band y ∈ [0.85, 1.0] sits on table pixels, not plate rim. A smaller fraction (e.g. 0.5) would leave the band overlapping the plate; a larger fraction (e.g. 0.9) would leave the band so thin (~5 % of image height) that it could fall below the sensor's frame on close framings. 0.7 is the sweet spot for the documented gating envelope; the constant can be tuned in one place if on-device verification suggests otherwise.

This is surgical (one call site, ~25 LOC), preserves the LiDAR-fit-takes-precedence design intent, and leaves a clean removal path: once the follow-on full spec wires a real food-region mask (post-segmentation), the helper is deleted and the call site passes the real mask.

### Alternatives Considered

- **Skip LiDAR plane fit on the `.twoViewSfS` path**: Gate the LiDAR branch in `fitSupportPlane` on `capturePath == .singleViewLidar` and fall through to the card-only branch on the SfS path — Rejected because (a) the wired `NullCardDetector` returns nil corners, so the card-only branch immediately throws `noScaleAvailable` (a different refusal, same user impact); (b) it inverts the documented design intent ("LiDAR plane fit takes precedence when depth is available", `Pipeline.swift:371`); (c) it does not fix the failure on the `.singleViewLidar` path, where the same wrong mask would still produce zero candidate points once the path-decider is corrected.
- **Depth-based heuristic food region (closest connected cluster)**: Use the LiDAR depth itself to identify the plate (the cluster closest to the camera within a tilt-and-distance envelope) and synthesise a mask from that — Rejected for Phase 1 because it adds a new heuristic with its own failure modes (e.g. a user's hand or a tall glass closer to the camera than the plate becomes the "food region"), and because the surgical centre-rectangle achieves the same Phase 1 goal at a fraction of the implementation surface. Worth revisiting in the follow-on full spec only if the real segmentation route is itself blocked.
- **Relax `LiDARPlaneFitter`'s `minPoints` / `stabilityRatioMin` guards**: Lower the thresholds so the fit succeeds with fewer points — Rejected because the proximate cause is *zero* candidate points, not too few; relaxing guards would let a near-degenerate fit through without addressing the wrong-mask root cause, with a real risk of silently-wrong plane normals downstream.
- **Defer the LiDAR plane fit until after segmentation**: Move `fitSupportPlane` from Stage D (pre-segmentation) to a step after Stage F so the real food mask is available — Rejected because it reorders the pipeline stages (`Pipeline.swift:111-156` Stage D feeds Stage E `MetricScaleResolver` via `lidarMmPerPx`), invalidating the existing scale-resolution flow, with effects far beyond a Phase 1 bugfix. Belongs in the follow-on full spec, not here.

### Consequences

**Positive:**

- The "Unable to detect a flat surface" modal stops firing on the documented capture envelope on iPhone 13 Pro Max iOS 26.5.
- The fix is localised: one call site, one helper, one unit test file; `LiDARPlaneFitter`'s public contract is untouched.
- Clean removal path: when the follow-on spec wires a real food-region mask, the helper is deleted and `Pipeline.fitSupportPlane` passes the real mask in.
- Adds DEBUG-only candidate-point-count logging so future regressions surface a numeric trace, not an opaque modal.

**Negative:**

- The centre-rectangle is a *spatial* approximation, not a semantic one. A user who frames off-centre or shoots at a steep tilt where the table is not below the rectangle will still see the modal. Aligned with the capture flow's existing gating envelope, which already enforces centred near-0° framing at the nadir stage, but it is a known limitation of Phase 1 that the follow-on spec must address.
- The chosen `fillFraction` (0.5) is a tuning knob that may need adjustment after on-device verification. Mitigated by making it a named constant adjustable in one place and asserting the chosen value in the unit test.

### Impact

`MedataCore/Sources/Pipeline/Pipeline.swift` (replace `roughMask` construction with the helper call; add the helper). `MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift` (new). DEBUG-only logging addition near `Pipeline.fitSupportPlane` call sites — same `os.Logger` subsystem `ie.medata.app`, category `Shutter` as the existing `estimate.start` / `estimate.end` events. No call-site changes anywhere else; no public-API changes.

---

## Decision 2: Scan four edge bands around the food bbox in `collectCandidatePoints`

**Date**: 2026-06-16
**Status**: accepted

### Context

The 2026-06-03 fix (Decision 1) shipped a centre-rectangle `roughMask` at the `Pipeline.fitSupportPlane` call site. The `specs/estimation/pipeline-real-device-correctness/` follow-on then retired that helper and wired a real pre-shutter `BinaryMask` through `CaptureResult.preShutterFoodMask` from `PreShutterSegmenter.latest`. On-device verification 2026-06-16 (PhoneMax, Double mode, build `288c5a7`) showed the real mask reaching `Pipeline.estimate` via `source=pre_shutter` (cadence + lost-age fixes holding from `specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/`) but `estimate.end success=false failure=lidarFitDegenerate`. Decision 1's regression sentinel did not cover this geometry: the real mask is a centred shape (Phase 1 dev-stub ellipse at α=0.618 in 513×513 letterbox → cropped to top-left 513×385 → bilinearly resized to 1920×1440 → bbox y ∈ [≈367, ≈1437] in a 1440-tall frame) whose bbox extends to within ~3 rows of the image's bottom edge. `LiDARPlaneFitter.collectCandidatePoints` only scanned the band BELOW the bbox; that window collapses to 2-3 rows, producing either zero candidates (`noLidarPoints`) or a near-collinear 3-D set (singular covariance at `refine` → `lidarFitDegenerate`). The centre-rectangle had been hiding this by guaranteeing a wide below-band; the production segmenter does not.

### Decision

Modify `LiDARPlaneFitter.collectCandidatePoints` to scan FOUR edge bands around the food bbox — bottom, top, left, and right — each as thick as the bbox dimension perpendicular to it (bottom/top use `bbox.heightPx`; left/right use a new `bbox.widthPx` accessor), clipped to image bounds. Each band is filtered by the existing `mask.isFood` check (food pixels skipped), depth-confidence threshold, and `zMm > 0` validity, before back-projection. `LiDARPlaneFitter.Inputs`, the `LiDARSupportPlaneFitter` protocol, and `Pipeline.fitSupportPlane` are all unchanged.

### Rationale

The fitter's design intent — find table pixels around the plate by scanning bands of non-food image area — is preserved. The original single-band-below assumption fitted a camera-strictly-above-plate framing in which the table is reliably visible below the food bbox. The MVP capture envelope (`App/CaptureFlowModel.swift` gating: centred, near-0° tilt, ~30-40 cm distance) puts the plate in the middle of the frame with the table visible on every side; the four-edge scan applies the same intent to every side the camera can see. Pixels overlapping the bbox boundary (the four corners shared between adjacent bands) are food and the existing `mask.isFood` filter drops them, so no double-counting in the candidate set.

The fix is contained to `LiDARPlaneFitter.swift` (~20 LOC delta in `collectCandidatePoints` plus a one-line `widthPx` accessor on `BBox`). No public surface changes. Determinism is preserved because the RNG seed is hashed from `inputs.depth.depthBytesMm`, not the candidate set; the candidate ordering across the four bands is fixed (below, above, left, right).

### Alternatives Considered

- **Fall back to the centre-rectangle roughMask when the real mask admits < 3 inliers**: Retry the fit with the Decision-1-style synthesised mask when the first attempt fails. — Rejected because (a) it re-runs the entire RANSAC + refine on a different candidate set, doubling worst-case latency; (b) it perpetuates the "all-ones-style placeholder mask" pattern Decision 1's `Prevention` section explicitly warned against; (c) it does not improve robustness for valid masks with bbox-edges-near-image-edge geometries, only "recovers" from them after the first attempt has already burned cycles.
- **Erode the real mask before passing it to `collectCandidatePoints`**: Shrink the food bbox by N pixels (or N % of its dimensions) so the below-band always has guaranteed thickness. — Rejected because (a) the erosion factor is a tuning knob with no principled value (must trade off plate-rim retention against scan-band thickness); (b) it does not help when the bbox legitimately reaches the image edge (a plate flush against the bottom of the frame); (c) it changes the meaning of the mask before it reaches the fitter, complicating downstream debug/log analysis.
- **Detect-and-throw earlier with a more specific error case**: Add a new `SupportPlaneError.lowerBandTooThin` and have `Pipeline.fitSupportPlane` retry with a synthetic mask on that error. — Rejected because it pushes recovery logic up to the Pipeline layer and conflates "mask too aggressive" with "fitter cannot find a plane", which are different concerns. The four-edge scan addresses the geometric issue at its source.
- **Scan the entire image for non-food pixels (no band constraint)**: Drop the band concept and collect every non-food pixel with valid depth. — Rejected because it can pick up background/wall/ceiling pixels far from the table surface, biasing the RANSAC seed and degrading recovered plane accuracy. The band constraint (proximity to the food bbox) is what keeps candidates likely-to-be-table.

### Consequences

**Positive:**

- Real `source=pre_shutter` masks no longer trip `lidarFitDegenerate` purely due to bbox-at-image-edge geometry. Centred framings work on every side.
- The fix is localised: one function, one helper accessor, one new test case. The `LiDARSupportPlaneFitter` protocol and `Pipeline.fitSupportPlane` are untouched.
- All existing SupportPlane + Pipeline tests continue to pass (313/313 with 3 skipped; the all-ones-mask sentinel from Decision 1 still throws `noLidarPoints` as before — the four-band scan over an all-ones mask still finds zero non-food candidates).
- Deterministic seed contract preserved (`testDeterministicSeedProducesIdenticalResults`).

**Negative:**

- The candidate count is now up to ~4× higher per fit (one band → four bands). Worst-case CPU cost grows accordingly; not yet measured on-device but the RANSAC + refine loops are already O(n) in candidate count, so absolute latency at 1920×1440 with ~50K candidates remains well under one frame budget.
- The "below-bbox" intuition documented in §6.2 ("scan the lower-edge band") is now broader; future readers must consult `collectCandidatePoints` itself, not the design doc, for the actual scan shape. The function comment cross-references this bugfix spec.
- The fix exposes a wider candidate set, which can in principle let RANSAC fit a NEAR-table plane biased by far-background depth samples (e.g., wall behind the table). Mitigated by the existing `gravityAngleMaxRad = 15°` filter and the per-side band-thickness clamp at `bbox.{height,width}Px`, which keeps the scan reasonably close to the food bbox in image space.

### Impact

`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` (`collectCandidatePoints` reworked to four-band; `BBox.widthPx` accessor added). `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift` (one new test `testFitsCentredMaskWithBboxAtImageBottomEdge`). No call-site changes anywhere else; no public-API changes; `LiDARSupportPlaneFitter` protocol unchanged.

---

## Decision 3: Move the re-open narrative into front-matter so `tasks.md` parses with rune

**Date**: 2026-06-28
**Status**: accepted

### Context

`tasks.md` failed to parse with the `rune` CLI (`rune list … → "line 38: unexpected content at this indentation level"`), so the task ledger could not be listed or reconciled programmatically (PROCESS §7 requires task state to live in a rune-managed ledger). The cause was a free-prose paragraph placed between the `## Re-open 2026-06-16` phase heading and its first task (task 6). Empirically, rune's parser tolerates no free prose in the task body — not between a phase heading and its first task, not under the H1 title, and not between a task block and the next phase heading; the only block it accepts outside tasks/phase-headings is the YAML front-matter.

### Decision

Relocate the re-open narrative verbatim into a `reopen_2026_06_16` YAML block scalar in the `tasks.md` front-matter and leave the `## Re-open 2026-06-16` phase heading immediately followed by task 6. No task's checked state was altered: tasks 1–7 remain `[x]` (Completed), tasks 8–9 remain `[ ]` (Pending), confirmed via `rune list` after the change.

### Rationale

The narrative is contextual metadata, not an executable task, so front-matter is its natural home and the one location rune accepts. The block scalar preserves the full text (links to `specs/estimation/pipeline-real-device-correctness/`, `decision_log.md` Decision 2, and the build/log evidence), so no information is lost — the same root-cause detail also lives in `smolspec.md` (`## Re-open 2026-06-16`) and Decision 2 above. Keeping the heading lets rune attribute tasks 6–9 to the re-open phase, which it does (the `PHASE` column shows the re-open label).

### Alternatives Considered

- **Inline HTML comment between heading and first task**: Replace the prose with a `<!-- … -->` block. — Rejected: rune treats a standalone comment block as unexpected body content and still fails at the same line.
- **Prose under the H1 title or before the phase heading**: Move the paragraph elsewhere in the body. — Rejected: tested both; rune fails (`line 2` / `line 36` respectively). No in-body prose location parses.
- **Delete the narrative outright**: It is duplicated in `smolspec.md` and Decision 2. — Rejected: the brief mandates moving, not losing, load-bearing narrative; keeping a pointer in the ledger's own metadata is cheap and aids readers of `tasks.md` alone.

### Consequences

**Positive:**

- `rune list` parses cleanly; the ledger is machine-reconcilable again (1–7 Completed, 8–9 Pending).
- No task state changed; the re-open context is preserved and discoverable from `tasks.md` itself.

**Negative:**

- Front-matter block scalars do not render the narrative's markdown links/backticks as formatted text; readers wanting the rich version consult `smolspec.md` or Decision 2.
- A future editor must remember rune's no-in-body-prose rule when adding phases, or the parse breaks again.

### Impact

`specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/tasks.md` only — front-matter gains `reopen_2026_06_16`; the body prose paragraph under the `## Re-open 2026-06-16` heading is removed. No code, no other spec files.

---
