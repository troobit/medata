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
