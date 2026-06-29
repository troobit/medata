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
