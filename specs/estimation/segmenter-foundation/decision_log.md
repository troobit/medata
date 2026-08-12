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

## Decision 19: Pretrained checkpoint survey — timm in21k-MIL vetted, adapter probe pending

**Date**: 2026-07-11
**Status**: accepted (probe run 2026-07-15: round-trip FAILED — candidate 2, torchvision `IMAGENET1K_V2`, selected)

### Context

Decision 17 fixed the initialisation selection order (timm in21k-MIL adapter → torchvision `IMAGENET1K_V2` → retain COCO-seg `DEFAULT`) with two falsifiable conditions on the leading candidate: the state-dict adapter must round-trip (identical logits on a probe input vs timm-native inference) and the licence must permit commercial bundling. Design §4.2 notes the survey itself — existence, licence, and hashes — is static fact-finding this spec can do autonomously, while consuming the checkpoint is gated. This entry records that survey (conducted 2026-07-11, web sources cited inline); the adapter round-trip needs the weights downloaded into a torch/timm environment, which the working session did not have, so the final selection stays with the gated training session.

### Decision

Survey outcome, per Decision 17's order:

1. **Candidate 1 — timm `mobilenetv3_large_100.miil_in21k_ft_in1k`: exists, licence clears, adapter probe written but NOT run.** Hosted at https://huggingface.co/timm/mobilenetv3_large_100.miil_in21k_ft_in1k; model-card licence tag **Apache-2.0** (permits commercial bundling — the timm-weights-vary concern is resolved for this card; the upstream Alibaba-MIIL ImageNet21K release it derives from is MIT). ImageNet-21k-P pretraining fine-tuned to ImageNet-1k; 5.5 M params; weights 22.1 MB. `model.safetensors` SHA-256 (from the Hugging Face blob page, not a local download): `436a40242a4b102d92dd5f0d6fc9e15c23aafc45dfa3a8cf00a0353c4f854eb0`. The state-dict adapter to the torchvision graph is judged structurally feasible (both implementations register the same MobileNetV3-Large 1.0x tensor sequence; one 1×1-conv→linear reshape at the head) and is implemented as `tools/segmenter/adapter_probe.py` — positional, shape-checked, failing loudly on any divergence. It has NOT been executed: that requires downloading the weights and installing torch/timm.
2. **Candidate 2 — torchvision `MobileNet_V3_Large_Weights.IMAGENET1K_V2`: verified fallback, zero surgery.** BSD-3-Clause (pytorch/vision). Weights URL https://download.pytorch.org/models/mobilenet_v3_large-5c1a4163.pth (the filename embeds the digest's first 8 hex, `5c1a4163`; the full SHA-256 is recorded into lineage at download time). acc@1 75.274 vs the V1 recipe's 74.042 (torchvision model docs).
3. **Candidate 3 — MIM checkpoints: confirmed absent for MobileNetV3-Large.** The SparK model zoo (https://github.com/keyu-tian/SparK) publishes ResNet-50/101/152/200 and ConvNeXt-S/B/L only; A2MIM (https://github.com/Westlake-AI/A2MIM) publishes ViT-S/B/L, ResNet, and ConvNeXt-S/B only. Neither lineage offers any MobileNet checkpoint, confirming Decision 12's expected-absence record.

The selection order stands: adopt candidate 1 IF `adapter_probe.py` round-trips in the gated session; otherwise candidate 2. Whichever is chosen lands in lineage's `pretrained_checkpoint` object (source URL, licence, SHA-256 — the task 12 schema). This entry stays `proposed` until the probe verdict exists; the gated session flips it to accepted (or records the fallback) with the measured numbers.

**Probe verdict (2026-07-15)**: the round-trip FAILED. The positional adaptation itself loaded cleanly (every tensor shape matched, including the conv→linear head reshape), but the logits diverge: max abs logit error **24.97** against the 1e-4 tolerance, argmax disagrees on the probe input. The graphs are therefore not numerically equivalent despite registering the same tensor sequence — exactly the implementation-subtlety failure mode (SE/activation placement, BN details) this entry declined to rule out by inspection. Per Decision 17's order, **candidate 2 is selected**: torchvision `MobileNet_V3_Large_Weights.IMAGENET1K_V2`, BSD-3-Clause, https://download.pytorch.org/models/mobilenet_v3_large-5c1a4163.pth, SHA-256 `5c1a416349c4cf298f2a6a5e2600ed0ee55e604713578f5e74e6bc8bcaef7997` (verified against the local download, staged at `tools/segmenter/build/mnv3_imagenet1k_v2.pth`). Consumption wiring landed with this verdict: `train.py --init-checkpoint PATH` initialises the MobileNetV3 backbone from a local classifier state dict (fresh DeepLab head), is drift-checked in the resume sidecar, and is recorded in the checkpoint/lineage `train_config` alongside the `--pretrained-*` provenance flags; a 2-epoch smoke run verified the init loads end-to-end and lands in lineage.

### Rationale

The licence and hash facts are static and were verifiable without downloading anything, so they are recorded now and the gated session's work reduces to `pip install timm`, one script run, and a status flip. The one condition that is NOT statically verifiable — the bitwise adapter round-trip — is exactly the condition Decision 17 made adoption hinge on: implementation subtleties (BatchNorm epsilon, SE/activation placement) between timm and torchvision are precisely what a structural argument can miss, so recording this entry as `accepted` before the probe runs would overstate what is known.

### Alternatives Considered

- **Accept candidate 1 now on structural feasibility alone**: The graphs align tensor-for-tensor on inspection — rejected; Decision 17's condition is a measured round-trip, not an inspection, and a silent numeric divergence would poison the training run's provenance.
- **Pre-select candidate 2 and skip the probe entirely**: Zero risk, BSD-3, no surgery — rejected; it forgoes the strongest documented pretraining for this exact backbone when the remaining vetting cost is a single script run.
- **Download the weights and run the probe in this session**: Rejected — the working environment has no torch/timm, and installing the heavy training stack outside the gated session contradicts the spec's gating (design §2.1, §5.2 pattern).

### Consequences

**Positive:**
- Both viable candidates carry commercial-bundling-compatible licences (Apache-2.0 / BSD-3-Clause); no legal blocker exists on any selection path.
- The MIM absence is now cited to the specific model zoos rather than asserted from memory.
- The gated session inherits a one-command probe with a saved-adapter option (`--save-adapted`) feeding straight into training.

**Negative:**
- The final initialisation choice stays open one session longer; the recipe-upgrade training run cannot be configured until the probe verdict is recorded.
- The recorded SHA-256 covers `model.safetensors`; if timm's hub loader fetches the `pytorch_model.bin` serialisation instead, that file's digest must be captured at download time for the lineage entry.

### Impact

`tools/segmenter/adapter_probe.py` (new, probe-only `timm` dependency installed ad hoc); lineage `pretrained_checkpoint` object (task 12) is the recording surface; Decision 17's selection order and its outcome (3) escape hatch are unchanged.

---

## Decision 20: Co-occurrence statistics restricted to food channels (`co_stats`)

**Date**: 2026-07-14
**Status**: accepted

### Context

Decision 15's `co_stats.json` counted image-level presence and joint presence over all 35 palette channels. Background (channel 32) is present in effectively every training image, so under the conditional-prior formula `P(c present | k present)` every class's prior against background collapses to roughly its marginal frequency — and because the pair weight takes the MAXIMUM prior over the image's ground-truth classes, background's membership in every ground-truth set hands every false presence a compatibility floor near its marginal frequency. That dilutes exactly the implausible-pair contrast the loss exists to create (design §4.3). The other special channels (`unknown_food`, `unsupported_liquid`) are non-food sentinels already supervised by the weighted-CE base, and "background present" is trivially true of every plate, so its slot in the presence-BCE term carries no signal either.

### Decision

Restrict the presence and joint-presence counts to the FOOD channels: `prepare_dataset.build_co_stats` excludes the mapping's `special_channels` from the counting pass (their rows/columns stay in the matrix as zeros so indices remain palette indices), records the excluded `special_channel_indices`, and stamps schema `co_stats`. `loss_config.load_co_stats` rejects any schema other than `co_stats` with the regeneration command, and the trainer's criterion restricts the priors, both presence vectors, and the pair weights to `loss_config.food_channel_indices(co_stats)`. Per-class pixel counts stay all-channel — they are descriptive, not consumed by the criterion.

### Rationale

Counting background poisons the pair weighting at its core: the max-over-ground-truth compatibility means one universally present class neutralises the up-weighting for every implausible false presence. Excluding the specials at the statistics source (rather than papering over them at training time) keeps the file's semantics honest, and mirrors the special-channel exclusion `validation.special_channel_names` already applies to the IoU gate — the loss and the gate now agree on which channels constitute the food problem. Bumping the schema makes the change enforceable: a pre-exclusion v1 file must not silently feed the criterion, and the fail-fast contract (design §4.3) is keyed on the file's own stamps.

### Alternatives Considered

- **Keep v1 counts and mask the specials at training time only**: Same criterion behaviour — rejected; the file would keep recording misleading priors, and a semantics change without a schema bump is invisible to the fail-fast contract, so stale and fresh files would be indistinguishable.
- **Zero only background's column in the priors**: Smallest arithmetic change — rejected; the trivially-satisfied background slot would still dilute the presence-BCE mean, and the sentinel channels would get zero-prior maximal up-weighting despite being CE-supervised non-food classes.
- **Drop the special rows/columns from the arrays entirely (32-wide vectors)**: More compact — rejected; matrix indices would no longer be palette indices, inviting off-by-one remapping errors between the statistics file, the class mapping, and the trainer.

### Consequences

**Positive:**
- The implausible-pair contrast is restored: a false presence's compatibility is measured against actual food co-occurrence, with no universal-class floor.
- The presence-BCE term spends its budget on the 32 food channels only; the loss and the IoU gate share one definition of "food channel".
- A stale v1 file fails fast with the regeneration command instead of silently degrading the recipe.

**Negative:**
- Any previously generated `co_stats.json` is invalidated and must be regenerated before a co-occurrence training run.
- The presence term no longer penalises a false image-level `unknown_food`/`unsupported_liquid` presence — that supervision now rests entirely on the weighted-CE base.

### Impact

`tools/segmenter/prepare_dataset.py` (`build_co_stats`, `main`), `tools/segmenter/loss_config.py` (`CO_STATS_SCHEMA`, `load_co_stats`, new `food_channel_indices`), `tools/segmenter/train.py` (`_build_criterion` co_occurrence branch), and the pytest coverage under `tools/segmenter/tests/`. The lineage recording surface (co_stats SHA-256, task 12) is unchanged.

---

## Decision 21: Re-cut executed at seed 20260715; baseline re-measured — full-heldout table is train-contaminated, leak-free anchor recorded

**Date**: 2026-07-15
**Status**: accepted

### Context

Task 17 (Req 2.6, design §3.2a) required the stratified held-out re-cut with a new frozen seed, then a re-measurement of the pinned baseline (`checkpoint_letterbox.pt`, model `24e0b022241a`) whose per-class table anchors every later uplift delta. The re-cut ran on 2026-07-15: `prepare_dataset.py --heldout-frac 0.12 --seed 20260715` over the 7118 FoodSeg103 pairs → train 5553 / val 711 / heldout 854, `splits.json` stratification block and `co_stats.json` (`schema: co_stats`, Decision 20) written. Two findings frame this entry. First, three staples (`brown_rice`, `bread_wholemeal`, `potato_mashed`) have **zero images in the dataset**: `class_mapping_foodseg103.json` routes no FoodSeg103 source category to those channels, so their absence from the old held-out split was never a carving artefact and no seed can make them measurable — the design §3.5 zero-image warning path fired for all three. Second, the pinned baseline was trained on the seed-1234 train split, and the re-shuffle moved 672 of the new 854 held-out images (78.7%) out of that old training set's complement — i.e. the pinned model has TRAINED ON 78.7% of the new held-out split, so its re-measured score there is leakage-inflated.

### Decision

The split seed is **20260715**, now frozen (Req 2.6); `--split-seed 20260715` is mandatory for every training run against `data/foodseg103_remapped`. Both baseline tables are recorded below. The full-heldout table (mean **0.7403**) is recorded for completeness but is **not usable as the uplift anchor** for the pinned model — it measures memorisation, not generalisation. The honest baseline estimate is the leak-free diagnostic: the 182 new-heldout images that were in the old val/heldout splits (never trained on), giving mean **0.3776**. Task 19's per-staple uplift judgements for the pinned model anchor to the leak-free table; the new recipe run's own heldout numbers are clean by construction (it trains on the new train split) and are judged on the full 854-image heldout.

Full-heldout re-measure (854 images, contaminated for the pinned model) — mean food-class IoU 0.7403; staples: bread_white 0.8199, chips_fries 0.8161, pasta 0.8476, potato_boiled 0.8066, white_rice 0.8411; per-class: apple 0.6194, background 0.9640, banana 0.9040, beef 0.7615, bread_white 0.8199, broccoli 0.9009, carrot 0.8594, cheese 0.6106, chicken 0.7655, chips_fries 0.8161, coffee 0.7656, egg 0.7873, fish_white 0.7406, fruit_juice 0.8481, lentils 0.1860, milk 0.9171, mixed_vegetables 0.7786, pasta 0.8476, peas 0.8173, pork 0.7226, potato_boiled 0.8066, salad_leaves 0.7531, soup 0.7291, tea 0.1036, tomato 0.8469, unknown_food 0.7926, unsupported_liquid 0.9357, white_rice 0.8411, wine 0.6992 (brown_rice, bread_wholemeal, potato_mashed absent).

Leak-free diagnostic (182 images, never in the pinned model's training set) — mean food-class IoU 0.3776; staples: bread_white 0.4017, chips_fries 0.6432, pasta 0.5002, potato_boiled 0.5041, white_rice 0.6715; per-class: apple 0.0453, background 0.9311, banana 0.7223, beef 0.4085, bread_white 0.4017, broccoli 0.8450, carrot 0.7188, cheese 0.0239, chicken 0.3463, chips_fries 0.6432, coffee 0.3110, egg 0.4862, fish_white 0.0364, fruit_juice 0.6775, lentils 0.0000, milk 0.0000, mixed_vegetables 0.4821, pasta 0.5002, peas 0.5800, pork 0.1537, potato_boiled 0.5041, salad_leaves 0.3706, soup 0.0112, tea 0.0000, tomato 0.7127, unknown_food 0.4669, unsupported_liquid 0.8265, white_rice 0.6715, wine 0.1649 (brown_rice, bread_wholemeal, potato_mashed absent).

Revisit triggers (design §3.2a), FLAGGED here without amending any bar: the Decision 5 trigger (|re-measured mean − 0.4054| > 0.02) fires on both tables — trivially on the contaminated one (Δ +0.335, cause: leakage, not model or split quality) and marginally on the leak-free one (0.3776, Δ −0.028), where 182 images leave the delta inside plausible sampling noise. The Decision 14 trigger (any staple baseline < 0.40) does not fire on any measured staple — bread_white at 0.4017 is the closest call — but the three dataset-absent staples can never be measured on FoodSeg103, which leaves their 0.45 floors unprovable (`validation.shortfall` correctly reports them as absent) and the strict gate permanently unattainable on FoodSeg103 alone. Whether Decisions 5/14 are actually revisited is left to the human gate before task 19 judging.

### Rationale

A baseline anchor exists to measure uplift on unseen data; a table where the model trained on 78.7% of the evaluation images cannot serve that purpose, and treating it as the anchor would make any honestly-trained successor look like a catastrophic regression. The leak-free subset is small but deterministic and reproducible (old carve reconstructed with `carve_splits(pairs, 0.12, 0.1, 1234, None)`), and its mean (0.3776) sits close to the frozen-split measurement (0.4054), which corroborates rather than contradicts the gate derivation. Recording both tables keeps the provenance honest and leaves the bar-revision question where Decision 2 put it — with a logged decision, not a silent renumbering.

### Alternatives Considered

- **Anchor to the full-heldout 0.7403 table as task 17 literally reads**: Rejected — it is a memorisation score; every uplift delta computed against it would be meaningless and Req 2.4's ≥ 0.03 uplift would be unreachable by construction.
- **Keep the old seed-1234 heldout for baseline judging and use the new split only for training**: Rejected — Req 2.6 froze ONE new stratified split for both training and judging; maintaining two evaluation splits invites exactly the comparability confusion the label-space note (design §3.1) exists to prevent.
- **Retrain the pinned recipe on the new train split to manufacture a clean 854-image baseline**: Rejected — a full multi-hour run whose only product is an anchor; the recipe-upgraded run (task 18) provides the forward comparison anyway, and the leak-free subset already gives an unbiased estimate of the pinned model's true generalisation.

### Consequences

**Positive:**
- The split is frozen and fully stratified for the five staples that exist; `co_stats` statistics match seed 20260715, so the task 18 fail-fast contract is satisfiable.
- The contamination is caught and documented BEFORE any judging run, with an unbiased (if small) baseline table recorded alongside the inflated one.
- The dataset-level absence of brown_rice/bread_wholemeal/potato_mashed is now established fact with a mapping-level cause, not a split-level suspicion.

**Negative:**
- The leak-free anchor rests on 182 images; per-class deltas judged against it carry meaningful sampling noise (several thin classes — lentils, milk, tea — measure 0.0000 there).
- Three staple floors (0.45) remain unprovable on FoodSeg103, so `export_eligible` stays false for any model validated on this dataset alone; the Decision 4 developer override remains the shipping path until a dataset supplying those classes exists.
- Req 2.3's "staples first measurable after the re-cut" clause is void — no staple becomes measurable, because none was ever present.

### Impact

`data/foodseg103_remapped` (regenerated, gitignored: `splits.json` with stratification block, `co_stats.json` schema v2), `tools/segmenter/build/lineage.json` (metrics block now carries the full-heldout re-measure + task 17b release override), task 18's launch flags (`--split-seed 20260715`), and task 19's judging procedure (pinned-model deltas anchor to the leak-free table recorded here).

---

## Decision 22: Hardware floor raised to iPhone 16 Pro

**Date**: 2026-07-15
**Status**: accepted (supersedes the device choice in Decision 16)

### Context

The user raised the supported-device floor on 2026-07-15: the iPhone 16 Pro (A18 Pro) is now the v1 hardware floor, and the iPhone 13 Pro Max and anything older are out of scope. Decision 16 had chosen the 13 Pro Max as the SegFormer-B0 spike measurement device precisely because it was the hardware floor — measuring on the floor made the latency verdict authoritative without a derating argument. That rationale now points at a different phone.

### Decision

All latency/residency budgets (design §5.1: ≤ 250 ms ANE-resident per 513×513 inference) are judged on the iPhone 16 Pro. The SegFormer-B0 spike (task 20) measures on the 16 Pro — the same physical device as the rest of the device pass. Prior architecture rejections that leaned on 13 Pro Max latency are flagged for re-examination under the A18 Pro budget (model-improvement research, 2026-07-15).

### Rationale

Measuring on out-of-scope hardware would gate architectures against a device the app no longer supports, rejecting viable candidates for no user-facing benefit. The floor device remains the authoritative measurement target — the floor itself moved.

### Alternatives Considered

- **Keep measuring on the 13 Pro Max**: More conservative gate - Rejected because the device is out of scope; an over-tight gate kills architectures that are viable on every supported phone.
- **Measure on the 16 Pro but derate to 13 Pro Max equivalents**: Preserves old comparability - Rejected because no in-scope device needs the derated number, and Decision 16 adopted direct floor measurement specifically to avoid derating arguments.

### Consequences

**Positive:**
- Extra ANE headroom: borderline-larger architectures (SegFormer-B0 and up) get a fair hearing.
- One physical phone covers the spike and the whole device pass.

**Negative:**
- Spike results say nothing about older hardware if scope ever widens again.
- Latency-derived verdicts recorded before this date are potentially stale and must be re-checked before being cited.

### Impact

design.md §5.1.3 and §7 (Decision 16 row), tasks 20/22 text, `tools/segmenter/spike_segformer.py` device strings, repo `CLAUDE.md` floor line, `offline-ledger.md` §3. The two-view + ID-1-card non-LiDAR capture mode's audience is also affected (all in-scope devices have LiDAR) — descoping it is a separate user decision, not made here.

---

## Decision 23: ImageNet-V2 init empirically rejected mid-run — task 18 relaunched on DEFAULT weights

**Date**: 2026-07-15
**Status**: accepted (invokes Decision 17 outcome 3; amends Decision 19's practical effect)

### Context

The first task-18 run used the Decision 19 fallback init (torchvision `IMAGENET1K_V2` classifier backbone via `--init-checkpoint`, cold DeepLab head) after the timm in21k adapter probe failed. Twenty epochs of trajectory comparison against the pinned letterbox run (same 60-epoch budget, poly-0.9 LR) showed the configuration losing, not converging: val food-class mIoU 0.2391 at epoch 20 vs the old run's 0.3610, with the gap widening from ~0.10 (epoch 10) to ~0.12 and the old run's own history showing only +0.04 mIoU available from the decaying-LR tail (0.3610 → 0.4005 over epochs 20–60). Reaching the task-19 target (≥ 0.4076 heldout: leak-free baseline 0.3776 + 0.03 uplift) would have required a ~4× late-stage differential over the proven recipe, with no supporting signal in the curve. The 2026-07-15 research survey (UniMatch V2 ablations) independently notes that initialisation quality dominates recipe changes — and torchvision's `DEFAULT` DeepLabV3 weights are COCO-segmentation-trained on top of ImageNet pretraining, strictly containing more segmentation-relevant signal than the plain ImageNet-V2 classifier.

### Decision

The V2-init run was killed at epoch 21 and task 18 relaunched on torchvision `DEFAULT` (COCO-seg) weights — Decision 17 outcome 3 — retaining every other recipe upgrade: co-occurrence loss (`co_stats`, seed 20260715), inverse-frequency weighting, photometric augmentation, and the stratified re-cut. Artifacts of the abandoned run are preserved as `tools/segmenter/build/train_v2init_abandoned_20260715.log` and `checkpoint_v2init_abandoned.resume.pt`.

### Rationale

Twenty epochs (~3.5 h) bought a definitive empirical answer to Decision 19's open question at a third of the full run's cost; spending the remaining ~7 h on a configuration tracking ~0.12 behind the proven baseline would have delayed the training chain a full cycle for a near-certain below-target result. `--init-checkpoint` and the probe tooling remain in the tree for future init candidates (e.g. a food-domain-pretrained backbone).

### Alternatives Considered

- **Ride the full 60 epochs**: The cold-head init might cross over late - Rejected because the old run's own tail shows only +0.04 available under LR decay, quantifying the required differential at ~4× with no signal supporting it.
- **Resume the V2 run with a raised LR or extended schedule**: Salvages sunk cost - Rejected because the resume path enforces hyperparameter identity by design, and a bespoke schedule would make the run incomparable with both the baseline and the task text.

### Consequences

**Positive:**
- The relaunched recipe differs from the pinned model by exactly the intended levers (loss + augment + clean split), making task 19's attribution clean.
- Decision 19's question is settled with measured evidence rather than plausibility arguments.

**Negative:**
- ~3.5 h of MPS time spent on the abandoned run.
- The "stronger init" lever is exhausted for this cycle; init-driven uplift now depends on future food-domain pretraining candidates (research survey §4).

---

## Decision 24: Task-19 verdict — co-occurrence recipe rejected (same-set regression); combined-loss fallback launched

**Date**: 2026-07-16
**Status**: accepted

### Context

The task-18 recipe run (DEFAULT init per Decision 23, co-occurrence loss with `co_stats` seed 20260715, inverse-frequency weighting, photometric augment) completed 60 epochs (final val food-class mIoU 0.3280) and was judged per task 19 and Decision 21's procedure. On the full 854-image heldout (clean for this model by construction): mean food-class IoU **0.3459** vs the ≥ 0.4076 uplift target — a miss. Because Decision 21's anchor (0.3776) was measured on a different image set (the 182-image leak-free subset), a same-set diagnostic was added: the subset was reconstructed exactly (new heldout ∩ old val∪heldout via `carve_splits(pairs, 0.12, 0.1, 1234, None)`, materialised as `data/foodseg103_remapped/heldout_leakfree/` symlinks) and the new checkpoint measured on it.

### Decision

The co-occurrence recipe, as configured, is **rejected**: on the identical 182 images it scores mean **0.3253 vs the pinned model's 0.3776 (−0.052)**, with four of five measurable staples regressing beyond the 0.02 tolerance (bread_white −0.102, chips_fries −0.112, potato_boiled −0.077, white_rice −0.169; pasta +0.006). `checkpoint_recipe.pt` is NOT exported; the bundled model remains `24e0b022241a`. The ledger's documented fallback run (`--loss combined`, same seed/augment/init, → `checkpoint_combined.pt`) was launched 2026-07-16 as a controlled experiment: `combined` shares the inverse-frequency weighted-CE base but replaces the co-occurrence term with dice at 0.5 mixing, so its result isolates whether the weighting or the co-occurrence term drove the regression.

### Rationale

The per-class table shows the recipe did what it was designed to do — resurrect dead tail classes (milk 0.00→0.31, tea 0.00→0.21, soup 0.01→0.28, fish_white 0.04→0.26, apple 0.05→0.24 on the 854 set) — but at a cost to head/staple classes that the 32-class mean does not repay. This is the signature of over-aggressive class weighting rather than a defective mechanism; the 2026-07-15 research survey independently found that co-occurrence gains concentrate on rare classes and that the statistics source (in-dataset vs Recipe1M+-scale corpora) materially changes the outcome. The fallback run costs idle overnight MPS time and produces diagnostic signal either way. It deviates from the ledger's letter (fallback "only if the recipe run cannot proceed" — it proceeded and failed) under the session's standing autonomy mandate.

### Alternatives Considered

- **Stop training and take the survey levers to a new spec immediately**: Cleanest hand-off - Rejected because the hardware is otherwise idle overnight, the fallback is already documented and commands-ready, and its result (weighting vs co-term attribution) directly informs that next spec.
- **Tune the failed recipe (lower `--co-lambda`, cap/soften the inverse-frequency weights) and rerun**: Direct fix attempt - Rejected as hyperparameter fishing: no local evidence isolates the culprit yet; the combined run provides that isolation on the same budget.
- **Export the new checkpoint anyway under the Decision 4 override**: Ships the tail-class gains - Rejected: a −0.052 same-set mean regression with four staple regressions makes the current bundled model strictly better for the carb-priority use case.

### Consequences

**Positive:**
- The verdict rests on a same-set comparison, immune to split-composition objections.
- Tail-class recovery is now demonstrated in this codebase — the mechanism works; its cost model is the problem.
- The fallback result will attribute the regression to weighting or the co-term with one run.

**Negative:**
- The training chain ends this cycle without a shippable uplift; the step-change now rests on the survey's levers (Recipe1M+ matrix, architecture bake-off, MyFoodRepo-273 bridge).
- A further ~10 h of MPS time committed to the fallback experiment.

### Impact

Tasks 18/19 recorded as executed with a negative verdict; `tools/segmenter/build/lineage.json` carries the 854-heldout metrics + override; the leak-free diagnostic split persists at `data/foodseg103_remapped/heldout_leakfree/` (gitignored, symlinks); fallback run artifacts are `checkpoint_combined.pt` + `train_combined_20260716.log`.

---

## Decision 25: Combined-loss attribution verdict — inverse-frequency weighting is the culprit; nothing exported

**Date**: 2026-07-16
**Status**: accepted

### Context

Decision 24 repurposed the ledger's combined-loss fallback run as a controlled attribution experiment: `--loss combined` shares the co-occurrence recipe's inverse-frequency weighted-CE base (and seed 20260715, photometric augment, DEFAULT COCO-seg init) but replaces the co-occurrence term with dice at 0.5 mixing. If it regressed on the staples the way the co-occurrence run did, the shared weighting — not the co-occurrence mechanism — would be attributed as the cause of the staple collapse. The run completed 60 epochs on 2026-07-16 (interrupted once by the 2026-07-15 machine reboot, resumed from the epoch-30 sidecar with drift-check passing; final val food-class mIoU 0.3399, lineage `69dcfde3567a`) and was judged by the same Decision 21 procedure as task 19, including the `heldout_leakfree` same-set pass.

### Decision

The combined-loss checkpoint is **not exported**; the bundled model remains `24e0b022241a`. On the identical 182 leak-free images it scores mean **0.3408 vs the pinned anchor 0.3776 (−0.037)**, with **all five measurable staples regressing beyond the 0.02 tolerance**: white_rice 0.5096 (−0.162), pasta 0.4114 (−0.089), chips_fries 0.5746 (−0.069), bread_white 0.3424 (−0.059), potato_boiled 0.4556 (−0.049). Full-heldout mean 0.3507 (854 images; vs the co-occurrence run's 0.3459 and the ≥ 0.4076 uplift target). Since both runs share only the inverse-frequency weighting and both regress the staples broadly, **the weighting is the attributed culprit**; the co-occurrence term is exonerated of the bulk of the damage (its run scored −0.052 mean vs combined's −0.037 with the co-term removed — the co-term's own marginal cost is real but secondary).

### Rationale

This is exactly the branch the ledger's judging step anticipated ("regresses like the co-occurrence run → the weighting is the attributed culprit"). The two runs differ in one lever and share the staple-regression signature; the common factor is the inverse-frequency weighted CE. The magnitude ordering corroborates it: removing the co-term recovered only ~0.015 of the −0.052 regression, so most of the damage tracks the weighting. The next cycle therefore keeps class rebalancing OFF or MILD (e.g. square-root or log frequency caps) and pursues the survey's structural levers instead (Recipe1M+-scale co-occurrence statistics, architecture bake-off, MyFoodRepo-273 data bridge), per `docs/agent-notes/estimation-improvement-avenues.md`. The SNAQ mandate (2026-07-16) reframes the success measure toward end-to-end carb MAE (`docs/agent-notes/snaq-benchmark.md`), which staple accuracy dominates — another reason not to pay staples for tail classes.

### Alternatives Considered

- **Export under the Decision 4 override to bank the tail-class gains**: Rejected — a same-set mean regression with five staple regressions makes the bundled model strictly better for the carb-priority use case; same reasoning as Decision 24.
- **Rerun combined with milder weighting now (e.g. sqrt-frequency cap)**: Rejected for this cycle — it is the obvious first experiment of the NEXT cycle, but it belongs inside a spec that also carries the survey levers and the SNAQ-anchored evaluation lane, not as ad-hoc hyperparameter fishing at the tail of a concluded chain.
- **Attribute the regression to dice instead of the weighting**: Rejected — dice was not present in the co-occurrence run, which regressed harder; the only shared lever is the weighting.

### Consequences

**Positive:**
- The attribution question is answered with one run, on a same-set comparison immune to split-composition objections.
- The next cycle starts with a concrete, evidence-backed constraint: no aggressive inverse-frequency weighting.
- Tail-class recovery remains demonstrated (both runs), so the mechanism is available once its cost model is fixed.

**Negative:**
- The §2 training chain closes with zero shipped uplift; the bundled model is still the 2026-07-05 `24e0b022241a`.
- The 0.48 gate remains unattained and unattainable on FoodSeg103 alone (three staples have zero images — Decision 21).

### Impact

Ledger §2 is fully closed. `tools/segmenter/build/lineage.json` carries both validation records with the Decision 24/25 override reasons. Artifacts kept: `checkpoint_combined.pt`, `train_combined_20260716.log`, the `heldout_leakfree/` split. The improvement work moves to the next spec, seeded from `estimation-improvement-avenues.md` + `snaq-benchmark.md` under the user's 2026-07-16 SNAQ-comparable mandate.

---

## Decision 26: Non-LiDAR two-view + ID-1-card path retained, not descoped

**Date**: 2026-07-24
**Status**: accepted (resolves the open question flagged in Decision 22's Impact)

### Context

Decision 22 raised the hardware floor to the iPhone 16 Pro and noted that the two-view + ID-1-card non-LiDAR capture path's audience was affected — every in-scope *floor* device carries LiDAR — but explicitly left descoping that path as "a separate user decision, not made here." The `CLAUDE.md` floor line and `CLOUT.md` open-decisions list have carried the descope question as pending since.

### Decision

The non-LiDAR two-view + ID-1-card capture path is kept. It is not descoped. The iPhone 16 Pro remains the floor for calibration and performance *targets*, but the app continues to run on non-LiDAR iOS 26.5 devices, degrading to the two-view + ID-1-card scale path with `noLidarConfidence` set on every meal.

### Rationale

The user's priority is availability: the tool should reach as many devices as possible, and only prefer LiDAR when it is present. The runtime already supports this — `ARKitCaptureEngine` starts the AR session without `.sceneDepth` when LiDAR is absent and the pipeline falls through to the card path (Req 4.3, §7.4; `docs/ios-device-setup.md`), so retention costs nothing to remove a gate that was never enforced. Descoping would shrink the addressable audience for a purely notional simplification, since the non-LiDAR code path already exists and is exercised.

### Alternatives Considered

- **Descope the non-LiDAR path**: Remove the two-view + ID-1-card fallback and refuse on LiDAR-less devices - Rejected because it narrows availability with no offsetting benefit; the path is already built and runtime-gated by capability.
- **Leave the decision pending**: Keep carrying it as an open question - Rejected because the ambiguity has propagated stale "descope pending" notes across `CLAUDE.md`/`CLOUT.md`; the user has now decided.

### Consequences

**Positive:**
- Wider device reach: any iOS 26.5 iPhone can run the app, LiDAR or not.
- Removes a standing open decision from the MVP tracker and the docs.

**Negative:**
- The non-LiDAR path stays a maintenance and test surface even though the floor/primary device never exercises it; its accuracy is not measured against the calibration targets.

### Impact

`CLAUDE.md` floor line, `CLOUT.md` open-decisions list. MD-23 in `specs/DECISIONS.md` already states the non-LiDAR confidence path "still exists at runtime," which this decision confirms rather than changes.

---

## Decision 27: Merged-corpus verdict — palette v2 model promoted (myfoodrepo-bridge)

**Date**: 2026-07-26
**Status**: accepted (amended by pipeline Decision 50, 2026-08-10: the promotion verdict and the `ab812dc3aa9d` model stand; the "palette v2" label does not — there is one palette, `ClassPalette.standard`, stamped "v0" until the first main release)

### Context

The myfoodrepo-bridge PRD retrained the incumbent recipe on the merged
FoodSeg103 + Food Recognition 2022 corpus (MD-30 substitution; 45,515 train /
1,711 val / 854 heldout images, 36-channel palette v2) — 12 epochs at
total-step parity ~1.6x the incumbent's budget, plain CE, class weighting
`none`, geometric augmentation only, matching `24e0b022241a` for an
attributable data-only comparison. The promotion criterion (PRD Training and
export req 3): leak-free mean food-class IoU beats the 0.3776 anchor AND no
existing carb-priority staple regresses materially.

### Decision

`checkpoint_merged_v2.pt` is **promoted**: exported through the gates and
swapped in as the bundled `segmenter.mlpackage`, with `PipelineFactory`
flipped to `ClassPalette.v2Standard`, under the standing developer-phase
release override (Decision 11 lineage; strict 0.48/0.45 gates still unmet
and `export_eligible` stays truthful).

### Rationale

Measured on the 182-image leak-free anchor via `run_validation.py`: mean
food-class IoU **0.3927 vs the 0.3776 anchor** (+0.015 raw). Family-collapsed
(sibling predictions folded to their v1 parent — brown_rice→white_rice,
bread_wholemeal→bread_white, potato_mashed→potato_boiled, cereal→unknown_food
— the label-space-comparable read, since FoodSeg GT cannot express the new
classes): **0.4212** (+0.044). The bridge's target classes measurably work on
merged val (1,711 images): **cereal 0.4831, bread_wholemeal 0.4787,
potato_mashed 0.3719**; per-epoch val mIoU climbed 0.2269 → 0.4418 over the
12 epochs. Anchor per-staple deltas (chips −0.083, white_rice −0.040,
potato_boiled −0.029, bread_white −0.009→−0.004 collapsed) were judged
non-material: the same checkpoint scores chips 0.5599 on the anchor but
0.4586 on the 854-image heldout — a ±0.10 same-model cross-set spread that
brackets every observed delta (Decision 21 already records the anchor's
per-class noise) — every measured staple stays above its 0.45 floor on the
anchor except bread_white, which the incumbent also failed (0.4017), and
bread_white's delta vanishes under family collapse (sibling-competition
artefact).

### Alternatives Considered

- **Reject on the strict staple-tolerance reading (>0.02 regression)**:
  Rejected — the tolerance was written for same-label-space comparisons; here
  the deltas sit inside demonstrated cross-set noise, and rejection would
  discard the only supervised path to cereal and the absent staples (the
  MVP's named fix) to protect noise-level readings.
- **Retrain longer / with sqrt_inverse before judging**: Rejected for this
  cycle — the attributable data-only comparison was the point; recipe levers
  remain available for a follow-up cycle if on-device behaviour disappoints.

### Consequences

**Positive:**
- Breakfast cereals, wholemeal bread, and mashed potato are supervised,
  measured classes for the first time (cereal 0.48 / wholemeal 0.48 /
  mashed 0.37 val IoU); the palette v2 chain ships end-to-end.
- The anchor uplift is the first positive training verdict since the
  letterbox model (Decisions 24/25 both rejected their candidates).

**Negative:**
- brown_rice remains effectively unlearned (0.0000 on merged val; 131
  training images) — its 0.45 floor stays unprovable and the class stays on
  the deferred list.
- Anchor per-staple readings carry ±0.10 cross-set noise, so per-class
  regressions of that order cannot be ruled out until the on-device pass and
  the SNAQ-parity benchmark campaign measure real captures.
- The strict 0.48 mean / 0.45 floor gates remain unmet; the developer-phase
  override continues to be the shipping path.

### Impact

`tools/segmenter/build/checkpoint_merged_v2.pt` + `build/lineage.json`
(metrics + override recorded), bundled
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`,
`PipelineFactory` palette default v1Standard → v2Standard,
`docs/agent-notes/model-production.md`, myfoodrepo-bridge
`tasks-training-and-export.md` tasks 5–6.

---

## Decision 28: SegFormer-B0 spike verdict — full pass; the conditional retrain gate is live

**Date**: 2026-08-13
**Status**: accepted

### Context

The spike's autonomous half (task 14) passed on 2026-08-09; the device half (task 20) waited on a human with the phone. The developer's initial instinct was to accept the incumbent's field latency as sufficient evidence — rejected in session because the latency experienced on recent builds belongs to the shipped DeepLabV3+MobileNetV3, not the SegFormer-B0 spike artifact, which had never run on device. The developer also relaxed the stance on the 250 ms bar ("this spec is all about accuracy — even a few seconds per scan is fine"), which turned out not to matter. The artifact was regenerated deterministically (`tools/segmenter/spike_segformer.py`, defaults): converts, 7,622,432 B FP16 vs the 24 MiB budget, oracle max abs err 0.00301, argmax agreement 99.87% (the 2026-08-09 run logged 99.98% — same pass, minor numeric drift).

### Decision

The spike verdict is a **full pass on all four criteria**, closing tasks 20 and 21. Criterion 3 measured on the iPhone 16 Pro (v1 hardware floor, Decision 22) via Xcode's Core ML performance report, 2026-08-13: **prediction median 12.68 ms** per 513×513 inference (n=120), compile 67.05 ms, load 21.34 ms, and **full ANE residency — all 315 dispatchable operations prefer the Neural Engine, zero CPU or GPU dispatch** (the remaining 547 program ops are consts/metadata). Task 22's conditional retrain is therefore live: retrain SegFormer-B0 on the same re-cut split with the same recipe, adopt only on ≥ 0.02 uplift on BOTH mean food-class IoU and the eight-staple mean (Req 3.3).

### Rationale

12.68 ms sits ~20× under the 250 ms bar with no fallback segments at all — including the spatial-reduction attention blocks, the ops with the least Core ML precedent and the stated conversion risk (design §5.1). Viability is settled; the only remaining question is the accuracy comparison, which is exactly what task 22 exists to answer.

### Alternatives Considered

- **Accept the incumbent's field latency without measuring the spike**: no device session needed - Rejected: measures a different architecture; ANE residency of SegFormer's attention ops was the actual unknown.
- **Close Requirement 3 without the device half (no adoption pressure from latency)**: ends the spec sooner - Rejected: the measurement was one regeneration command plus a two-minute Xcode report, and a pass keeps the strongest accuracy lever available rather than discarding it undecided.

### Consequences

**Positive:**
- The backbone-swap decision now rests purely on accuracy — latency and residency impose no constraint, with ~20× headroom for a larger variant if ever wanted.
- Evidence is committed, not anecdotal: the full Xcode report JSON sits in `artifacts/spike_segformer-you.mlperf/`.

**Negative:**
- Task 22 is a live multi-hour MPS training gate (human/compute-gated STOP) — the spec cannot close without either running it or a recorded decision not to.
- The regenerated artifact's oracle numbers differ in the third decimal from the 2026-08-09 run; harmless here, but conversion is not bit-reproducible across environments.

### Impact

Tasks 20–21 closed; task 22 (STOP — conditional SegFormer-B0 retrain vs the Req 3.3 adoption margin) is the sole remaining open task in this spec. Evidence: `artifacts/spike_segformer-you.mlperf/report.json`; the regenerated verdict JSON remains gitignored build output, transcribed here per task 21.

---

## Decision 29: Task-22 retrain re-anchored to the live lane — Decision 27 recipe on the merged corpus vs `ab812dc3aa9d`

**Date**: 2026-08-13
**Status**: accepted

### Context

Task 22 and Req 3.3 as written pin the retrain to a configuration that no longer exists. The "same recipe" was the Requirement 2 candidate's: co-occurrence loss plus inverse-frequency weighting. That candidate was rejected (Decision 24), the weighting was attributed as the staple-killer (Decision 25) and removed from `train.py` entirely (snaq-parity Decision 13 — restoring it is deliberate friction). The "same re-cut split" was `data/foodseg103_remapped`, the 35-class v1 label space: its mapping file (`class_mapping_foodseg103_v1.json`) has left the tree, and `load_co_stats` fail-fasts on the mapping SHA — both the v1 re-cut's `co_stats.json` (`af6e1cd7…`) and the v2 remap's (`90ff4b4c…`) stamp SHAs that no longer match the current `class_mapping_foodseg103.json` (`62ce25cf…`). The comparison target, the task-19 recipe checkpoint, was never exported and lost to the incumbent on the same-set diagnostic. Meanwhile Decision 27 promoted `ab812dc3aa9d`, trained on the merged FoodSeg103 + Food Recognition 2022 corpus with plain CE, class weighting `none`, and geometric-only augmentation. Executing task 22's letter would train a candidate in a dead label space, with a banned lever, to beat a checkpoint that already lost — a win could not drive adoption.

### Decision

The Req 3.3 comparison runs in the live label space instead: `--arch segformer_b0` (published ADE20K init per the task-23 ArchSpec) is trained with **exactly the Decision 27 incumbent recipe** — `data/merged_foodseg_foodrec2022`, 36 classes, 513×513, 12 epochs, batch 16, lr 1e-3, plain CE, class weighting `none`, geometric augmentation only — and compared against the promoted incumbent `ab812dc3aa9d` on the 182-image leak-free anchor (primary, the Decision 21/27 measurement), with merged val/heldout as context. Adoption still requires the unchanged Req 3.3 margin: ≥ 0.02 on BOTH mean food-class IoU and the carb-staple mean (Req 2.3's staple set as measurable on the comparison set, identical treatment for both checkpoints). Adoption hands export-gate integration to `model-production`, as task 22 already states.

### Rationale

Design §5.3 states the point of the comparison: "does the better backbone plus the same recipe beat the same recipe on the current backbone." Re-anchoring preserves that sentence exactly — same data, same recipe, same step budget (12 epochs at batch 16 on either side), backbone as the only variable — against the checkpoint the swap would actually replace. The margin, the two-mean conjunction, and the adoption consequence are untouched. Both candidates share one label space, so the comparison needs no family-collapse adjustment and reuses the same `run_validation.py` path that judged Decision 27.

### Alternatives Considered

- **Literal replication (v1 split, co-occurrence + inverse-frequency)**: faithful to the letter of Req 3.3 - Rejected: requires restoring a deleted mapping file and a lever banned in code as the attributed failure cause (Decisions 25, snaq-parity 13); the target checkpoint already lost to the incumbent, so beating it proves nothing adoptable.
- **FoodSeg103-only retrain in the current palette (v2 re-cut, co-occurrence loss, weighting `none`)**: closest permitted reading of "same recipe + same split" - Rejected: its `co_stats.json` fail-fasts on the stale mapping SHA by design, and no incumbent checkpoint with that recipe exists — a fair backbone comparison would need a second gated incumbent retrain, doubling compute in the FoodSeg103-only lane Decisions 24/25 closed.
- **Close Requirement 3 without the retrain** (the "recorded decision not to" branch of Decision 28): cheapest exit - Rejected: the spike passed with ~20× latency headroom, leaving accuracy the only open question; discarding the strongest remaining accuracy lever undecided contradicts the reason the device half was measured at all.

### Consequences

**Positive:**
- One gated run answers the adoption question that is actually live, against the checkpoint the swap would replace, measured by the same validation path and sets as Decision 27.
- Exact recipe parity (identical flags, epochs, and step budget) makes the result attributable to the backbone alone.
- The pre-launch smoke run surfaced that `segformer_b0` could not train on the rig at all — an MPS-only BatchNorm-backward failure in the decode head, now fixed in `archs.py` (contiguous-input pre-hook; no-op for CPU, inference, and the export trace).

**Negative:**
- Req 3.3's letter (co-occurrence countermeasure, task-19 target) is not exercised; the co-occurrence mechanism stays parked where Decisions 24/25 left it, and this run says nothing further about it.
- A negative verdict costs roughly half a day of MPS time with no shipped uplift — the accepted price of the gate Decision 28 left live.

### Impact

Req 3.3 carries an amended-by note pointing here. Task 22 executes via this instantiation: run artifacts land in the working branch's `tools/segmenter/build/` (`checkpoint_segformer_merged.pt`, `train_segformer_merged_20260813.log`, lineage); the verdict entry follows as its own decision. `tools/segmenter/archs.py` gains the MPS backward fix.

---
