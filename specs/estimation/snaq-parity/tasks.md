---
references:
    - requirements.md
    - design.md
    - decision_log.md
---
# SNAQ Parity

## Diagnostics foundation

- [x] 1. Write failing tests for non-throwing VolumeOutcome estimators <!-- id:isuh2ps -->
  - Extend the existing volume maths suites (MVP gate: executed MedataCore tests only)
  - Assert skip counters and per-class pre-beta volumes survive a noFoodVolumeRecovered refusal — the stats currently die with the throw at VoxelCarveEstimator.swift:206-208
  - Cover the silent drops at VoxelCarveEstimator.swift:200-207,276 and HeightFieldEstimator.swift:126-135
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 2. Convert VoxelCarveEstimator and HeightFieldEstimator to return VolumeOutcome <!-- id:isuh2pt -->
  - Return VolumeOutcome {perClassVolumesCm3 (pre-beta), stats: VolumeStats, refusal: VolumeError?} — no throws
  - Pipeline stamps stats into the accumulator, then maps a non-nil refusal to the EstimationFailure throw itself
  - Existing callers and tests updated mechanically; behaviour under make test unchanged for the success path
  - Blocked-by: isuh2ps (Write failing tests for non-throwing VolumeOutcome estimators)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 3. Write failing tests for EstimationAttemptRecord JSON round-trip <!-- id:isuh2pu -->
  - Codable + Sendable value type; schema-versioned v field so the browser tolerates older rows
  - Failure encoding: {domain: estimation|capture, case, payload} — EstimationFailure has associated values (lidarCoverageTooLow, internalError)
  - Per-view segmentation timings (nadir/oblique), per-class decomposition snapshot fields, no raw imagery (Req 2.6)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.6](requirements.md#2.6), [3.3](requirements.md#3.3)

- [x] 4. Implement EstimationAttemptRecord and PipelineDiagnostics accumulator <!-- id:isuh2pv -->
  - PipelineDiagnostics is a reference type stages append to; snapshot() builds the immutable EstimationAttemptRecord
  - Success snapshot embeds the compact per-class decomposition (class → volume/mass/carbs/beta, sigma terms) so deleteMeal cannot hollow out Req 3.4
  - Blocked-by: isuh2pu (Write failing tests for EstimationAttemptRecord JSON round-trip)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.6](requirements.md#2.6), [3.4](requirements.md#3.4)

- [x] 5. Wire Pipeline outcome stamping, snapshot handoff, and stage measurement collection <!-- id:isuh2pw -->
  - estimate body wrapped in do/catch stamping outcome (incl. underlying description of non-typed errors); CancellationError discarded, no record; defer hands snapshot to CaptureFlowDelegate.didCompleteAttempt (CaptureFlowDelegate.swift:7)
  - SegmentationResult gains timings (preprocess/prediction/argmax) populated in CoreMLSegmenter.segment; Pipeline records per invocation — two-view path calls segment twice (Pipeline.swift:239,333)
  - Card-fallback flag promoted from the DEBUG-only branch (Pipeline.swift:116-131); LiDARPlaneFitter.debugLast* statics become returned values; scale source and tilt recorded
  - PreShutterSegmenter bare try? at :145,157,201 becomes count-and-continue
  - Fix stale noLidarDevice copy to the Decision 22 floor (EstimationFailure.swift:52-54, Req 3.5)
  - Blocked-by: isuh2pt (Convert VoxelCarveEstimator and HeightFieldEstimator to return VolumeOutcome), isuh2pv (Implement EstimationAttemptRecord and PipelineDiagnostics accumulator)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)

## Outcome store

- [x] 6. Write failing store tests for estimation_outcomes <!-- id:isuh2px -->
  - Split eviction bounds: 500 non-benchmark rows; benchmark-tagged rows capped at 10 attempts per meal per lineage
  - Millisecond timestamps (store precedent last_sweep_at_ms); latest-attempt ties broken by (timestamp, id)
  - Indexes: outcomes_timestamp, outcomes_benchmark(benchmark_meal_id, model_version)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.5](requirements.md#2.5)

- [x] 7. Implement estimation_outcomes table and store methods <!-- id:isuh2py -->
  - Append CREATE TABLE IF NOT EXISTS per the quick_presets precedent (GRDBPersistenceStore.swift:711-754), schema_version → 6, no destructive DDL
  - saveEstimationOutcome: atomic insert + eviction in one write; no eventsDidChange interaction (PersistenceStore.swift:141-146 convention)
  - Blocked-by: isuh2px (Write failing store tests for estimation_outcomes)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5)

- [x] 8. Wire CaptureFlowModel write-behind persistence <!-- id:isuh2pz -->
  - Detached fire-and-forget task on didCompleteAttempt; store errors logged to Shutter and swallowed (MaskArtefactWriter.swift:75-86 precedent)
  - Slim records for capture-stage refusals from performFlow catch (CaptureFlowModel.swift:661-673): outcome refused, domain capture, no stage measurements
  - Merge the pre-shutter error counter snapshot at persist time; tag rows with CaptureFlowModel.benchmarkMealID when set
  - PreShutterSegmenter's segmentationErrorCount is lifetime-cumulative with no reset: the persist-time merge MUST record a per-attempt delta (snapshot a baseline at attempt start) or the field is wrong from its first persisted row
  - Blocked-by: isuh2pw (Wire Pipeline outcome stamping, snapshot handoff, and stage measurement collection), isuh2py (Implement estimation_outcomes table and store methods)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2)

## Benchmark

- [x] 9. Write failing store tests for benchmark_meals <!-- id:isuh2q0 -->
  - Truth = grams × carbs_per_100g / 100 via the same FoodDatabase.entry(for:) lookups Macros.compute uses — no volume, no beta (Req 1.2)
  - PersistenceError.benchmarkGramsOutOfRange (1...5000) and benchmarkClassUnresolvable (no silent 0 g truth — Macros.swift:110-113 skip must not leak)
  - Updates rejected once attempts exist (immutability); db_edition and fidelity (weighed|package) persisted
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)

- [x] 10. Implement benchmark_meals table and store methods <!-- id:isuh2q1 -->
  - Items JSON [{class_id, grams}]; truth derived at save; references design Data Models DDL
  - Blocked-by: isuh2py (Implement estimation_outcomes table and store methods), isuh2q0 (Write failing store tests for benchmark_meals)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)

- [x] 11. Write failing BenchmarkReport tests including property-based invariants <!-- id:isuh2q2 -->
  - Report fields: MAE g, per-meal MAPE, ±10 g share of completed meals, completion rate, N, attempts-per-meal, anchor block (SNAQ 13.1 g / 44.3%, GoCARB 37.0%, dietitians 35.2%) with verdict
  - Headline-validity boundaries: N 19 vs 20; staple-floor coverage per validation.py staple set; refused attempts counted, never excluded (Req 1.5)
  - Latest-completed-attempt selection with (timestamp, id) tie-break
  - PBT via swift-testing (executed suite): completion rate in [0,1]; MAE ≥ 0; adding a refused attempt never raises completion rate
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6)

- [x] 12. Implement Benchmark target and BenchmarkReport.compute <!-- id:isuh2q3 -->
  - New Benchmark SwiftPM target depending on Persistence; compute is pure and deterministic
  - Anchor constants with source citations from docs/agent-notes/snaq-benchmark.md
  - Blocked-by: isuh2q1 (Implement benchmark_meals table and store methods), isuh2q2 (Write failing BenchmarkReport tests including property-based invariants)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6)

- [x] 13. Write failing promotionVerdict tests <!-- id:isuh2q4 -->
  - Seeded SplitMix64 determinism (system RNG is not seedable)
  - Two-tier boundaries: point regression > 2 g reverts regardless of significance; any CI-confident regression reverts; completed-count drop ≥ 2 reverts; drop of exactly 1 marks manual-call
  - Stream: 1
  - Requirements: [7.2](requirements.md#7.2)

- [x] 14. Implement promotionVerdict paired bootstrap <!-- id:isuh2q5 -->
  - Paired per-meal deltas over meals completed under both lineages; 10 000 resamples, one-sided 95% CI
  - Blocked-by: isuh2q3 (Implement Benchmark target and BenchmarkReport.compute), isuh2q4 (Write failing promotionVerdict tests)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)

## App surfaces

- [x] 15. Build EstimationLogView with JSON export <!-- id:isuh2q6 -->
  - Settings NavigationLink beside About (SettingsView.swift:130) — NOT inside #if DEBUG (Req 2.3 requires Release operation)
  - RecordsView list pattern, reload on appear, no change-stream subscription
  - JSON export of outcome rows + benchmark meals via the existing ShareSheet seam (SettingsView.swift:170-202); export contains record contents only (Req 2.6)
  - Verified by build + on-device per the MVP gate — no app-target tests
  - Blocked-by: isuh2pz (Wire CaptureFlowModel write-behind persistence)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3)

- [x] 16. Build BenchmarkView with capture launch and report rendering <!-- id:isuh2q7 -->
  - Meal creation: palette class picker, grams keypad, fidelity toggle; edit-after-attempts creates a new meal (immutability)
  - Capture launch sets CaptureFlowModel.benchmarkMealID before presenting the capture route
  - Report rendering includes the anchor block and the not-headline-valid marker
  - Verified by build + on-device per the MVP gate
  - Blocked-by: isuh2q1 (Implement benchmark_meals table and store methods), isuh2q3 (Implement Benchmark target and BenchmarkReport.compute), isuh2q6 (Build EstimationLogView with JSON export)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6)

## Python levers

- [x] 17. Write failing pytest for the archs.py architecture registry <!-- id:isuh2q8 -->
  - Contract per arch: model constructor, checkpoint loader, forward-output normaliser to the [out]-at-input-resolution convention
  - deeplab_mnv3 parity: registry output equals current deeplabv3_mobilenet_v3_large path (export.py:124, train.py:208-213)
  - Plain-tensor architectures (SegFormer-class) wrapped and upsampled; fixture-level, no torch-optional paths broken
  - Stream: 2
  - Requirements: [5.4](requirements.md#5.4), [6.4](requirements.md#6.4)

- [x] 18. Implement archs.py and refactor train, export, and validation to consume it <!-- id:isuh2q9 -->
  - tools/segmenter/archs.py consumed by train.py (--arch flag, default deeplab_mnv3), export.load_checkpoint, and run_validation.py (arch resolved from lineage)
  - Sidecar resume drift-check and lineage gain the arch field
  - NEVER edit train.py while a run is live (docs/ml-training.md §4; train.py:42-44)
  - Blocked-by: isuh2q8 (Write failing pytest for the archs.py architecture registry)
  - Stream: 2
  - Requirements: [5.4](requirements.md#5.4), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4)

- [x] 19. Write failing pytest for class-weighting schemes <!-- id:isuh2qa -->
  - Scheme builder none|sqrt_inverse replaces inverse_frequency_weights (train.py:516-523, loss_config.py:128-130,181) — inverse-frequency removed entirely (Decision 25 enforced in code)
  - --loss weighted_ce --class-weighting none is a launch error (ce in disguise corrupts sweep verdicts)
  - combined and co_occurrence wiring covered, not just the co-term criterion
  - Stream: 2
  - Requirements: [6.3](requirements.md#6.3)

- [x] 20. Implement --class-weighting across the weighted-loss surface <!-- id:isuh2qb -->
  - Default none; applies to every weighted loss in loss_config.LOSS_CHOICES
  - Blocked-by: isuh2qa (Write failing pytest for class-weighting schemes)
  - Stream: 2
  - Requirements: [6.3](requirements.md#6.3), [6.5](requirements.md#6.5)

- [x] 21. Write failing pytest for the external co-occurrence stats builder <!-- id:isuh2qc -->
  - Output: co_stats.v2 shape + source field, split_seed null, palette coverage list, ingredient-mapping SHA-256
  - loss_config acceptance matrix: null split_seed only when source is external; class_mapping_sha256 (palette identity), channel_count 35, food-channels-only (Decision 20) still enforced
  - Fixture corpus committed under tools/segmenter/tests
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1)

- [x] 22. Implement build_external_co_stats.py and the loss_config acceptance amendment <!-- id:isuh2qd -->
  - Committed ingredient_mapping_recipe1m_v1.json (reviewable, like class_mapping_foodseg103_v1.json)
  - Tool fails on unmapped-ingredient rate above threshold or zero-coverage classes; train.py fail-fast contract at launch unchanged (train.py:741-754)
  - Lineage records source and mapping SHA
  - Blocked-by: isuh2qc (Write failing pytest for the external co-occurrence stats builder)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1)

- [x] 23. Write failing pytest for the spike_convert candidate registry <!-- id:isuh2qe -->
  - Candidate table: segformer_b0, efficientvit_b0/b1, seaformer_base, ppmobileseg_base with weights source, conversion toolchain, head graft
  - blocked-toolchain verdict distinct from reject (PP-MobileSeg is PaddlePaddle-native; harness limits must not masquerade as model evidence, Req 5.2)
  - build/spike_<candidate>.json output shape incl. size/latency margins (Req 5.3)
  - Stream: 2
  - Requirements: [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)

- [x] 24. Implement spike_convert.py generalising the SegFormer spike <!-- id:isuh2qf -->
  - Four ordered stop-on-fail criteria per segmenter-foundation design §5.1; reuses export.oracle_agreement and reference_input
  - Latency criterion emitted as pending — the 16 Pro measurement is human-gated (prerequisites.md)
  - Conversion runs need the torch/transformers venv — code testable without them via registry fixtures
  - Blocked-by: isuh2qe (Write failing pytest for the spike_convert candidate registry)
  - Stream: 2
  - Requirements: [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)
