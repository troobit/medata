# Design: SNAQ Parity

## Overview

Three lanes: (A) an on-device estimation-outcome store with a diagnostics accumulator threaded through the pipeline, (B) an in-app weighed-meal benchmark that computes SNAQ-comparable reports from those outcome records, (C) the model levers — segmenter tail profiling, a generalised conversion bake-off, and an external co-occurrence matrix — run through the existing `tools/segmenter/` chain. Lanes A/B are Swift (Persistence + Pipeline + App); lane C is Python plus two human-gated device measurements.

## Architecture

### Lane A — outcome recording and diagnostics (Req 2, 3)

**Diagnostics accumulator.** A reference-type `PipelineDiagnostics` is created at the top of `Pipeline.estimate` (`Pipeline.swift:76`) and passed to stage helpers, which append measurements as they run. `estimate`'s body is wrapped in a do/catch that **stamps the outcome into the accumulator** — success (with meal id), the typed failure case, or the underlying description of a non-typed error — and rethrows; a `defer` then builds an **immutable `Sendable` value snapshot** (`EstimationAttemptRecord`, the same `Codable` type the store persists) and hands it to a new callback on the existing `CaptureFlowDelegate` (`CaptureFlowDelegate.swift:7`), `didCompleteAttempt(_:)`. Stamping must happen inside the pipeline, not the App catch ladder — the handoff fires before the App layer ever sees the error — and the snapshot-at-handoff removes the mutable-reference-across-actors hazard (the delegate is `Sendable`; `CaptureFlowModel` conforms via `nonisolated` methods on a `@MainActor` type). **Cancellation is not an outcome**: the do/catch checks `is CancellationError` (mirroring `CaptureFlowModel.swift:661,709`) and discards the accumulator — a user-abandoned capture must not depress benchmark completion rates.

Capture-stage refusals that never reach `estimate` (e.g. tracking lost in `performFlow`'s catch, `CaptureFlowModel.swift:661-673`) get a slim outcome record written directly by `CaptureFlowModel` — outcome `refused`, failure recorded with a `domain` discriminator (`capture` vs `estimation`, since `CaptureError` is not an `EstimationFailure`), no stage measurements — so the log covers every attempt the user experienced, not just those that reached the pipeline.

Accumulated fields (populated by the stage that owns them):

| Stage | Measurements | Source change |
|---|---|---|
| Capture context | capture path (1/2-view), oblique tilt θ, model version | already at hand in `estimate` |
| Scale | resolved source (card/LiDAR), card-fallback flag | promote the DEBUG-only `scale.card_fallback` branch (`Pipeline.swift:116-131`) to always record |
| Support plane | candidates/inliers/residual_mm | `LiDARPlaneFitter.debugLast*` statics become values returned to the caller |
| Segmentation | food-mask coverage %, sub-stage latencies (preprocess / prediction / argmax) **per view** | `SegmentationResult` gains a `timings` field populated inside `CoreMLSegmenter.segment` (`CoreMLSegmenter.swift:72-118`); Pipeline copies it into the accumulator per invocation — the two-view path (`Pipeline.swift:239,333`) records nadir and oblique separately; lane C consumes it |
| Volume | per-class volumes pre-β, post-β, post-threshold; degenerate voxel/ray skip counts | estimators become **non-throwing**: they return a `VolumeOutcome` (volumes + stats + optional refusal). The stats currently die with the `throw` at `VoxelCarveEstimator.swift:206-208` on exactly the refusal Req 3.1 targets — so Pipeline stamps the stats first, then maps the refusal to the `EstimationFailure` throw itself |
| Pre-shutter | segmentation error count | replace the bare `try?` at `PreShutterSegmenter.swift:145,157,201` with count-and-continue; `CaptureFlowModel` (which owns both objects) merges the counter snapshot into the record at persist time — it never crosses `CaptureResult` |
| Outcome | success (σ terms, per-class decomposition by reference to the saved `MealRecord`) or failure case incl. payload; underlying description for non-typed errors | `CaptureFlowModel` catch ladder (`CaptureFlowModel.swift:709-720`) |

**Persistence.** New `estimation_outcomes` table (see Data Models) appended to `createSchema` per the `quick_presets` precedent (`GRDBPersistenceStore.swift:711-754`, `IF NOT EXISTS`, schema_version → 6, no destructive DDL). Records are NOT `events` rows — they are CRUD'd independently and never touch `eventsDidChange`, matching the `quick_presets` convention (`PersistenceStore.swift:141-146`). Bound (Req 2.5), counted separately so both populations stay bounded and neither starves the other: **500 non-benchmark rows** (oldest evicted in the insert transaction — the diagnostic log's guaranteed capacity), and benchmark-tagged rows capped at **10 attempts per meal per model lineage** (oldest for that meal+lineage evicted beyond the cap; total is therefore bounded by meals × lineages × 10, and the latest-completed-attempt semantics are unaffected).

**Write-behind.** `CaptureFlowModel` persists the record in a detached fire-and-forget task; store errors are logged to the `Shutter` category and swallowed (MaskArtefactWriter precedent, `MaskArtefactWriter.swift:75-86`). Recording therefore cannot alter, delay, or block the estimation result (Req 2.4). Successful attempts store the `MealRecord` id **and a compact per-class decomposition snapshot** (class → volume/mass/carbs/β, σ terms — a few hundred bytes) copied into the measurements JSON: Req 3.4 says the record *contains* the decomposition, and a later `deleteMeal` must not hollow it out. The referenced mask artefact (`meals/<id>/mask.png`) is subject to the existing 30-day sweep; a swept artefact leaves the outcome row intact with a dangling reference — accepted.

**Browser + export.** `EstimationLogView` reached from a `NavigationLink` in Settings alongside About (`SettingsView.swift:130`) — **not** inside the `#if DEBUG` section, since Req 2.3 requires Release operation and every build is developer-phase. List UI clones `RecordsView`'s structure (own `NavigationStack`, `.task` reload; no change-stream — reload on appear is enough for a developer log). Export serialises the outcome rows (+ benchmark meals) to JSON and presents the existing `ShareSheet` exactly as archive export does (`SettingsView.swift:170-202`). No raw imagery is duplicated into records or export (Req 2.6).

**Copy fix (Req 3.5).** `EstimationFailure.swift:52-54` `noLidarDevice` message re-worded to the Decision 22 floor.

### Lane B — benchmark (Req 1, 7)

**Ground truth in-app.** `BenchmarkView` (from Settings, sibling of the log browser): create a meal → pick classes from the 35-class palette → enter weighed grams per item → the app derives ground-truth carbs as `grams × carbs_per_100g / 100` via the same `FoodDatabase.entry(for:)` lookups `Macros.compute` uses (`Macros.swift:95-154`) — no volume, no β, so truth isolates the pipeline (Req 1.2). A palette class with no DB entry at the current edition throws `PersistenceError.benchmarkClassUnresolvable` rather than silently contributing 0 g (the `Macros.compute` skip at `Macros.swift:110-113` must not leak into truth). Each meal stores fidelity `weighed` or `package` (package weights are the marked lower-fidelity fallback) and the food-DB edition. **Meals are immutable once they have attempts** — editing items/grams would silently re-score history; corrections create a new meal.

**Attempt vs meal semantics (completion-rate denominator).** A capture launched from a benchmark meal's "Capture" action carries `benchmarkMealID` into `CaptureFlowModel`; every attempt writes an outcome row tagged with it. For a model lineage L: a meal **counts completed** if ≥ 1 attempt under L completed; **completion rate** = completed meals ÷ meals attempted under L; the meal's error uses the **latest completed attempt** under L; attempts-per-meal is reported so retry-spam stays visible (Req 1.5's refusals all remain in the store and the report).

**Report.** `BenchmarkReport.compute(meals:outcomes:lineage:)` — pure function in a new `Benchmark` SwiftPM target (depends on `Persistence`; placement keeps report maths testable under `make test`). Emits: MAE (g), mean absolute percentage error per meal, share of completed meals within ±10 g, completion rate, N, attempts-per-meal, per-meal rows, and the **anchor comparison block** (Req 1.4): the SNAQ shipping-app figures (13.1 g / 44.3%), the reference ±10 g bands (GoCARB 37.0%, dietitians 35.2%), and a computed verdict (better than / within noise of / worse than anchor) — constants live in the Benchmark target with source citations from `docs/agent-notes/snaq-benchmark.md`. Rendered in `BenchmarkView` and included in the JSON export. Headline validity flag: N ≥ 20 and staple coverage per Req 1.6 (staple set as defined by `validation.py`'s staple floors); reports below the floor render with an explicit "not headline-valid" marker.

**Promotion tolerance (Req 7.2).** Same-meal-set paired comparison over meals completed under both lineages, per-meal error deltas, one-sided 95% bootstrap CI (10 000 resamples, seeded SplitMix64 for determinism). Two-tier revert rule with the burden stated explicitly: revert if (a) the point-estimate ΔMAE regresses by more than 2 g regardless of significance (order-of-magnitude bar), or (b) any point-estimate regression whose 95% CI excludes zero (confident regression), or (c) the completed-meal **count** on the shared set drops by ≥ 2 (a 1-meal drop marks the report for a manual call — promotion execution is human-gated anyway). Small noisy regressions can ship; large or statistically confident ones cannot. **Re-run protocol**: the re-cooked plate is re-plated to the stored grams ±5 g per item; if that is impossible, re-weighing creates a *new* meal (deliberately breaking pairing rather than silently changing truth).

**Protocol (Decision 4 resolution).** Weigh each item to ±1 g before plating; one row per palette class; capture immediately after weighing. Starting set: the foods on hand now (lemon, cereal + milk, bread, other basics), growing to ≥ 20 meals that include the staple-floor foods — cheap to cook (white rice, chips, white bread, boiled potato). Known-weak staples are captured and expected to refuse; that is the honest baseline (Req 1.5/1.6).

### Lane C — model levers (Req 4, 5, 6)

**Tail profile (Req 4).** The `CoreMLSegmenter.segment` sub-stage clocks added in lane A run in Release and land in every outcome record, so the profile is read from real 16 Pro captures via the log browser/export — no separate bench harness. ANE residency is confirmed once via the Xcode Core ML performance report (the task-20 method). Budget derivation (Req 4.2): residual model budget = 250 ms − measured non-model share (preprocess + tail + fixed pipeline overhead); recorded in the decision log before any bake-off verdict.

**Bake-off (Req 5).** `spike_segformer.py` generalises to `spike_convert.py --candidate {segformer_b0, efficientvit_b0, efficientvit_b1, seaformer_base, ppmobileseg_base}` with a per-candidate registry (weights source, **conversion toolchain**, 35-channel head graft). Same four ordered stop-on-fail criteria as task 20 (`segmenter-foundation/design.md` §5.1): conversion succeeds → FP16 ≤ 24 MiB (`export.py` `WEIGHTS_MAX_BYTES`) → latency within the Req 4.2-derived budget and ANE-resident on the 16 Pro (human-gated Xcode measurement) → oracle equivalence (`export.oracle_agreement`). Emits `build/spike_<candidate>.json` including size/latency margins (Req 5.3 headroom). PP-MobileSeg is PaddlePaddle-native: a failure caused by toolchain limitation records the distinct verdict `blocked-toolchain`, never `reject` — Req 5.2's evidence must not launder harness limits as model evidence.

**Winner training (Req 5.4).** The architecture registry is a **shared module `tools/segmenter/archs.py`** consumed by all three consumers, because the pipeline is DeepLab-hard-wired in more places than `train.py`: `export.load_checkpoint` rebuilds `deeplabv3_mobilenet_v3_large` (`export.py:124`), and both `run_validation.py:68` and `train.py:601` assume the torchvision `model(images)["out"]` dict output. The registry provides per-arch: model constructor, checkpoint loader, and a forward-output normaliser (plain-tensor architectures wrapped to the `["out"]`-at-input-resolution convention). `train.py --arch` (default `deeplab_mnv3`) reuses the dataset/loss/sidecar/lineage machinery; the resume drift-check and lineage gain the `arch` field; `export.py` and `run_validation.py` resolve the arch from lineage so a trained winner can be judged **and** exported — without this, an adopt verdict (Req 7.1) is unreachable. Judging stays `run_validation.py --split heldout_leakfree` against the 0.3776 anchor — the Decision 21 same-set procedure unchanged. Run hygiene per `docs/ml-training.md` §4 (nohup + caffeinate, never edit `train.py` mid-run).

**External co-occurrence matrix (Req 6.1).** New `tools/segmenter/build_external_co_stats.py`: ingests a Recipe1M+-style ingredient corpus, maps ingredients → palette classes via a **committed** `ingredient_mapping_recipe1m.json` (reviewable, like `class_mapping_foodseg103.json`), and emits `co_stats.json` in the existing `co_stats` shape with two amendments: `source: "recipe1m"` and `split_seed: null`. `loss_config.load_co_stats` accepts a null `split_seed` **only when** `source` is external; `class_mapping_sha256` (which pins *palette identity*, not derivation input — the external build never reads the FoodSeg103 mapping but must stamp the same palette hash), `channel_count` 35, and the food-channels-only rule (Decision 20) still enforced. Palette coverage (classes with/without external statistics) AND the ingredient-mapping file's SHA-256 are written into the file and into lineage.

**Weighting ban (Req 6.3).** Inverse-frequency weighting is removed from the **whole weighted-loss surface**, not just the co-occurrence criterion: `weighted_ce` and `combined` build on the same `inverse_frequency_weights` (`train.py:516-523`, `loss_config.py:128-130,181`). A single `--class-weighting {none, sqrt_inverse}` flag (default `none`) parameterises every weighted loss; `inverse_frequency_weights` is replaced by a scheme-parameterised builder. `--loss weighted_ce --class-weighting none` is an error at launch (it would be `ce` in disguise and corrupt a sweep verdict), keeping Req 6.5's sweep surface meaningful after the removal.

**Opportunistic loss sweep (Req 6.5).** No new machinery: the existing `--loss` choices (`loss_config.LOSS_CHOICES`) are the sweep surface; any sweep run is launched, resumed, and judged identically to every other run in this cycle.

## Data Models

```sql
CREATE TABLE IF NOT EXISTS estimation_outcomes (
  id TEXT PRIMARY KEY,            -- UUID
  timestamp INTEGER NOT NULL,     -- milliseconds (store precedent: last_sweep_at_ms); latest-attempt
                                  -- ties broken by (timestamp, id) so scoring is deterministic
  outcome TEXT NOT NULL,          -- 'success' | 'refused'
  failure TEXT,                   -- JSON {domain: 'estimation'|'capture', case, payload}
  measurements TEXT NOT NULL,     -- JSON EstimationAttemptRecord snapshot (schema-versioned 'v' field)
  meal_id TEXT,                   -- FK-style ref to saved MealRecord (success only)
  model_version TEXT NOT NULL,    -- 12-hex lineage digest
  benchmark_meal_id TEXT          -- set when launched from a benchmark meal
);
CREATE INDEX IF NOT EXISTS outcomes_timestamp ON estimation_outcomes(timestamp);
CREATE INDEX IF NOT EXISTS outcomes_benchmark ON estimation_outcomes(benchmark_meal_id, model_version);

CREATE TABLE IF NOT EXISTS benchmark_meals (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  items TEXT NOT NULL,            -- JSON [{class_id, grams}]
  truth_carbs_g REAL NOT NULL,    -- derived at save from the bundled DB
  db_edition TEXT NOT NULL,
  fidelity TEXT NOT NULL          -- 'weighed' | 'package'
);
```

`schema_version` → `'6'`. Both tables follow the quick_presets convention: own store methods, no `eventsDidChange` interaction. The persisted `measurements` JSON is the `EstimationAttemptRecord` snapshot; a `v` field lets the browser tolerate older rows. Recorded deviation from Req 1.3's literal wording: the estimate and lineage live on outcome rows *referencing* the meal (relational inversion), not on the meal row — same information, queryable direction.

## Components and Interfaces

```swift
// MedataCore/Sources/Pipeline
final class PipelineDiagnostics {                  // reference type: stages append; never crosses actors
    // capture context, per-stage measurements, sub-stage latencies, counters — see lane A table
    func snapshot() -> EstimationAttemptRecord     // immutable Sendable value built at handoff
}
struct EstimationAttemptRecord: Codable, Sendable  // the persisted 'measurements' payload + outcome
struct VolumeOutcome {                             // estimators become non-throwing
    let perClassVolumesCm3: [String: Double]       // pre-β; post-β/threshold applied by Pipeline
    let stats: VolumeStats                         // degenerate voxel/ray skip counts, coverage
    let refusal: VolumeError?                      // Pipeline stamps stats, then throws for non-nil
}
protocol CaptureFlowDelegate {                     // existing (CaptureFlowDelegate.swift:7); gains:
    func didCompleteAttempt(_ record: EstimationAttemptRecord)   // fires on success AND throw (defer)
}

// MedataCore/Sources/Persistence — PersistenceStore gains:
func saveEstimationOutcome(_ o: EstimationOutcome) throws       // in-transaction eviction, split bounds
func estimationOutcomes(limit: Int) throws -> [EstimationOutcome]
func saveBenchmarkMeal(_ m: BenchmarkMeal) throws               // validates grams + class resolvability
func benchmarkMeals() throws -> [BenchmarkMeal]                 // update rejected once attempts exist

// MedataCore/Sources/Benchmark (new target, depends on Persistence)
enum BenchmarkReport {
    static func compute(meals: [BenchmarkMeal], outcomes: [EstimationOutcome], lineage: String) -> Report
    static func promotionVerdict(old: Report, new: Report, seed: UInt64) -> PromotionVerdict  // paired bootstrap
}

// App
EstimationLogView / BenchmarkView                  // Settings NavigationLinks; RecordsView/AboutView patterns
CaptureFlowModel.benchmarkMealID: UUID?            // tags outcome rows for attempts launched from a benchmark meal
```

Behavioural contracts: `didCompleteAttempt` fires exactly once per non-cancelled `estimate` call, after the outcome has been stamped by the pipeline's own do/catch; the payload is an immutable `Sendable` snapshot, so crossing to a detached write task is safe under strict concurrency. `saveEstimationOutcome` is atomic (insert + eviction in one write; split bounds per lane A). `BenchmarkReport.compute` is pure and deterministic; `promotionVerdict` is deterministic given the seed (seedable RNG, e.g. SplitMix64 — the system generator is not seedable).

## Error Handling

- Outcome-store write failures: log to `Shutter`, swallow — never surface to the capture flow (Req 2.4).
- `PersistenceError.benchmarkGramsOutOfRange` for item grams outside `1...5000`, mirroring `intakeCarbsOutOfRange`; `PersistenceError.benchmarkClassUnresolvable` when a palette class has no DB entry at the current edition (a silent 0 g truth would poison MAE); benchmark-meal updates rejected once attempts exist (immutability).
- Cancellation (`CancellationError`, user-abandoned capture) produces no outcome record — checked in the pipeline's stamping do/catch.
- `build_external_co_stats.py` validation failures (unmapped-ingredient rate above threshold, zero-coverage classes) fail the tool, not the training run; `train.py` retains its fail-fast contract at launch (`train.py:741-754`).
- A benchmark capture that refuses is not an error path — it is data (Req 1.5).

## Testing Strategy

Per the MVP gate: MedataCore maths under `make test`, app surfaces by build + on-device; no new app-target test scaffolding.

- **Persistence**: `estimation_outcomes` CRUD + both eviction bounds (500 non-benchmark; 10 per meal per lineage) + `benchmark_meals` truth-carb derivation, unresolvable-class rejection, and post-attempt immutability, as natural extensions of the executed store suite (the `insulinUnitsOutOfRange` precedent).
- **Benchmark maths** (new target's suite): MAE/MAPE/±10 g/completion-rate on hand-built fixtures; bootstrap `promotionVerdict` determinism for a fixed seed; headline-validity flag at the N/staple boundaries. PBT candidate (swift-testing, existing dependency): `compute` invariants — completion rate ∈ [0,1], MAE ≥ 0, removing a refused attempt never lowers completion rate — over generated meal/outcome sets; small generator, executed suite, so it clears the MVP-gate bar.
- **Diagnostics**: `EstimationAttemptRecord` JSON round-trip incl. the `v` field; the non-throwing `VolumeOutcome` conversion (stats survive refusal) covered by extending the existing volume maths tests.
- **Python** (`tools/segmenter/tests`, pytest): `build_external_co_stats.py` mapping/coverage/schema output; `loss_config` acceptance matrix for `split_seed: null` × `source`; `--class-weighting` flag wiring; spike registry smoke (conversion runs stay human-gated).
- **On-device**: capture a benchmark meal end-to-end; force a "no volume" refusal (empty plate) and verify the outcome row carries pre/post-β volumes and skip counters; export JSON via the share sheet.

## Requirements Traceability

| Req | Design element |
|---|---|
| 1.1–1.6 | `benchmark_meals` + `BenchmarkReport.compute`, semantics + protocol (lane B) |
| 2.1–2.6 | `PipelineDiagnostics` + `estimation_outcomes` + write-behind + browser/export (lane A) |
| 3.1–3.5 | Accumulator fields table, estimator stats structs, `internalError` description capture, copy fix |
| 4.1–4.2 | `CoreMLSegmenter` sub-stage clocks + budget derivation |
| 5.1–5.4 | `spike_convert.py` registry + `--arch` winner training |
| 6.1–6.5 | `build_external_co_stats.py` + `loss_config` amendment + `--class-weighting` |
| 7.1–7.2 | `promotionVerdict` paired bootstrap + existing Decision 21 judging |
| 8.1–8.2 | Verdicts land in decision log; export carries the evidence |
