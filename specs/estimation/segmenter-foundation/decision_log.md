# Decision Log: Segmenter Foundation

## Decision 1: New sibling spec, not a model-production extension

**Date**: 2026-07-10
**Status**: accepted

### Context

The Track A research (`docs/agent-notes/model-foundation-research.md`) concluded the segmenter effort needs a spec covering the accuracy gate, the training recipe, and a possible backbone swap. `specs/estimation/model-production/` already owns the dataset→train→export→bundle process, so the work could live there as new requirement sections instead of a new folder.

### Decision

Create a new spec at `specs/estimation/segmenter-foundation/`, referencing `model-production` for the production process it consumes.

### Rationale

`model-production` owns a *repeatable process* and consumes a gate; this work decides *what the foundation is* — recipe, backbone, and the gate's value. It has its own acceptance bar (measured uplift on the collapsed carb staples, a spike verdict), which per PROCESS.md §3 makes it a sibling capability. A separate folder also keeps the three-track parallel merge additive (PROCESS.md §9).

### Alternatives Considered

- **Extend model-production**: Add the recipe and gate re-derivation as new requirement sections — rejected because the acceptance bar differs (foundation choice vs process repeatability) and it would entangle a parallel-track branch with a spec owned elsewhere.
- **Name it `segmenter-accuracy-uplift` or `model-foundation`**: Rejected as effort-flavoured names; PROCESS.md §3 requires naming the durable capability. `segmenter-foundation` names what the spec owns: the segmenter's model foundation.

### Consequences

**Positive:**
- Disjoint spec folders keep the Track A merge to `research` conflict-free.
- `model-production` stays focused on process; gate amendments are explicit cross-references.

**Negative:**
- The gate now spans two specs until the amendment in Req 1.3 lands; a stale 0.60 reference is possible in the interim.

---

## Decision 2: Gate derivation method fixed in requirements, number fixed in design

**Date**: 2026-07-10
**Status**: accepted

### Context

Research finding: no published model at any size clears 0.60 mIoU on FoodSeg103 (SOTA ~0.52 on 100M+ parameter models), so the existing gate (pipeline Decision 14, model-production Req 3.2) is very likely unattainable and is currently bypassed by a developer override. The spec must re-derive it, but picking a number before the frontier analysis risks another arbitrary bar.

### Decision

Requirements define the derivation method (published frontier at comparable parameter budget + shipped baseline + carb-staple floors) and a provisional band (0.45–0.52); design fixes the binding number, logged before the first training run judged against it.

### Rationale

Deriving the number in design lets the frontier analysis inform it, while the "logged before the first gated run" rule prevents the gate being fitted post-hoc to whatever the run achieves.

### Alternatives Considered

- **Fix the number in requirements now**: Simplest - rejected because it pre-empts the frontier analysis the design phase should do.
- **Keep 0.60 with a data/taxonomy plan**: Rejected — the research shows the ceiling is the dataset, and a taxonomy overhaul is out of scope for this spec.

### Consequences

**Positive:**
- The gate ends up defensible against published evidence, not aspiration.
- Post-hoc gate-fitting is structurally prevented.

**Negative:**
- The binding number is unknown until design completes; model-production Req 3.2 stays stale until then.

---

## Decision 3: Public pretrained checkpoints only — no in-house SSL pretraining

**Date**: 2026-07-10
**Status**: accepted

### Context

FoodSeg103 winners lean on heavy ImageNet-1K masked-image modelling (MIM) pretraining (e.g. BEiT v2, 1,600 epochs). Reproducing such pretraining in-house is a large, human-gated GPU cost; using published pretrained weights captures most of the lever.

### Decision

The training recipe initialises from published, permissively-licensed pretrained checkpoints only; in-house self-supervised pretraining is out of scope.

### Rationale

Compute realism for a solo project: the research shows the lever is *heavy pretraining*, not *food-specific pretraining*, and heavy pretraining is exactly what published checkpoints already embody. Licensing becomes an explicit acceptance criterion (Req 2.2).

### Alternatives Considered

- **Allow in-house SSL runs**: Would permit Food-101 MIM pretraining if public checkpoints underperform — rejected for GPU cost and schedule risk out of proportion to the expected marginal gain.
- **No pretraining change (ImageNet-supervised weights as today)**: Rejected — forgoes the strongest evidence-backed lever in the research.

### Consequences

**Positive:**
- No pretraining compute; the recipe stays reproducible from public artefacts.
- Licence vetting is forced into the build lineage.

**Negative:**
- Checkpoint choice is limited to what exists publicly for the chosen backbone; a MobileNetV3-compatible MIM checkpoint may not exist, in which case the imbalance-loss half of the recipe carries the load.

---

## Decision 4: Developer override stays available under the re-derived gate

**Date**: 2026-07-10
**Status**: accepted

### Context

The shipped model is live under a developer override (0.40–0.43 vs the 0.60 gate). With an achievable gate, the override could be retired so the gate becomes binding.

### Decision

Keep the override path: a below-gate checkpoint may still ship with the shortfall recorded and estimates flagged low-confidence.

### Rationale

User call (2026-07-10): MVP flexibility outweighs gate strictness at this stage — the developer is the only user, and a working-but-below-bar model on device is worth more than a blocked pipeline.

### Alternatives Considered

- **Retire the override**: Makes the re-derived gate binding — rejected by the user to preserve MVP shipping flexibility.
- **Retire it only after the recipe upgrade lands**: A staged retirement — rejected as premature process; revisit before any non-developer release.

### Consequences

**Positive:**
- No shipping deadlock if the first recipe-upgrade run lands below the new gate.

**Negative:**
- The gate remains advisory in practice; its steering force depends on discipline, not mechanism.

---

## Decision 5: Re-derived gate fixed at 0.48 mean IoU, superseding pipeline Decision 14

**Date**: 2026-07-10
**Status**: accepted

### Context

Requirements (Req 1.1, 1.2; Decision 2) fixed the derivation method and a provisional band (0.45–0.52) but left the binding number to design, informed by the frontier analysis. The three named inputs are now available: the published FoodSeg103 frontier at a comparable parameter budget (no model at any size clears 0.60; SOTA ≈ 0.52 needs 100M+ params; the shipped architecture is 11.0M params), the shipped baseline (0.4054 mean food-class IoU, checkpoint `24e0b022241a`, per `model-production/prerequisites.md`), and the carb-priority per-class floors already in force (model-production Req 3.5, ≥ 0.50 per staple).

### Decision

Fix the re-derived export-eligibility gate at **mean IoU ≥ 0.48** on the fixed FoodSeg103 held-out split, measured by the existing validation harness (`run_validation.py`). This value is logged before any training run is judged against it, per Decision 2's rule.

### Rationale

0.48 sits inside the provisional band, roughly one point above its midpoint, and is derived as: shipped baseline (0.4054) plus the recipe-upgrade uplift floor already required by Req 2.4 (≥ 0.03) plus headroom reflecting Req 2.3's staple-specific uplift (≥ 0.05 on the eight carb-priority classes, which pull the overall mean up faster than a uniform improvement would). It sits well below the 100M+-parameter SOTA frontier (0.50–0.52), consistent with the shipped architecture's much smaller parameter budget — no compact-model FoodSeg103 number exists in the published literature to anchor to more precisely (the research's Q1 table has no FoodSeg103 result for any sub-10M-parameter model), so 0.48 is a considered interpolation rather than a literature-matched value. It is compatible with the existing per-class floors: several carb staples already clear 0.50 in the current run, so a 0.48 mean does not require every class to improve uniformly.

### Alternatives Considered

- **Set the gate at the band's lower bound (0.45)**: Simplest, least risk of missing it — rejected because it is barely above baseline + the mandatory Req 2.4 uplift (0.4054 + 0.03 = 0.4354), giving almost no margin and little steering force over "meets the minimum required uplift and stops."
- **Set the gate at the band's upper bound (0.52), matching literature SOTA**: Aspirational, matches the published ceiling — rejected because that ceiling is reached only by 100M+-parameter models; setting it there for an 11M-parameter architecture repeats the exact mistake (gate set above the achievable frontier) that motivated this spec.
- **Derive the gate purely from the mandatory uplifts (0.4054 + 0.03 = 0.4354, ignoring the staple-specific uplift's pull on the mean)**: More mechanical — rejected because it produces a gate below the band's lower bound, which Req 1.2 requires a logged justification for, and 0.48 is defensible without needing that exception.

### Consequences

**Positive:**
- The gate is defensible against published evidence and the shipped baseline, not aspiration.
- Compatible with the existing per-class floors — the mean and per-class bars are not fighting each other.

**Negative:**
- 0.48 is an interpolation, not a literature-matched number — no compact-model FoodSeg103 published result exists to validate it against directly; it may need revision after the first recipe-upgrade run's actual result is known.

### Impact

Amends `model-production/requirements.md` Req 3.2 (was "≥ 0.60") and marks pipeline Decision 14 as superseded. See Decision 6 for the related size-budget correction surfaced during the same design pass.

---

## Decision 6: Correct the drafted requirements' stale 10 MB weight-budget figure to the binding 24 MiB

**Date**: 2026-07-10
**Status**: accepted

### Context

`requirements.md` Req 2.5 and Req 3.1(b), as drafted, state the exported artefact must be "≤ 10 MB on-disk FP16," inherited from the research note's use of the same figure throughout. The actual binding budget is **24 MiB**, raised from 10 MB by `model-production` Decision 13 (2026-07-05) after the first real checkpoint (DeepLabV3+MobileNetV3-Large, 11.0M params, 22.1 MB at FP16) proved 10 MB unachievable for the chosen architecture. Both `SegmenterWeightsBudget.maxBytes` (`CoreMLSegmenter.swift:157`) and `export.py`'s gate already enforce 24 MiB in code. A design that measured the training-recipe upgrade (Requirement 2) or the SegFormer-B0 spike (Requirement 3) against 10 MB would reject the *already-shipped* baseline model, which cannot be the intended bar.

### Decision

Design uses 24 MiB as the binding on-disk FP16 budget for both the recipe-upgraded checkpoint (Req 2.5) and the SegFormer-B0 spike (Req 3.1(b)), correcting the stale figure inherited from the research note. This is recorded as a factual correction, not a re-opening of the size-budget question — the budget itself was already decided and landed by `model-production` Decision 13; this spec did not know about it when requirements.md was drafted.

### Rationale

Measuring against a number the shipped model already violates would make Requirement 2 unsatisfiable by construction. The correction costs nothing — no code changes, no new decision about what the budget *should* be — it aligns this spec's requirements text with a budget that is already decided, already in code, and already documented in two other specs (`model-production` Decision 13, `pipeline` Req 8.2 as amended).

### Alternatives Considered

- **Leave requirements.md's 10 MB figure as-is and note the discrepancy only in design**: Rejected — leaves a normative document (requirements.md) internally contradicted by its own design, which a future reader would reasonably trust as authoritative; the correction is cheap enough to make directly.
- **Treat this as evidence the research note needs a fresh pass**: Rejected — the research's conclusions (frontier, recipe lever, spike necessity) are unaffected by which number the budget is; re-running research for one stale figure is disproportionate.

### Consequences

**Positive:**
- Req 2.5 and Req 3.1(b) become satisfiable by the shipped baseline and consistent with `model-production` Decision 13 and `pipeline` Req 8.2.
- No design or code change is required beyond the text correction.

**Negative:**
- `requirements.md` still contains the stale "≤ 10 MB" text until it is next revised; design.md is the authoritative correction in the interim (same pattern as Decision 2's gate-value handling).

---

## Decision 7: Backbone-swap conversion spike reuses the existing equivalence-oracle thresholds

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 3.1(d) requires the SegFormer-B0 conversion spike to check that its Core ML output "matches its PyTorch outputs within a tolerance stated in design." A new tolerance could be invented for this comparison, or the spec could reuse the thresholds `model-production` already established and validated in practice for the current architecture's export gate (per-pixel argmax agreement > 99%, max absolute logit error < 0.05, later recalibrated to < 0.5 by `model-production` Decision 14 to absorb measured FP16 compute drift of 0.13–0.30 on ±20-magnitude logits, with argmax agreement staying the functional bar).

### Decision

The spike's equivalence check reuses `model-production`'s existing oracle thresholds and recalibration history verbatim: > 99% per-pixel argmax agreement (the functional bar) and the current FP16-drift-adjusted logit-error tolerance, rather than a spike-specific tolerance invented for this one comparison.

### Rationale

The existing thresholds already reflect a real, measured FP16 conversion-drift lesson (`model-production` Decision 14) rather than an assumption. Reusing them means the spike is judged by a bar the project has already calibrated against reality, and any future person comparing the two architectures' export fidelity is comparing against the same yardstick.

### Alternatives Considered

- **Invent a spike-specific tolerance**: Gives room to tune for SegFormer's different numeric behaviour (attention vs. convolution) — rejected because it is calibration effort spent before knowing whether the spike will even proceed past criteria 1–3, and a stricter or looser bar than the proven one would need its own justification.
- **Skip the equivalence check for the spike, defer it to the full retrain**: Reduces spike scope — rejected because Req 3.1(d) explicitly requires it as part of the spike verdict, and a conversion that silently changes outputs is exactly the failure mode a spike exists to catch early.

### Consequences

**Positive:**
- No new tolerance-calibration work; the spike is judged by a proven, documented bar.
- A pass/fail verdict is directly comparable to the existing architecture's own export-gate history.

**Negative:**
- If SegFormer-B0's attention-based numerics behave very differently under FP16 from DeepLabV3's convolutions, the reused tolerance may be miscalibrated for it (too strict or too loose) — not discoverable until the spike actually runs.

---

## Decision 8: Rejected approaches formalised with citations (CLIPSeg, MobileSAM/SAM3-distilled, FoodSAM)

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 4.1 requires the decision log to record text-conditioned segmentation, the SAM family, and FoodSAM as evaluated-and-rejected, each citing the specific violated constraint, so they are not re-opened in a later session without rediscovering why.

### Decision

Record as evaluated-and-rejected, each against the ≤ 24 MiB / ≤ 250 ms ANE budget and/or the single-pass per-pixel multi-class-probability contract (pipeline Decision 11):

- **CLIPSeg** (CVPR 2022, Lüddecke & Ecker) — ships a frozen CLIP ViT-B/16 (~150M params, >100 MB FP16), ~4× the 24 MiB budget even before accounting for its own head; emits one binary mask per text prompt, requiring one forward pass per class to cover the 35-channel palette, breaking the single-pass multi-class contract. Reported 43–48% mIoU, below even the re-derived 0.48 gate, and not food-trained.
- **MobileSAM / SAM3-distilled** — class-agnostic promptable masks, not per-pixel food-class probabilities, breaking the multi-class contract structurally (not just by budget); even distilled, the SAM3 text encoder alone is 42.5M params (~1.75× the 24 MiB budget); no ANE latency claims exist; the family's deployment target is edge GPUs, not an ANE-resident mobile segmenter.
- **FoodSAM** (arXiv 2308.05938, 46.42% mIoU on FoodSeg103) — a ViT-H (~636M param) SAM backbone plus a semantic module and detector, far outside budget by an order of magnitude; a post-hoc mask-refinement scheme rather than a foundation architecture; no latency/size/ANE data published.

### Rationale

Each is a real, evaluated option from the Track A research, not a strawman — CLIPSeg and FoodSAM in particular report competitive-looking mIoU numbers that could tempt a future re-proposal without the size/contract context attached here. Citing the specific violated constraint (not just "rejected") lets a future reader check whether the constraint has since changed (e.g. a future budget increase) rather than re-researching from scratch.

### Alternatives Considered

- **Record only a summary line ("text-conditioning and SAM variants rejected for size")**: Less durable — rejected because "size" alone does not explain why MobileSAM/SAM3 are rejected even independent of size (the class-agnostic output breaks the contract regardless of budget), which a future reader would need to rediscover.

### Consequences

**Positive:**
- Future sessions can check a specific constraint against a specific candidate without repeating the research.
- Distinguishes budget-only rejections (CLIPSeg, FoodSAM) from contract-structural rejections (SAM family) — relevant if the budget ever changes.

**Negative:**
- None identified; this is a documentation-only decision.

---

## Decision 9: `plate` as a distinct class — recorded open, not committed

**Date**: 2026-07-10
**Status**: proposed

### Context

Req 4.2 requires the `plate`-class question to be recorded as open and unresolved. The research (`docs/agent-notes/model-foundation-research.md` Q2) found no direct evidence either way: a dedicated `plate` channel is plausibly useful for plate isolation and scale recovery, but no source in the Track A search addressed it, and this spec's Non-Goals explicitly place any palette change out of scope.

### Decision

Record `plate` as a distinct segmenter class as an open sub-question. No change to `ClassPalette.v1Standard` is proposed by this spec. Revisiting it — if ever — is a `pipeline` or `nutrition5k-calibration` palette-change decision (those specs own the class list), informed by whatever evidence surfaces, not a `segmenter-foundation` decision.

### Rationale

Recording "open" rather than silently dropping the question means a future session evaluating palette changes has a pointer to this spec's Track A research instead of re-asking whether it was ever considered. Status is `proposed` rather than `accepted` because nothing is actually decided here — this entry exists to close out Req 4.2's acceptance criterion, not to commit to a direction.

### Alternatives Considered

- **Omit any record, since nothing was decided**: Rejected — Req 4.2 explicitly requires the question be recorded as open; silence would look like the question was never considered rather than deliberately deferred.
- **Recommend adding `plate` now on the plausibility argument alone**: Rejected — no evidence was found either way, and any palette change is out of scope for this spec (Non-Goals) and owned elsewhere.

### Consequences

**Positive:**
- The question is findable and attributed to its research source rather than lost.

**Negative:**
- None — no commitment is made, so there is no execution risk from this entry.

---
