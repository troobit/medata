# Requirements: SNAQ Parity

## Introduction

Estimation work to date has not produced trustworthy results: real-food captures fail with "no volume" or similar refusals, nothing records why, and there is no end-to-end carb-accuracy measurement at all. This cycle makes estimation quality measurable against SNAQ's published real-world figure (per-meal carb MAE ≤ ~13 g, `docs/agent-notes/snaq-benchmark.md`), makes every estimation attempt diagnosable and persistently logged — negative results included — and executes the ranked improvement levers from the verified survey (`docs/agent-notes/estimation-improvement-avenues.md`). The cycle is bounded: it completes when the benchmark produces real numbers, diagnostics are live, and every in-scope lever has an evidence-backed verdict — hitting the target is the mandate's job across cycles, not this spec's exit condition.

## Out of Scope

- The MyFoodRepo-273 dataset bridge — the verified fix for the three absent staples becomes its own spec when reached; this cycle only records the handoff.
- Food-domain SSL pretraining (FeaSC-style) — parked on cost (~V100-weeks) until local hardware changes (survey §4).
- TTA, CRF/boundary refinement, monocular-depth fusion, learned volume correction — survey coverage gaps needing their own research passes first (survey §6).
- Any cloud or remote training — training stays locally runnable on Apple silicon.
- Non-developer diagnostics polish — surfaces are developer-facing; the dev-phase no-disclaimer rule stands (design-handoff-00 Decision 21).
- Changing the estimation-path invariants — no LLM, no network calls, deterministic geometry (unchanged).
- Reaching carb MAE ≤ 13 g — the cycle is complete on verdicts, not on the target (successor cycles inherit).

## Requirements

### 1. Operational carb-accuracy benchmark

**User Story:** As the developer, I want a repeatable carb-accuracy benchmark against weighed meals, so that estimation quality is measured in the same terms as SNAQ's published results.

**Acceptance Criteria:**

1. <a name="1.1"></a>The benchmark SHALL compute per-meal absolute carb error over completed benchmark meals and report: MAE in grams, mean absolute percentage error per meal, the proportion of completed meals within ±10 g, the completion rate (completed vs refused attempts), and the meal count N; MAE figures SHALL never be reported without the accompanying completion rate.  
2. <a name="1.2"></a>Ground-truth carbs SHALL be derived from weighed portions resolved through the bundled food databases (the same CoFID/AFCD lookups estimation uses), so measured error isolates the estimation pipeline rather than database disagreement; the weighing protocol and starting meal set are design decisions (Decision 4).  
3. <a name="1.3"></a>Each benchmark meal record SHALL persist the items, weighed grams, derived ground-truth carbs, the estimate produced, and the model lineage it was produced by, and SHALL reference the outcome records (Req 2) of its estimation attempts, so results are comparable across model versions and attributable per attempt.  
4. <a name="1.4"></a>WHEN a benchmark report is produced, it SHALL state the comparison against the ≤ 13 g SNAQ anchor and the ±10 g-band figures from the reference studies, and record the verdict in the spec's decision log.  
5. <a name="1.5"></a>A refused estimation attempt on a benchmark meal SHALL be recorded against that meal with its refusal reason and reflected in the completion rate — never silently excluded from the report.  
6. <a name="1.6"></a>A headline benchmark report SHALL cover at least 20 meals, and the meal set SHALL include the staple foods of the segmenter staple-floor set — known-weak staples included, with their failures counted per [1.5](#1.5) — or explicitly record which staples are absent and why.  

### 2. Estimation outcome recording

**User Story:** As the developer, I want every estimation attempt recorded persistently on-device, so that negative results are logged as data rather than lost.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN an estimation attempt completes — success or refusal — the system SHALL persist a record on-device (timestamp, outcome, typed failure case where refused, stage measurements) that survives app relaunch.  
2. <a name="2.2"></a>Outcome records SHALL be browsable in-app and exportable off-device (Decision 3).  
3. <a name="2.3"></a>Outcome recording SHALL operate in Release builds, not only DEBUG.  
4. <a name="2.4"></a>Outcome recording SHALL introduce no network activity, and a recording failure SHALL neither alter nor block the estimation result.  
5. <a name="2.5"></a>Outcome-record storage SHALL be bounded (bound and eviction policy are design decisions); WHEN the bound is reached, the oldest records SHALL be evicted rather than recording failing or estimation being affected.  
6. <a name="2.6"></a>Outcome records SHALL contain derived measurements and references to already-persisted artefacts (e.g. mask artefacts), not duplicated raw capture imagery; an export SHALL contain only record contents.  

### 3. Diagnosable failures

**User Story:** As the developer, I want refusals to carry causal detail, so that a "no volume" failure identifies which stage collapsed instead of being a dead end.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN volume recovery fails, the outcome record SHALL contain the measurements needed to distinguish the candidate causes — at minimum per-class recovered volumes both before and after β-correction and thresholding, the β factors applied, counts of discarded degenerate voxels/rays, support-plane fit quality, the resolved scale source, the oblique-view tilt where a second view was used, and food-mask coverage.  
2. <a name="3.2"></a>Currently-silent degradations SHALL be counted and included in the outcome record: degenerate voxel/ray skips, card-pose failure falling back to LiDAR-only scale, and pre-shutter segmentation errors.  
3. <a name="3.3"></a>WHEN estimation refuses on an unexpected (non-typed) error, the outcome record SHALL preserve the underlying error description in Release builds, not only the Swift type name.  
4. <a name="3.4"></a>WHEN estimation succeeds, the outcome record SHALL contain the per-class decomposition of the estimate (class → volume → matched food code → carbs, with the β factor applied), so an inaccurate success is attributable across segmentation, volume, and density error rather than opaque.  
5. <a name="3.5"></a>Failure-message copy citing the superseded device floor (the no-LiDAR message naming the iPhone 13 Pro Max) SHALL be corrected to the Decision 22 floor.  

### 4. Segmentation-tail latency profile

**User Story:** As the developer, I want a measured per-stage latency profile of the deployed segmenter path on the iPhone 16 Pro, so that optimisation effort is spent where the time actually goes.

**Acceptance Criteria:**

1. <a name="4.1"></a>The profile SHALL break end-to-end segmenter latency on the iPhone 16 Pro into at least preprocess, model execution, and upsample/argmax tail, for the bundled model, and record the tail's share of the total in the spec's decision log.  
2. <a name="4.2"></a>The latency budget used for bake-off verdicts (Req 5) SHALL be derived from the measured profile — not the nominal 250 ms whole-pipeline figure — and the derivation recorded before candidate verdicts are recorded.  

### 5. Architecture bake-off

**User Story:** As the developer, I want the shortlisted architectures put through the same conversion-and-measurement spike, so that a backbone decision is made on evidence rather than paper numbers.

**Acceptance Criteria:**

1. <a name="5.1"></a>Each shortlisted candidate (EfficientViT-B0/B1, SeaFormer-Base, PP-MobileSeg-Base; the list MAY be amended with recorded rationale) SHALL receive a verdict against stop-on-fail criteria measured on the iPhone 16 Pro: converts to Core ML, ≤ 24 MiB FP16, and within the latency budget as restated by Req 4.  
2. <a name="5.2"></a>Each candidate verdict SHALL be recorded with its measurements; a candidate failing any stop-on-fail criterion SHALL be rejected without further training investment.  
3. <a name="5.3"></a>Candidate measurements SHALL record observed headroom (size and latency margin), so that future device floors can re-rank candidates without re-running the spikes.  
4. <a name="5.4"></a>At least the highest-ranked candidate passing the stop-on-fail criteria SHALL receive a training run on the 35-class palette judged under [6.2](#6.2) before an adopt verdict; conversion feasibility alone SHALL NOT count as adoption, and feasible-but-untrained candidates SHALL be recorded as handoffs, not verdicts.  

### 6. Training-recipe levers

**User Story:** As the developer, I want the verified training-recipe upgrades run and judged under the established procedure, so that recipe changes land only on evidence.

**Acceptance Criteria:**

1. <a name="6.1"></a>The training pipeline SHALL accept a co-occurrence matrix derived from an external corpus (Recipe1M+ or equivalent) mapped onto the 35-class palette, as an alternative to the FoodSeg103-internal matrix; the derivation SHALL record its palette coverage (which classes gained external statistics) alongside lineage.  
2. <a name="6.2"></a>Every training run in this cycle SHALL be judged by the Decision 21 same-set leak-free procedure against the 0.3776 anchor with staple-floor tolerances, and its verdict recorded.  
3. <a name="6.3"></a>Training runs SHALL NOT reuse the inverse-frequency class weighting attributed as the staple regression cause (segmenter-foundation Decision 25); any re-test of class weighting SHALL use a deliberately milder scheme with recorded rationale.  
4. <a name="6.4"></a>Training runs SHALL be runnable and resumable on the local Apple-silicon machine.  
5. <a name="6.5"></a>A loss-function sweep MAY run opportunistically alongside other retrains; if run, its results SHALL be judged and recorded under the same procedure.  

### 7. Model promotion gate

**User Story:** As the developer, I want the bundled model replaced only on evidence, so that a regression can never ship silently.

**Acceptance Criteria:**

1. <a name="7.1"></a>The bundled model SHALL change only when a candidate beats the current leak-free anchor (mean food-class IoU > 0.3776 with staples within the established tolerances) under the same-set procedure.  
2. <a name="7.2"></a>WHEN a model is promoted, the carb-accuracy benchmark (Req 1) SHALL be re-run against the same meal set; IF headline MAE or completion rate regresses beyond a tolerance set in design, THEN the promotion SHALL be reverted — before/after figures recorded with the decision either way.  

### 8. Bounded cycle completion

**User Story:** As the developer, I want the cycle to end with recorded verdicts, so that the next cycle starts from evidence instead of re-deriving it.

**Acceptance Criteria:**

1. <a name="8.1"></a>The spec SHALL be complete when the benchmark has produced an end-to-end MAE report meeting [1.6](#1.6), outcome recording and failure diagnostics are live on-device, and every in-scope lever (tail profile, each bake-off candidate, external co-occurrence matrix) has an evidence-backed adopt/reject verdict or explicitly recorded handoff; the opportunistic loss sweep ([6.5](#6.5)) needs a verdict only if run.  
2. <a name="8.2"></a>IF the ≤ 13 g target is unmet at completion, THEN the closing record SHALL name the successor work it seeds, including the MyFoodRepo-273 bridge handoff.  
