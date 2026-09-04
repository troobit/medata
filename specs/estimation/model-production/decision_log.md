# Decision Log: Model Production

## Decision 1: New full "process-to-done" spec as the vessel

**Date**: 2026-06-29
**Status**: accepted

### Context

The MVP is blocked on exactly one thing — no trained `segmenter.mlpackage` exists, so estimates run on the `StubInferenceEngine` ellipse (mvp-gap-analysis.md, 2026-06-28). The end-to-end recipe (`docs/ml-training.md`, 543 lines), the `tools/segmenter/*` scripts (smoke-tested on synthetic data), and the Swift runtime (`CoreMLSegmenter`, pipeline tasks 22/23) already exist. What is missing is a driving, acceptance-gated execution ledger that takes the model from "documented" to "bundled and verified."

### Decision

Create a new full spec at `specs/estimation/model-production/` whose requirements are the acceptance gates and whose tasks are the executable steps, referencing the existing recipe/architecture rather than duplicating them.

### Rationale

The user explicitly wanted the work "well defined and processed in spec and documentation," refined as it proceeds. A runbook (`ml-training.md`) documents the *how* but is not a tracked ledger with acceptance gates and a decision log; the existing pipeline spec is 90/91 done and owns the architecture, not the production process.

### Alternatives Considered

- **No new spec — drive existing pipeline Phase-3 tasks (22/23/58–65)**: Rejected — those tasks are marked code-complete; they track code, not the data/training execution, and give no single driving ledger.
- **Thin smolspec (loader fix + checklist)**: Rejected — undersizes a multi-stage, cross-cutting (dataset, training, export, bundling, calibration) effort the user wants formally specced.

### Consequences

**Positive:**
- One tracked ledger drives the MVP's last blocker to done.
- Existing docs stay authoritative; the spec references, not duplicates.

**Negative:**
- Some overlap with `ml-training.md`; requires the [1.4](requirements.md#1.4) "update together" discipline to avoid drift.

---

## Decision 2: Spec named `estimation/model-production`

**Date**: 2026-06-29
**Status**: accepted

### Context

The routing suggested `estimation/segmenter-model`. The spec covers two model artefacts — the segmenter network and the β_c bulk-correction table.

### Decision

Name the spec `estimation/model-production`.

### Rationale

"Model production" captures both artefacts and the process emphasis; "segmenter-model" would understate the β_c calibration process the spec also defines.

### Alternatives Considered

- **estimation/segmenter-model**: Rejected — names only the segmenter, though the spec also owns the β_c calibration process.

### Consequences

**Positive:** Name matches the full scope (segmenter + β_c process).
**Negative:** Slightly less discoverable for someone searching "segmenter."

---

## Decision 3: MVP gate is a real segmenter with β_c calibration deferred

**Date**: 2026-06-29
**Status**: accepted

### Context

The user wants to "push a simple MVP" that produces a real carb number. The full v1 accuracy bar (MAPE < 20%) depends on β_c calibration, which depends on a ≥30-meals/class gravimetric dataset — flagged the single largest project risk.

### Decision

Define the MVP gate as a trained segmenter (mIoU ≥ 0.60, ≤10 MB FP16, ANE-resident) bundled and producing a real carb number with β_c left uncalibrated and flagged low-confidence. The MAPE < 20% / MAE ≤ 25 g bar is the v1 target, tracked but explicitly off the MVP critical path.

### Rationale

A real segmenter is sufficient to produce a real (if biased) number; gating the MVP on the gravimetric campaign would couple it to the project's biggest risk. Persisting `betaCalibrationStatus` keeps the uncalibrated number honest.

### Alternatives Considered

- **Full v1 accuracy bar as MVP gate**: Rejected — re-couples MVP completion to the gravimetric dataset risk; contradicts "simple MVP."

### Consequences

**Positive:** MVP unblocked by code + a single training run; honest low-confidence labelling.
**Negative:** MVP carb numbers carry known upward volume bias until calibration runs.

---

## Decision 4: Train the full 27-class v1 palette

**Date**: 2026-06-29
**Status**: accepted

### Context

A reduced subset could reach a real model faster, but the palette channel order is fixed by `ClassPalette.v1Standard` and "must never be reordered"; the DB edition and tooling assume the full palette.

### Decision

Train the full 27-class v1 palette (24 food + background + unknown_food + unsupported_liquid).

### Rationale

Matches the existing mapping, tooling, and palette↔DB lock; a subset would need a mapping/migration story for no MVP-time benefit.

### Alternatives Considered

- **Reduced subset first**: Rejected — fixed channel order makes a subset a migration problem, not a shortcut.

### Consequences

**Positive:** No palette/DB churn; tooling runs as-built.
**Negative:** Training requires the full FoodSeg103 remap up front.

---

## Decision 5: β_c calibration process is defined and tracked, execution deferred

**Date**: 2026-06-29
**Status**: accepted

### Context

The calibration runbook (`ml-training.md` §9) and harness (pipeline tasks 58–65) exist; only the weighed-meal data and execution run are missing. Calibration execution is human/data-gated.

### Decision

This spec defines and tracks the β_c calibration process (fixtures → `HarnessCLI calibrate` → bake into DB) but defers its execution past the MVP gate; it is neither fully in-scope nor split to a separate spec.

### Rationale

Keeping the process in this spec keeps it adjacent to the segmenter work it depends on, while deferring execution keeps the MVP unblocked. A separate spec would risk the process drifting from the model it calibrates.

### Alternatives Considered

- **Fully in scope**: Rejected — re-couples MVP to the gravimetric dataset risk.
- **Separate follow-on spec**: Rejected — splits the calibration process from the model production it depends on.

### Consequences

**Positive:** Process is ready to run unchanged once data exists; MVP stays unblocked.
**Negative:** The spec is "done" for MVP while a defined phase remains unexecuted — completion is milestone-scoped, not absolute.

---

## Decision 6: Review-driven requirements hardening

**Date**: 2026-06-29
**Status**: accepted

### Context

The design-critic and a peer-validation pass (external models Gemini/Codex were unreachable due to auth, so the second pass was an independent in-house review, not a true multi-model cross-check) converged on correctness gaps in the first requirements draft.

### Decision

Apply the agreed fixes and resolve three scope calls: (a) export equivalence oracle changed from Core ML-vs-TFLite to the **PyTorch checkpoint** ([4.3](requirements.md#4.3)); (b) added training/inference **preprocessing parity** ([4.5](requirements.md#4.5)); (c) hardened the on-device gate to assert `segmenterSource`, value > 0, and **mask plausibility** on the deployment distribution ([6.2](requirements.md#6.2)); (d) MVP gate now lists its export-eligibility preconditions ([6.3](requirements.md#6.3)); (e) MVP β fixed to `uncalibrated_unity` (pooled unreachable pre-calibration) plus **upward-bias direction** in the honesty label ([7.1](requirements.md#7.1), [7.3](requirements.md#7.3)); (f) build **lineage** recorded for metric-level reproducibility ([1.3](requirements.md#1.3)); (g) compute/hardware stages marked human-gated ([3.1](requirements.md#3.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)); (h) added a **per-class IoU floor (≥ 0.50)** on the carb-priority staples with a fallback ([3.5](requirements.md#3.5), [3.6](requirements.md#3.6)). Scope calls: **no latency AC** (the 22 s freeze was a Debug `-Onone` artifact; Release ~827 ms per MD-28, owned by the pipeline spec); **bad-model rollback/integrity deferred** (5.3 covers a missing model; field recovery = ship the previous bundle until OTA matters).

### Rationale

The oracle, preprocessing-parity, and mask-plausibility fixes close silent-failure paths where a model looks valid but produces wrong masks/numbers — the same failure class as the dev-stub. The per-class floor protects the staples that dominate the carb number, which a mean mIoU hides. Latency and rollback were declined to avoid duplicating the pipeline spec and over-scoping a simple MVP.

### Alternatives Considered

- **Latency AC referencing the pipeline budget**: Rejected — MD-28 already confirms Release latency; duplication, no new risk covered.
- **Mean-only IoU (no per-class floor)**: Rejected — a passing mean can hide a near-zero staple class, defeating the MVP's purpose.
- **Bad-model kill-switch/integrity check in MVP**: Rejected — out of scope until distribution/OTA exists; recovery is a rebuild.

### Consequences

**Positive:** Gates now test fidelity to the trained network and the deployment distribution, not just internal export consistency; carb-critical classes are individually protected.

**Negative:** More export-eligibility gates raise the bar to ship a model; the per-class floor and mask-plausibility check need real-run data to tune, deferred to design.

---

## Decision 7: Bundle the segmenter via `.copy("Resources")` directory, not a named-file copy

**Date**: 2026-06-29
**Status**: accepted

### Context

Tasks 1–2 switch the Phase 3 loader from `Bundle.main` to the `Pipeline` target's
own resource bundle (`Bundle.module`, Req 5.1). Two hard SPM constraints collide:
(a) `Bundle.module` is only synthesised for a target that declares at least one
resource — referencing it otherwise is a compile error; (b) a `.copy` of a named
file fails the manifest/build for *every* configuration when that file is absent.
The real `segmenter.mlpackage` does not exist yet — it is the gated MVP deliverable
and is gitignored — so the literal `.copy("Resources/segmenter.mlpackage")` from the
task draft would break `swift build`/`swift test` for everyone until a model lands.

### Decision

Declare `resources: [.copy("Resources")]` on the `Pipeline` target — a copy of the
*directory*, not the named model file — and commit a `Resources/README.md` marker so
the directory exists on clean checkouts. The model file stays gitignored at
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`. The loader looks it up
with `Bundle.module.url(forResource:"segmenter", withExtension:"mlpackage", subdirectory:"Resources")`
because a directory `.copy` preserves the `Resources/` structure inside the bundle.
Resolution is extracted into the always-compiled helper `resolveBundledSegmenterURL(in:)`
so the contract is testable under the Debug/DEV_STUB build, where the `#else` branch
that calls it is compiled out.

### Rationale

The directory copy is the only declaration that is valid *now* (the directory exists
via the README) yet bundles the real model automatically once `export.py` drops it in —
no second Package.swift edit when the model arrives. Clean builds stay green, `Bundle.module`
becomes available, and an absent model still produces exactly the intended
`PipelineFactoryError.segmenterModelMissing` at runtime in Release. Committing a fake
placeholder `.mlpackage` was rejected as dishonest and contrary to the gitignore intent.

### Alternatives Considered

- **Literal `.copy("Resources/segmenter.mlpackage")`**: Breaks all builds until the gitignored model exists — infeasible pre-training.
- **Commit a tiny placeholder `.mlpackage`**: Makes the named-file copy valid, but ships a fake model that Release would try to load, and pollutes git with a binary the gitignore is meant to exclude.
- **Defer the `Bundle.module` switch entirely**: Leaves `Bundle.main` in place; fails Req 5.1 and blocks the rest of the spec for no real gain.

### Consequences

**Positive:**
- Loader is on `Bundle.module` now; clean Debug + Release builds both compile with no model present.
- The real model bundles with zero further manifest changes.
- Absent-model behaviour is the correct `segmenterModelMissing`, asserted by an always-compiled, Debug-runnable test.

**Negative:**
- Lookup must pass `subdirectory: "Resources"`; a future contributor moving the file to the bundle root would silently break resolution (mitigated by the README and this entry).
- `.copy("Resources")` will bundle anything else placed in that directory verbatim.

### Impact

`Package.swift` (Pipeline target `resources:`), `PipelineFactory.swift`
(`resolveBundledSegmenterURL`, `#else` branch), `.gitignore` (model path moved to the
new location), and the new `MedataCore/Sources/Pipeline/Resources/README.md`.

### Parity audit (Req 5.1)

`grep -rn 'Bundle.main.\(url\|path\)(forResource:'` over `MedataCore/Sources/**` and
`App/**` after the change found exactly one remaining hit:
`CaptureKit/MetalContext.swift:66` looking up a `.metallib`. That is an app-resident
Metal library, not a model resource, and is out of scope for this spec. The segmenter
model is now the sole resource lookup migrated to `Bundle.module`; the food DB already
used `Bundle.module`. Result recorded, not assumed.

---

## Decision 8: `segmenterSourceTag` derives from the loaded model, not a static constant

**Date**: 2026-06-29
**Status**: accepted

### Context

Task 5 makes the Core ML model version per-loaded-model: `CoreMLInferenceEngine.modelVersion`
changes from a `static let "v0.1"` to an instance value read from the model's
`userDefinedMetadata["medata.modelVersion"]` (the checkpoint SHA-256 prefix, Req 5.4).
`Pipeline.segmenterSourceTag` previously interpolated the *static* version, so it could no
longer compute the tag without an actual loaded segmenter.

### Decision

Change the public `static var segmenterSourceTag: String` to a function
`static func segmenterSourceTag(for segmenter: CoreMLSegmenter) -> String`, and add a pure,
always-compiled helper `coreMLSourceTag(modelVersion:)` that does the `"coreml_\(version)"`
interpolation. `CoreMLSegmenter` gains an optional `modelVersion` (nil for the dev-stub).
The version-from-metadata resolution lives in `CoreMLInferenceEngine.resolveModelVersion(fromUserMetadata:)`
with a non-empty `fallbackModelVersion`, so an unstamped model never yields an empty `coreml_` tag.

### Rationale

The tag must reflect the model that actually produced the meal, which is only knowable from the
loaded instance. Extracting `coreMLSourceTag` / `resolveModelVersion` as pure functions keeps the
contract testable under the Debug/DEV_STUB build, where the `#else` (Core ML) branch is compiled out
— the same constraint that shaped Decision 7. `preShutterSourceTag` stays a static property (it carries
no version).

### Alternatives Considered

- **Keep `segmenterSourceTag` static, read a static version**: Impossible once the version is per-model; would force a global mutable, breaking the "traceable to exact build" goal.
- **Expose the engine's `MLModel` to the Pipeline layer**: Leaks Core ML into Pipeline and is untestable without a real model; the metadata-dict seam is lighter and pure.

### Consequences

**Positive:** Persisted `segmenterSource` traces to the exact model build; derivation is unit-tested without a real `.mlpackage`.

**Negative:** A public API signature change (`segmenterSourceTag` now takes a segmenter); the only in-repo caller (`makeForDevice`) is updated, but any external caller would need the new form.

---

## Decision 9: Export oracle mirrors the runtime (letterbox) preprocessing; train.py square-resize skew flagged, not fixed

**Date**: 2026-06-29
**Status**: accepted

### Context

Implementing the Req 4.5 preprocessing-parity gate (task 7) required a Python replica of
the preprocessing the equivalence oracle feeds both the PyTorch checkpoint and the Core ML
artefact. Two existing preprocessing paths disagree: the **runtime** path
(`PreProcessing.swift`) does aspect-preserving **letterbox + pad**, while **training**
(`train.py` `FoodSegDataset`) and the fixture/reference helper (`export.reference_input`,
used by `make_fixtures.py`) do a **square resize** to 513×513. For non-square inputs these
produce different tensors — a real train/serve skew.

### Decision

`export.preprocess_reference` replicates the **runtime** path (letterbox + ImageNet
normalise + top-left pad with `(0−mean)/std`), and the oracle feeds inputs through it
(Req 4.5 names "the runtime preprocessing path"). The `train.py` / `reference_input`
square-resize discrepancy is **flagged as a follow-up**, not changed here: altering the
training transform is a training-pipeline behaviour change outside the export-gate scope,
and `reference_input` is still consumed by `make_fixtures.py`.

### Rationale

The export gate's job is to make the *shipped* path honest; the runtime path is what the
device actually feeds the model, so the oracle mirrors it. Reconciling training to also
letterbox is a separate, riskier change (it affects learned weights and fixtures) that
should be decided deliberately in the training pipeline, not bundled into the export gate.
Note the limitation: because the oracle feeds the SAME preprocessed input to both checkpoint
and artefact, it catches checkpoint↔artefact divergence, not the train↔runtime skew itself —
that skew is a code-parity concern the shared `preprocess_reference` makes visible.

### Alternatives Considered

- **Change train.py to letterbox now**: Rejected for this task — risks training behaviour/fixtures and belongs to the training pipeline spec; needs its own validation.
- **Mirror the square resize in the oracle**: Rejected — 4.5 explicitly names the runtime path; mirroring training would bless the skew instead of exposing it.

### Consequences

**Positive:** The export oracle reflects real device inputs; the skew is now documented and surfaced in one shared function.

**Negative:** A train/serve preprocessing mismatch remains until `train.py` is reconciled; the gate cannot numerically detect it (it compares checkpoint vs artefact on identical inputs).

### Impact

`tools/segmenter/export.py` (gates + `preprocess_reference` + oracle flip to the PyTorch
checkpoint), `tools/segmenter/tests/` (new pytest suite). Follow-up: reconcile
`train.py`/`reference_input` resize with the runtime letterbox path.

---

## Decision 10: Canonical model artefact name is `segmenter.mlpackage`

**Date**: 2026-07-03
**Status**: accepted

### Context

The trained Core ML artefact has been referred to in transcripts and drafts as
both `segmenter.mlpackage` and `food_segmenter.mlpackage` (the latter echoing
Google's `mobile_food_segmenter_V1` reference model in
`docs/agent-notes/dataset-strategy.md`). The name is load-bearing: the runtime
loader resolves it literally
(`Bundle.module.url(forResource: "segmenter", withExtension: "mlpackage",
subdirectory: "Resources")` in `PipelineFactory.resolveBundledSegmenterURL`),
the gitignore lists the exact path, and `tools/segmenter/export.py` defaults
its output to it. An artefact exported under any other name is silently NOT
bundled and Release falls over with `segmenterModelMissing`.

### Decision

The one canonical name is **`segmenter.mlpackage`**, at
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`. Never
`food_segmenter.mlpackage` or any other variant.

### Rationale

This is the name the entire committed chain already agrees on — loader,
gitignore, export default, and Decision 7's `.copy("Resources")` bundling.
Everything in this app segments food; the `food_` prefix adds no information
inside this codebase and creates a run-time-only failure when the names drift.
Recording the decision stops the drift at the source.

### Alternatives Considered

- **`food_segmenter.mlpackage`**: Mirrors the Google reference model's naming - Rejected: redundant prefix in a single-model food app, and would require touching loader, gitignore, and export defaults for zero benefit.
- **Versioned file name (e.g. `segmenter_v1.mlpackage`)**: Encodes the model version in the name - Rejected: the version already travels inside the artefact and is surfaced as `coreml_<modelVersion>` via `segmenterSourceTag` (Decision 8); a moving file name would break the literal resource lookup on every retrain.

### Consequences

**Positive:**
- One grep-able name across loader, tooling, gitignore, and docs.
- Retrained models drop in without code changes.

**Negative:**
- The name alone does not distinguish model generations — traceability relies on `segmenterSourceTag` (Decision 8).

---

## Decision 11: Developer-phase release override for the strict export gate

**Date**: 2026-07-05
**Status**: accepted

### Context

The export-eligibility gate (Req 3.2/3.5: mean food-class IoU ≥ 0.60 AND every
carb-priority staple ≥ 0.50) was written as a hard block. The first real
training run showed the FoodSeg103-remapped baseline converging around 0.34
mean food-class IoU — well short of the bar. Every other MVP subsystem is
complete and verified against the dev-stub; a hard gate would make model
quality the sole blocker for merging to main, while the developer's own
normal use of a real (if imperfect) model is itself the fastest source of
feedback for improving it.

### Decision

During the developer phase, the strict gate advises rather than hard-blocks.
`run_validation.py --allow-below-gate --reason "..."` records an attributable
`release_override` block in `lineage.json` metrics and exits 0. Without the
override the gate still fails the run. `export_eligible` always records the
truthful strict-gate verdict. The gate returns to blocking before any
non-developer release.

### Rationale

Model quality improves iteratively (more data, better recipe) and each
iteration drops in without code changes (Decision 10). Blocking the merge on
0.60 mIoU delays real-use feedback without making the interim estimates any
better; the app already surfaces per-class calibration honesty (uncalibrated
banner). An explicit, reasoned override keeps provenance truthful — lineage
never claims a below-gate model passed — while unblocking the release.

### Alternatives Considered

- **Lower the bar (e.g. to 0.35)**: Would let the current model "pass" - Rejected: rewrites the accuracy requirement to fit the artefact; the bar stops meaning anything.
- **Keep the hard block until 0.60 is reached**: Strictest reading of Req 3.2 - Rejected: serialises model improvement in front of all real-use testing, for a developer-phase build no one else receives.
- **Ship the dev-stub instead**: No gate involvement - Rejected: stub estimates are garbage by construction; a below-gate real model produces genuinely useful (if imperfect) masks and exercises the true pipeline.

### Consequences

**Positive:**
- Model quality stops being the only merge blocker; iteration happens against real use.
- Every below-gate release is deliberate, reasoned, and traceable in lineage.
- `export_eligible` stays truthful; re-validation drops stale overrides so each new metrics outcome needs a fresh decision.

**Negative:**
- A developer-phase build can ship with known-poor segmentation for some classes.
- The "return to blocking" step is process, not code — it must be enforced at the first non-developer release (flagged alongside the Req 14.5 disclaimer revisit).

---

## Decision 12: Training recipe adds geometric augmentation and poly LR decay

**Date**: 2026-07-05
**Status**: accepted

### Context

The first full training run (fixed lr 1e-3, no augmentation, 60 epochs
planned) overfit: train loss fell monotonically (1.12 → 0.21) while val
food-class mIoU plateaued at ~0.33–0.34 from epoch 13 through epoch 22. The
dataset (5,553 train images) is small for a 35-channel segmenter, and the only
train-time variation was the square resize.

### Decision

`train.py` now applies joint geometric augmentation to the train split —
horizontal flip (p=0.5) plus a random scale-up crop (scale 1.0–1.5, then a
random 513² window) — and steps the learning rate with a per-epoch poly-0.9
decay (`lr_e = lr · (1 − (e−1)/epochs)^0.9`). `--no-augment` restores
deterministic loading; val/heldout are never augmented. Both are recorded in
checkpoint provenance, the resume sidecar (augmentation is resume-gated), and
lineage `train_config`.

### Rationale

Flip + scale-crop and poly decay are the standard DeepLab transfer-learning
recipe and directly target the observed failure (memorising the small train
set). Scale is bounded ≥ 1.0 so cropping never pads — padding would invent
pixels carrying a real class id, since the loss has no ignore_index. The
schedule is a pure function of the epoch number, so `--resume` needs no
scheduler state and provenance stays reproducible.

### Alternatives Considered

- **Colour jitter as well**: More augmentation diversity - Rejected for now: colour handling is locked to `SegmenterPreProcessor` (train/serve match, §5); any colour-space change must be decided in lockstep with the device pre-processor, not slipped into the recipe.
- **Per-iteration poly schedule**: Closer to the reference implementation - Rejected: per-epoch stepping is indistinguishable at 60 epochs and keeps the resume sidecar stateless.
- **Early stopping on val mIoU instead**: Would cap wasted epochs - Rejected: does not fix overfitting, only stops at its plateau; augmentation attacks the cause.

### Consequences

**Positive:**
- Directly addresses the observed train/val divergence; standard, well-understood recipe.
- Resume safety preserved: augmentation mismatch is rejected like any other hyperparameter drift.

**Negative:**
- Epochs are no longer bit-reproducible (worker-seeded randomness), so lineage reproducibility stays metric-level (design §3.3), not byte-level.
- Slightly slower epochs (extra resize on scaled crops).

---

## Decision 13: Weight budget raised to 24 MiB — 10 MB was unachievable for the chosen architecture

**Date**: 2026-07-05
**Status**: accepted

### Context

The first real export hit the weight-budget gate: `segmenter.mlpackage` weighs
22.1 MB while `WEIGHTS_MAX_BYTES` and `SegmenterWeightsBudget.maxBytes` both
enforced 10 MB (Req 4.2 / pipeline Req 8.2). The architecture Decision 25
selected — DeepLabV3 + MobileNetV3-Large — has 11,029,075 parameters, which is
22.06 MB at FP16. The 10 MB budget and the architecture choice were never
mutually satisfiable at FP16; the conflict stayed latent until the first real
checkpoint existed. Meeting 10 MB would need sub-8-bit palettisation (8-bit
linear quantisation still lands at ~11.1 MB).

### Decision

Raise the segmenter weight budget to 24 MiB in both enforcement points
(`export.py` gate and the on-device `SegmenterWeightsBudget` load check), and
amend Req 4.2 and pipeline Req 8.2 accordingly. The gate itself stays active.

### Rationale

The budget's real job is to catch export mistakes (an accidental FP32 export
is ~44 MB) and unbounded model growth, not to force sub-8-bit compression onto
the MVP. Quantising below FP16 adds accuracy risk to a model already below the
mIoU gate (Decision 11) for ~11 MB of app-size saving that no current
requirement depends on. 24 MiB fits the Decision 25 architecture at FP16 with
minimal headroom (22.1 → 24).

### Alternatives Considered

- **8-bit linear quantisation**: Halves the artefact to ~11.1 MB - Rejected: still over the 10 MB budget, so the budget must move anyway; adds an untested accuracy variable to a below-gate model.
- **Sub-8-bit palettisation (6-bit ≈ 8.3 MB)**: The only route to genuinely meet 10 MB - Rejected for MVP: highest accuracy risk, and oracle-agreement thresholds would likely need loosening — the wrong trade during the developer phase. Revisit as a size-optimisation pass alongside accuracy work.
- **Switch to a smaller architecture (e.g. LR-ASPP MobileNetV3, ~3.2 M params)**: Fits 10 MB at FP16 - Rejected: abandons Decision 25 and the trained checkpoint for an architecture with lower reference accuracy, mid-developer-phase.

### Consequences

**Positive:**
- Export and on-device load agree again, and the gate still catches FP32/oversize mistakes.
- No new accuracy risk added on top of the below-gate model.

**Negative:**
- The app bundle grows ~22 MB with the model.
- A future size-optimisation pass (quantisation/palettisation) is deferred, not resolved; the 250 ms/view latency bar (Req 8.3) must still be verified on device at FP16.

---

## Decision 14: Oracle abs-logit-error bar recalibrated for FP16 compute (0.05 → 0.5)

**Date**: 2026-07-05
**Status**: accepted

### Context

The equivalence oracle (Req 4.3) required per-pixel argmax agreement > 99% AND
max abs logit error < 0.05. The first real export failed the second bar while
passing the first perfectly: measured FP16 drift was 0.13 (synthetic input,
argmax agreement 1.0000) and 0.30 (real heldout image, argmax agreement
0.9985) on logits of roughly ±20 magnitude. Both bars were authored before any
real FP16 artefact existed. The export forces FP16 for weights and compute
(Decision 25's on-device budget); ~1% relative drift on unnormalised logits is
inherent to FP16 accumulation, not an artefact defect.

### Decision

Raise `ORACLE_MAX_ABS_ERR` from 0.05 to 0.5 and amend Req 4.3 accordingly.
Argmax agreement > 99% stays unchanged as the functional bar.

### Rationale

The oracle's job is to catch conversion defects — wrong weights, broken
preprocessing, channel scrambling — which shift logits by whole units and
collapse argmax agreement. A 0.5 abs bar still catches those failure modes
(measured healthy drift is 0.13–0.30) while no achievable FP16 artefact could
meet 0.05. Downstream consumers use argmax and softmax probabilities, so class
decisions and their relative confidences, not raw logit precision, are what
the app depends on.

### Alternatives Considered

- **Export FP32 weights to meet 0.05**: Would pass the original bar - Rejected: ~44 MB artefact, violates even the amended weight budget (Decision 13), and the device runs FP16 on the ANE anyway — the oracle would then validate an artefact that does not match what ships.
- **Relative (per-magnitude) error bar**: Scale-aware and principled - Rejected: more moving parts for the same discrimination; argmax agreement already provides the functional check, and a fixed 0.5 is easily interpreted at the console.
- **Drop the abs-error bar, keep argmax only**: Simplest - Rejected: a uniform logit shift keeps argmax perfect while indicating a real conversion problem; a loose abs bar retains that signal.

### Consequences

**Positive:**
- The oracle passes for faithful FP16 artefacts and still fails on genuine conversion defects.
- The bar now reflects measured reality with ~1.7× headroom over the worst observed healthy drift.

**Negative:**
- Subtle sub-0.5 logit distortions that keep argmax intact are no longer caught — accepted, as downstream consumes argmax/softmax only.

---

## Decision 15: run_validation.py is the developer-phase validation gate; seg-bench fixture generation deferred

**Date**: 2026-07-06
**Status**: accepted

### Context

Two gate surfaces measure the same quantity — mean food-class mIoU on the
held-out split. The held-out validation stage (design §2.1 stage 4,
`tools/segmenter/run_validation.py`) computes it in Python and records it,
per-class IoUs, the strict-gate verdict and any Decision 11 override into
`build/lineage.json`. The `HarnessCLI seg-bench` path (`docs/ml-training.md`
§5, pipeline Req 8.9) measures the same bar through the Swift runtime, but
requires first generating a fixture bundle via `make_fixtures.py` — roughly
16 GB for the full held-out split. For the second real segmenter
(`24e0b022241a`, letterbox recipe) the question was whether to run both.

### Decision

During the developer phase, the held-out validation via `run_validation.py`
— with the Decision 11 override where the strict gate is not met — is the
recorded validation gate. §5 seg-bench fixture generation and the
`HarnessCLI seg-bench` run are deferred; the gate quantity of record lives
in `build/lineage.json`.

### Rationale

`run_validation.py` already records the identical gate quantity (mean
food-class mIoU plus per-class IoUs) into lineage, so a seg-bench run would
reproduce a number that is already on record. The fixture bundle costs
~16 GB of disk and the generation compute while adding no new information
about the model. And the offline bench is blind to the device-side gains
the letterbox recipe specifically targets — matching the runtime
letterbox pre-processing is only observable in on-device behaviour (stage
7), not in an offline mIoU re-measurement.

### Alternatives Considered

- **Run the full seg-bench**: Exercises the Swift-side gate path end-to-end - Rejected: ~16 GB fixture bundle that duplicates the number already recorded in lineage.
- **Subset bench (partial fixture set)**: Cheaper than the full bundle - Rejected: produces a partial mIoU that is not comparable to the recorded held-out figure or to the Req 8.9 bar.

### Consequences

**Positive:**
- Zero redundant compute and disk; no 16 GB fixture bundle per iteration.
- A single recorded gate number in `build/lineage.json` — no risk of two subtly divergent mIoU figures for the same checkpoint.

**Negative:**
- The Swift-side IoU implementation goes unexercised against real fixtures.
- Req 8.9's named gate path (`HarnessCLI seg-bench`) stays dormant until the pre-release return-to-blocking step (Decision 11).

---

## Decision 16: Export-eligibility bars re-pointed at the segmenter-foundation re-derivation (0.60 → 0.48 mean, 0.50 → 0.45 floors)

**Date**: 2026-07-11
**Status**: accepted

### Context

The Track A deep-research findings (`docs/agent-notes/model-foundation-research.md`)
showed the 0.60 mean food-class IoU gate (Req 3.2 / pipeline Decision 14) sits
above the published FoodSeg103 achievable frontier — no published model at any
size clears 0.60, and the ~0.52 SOTA needs 100M+ parameters against the shipped
architecture's 11.0M. Both shipped models were released under the Decision 11
developer-phase override, so the gate steered nothing. The `segmenter-foundation`
spec re-derived the bars from the frontier, the pinned 0.4054 baseline, and the
carb-priority floors: gate 0.48 (its Decision 5) and uniform per-class floors
0.45 (its Decision 14), with the held-out split re-cut stratified under its
Req 2.6 so every staple is measurable.

### Decision

Amend this spec's requirements to reference the re-derived bars, with
`segmenter-foundation`'s decision log as the authoritative home for the values:
Req 3.2 and Req 3.4 now cite the re-derived gate (segmenter-foundation
Decision 5, currently 0.48; was 0.60), Req 3.5 the re-derived floors
(segmenter-foundation Decision 14, currently 0.45; was 0.50), and Req 2.2
carries the stratified held-out re-cut note (segmenter-foundation Req 2.6: new
fixed seed, stratified, then frozen again).

### Rationale

A gate no achievable model can meet is permanently overridden and stops
informing shipping decisions — the same shape as the 10 MB weight budget
Decision 13 already corrected. Pointing the requirements at the
segmenter-foundation derivation keeps one authoritative home for the numbers,
so a future re-derivation amends one decision log instead of chasing every
copy. The export-eligibility mechanics (validation harness, shortfall
recording, Decision 11 override) are unchanged; only the bar values move.

### Alternatives Considered

- **Keep 0.60 and rely on the Decision 11 override indefinitely**: No document churn - Rejected: the gate then never blocks or steers anything; the override was designed as a developer-phase bridge, not a permanent bypass.
- **Inline the bare numbers (0.48/0.45) without citing segmenter-foundation**: Simpler sentences - Rejected: severs the trail to the derivation and its revisit triggers (baseline re-measure shift > 0.02, staple baseline < 0.40), inviting another arbitrary-bar cycle.

### Consequences

**Positive:**
- The gate is attainable, so export eligibility becomes a real shipping signal again instead of a formality to override.
- One authoritative home (segmenter-foundation Decisions 5 and 14) for the bar values, with the amendment history visible in the requirement text.

**Negative:**
- A model can now ship as export-eligible at an accuracy the original 0.60 bar would have blocked — the bar is honest rather than aspirational.
- Reading Req 3.2/3.5 now requires following a cross-spec reference to get the current numbers.

---
