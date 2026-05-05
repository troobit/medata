# Decision Log: research

## Decision 1: Replace LLM-based MVP with voxel-carving pipeline

**Date**: 2026-05-05
**Status**: accepted

### Context

The existing `mvp-refinement` spec describes a provider-agnostic LLM pipeline (OpenAI-compatible vision endpoint) that asks a multimodal model to produce per-item macro estimates from a food photo. The MVP is code-complete only at the UI layer — none of the recognition is operational. Open GitHub issues (#6–#24 on `troobit/medata`) describe a different system grounded in classical computer vision and geometric reconstruction (Anthimopoulos 2014, Dehais 2017, GoCARB clinical pipeline). The two approaches are architecturally incompatible: the LLM path predicts macros directly; the geometric path measures volume and looks up density.

The user's stated objectives are (a) build a *very specific* system (carbohydrate estimation for type-1 diabetes), (b) reduce cost of use and compute, and (c) base the system on the mathematics in the academic literature rather than direct AI inference.

### Decision

Discard the LLM-based MVP and adopt the voxel-carving + density-lookup pipeline as the only intended approach. The mvp-refinement Svelte frontend is treated as throwaway UI exploration. Future external validation against a cloud model is a deferred extension, not a core dependency.

### Rationale

The geometric pipeline produces per-photo cost dominated by a single ≤10 MB segmentation forward pass and a bounded voxel-grid sweep — orders of magnitude cheaper than a multimodal LLM call. Its outputs are derived from measurable physical quantities (volume, density) with traceable provenance, satisfying the clinical-grade constraint that a hallucinated LLM number cannot. The mathematics is established in the cited literature.

### Alternatives Considered

- **Coexist (LLM as fallback)**: Rejected — keeping the LLM path in the core flow undermines the cost/compute objective and forces every release to meet two correctness bars.
- **LLM-only with smaller models**: Rejected — even a quantised on-device VLM is heavier than a single segmentation network, and gives no traceable physical derivation.

### Consequences

**Positive:**
- Per-photo compute cost is bounded and on-device.
- Estimates are mathematically derived from measurements, not learned end-to-end.
- Clinical-grade auditability — every output traces back to a volume, a density, and a per-100 g coefficient.

**Negative:**
- Two-view geometry adds capture friction vs single-photo LLM.
- Requires a reference scale (LiDAR or ID-1 card) to establish metric units.
- Density tables and segmenter class palette must be curated up-front.

---

## Decision 2: iOS-first, Android-ready architecture

**Date**: 2026-05-05
**Status**: accepted

### Context

The developer is on iOS and the existing GitHub issues label both iOS and Android as targets. Building both natively in parallel doubles cost without doubling learning. Building only iOS without portability planning would force a Kotlin re-derivation of all geometry and a re-collection of the segmenter dataset.

### Decision

Implement v1 on iOS only (Swift / SwiftUI / Vision / Core ML / ARKit / Core Motion / AVFoundation). Architect the system so an Android co-development effort can be added later without re-deriving the mathematics or re-training the segmenter:

- Pipeline contracts (card detector, segmenter, voxel carver, density lookup, macro calculator) are defined as platform-neutral interfaces with mathematically specified inputs and outputs.
- Core algorithms (voxel carving, projective geometry, FSAI carb formula) are written in pseudocode/maths in the spec, not in Swift-only constructs.
- Data formats (calibration record, segmentation mask, voxel grid, density table) are platform-neutral and serialised in portable representations (Protocol Buffers, FlatBuffers, or plain JSON/SQLite).
- The segmentation network is sourced from a framework with a clean Android port path (a single source-of-truth model exported to both Core ML and TFLite, e.g. via ONNX or TensorFlow).

### Rationale

The mathematics is inherently platform-neutral; only sensor APIs and inference runtimes differ between iOS and Android. Encoding that boundary explicitly in the spec means a future Android implementation re-implements only the platform-bound shell, not the algorithms.

### Alternatives Considered

- **Native both platforms simultaneously**: Rejected — doubles effort without halving time; v1 risk is in the maths and dataset, not the Swift/Kotlin split.
- **Cross-platform framework (Flutter, KMP, React Native)**: Rejected — vision/ML runtimes still need platform-specific bindings; cross-platform layer adds a debugging surface without removing the underlying split.
- **PWA + Capacitor**: Rejected by user — sensor and ML runtime access is too constrained for the required performance and accuracy targets.

### Consequences

**Positive:**
- Single iOS codebase to ship v1.
- Algorithms documented once; Android impl is mechanical translation.
- Segmenter and density tables shared verbatim across platforms.

**Negative:**
- Spec must avoid iOS-only abstractions in algorithm descriptions.
- Some duplication between Swift and future Kotlin shells.

---

## Decision 3: Segmentation via single small on-device network (Option C)

**Date**: 2026-05-05
**Status**: accepted

### Context

Shape-from-Silhouette voxel carving requires per-view binary masks of each food item. Three feasible approaches: classical segmentation (GrabCut, watershed, colour clustering); a small on-device deep network; or a cloud network. Classical methods do not generalise across cuisines; cloud calls violate the cost/compute objective and break offline use.

### Decision

Use a single small on-device segmentation network (≤ 10 MB quantised, MobileNetV3-DeepLab class or equivalent) as the only learned component. All other components (card detection, voxel carving, density lookup, carb maths) are deterministic. An optional cloud-validation fallback is permitted as a non-core, deferred extension (Option D), only invoked when the on-device pipeline rejects a capture or the user explicitly requests a second opinion.

### Rationale

A small semantic segmenter is the minimal learned component that lets the rest of the pipeline be deterministic geometry and lookups. Anthimopoulos 2014 used a Bag-of-Features SVM, which works but generalises poorly to new cuisines and lighting. A modern quantised MobileNet-class segmenter outperforms the BoF baseline at comparable on-device cost.

### Alternatives Considered

- **(A) Pure mathematics, no learning**: Rejected — would need user-drawn masks per food, unacceptable friction.
- **(B) Classical ML only (BoF SVM, density regressors)**: Rejected — generalisation across cuisines is poor.
- **(D) Add cloud fallback to the core path**: Rejected as core; permitted as a deferred opt-in extension only.

### Consequences

**Positive:**
- One learned component, well-bounded by size limit.
- Segmenter is the only artefact requiring training data; everything else is documented maths.
- Fully offline by default.

**Negative:**
- Segmenter class palette must be designed and curated.
- Out-of-palette foods produce an "unknown" class with degraded accuracy.

---

## Decision 4: Clinical features (AWAP, carb decay, CGM) descoped to specs/clinical

**Date**: 2026-05-05
**Status**: accepted

### Context

GitHub issues #7, #8, #9, #17, #24 describe a clinical layer over the carb-estimation core: an atomic event log with the AWAP cycle, an active-carb-load decay model, and OAuth2 sync with Dexcom/LibreView. These are clinically valuable but orthogonal to the photography → volume → carbs pipeline.

### Decision

Defer the clinical layer to a separate `specs/clinical` track. The research spec must include the data hooks that allow user-corrected ground truth and structured macro outputs to be persisted in a form the clinical track can consume, but it does not implement the AWAP cycle, the decay model, or CGM integration.

### Rationale

The carb-estimation pipeline is the technical risk concentration. Bundling clinical features dilutes focus and pushes the test surface beyond what is verifiable from a single research effort. The two tracks share data structures only; they do not share runtime concerns.

### Alternatives Considered

- **Bundle in a single spec**: Rejected — review burden too large; clinical features would block the carb-estimation milestone.
- **Cancel the clinical work entirely**: Rejected — it is the eventual product reason, just not the v1 risk surface.

### Consequences

**Positive:**
- Research spec stays focused on measurable mathematical contracts.
- Clinical work can proceed in parallel once data formats are stable.

**Negative:**
- Two specs to maintain.
- Some early decisions in research must anticipate clinical needs (e.g. immutable meal records, structured corrections).

---

## Decision 5: Accuracy target — <20% MAPE, ≤10 g MAE for v1

**Date**: 2026-05-05
**Status**: accepted

### Context

GoCARB clinical trials reported approximately 6 g mean absolute error in carbohydrate estimation. GitHub issue #6 referenced a <15% error target. The user must pick a v1 bar that is both honest about a greenfield effort and tight enough to test against.

### Decision

V1 accuracy target on a labelled internal test set: mean absolute percentage error (MAPE) below 20% and mean absolute error (MAE) at or below 10 grams of carbohydrate per meal photo. Confidence labelling is per-item; the meal-level error figures are reported on the aggregate carb total.

### Rationale

This bar is achievable for a greenfield voxel-carving pipeline at v1 and remains within the clinically useful range for type-1 diabetes carbohydrate counting (current manual estimation by patients commonly exceeds 20% error). Tightening the target later is a measurement question, not a redesign question.

### Alternatives Considered

- **GoCARB-equivalent (~6 g MAE)**: Rejected for v1 — sets up failure on first benchmark; tightens later once the pipeline is operational.
- **No numeric target until measured**: Rejected — leaves acceptance criteria ambiguous.

### Consequences

**Positive:**
- Clear go/no-go bar for v1.
- Comparable to literature.

**Negative:**
- A labelled test set must be assembled to measure against.

---

## Decision 6: Card behaviour — allow capture, mark low-confidence

**Date**: 2026-05-05
**Status**: accepted

### Context

The ID-1 reference card (85.60 × 53.98 mm, ISO/IEC 7810) gives a metric scale by detected pixel-to-mm ratio. With the iPhone 12 Pro+ floor (Decision 7) LiDAR also provides a metric scale natively. The two are complementary: card and LiDAR can cross-validate; either alone can carry the pipeline.

### Decision

If a card is detected, use its pixel-to-mm ratio for scale and additionally cross-check against LiDAR depth. If no card is detected but LiDAR depth is available, use LiDAR scale and mark the meal estimate as "no-card-confidence". If neither card nor LiDAR is available (a degraded state), refuse to compute and surface an actionable message.

### Rationale

LiDAR alone produces metric volume on iPhone 12 Pro+; the card adds an independent check. Forcing the card universally would lose users; allowing capture without the card with a confidence flag preserves utility and honesty about uncertainty.

### Alternatives Considered

- **Hard-require card**: Rejected — high friction; LiDAR makes the card non-essential for scale.
- **Fallback to known plate/utensil sizes**: Rejected — adds an additional vision burden for marginal benefit, given LiDAR baseline.

### Consequences

**Positive:**
- Honest confidence reporting.
- Card becomes a quality boost rather than a hard gate.

**Negative:**
- Two scale-source code paths to maintain.

---

## Decision 7: iPhone 12 Pro and later (LiDAR floor)

**Date**: 2026-05-05
**Status**: accepted

### Context

iPhone 12 Pro (October 2020) is the earliest iPhone with a rear-facing LiDAR sensor. ARKit scene reconstruction with LiDAR provides metric depth maps directly, materially improving voxel carving accuracy and removing the need to acquire two separate photographic views in well-conditioned cases. Without LiDAR, the pipeline collapses to two-view Shape-from-Silhouette, which still works but adds capture friction.

### Decision

V1 minimum hardware: iPhone 12 Pro, 12 Pro Max, 13 Pro and later Pro / Pro Max devices (any iPhone with rear LiDAR). iOS minimum: iOS 17.

### Rationale

LiDAR collapses the metric-scale problem and reduces capture from two views to (often) one view. The user accepts the smaller addressable audience for the precision improvement. Android co-development still uses two-view SfS as the canonical algorithm; the iOS implementation may opt to skip the second view when LiDAR depth is sufficient.

### Alternatives Considered

- **iPhone 11+ (no LiDAR)**: Rejected — the user explicitly chose the LiDAR floor for accuracy.
- **iPhone X+**: Rejected — A11 inference performance and no LiDAR.

### Consequences

**Positive:**
- LiDAR depth is a strong prior for voxel occupancy.
- Single-view capture often viable, reducing user friction.
- ARKit world tracking is available for two-view registration.

**Negative:**
- Smaller addressable audience.
- Android port cannot rely on LiDAR — must keep two-view SfS as portable canonical algorithm.

---

## Decision 8: Multi-food, distinct items (semantic segmentation per item)

**Date**: 2026-05-05
**Status**: accepted

### Context

Real meals are multi-component (e.g. chicken + rice + broccoli on one plate). Single-food v1 is sharply scoped but unrealistic. Multi-food via semantic segmentation requires the segmenter to label each pixel by food class; instance separation within a class is generally unnecessary for carbohydrate totals.

### Decision

V1 supports multi-food meals where each food is a distinct semantic class (rice, chicken, broccoli, etc.). The segmenter produces a class map; voxel carving runs per class; density and macro coefficients are looked up per class; per-class macros are summed to a meal total.

Composite dishes (stew, curry, mixed salad) are handled as a single composite class with a composite-density entry, treated as one food for v1 purposes.

### Rationale

Aligns with the literature (GoCARB segments per food class). Avoids instance segmentation cost. Composite dishes are common enough that excluding them halves real-world utility.

### Alternatives Considered

- **Single-food v1**: Rejected — too narrow.
- **Full instance segmentation**: Rejected — no benefit for carb totals; doubles model cost.

### Consequences

**Positive:**
- Realistic meal coverage.
- Per-class confidence reporting.
- Composite dishes covered via dedicated class entries.

**Negative:**
- Class palette must be curated and maintained.
- Out-of-palette foods produce an "unknown" class.

---
