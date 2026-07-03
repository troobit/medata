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
