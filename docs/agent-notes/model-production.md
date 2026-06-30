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
  `preprocess_reference`) are unit-tested torch-free; the full oracle run is gated
  on a real `checkpoint.pt`. The oracle is the **PyTorch checkpoint** (not Core ML
  vs TFLite); inputs flow through `preprocess_reference`, which mirrors the
  **runtime letterbox** path (Decision 9). Known limitation: the oracle feeds the
  same preprocessed input to both sides, so it catches checkpoint↔artefact drift,
  **not** the train↔runtime square-resize skew (`train.py`/`reference_input` still
  square-resize — flagged follow-up).
- **Validation reporting (tasks 8–9)** — `tools/segmenter/validation.py` (pure,
  torch-free). Takes a `per_class_iou` mapping, computes food-class mean IoU
  (special channels excluded), the carb-priority subset, and the **export
  eligibility** decision: `mean ≥ 0.60 AND every carb-priority staple ≥ 0.50`.
  `shortfall()` lists what failed (incl. an absent staple — it cannot prove the
  floor, Req 3.6). `record_metrics_into_lineage()` / `update_lineage_file()` write
  the `{mean_iou, per_class_iou, carb_priority_iou, export_eligible, shortfall}`
  block into `build/lineage.json`. Synthetic IoUs in the test; the real run is
  GPU-gated. Carb-priority staples: white_rice, brown_rice, pasta, bread_white,
  bread_wholemeal, potato_boiled, potato_mashed, chips_fries.
- **Uncalibrated honesty (task 10)** — `App/ResultView.swift`. At the MVP gate
  every class is `uncalibrated_unity` (β = 1.0), so the carb number is **real but
  over-estimating**. `ResultFormat.showsUncalibratedBanner(perClassCalibration:)`
  is true when any contributing class is not `calibrated` (or the dict is empty).
  The banner (orange `confidenceModerate` rounded card, up-arrow glyph) is
  **suppressed for `dev_stub`** meals — the yellow placeholder capsule owns the
  *fake-number* case; this marks a *real-but-uncalibrated* number. No schema
  change (`perClassCalibration` is already persisted in `Pipeline.swift`).
- **β_c bake lock (tasks 11–12)** — `tools/food_db/generate.py`. The bake now runs
  under an `__main__` guard via `bake()`, so importing the module is
  side-effect-free (testable without rebaking). `verify_palette_lock(PALETTE_VERSION)`
  reads `ClassPalette.version` from `ClassPalette.swift` (regex on the v1Standard
  literal) and aborts the bake on mismatch (Req 8.4). This only ADDS the lock; the
  baked value stays `'v1'` and `ClassPalette.version` is untouched.

## Gotchas

- **`swift test` does not cover `App/`.** The SPM package targets are CaptureKit,
  Pipeline, Foods, etc.; `App/` (the iOS app, built from `MeData.xcodeproj`, which
  is not in the repo/worktree) is not a package target. ResultView changes are
  verified by build + on-device only (gated). Keep App-side predicates trivially
  correct and reuse existing API/`Color.*` tokens.
- **`ColourTokenUsageTests`** forbids inline `Color(red:…)` in view bodies — always
  use a named token from `App/Colors.swift`. `tools/check_spelling.sh` enforces
  Irish/British spelling but, run over a whole file, naively flags SwiftUI API
  (`colors:`, `.center`, the `Color` type); the real gate scopes tighter. New copy
  must avoid US spellings regardless.
- **Running `generate.py` rebakes `cofid_db.sqlite`/`afcd_db.sqlite` and the SQLite
  bytes differ even with identical data** (page/freelist layout). The DBs are
  *tracked*. If you run the script for a manual check, `git checkout --` the two
  files afterwards unless you intend to commit a rebake. The food-DB density data
  is owned separately — don't bundle a rebake into unrelated work.
- **`rune complete` takes the numeric task id**, e.g.
  `rune complete specs/.../tasks.md 9` (not the `<!-- id:... -->` comment id).
