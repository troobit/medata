# Decision Log: SNAQ Parity

## Decision 1: One cycle spec, dataset bridge spun off later

**Date**: 2026-07-17
**Status**: accepted

### Context

The improvement cycle spans three strands — a SNAQ benchmark/evaluation lane, estimation diagnostics, and the ranked model levers from `docs/agent-notes/estimation-improvement-avenues.md`. They could be one spec, several, or have the diagnostics carved out for speed.

### Decision

A single full spec under `specs/estimation/` covers benchmark + diagnostics + model levers, with benchmark and diagnostics as the leading strands. The MyFoodRepo-273 dataset bridge is referenced but becomes its own spec when reached.

### Rationale

The strands are interdependent: the benchmark needs outcome recording to measure anything, and the levers need the benchmark to be judged honestly. One spec keeps the evidence chain in one place — the same precedent segmenter-foundation set for its recipe + spike + gates bundle. The dataset bridge is the one strand big and separable enough to stand alone.

### Alternatives Considered

- **Diagnostics smolspec first**: fastest route to diagnosable device-pass logs - Rejected because the diagnostics likely exceed smolspec bounds (multiple pipeline stages plus persistence plus UI) and would still need a deploy; splitting saves little.
- **Three specs upfront** (benchmark+diagnostics / model levers / dataset): maximum separation - Rejected because it forces three requirements/design/approval cycles before any work starts, for strands that share one evidence chain.

### Consequences

**Positive:**
- One evidence chain, one decision log, one task list for the whole cycle.
- Benchmark and diagnostics land first, so lever verdicts are measured, not vibes.

**Negative:**
- A larger spec to review and keep current.
- The dataset bridge handoff must be recorded explicitly or it gets lost at cycle end.

---

## Decision 2: Spec name — snaq-parity

**Date**: 2026-07-17
**Status**: accepted

### Context

The spec needs a folder name under `specs/estimation/`. Candidates: `snaq-parity`, `estimation-uplift`, `accuracy-cycle-1`.

### Decision

`specs/estimation/snaq-parity/`.

### Rationale

Names the goal directly — the mandate is "iterate until comparable to SNAQ", and the benchmark note pins that to measurable figures. User selected it from the three candidates.

### Alternatives Considered

- **estimation-uplift**: neutral, survives target revision - Rejected as vaguer than the actual mandate.
- **accuracy-cycle-1**: numbered-cycle naming - Rejected; cycle numbering adds nothing while the target has a name.

### Consequences

**Positive:**
- The folder name states the success criterion.

**Negative:**
- If the SNAQ anchor is ever replaced as the reference, the name lags the target.

---

## Decision 3: Outcome records persisted on-device, browsable and exportable

**Date**: 2026-07-17
**Status**: accepted

### Context

Estimation failures ("no volume" and similar) currently surface as a chip with no causal breadcrumbs: volume-stage measurements are not logged, degenerate voxels/rays are silently skipped, and most stage diagnostics are DEBUG-only. The user mandate is that negative results be logged as data. The question was where that evidence should live.

### Decision

Every estimation attempt — success or refusal — persists a record on-device (outcome, failure case, stage measurements) that survives relaunch, is browsable in-app, and is exportable off-device.

### Rationale

Persisted records serve both mandates at once: negative results become durable data, and the benchmark lane gets its per-meal outcome storage for free. Log-only capture requires tethered collection (`sudo make logs-device`, root-only) at exactly the moment the developer is holding food in one hand and the phone in the other.

### Alternatives Considered

- **Device log only** (promote DEBUG lines to Release): smallest change - Rejected because tethered root-only collection makes real-meal testing impractical and nothing survives for the benchmark.
- **Persisted but no in-app browsing** (export-only): less UI work - Rejected by the user; in-app browsing chosen as part of the recommended option.

### Consequences

**Positive:**
- Failures are diagnosable in the field, at the kitchen table, without a tether.
- The benchmark meal set and the outcome store share one persistence mechanism.

**Negative:**
- New storage plus a developer-facing browsing surface to design and build.
- Storage growth needs a bounding policy (design decision).

---

## Decision 4: Ground-truth weighing protocol deferred to design

**Date**: 2026-07-17
**Status**: accepted

### Context

The SNAQ-comparable target only means something against weighed ground truth (weighed items resolved through a food-composition database — the protocol every reference study uses). Options were to commit now to a kitchen-scale protocol, use package weights, or defer the details.

### Decision

Requirements state only that ground truth derives from weighed portions resolved through the bundled food databases; the exact weighing protocol and the starting meal set are design-phase decisions.

### Rationale

The user chose to decide the practicalities in design. The requirement pins what matters for testability (weighed ground truth, same DB as estimation, persisted meal records); scale choice, weighing precision, and meal-set composition don't change the acceptance criteria.

### Alternatives Considered

- **Kitchen scale, grow the set now**: starts measurement immediately with foods on hand - Not selected; folded into design where the protocol can be specified properly.
- **Package weights for now**: no scale needed - Not selected; looser error bars would blur an already order-of-magnitude target.

### Consequences

**Positive:**
- Requirements stay implementation-free and stable while the protocol is worked out.

**Negative:**
- The benchmark lane cannot start producing numbers until design settles the protocol.

---

## Decision 5: Bounded cycle, not target-gated

**Date**: 2026-07-17
**Status**: accepted

### Context

The mandate — iterate until carb estimation is SNAQ-comparable — potentially spans several cycles. A spec needs a defined completion state: open until the ≤ 13 g target is measured, or bounded by this cycle's deliverables.

### Decision

The spec is complete when the benchmark produces an end-to-end MAE report, diagnostics are live on-device, and every in-scope lever has an evidence-backed adopt/reject verdict. If the target is unmet, the closing record seeds the successor spec.

### Rationale

Target-gated specs never close on a hard research problem; segmenter-foundation's bounded shape (execute, judge, record, hand off) kept verdicts honest through two negative training results. The mandate lives across cycles; each spec is one falsifiable pass.

### Alternatives Considered

- **Target-gated** (open until MAE ≤ ~13 g): mirrors the mandate literally - Rejected because an unbounded spec cannot be planned into tasks, and a run of negative verdicts would leave it permanently "in progress".

### Consequences

**Positive:**
- The cycle can end honestly on negative results — which is the point of logging them.
- Successor work (including the dataset bridge) gets an explicit seeding record.

**Negative:**
- "Done" may arrive with the headline target still unmet, which reads oddly against the spec's name.

---

## Decision 6: Review-cycle amendments to the requirements

**Date**: 2026-07-17
**Status**: accepted

### Context

The design-critic review found two critical and five major gaps in the initial requirements, chiefly around measurement honesty: MAE without a completion rate is gameable by refusing hard meals; no meal-count floor meant N=2 satisfied the benchmark; the promotion gate used mIoU while the spec's success metric is carb MAE; the "no volume" record omitted β-correction and oblique tilt — the quantities that actually push volumes under the 1 cm³ threshold; and successful-but-inaccurate estimates had no attribution path at all. External peer validators are unavailable (known-broken), so findings were verified by self-review against the pipeline source and prior decisions instead.

### Decision

All critical and major findings folded into the requirements: headline MAE is always paired with a completion rate and refusals count against it (1.1, 1.5); reports need ≥ 20 meals including the staple-floor foods (1.6); outcome records get storage bounding with oldest-first eviction (2.5), a no-raw-imagery content rule (2.6), β/tilt in failure records (3.1), and per-class decomposition for successes (3.4); the bake-off latency budget derives from the measured tail profile (4.2); the top feasible candidate must be trained and judged before adoption (5.4); promotion reverts on MAE or completion-rate regression (7.2); and cycle completion accepts explicit handoffs for untrained candidates and an unrun loss sweep (8.1). The stale 13 Pro Max failure copy is corrected in passing (3.5).

### Rationale

Each amendment closes a path by which the cycle could report success while hiding the behaviour the user is dubious about — the review's common thread. The ≥ 20-meal floor sits at the bottom of the reference studies' range (24–54 meals) as an order-of-magnitude bar, matching the snaq-benchmark note's honesty caveat.

### Alternatives Considered

- **Defer measurement-definition details to design**: keeps requirements shorter - Rejected because completion rate, meal floor, and promotion gating change what "the benchmark passed" means; they are acceptance criteria, not mechanisms.
- **Gate promotion on mIoU only, MAE advisory**: simpler gate - Rejected; a model shipping on mIoU while regressing carb MAE contradicts the spec's own success metric.

### Consequences

**Positive:**
- The benchmark cannot post a flattering number by excluding refusals or weak staples.
- A "no volume" failure record now distinguishes geometry collapse from genuinely sub-threshold food.

**Negative:**
- The ≥ 20-meal floor and staple coverage raise the manual effort of the first headline report.
- Training the top bake-off candidate (5.4) makes the cycle materially longer than a feasibility-only bake-off.

---

## Decision 7: Outcome records live in dedicated tables, bounded at 500 rows

**Date**: 2026-07-17
**Status**: accepted

### Context

Req 2 needs per-attempt records persisted on-device. The Persistence module offers two homes: rows in the generic `events` log, or dedicated tables following the `quick_presets` precedent (own store methods, no `eventsDidChange` coupling).

### Decision

Two new tables — `estimation_outcomes` (bounded at 500 rows, oldest evicted inside the insert transaction) and `benchmark_meals` — appended via `CREATE TABLE IF NOT EXISTS`, `schema_version` → 6.

### Rationale

Outcome records are developer telemetry, not timeline events: they must never appear in Records/Graph, need bounded eviction the events retention sweep doesn't provide, and carry structured JSON rather than a canonical scalar. The codebase already states this convention explicitly for `quick_presets`. 500 rows ≈ months of dev-phase captures at a few KB each — generous for diagnosis, trivial for storage.

### Alternatives Considered

- **`events` rows with a new `EventType`**: reuses existing plumbing - Rejected; would leak into event consumers, and eviction semantics differ from the events retention sweep.
- **File-per-record artefacts** (MaskArtefactWriter style): no schema change - Rejected; unqueryable for the benchmark join and the browser.

### Consequences

**Positive:**
- Benchmark reporting is a straightforward join on indexed tables.
- Eviction is one DELETE in the same write — atomic by construction.

**Negative:**
- Schema version bump and new store surface to maintain.

---

## Decision 8: Diagnostics accumulator with defer-handoff; write-behind persistence

**Date**: 2026-07-17
**Status**: accepted

### Context

Stage measurements (Req 3) originate deep inside `Pipeline.estimate`, which exits by return on success and by `throw` on all 16 failure cases. Req 2.1 requires a record either way; Req 2.4 forbids recording from altering or blocking the result.

### Decision

A reference-type `PipelineDiagnostics` accumulator is created at the top of `estimate`, appended to by stage helpers, and handed to a new `didCompleteAttempt` delegate callback from a `defer` — firing exactly once per attempt on both exits. The App layer persists it in a detached fire-and-forget task; store errors are logged and swallowed.

### Rationale

The defer-handoff is the only single-seam way to catch every exit path without duplicating the catch ladder or weaving diagnostics into 16 throw sites. Write-behind isolation makes Req 2.4 structural rather than conventional. Estimators return stats structs (skip counters) instead of logging, keeping MedataCore maths pure and testable.

### Alternatives Considered

- **Enrich thrown errors with diagnostics payloads**: no delegate change - Rejected; bloats every failure case, and the success path still needs a second mechanism.
- **Persist from inside the Pipeline**: no App involvement - Rejected; Pipeline gains a store dependency and the write lands on the estimation task, violating Req 2.4's isolation.

### Consequences

**Positive:**
- One code path covers success, refusal, and non-typed errors.
- Recording failures are provably invisible to the capture flow.

**Negative:**
- Estimator return types change (internal API churn covered by existing maths tests).
- A crash mid-attempt loses that attempt's record — accepted; the record is telemetry, not ledger.

---

## Decision 9: Benchmark is in-app end-to-end; meal/attempt semantics; protocol

**Date**: 2026-07-17
**Status**: accepted

### Context

Resolves Decision 4's deferral and the two validation flags (execution surface, attempt-vs-meal semantics). The user chose in-app ground-truth entry over a CSV + Mac harness.

### Decision

`BenchmarkView` handles meal creation (palette classes + weighed grams; truth carbs derived from the bundled DB at save; fidelity `weighed`/`package` recorded). Captures launched from a meal tag their outcome rows. Semantics per model lineage: a meal is completed if ≥ 1 attempt completed; completion rate = completed ÷ attempted meals; per-meal error uses the latest completed attempt; attempts-per-meal is reported. Protocol: items weighed to ±1 g before plating; starting set is the foods on hand (lemon, cereal + milk, bread, basics), growing to ≥ 20 meals including the staple-floor foods.

### Rationale

Everything happens at the kitchen table on one device — no two-device bookkeeping per meal. Latest-completed-attempt keeps retries honest (attempts stay visible; a meal can't fail its way out of the denominator). Deriving truth via the same DB lookups as estimation makes the comparison DB-neutral (Req 1.2).

### Alternatives Considered

- **CSV + Mac harness join**: less app UI - Rejected by the user; per-meal bookkeeping across two devices invites transcription errors.
- **First-attempt-only scoring**: stricter - Rejected; punishes benign retakes (framing/lighting) the reference studies also allowed, while completion rate already exposes systematic refusal.

### Consequences

**Positive:**
- Benchmark meals, attempts, and reports share one store and one export.
- Package-weight fallback lets testing start today, marked honestly.

**Negative:**
- Two new app screens to build before the first headline report.
- Truth quality depends on kitchen discipline; the protocol lives in this spec, not in code.

---

## Decision 10: Promotion tolerance is a paired one-sided bootstrap, not fixed grams

**Date**: 2026-07-17
**Status**: accepted

### Context

Req 7.2 reverts a promotion that regresses benchmark MAE "beyond a tolerance set in design". At N≈20 the MAE's noise is of the same order as plausible real regressions; a fixed gram threshold would either revert good models or admit bad ones depending on dispersion.

### Decision

For meals completed under both lineages: revert if the one-sided 95% bootstrap confidence interval (10 000 resamples, fixed seed) of the mean paired per-meal error delta shows a regression, or if completion rate drops by more than one meal.

### Rationale

Pairing removes between-meal variance — the dominant noise term; the bootstrap ties the tolerance to observed dispersion exactly as the requirements review demanded; the fixed seed keeps the verdict deterministic and re-runnable.

### Alternatives Considered

- **Fixed gram tolerance (e.g. +2 g)**: simple - Rejected; ignores dispersion, arbitrary at small N.
- **Paired t-test**: standard - Rejected in favour of bootstrap; error deltas at N=20 with refusal-censoring are not plausibly normal, and the bootstrap is as cheap to implement deterministically.

### Consequences

**Positive:**
- The gate self-adjusts as the meal set grows.

**Negative:**
- Only meals completed under both lineages pair up — heavy refusal overlap shrinks the effective N (the completion-rate clause backstops this).

---

## Decision 11: Tail profile comes from Release sub-stage clocks in outcome records

**Date**: 2026-07-17
**Status**: accepted

### Context

Req 4 needs a preprocess/model/tail latency breakdown on the 16 Pro. No such granularity exists — the pipeline times segmentation as one DEBUG-only interval, and SegBench measures accuracy only.

### Decision

`CoreMLSegmenter.segment` gains sub-stage clock stamps (preprocess, prediction, argmax/upsample) that run in Release and land in every outcome record; the profile is read from real captures via the log browser/export. ANE residency is confirmed once with the Xcode Core ML performance report. The bake-off budget is then derived as 250 ms minus the measured non-model share and recorded in this log before any candidate verdict (Req 4.2).

### Rationale

Lane A already ships the collection mechanism, so the profile costs three clock stamps and reflects real capture conditions rather than a synthetic bench. The Xcode report covers the one thing wall-clocks can't see (compute-unit residency) — the same split the task-20 spike method uses.

### Alternatives Considered

- **Dedicated bench harness on-device**: controlled conditions - Rejected; duplicates collection lane A provides, and synthetic inputs can hide real-capture preprocessing costs.
- **Instruments/signpost tracing only**: no code in Release - Rejected; requires a tethered profiling session per data point and leaves nothing in the outcome records.

### Consequences

**Positive:**
- Every capture contributes profile data; the budget derivation is reproducible from exported records.

**Negative:**
- Three always-on clock reads per estimate — negligible, but present in Release.

---

## Decision 12: Bake-off generalises the task-20 spike; the winner trains via an --arch registry

**Date**: 2026-07-17
**Status**: accepted

### Context

Req 5 extends segmenter-foundation's SegFormer spike method to 3–4 candidates, and Req 5.4 requires the top feasible candidate trained and judged in-cycle. `train.py` is currently DeepLab+MobileNetV3-specific.

### Decision

`spike_segformer.py` generalises to `spike_convert.py --candidate <id>` with a per-candidate registry (weights source, 35-channel head graft), keeping the four ordered stop-on-fail criteria and emitting `build/spike_<candidate>.json` with size/latency margins. `train.py` gains an `--arch` registry (default `deeplab_mnv3`; the winner added) reusing the dataset/loss/sidecar/lineage machinery, with `arch` added to the resume drift-check. Judging stays `run_validation.py --split heldout_leakfree` vs 0.3776.

### Rationale

The spike method is already designed, reviewed, and half-implemented — candidates differ only in model source and head surgery, which is exactly what a registry isolates. Extending `train.py` (rather than a parallel script) keeps the co-occurrence loss, resume safety, and lineage stamping identical across architectures, so verdicts compare recipes, not harnesses.

### Alternatives Considered

- **One spike script per candidate**: independent - Rejected; four near-copies of conversion/oracle logic drift apart.
- **Separate `train_candidate.py`**: no risk to the existing trainer - Rejected; a second trainer forks the judging procedure and doubles run-hygiene surface (sidecars, lineage, drift checks).

### Consequences

**Positive:**
- Candidate verdicts and recipe verdicts share one evidence format and one judging path.

**Negative:**
- `train.py` grows an abstraction seam it didn't need for one architecture; mid-run-edit discipline now guards a bigger file.

---

## Decision 13: External co-stats carry source + null split_seed; inverse-frequency weighting removed

**Date**: 2026-07-17
**Status**: accepted

### Context

The `co_stats` contract fail-fasts on `split_seed` and `class_mapping_sha256` — correct for a split-derived matrix, impossible for a corpus-derived one (Req 6.1). Separately, Req 6.3 bans the inverse-frequency weighting Decision 25 attributed as the staple-killer, and the co-occurrence criterion currently hard-wires it.

### Decision

`build_external_co_stats.py` emits the `co_stats` shape with `source: "recipe1m"` and `split_seed: null`; `loss_config.load_co_stats` accepts a null seed only when `source` is external, all other checks (mapping SHA, 35 channels, food-channels-only) unchanged; palette coverage is recorded in the file and in lineage. The ingredient→class mapping is a committed, reviewable JSON. In `train.py`, class weighting becomes `--class-weighting {none, sqrt_inverse}` with default `none`; the inverse-frequency option is removed entirely.

### Rationale

Keeping the v2 shape means one loader, one validation path, and lineage that always records which statistics trained which checkpoint. Removing (not defaulting away) inverse-frequency enforces Decision 25 in code — the attributed failure cause cannot be re-selected by accident; `sqrt_inverse` remains as the deliberately milder re-test Req 6.3 permits.

### Alternatives Considered

- **A new co_stats.v3 schema**: cleaner versioning - Rejected; every consumer would need dual-schema handling for what is two added fields.
- **Keep inverse-frequency behind a flag**: preserves re-test optionality - Rejected; Decision 25's evidence is two failed runs — an accessible foot-gun with no planned use.

### Consequences

**Positive:**
- Matrix provenance is explicit in lineage; a Recipe1M+ run and a FoodSeg103 run are directly comparable.

**Negative:**
- Re-testing true inverse-frequency weighting would need code restoration — deliberate friction.

---

## Decision 14: Design-critic amendments

**Date**: 2026-07-17
**Status**: accepted

### Context

The design-critic review (verified by self-review against source; external validators remain broken) found two critical flaws — volume-stage stats died with the `throw` on exactly the refusal Req 3.1 exists to explain, and the `--arch` registry stopped at `train.py` while `export.py`/`run_validation.py` stayed DeepLab-hard-wired, making a winner unjudgeable and unshippable — plus five majors (weighting removal contradicted the loss-sweep surface; eviction-exemption ambiguity; cancellations recorded as refusals; unspecified transport for segmenter timings and pre-shutter counts; missing Req 1.4 anchor-comparison element; unstated re-plating/immutability rules; mutable reference handed across actors).

### Decision

All folded into the design: estimators become non-throwing (`VolumeOutcome` with volumes + stats + optional refusal; Pipeline stamps, then throws); the arch registry is a shared `archs.py` consumed by train/validate/export with a forward-output normaliser, arch recorded in lineage; `--class-weighting {none, sqrt_inverse}` governs the whole weighted-loss surface with `weighted_ce`+`none` rejected; split eviction bounds (500 non-benchmark, 10 per meal per lineage); cancellation produces no record; `SegmentationResult` gains per-view timings and pre-shutter counts merge at persist time in `CaptureFlowModel`; the report gains an anchor-comparison block with cited constants; benchmark meals are immutable once attempted, with a ±5 g re-plating protocol; the handoff payload becomes an immutable `Sendable` `EstimationAttemptRecord` snapshot on the real `CaptureFlowDelegate`. Minors: two-tier promotion revert rule (>2 g point regression, or CI-confident regression, or completed-count drop ≥ 2), millisecond timestamps with (timestamp, id) tie-break, `benchmark_meal_id` index, `benchmarkClassUnresolvable` validation, `blocked-toolchain` spike verdict distinct from `reject`, ingredient-mapping SHA in lineage, failure `domain` discriminator for capture-stage refusals.

### Rationale

The two criticals each severed a load-bearing requirement at the exact point the design claimed to satisfy it; both are interface changes, which is precisely what design review exists to catch before tasks. The majors all shared one failure shape — data that must survive (stats past a throw, paired attempts past eviction, truth past an edit) not being guaranteed to survive.

### Alternatives Considered

- **Stats payload on `VolumeError`**: smaller signature change - Rejected; error-as-data-carrier bloats every catch site, and non-throwing results keep estimator maths pure and directly testable.
- **Fork a `train_candidate.py` instead of the shared registry**: isolates risk - Rejected (re-affirming Decision 12); the critic's finding strengthens the original rationale — judging and export must share the registry too, or verdicts compare harnesses.

### Consequences

**Positive:**
- The "no volume" record now provably contains its causal measurements on the refusal path.
- A bake-off winner has a complete train → judge → export path before any run starts.

**Negative:**
- Estimator signature changes ripple through existing volume tests (mechanical, covered by `make test`).
- The design now specifies more invariants for tasks to honour — longer task list, same cycle.

---

## Decision 15: Anchor verdict bands at 1.96 SE with an n ≥ 2 gate

**Date**: 2026-07-17
**Status**: accepted

### Context

The report's anchor verdict (Req 1.4) compared our MAE to the published SNAQ figure using a band of ±1 standard error (~68% confidence), and a single completed meal — whose standard error is zero — could produce a hard `betterThanAnchor`/`worseThanAnchor` verdict. Both are inconsistent with the project's promotion standard, which is a one-sided 95% test (Decision 10): the same report could call a result "better than SNAQ" on evidence the promotion gate would call noise.

### Decision

The anchor verdict bands at MAE ± 1.96 standard errors, and a hard `betterThanAnchor`/`worseThanAnchor` verdict additionally requires at least two completed meals; below that the verdict is the within-noise/indeterminate one. The anchor's own sampling noise is consciously ignored — the published 13.1 g figure is treated as a fixed constant.

### Rationale

1.96 SE aligns the anchor comparison with the same 95% evidentiary bar the promotion verdict already uses, so the two headline signals cannot disagree about what counts as confident. The n ≥ 2 gate exists because a single observation has no measurable dispersion: SE = 0 collapses the band to a point and any error would read as a hard verdict. Treating the anchor as a constant is deliberate — its sampling distribution is not published in a usable form, and the benchmark is a developer-phase signal, not a publishable comparison.

### Alternatives Considered

- **Keep the ±1 SE band**: simpler and already implemented - Rejected; a ~68% band is inconsistent with the one-sided 95% promotion standard, so the report could claim confidence the promotion gate would refuse.
- **Full two-sample test against the published anchor**: statistically complete - Rejected as overkill for a developer-phase signal; the anchor's sample-level data is not available, and the added machinery would imply a rigour the single published figure cannot support.

### Consequences

**Positive:**
- One evidentiary standard (95%) across the anchor verdict and the promotion verdict.
- A single lucky (or unlucky) meal can no longer produce a hard verdict.

**Negative:**
- The wider band makes `withinNoiseOfAnchor` the most common verdict at small n — honest, but less satisfying during early data collection.
- Ignoring the anchor's own noise slightly overstates how sharp the comparison boundary is.

---
