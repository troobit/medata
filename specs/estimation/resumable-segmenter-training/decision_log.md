# Decision Log: resumable-segmenter-training

## Decision 1: Resume state is a sidecar file, not an enriched final checkpoint

**Date**: 2026-07-02
**Status**: accepted

### Context

Resumable training needs optimizer state and an epoch counter persisted per epoch. The shipped checkpoint at `--out` is consumed by `export.load_checkpoint`, `make_fixtures.py`, and the lineage manifest; `load_checkpoint` extracts `state["model"]` and would tolerate extra keys, so the resume data *could* be folded into the same file.

### Decision

Write resume state to a separate sidecar (`<--out>.resume.pt`, atomic temp+rename per epoch) and leave `_save_checkpoint` and the shipped dict untouched.

### Rationale

The shipped artifact's shape is a cross-tool contract (export, fixtures, lineage, and the Android re-export path). Keeping optimizer tensors out of it avoids doubling its size, avoids re-verifying three consumers for a tooling-only change, and makes "the file at `--out` is the final model" remain unconditionally true.

### Alternatives Considered

- **Enrich the final checkpoint with optimizer/epoch keys**: one file, tolerated by `load_checkpoint`'s key extraction - Rejected; doubles artifact size with training-only state and couples a run-state concern to a shipping contract.
- **Save per-epoch numbered checkpoints (`epoch_NN.pt`)**: standard in larger training rigs - Rejected; N× disk for no benefit at this model size, and the single-sidecar overwrite already bounds loss to one epoch.

### Consequences

**Positive:**
- Zero change to the shipped artifact or its three consumers.
- Bounded disk use (one sidecar, overwritten atomically).

**Negative:**
- Two files describe one run; the sidecar left behind after a completed run could be stale (resuming a finished run is specified harmless).

---

## Decision 2: New smolspec folder rather than reopening model-production

**Date**: 2026-07-02
**Status**: accepted

### Context

The change refines training tooling owned by `estimation/model-production`, whose ledger is code-complete and closed. PROCESS §3 offers extension (add a requirement to the owning spec) or a new capability folder.

### Decision

House the change at `specs/estimation/resumable-segmenter-training/` as a smolspec, cross-referencing model-production.

### Rationale

Reopening a closed Done ledger for a <80 LOC tooling change churns its status for no reader benefit; the sibling precedent (`estimation/lidar-first-scale-fallback`) established the standalone-smolspec shape. The capability (crash-safe, resumable local training) has its own small acceptance bar, which is PROCESS §3's test for a new spec. Chosen by Ronan at the spec-home gate.

### Alternatives Considered

- **Extend model-production**: keeps one home for all training concerns - Rejected; reopens a closed ledger and mixes a tooling refinement into a Done spec's history.

### Consequences

**Positive:**
- model-production's record stays closed; this change is independently trackable and mergeable.

**Negative:**
- One more spec folder; readers of model-production must follow a cross-reference to find the resume behaviour.

---

## Decision 3: Resume validates hyperparameters instead of reconciling them

**Date**: 2026-07-02
**Status**: accepted

### Context

Critic review surfaced two silent-divergence hazards: `optimizer.load_state_dict` restores the *old* lr from `param_groups` regardless of the resume invocation's `--lr`, and `_save_checkpoint`/`lineage.json` stamp the *resuming* invocation's `epochs`/`lr`/`batch_size`/`pretrained` as if they described the whole run. Reconciling (re-applying CLI lr after restore, merging provenance across invocations) is real code with subtle semantics.

### Decision

Reject instead of reconcile: `--resume` exits non-zero when `num_classes`, `palette_version`, `target_size`, `lr`, or `batch_size` differ from the sidecar; `pretrained` is carried from the sidecar (model built with `weights=None` on resume); the lineage manifest gains `resumed_from_epoch`. Changing hyperparameters mid-run is out of scope — start a fresh run.

### Rationale

With drift rejected, the restored optimizer state is consistent with the CLI by construction and every provenance field stays truthful with near-zero code. Mid-run hyperparameter tuning belongs to a schedule feature (explicitly out of scope), not to resume semantics. Same refuse-don't-guess stance as the sidecar-exists-without-`--resume` guard.

### Alternatives Considered

- **Re-apply CLI `--lr` to param_groups after restore**: allows mid-run lr drops - Rejected; makes lineage describe a run trained under two lrs with one recorded value, and invites silent drift for the other flags.
- **Record per-invocation provenance history in the manifest**: fully honest under drift - Rejected; disproportionate machinery for a smolspec whose users run identical chunked invocations.

### Consequences

**Positive:**
- Provenance is truthful with no reconciliation code; footguns become loud errors.

**Negative:**
- Lowering lr mid-run requires starting a fresh run (accepted; LR schedules are out of scope).

---
