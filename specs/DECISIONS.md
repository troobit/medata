# Decision Log: Medata (Meta)

This is the repository-level **meta decision log**. It distils the load-bearing,
cross-cutting decisions that define Medata from the per-spec decision logs under
`specs/*/decision_log.md`, and organises them by architectural theme rather than
by feature.

It is a synthesis, not a replacement: each meta-decision (MD) cites the source
per-spec decisions that establish or refine it. When a meta-decision and a source
decision disagree, **the per-spec decision log is authoritative** — this file is
maintained as a rolling summary and may lag the detail. For the full Context /
Alternatives / Consequences of any item, follow its **Sources** line.

For the spec index see [OVERVIEW.md](OVERVIEW.md). For the
per-decision format see `rules/references/decision-log-format.md`.

**Source citation key:** `research D9` = Decision 9 in `specs/estimation/pipeline/decision_log.md`;
`ui D15` = Decision 15 in `specs/ui/iphone-experience/decision_log.md`; `event-log D3` =
`specs/data/event-log-schema/decision_log.md`; `pipeline-rdc D4` =
`specs/estimation/pipeline-real-device-correctness/decision_log.md`; `lidar-fallback D1` =
`specs/estimation/lidar-first-scale-fallback/decision_log.md`; `rawframe D5` =
`specs/capture/rawframe-rgb-conversion/decision_log.md`; `shutter D4` =
`specs/ui/shutter-blocked-feedback/decision_log.md`; `mv-volume D5` =
`specs/estimation/mv-volume-estimator/decision_log.md`; `bubble D1` =
`specs/ui/bubble-only-cleanup/decision_log.md`; `bugfix/<name> D1` =
`specs/bugfixes/<name>/decision_log.md`.

---

## Summary

| ID | Section | Title | Status |
|----|---------|-------|--------|
| [MD-1](#md-1-geometric-voxel-carving--density-lookup-pipeline-over-llm-inference) | Pipeline Architecture | Geometric voxel-carving + density-lookup pipeline over LLM inference | accepted |
| [MD-2](#md-2-two-capture-paths-single-view-height-field-integration-and-two-view-sfs) | Pipeline Architecture | Two capture paths: single-view height-field integration and two-view SfS | accepted |
| [MD-3](#md-3-visual-hull-is-an-upper-bound-corrected-by-closure-lidar-and-per-class-c) | Pipeline Architecture | Visual hull is an upper bound, corrected by closure + LiDAR + per-class β_c | accepted |
| [MD-4](#md-4-one-small-on-device-segmenter-is-the-only-learned-component) | Pipeline Architecture | One small on-device segmenter is the only learned component | accepted |
| [MD-5](#md-5-pre-shutter-segmentation-and-card-detection) | Pipeline Architecture | Pre-shutter segmentation and card detection | accepted |
| [MD-6](#md-6-protocol-seams-at-every-injectable-boundary) | Pipeline Architecture | Protocol seams at every injectable boundary | accepted |
| [MD-7](#md-7-metric-scale-from-lidar-andor-id-1-card-via-pnp-card-optional) | Scale & Geometry | Metric scale from LiDAR and/or ID-1 card via PnP; card optional | accepted |
| [MD-8](#md-8-degrade-confidence-instead-of-refusing-keep-only-undefined-cases-hard) | Scale & Geometry | Degrade confidence instead of refusing; keep only undefined cases hard | accepted |
| [MD-9](#md-9-on-device-plane-fit-robustness) | Scale & Geometry | On-device plane-fit robustness | accepted |
| [MD-10](#md-10-multi-food-semantic-segmentation-liquids-excluded) | Segmentation & Classes | Multi-food semantic segmentation; liquids excluded | accepted |
| [MD-11](#md-11-deterministic-per-class-voxel-ownership) | Segmentation & Classes | Deterministic per-class voxel ownership | accepted |
| [MD-12](#md-12-segmenter-and-c-quality-bars) | Segmentation & Classes | Segmenter and β_c quality bars | accepted |
| [MD-13](#md-13-single-bundled-sqlite-food-database-cofid--afcd) | Persistence & Data | Single bundled SQLite food database (CoFID + AFCD) | accepted |
| [MD-14](#md-14-long-form-event-log-is-the-single-meal-store) | Persistence & Data | Long-form event log is the single meal store | accepted |
| [MD-15](#md-15-photo-storage-via-photokit-bounded-artefact-retention) | Persistence & Data | Photo storage via PhotoKit; bounded artefact retention | accepted |
| [MD-16](#md-16-confidence-is-the-geometric-mean-of-sub-confidences) | Persistence & Data | Confidence is the geometric mean of sub-confidences | accepted |
| [MD-17](#md-17-bgra8-pixel-conversion-at-the-capture-boundary) | Persistence & Data | BGRA8 pixel conversion at the capture boundary | accepted |
| [MD-18](#md-18-three-tab-shell-with-persistent-meal-history) | UI / UX | Three-tab shell with persistent meal history | accepted |
| [MD-19](#md-19-tilt-tolerant-capture-always-armed-shutter-four-tier-confidence) | UI / UX | Tilt-tolerant capture, always-armed shutter, four-tier confidence | accepted |
| [MD-20](#md-20-clean-capture-aesthetic-driven-by-design-tokens) | UI / UX | Clean capture aesthetic driven by design tokens | accepted |
| [MD-21](#md-21-console-grade-diagnostic-logging-for-the-capture-trail) | UI / UX | Console-grade diagnostic logging for the capture trail | accepted |
| [MD-22](#md-22-ios-first-android-ready-architecture) | Platform & Hardware | iOS-first, Android-ready architecture | accepted |
| [MD-23](#md-23-hardware-floor-iphone-13-pro-max--ios-265-iphone-only) | Platform & Hardware | Hardware floor: iPhone 13 Pro Max / iOS 26.5, iPhone-only | accepted |
| [MD-24](#md-24-clinical-layer-descoped-carb-estimation-is-the-risk-focus) | Process & Method | Clinical layer descoped; carb estimation is the risk focus | accepted |
| [MD-25](#md-25-accuracy-bar-mape--20-mae-a-reference-not-a-gate) | Process & Method | Accuracy bar: MAPE < 20%, MAE a reference not a gate | amended |
| [MD-26](#md-26-phased-delivery-behind-a-dev-stub-segmenter) | Process & Method | Phased delivery behind a dev-stub segmenter | accepted |
| [MD-27](#md-27-evaluation-harness-gated-behind-a-compile-flag) | Process & Method | Evaluation harness gated behind a compile flag | accepted |
| [MD-28](#md-28-measure-latency-in-release-before-treating-it-as-a-defect) | Process & Method | Measure latency in Release before treating it as a defect | accepted |

---

# Pipeline Architecture

## MD-1: Geometric voxel-carving + density-lookup pipeline over LLM inference

**Status**: accepted
**Sources**: research D1, research D3; mv-volume D5

### Context

The original `mvp-refinement` work was a provider-agnostic multimodal-LLM path that
predicted macros directly from a photo. The stated objectives are a *specific*
system (carbohydrate estimation for type-1 diabetes), low cost/compute, and outputs
grounded in the academic literature rather than direct AI inference.

### Decision

The carb-estimation core is a classical computer-vision + geometry pipeline:
segment the food, reconstruct its volume, look up density, and compute carbohydrate
mass. The LLM path is discarded as the core approach; a cloud second-opinion is at
most a deferred, opt-in extension.

### Rationale

Per-photo cost is bounded by a single small segmentation pass plus a bounded
geometric sweep — orders of magnitude cheaper than a multimodal LLM call, and
fully on-device. Every output traces back to a measured volume, a density, and a
per-100 g coefficient, which a hallucinated LLM number cannot.

### Consequences

- **Positive:** Bounded on-device cost; clinically auditable provenance.
- **Negative:** Requires a reference scale and curated density tables; two-view
  geometry adds capture friction versus a single photo.

---

## MD-2: Two capture paths: single-view height-field integration and two-view SfS

**Status**: accepted
**Sources**: research D7, research D10, research D13, research D35

### Context

With a LiDAR device, a single nadir view plus a metric depth surface can produce
volume directly. Without depth, the portable algorithm is two-view
Shape-from-Silhouette voxel carving.

### Decision

The pipeline supports two explicit, separately-specified capture paths, persisted
per meal as `capturePath`:

- `single_view_lidar` — **height-field integration** between the support plane and
  the LiDAR top surface (not a degenerate voxel carve).
- `two_view_sfs` — voxel carving with support-plane closure; this is the
  **Android-canonical** algorithm.

The path is **user-selected** via a persistent `Single` / `Double` toggle, not
auto-derived. Each path carries its own latency budget.

### Rationale

The two algorithms have different error models and costs, so conflating them hides
real differences. Making the path explicit and user-chosen keeps behaviour
predictable and keeps the two-view algorithm portable to Android unchanged.

### Consequences

- **Positive:** Each path has a clean contract, budget, and confidence model.
- **Negative:** Two algorithms to maintain; re-derivation must dispatch on
  `capturePath`.

---

## MD-3: Visual hull is an upper bound, corrected by closure + LiDAR + per-class β_c

**Status**: accepted
**Sources**: research D9, research D20, research D30

### Context

Pure Shape-from-Silhouette yields the visual hull (Laurentini 1994), a strict
superset of the true food shape. Concavities, packing fraction, and internal voids
are never carved — the single largest source of systematic over-estimation.

### Decision

Acknowledge the hull bound explicitly and correct it with three combined
mechanisms: (1) **support-plane closure** bounding the carve from below;
(2) **LiDAR top-surface intersection** where available; and (3) a per-class
**bulk-correction factor β_c ∈ (0, 1]** in the bundled database, calibrated by
minimising log-residuals (MAPE-aligned) against a gravimetric test set, with
≥ 30 meals/class required to calibrate or else β_c = 1.0.

### Rationale

This matches what the single-digit-MAE literature does in practice. Putting the
correction in β_c (rather than in the densities) keeps the published CoFID/AFCD
densities attributable, and a database-level factor lets calibration improve
without code changes.

### Consequences

- **Positive:** Pipeline matches the reality of silhouette reconstruction; density
  provenance preserved.
- **Negative:** β_c is coupled to the specific segmenter checkpoint — retraining
  invalidates calibration; uncalibrated classes ship with the hull's upward bias.

---

## MD-4: One small on-device segmenter is the only learned component

**Status**: accepted
**Sources**: research D3, research D25, research D26, research D27, research D28

### Context

Voxel carving needs per-view food masks. Classical segmentation does not generalise
across cuisines; cloud calls break the cost/offline objectives.

### Decision

A single small semantic segmenter is the only learned component; everything else
(card detection, carving, density lookup, carb maths) is deterministic. The model
is **DeepLabV3 + MobileNetV3-Large** at 513² input, FP16, ≤ 10 MB, trained once in
PyTorch and exported to **both Core ML and TFLite** from one checkpoint. Volume
kernels run as **Metal compute** shaders. Weights and the food database are
**bundled in the binary** — no CDN.

### Rationale

A small segmenter is the minimal learned piece that lets the rest be deterministic
geometry. Single-checkpoint dual export keeps iOS and Android on the same weights.
Bundling keeps the app fully offline.

### Consequences

- **Positive:** One artefact needs training data; fully offline; portable weights.
- **Negative:** Class palette must be curated; out-of-palette foods degrade.

---

## MD-5: Pre-shutter segmentation and card detection

**Status**: accepted
**Sources**: pipeline-rdc D3, pipeline-rdc D4, pipeline-rdc D5, pipeline-rdc D10, pipeline-rdc D11, pipeline-rdc D13, pipeline-rdc D14

### Context

On real-device captures the food mask and `foodRegionCoveragePercent` must exist at
shutter-tap time, not be computed after. Phase-1 stop-gaps produced empty/stale
masks and false refusals.

### Decision

Run segmentation continuously **before** the shutter (≥ 2 Hz / ≤ 500 ms latency,
staleness ceiling 750 ms) at native 1920×1440, with latest-wins publication and
cancellable in-flight inference. Run the **Vision card detector on every nadir
capture**. The mask is **frozen at the nadir-capture instant** (snapshot-then-pause
via `awaitPaused()`) and travels with the captured frame; coverage is computed in
confidence-buffer space (256×192).

### Rationale

A live producer with a frozen-at-capture snapshot gives a fresh, deterministic mask
at the exact capture instant, eliminating the staleness and empty-mask failures seen
on device.

### Consequences

- **Positive:** Real coverage and masks available at shutter time; deterministic.
- **Negative:** A continuous inference producer adds steady-state compute and
  lifecycle (pause/resume, cancellation) to manage.

---

## MD-6: Protocol seams at every injectable boundary

**Status**: accepted
**Sources**: ui D13, pipeline-rdc D9, rawframe D3

### Context

Unit tests and phased delivery need to swap concrete pipeline pieces without
spinning up the real (heavy) implementations.

### Decision

Introduce narrow protocol seams in `MedataCore` at each injectable boundary:
`PipelineEstimator` (whole-pipeline mock for UI state tests), `SupportPlaneFitter`
(injectable plane-fit), and the `PixelBufferAdapter` conversion boundary. Each is
the smallest contract that decouples a consumer from a heavy concrete type.

### Rationale

API-shaped abstractions belong in the core module, not in `App/`. Small seams let
the UI spec ship independently of the segmenter, and let production conformers be
swapped for stubs deterministically.

### Consequences

- **Positive:** UI/state testable without real weights; phased delivery unblocked.
- **Negative:** A few public protocols exist primarily for testability.

---

# Scale & Geometry

## MD-7: Metric scale from LiDAR and/or ID-1 card via PnP; card optional

**Status**: accepted
**Sources**: research D6, research D16, research D18, research D29; lidar-fallback D1, lidar-fallback D2

### Context

An ID-1 card (85.60 × 53.98 mm) and LiDAR depth each independently give a metric
scale. Edge-ratio scaling is geometrically wrong on oblique views.

### Decision

Recover the card's 6-DOF pose by **Perspective-n-Point**, lifting scale to the food
plane — never by edge ratio. The card is **optional**: with a card, cross-check
against LiDAR; with LiDAR only, proceed and flag low confidence; with neither,
refuse. A card-solve failure (`cardTooOblique` / `degenerateCardPose`) **falls back
to LiDAR scale** when depth is present, and only fails closed when LiDAR is absent
(generic card errors always fail closed). Geometry uses a 1/cos³θ off-axis pixel-area
correction and a voxel grid sized for a 270 mm plate at 3 mm edge.

### Rationale

PnP is the standard, portable solution and is geometrically correct from any
reasonable angle. Treating the card as a quality boost rather than a hard gate keeps
the app usable while staying honest about uncertainty.

### Consequences

- **Positive:** Correct scale off-axis; card-pose failure is non-fatal with LiDAR.
- **Negative:** Two scale-source code paths to maintain.

---

## MD-8: Degrade confidence instead of refusing; keep only undefined cases hard

**Status**: accepted
**Sources**: research D43, research D44, research D46, research D47; bugfix/closeout-trail-mvp-cleanup D1

### Context

A t1dm user with unsteady hands could not get past hard angular and coverage gates.
Most off-axis captures are still useful if reported honestly.

### Decision

Replace hard gates with **soft acceptance + confidence degradation**: drop the ±5°
nadir tilt gate (σ_tilt = cos(Δθ), a fourth σ_geom factor), raise the LiDAR
plane-fit refusal from 8 mm to 20 mm, and relax single-view LiDAR coverage refusal
from 50% to 30%. **Mathematically-undefined cases stay hard refusals** (no food
pixels, singular covariance, zero depth in food). The oblique stage keeps a wider
hard cap (later tightened to ≈ ±15° around 25° to stay inside the SfS envelope).

### Rationale

The hard gates encoded "wrong" states that mostly just cost confidence. Surfacing
the cost via σ rather than blocking capture removes the principal usability blocker
while keeping genuinely meaningless captures out.

### Consequences

- **Positive:** Always-capturable; honest confidence reporting.
- **Negative:** More low-confidence meals; users rely on the pill to interpret them.

---

## MD-9: On-device plane-fit robustness

**Status**: accepted
**Sources**: bugfix/lidar-plane-fit-oom-on-device-1920x1440 D1; bugfix/lidar-plane-fit-degenerate-on-clean-capture D1, D2; pipeline-rdc D7

### Context

At 1920×1440 the LiDAR plane fit hit a 32 GB allocation (full SVD over all
inliers) and produced degenerate fits on clean captures where the rough mask gave
no usable spatial prior.

### Decision

Replace the O(n²) 3×n SVD with a **3×3 scatter-matrix SVD** (the O(n) accumulation
that removed the 32 GB allocation), and scan **four edge bands** around the food bbox
when collecting candidate points (superseding the all-ones / single-below-band
approximations). A DEBUG candidate-point counter (`debugLastCandidatePointCount`) is
emitted for diagnostics, but there is **no enforced candidate ceiling** — the
scatter-matrix form already bounds memory regardless of n.

### Rationale

The scatter-matrix form is mathematically equivalent at bounded memory independent of
resolution; edge-band sampling gives the table-plane prior that food segmentation alone
cannot.

### Consequences

- **Positive:** Plane fit is memory-bounded and robust on real captures.
- **Negative:** Candidate sampling is a heuristic that future captures may stress.

---

# Segmentation & Classes

## MD-10: Multi-food semantic segmentation; liquids excluded

**Status**: accepted
**Sources**: research D8, research D12

### Context

Real meals are multi-component. Liquids and semi-liquids break silhouette, depth,
and the constant-density assumption.

### Decision

Support **multi-food** meals where each food is a distinct semantic class (composite
dishes handled as a single composite class). **Liquids/semi-liquids are out of scope
for v1**: an `unsupported_liquid` class catches them, those pixels are excluded from
volume, and the meal is flagged.

### Rationale

Per-class segmentation matches the literature and avoids instance-segmentation cost.
Excluding a known-broken category is more honest than emitting wrong numbers for it.

### Consequences

- **Positive:** Realistic meal coverage; explicit message instead of bad estimate.
- **Negative:** Palette curation cost; smoothies/soups unestimated in v1.

---

## MD-11: Deterministic per-class voxel ownership

**Status**: accepted
**Sources**: research D11

### Context

Overlapping silhouettes can assign one voxel to two classes, double-counting carbs.

### Decision

Path-specific ownership: single-view assigns each nadir pixel to one class by
**argmax**; two-view assigns each voxel to `argmax_c q₁(v)_c · q₂(v)_c`, discarding
voxels below a probability-product threshold τ_v (default 0.04) and persisting the
discarded fraction. No voxel/pixel contributes mass to more than one class.

### Rationale

Argmax does not lift cleanly to 3D; the probability-product is the natural
conditional-independence extension, used deterministically as an ownership rule
rather than as a probabilistic claim.

### Consequences

- **Positive:** Deterministic, testable, uses segmenter probabilities directly.
- **Negative:** A marginally-less-probable class gets zero mass at a pixel.

---

## MD-12: Segmenter and β_c quality bars

**Status**: accepted
**Sources**: research D14, research D20, research D30

### Context

Without component-level bars, segmenter regressions could be masked by β_c, and the
end-to-end accuracy bar would have no decomposition.

### Decision

The segmenter must meet **mean IoU ≥ 0.60** across food classes on a held-out set,
evaluated separately from the carb-error bar. β_c is calibrated by a closed-form
**log-residual** fit on a disjoint subset, requiring ≥ 30 meals/class (else
β_c = 1.0, flagged uncalibrated).

### Rationale

A separate segmenter bar localises regressions; the log-residual fit aligns β_c with
the MAPE objective; the sample-size floor keeps shipped β_c statistically defensible.

### Consequences

- **Positive:** Accuracy decomposes into segmenter + density components.
- **Negative:** A held-out segmenter test set must be maintained.

---

# Persistence & Data

## MD-13: Single bundled SQLite food database (CoFID + AFCD)

**Status**: accepted
**Sources**: research D19, research D24, research D27, research D39

### Context

The first draft offered "SQLite or FlatBuffers" and an IFCDB overlay — two schemas
and an extra toggle.

### Decision

The bundled food database is a **single SQLite file**, documented and used verbatim
on iOS and Android. Macros are sourced from **CoFID + AFCD** queried with a
CoFID-wins `COALESCE`; the **IFCDB overlay is removed** (both databases always
present). Palette migrations preserve original class assignments via explicit maps.

### Rationale

SQLite has first-class support on both platforms and standard tooling; FlatBuffers'
read-speed edge is irrelevant for a small, read-once table. Two always-present
databases remove a configuration branch.

### Consequences

- **Positive:** One format, one schema, two-platform interoperability.
- **Negative:** Marginally slower startup than a pre-parsed format (immaterial).

---

## MD-14: Long-form event log is the single meal store

**Status**: accepted
**Sources**: event-log D1–D10

### Context

Persistence needed a forward-compatible shape that the future clinical track can
consume, without lakehouse complexity at MVP.

### Decision

A **long-form event log** is the sole meal store: one event per meal, the primary
scalar (total carbohydrate) in `value`, and the per-class / per-macro breakdown plus
the verbatim record in JSON `metadata`. Units are **metric only** (glucose in
mmol/L). Event type is a Swift constant (`EventType.meal`), not a SQL `CHECK`. No
migration/backfill (no production data exists). `PersistenceStore` exposes
`events(in:type:)` / `corrections(for:)` and an `eventsDidChange` stream.

### Rationale

A fixed timestamp/type/value schema with a JSON metadata sidecar is the smallest
shape that supports future event types and the clinical track without schema churn.

### Consequences

- **Positive:** Forward-compatible; single store; metric-only avoids i18n surface.
- **Negative:** Multi-dimensional reads parse JSON rather than query columns.

---

## MD-15: Photo storage via PhotoKit; bounded artefact retention

**Status**: accepted
**Sources**: research D37, research D15

### Context

The user wants photos to stay on-device and under their control; indefinite
retention served the clinical track, not the user story.

### Decision

The captured RGB nadir frame is saved to the **Photos library** (`MealRecord`
stores the `PHAsset.localIdentifier`); the app container keeps only algorithm-private
artefacts. Default artefact retention is **30 days** (configurable to 90/365/
indefinite for opt-in clinical participation); macro values stay in the database
indefinitely. Deleting a meal never deletes the user's `PHAsset`.

### Rationale

PhotoKit gives the user ownership and a familiar surface; a 30-day artefact window
honours the privacy expectation while keeping small, non-sensitive macros forever.

### Consequences

- **Positive:** User owns the imagery; default aligns with the user story.
- **Negative:** Re-deriving an old meal with a new β_c needs frames that may be gone.

---

## MD-16: Confidence is the geometric mean of sub-confidences

**Status**: accepted
**Sources**: research D17, research D21, research D45

### Context

The combination function was originally ambiguous ("product or another function"),
making the 0.6 threshold untestable; a single zero sub-confidence collapsed the
whole value.

### Decision

Per-meal confidence is the **geometric mean** of three sub-confidences (scale,
segmenter, geometric completeness), each floored at **ε = 0.01** before combining,
so σ_meal ∈ [ε, 1] and never zero. True failure modes are handled by refusal, not by
a zero-confidence estimate.

### Rationale

The geometric mean stays in a readable range, is symmetric, and is monotone with the
product so the threshold survives. The ε floor preserves information from non-zero
factors while still penalising a bad one; 0.01 lets genuinely degraded estimates show
as ~1% rather than hitting an artificial floor.

### Consequences

- **Positive:** Single testable function; honest low-but-nonzero confidence.
- **Negative:** ε is a tuned constant; revising it needs a new decision.

---

## MD-17: BGRA8 pixel conversion at the capture boundary

**Status**: accepted
**Sources**: rawframe D1, D2, D5, D6, D7, D8

### Context

ARKit delivers YCbCr frames; downstream Vision/CGImage consumers expect interleaved
RGB, so the wrong bytes were being read.

### Decision

Convert ARKit YCbCr → **BGRA8** at the capture boundary, **at shutter time only**
(the live `frames` stream stays raw), via **vImage** behind a `PixelBufferAdapter`
seam. Conversion failures are a nested `ConversionError`, and the pipeline catch-all
maps untyped errors to a new `EstimationFailure.internalError(String)` rather than
mislabelling them `noScaleAvailable`.

### Rationale

Converting once at capture keeps the live stream cheap; vImage is hardware-accelerated
and standard; a dedicated error case stops misdiagnosis of unrelated failures.

### Consequences

- **Positive:** Correct bytes downstream; honest error reporting; testable seam.
- **Negative:** No hard per-frame wall-clock target (correctness-gated instead).
- **Negative (latent, rawframe D8):** the adapter accepts both full- and video-range
  YCbCr but decodes both with the full-range matrix, so a video-range source would be
  colour-shifted (correct length/order, so no error fires). Dormant — ARKit emits
  full-range by default — but bites a non-ARKit caller (e.g. the macOS HarnessCLI);
  fix is to select the matrix on the four-CC or honour Req 1.5 and refuse `420v`.

---

# UI / UX

## MD-18: Three-tab shell with persistent meal history

**Status**: accepted
**Sources**: ui D2, ui D15; event-log D7

### Context

v1.0 was a single-screen capture flow with no way to confirm meals were persisting
or to clean up placeholder runs.

### Decision

The app is a three-tab `TabView` shell — **Photo** (capture, default), **Meals**
(persistent history list with thumbnail, carbs, confidence, and a dev-stub
"Placeholder" chip), **Settings** — each in its own `NavigationStack`. Capture state
survives a tab switch during `.estimating`; the engine is released within 200 ms when
leaving Photo otherwise. (v1.0 had deferred history; it was added in v1.1.)

### Rationale

The standard iOS tab pattern is the conventional answer for three top-level surfaces;
it inherits pop-to-root, per-tab state, and the system Liquid Glass tab bar for free,
and gives the developer in-app confirmation that meals persist.

### Consequences

- **Positive:** Standard navigation; in-app verification of persistence.
- **Negative:** v1.0 capture-only framing no longer holds; small new persistence
  surface (`allMeals`, `deleteMeal`, `eventsDidChange`).

---

## MD-19: Tilt-tolerant capture, always-armed shutter, four-tier confidence

**Status**: accepted
**Sources**: ui D1, ui D5, ui D17, ui D18, ui D19, ui D20, ui D21; research D43

### Context

With soft acceptance (MD-8) low-confidence estimates became routine, so the old
three-tier pill and 0.6 retake prompt would fire on most captures, and the
tilt-driven shutter gate no longer had meaning.

### Decision

Capture is a **manual shutter** that is **always armed when capture is otherwise
possible** (tracking normal, distance OK, no estimate in flight; only the oblique
stage keeps a hard angular cap). The result view uses a **four-tier confidence pill**
(High ≥ 0.75 / Moderate ≥ 0.50 / Low ≥ 0.20 / Very Low < 0.20), and the **retake
prompt fires only at Very Low**. The live tilt indicator is a **continuous Δθ +
σ_tilt% readout**, not a binary green/white state. Refusals appear inline as a
swipe-dismissible sheet; leaving the Photo tab clears `.refused`.

### Rationale

Always-arming removes the usability blocker; four tiers convey the gradient that soft
acceptance produces and restore signal value to the retake prompt; a continuous
readout teaches the confidence trade-off at the moment of capture.

### Consequences

- **Positive:** Steady-hands-not-required capture; honest, low-fatigue feedback.
- **Negative:** Several shared UI components and their tests change with the tiers.
- **Negative (contract gap, ui D21):** the very-low surface's per-stage Δθ readout is
  hardcoded to 0° because the persisted `PbConfidenceResult` lacks
  `deltaThetaNadirDeg`/`deltaThetaObliqueDeg`; the continuous live readout is real, but
  the result-view value is inert until the estimation side adds those fields.

---

## MD-20: Clean capture aesthetic driven by design tokens

**Status**: accepted
**Sources**: ui D16, ui D4; bubble D1, bubble D2

### Context

After the tab shell, visual design across tabs was implicit; the v1.0 chrome competed
with the AR preview.

### Decision

Adopt a clean capture aesthetic (OLED-black capture/result backgrounds, flat
touch-first chrome, exaggerated-minimal carb total) with **all visual tokens in
`design-system/MASTER.md`** plus per-screen overrides; views consume tokens verbatim,
no parallel inline values. The app targets the system-default **Liquid Glass** material
on iOS 26.5 (superseding the earlier "iOS 17 surface, no Liquid Glass" stance). Unused
tilt-guide designs (`.gauge`/`.dial`) were removed, leaving the device-confirmed
`.bubble` guide as the sole design.

### Rationale

Tokenising is the standard way to keep every screen feeling like one product and lets
shared elements (placeholder chip, confidence pill) stay identical without copy-paste
coordination.

### Consequences

- **Positive:** Centralised visual language; new screens inherit tokens for free.
- **Negative:** Superseded v1.0 components need their tests rewritten.

---

## MD-21: Console-grade diagnostic logging for the capture trail

**Status**: accepted
**Sources**: shutter D1, D2, D3, D4, D5, D6

### Context

"The shutter doesn't work" was ambiguous between a gated shutter, a hung pipeline, and
a silent refusal, with no on-device signal to distinguish them.

### Decision

Emit a symmetric OSLog trail under one `Logger(subsystem: "ie.medata.app",
category: "Shutter")` covering blocked taps and the full success path
(`fired` → `capture.start/end` → `estimate.start/end`), so a single Console.app
predicate captures every tap's lifecycle. Only `.disabled` taps trigger feedback
(haptic via `.sensoryFeedback`, indicator reveal) — `.capturing` taps are dropped.
Badge visibility moved onto `LiveIndicatorModel`.

### Rationale

Stage-boundary logs make field diagnosis possible without Instruments and distinguish
"gated" / "hung" / "refused" / "succeeded"; the iOS 17+ `.sensoryFeedback` API keeps
`CaptureFlowModel` UIKit-free and testable.

### Consequences

- **Positive:** Field-diagnosable capture trail; idiomatic haptics.
- **Negative:** A handful of unconditional `.info` log sites in the model.

---

# Platform & Hardware

## MD-22: iOS-first, Android-ready architecture

**Status**: accepted
**Sources**: research D2, research D28, research D31

### Context

Both iOS and Android are eventual targets, but building both natively in parallel
doubles cost; building iOS with no portability plan forces a full Kotlin re-derivation.

### Decision

Ship **iOS first**, but architect for Android: algorithms specified as
platform-neutral maths; cross-module **type contracts via `.proto` schemas** (Swift
types wrap protobuf; records persisted as protobuf-JSON); the segmenter exported to
both Core ML and TFLite from one checkpoint (MD-4). The two-view SfS path stays the
portable canonical algorithm (MD-2).

### Rationale

The maths is platform-neutral; only sensor APIs and inference runtimes differ.
Encoding the boundary explicitly makes a future Android port a mechanical translation
of the shell, not the algorithms.

### Consequences

- **Positive:** Single iOS codebase now; algorithms documented once.
- **Negative:** Specs must avoid iOS-only abstractions; some Swift/Kotlin duplication.

---

## MD-23: Hardware floor — iPhone 13 Pro Max / iOS 26.5, iPhone-only

**Status**: accepted
**Sources**: research D7 (superseded), research D40; bugfix/clean-build-baseline D1, D3

### Context

LiDAR collapses the metric-scale problem and often removes the second view. The floor
started at iPhone 12 Pro+ / iOS 17 and was narrowed for a measurable MVP target.

### Decision

The v1 calibration/performance floor is **iPhone 13 Pro Max, iOS 26.5**, and the app
is **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`). The non-LiDAR confidence path still
exists at runtime, but targets are measured only on the floor device. Latency is a
single soft target (**end-to-end < 30 s**, both modes), per-stage P95 budgets removed.

### Rationale

A single, current floor device makes targets measurable and removes a class of device
matrix variance; dropping iPad removes validator warnings and unneeded icon assets.

### Consequences

- **Positive:** Measurable targets; smaller validation matrix.
- **Negative:** Smaller addressable audience; Android cannot rely on LiDAR.

---

# Process & Method

## MD-24: Clinical layer descoped; carb estimation is the risk focus

**Status**: accepted
**Sources**: research D4

### Context

GitHub issues describe a clinical layer (atomic event log + AWAP cycle, active-carb
decay, CGM/OAuth2 sync) over the carb core. It is valuable but orthogonal to the
photography → volume → carbs pipeline.

### Decision

Defer the clinical layer to a separate `specs/clinical` track. The research spec
includes only the **data hooks** (immutable meal records, structured corrections) the
clinical track will consume; it does not implement the cycle, decay model, or CGM
sync.

### Rationale

The carb pipeline is where the technical risk concentrates; bundling clinical features
would dilute focus and blow up the test surface. The tracks share data structures
only, not runtime concerns.

### Consequences

- **Positive:** Research stays focused on measurable contracts.
- **Negative:** Two specs to maintain; some early data shapes must anticipate clinical
  needs.

---

## MD-25: Accuracy bar — MAPE < 20%, MAE a reference not a gate

**Status**: amended
**Sources**: research D5 (amended), research D23, research D40

### Context

GoCARB reached ≈ 6 g MAE; a greenfield v1 needs an honest but testable bar.

### Decision

The v1 accuracy bar is **MAPE < 20%** on a labelled internal test set, as a **point
estimate** (the reported confidence interval is transparency, not a moving gate). The
MAE reference was **relaxed from ≤ 10 g to ≤ 25 g** and is now **informational**, not a
CI gate.

### Rationale

This is achievable for a greenfield voxel pipeline and within the clinically useful
range; tightening later is a measurement question, not a redesign. Gating on a point
estimate keeps the acceptance line stable.

### Consequences

- **Positive:** Clear, stable go/no-go bar comparable to the literature.
- **Negative:** A labelled (and gravimetric, for β_c) test set must be assembled.

---

## MD-26: Phased delivery behind a dev-stub segmenter

**Status**: accepted
**Sources**: research D42; pipeline-rdc D8; mv-volume D5

### Context

The real Core ML segmenter does not exist yet, but the device pipeline, UI, and
persistence can be built and verified ahead of it.

### Decision

Deliver in phases — **device pipeline → UI/UX → data veracity** — with Phase 1 running
a `StubInferenceEngine` behind a `DEV_STUB_SEGMENTER` compile flag (a deterministic
centred-ellipse food region). `Pipeline.makeForDevice` swaps the implementation, the
result view shows a placeholder banner, and `segmenterSource` is persisted for audit
so dev-stub provenance follows each meal. The fallback retires automatically when the
real model lands.

### Rationale

Keying everything off the stamped `segmenterSource` means the degraded path cannot
ship to App Store builds and disappears without a later removal step; it unblocks
parallel UI/persistence work.

### Consequences

- **Positive:** Self-retiring; parallel workstreams; App-Store builds never degraded.
- **Negative:** The stub path needs explicit device verification before it is trusted.

---

## MD-27: Evaluation harness gated behind a compile flag

**Status**: accepted
**Sources**: research D34 (superseded), research D41

### Context

The §21 test harness / β_c calibration / mIoU bench were first removed from the v1
tree to cut surface area, then needed back without bloating the shipping app.

### Decision

Restore the harness and gate every harness source file behind `#if HARNESS_ENABLED`,
defined **only** in the `HarnessCLI` target. The iOS app target contains **zero**
harness code at link time. (This supersedes the earlier outright-removal decision.)

### Rationale

A compile-flagged harness keeps evaluation code available for development while
guaranteeing it never reaches the shipped binary.

### Consequences

- **Positive:** Harness available; app binary stays clean.
- **Negative:** A compile flag and a separate target to maintain.

---

## MD-28: Measure latency in Release before treating it as a defect

**Status**: accepted
**Sources**: pipeline-rdc D16; mv-volume D4, D5

### Context

On-device dev-stub Debug builds showed 27–50 s stage latencies and AR-frame
starvation, which looked like a code defect — and a smolspec was nearly built on a
misdiagnosis of where a refusal originated.

### Decision

Treat Debug `-Onone` latency as suspect: **measure in Release before scheduling a
fix**. The Release build showed an ~827 ms full estimate with no starvation, so no
code fix was scheduled. Relatedly, verify a failure's actual stage on-device before
building a fix — the `mv-volume-estimator` smolspec was abandoned (premise invalidated)
when a static read showed the dev-stub masks were carveable and the real failure was
geometric, redirected to a `/fix-bug` investigation.

### Rationale

Acting on Debug-build timings or an inferred failure location wastes effort on
non-defects and builds throwaway crutches that hide the real bug.

### Consequences

- **Positive:** Avoids fixing non-defects; keeps the record honest.
- **Negative:** Requires Release measurement and on-device captures before diagnosis.

---
