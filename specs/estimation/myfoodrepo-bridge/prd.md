# PRD: MyFoodRepo-273 bridge, cereal class, and the ungated retrain

> **Amendment 2026-07-26 (MD-30):** the bridge dataset is now the **Food
> Recognition Benchmark 2022** release (same MyFoodRepo source, CC BY 4.0,
> finer ontology, ~40k images) — MyFoodRepo-273 v0.4 is unobtainable (AIcrowd
> storage backend down, no mirror exists; sweep recorded in MD-30). Where this
> PRD says "MyFoodRepo-273", read the 2022 release; the landing zone is
> `data/foodrec2022/` and the mapping artefact is
> `class_mapping_foodrec2022_v1.json`. The spec folder name is unchanged.

## Product summary

MeData estimates carbohydrate content from 1–2 iPhone photos using a fully offline, deterministic pipeline: Core ML semantic segmentation, LiDAR/visual-hull volume geometry, and per-class factors against bundled food-composition databases. Target repository: `medata` (this repo; work lands on the `research` line via the PRD/engage lane).

Two facts motivate this PRD. First, the palette has **no cereal class** — breakfast cereals (porridge, muesli, granola, cornflakes) fall through to `unknown_food`, a gap explicitly recorded in `specs/bugfixes/segmenter-output-stride-ignored/report.md:141` and visible in `tools/nutrition5k/mapping_n5k_to_palette.json` where `oatmeal`, `granola`, `cereal`, and `muesli` are all `status: "unmapped"`. Second, the training set (FoodSeg103) has a hard data ceiling: three carb-priority staples (`brown_rice`, `bread_wholemeal`, `potato_mashed`) have **zero annotated images**, so no training technique can recover them (segmenter-foundation Decision 21), and the entire recent training chain closed with zero shipped uplift (Decisions 23–25). The repo's own improvement survey (`docs/agent-notes/estimation-improvement-avenues.md` §3) names the **MyFoodRepo-273 / AIcrowd Food Recognition Benchmark** bridge (24,119 images, 39,325 segmented polygons, 273 categories, menuCH ontology) as "the only verified fix for the absent staples and the data ceiling", and the snaq-parity spec (Decision 1, Req 8.2) reserved it as its own body of work.

The author has ungated the previously STOP-pointed work: this PRD acquires the MyFoodRepo-273 data, bridges it into an expanded 36-channel palette (the 35 existing channels plus a new `cereal` solid class), retrains the segmenter on the merged corpus, and — if the promotion criterion is met — exports and swaps the bundled model. β_c gravimetric calibration stays deferred past the MVP (model-production Decision 3); carb magnitudes stay coarse by design.

## Goals

- Add a `cereal` solid class to the palette as version v2 (36 channels), with a CoFID-backed food-DB row, so breakfast cereals stop disappearing into `unknown_food`.
- Acquire MyFoodRepo-273 with recorded provenance, audit its coverage of the palette (especially cereal and the three absent staples), and bridge it into the v2 palette as a merged FoodSeg103 + MyFoodRepo-273 training corpus.
- Retrain the segmenter on the merged corpus with a staple-safe recipe, validate against the preserved leak-free anchor, and swap the bundled `segmenter.mlpackage` if and only if the promotion criterion is met.
- Close the small doc-hygiene gaps left by the iOS 26.5 floor move (three stale app-level iOS 17 / iPhone 13-class references) and record the palette and bridge decisions in the existing decision logs.

## Non-goals

- **No β_c gravimetric calibration.** It is recorded as deferred past the MVP (model-production Decision 3, prerequisites lines 18/36); the new cereal row uses CoFID-derived composition and density like every other class, with β staying `uncalibrated_unity`.
- **No Nutrition5k 181 GB ingestion and no `cross-dataset-calibration` work** — that spec stays Planned and off this path.
- **No architecture bake-off.** The SegFormer/EfficientViT spike (segmenter-foundation tasks 20–22) is human-gated on physical-device latency measurement and stays with its owning spec. This PRD retrains the existing DeepLabV3+MobileNetV3-Large recipe.
- **No end-to-end carb-MAE benchmark campaign.** The ≤ ~13 g SNAQ gate needs weighed meals on the physical device (snaq-parity prerequisites) and remains human-gated.
- **No UI changes, no new Swift test scaffolding.** The app test gate stays "builds + looks right on device"; only existing hardcoded palette assertions are updated.
- **No descoping of the non-LiDAR two-view + ID-1-card mode** — it is retained (segmenter-foundation Decision 26); no work is needed, and nothing here may touch it.
- **No palette changes beyond the single cereal class.** No inverse-frequency class weighting anywhere (deleted per snaq-parity Decision 13; the attributed staple-killer per Decision 25).

## Palette and food DB

Covers `MedataCore/Sources/Segmentation/ClassPalette.swift`, `MedataCore/Sources/Persistence/PaletteMigrator.swift`, `tools/food_db/`, and the committed sqlite artefacts under `MedataCore/Sources/Foods/Resources/`.

1. The palette MUST gain a `cereal` solid class appended after the existing 24 solids (index 24), shifting liquids to 25–32 and sentinels to 33/34/35, with the palette version bumped to `v2` and `totalClasses` 36.
   - Acceptance: `ClassPalette` standard palette reports 25 food classes, 8 liquid classes, sentinels 33/34/35, version `v2`; the hardcoded assertions in `MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift:59-72` are updated to match; `make test` is green with both totals reported.
   - Acceptance: the carb-priority staple channels (first 8 solids) keep their existing indices — `tools/segmenter/validation.py:49` and `tools/segmenter/prepare_dataset.py:139-161` remain index-stable.
2. The food DB bake MUST gain a `cereal` row in `FOOD_DATA` (`tools/food_db/generate.py:216-256`) with CoFID-sourced carbohydrate composition and density, `SOLID_CLASS_COUNT` bumped to 25, and both sqlite DBs regenerated and committed under the bake lock.
   - Acceptance: `verify_palette_lock()` passes with `PALETTE_VERSION = "v2"`; regenerated `cofid_db.sqlite` and `afcd_db.sqlite` are committed; `tools/food_db/tests/` (bake lock + palette content lock) updated and green under pytest.
   - Acceptance: the chosen CoFID food codes for cereal (composition and density) are recorded in a decision-log entry (see Specs and docs).
3. Persisted meal data MUST migrate v1 → v2 through the existing `PaletteMigrator` edition path.
   - Acceptance: `PaletteMigratorTests` exercise the real v1 → v2 palettes (cereal unmappable-from-v1 is acceptable and retained per the migrator's existing semantics); `make build` and `make test` green.
4. The bake SHOULD record whether `cereal` joins the carb-priority staple set (per-class ≥ 0.45 floor) now or only after its training coverage is known.
   - Acceptance: a decision-log entry states the choice and rationale; `validation.py` matches it.

## Dataset bridge

Covers `tools/segmenter/` dataset plumbing (`build_class_mapping.py`, `prepare_dataset.py`, new bridge scripts) and the gitignored `data/` tree in the main checkout.

1. The bridge MUST acquire the Food Recognition Benchmark 2022 dataset (MD-30 substitution) into `data/foodrec2022/` with provenance recorded in a `SOURCE.md` following the `data/foodseg103/SOURCE.md` pattern; the release choice (2.0, 498 categories / 2.1, 323 categories) is settled by the coverage audit and recorded in `SOURCE.md`.
   - Acceptance: dataset on disk with images and COCO-format polygon annotations; `SOURCE.md` records source URLs, SHA-256 checksums, licence (expected CC BY 4.0 — record what is actually attached), and image/annotation counts.
   - Acceptance: if the download turns out to require interactive credentials or a browser step, the attempt and the exact blocker are documented and the STOP in Execution notes fires instead of guessing.
2. The bridge MUST publish a coverage audit before any training: which source categories map to each of the 36 palette channels, with per-channel image counts, explicitly settling the survey's unverified caveats.
   - Acceptance: a committed audit artefact (markdown or JSON under `tools/segmenter/` or `docs/agent-notes/`) states the counts for `cereal`, `brown_rice`, `bread_wholemeal`, and `potato_mashed`; where coverage is absent (e.g. brown rice was never confirmed — `estimation-improvement-avenues.md:80-81`), the audit says so plainly and the class simply stays unsupervised rather than being faked.
3. The bridge MUST produce a committed label-space mapping (`class_mapping_foodrec2022_v1.json`) into the v2 36-channel palette via a `build_class_mapping.py`-style curated-rules script, with unmapped categories routed to `unknown_food`.
   - Acceptance: mapping JSON has `channel_count: 36` and sentinels 33/34/35; torch-free unit tests in `tools/segmenter/tests/` cover the curated rules and sentinel routing, green under pytest.
4. The bridge MUST rasterise the polygon instance annotations to PNG semantic masks in palette channel space and produce a merged FoodSeg103 + Food-Recognition-2022 corpus with frozen-seed stratified splits that preserve the existing leak-free anchor.
   - Acceptance: a preparation script emits merged `train/val/heldout` under `data/` with the seed recorded in `splits.json`; the 182-image FoodSeg103 leak-free anchor (`data/foodseg103_remapped/heldout_leakfree/`) is byte-identical afterwards and none of its images appear in the merged train/val split.
   - Acceptance: `co_stats.json` is regenerated food-channels-only (schema `co_stats.v2`) for the merged corpus.

## Training and export

Covers `tools/segmenter/train.py`, `export.py`, `validation.py`, `lineage.py`, and the bundled `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`.

1. The tooling MUST move every 35-channel constant and assertion to 36: `EXPECTED_CHANNEL_COUNT` (`export.py:316`), the `--num-classes` default, `build_class_mapping.py` count constants, and the hardcoded palettes in `tools/segmenter/tests/test_export_gates.py` and `test_class_mapping.py`.
   - Acceptance: the full torch-free pytest suite under `tools/segmenter/tests/` is green.
2. The trainer MUST run a full training job on the merged corpus at 36 classes on local MPS, detached and resumable, with a staple-safe recipe: class rebalancing `none` or at most `sqrt_inverse`, no inverse-frequency weighting, geometric augmentation on, photometric augmentation at the executing agent's discretion with the choice recorded.
   - Acceptance: launched per `docs/ml-training.md` §4 (`nohup caffeinate -is`, resume sidecar active, log file retained); `train.py` and its imports are not edited while the run is live (`docs/agent-notes/model-production.md` gotcha); the completed checkpoint and its lineage entry exist.
3. The run MUST be validated with an honest before/after against the preserved leak-free anchor, and the promotion decision recorded: swap the bundled model only if leak-free mean food-class IoU beats the 0.3776 anchor of `24e0b022241a` AND no existing carb-priority staple regresses materially; otherwise record the rejection in the ledger exactly as Decisions 24/25 did.
   - Acceptance: `run_validation.py` output recorded in `tools/segmenter/build/lineage.json`, including per-staple and cereal IoU; the promotion or rejection verdict, with numbers, lands in the segmenter-foundation decision log.
   - Acceptance: if promoted while still below the 0.48/0.45 gates, the developer-phase override is used with an attributable reason and `export_eligible` stays truthful.
4. On promotion, the model MUST be exported and swapped through the existing gates and deployed for verification: `export.py` (24 MiB weight budget, 36 channels in palette order, oracle parity), then `make deploy-release`.
   - Acceptance: export gates pass; the device launch log shows the new `segmenterSource=coreml_<12-hex>` with a matching `buildStamp` via `make logs-device`.

## Specs and docs

Covers decision logs, agent notes, and the stale floor references. Doc-only context; `make spell` gates everything here.

1. The docs MUST annotate the three stale app-level floor references found in the 2026-07-25 audit: `specs/estimation/pipeline/tasks.md:36` (app target "iOS 17"), `specs/estimation/pipeline/decision_log.md:229` (iOS 17 / iPhone 12–13 Pro floor, not marked superseded), and `specs/estimation/model-production/prerequisites.md:16` (13 Pro Max as the verify device).
   - Acceptance: each carries a superseded/annotation note pointing at iOS 26.5 and the iPhone 16 Pro floor (segmenter-foundation Decisions 22/26); historical text is annotated, not rewritten; MedataCore-package iOS 17 references are left alone.
2. The decision record MUST be extended in place: palette v2 + cereal (with CoFID codes) and the bridge execution + promotion/rejection verdict go into the existing ledgers (`specs/estimation/segmenter-foundation/decision_log.md` for the training chain; the palette/DB decision may live there or in `specs/DECISIONS.md`, following where Decision 21-era palette decisions live), using the Enhanced Nygard format already in use.
   - Acceptance: entries follow the existing format with alternatives and consequences; no new spec folders are created for this.
3. The operational docs MUST be updated for the new corpus and palette: `docs/ml-training.md` (dataset table, run commands, 36-channel notes) and `docs/agent-notes/dataset-strategy.md` (MyFoodRepo-273 section with licence and split posture); `docs/agent-notes/model-production.md` gains the run's outcome.
   - Acceptance: docs updated; `make spell` green.
4. The overview SHOULD be regenerated at close via the specs-overview workflow rather than hand-edited.
   - Acceptance: `specs/OVERVIEW.md` reflects this PRD's folder.

## Execution notes

- Quality gates: `make build`, `make test` (report BOTH the XCTest and swift-testing totals), `make spell` — all via the repo-root Makefile. Python tests have no Makefile target: run pytest manually with `tools/segmenter/.venv` for `tools/segmenter/tests/` and `tools/food_db/tests/`. Use `run_silent` where available.
- Ordering: **Palette and food DB merges first** — it defines the v2 channel order everything else consumes. **Dataset bridge** acquisition and the coverage audit (requirements 1–2) can run in parallel with it, but the mapping JSON and merged corpus (requirements 3–4) need the final v2 order. **Training and export** needs both. **Specs and docs** requirements 1 and 3 are independent; requirement 2's verdict entry waits on the training outcome.
- Worktree caveat: `data/` is gitignored and exists only in the main checkout — bridge and training code must reference it by absolute path (`/Users/r/repos/medata/data/…`). The long training run itself must be launched from the main checkout after the palette and bridge work has merged, not from a temporary worktree that will be cleaned up mid-run.
- The training run is ~10+ hours of local MPS wall-clock for 60 epochs (~20 min/epoch on M5 Pro). Measure one epoch before committing to the full run; rely on the resume sidecar for interruptions.
- iOS 26.5 floor and non-LiDAR retention are already done and verified on device (commits `4ee8199`, `8f18a8d`; user confirmation 2026-07-25) — verify, don't redo. Only the three stale references in Specs and docs remain.
- STOP — dataset acquisition: if the download requires interactive login, CAPTCHA, or terms acceptance that cannot be completed non-interactively, stop and ask the user for the credential or the archive (document the exact URL and steps needed); do not scrape around an auth wall. (Fired 2026-07-25 for v0.4; resolved by the MD-30 substitution — the 2022 Kaggle mirror needs a user-supplied API key.)
- STOP — on-device capture verification: after a promoted model is deployed, a human must point the phone at real meals (including a cereal bowl) to confirm the overlay and readings; the agent verifies only the launch log and build stamp.
- STOP — ANE residency: the Core ML performance-report check is manual in Xcode; record it as pending rather than claiming it.
