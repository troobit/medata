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

0.48 sits inside the provisional band, about half a point below its midpoint (0.485) *(corrected 2026-07-11: originally misstated as "above")*, and is derived as: shipped baseline (0.4054) plus the recipe-upgrade uplift floor already required by Req 2.4 (≥ 0.03) plus roughly 0.04 of headroom reflecting Req 2.3's staple-specific uplift (≥ 0.05 on the below-gate staples, which pulls the overall mean up faster than a uniform improvement would). This derivation is the authoritative one; design §3.2 mirrors it. It sits well below the 100M+-parameter SOTA frontier (0.50–0.52), consistent with the shipped architecture's much smaller parameter budget — no compact-model FoodSeg103 number exists in the published literature to anchor to more precisely (the research's Q1 table has no FoodSeg103 result for any sub-10M-parameter model), so 0.48 is a considered interpolation rather than a literature-matched value. It is compatible with the existing per-class floors: several carb staples already clear 0.50 in the current run, so a 0.48 mean does not require every class to improve uniformly.

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

Will amend `model-production/requirements.md` Req 3.2 (currently "≥ 0.60") and mark pipeline Decision 14 as superseded — per Req 1.3 the amendments land once the floors of Decision 11 are also fixed, so the sibling specs are updated in one pass. *(Corrected 2026-07-10: originally written as already done; the sibling specs still carry 0.60 until the Req 1.3 amendment pass.)* See Decision 6 for the related size-budget correction surfaced during the same design pass. Note the derivation above used the 0.50 floors then in force; Decision 11 re-derives them, and Req 1.6 forces a revisit of this decision if the re-derived floors are inconsistent with the 0.48 mean.

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
- `requirements.md` still contains the stale "≤ 10 MB" text until it is next revised; design.md is the authoritative correction in the interim (same pattern as Decision 2's gate-value handling). *(Update 2026-07-10: requirements.md corrected the same day — Req 2.5 and 3.1(b) now state 24 MiB.)*

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

Record as evaluated-and-rejected, each against the ≤ 24 MiB weight budget and/or the single-pass per-pixel multi-class-probability contract (pipeline Decision 11) — ANE latency is recorded as unverified where no measurement exists, not claimed as a violation (Req 4.1):

- **CLIPSeg** (CVPR 2022, Lüddecke & Ecker) — ships a frozen CLIP ViT-B/16 (~150M params, >100 MB FP16), ~4× the 24 MiB budget even before accounting for its own head; emits one binary mask per text prompt, requiring one forward pass per class to cover the 35-channel palette, breaking the single-pass multi-class contract. Reported 43–48% mIoU, below even the re-derived 0.48 gate, and not food-trained.
- **MobileSAM / SAM3-distilled** — class-agnostic promptable masks, not per-pixel food-class probabilities, breaking the multi-class contract structurally (not just by budget); even distilled, the SAM3 text encoder alone is 42.5M params (≈ 85 MB at FP16, ~3.5× the 24 MiB budget); no ANE latency claims exist; the family's deployment target is edge GPUs, not an ANE-resident mobile segmenter.
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

## Decision 10: Stratified heldout re-cut so every carb staple is measurable

**Date**: 2026-07-10
**Status**: accepted

### Context

The design-critic review surfaced that three of the eight carb-priority staples (`brown_rice`, `bread_wholemeal`, `potato_mashed`) have no instances in the current fixed heldout split (model-production `prerequisites.md`, stage-4 validation, 2026-07-06), so per-class targets for them are unmeasurable and "no staple regresses" cannot be evaluated.

### Decision

Re-cut the heldout split stratified so every carb-priority staple has heldout instances, recorded as an amendment to model-production Req 2.2 (a new fixed seed, then frozen again). The pinned baseline `24e0b022241a` is re-measured on the re-cut split before any uplift target is judged; if its re-measured mean differs from 0.4054 by more than 0.02, the 0.48 gate (Decision 5) is revisited. (Req 2.6.)

### Rationale

User call (2026-07-10): a gate over five of eight staples does not protect what the spec claims to protect. Re-measuring the baseline on the new split keeps uplift deltas honest; the revisit trigger keeps Decision 5's derivation tied to the split it is judged on.

### Alternatives Considered

- **Measure present staples only**: Keeps run-to-run comparability with the 2026-07-06 results — rejected because the three absent staples are exactly the ones with zero visibility today.
- **Backfill heldout instances from external images**: Rejected — introduces a distribution the training set does not share, and FoodSeg103-internal stratification is sufficient.

### Consequences

**Positive:**
- All eight staples become measurable; floors and deltas apply to the full set.

**Negative:**
- Direct comparison with pre-re-cut runs is lost; the baseline must be re-measured before any judged run.

---

## Decision 11: Carb-priority floors re-derived alongside the gate

**Date**: 2026-07-10
**Status**: accepted

### Context

model-production Req 3.5's absolute per-class floors (IoU ≥ 0.50 per staple) were set under the same unattainable-frontier assumption as the 0.60 gate. This spec's Requirement 2 adds relative uplift deltas; without a ruling, a checkpoint could satisfy every delta and still be export-ineligible under the old floors, with no spec saying which wins.

### Decision

Design re-derives the per-class floors alongside the 0.48 mean gate using the same derivation inputs, logged before the first judged training run, and amends model-production Req 3.5 with the resulting values (Reqs 1.6, 1.3). The floors stay binding for export-eligibility; the deltas are the recipe track's success measure on top of them.

### Rationale

User call (2026-07-10): one coherent derivation for the mean gate and the floors. Keeping absolute floors preserves the protection deltas alone cannot give (a uniformly poor model could pass on deltas).

### Alternatives Considered

- **Keep the 0.50 floors unchanged**: Simpler — rejected because 0.50 inherits the discredited frontier assumption; `white_rice` at 0.6022 and `bread_white` at 0.4315 plainly do not share one achievable floor.
- **Subsume floors into deltas**: Rejected — removes the absolute backstop entirely.

### Consequences

**Positive:**
- Floors and gate come from one logged derivation; the two specs stop conflicting.

**Negative:**
- One more design deliverable before the first judged run.

---

## Decision 12: Pretraining fallback — imbalance loss carries the recipe if no stronger MobileNetV3 checkpoint exists

**Date**: 2026-07-10
**Status**: accepted

### Context

The MIM evidence in the research is for transformer backbones; Decision 3's consequences already note a MobileNetV3-compatible MIM checkpoint may not exist. Req 2.2 as first drafted was satisfiable by today's ImageNet-supervised weights, which would silently degrade the recipe to the status quo.

### Decision

Req 2.2 now requires a checkpoint embodying stronger pretraining than the current ImageNet-supervised weights, MIM-style where available. If none exists for MobileNetV3-Large, that absence is logged, the supervised initialisation is retained, and the class-imbalance countermeasure carries the recipe alone with expected uplift revised down.

### Rationale

User call (2026-07-10): log-and-degrade beats treating checkpoint absence as track failure — the imbalance loss is independently evidenced (+3.72% overall mIoU on FoodSeg103). The absence finding also raises the weight of the backbone track, where MIM-family pretraining does exist.

### Alternatives Considered

- **Treat absence as recipe failure**: Shifts effort to the backbone track immediately — rejected; it discards the independently evidenced half of the recipe.
- **Leave Req 2.2 as "any published checkpoint"**: Rejected — satisfiable by the status quo, so it required nothing.

### Consequences

**Positive:**
- The requirement now encodes the lever's intent and its honest fallback.

**Negative:**
- "Stronger pretraining" for a conv backbone may have no clean candidate, making the fallback the likely path — the expected-uplift revision must then be recorded, not glossed.

---

## Decision 13: Recipe-track success and gate compliance are allowed to diverge

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 2.4's minimum uplift (+0.03 over 0.4054 → ~0.44) sits below the 0.48 gate. The planned path can therefore be "recipe succeeds, model still ships under the developer override" — the state the re-derived gate was meant to end — and the first draft left this unacknowledged.

### Decision

The divergence is acknowledged explicitly (Req 1.5): the recipe track may land below the 0.48 gate while meeting its own uplift criteria; the gate remains the export bar; any residual gap is recorded and assigned to the backbone track or follow-up data work.

### Rationale

User call (2026-07-10): raising the recipe target to the gate would define a likely-achievable +0.03–0.04 uplift as failure. One training lever is not obliged to close the whole gap; what matters is that the remainder is tracked, not silently absorbed by the override.

### Alternatives Considered

- **Raise Req 2.4's target to the gate (≥ 0.48)**: Cleaner story — rejected as risking "success defined as failure" for a genuinely useful uplift.
- **Lower the gate to baseline + 0.03**: Rejected in Decision 5 (no steering force).

### Consequences

**Positive:**
- The gate keeps steering without blocking incremental progress; the residual has a named owner.

**Negative:**
- Shipping under the override remains the expected near-term state, so the override-discipline risk from Decision 4 persists.

---

## Decision 14: Carb-priority per-class floors fixed at 0.45 uniform

**Date**: 2026-07-10
**Status**: accepted

### Context

Decision 11 committed to re-deriving the per-class floors alongside the 0.48 gate (Req 1.6). Baseline (pre-re-cut split): `white_rice` 0.6022, `chips_fries` 0.5671, `pasta` 0.5538 clear the old 0.50; `bread_white` 0.4315 and `potato_boiled` 0.4648 fall short; three staples are unmeasured until the Decision 10 re-cut. Req 1.1 also still required a label-space comparability note for the gate derivation.

### Decision

Uniform per-class floor of 0.45 (gate − 0.03) for each of the eight carb-priority staples, replacing model-production Req 3.5's 0.50 via the Req 1.3 amendment pass. Alongside it, the comparability note is recorded (design §3.1): published FoodSeg103 numbers are 103-class mIoU; MeData's 32-food-channel pooled metric is plausibly easier, so the ~0.52 SOTA bounds the harder task and 0.48 stands as an interpolation, not a literature match. Consistency check per Req 1.6: floors below the mean gate, strong staples pull the staple mean above it — no Decision 5 revisit.

### Rationale

User call (2026-07-10). Reachable by the weak staples after Req 2.3's mandatory +0.05 uplift (`bread_white` → ≥ 0.4815); one number to reason about; the strong staples are protected by the no-regression clause rather than the floor.

### Alternatives Considered

- **Keep 0.50**: `bread_white` would need +0.07 — above the required uplift — so the planned path stays export-ineligible on floors alone; inherits the discredited frontier assumption.
- **Ratchet per class (min(0.50, baseline − 0.02))**: More faithful to per-class reality — rejected as eight different numbers needing re-derivation again after the re-cut.

### Consequences

**Positive:**
- Floors and gate come from one derivation and pull in the same direction; the planned uplift path can actually clear them.

**Negative:**
- 0.45 is permissive for the strong staples — their protection is only the ≤ 0.02 no-regression clause.

### Impact

Under the 0.45 floors only `bread_white` (0.4315) is currently below floor; `potato_boiled` (0.4648) clears the floor but not the gate — Decision 18 anchors Req 2.3's uplift set to the gate so both keep the +0.05 obligation. Per-class revisit trigger (design §3.2a): if the re-cut re-measure leaves any staple's baseline below 0.40 (floor unreachable even with the mandatory +0.05), this decision is revisited with a logged outcome.

---

## Decision 18: Req 2.3's uplift set anchors to the gate, not the floors

**Date**: 2026-07-11
**Status**: accepted

### Context

Req 2.3 as approved required +0.05 uplift for "each staple below its floor", with `bread_white` (0.4315) and `potato_boiled` (0.4648) as the worked examples — computed when the floor was 0.50. Decision 14's re-derived 0.45 floor silently dropped `potato_boiled` from the mandatory set (it clears 0.45), changing the requirement's meaning without anyone deciding that.

### Decision

The uplift set is defined as staples below the **re-derived gate** (Decision 5, currently 0.48) at the re-measured baseline. Both `bread_white` and `potato_boiled` remain in the mandatory +0.05 set; the floors stay the export-eligibility backstop.

### Rationale

Preserves the approved intent (both weak staples get the uplift obligation) under the new floors, and is the more coherent anchor: staples below the gate are exactly the ones dragging the mean under the target.

### Alternatives Considered

- **Keep "below its floor"**: Textually unchanged — rejected because it silently shrank the obligation to one class as a side effect of Decision 14, which nobody chose.
- **Enumerate the two staples by name**: Rejected — the set should re-derive mechanically from the re-measured baseline, not be frozen to today's numbers.

### Consequences

**Positive:**
- The requirement means after Decision 14 what it meant when approved.

**Negative:**
- If the re-measure lands a staple at 0.475, it owes +0.05 (to ~0.53) despite nearly clearing the gate — a slightly demanding edge, accepted for the simpler rule.

---

## Decision 15: Co-occurrence matrix built FoodSeg103-internal

**Date**: 2026-07-10
**Status**: accepted

### Context

The co-occurrence loss (research Q2; +3.72% overall FoodSeg103 mIoU) needs a class co-occurrence matrix. The largest published tail-class gains (+16.54%) used Recipe1M+ priors — an external dataset requiring acquisition and licence vetting.

### Decision

Build the matrix from the remapped FoodSeg103 training masks during dataset preparation (`co_stats.json`: per-class pixel counts per split + image-level joint presence counts, training split only; SHA-256 joins the lineage). Recipe1M+ is recorded as follow-up if tail classes stay collapsed after the first run.

### Rationale

User call (2026-07-10): self-contained and reproducible from existing lineage inputs, no human-gated dataset acquisition on the critical path. The loss mechanism — not the specific prior — is the evidenced lever at overall-mIoU level.

### Alternatives Considered

- **Recipe1M+ priors**: The configuration behind the biggest tail gains — rejected for the first iteration; adds a human-gated acquisition and licence work before training can start.
- **No matrix (weighted CE only)**: Already the landed fallback — kept as the documented fallback if the co-occurrence term proves impractical (design §4.3), not the plan.

### Consequences

**Positive:**
- Training can start as soon as the code tasks land; the matrix is reproducible from the dataset already in hand.

**Negative:**
- FoodSeg103-internal priors are weaker than Recipe1M+ priors for tail classes; if the staples stay collapsed, the follow-up is already queued.

---

## Decision 16: Spike latency measured directly on the iPhone 13 Pro Max

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 3.1(c) requires the SegFormer-B0 spike latency on the v1 hardware floor (pipeline Req 8.3). The primary development device is an iPhone 16 Pro; measuring there would need a logged derating argument (A18 Pro vs A15 ANE).

### Decision

Measure on the iPhone 13 Pro Max directly — the device is physically available (user confirmation 2026-07-10). The spike's latency verdict is authoritative; no derating argument is recorded.

### Rationale

Direct measurement on the floor device removes the weakest link in the spike's evidence chain — attention-op ANE behaviour on older Neural Engines is exactly the research's flagged unknown.

### Alternatives Considered

- **16 Pro + derating argument**: Rejected — available only as a fallback; a derating factor for attention ops across ANE generations would itself be an unevidenced number.

### Consequences

**Positive:**
- The spike verdict needs no caveats; pass/fail on criterion (c) is final.

**Negative:**
- The human-gated half of the spike needs the 13 Pro Max physically to hand when it runs.

---

## Decision 17: Initialisation selection order — timm in21k adapter, torchvision V2, or retain COCO-seg DEFAULT

**Date**: 2026-07-10
**Status**: accepted

### Context

Req 2.2 requires initialising from a published checkpoint embodying stronger pretraining than the current weights, with a logged fallback (Decision 12). Candidates for MobileNetV3-Large: timm `mobilenetv3_large_100.miil_in21k_ft_in1k` (ImageNet-21k MIL pretraining, needs a state-dict adapter to the torchvision graph and licence vetting), torchvision `MobileNet_V3_Large_Weights.IMAGENET1K_V2` (improved supervised recipe, zero surgery, BSD-3), and true MIM checkpoints (none published for this backbone — the Decision 12 case). The current init (`DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT`) is COCO-segmentation-pretrained, which already embodies dense-prediction transfer a classification init lacks.

### Decision

Selection order: (1) timm in21k-MIL if the adapter round-trips (identical logits on a probe image vs timm-native) and the licence permits commercial bundling; (2) torchvision `IMAGENET1K_V2` backbone + fresh head; (3) retain the COCO-seg `DEFAULT` if the survey concludes it beats both for this task. Whichever is chosen is logged with source, licence, and SHA-256 in lineage (Req 2.2); outcome (3) triggers Decision 12's "expected uplift revised down" record.

### Rationale

Orders candidates by pretraining strength while making each step falsifiable (adapter round-trip, licence check) rather than aspirational. Explicitly permitting outcome (3) keeps the survey honest — a classification init is not automatically better than a dense-prediction init, and the spec should not force a downgrade to claim novelty.

### Alternatives Considered

- **Mandate the timm checkpoint**: Strongest pretraining — rejected because the adapter or licence may fail, and an unvetted mandate would block the run.
- **Skip the survey, keep DEFAULT**: Rejected — forgoes the evidence-backed pretraining lever without checking its cost.

### Consequences

**Positive:**
- Every survey outcome, including "keep what we have", is a logged, lineage-recorded decision rather than a silent default.

**Negative:**
- The adapter spike is real work that may end in outcome (2) or (3) anyway.

---
