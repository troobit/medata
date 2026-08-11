# Model Production (segmenter + β_c) — code paths

Spec: `specs/estimation/model-production/`. Most of the spec is process, not code;
the code deltas are loader alignment, lineage/versioning, export gates, validation
reporting, uncalibrated honesty, and the β_c bake lock. Stages 0/3/7/9 and the
*execution* of stage 10 are human/data-gated (see `prerequisites.md`).

## Where the code lives

- **Loader (tasks 1–2, 5)** — `MedataCore/Sources/Pipeline/PipelineFactory.swift`.
  Resolves `segmenter.mlpackage` via `Bundle.module` (not `Bundle.main`) with
  `subdirectory: "Resources"`. The `Pipeline` target declares
  `resources: [.copy("Resources")]` in `Package.swift` — a **directory** copy, not
  a named-file copy (Decision 7), so clean Debug + Release builds stay green before
  any model exists. The real `.mlpackage` is gitignored and drops into
  `MedataCore/Sources/Pipeline/Resources/` from `export.py`. Absent model →
  `PipelineFactoryError.segmenterModelMissing`.
- **modelVersion (tasks 3, 5, 7)** — `CoreMLInferenceEngine.modelVersion`
  (`CoreMLSegmenter.swift`) reads `userDefinedMetadata["medata.modelVersion"]` off
  the loaded `MLModel` (falls back to a constant for keyless fixtures). The key
  string is the contract shared with `export.py`'s `MODEL_VERSION_METADATA_KEY`.
  `Pipeline.segmenterSourceTag(for:)` interpolates `coreml_<sha12>` into
  `MealRecord.segmenterSource`. The 12-hex is the first 12 of the checkpoint
  SHA-256 (the join key in `build/lineage.json`).
- **Lineage (task 3)** — `tools/segmenter/lineage.py` (pure stdlib, no torch).
  `train.py`/`export.py` emit `build/lineage.json`; `metrics` is null-placeholder
  until validation fills it.
- **Export gates (tasks 6–7)** — `tools/segmenter/export.py`. Pure predicates
  (`validate_weight_budget`, `validate_channel_count`, `oracle_agreement`,
  `preprocess_reference`) are unit-tested torch-free. First-real-export
  recalibrations (2026-07-05): weight budget is 24 MiB (Decision 13 — the
  Decision 25 architecture is 11.03 M params = 22.1 MB FP16, so the original
  10 MB was never achievable; `SegmenterWeightsBudget.maxBytes` matches) and
  the oracle abs-logit bar is 0.5 (Decision 14 — measured healthy FP16 drift is
  0.13–0.30 with argmax agreement ≥ 0.9985; argmax > 0.99 is the functional
  gate). The oracle is the **PyTorch checkpoint** (not Core ML
  vs TFLite); inputs flow through `preprocess_reference`, which mirrors the
  **runtime letterbox** path (Decision 9). Known limitation: the oracle feeds the
  same preprocessed input to both sides, so it catches checkpoint↔artefact drift
  only. The previously flagged train↔runtime square-resize skew is **closed**
  (2026-07-06): `train.py` now letterboxes via `_letterbox_pair`, matching the
  runtime path — see the second real model below.
- **Validation reporting (tasks 8–9)** — `tools/segmenter/validation.py` (pure,
  torch-free). Takes a `per_class_iou` mapping, computes food-class mean IoU
  (special channels excluded), the carb-priority subset, and the **export
  eligibility** decision: `mean ≥ 0.48 AND every carb-priority staple ≥ 0.45`
  (re-derived bars, segmenter-foundation Decisions 5/14; were 0.60/0.50 —
  `HarnessCore/SegBench.swift` `passesBar` enforces the same 0.48 gate).
  `shortfall()` lists what failed (incl. an absent staple — it cannot prove the
  floor, Req 3.6). `record_metrics_into_lineage()` / `update_lineage_file()` write
  the `{mean_iou, per_class_iou, carb_priority_iou, export_eligible, shortfall}`
  block into `build/lineage.json`. Carb-priority staples: white_rice, brown_rice,
  pasta, bread_white, bread_wholemeal, potato_boiled, potato_mashed, chips_fries.
- **Held-out validation runner** — `tools/segmenter/run_validation.py` (torch).
  Runs a checkpoint over a remapped split (default `heldout`), computes per-class
  IoU by palette name, records metrics into lineage. Exit 1 on strict-gate fail.
  It imports siblings via sys.path (`_load_sibling`), NOT
  `spec_from_file_location` — spawn DataLoader workers re-import
  `FoodSegDataset.__module__` by name, and a synthetic module name breaks the
  unpickle (same family as the modules-on-instance gotcha below).
- **First real model (2026-07-05)** — recipe-v2 checkpoint `0295ea61edd9`:
  heldout mean food-class IoU 0.4259; staples white_rice 0.60 / chips_fries 0.55
  / pasta 0.55 pass, bread_white 0.45 / potato_boiled 0.47 short, brown_rice /
  bread_wholemeal / potato_mashed absent from heldout. Below-gate release
  override recorded in lineage; exported and bundled. `make deploy-release`
  (new; `tools/deploy_release.sh`) deploys plain Release with the real model.
  Superseded by `24e0b022241a` below.
- **Second real model (2026-07-06)** — letterbox-recipe checkpoint
  `24e0b022241a` (`build/checkpoint_letterbox.pt`, trained at code commit
  0e5f46a: 60 epochs, lr 1e-3 poly-0.9 per-epoch, target 513, augment = hflip
  + random scale-up crop + the new independent vertical flip). The recipe
  change vs `0295ea61edd9` is **letterbox training preprocessing**
  (`_letterbox_pair` in `train.py`), closing the train↔runtime square-resize
  skew flagged in the export-gates bullet above. Final-epoch train-val
  food-class mIoU 0.4005; heldout (`run_validation.py`, stage 9) mean
  food-class IoU 0.4054 — staples white_rice 0.6022 / chips_fries 0.5671 /
  pasta 0.5538 pass, bread_white 0.4315 / potato_boiled 0.4648 short,
  brown_rice / bread_wholemeal / potato_mashed absent from heldout.
  **Caveat (2026-07-15, segmenter-foundation Decision 21):** that 0.4054 was
  measured on the old seed-1234 split; the split has since been re-cut at
  frozen seed 20260715, and re-measuring this checkpoint on the new heldout is
  TRAIN-CONTAMINATED (it scores 0.7403 there — memorisation, not
  generalisation). The honest anchor for this model is the leak-free
  182-image table, mean food-class IoU **0.3776**.
  `export_eligible=false`; Decision 11 developer-phase override recorded in
  `build/lineage.json` (deployed for on-device efficacy testing while the
  model improves). The heldout mean is slightly *below* the previous model's
  0.4259, but the letterbox parity fix is expected to improve real-device
  behaviour, which the offline bench cannot see. Bundled
  `segmenter.mlpackage` carries `medata.modelVersion=24e0b022241a`; deployed
  via `make deploy-release`, build stamp `0e5f46a-20260706-120508` — expect
  `segmenterSource=coreml_24e0b022241a` in the launch log (launch verification
  pending; device was locked at deploy time). `HarnessCLI seg-bench`
  (ml-training.md §5) was intentionally skipped: `run_validation.py` records
  the same food-class-mIoU gate quantity into lineage, and the full held-out
  fixture bundle would be ~16 GB for no new information — same
  developer-phase precedent as the first model.
- **Developer-phase release override (Decision 11)** — the strict gate advises,
  not blocks, during the developer phase. `run_validation.py --allow-below-gate
  --reason "..."` records an attributable `metrics.release_override` block and
  exits 0; `validation.record_release_override()` / `release_allowed()` are the
  pure primitives. `export_eligible` stays truthful; re-running validation drops
  a stale override. Returns to hard-blocking before any non-developer release.
- **Training recipe (Decision 12)** — train split gets hflip + random scale-up
  crop (`--no-augment` to disable; augmentation is resume-drift-gated) and the lr
  follows per-epoch poly-0.9 decay (`train.LR_SCHEDULE`), recorded in checkpoint +
  lineage `train_config`. The fixed-lr, no-aug baseline plateaued at ~0.34 val
  food-class mIoU by epoch 22/60 while train loss kept falling.
- **Opt-in loss + photometric augmentation (estimation-quality PRD)** —
  `train.py --loss {ce,weighted_ce,focal,dice,combined}` selects the training
  loss; `--photometric-augment` adds train-only brightness/contrast/colour
  jitter (image only, applied BEFORE the letterbox so padding stays exact
  black). Omitting both reproduces the historical recipe byte-for-byte in the
  recorded checkpoint/`train_config` — the default `ce` and off-by-default
  photometric record NO new keys, so absence means the historical unweighted
  CE. The pure parts (loss-name validation, spec dispatch, inverse-frequency
  class weights with zero-count auto-pin + `MAX_CLASS_WEIGHT` clamp) live in
  `tools/segmenter/loss_config.py`, torch-free-tested by
  `tests/test_loss_config.py`; the torch side is `train._build_criterion` +
  `train._train_pixel_counts` (one PIL/numpy pass over the train masks, only
  when the loss uses weights). The resume sidecar records/validates
  `loss`/`photometric_augment` as drift (old sidecars without the keys read as
  the defaults). Recommended next run: docs/ml-training.md §4.
- **`emit_lineage` preserves recorded metrics** — re-exporting the SAME checkpoint
  no longer wipes a validation result or release override out of `lineage.json`
  (`lineage.preserve_metrics`, SHA-matched).
- **Uncalibrated honesty (task 10)** — `App/ResultView.swift`. At the MVP gate
  every class is `uncalibrated_unity` (β = 1.0), so the carb number is **real but
  over-estimating**. `ResultFormat.showsUncalibratedBanner(perClassCalibration:)`
  is true when any contributing class is not `calibrated` (or the dict is empty).
  The banner (orange `confidenceModerate` rounded card, up-arrow glyph) is
  **suppressed for `dev_stub`** meals — the yellow placeholder capsule owns the
  *fake-number* case; this marks a *real-but-uncalibrated* number. No schema
  change (`perClassCalibration` is already persisted in `Pipeline.swift`).
- **Resumable training** (`specs/estimation/resumable-segmenter-training/`) —
  `train.py` writes a resume sidecar `<--out>.resume.pt` atomically
  (temp + `os.replace`) after every completed epoch: model + optimizer state
  (CPU tensors), epoch counter, and the run's hyperparameters. `--resume PATH`
  validates `num_classes`/`palette_version`/`target_size`/`lr`/`batch_size`
  against the sidecar *before* building the model and **rejects drift**
  (Decision 3 — no reconciliation; start a fresh run). Without `--resume`, an
  existing default sidecar refuses to start. On resume the model is built with
  `weights=None`; `pretrained` provenance carries the sidecar's original value
  and lineage gains `train_config.resumed_from_epoch`. The sidecar is deleted
  after the final checkpoint save. Shipped checkpoint dict shape unchanged.
  Tests: `tools/segmenter/tests/test_train_resume.py` (skips without torch;
  the rest of the suite stays torch-free).
- **β_c bake lock (tasks 11–12)** — `tools/food_db/generate.py`. The bake now runs
  under an `__main__` guard via `bake()`, so importing the module is
  side-effect-free (testable without rebaking). `verify_palette_lock(PALETTE_VERSION)`
  reads `ClassPalette.version` from `ClassPalette.swift` (regex on the standard
  literal) and aborts the bake on mismatch (Req 8.4). This only ADDS the lock; the
  baked value stays `'v1'` and `ClassPalette.version` is untouched.
- **Segmenter-foundation phase 2 (2026-07-11)** — `prepare_dataset.py` now carves
  a STRATIFIED heldout split by default (design §3.5; `--no-stratify` restores the
  plain shuffle): staple presence is computed from RAW masks via the LUT in
  `compute_staple_presence` before `write_split` remaps, quota =
  `min(max(3, ceil(heldout_frac·n)), n//3)`, `carve_splits` returns
  `(splits, stratification_block_or_None)`. The remap pass also writes
  `out/co_stats.json` (per-split pixel counts + train-only presence/joint-presence,
  stamped with split seed + class-mapping SHA-256). `--loss co_occurrence`
  (`loss_config.py` + `train._build_criterion`) = weighted_ce + λ·presence-BCE with
  co-occurrence pair weights; it FAILS FAST if `<data>/co_stats.json` is missing or
  its seed/mapping-SHA mismatch the invocation (`--split-seed` becomes mandatory).
  Lineage gained `pretrained_checkpoint` `{source_url, licence, sha256}` (via
  `--pretrained-source-url/-licence/-sha256`) and `co_stats_sha256`;
  `preserve_metrics` now carries both across re-exports. `spike_segformer.py`
  (SegFormer-B0 Core ML spike, criteria 1/2/4 — measured on the iPhone 16 Pro,
  the hardware floor since Decision 22) needs the heavy deps (`transformers`
  is in requirements.txt as spike-only). `adapter_probe.py` (timm in21k-MIL →
  torchvision state-dict round-trip) was RUN and FAILED — Decision 19; the
  timm graphs diverge numerically despite matching shapes.
- **Segmenter-foundation training cycle (2026-07-15/16, Decisions 21–24)** —
  the stratified re-cut is frozen at seed **20260715**; `--split-seed 20260715`
  is mandatory for every run against `data/foodseg103_remapped`. The pinned
  model's uplift anchor is the **leak-free 182-image table, mean 0.3776**
  (Decision 21; the full-heldout re-measure of the pinned model is
  train-contaminated — see the caveat on the second-real-model bullet). The
  leak-free diagnostic split is materialised at
  `data/foodseg103_remapped/heldout_leakfree/` (gitignored symlinks). Task-18
  outcomes: torchvision `IMAGENET1K_V2` init was empirically REJECTED at epoch
  20 (val mIoU 0.2391 vs 0.3610 at the same point; Decision 23) and the run
  relaunched on `DEFAULT` (COCO-seg) weights; that co-occurrence-recipe run
  then completed and was REJECTED at task 19 (Decision 24: same-set leak-free
  0.3253 vs the pinned model's 0.3776, four of five measurable staples
  regressing beyond the 0.02 tolerance, although dead tail classes genuinely
  recovered — milk/tea/soup/fish_white/apple up from ~0). `checkpoint_recipe.pt`
  was NOT exported; **the bundled model remains `24e0b022241a`**. A
  combined-loss fallback run (weighted CE + dice, same seed/augment/init —
  isolates weighting vs the co-occurrence term) is in flight:
  `tools/segmenter/build/checkpoint_combined.pt`, log
  `train_combined_20260716.log`, resumed from epoch 30 after a reboot.

## Gotchas

- **Core ML output `MLMultiArray`s are strided, not dense.** The 513-wide
  segmenter output comes back with a 544-element row stride (measured on both
  `.cpuOnly` and `.all`); any Swift code reading the raw buffer must index via
  `MLMultiArray.strides`. A dense linear read shears every logit plane — on
  device this flooded field captures with 87–99 % `unsupported_liquid` and
  near-zero background while the same photo replayed sanely through PyTorch
  and coremltools on the Mac (both honour strides, so the export-time
  equivalence oracle can never catch this class of bug). Fixed in
  `CoreMLInferenceEngine.unpackLogits` 2026-07-23
  (`specs/bugfixes/segmenter-output-stride-ignored/`); regression tests build
  row-padded arrays via `MLMultiArray(dataPointer:shape:dataType:strides:)`.
  Diagnosis recipe: pull a capture bundle from `Documents/captures/`,
  histogram/rendering of `nadir_argmax` (diagonal streaks = stride bug), then
  Mac replay through `tools/segmenter/build/checkpoint_*.pt` to isolate
  device-runtime vs model.
- **NEVER edit `train.py` (or anything it imports) while a training run is
  live.** DataLoader workers are respawned each epoch via `spawn` and re-import
  the script from disk, so new code runs against the old pickled dataset object
  — an attribute added in an edit crashed a live run at epoch 22 with
  `AttributeError` in worker process. Land code changes between runs.
- **Never store imported modules on `FoodSegDataset` (or anything a DataLoader
  pickles).** macOS starts DataLoader workers via `spawn`, which pickles the
  dataset; module objects are unpicklable → `TypeError: cannot pickle 'module'
  object` with `--num-workers > 0` (the default is 4, so single-process smoke
  tests don't catch it). `__init__` calls `_import_torch()`/`_import_pillow()`
  as availability checks only; `__getitem__` re-imports locally.
- **torchvision refuses `aux_loss=False` alongside pretrained weights** (any
  version `requirements.txt` allows, ≥ 0.13). `export.load_checkpoint` (and via
  it `train.py --no-pretrained`-less runs) crashed until fixed by building with
  `aux_loss=True` and then setting `model.aux_classifier = None` — architecture
  and state_dict key set stay identical to an `aux_loss=False` build. The bug
  was latent because nothing exercised `load_checkpoint` with torch installed
  before `test_train_resume.py`.
- **`swift test` does not cover `App/`.** The SPM package targets are CaptureKit,
  Pipeline, Foods, etc.; `App/` (the iOS app, built from `MeData.xcodeproj`, which
  is not in the repo/worktree) is not a package target. ResultView changes are
  verified by build + on-device only (gated). Keep App-side predicates trivially
  correct and reuse existing API/`Color.*` tokens.
- **`ColourTokenUsageTests`** forbids inline `Color(red:…)` in view bodies — always
  use a named token from `App/Colors.swift`. `tools/check_spelling.sh` enforces
  correct spelling but, run over a whole file, naively flags SwiftUI API
  (`colors:`, `.center`, the `Color` type); the real gate scopes tighter. New copy
  must avoid US spellings regardless.
- **Running `generate.py` rebakes `cofid_db.sqlite`/`afcd_db.sqlite` and the SQLite
  bytes differ even with identical data** (page/freelist layout). The DBs are
  *tracked*. If you run the script for a manual check, `git checkout --` the two
  files afterwards unless you intend to commit a rebake. The food-DB density data
  is owned separately — don't bundle a rebake into unrelated work.
- **`rune complete` takes the numeric task id**, e.g.
  `rune complete specs/.../tasks.md 9` (not the `<!-- id:... -->` comment id).
- **Import sibling tool modules by NAME (sys.path), not `spec_from_file_location`,
  when identity matters.** `spec_from_file_location` creates a distinct module
  object, so `except export.ExportGateError` (or any isinstance check) fails
  against the conftest-imported `export`. `spike_segformer._load_export_module`
  hit this; the `train.py` loss_config sys.path pattern is the fix. (`train.py`'s
  old spec-loaded `_load_export_module` is gone — model construction now goes
  through `archs.py`, imported by name.)

## snaq-parity stream 2 (2026-07-17): archs registry, class weighting, external co-stats, spike_convert

- **`archs.py` is the single architecture seam** (snaq-parity Decisions 12/14).
  `ArchSpec` = build / load_checkpoint / forward_logits (normalises to the
  `["out"]`-at-input-resolution convention; `plain_tensor_logits` upsamples
  SegFormer-class stride-4 outputs). Consumers: `train.py --arch` (default
  `deeplab_mnv3`; arch in the sidecar drift-check; recorded in checkpoint +
  lineage `train_config` ONLY when non-default — absence means deeplab),
  `export.load_checkpoint(…, arch=None)` (resolves from the checkpoint's own
  `arch` key), `run_validation.py` (resolves via `archs.arch_from_lineage`).
  Torch-free at import; `register()`/`unregister()` exist for fixtures and the
  future bake-off winner. `--init-checkpoint` is deeplab-only (backbone surgery).
- **Inverse-frequency weighting is deleted, not deprecated** (Req 6.3 /
  Decision 13, enforcing segmenter-foundation Decision 25).
  `loss_config.class_weights(scheme, …)` builds `none` (returns None) or
  `sqrt_inverse` (square root of the inverse-frequency ratio, same pin/
  normalise/clamp rules). `--loss weighted_ce --class-weighting none` is a
  launch error (ce in disguise); combined/co_occurrence run their CE base
  unweighted under `none`. The scheme lands in the loss spec (`weighting` key)
  and the resume drift-check.
- **`build_external_co_stats.py`** (Req 6.1) maps a Recipe1M-style corpus onto
  the palette via the committed `ingredient_mapping_recipe1m.json`
  (longest word-boundary term wins) and emits co_stats with
  `source: recipe1m`, `split_seed: null`, the ingredient-mapping SHA, coverage
  lists, and `pixel_counts`/`train_images` null. Fails (SystemExit, no file
  written) on unmapped rate > `--max-unmapped-rate` or any zero-coverage food
  class. `loss_config.load_co_stats` accepts a null seed ONLY for a recognised
  external source; `train.py --co-stats` points at the file; lineage gains
  `co_stats_provenance` (carried across re-export by `preserve_metrics`).
- **`spike_convert.py --candidate {segformer_b0, efficientvit_b0/b1,
  seaformer_base, ppmobileseg_base}`** generalises the SegFormer spike.
  Verdicts: `reject` (a measured criterion failed — model evidence),
  `blocked-toolchain` (ppmobileseg_base: PaddlePaddle-native; short-circuits
  BEFORE any heavy import — harness limit, never reject), `pending` (all
  measured criteria pass; criterion 3 is the string `"pending"` — the 16 Pro
  latency half is human-gated and judged against the Req 4.2-derived budget).
  `build/spike_<candidate>.json` records size/latency margins (Req 5.3).
  The efficientvit/seaformer loaders need their zoos installed; a missing
  package aborts with NO verdict (environment gap, not evidence). The generic
  `_graft_last_conv_head` (last Conv2d → 35-channel 1x1) is a heuristic —
  verify per candidate in the gated conversion session.
- `spike_segformer.py` is unchanged (historical task-20 evidence); its stale
  test expectation was updated to the Decision 22 iPhone 16 Pro floor.

## myfoodrepo-bridge (2026-07-26): 36-channel model `ab812dc3aa9d` promoted

- Third real model shipped: `checkpoint_merged_v2.pt` -> `ab812dc3aa9d`,
  trained 12 epochs on the merged FoodSeg103 + Food Recognition 2022 corpus
  (45,515 train images, 36-channel palette), plain CE / class weighting
  `none` / geometric augment only — the incumbent recipe, so the delta is
  attributable to data alone. Verdict: segmenter-foundation Decision 27.
- Leak-free anchor: mean food-class IoU 0.3927 vs the 0.3776 incumbent
  (family-collapsed 0.4212). New classes on merged val: cereal 0.4831,
  bread_wholemeal 0.4787, potato_mashed 0.3719; brown_rice unlearned (0.0000,
  131 train images) and stays deferred.
- Anchor per-staple readings carry ±0.10 cross-set noise (the same checkpoint
  scores chips_fries 0.5599 on the 182-image anchor vs 0.4586 on the 854-image
  heldout) — treat single-set per-class deltas accordingly.
- `PipelineFactory` defaults moved to the 36-channel palette (both
  `makeForDevice` and `makeSegmenter`); `ClassColourTable` needed no change
  (id-indexed golden-angle wheel, palette-size-independent).
- Export gates: 22,169,442 B weights (≤ 24 MiB), 36 channels, Core ML vs
  oracle argmax agreement 0.9999; developer-phase release override recorded in
  `build/lineage.json` (strict 0.48/0.45 gates still unmet; `export_eligible`
  truthful).
- GOTCHA (recurring): `run_validation.py`/`export.py` defaults are
  REPO-RELATIVE (`tools/segmenter/build/...`). Run them from the repo root or
  pass absolute `--lineage`/`--out-*`, or metrics land in a stray
  `tools/segmenter/tools/segmenter/` tree (happened 2026-07-26; stray removed,
  validation re-run with absolute paths).
- Validation of a v2 model needs v2-space masks: the 182-anchor images were
  re-paired with v2 masks at `data/foodseg103_remapped_v2/heldout_leakfree/`
  (same stems; the v1 anchor dir stays byte-identical as the provenance
  artefact).
