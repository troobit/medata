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

## Decision 9: Visual hull is an upper bound; correct with support-plane closure, LiDAR top-surface, and per-class bulk factor

**Date**: 2026-05-06
**Status**: accepted

### Context

Pure Shape-from-Silhouette with a nadir + oblique view pair produces the visual hull (Laurentini 1994), which is provably a strict superset of the true food shape. Concavities (the dip in a bowl of curry, the gap between mashed-potato peaks), packing fraction (rice grains, granola), and internal voids (samosa, bread crumb) are never carved. The first draft of the requirements treated $V_c = |H_c| \cdot \Delta x \Delta y \Delta z$ as the true volume and piped it directly into $m = V \rho$. With a generic CoFID density that has not been calibrated against the visual hull, this is the single largest source of systematic over-estimation in the pipeline. Both reviewers (design-critic and peer-review-validator) flagged this as the single biggest accuracy risk and the principal load-bearing gap in v0.1. The literature reaching single-digit MAE (Dehais 2017, GoCARB) does so by either (a) calibrating per-class bulk densities against ground-truth meals, (b) applying per-class shape priors (cylinder / cone / hemisphere), or (c) augmenting silhouettes with metric depth.

### Decision

The pipeline acknowledges the visual-hull bound explicitly and corrects it with three combined mechanisms:

1. **Support-plane closure.** A detected support plane $\pi_{\text{sup}}$ (plate / table) bounds the carved set from below, removing the unbounded-downward defect.
2. **LiDAR top-surface intersection** (where available). The single-view path replaces back-projection with height-field integration between $\pi_{\text{sup}}$ and the LiDAR depth surface $z_{\text{top}}$. The two-view path uses LiDAR depth as an upper-bound constraint on retained voxels.
3. **Per-class bulk-correction factor $\beta_c$.** A unitless factor $\beta_c \in (0, 1]$ stored in the bundled database, calibrated against the v1 test set by minimising MAE per class. $\beta_c$ folds together residual hull bias, packing fraction, and internal-void bias into a single per-class number.

### Rationale

This three-part correction matches what the literature does in practice. LiDAR top-surface fitting alone (single-view path) produces a near-direct volume estimate. Support-plane closure alone (two-view path without LiDAR — the canonical Android algorithm) bounds the hull from below. The $\beta_c$ factor absorbs the residual gap and is empirically calibrated, which is honest about the fact that the visual hull is not the true volume. Unlike pure shape priors (cylinder / cone), $\beta_c$ does not impose a geometric assumption per food and so generalises across the class palette.

### Alternatives Considered

- **Pure shape priors (cylinder, cone, hemisphere) per class**: Rejected — requires hand-coded geometric assumption per class; brittle for irregular foods (broccoli, salad, mashed potato); does not compose with multi-class ownership.
- **Calibrate the bundled densities themselves against the visual hull**: Rejected — silently turns CoFID-attributed densities into project-internal numbers, breaking the bundled-database provenance. Keeping density as published and putting the correction in $\beta_c$ preserves database integrity.
- **Acknowledge the bias but do not correct it; trust the test set to demonstrate small enough bias**: Rejected — first-measurement risk is too high; literature gives no reason to believe uncorrected hull volumes hit a 10 g MAE bar.

### Consequences

**Positive:**
- Mathematical pipeline matches reality of silhouette-based reconstruction.
- $\beta_c$ is database-level, so improvements (better calibration, more test data) flow through without code changes.
- Density values in the bundled DB stay attributable to CoFID / IFCDB.

**Negative:**
- $\beta_c$ calibration must be performed before the v1 accuracy bar can be met; this couples segmenter-readiness to test-set-readiness.
- $\beta_c$ calibration and accuracy evaluation must be on disjoint subsets of the test set (cross-validation procedure required) to avoid trivial overfit.
- **Segmenter-β_c coupling.** $\beta_c$ is calibrated against the specific segmenter checkpoint that produced the cached probability tensors. Retraining the segmenter (e.g. for v1.1) invalidates every $\beta_c$ and requires full recalibration on the gravimetric test set. The design (§6.6) tightens the silhouette test from `argmax = background → discard` to `(1 − q[background]) ≥ τ_sil = 0.5` so $\beta_c$ absorbs only shape bias, not segmenter boundary-confidence calibration; the residual coupling cannot be fully eliminated and is documented in `design.md` §6.9.

### Impact

Affects Req 9 (volume estimation), Req 11 (database now contains $\beta_c$ per class), Req 12 (mass formula uses corrected volume), Req 21 (test harness must perform $\beta_c$ calibration on a disjoint subset).

---

## Decision 10: Single-view depth-augmented path is height-field integration, distinct from voxel carving

**Date**: 2026-05-06
**Status**: accepted

### Context

Decision 7 established the LiDAR floor and noted that the iOS implementation may skip the second view when LiDAR depth is sufficient. The first draft of the requirements left the single-view algorithm under-specified, implying it was a degenerate variant of voxel carving. Both reviewers pointed out that a single silhouette plus a depth surface does not produce a closed volume by silhouette back-projection alone — at least not without a closure assumption — and that calling it "depth-augmented Shape-from-Silhouette" obscures the fact that it is a different algorithm with different error characteristics. The two-view path also remains the canonical Android-portable algorithm (Decision 2 + Decision 7) so single-view choices on iOS must not entangle with the two-view contract.

### Decision

The single-view path (`capturePath = single_view_lidar`) is specified as **height-field integration**: for each class's nadir-view pixels, integrate the height between the support plane $\pi_{\text{sup}}$ and the LiDAR-observed top surface $z_{\text{top}}(p)$ over the metric pixel area at the food plane. This is not voxel carving and is documented as a separate algorithm in Req 9.4. The two-view path (`capturePath = two_view_sfs`) is voxel carving with support-plane closure as specified by Dehais 2017 §III.D, and remains the canonical algorithm for Android.

### Rationale

Height-field integration is the natural algorithm when you have a metric top surface and a metric bottom plane; it is more accurate than visual-hull carving when those two surfaces are reliable. Distinguishing it explicitly in the contract prevents conflation with voxel carving and lets each path declare its own latency budget, error model, and confidence value. Persisting `capturePath` in the meal record makes the choice auditable per meal.

### Alternatives Considered

- **Treat single-view as a degenerate voxel carve with one silhouette**: Rejected — produces an open volume in directions perpendicular to the nadir view; closure rules become ad hoc.
- **Disallow single-view; require two views always**: Rejected — sacrifices the LiDAR advantage on iPhone 12 Pro+ and adds capture friction without accuracy benefit.

### Consequences

**Positive:**
- Each path has a clean, separately specified algorithm and latency budget.
- Single-view path is materially faster and more accurate when LiDAR coverage is good.
- `capturePath` lets the clinical track and downstream analytics treat the two paths' error distributions distinctly.

**Negative:**
- Two algorithms to maintain instead of one.
- Re-derivation across paths (e.g. re-running an old meal with a new $\beta_c$) must dispatch on `capturePath`.

---

## Decision 11: Multi-class voxel ownership by per-pixel argmax over segmenter probabilities

**Date**: 2026-05-06
**Status**: accepted

### Context

Real meals (pasta with sauce, rice with curry, broccoli with melted cheese) produce overlapping silhouettes from any view. Without an explicit ownership rule, the same voxel can land inside two classes' silhouettes from each view and contribute mass to both, double-counting carbohydrates. The first-draft requirements specified per-class carving but did not state how an overlap was resolved.

### Decision

The ownership rule is path-specific:

- **Single-view path:** each nadir-view pixel is assigned to exactly one class by per-pixel argmax over the segmenter's class probability vector.
- **Two-view path:** each voxel $v$ is assigned the class $c^*(v) = \arg\max_c [\mathbf{q}_1(v)]_c \cdot [\mathbf{q}_2(v)]_c$ where $\mathbf{q}_1, \mathbf{q}_2$ are the segmenter probability vectors at the voxel's projection in each view. Voxels whose top probability product falls below a documented threshold $\tau_v$ (default 0.04 — both views agreeing on a class with probability ≥ 0.2) are discarded as class-ambiguous, and the discarded fraction is persisted with the meal record.

No voxel and no nadir-view pixel contributes mass to more than one class.

### Rationale

Per-pixel argmax does not lift cleanly to 3D voxels in the two-view path because a voxel projects to two different pixels with potentially different argmax classes. The probability-product rule is the natural extension: it is a Naïve-Bayes-style score that selects the class with the highest joint score under a **conditional-independence approximation** of the two views' segmenter probabilities given the true class. **The two views are not strictly conditionally independent** — they observe the same physical food under correlated lighting, processed by the same segmenter network — so the rule is a heuristic, not a maximum-likelihood class. In practice the heuristic produces a stable partition: we use it as a deterministic ownership rule rather than as a probabilistic claim. The threshold $\tau_v$ catches voxels where neither view agrees strongly — those are most likely class-boundary noise rather than physical food and are better discarded than mis-assigned. Fractional allocation by class probability was considered but rejected for v1 because it complicates the mass formula and the auditability of per-class breakdowns without strong evidence of accuracy gain.

### Alternatives Considered

- **Fractional voxel allocation by per-pixel class probability**: Rejected — splits a single voxel's mass across two classes, complicating the per-class breakdown; gain over argmax is unproven.
- **Depth-ordering allocation (front class wins)**: Rejected — depth ordering is not always available across both paths and conflicts with the segmenter's own class signal.
- **Mutual-exclusion in the segmenter (instance segmentation)**: Rejected per Decision 8 — instance segmentation doubles model cost without benefit for carb totals.

### Consequences

**Positive:**
- Deterministic, testable rule.
- Compatible with both single-view and two-view paths.
- Direct use of segmenter probabilities, no extra signal needed.

**Negative:**
- A class slightly less probable at a pixel gets zero mass from it, even if the segmenter is uncertain — this is absorbed by the per-class confidence and the mIoU bar in [8.9].

---

## Decision 12: Liquids and semi-liquids excluded from v1

**Date**: 2026-05-06
**Status**: accepted

### Context

Soup, smoothies, milk, yoghurt, custard, gravy and clear liquids (water, tea, fruit juice) are common in real meals but break the pipeline at multiple layers: clear liquids have no opaque silhouette and confound LiDAR (specular surfaces); opaque liquids violate the constant-density assumption since the volume is dominated by container shape, not the food's intrinsic structure; both produce unreliable segmenter output because the food/background boundary is ambiguous. The first-draft requirements did not address this, leaving liquid handling implicit and the v1 accuracy bar at risk on any meal containing them.

### Decision

Liquids and semi-liquids are out of scope for v1. The segmenter palette includes an `unsupported_liquid` class that catches them; pixels assigned to that class are excluded from volume estimation and the meal is flagged with an Irish-English message stating that liquids are not estimated in v1.

### Rationale

Excluding a known-broken category is more honest than producing wrong numbers for it. The `unsupported_liquid` class lets the segmenter learn the visual signature of common liquids and gracefully degrade rather than mis-classify them as a solid food. Liquids can be re-evaluated post-v1 with a dedicated container-detection sub-pipeline if user demand justifies the engineering.

### Alternatives Considered

- **Best-effort estimation for opaque liquids using container shape**: Rejected — requires container detection and shape-fitting (cylindrical bowls, mugs), a separate geometric problem; v1 risk-budget cannot absorb it.
- **Silently process liquids alongside solids**: Rejected — produces large carb errors on meals that contain a glass of fruit juice, masking accuracy on the rest of the pipeline.

### Consequences

**Positive:**
- v1 accuracy bar is measurable on meals where the pipeline is competent.
- User gets an explicit message rather than a wrong number.

**Negative:**
- Smoothies, soups and similar real-world meals are not estimated in v1.
- An additional segmenter class (`unsupported_liquid`) takes labelling effort without producing an estimate.

---

## Decision 13: Per-path latency budgets (single-view 1000 ms, two-view 1800 ms)

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements set a single 1000 ms P95 latency budget end-to-end. With per-stage budgets of 100 ms (card detect) + 250 ms (segmenter) + 300 ms (voxel carve), the canonical two-view path runs card detect twice, segmentation twice, plus mask matching, scale resolution, support-plane fit, macro lookup, persistence and UI commit — already exceeding 1000 ms before any P95 variance. The 1000 ms bar is realistic for the single-view LiDAR path (one card detect + one segmenter pass + height-field integration + lookups) but unattainable for the two-view path. Decision 2 + Decision 7 keep the two-view path as the Android-canonical algorithm, so applying a 1000 ms cap globally implicitly forbids the canonical Android path, breaking the portability commitment.

### Decision

Latency budgets are stated per `capturePath`:

- `single_view_lidar`: under 1000 ms at the 95th percentile on the v1 hardware floor.
- `two_view_sfs`: under 1800 ms at the 95th percentile on the v1 hardware floor.

Per-stage budgets are listed explicitly in Req 16.2 (single-view) and 16.3 (two-view) such that the sum plus headroom fits the path's P95 cap.

### Rationale

Two distinct algorithms with different cost profiles deserve distinct budgets. 1000 ms remains the user-facing fast path; 1800 ms remains comfortably under "user gives up" thresholds for the two-view path and aligns with what the canonical Android implementation will achieve on equivalent hardware. Card detection runs twice on the two-view path (one card per view) and the segmenter runs twice — these are the dominant cost increases that must be explicit.

### Alternatives Considered

- **Single 1000 ms cap, optimise both paths to fit**: Rejected — would force segmenter latency below 250 ms or skip the per-view card detect; both compromises accuracy.
- **Single 1800 ms cap for both paths**: Rejected — slows the iOS-flagship single-view path unnecessarily and weakens the user-facing performance promise.

### Consequences

**Positive:**
- Latency arithmetic closes for both paths.
- Each path's P95 cap is achievable and CI-testable.
- Android port does not inherit an iOS-specific budget.

**Negative:**
- Two CI thresholds to maintain.

---

## Decision 14: Segmenter mIoU floor of 0.60 averaged across food classes

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements specified segmenter size (≤ 10 MB) and latency (≤ 250 ms per view) but no accuracy bar. Without one, segmenter regressions could be masked by compensating $\beta_c$ adjustments, the mIoU bar would be undefined, and the end-to-end accuracy bar (MAPE < 20%, MAE ≤ 10 g) would have no decomposition into component bars. A 10 MB segmenter with 50% mIoU on a 24-class palette will not deliver the end-to-end target.

### Decision

The segmenter SHALL meet a minimum mean Intersection-over-Union of 0.60 averaged across the 24 food classes (excluding `background`, `unknown_food`, `unsupported_liquid`) on a held-out segmenter test set, evaluated separately from the end-to-end carb-error bar.

### Rationale

0.60 mean food-class mIoU is achievable for a quantised MobileNet-class semantic segmenter on a 24-class food palette given a reasonable training set (a few thousand instances per class). It is high enough that the end-to-end carb-error bar is plausibly attainable (segmenter errors propagate to volume errors at roughly 1:1 for compact foods). It also gives the design phase a concrete target to size the model and the dataset against.

### Alternatives Considered

- **No segmenter-level bar; trust end-to-end MAPE/MAE**: Rejected — couples segmenter and density investigation; regressions are hard to localise.
- **Higher mIoU bar (≥ 0.75)**: Rejected — pushes model size, latency, and training-data cost above v1 budget.

### Consequences

**Positive:**
- End-to-end accuracy bar decomposes into segmenter and density components.
- Segmenter regressions are detectable in isolation.
- Target informs model architecture and dataset size decisions in design.

**Negative:**
- Held-out segmenter test set must be curated and maintained alongside the end-to-end test set.

---

## Decision 15: Photo retention default — 30 days

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements set the default photo retention period to "indefinite", with the rationale that the user-correction hooks (Req 14) should remain meaningful. The Req 17 user story, however, explicitly says "I want my food photographs to stay on my device" — indefinite retention serves the future clinical track, not the user's stated intent. Both reviewers flagged the contradiction.

### Decision

The default photo, depth, and mask retention period is 30 days. After 30 days, the per-meal artefact directory is deleted but the macro values, confidences and metadata remain in the SQLite database indefinitely. Users can change retention to 90 days, 365 days, or "retain indefinitely (clinical-track participation)" via a setting; users can manually delete any individual meal's artefacts at any time.

### Rationale

30 days covers the realistic correction-window for most users (carb estimates that turned out wrong in a meal-replay scenario) while honouring the privacy expectation set by the user story. Clinical-track participation is opt-in and explicit, which is the appropriate gate for retaining sensitive imagery. Macro values stay in the database forever because they are small, non-sensitive, and necessary for the clinical track even after raw artefacts are deleted.

### Alternatives Considered

- **Indefinite default (first draft)**: Rejected — contradicts user story; biases default toward research-data collection over user privacy.
- **7-day default**: Rejected — too short to support correction workflows.
- **Delete on macro persistence (no retention)**: Rejected — eliminates the audit and re-derivation use case in [12.7].

### Consequences

**Positive:**
- Default aligns with user story.
- Clinical-track data remains available for participants who opt in.
- Macro records remain available indefinitely without retaining sensitive imagery.

**Negative:**
- A retention scheduler must run and delete artefacts on schedule.
- Re-derivation of an old meal with a new $\beta_c$ requires the original frames, which may no longer exist past 30 days.

---

## Decision 16: ID-1 metric scale recovered by Perspective-n-Point, not edge ratio

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements derived the metric scale from "the long-edge length and the known 85.60 mm physical dimension, after rectifying the quadrilateral to the camera plane using the calibration intrinsics". Both reviewers pointed out that this is geometrically wrong: the long-edge pixel count gives correct scale only for a fronto-parallel card. From a 25° oblique view (Req 3.3) the long edge foreshortens, and rectification with intrinsics alone is insufficient — recovery of the card's pose requires solving Perspective-n-Point with the four corners and the known 85.60 × 53.98 mm dimensions. The card sits in the support plane, not the camera plane, and the food sits above the support plane, so the card-derived scale must also be lifted to the food plane via the food's mean height above the support plane.

### Decision

The card detector recovers the 6-DOF pose of the card by solving PnP with the four detected corners, the known dimensions, and the calibration intrinsics. The metric scale $s_{\text{card}}$ is defined at the food plane (parallel to the card / support plane, offset by the food's mean height above $\pi_{\text{sup}}$).

### Rationale

PnP is the standard solution and is supported across vision frameworks on both iOS (Vision / OpenCV) and Android (OpenCV) without specialised libraries. Lifting scale to the food plane addresses the geometric reality that food sits above the card; without that lift, the scale carries a 5–15% systematic error proportional to food height.

### Alternatives Considered

- **Edge-ratio scale (first draft)**: Rejected — geometrically wrong on oblique views.
- **Use only LiDAR scale, drop the card path**: Rejected — Decision 6 already commits to the card as a cross-check on LiDAR; without it the LiDAR scale has no independent validation.

### Consequences

**Positive:**
- Card-derived scale is geometrically correct from any reasonable viewing angle.
- PnP recovers two scale values: $s_{\text{card,init}}$ at the card plane (drives the iterative support-plane fit on the card-only/no-LiDAR path) and $s_{\text{card}}$ at the food plane (consumed by the metric scale resolver).
- PnP residuals are persisted with the meal record for clinical-track analysis (informational; not a v1 sub-confidence input — see Decision 17 / Req 13.1).

**Negative:**
- More compute per card detection (PnP solve), but well within the 80 ms budget.
- The card-only/no-LiDAR path requires a small fixed-point iteration to resolve the metric scale and the support plane jointly (see Req 4.3).

---

## Decision 17: Confidence combination is the geometric mean of three sub-confidences

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements specified the combination function as "the product (or another documented combination function)". This is two distinct contracts in one clause; the threshold of 0.6 in Req 13.5 depends on which one is chosen, and both reviewers flagged the requirement as untestable as written.

### Decision

The per-meal confidence is the geometric mean of three sub-confidences:

$$\sigma_{\text{meal}} = (\sigma_s \cdot \sigma_{\text{seg}} \cdot \sigma_{\text{geom}})^{1/3}$$

where $\sigma_s$ is metric-scale sub-confidence, $\sigma_{\text{seg}}$ is the segmenter mean class probability over food pixels, and $\sigma_{\text{geom}}$ is the geometric-completeness sub-confidence whose values are tabulated in Req 13.2.

### Rationale

Geometric mean (cube root of the product) is more readable as a confidence than a raw product (it stays in roughly the same numeric range as the inputs), is symmetric in the three sub-confidences, and is monotonically equivalent to the product so the 0.6 threshold remains meaningful. It is testable against fixed input vectors.

### Alternatives Considered

- **Product**: Rejected — collapses fast (three 0.85 inputs give 0.61), making the 0.6 threshold close to a default-fail trip.
- **Min**: Rejected — discards information from the other two inputs.
- **Weighted sum**: Rejected — weights are arbitrary without empirical grounding; a future spec revision can move to a learned weighting if the test set supports it.

### Consequences

**Positive:**
- Single, testable function.
- Stays in a readable [0,1] range.
- Threshold of 0.6 in Req 13.5 has a defensible interpretation.

**Negative:**
- Function is fixed at the requirement layer; revising it post-v1 needs a new decision.

---

## Decision 18: Voxel grid sized for a 270 mm dinner plate, default edge 3 mm

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements specified a $128^3$ voxel grid with 2 mm edge length, giving a 256 mm cube. A typical dinner plate is 270 mm in diameter — the grid was smaller than the plate it claimed to cover. Both reviewers flagged the inconsistency.

### Decision

Horizontal extent: dynamically sized to cover the union of food silhouettes back-projected to the support plane, plus a 30 mm margin, capped at 360 mm × 360 mm. Vertical extent: 12 cm above the support plane. Default voxel edge length: 3 mm. With these values the worst-case grid is $120 \times 120 \times 40 = 576{,}000$ voxels — comparable to $128^3 = 2{,}097{,}152$ but oriented for a flat plate footprint, not a cube.

### Rationale

3 mm edge length is the design-phase sensitivity-study midpoint and is sufficient to resolve a typical food region (a piece of broccoli ~30 mm produces ~10 voxels per dimension). 360 mm horizontal extent covers a 270 mm dinner plate plus a 45 mm margin per side. 12 cm vertical extent covers typical food-on-plate heights (most foods sit under 8 cm; 12 cm absorbs piled rice / pasta).

### Alternatives Considered

- **Fixed $128^3$ grid (first draft)**: Rejected — too small horizontally for a dinner plate; wastes voxels vertically.
- **2 mm edge length default**: Rejected for v1 default — pushes voxel count to 1.3M, harder to fit the latency budget; revisit in design sensitivity study.

### Consequences

**Positive:**
- Grid actually contains the food it intends to carve.
- Voxel count is bounded and the 300 ms two-view-carve budget is achievable.

**Negative:**
- Larger horizontal grid means more carving work in the worst case; offset by the lower voxel count overall.

---

## Decision 19: Database is SQLite (FlatBuffers rejected for v1)

**Date**: 2026-05-06
**Status**: accepted

### Context

The first-draft requirements offered "SQLite or FlatBuffers" as the bundled database format. Both reviewers pointed out that this is two different schemas, two different read paths, and two different update stories. v1 cannot ship one of either; it must commit.

### Decision

The bundled food database is a single SQLite file. The schema is documented and used verbatim on iOS and Android.

### Rationale

SQLite has first-class support on both platforms, supports the optional IFCDB overlay via attached databases or schema flags, and admits versioning via `PRAGMA user_version`. FlatBuffers is faster for read-heavy random-access workloads but the database is small (≤ 30 classes), read once at startup, and not on the hot path; FlatBuffers' performance edge is irrelevant. SQLite's debuggability (sqlite3 CLI on either platform) is materially more valuable.

### Alternatives Considered

- **FlatBuffers**: Rejected — performance edge is irrelevant for this database size; toolchain on Android adds friction.
- **JSON**: Rejected — no schema enforcement; types and units are easy to corrupt across hand-edits.
- **Embedded in-code as Swift/Kotlin static data**: Rejected — kills the "single source of truth across platforms" objective.

### Consequences

**Positive:**
- One format, one schema, two-platform interoperability out of the box.
- Standard tooling (sqlite3 CLI, DB Browser).

**Negative:**
- Slightly slower startup than a pre-parsed FlatBuffers file; immaterial at this size.

---

## Decision 20: β_c calibration requires ≥30 calibration meals per class; uncalibrated classes default to β = 1.0

**Date**: 2026-05-06
**Status**: accepted

### Context

Decision 9 introduced $\beta_c$ as a per-class bulk-correction factor calibrated against the v1 test set. Both reviewers of the v0.2 draft flagged that with 24 classes, a realistic v1 test set will not yield enough meals per class to fit a defensible scalar — fitting noise produces unstable $\beta_c$ values that then drive the v1 accuracy bar. The first draft did not specify a minimum sample size or a fallback behaviour for under-represented classes. Without one, the bundled database silently ships with overfit $\beta_c$ values for sparse classes, the accuracy bar is invalid for those classes, and the whole pipeline is held hostage to dataset coverage that may not be achievable in v1.

### Decision

A class $c$ is considered calibrated only if the calibration subset of the test set contains at least 30 meals in which class $c$ is present and gravimetrically weighed. Classes that do not meet this bar receive $\beta_c = 1.0$ and are flagged `uncalibrated` in the bundled database. The design document MAY define a class-pooled β as a softer fallback than 1.0 (a single β computed across all uncalibrated classes' calibration meals together). Each meal record persists a per-class `betaCalibrationStatus` field with values `calibrated`, `uncalibrated_pooled`, or `uncalibrated_unity`, and the v1 accuracy bar reports per-class statistics distinguishing calibrated from uncalibrated classes.

### Rationale

30 meals per class is the standard rule-of-thumb minimum for a single-parameter scalar fit to be reasonably stable; a tighter bar would block too many classes; a looser bar admits noise. Defaulting uncalibrated classes to 1.0 is the most conservative choice — it leaves the visual hull uncorrected and surfaces the systematic bias rather than burying it in a fitted noise term. The pooled fallback is offered as an optional softer middle ground for the design phase to evaluate. The `betaCalibrationStatus` field makes the limitation auditable per meal.

### Alternatives Considered

- **No minimum sample size; fit β_c on whatever data is available**: Rejected — silently overfits noise; accuracy bar interpretation depends on hidden dataset coverage.
- **Single global β across all classes**: Rejected — defeats the purpose of $\beta_c$ being per-class; foods with very different concavity / packing characteristics would share a poor compromise factor.
- **Bar release on full calibration of all 24 classes**: Rejected — couples the v1 release to a dataset target that may slip indefinitely; the application can ship usefully with some classes uncalibrated and the user surfaced the limitation per-class.

### Consequences

**Positive:**
- β_c values that ship are statistically defensible.
- Uncalibrated classes are surfaced explicitly rather than silently producing biased estimates.
- v1 release is not blocked on dataset completeness for every class.

**Negative:**
- Some classes ship uncalibrated at v1; the user-facing carb estimate for those classes carries the visual-hull upward bias.
- Per-class accuracy reporting adds complexity to the test harness.

### Impact

Affects Req 11.7 (calibration sample size), Req 21.4 (test-set partitioning), the meal record schema (`betaCalibrationStatus` field), and the v1 release readiness criteria.

---

## Decision 21: Confidence sub-confidences floored at ε = 0.05 before geometric mean

**Date**: 2026-05-06
**Status**: accepted

### Context

Decision 17 fixed the confidence combination function as the geometric mean of three sub-confidences. v0.2 review flagged that any sub-confidence of 0 forces $\sigma_{\text{meal}} = 0$ regardless of the other two, discarding meaningful signal. The segmenter's mean class probability $\sigma_{\text{seg}}$ can floor near 0 in regions of severe ambiguity; the `unknown_food` path explicitly outputs confidence 0; geometric inputs near 0 are also possible from very poor LiDAR coverage. The geometric mean is also undefined when an input is negative — bounds need to be enforced explicitly.

### Decision

Each sub-confidence input ($\sigma_s$, $\sigma_{\text{seg}}$, $\sigma_{\text{geom}}$) is floored at $\varepsilon = 0.05$ before being combined: $\tilde{\sigma}_x = \max(\varepsilon, \sigma_x)$. The combined $\sigma_{\text{meal}}$ therefore lies in $[\varepsilon, 1]$, never 0. Cases where the system should refuse to compute (no food pixels, < 50% LiDAR coverage on single-view path, no scale signals) are handled by refusal, not by emitting a 0-confidence estimate.

### Rationale

Flooring preserves information from non-zero sub-confidences while still penalising the meal severely when one sub-confidence is poor. ε = 0.05 means a single very-bad sub-confidence drops the geometric mean to at most $0.05^{1/3} \approx 0.37$ when the other two are perfect — well below the 0.6 user-prompt threshold (Req 13.5), so the user is correctly prompted to recapture without the value collapsing to a meaningless 0. Refusal is reserved for failure modes where no useful number can be produced; the confidence is meant to span the "compute it but be honest about uncertainty" space.

### Alternatives Considered

- **No flooring (first draft)**: Rejected — single 0 input collapses the entire confidence regardless of the other inputs; loses information.
- **Floor at a higher ε (e.g. 0.2)**: Rejected — too generous; a meal with one sub-confidence at 0 should not produce a final confidence above 0.5.
- **Use min instead of geometric mean**: Rejected per Decision 17 (discards information from the other two sub-confidences).

### Consequences

**Positive:**
- σ_meal is always in [ε, 1], well-defined for all valid inputs.
- The 0.6 user-prompt threshold remains meaningful.
- A single bad sub-confidence still produces an informative low confidence, not a meaningless 0.

**Negative:**
- ε is a magic number; revisiting it post-v1 needs a new decision.

---

## Decision 22: Single-view path acknowledges inter-class occlusion as a known limitation

**Date**: 2026-05-06
**Status**: accepted

### Context

The single-view height-field integration path sums volume only over class-c nadir-view pixels. Food behind taller food in the nadir view (rice partially occluded by a chicken breast) contributes zero to the rice volume because the occluded pixels never receive a `rice` segmenter label. β_c cannot recover this — it is per-class, not per-occlusion. The two-view path partially recovers occluded food via the oblique view's silhouette. v0.2 review flagged this as a silent under-counting failure mode.

### Decision

Inter-class occlusion is acknowledged as an explicit limitation of the single-view path (Assumption 5 in the requirements introduction). When inter-class occlusion is detected (heuristic: a class boundary in the nadir mask shares a depth discontinuity > 10 mm with another class within 5 px), the geometric-completeness sub-confidence factor $\sigma_{\text{occl}}$ is reduced to 0.80, which propagates through the geometric-mean confidence and triggers the user-prompt threshold; the user is prompted to recapture using the two-view path. The two-view path uses $\sigma_{\text{occl}} = 1.00$ because the oblique view recovers most occluded regions.

### Rationale

The limitation is intrinsic to height-field integration from a single nadir view — no algorithmic correction is possible without a second view or a semantic prior. Surfacing it via confidence reduction is the honest path: the user is informed that the estimate is degraded and offered the two-view recapture as a remedy. The detection heuristic (depth discontinuity at class boundary) is cheap to compute from data already available in the pipeline (LiDAR depth + segmenter mask).

### Alternatives Considered

- **Disallow single-view path when occlusion is detected**: Rejected — too aggressive; many occlusion cases produce only minor under-counting and the user gains little from a forced recapture.
- **Use a class-pair occlusion-correction factor**: Rejected — requires per-class-pair calibration data v1 cannot afford.
- **Silently accept the under-counting**: Rejected — masks a known systematic error.

### Consequences

**Positive:**
- A known systematic bias is surfaced to the user.
- The two-view path becomes the recommended fallback for complex meals.

**Negative:**
- Occlusion detection adds a small compute cost (within the single-view 80 ms budget).
- Some users will see frequent recapture prompts on busy plates; this is acceptable for v1 honesty.

---

## Decision 23: Acceptance bar is point estimate; CI is reporting-only

**Date**: 2026-05-06
**Status**: accepted

### Context

Req 21.3 fixes the v1 acceptance bar at MAPE < 20% AND MAE ≤ 10 g; Req 21.8 mandates reporting a confidence interval when the test set is too small for a 95% CI on the bar. v0.2 review flagged that the bar can be interpreted two ways: as a point estimate, or as the upper bound of the reported CI. The two interpretations have very different implications for how thin a test set the project can ship with.

### Decision

The v1 acceptance bar is the point estimate. The CI per Req 21.8 is reported alongside the point estimate but does not change the bar. A test set producing a point estimate of MAPE = 18% with a wide CI passes; a point estimate of 21% with a tight CI does not pass.

### Rationale

A point-estimate bar is operationally simpler and matches how the literature reports food-volume accuracy (Dehais 2017, GoCARB). The CI is published transparency for honest interpretation, not a moving acceptance line. Using the upper CI bound as the bar would push the project toward a much larger test set than v1 can afford, with the practical effect of blocking release on dataset coverage rather than on system accuracy.

### Alternatives Considered

- **Upper CI bound must satisfy the bar**: Rejected — couples release to test-set size, not to system performance; v1 cannot afford the data.
- **Lower CI bound must satisfy the bar**: Rejected — lower bound is always more lenient than the point estimate; offers no additional rigour over the point estimate alone.
- **Drop the CI requirement**: Rejected — the CI is valuable transparency; users and clinicians should know how confident the headline number is.

### Consequences

**Positive:**
- Acceptance is operationally testable from a small test set.
- CI publication keeps interpretation honest.

**Negative:**
- A point-estimate bar from a small test set has high variance; a marginal pass on one dataset realisation may have failed on another.
- This is mitigated by the cross-validation procedure in Req 21.4 and by reporting per-class statistics in Req 21.4.

---

## Decision 24: Palette migration preserves original class assignments

**Date**: 2026-05-06
**Status**: accepted

### Context

The palette is fixed at 24 food classes for v1 (Req 8.4) but the database and palette are released as a versioned pair (Req 11.4) and the meal record persists the database edition (Req 11.9). v0.2 review flagged that no requirement specifies what happens to existing meal records when palette v2 splits, merges, or renames classes. Without explicit migration semantics, a re-derivation under v2 could silently remap a v1 `rice` class to either v2 `white_rice` or v2 `brown_rice` without the user knowing which.

### Decision

When a newer palette / database version splits, merges, or renames classes, the system preserves the original class assignments on existing meal records and does not silently remap. Re-derivation of an existing meal under a newer palette is permitted only if the design document specifies an explicit class mapping (e.g. v1 `rice` → v2 `white_rice`) and the user is informed that the record has been re-derived. Meals whose original class has no mapping in the new palette remain on the old palette / database edition for that class.

### Rationale

Silent remap destroys the audit trail — a clinical-track analysis that aggregates carb totals across a date range would silently shift if the underlying class assignments changed. Explicit mappings (with user awareness) preserve provenance while still allowing the fleet to migrate when the palette improves. Keeping unmappable classes on the old database edition is the only safe option short of discarding the meal.

### Alternatives Considered

- **Always remap to the closest new class by name**: Rejected — fuzzy matching introduces silent errors; "rice" → "rice_pilaf" is wrong.
- **Force re-capture under the new palette**: Rejected — destroys data the user has already provided.
- **Discard meals with unmappable classes**: Rejected — destroys audit history; user has no recourse.

### Consequences

**Positive:**
- Meal records are stable across database / palette upgrades.
- Re-derivation is opt-in and transparent.
- Old classes can coexist with new palette in the same SQLite database.

**Negative:**
- The runtime must dispatch density / coefficient lookups by `databaseEdition` per meal, not by the latest version globally.
- Palette upgrades require a per-class mapping file in the design document.

---

## Decision 25: Segmenter base architecture is DeepLabV3 + MobileNetV3-Large at 513² input

**Date**: 2026-05-07
**Status**: accepted

### Context

Req 7.1 (now Req 8.1) names "MobileNetV3-DeepLab class or equivalent" but defers the specific architecture to design. The design must select a single architecture so that training-data acquisition (Req 20), the mIoU bar (Req 8.9), the size budget (Req 8.2 ≤10 MB), and the latency budget (Req 8.3 ≤250 ms) are all measurable against one target. The choice must export cleanly to both Core ML (iOS) and TFLite (Android) per Decision 2.

### Decision

V1 segmenter is **DeepLabV3 with MobileNetV3-Large backbone**, FP16 weight-compressed, input resolution 513×513 (aspect-preserving letterbox per Req 8.8). The training pipeline is PyTorch with `torchvision.models.segmentation.deeplabv3_mobilenet_v3_large` as the starting checkpoint, fine-tuned on FoodSeg103 + project-internal UK/Irish food images for the 24-class palette plus 3 special classes.

### Rationale

DeepLabV3 + MobileNetV3-Large is the smallest mainstream segmenter that consistently hits ≥0.60 mIoU on multi-class food datasets (FoodSeg103 baseline papers report ~0.40 mIoU for non-pre-trained networks; transfer learning from ImageNet + DeepLabV3 head closes the gap). The pretrained checkpoint exists in torchvision, exports cleanly via `coremltools.convert(...)` to Core ML and via `ai-edge-torch` to TFLite, and runs on the A14 Apple Neural Engine in FP16 within budget. 513² is the established DeepLab input size; smaller resolutions trade accuracy for latency below the mIoU bar.

### Alternatives Considered

- **BiSeNet / FastSCNN**: Faster but with materially lower mIoU on multi-class food data; would risk the 0.60 mIoU bar.
- **U-Net variants**: Larger parameter count; harder to fit the 10 MB ceiling without aggressive quantisation that hurts mIoU.
- **MobileNetV3-Small backbone**: Smaller and faster but mIoU ceiling on 27 classes is below 0.60 in the literature.
- **Vision Transformer (MobileViT, etc.)**: Faster compute but transformer ops have weaker Core ML / TFLite support; risk of CPU/GPU fallback knocks the 250 ms budget.

### Consequences

**Positive:**
- Pretrained ImageNet checkpoint and a torchvision-supported architecture; no custom architecture code required.
- Clean export path to both Core ML and TFLite.
- Hits all three constraints (size, latency, mIoU) with conventional training.

**Negative:**
- 513² is larger than some real-time mobile segmenters; latency margin is tight on iPhone 12 Pro (A14).
- Letterbox padding wastes ~10–20% of the model's compute on background pixels for non-square photos.

---

## Decision 26: Voxel carving and height-field integration run as Metal compute shaders

**Date**: 2026-05-07
**Status**: accepted

### Context

Volume estimation runs at 576k voxels for the two-view path (Req 9.3) with two view back-projections per voxel and a voxel-ownership probability product across two probability tensors. The two-view P95 budget per Req 16.3 is 300 ms. A pure CPU implementation using Accelerate vDSP is plausible but tight; a Metal compute shader is the conservative choice and lets the segmenter and carve overlap on different processors (segmenter on ANE, carve on GPU).

### Decision

Both volume-estimation algorithms run as Metal compute kernels with 8×8×8 threadgroups (512 threads per group, fits all Apple GPUs). Probability tensors are uploaded to Metal once per inference and consumed by the kernel via `texture2d_array<half>`. Per-class voxel counts accumulate atomically in an `MTLBuffer<UInt32>` and are reduced in-kernel via threadgroup atomics before readback.

### Rationale

The 300 ms two-view budget at 576k voxels × 2 projections × per-class probability product (27 classes) is on the cusp of pure-CPU feasibility but well inside Metal capability on the A14. Metal also lets the segmenter (ANE) and the voxel carve (GPU) overlap, recovering the segmenter's CPU stalls. The per-thread workload (project, sample two textures, multiply 27-vector products, atomic increment) maps cleanly to a compute kernel.

### Alternatives Considered

- **CPU SIMD via Accelerate**: Simpler but risks missing the 300 ms two-view budget; GPU/CPU overlap is lost.
- **Start CPU, switch to Metal if budget missed**: Defers a known performance risk; the CPU implementation would be discarded.

### Consequences

**Positive:**
- Latency budget has comfortable headroom.
- ANE-segmenter / GPU-carve overlap.
- Metal codebase reusable for the height-field integrator (single-view path).

**Negative:**
- Metal shaders are platform-specific; Android port re-implements in Vulkan compute or OpenGL ES 3.1+ compute shaders.
- Debugging compute shaders is less straightforward than CPU code.

---

## Decision 27: Segmenter weights and CoFID/IFCDB SQLite ship in the app binary

**Date**: 2026-05-07
**Status**: accepted

### Context

The segmenter weights (≤10 MB per Req 8.2), CoFID SQLite (~5 MB for 27 classes' coefficients + meta), and the optional IFCDB overlay (~1 MB) total ~16 MB. These can be either bundled in the app binary or downloaded from a project CDN on first launch. Bundling adds 16 MB to the install size; downloading adds a network failure path to onboarding and a CDN to operate.

### Decision

Bundle the segmenter weights and the CoFID + IFCDB SQLite databases in the app binary. The IFCDB overlay is bundled but loaded only when the user enables the regional overlay setting.

### Rationale

The combined ~16 MB is small relative to App Store norms and small relative to typical photo-app data (a single iPhone photo can exceed 5 MB). Bundling keeps the app fully offline from first launch (per Req 1.5), removes the CDN as an operational dependency, and simplifies onboarding to a single permission prompt (camera). The on-device-first commitment in Decision 3 is best served by no first-launch network requirement.

### Alternatives Considered

- **Download on first launch**: Smaller install (~3 MB shell only); adds network failure mode and CDN ops cost; wrong default given offline-first commitment.
- **Hybrid (small DB bundled, weights downloaded)**: Splits the difference; adds onboarding complexity for marginal install-size benefit at this scale.

### Consequences

**Positive:**
- App is fully usable on first launch with no network.
- No CDN to operate or version.
- Database / weights versions are pinned to the app version; no version-skew bugs.

**Negative:**
- App binary grows by ~16 MB.
- Database upgrades require app updates; IFCDB / CoFID edition refresh ships through normal App Store releases.

---

## Decision 28: Segmenter trained in PyTorch; exported to both Core ML and TFLite from one checkpoint

**Date**: 2026-05-07
**Status**: accepted

### Context

The segmenter is the only learned component (Decision 3) and must satisfy Decision 2's "single source-of-truth" portability. Three plausible training stacks: PyTorch (research-dominant), TensorFlow (TFLite-native), or Apple's CreateML / MLX (iOS-only).

### Decision

Train in PyTorch. Export the same checkpoint twice: once via `coremltools` to Core ML for iOS, once via `ai-edge-torch` to TFLite for the future Android port.

### Rationale

PyTorch is the dominant research stack, with mature semantic-segmentation tooling (torchvision, lightning, etc.). `coremltools` (8.x) supports `torch.export`-based conversion that bypasses the legacy ONNX hop. `ai-edge-torch` (Google AI Edge, GA September 2024) replaces the brittle PyTorch → ONNX → tf2onnx → TFLite chain with a `torch.export` + StableHLO → TFLite path. Both export paths consume the same PyTorch checkpoint, so the "single source of truth" commitment is mechanically satisfied.

### Alternatives Considered

- **TensorFlow + TFLite + coremltools**: TF research community is now smaller; modern segmentation work is mostly PyTorch.
- **Apple CreateML / MLX**: iOS-only; defeats Decision 2 portability.

### Consequences

**Positive:**
- One training pipeline, one checkpoint, two production artefacts.
- PyTorch ecosystem includes the FoodSeg103-style transfer-learning recipes.
- `ai-edge-torch` is a Google-maintained path with active investment.

**Negative:**
- Two export tools to maintain (coremltools, ai-edge-torch); each has its own opinion about supported ops.
- Op-coverage gaps require occasional manual op replacement before export.

---

## Decision 29: Single-view pixel area uses 1/cos³θ off-axis correction

**Date**: 2026-05-08
**Status**: accepted

### Context

The v0.2 design used $a(p) = z_t^2 / (f_x f_y)$ — the on-axis small-pixel-area approximation — and claimed the off-axis error was ~6% for corner pixels and "absorbed by β_c". Round-3 mathematical review showed this calculation was wrong: the geometrically correct factor is $1/\cos^3\theta_p$ where $\theta_p$ is the angle from the optical axis. At iPhone 12 Pro main-camera 73° HFoV, the corner-pixel correction is ~54% (cos(36.5°)⁻³ ≈ 1.94), not 6%. β_c is a per-class scalar; it cannot absorb a spatially varying bias of that magnitude. Calibrating β_c against the broken kernel would silently absorb spatial geometry error into per-class numbers, polluting the calibration and invalidating the pipeline the moment the kernel is fixed.

### Decision

The single-view height-field pixel area is computed as
$$a(p) = \frac{z_t^2}{f_x f_y \cos^3\theta_p}, \qquad \cos\theta_p = \frac{f}{\sqrt{f^2 + (u-c_x)^2 + (v-c_y)^2}}, \quad f = (f_x + f_y)/2.$$
The cosine-cubed correction lands **before** the v1 test set is curated and β_c is calibrated, so β_c absorbs only true per-class shape bias (visual-hull concavity, packing fraction, internal voids), not spatial geometry error.

### Rationale

The factor $1/\cos^3\theta_p$ is the standard derivation: one factor of $1/\cos\theta$ for the increased ray length to reach depth $z_t$ along an off-axis ray, and $1/\cos^2\theta$ for the off-axis pixel-area Jacobian on the image plane. β_c is unable to correct spatial bias because it has no positional dependence; a per-class scalar cannot vary with image position. Without the cosine-cubed correction, β_c calibration on a centred-food test set produces values that fail on corner-of-frame food in production.

### Alternatives Considered

- **Keep on-axis and absorb in β_c**: Rejected per the calibration-pollution argument.
- **Constrain capture to centred food only**: Rejected — UX-hostile; users will not consistently centre food.
- **Use the simpler $1 + (\Delta x^2 + \Delta y^2)/f^2$ Jacobian only (drop the ray-length factor)**: Rejected — drops half the geometric correction; matches the (incorrect) v0.2 6% claim.

### Consequences

**Positive:**
- Volume estimates are geometrically correct across the full image.
- β_c calibrates against true per-class shape bias only.
- Robust to off-centre food in production.

**Negative:**
- One additional kernel computation per pixel (square root + division). Negligible cost.
- The on-axis approximation in v0.2 produced under-estimates at the edges; users with consistently corner-positioned food will see slightly larger carb totals after the fix lands.

### Impact

Affects §6.7 height-field integration. Fixed before v1 test set curation, so calibration is unaffected.

---

## Decision 30: β_c calibration uses log-residual closed form (MAPE-aligned)

**Date**: 2026-05-08
**Status**: accepted

### Context

Decision 9 introduced β_c as a per-class bulk-correction factor. The v0.2 design specified an OLS closed-form fit:
$$\beta_c = \frac{\sum (V_c^{\text{uncal}} \rho_c \kappa_c / 100) \cdot C_c^*}{\sum (V_c^{\text{uncal}} \rho_c \kappa_c / 100)^2}.$$
This minimises the sum of squared **absolute** carb errors (MAE-aligned). The v1 acceptance bar is **MAPE < 20% AND MAE ≤ 10 g** (Req 21.3). OLS does not minimise MAPE: meals with very small ground-truth carb mass have small absolute squared residuals even when the percentage error is large. Calibration may pass MAE while quietly missing MAPE.

### Decision

β_c is calibrated by minimising squared **log-residuals**:
$$\beta_c = \exp\left(\text{mean}\left[\ln\left(\frac{C_c^*}{V_c^{\text{uncal}} \rho_c \kappa_c / 100}\right)\right]\right).$$
This is the closed-form solution to $\min_\beta \sum_i (\ln \beta - \ln(C_c^* / \text{predicted}_i))^2$ — a 1-D log-space OLS that targets MAPE directly. Numerical stability: refuse the log-fit and fall back to pooled β if any meal in the calibration set has predicted carbs $< 10^{-9}$.

### Rationale

Log-residual fits are the standard approach when the acceptance bar is multiplicative-error rather than additive-error. The closed form remains 1-D and is dimensionally identical to the OLS form. The geometric-mean nature of the estimator makes it less sensitive to outlier meals with very large carb totals than the arithmetic-mean OLS. Path-specific clamps remain ($(0, 1]$ for two-view, $(0, 1.5]$ for single-view) to bound β within physically meaningful ranges.

### Alternatives Considered

- **OLS on absolute carbs (v0.2)**: Rejected — minimises wrong objective.
- **Joint MAPE+MAE objective via line-search**: Rejected — adds a hyperparameter and a non-closed-form solver for marginal benefit.
- **Median residual ratio**: Rejected — robust but not closed-form, and the log-residual mean already provides outlier resistance compared to OLS.

### Consequences

**Positive:**
- Calibration objective matches the acceptance bar.
- More resilient to high-carb-mass outlier meals than OLS.
- Still 1-D closed-form, no iterative solver.

**Negative:**
- Refuses the fit (falls back to pooled β) when any meal has near-zero predicted carbs; this is a real refusal case, not silent.
- Log-residual mean is sensitive to underestimated meals (predicted $\ll$ actual produces large positive log-residual), which is the desired behaviour but means a single low-volume outlier can sway β upward.

### Impact

Affects §6.9 calibration; supersedes the v0.2 OLS form. Path-specific clamps from §6.9 step 2.

---

## Decision 31: Portable type contracts strip iOS-only types from public surfaces

**Date**: 2026-05-08
**Status**: accepted

### Context

The v0.2 design declared `ProbabilityTensor.buffer: MTLBuffer` as a public field. `RawFrame` exposed `simd_float3`, `simd_float4x4`, `Data`-typed BGRA bytes, and `TimeInterval`. Round-3 portability review found these were not just iOS implementation choices but iOS-specific *contract surfaces* that an Android co-developer could not consume. Decision 2 commits to portable contracts; the v0.2 surface contradicted that commitment in five places.

### Decision

Every type that crosses a module boundary in `MedataCore` is defined by a `.proto` schema in `PortableContracts/Schemas/`. Swift types in §3 are typealiases or thin wrappers over the generated protobuf types. Specifically:

- `Vec3`, `Mat4` (column-major, right-handed, −Z forward, +Y up) replace `simd_float3` / `simd_float4x4`.
- `RawFrame.imageBytes: Data` is bytes plus a `pixelFormat` enum (RGB8/BGRA8/RGBA8); §6.5 step 1 canonicalises to RGB8 before any algorithm runs.
- `ProbabilityTensor.bytes` is the portable contract (FP16 IEEE-754 LE, HWC row-major); the `MTLBuffer` is an iOS-private adaptor inside `Segmentation/`.
- `RawFrame.timestampMonotonicNs: Int64` replaces `TimeInterval` with an explicit monotonic-ns contract.
- `DepthMap.confidenceBytes` is UInt8 0..255 normalised; iOS adapts ARKit's `ARConfidenceLevel` `{0, 1, 2}` to `{0, 127, 255}`.
- `DepthMap` carries `width`, `height`, `rowStrideBytes`; algorithms read from the struct rather than assume 256×192.
- File paths in module APIs are `String`, not `URL`; iOS UI wraps in `URL` at the boundary.
- Persisted `meals.record_json` is **protobuf-JSON** of `MealRecord.proto`, NOT Swift `Codable` default — guarantees byte-identical encoding from iOS Swift and from a future Android Kotlin consumer.

### Rationale

Portable contracts are the load-bearing mechanism for Decision 2. The v0.2 surface forced an Android co-developer to either re-derive the contracts from algorithm prose or guess at byte layouts. The .proto-first approach makes the canonical specification the single source of truth and reduces the iOS-Android delta to mechanical platform bindings.

### Alternatives Considered

- **Document iOS types as the contract and require Android to adapt**: Rejected — pushes the cost of portability onto every Android consumer.
- **JSON-only contracts (no protobuf)**: Rejected — JSON has no schema enforcement and Swift `Codable` vs Kotlin `kotlinx.serialization` defaults differ; protobuf-JSON gives deterministic encoding.
- **Hide `MTLBuffer` behind a Swift protocol but keep it on the public surface**: Rejected — protocols don't survive .proto round-trip.

### Consequences

**Positive:**
- Android co-developer can implement v1 from .proto + §6 + bundled SQLite + segmenter checkpoint, without consulting iOS code.
- `meals.record_json` is portable across platforms; clinical-track export (Req 15.8) is consumable on either platform.
- Pixel-format / colour-space / timestamp / LiDAR-confidence ambiguities are resolved at the contract layer.

**Negative:**
- Swift implementation has a per-frame `simd_*` ↔ `Vec3`/`Mat4` conversion at the `CaptureKit` boundary (negligible cost; ~10ns per conversion).
- More .proto files to maintain (24 schemas inventoried in §4.3).

### Impact

Affects §3.1, §3.5, §3.6, §3.8, §4.1 (`record_json` encoding), §4.3 (.proto inventory), and §8 portability table. Implementation cost is concentrated in the `PortableContracts` module; downstream modules consume the generated types directly.

---
