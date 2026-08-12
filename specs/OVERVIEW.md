# Specs Overview

> How specs are written, tracked, and turned into code: [PROCESS.md](PROCESS.md).
> Cross-cutting architectural decisions are distilled in the meta decision log: [DECISIONS.md](DECISIONS.md). Per-spec decision logs below remain authoritative for detail.

> **Domain** ([PROCESS.md §3](PROCESS.md#3-directory-structure-spec-boundaries-and-naming)) — every spec lives at `specs/<domain>/<capability>/`; the domain is one of `platform · capture · estimation · data · ui`.
> **Mode** ([PROCESS.md §5](PROCESS.md#5-choosing-the-mode-full-spec-smolspec-or-iterative)) — `full` / `smol` / `iterative`; a `·iterative` suffix marks a target-driven concern inside an otherwise deterministic spec.

| Name | Domain | Created | Status | Mode | Summary |
|------|--------|---------|--------|------|---------|
| [Research](#research) | estimation | 2026-05-24 | Done | full ·iterative | Low-compute on-device system estimating carbohydrate content from one or two iPhone photos. |
| [Pipeline Real Device Correctness](#pipeline-real-device-correctness) | estimation | 2026-06-13 | Done | full | Replace Phase-1 stop-gaps with a pre-shutter food-region mask, real foodRegionCoveragePercent, and Vision-backed CardDetector to unblock the iPhone 13 Pro Max fruit-plate MVP capture. |
| [Minimum Viable Volume Estimator](#minimum-viable-volume-estimator) | estimation | 2026-06-22 | Superseded | smol | Retired before tasks/code (decision_log Decision 5): its premise that the dev-stub yields uncarveable masks proved false; the real two-view defect lives in `bugfixes/two-view-carve-no-volume`. |
| [LiDAR First Scale Fallback](#lidar-first-scale-fallback) | estimation | 2026-06-23 | Done | smol | Make a card-pose-solve failure non-fatal when LiDAR depth is present so the pipeline falls back to LiDAR-only scale instead of aborting. |
| [Model Production](#model-production) | estimation | 2026-06-29 | Done | full | Train → Core ML export → bundle the on-device segmenter. All 13 code tasks done; two real models shipped under the Decision 11 developer-phase override (latest `24e0b022241a`, letterbox recipe, 2026-07-06) — on-device capture verify and β_c calibration remain gated, see [prerequisites.md](estimation/model-production/prerequisites.md). |
| [Nutrition5k Calibration](#nutrition5k-calibration) | estimation | 2026-07-01 | Done | full | Bridge the Nutrition5k RGB-D dataset into the harness to fit per-class β bulk-correction factors, bake them into the food DB with lineage, report carb/protein/fat accuracy against a β=1.0 baseline, and add standalone-liquid classes to the in-place-redefined palette. All 45 tasks done (39 implementation + closeout consolidation); the post-checkpoint single-dominant re-fit stays gated on model-production Bucket C. |
| [Resumable Segmenter Training](#resumable-segmenter-training) | estimation | 2026-07-02 | Done | smol | Give `train.py` crash-safe per-epoch checkpointing and a `--resume` flag for interruptible local-Mac (MPS) training runs. |
| [Cross-dataset Calibration](#cross-dataset-calibration) | estimation | 2026-07-04 | Done | full | Broaden per-class β calibration beyond Nutrition5k by rendering overhead depth from MetaFood3D single-food meshes and feeding them as single-class mixture rows to the existing harness, so carb staples gain samples N5k's mixed plates cannot. All 23 tasks done (Decisions 15–17: palette content retarget, MF3D-only reference stamping, canonical run_summary contract + strictest-licence lineage; Decision 18: NC data free for research βs, commercial ship needs an NC-free re-bake or commercial licence); awaiting only the request-gated dataset snapshot before a real corpus run. |
| [Estimation Quality](#estimation-quality) | estimation | 2026-07-09 | In Progress | prd | Kill the mask speckle and stabilise carb readings: imbalance-aware `--loss`/`--photometric-augment` training flags (torch-free tested), deterministic connected-component speckle cleanup (default-on), plane-fit consensus polish + fail-closed food-coverage gate, and the segmenter-improvement research doc. 4 contexts landed; the on-device speckle verify closed 2026-08-13 (speckle gone, accepted on the promoted model + cleanup); the new-recipe training run + export/swap remains the one open human-gated STOP. |
| [Segmenter Foundation](#segmenter-foundation) | estimation | 2026-07-10 | In Progress | full | Re-derive the segmenter bars (gate 0.60 → mean IoU ≥ 0.48, staple floors 0.50 → 0.45), upgrade the training recipe (stronger init + co-occurrence loss, stratified heldout re-cut) as the primary lever, and gate a SegFormer-B0 backbone swap on a Core ML conversion spike measured on the hardware floor. 19 of 22 tasks done — training chain executed with a NEGATIVE verdict (Decision 24): the co-occurrence recipe regressed the leak-free same-set mean 0.3776 → 0.3253 with four staple regressions, so `24e0b022241a` stays bundled; V2 init was separately rejected mid-run (Decision 23) and the floor re-based to the iPhone 16 Pro (Decision 22). Combined-loss fallback run in flight as a weighting-vs-co-term experiment; the spike's autonomous half (task 14) passed 2026-08-09 (converts, 7.3 MiB vs 24 MiB budget, oracle argmax 0.9998), leaving the device-gated ANE latency measurement (20), the verdict entry (21) and the conditional retrain (22). |
| [SNAQ Parity](#snaq-parity) | estimation | 2026-07-17 | Done | full | Make estimation quality measurable against SNAQ's real-world figure (per-meal carb MAE ≤ ~13 g, completion rate always reported): an in-app weighed-meal benchmark with a paired-bootstrap promotion gate, a persistent on-device outcome/diagnostics store so "no volume" refusals carry causal measurements (pre/post-β volumes, skip counters, plane/scale/tilt), and the ranked model levers — segmenter tail profiling, a 4-candidate conversion bake-off via a shared `archs.py` registry, Recipe1M+-derived co-occurrence statistics, inverse-frequency weighting removed (Decision 25 enforced in code). Bounded cycle: complete on evidence-backed verdicts, not on hitting the target; seeds the MyFoodRepo-273 bridge if unmet. All 24 tasks done — diagnostics foundation, the persistent outcome store, the `Benchmark` target (SNAQ-anchored `BenchmarkReport.compute` + seeded paired-bootstrap `promotionVerdict`), the `EstimationLogView`/`BenchmarkView` Settings surfaces, and all Python levers; the cycle's exit condition (Req 8: benchmark campaign, tail profile, bake-off and retrain verdicts) is human-gated per prerequisites.md. |
| [MyFoodRepo Bridge](#myfoodrepo-bridge) | estimation | 2026-07-25 | In Progress | prd | Palette v2 (cereal at 24, 36 channels) plus the dataset bridge that fixed the zero-image staples — MD-30 substituted the obtainable Food Recognition 2022 release for the unreachable v0.4, and the merged-corpus retrain beat the leak-free anchor (0.3927 vs 0.3776; cereal 0.48 on val) and shipped as model `ab812dc3aa9d` (Decision 27). 19/22 tasks done; remaining: the device launch-log verify and the two human STOPs (capture pass incl. a cereal bowl, ANE residency). |
| [Support Plane Reference](#support-plane-reference) | estimation | 2026-07-27 | In Progress | full | Redefine the LiDAR support plane as the surface the food rests on rather than the largest gravity-aligned plane in the frame: the current fit lands on the table, 26.1 mm too low, and per-pixel integration turns that into a 2–3.6× volume over-read confirmed by two weighed captures. Bounded annulus sampling on the native depth grid, CC-RANSAC scoring, and a contact-ring admissibility filter, with rejection falling back to today's edge-band fit unchanged. 25/27 tasks done — geometry and selection (`SupportRegion`), wiring and persistence, harness parity, and regression fixtures are in: the offline replay derives its plane from the same code the device runs, the accuracy report carries the fallback rate segmented by reference, the calibration artefact records the reference each β was fitted under with a fail-closed bake guard, and committed 290 KB depth slices made Reqs 6.2/7.1/7.2 executable from a clean checkout — which falsified three of the figures they stated (Decision 28). The N5k rebase then ran and falsified its own premise: pre-checkpoint ingestion stamps every plate `mixture`, so the promoted fitter gets no N5k coverage at all until model-production Bucket C lands. Only the corpus constant measurements and the on-device weighed verify remain. |
| [Alternative Class Candidates](#alternative-class-candidates) | estimation | 2026-08-07 | 17/20 | full | Retain the per-detected-food alternative classes the segmenter computes and discards, so a relabel shortlist can offer a food the user has never chosen. Owed by meal-review Decision 18, which deferred it and shipped recency ordering. Recency is kept as a live component of the ordering rather than superseded (Decision 6). Requirements and design both approved 2026-08-10 (design-critic + peer review applied; Decisions 7–12: three-layer shortlist, JSON-sized encoding, shared-function replay parity, pre-implementation statistic probe, 64-sample floor, stated Req 8 confound). Probe gate discharged 2026-08-11 (Decision 13): mean-over-region ships — true class in the top five on 78.2% of the segmenter's wrong regions vs 68.6% for second-argmax share, and the early-exit condition was not met. Boundary bleed is real and ships unmitigated (rank 1 touches the food 69.7% vs 9.1% chance; erosion measured and rejected), tracked in `docs/agent-notes/candidate-evidence.md`, a required Req 8 adjacency partition, and a conditional mitigation task. The evidence pass landed 2026-08-11 — `CandidateEvidence.compute`, its post-processing call site and the Req 2.2 non-interference test that pins σ_seg, the argmax bytes, `perClassMeanProb` and the refusal outcome as unchanged by it. The persistence contract landed 2026-08-12 — meal-record fields 16/17 as parallel arrays plus the produced marker, carried through the pipeline assembly and both member-wise copy sites, with the worst case measured at 920 B of added JSON against the 1 KB budget. The combined ordering landed 2026-08-12 — `ShortlistOrdering.combined` (recency, then evidence fills, then the shipped top-up) consumed by `MealReviewModel.buildShortlist`, so evidence displaces only the blind top-up and an empty fills layer reproduces the shipped list byte for byte. Replay parity landed 2026-08-12 — one synthetic bundle-shaped fixture through the shared `compute` against a golden committed beside it, with a 0.2005 channel that reads 200 per mille as FP16 and 201 as FP32 so the decode contract fails loudly if the ranking ever moves to the intermediate buffer; the harness gains no candidate-evidence code of its own. The Req 8 corpus analysis landed 2026-08-12 — `tools/shortlist_hit_rate.py` reads device pulls or the Corrections JSONL and emits the hit rate per arm, the first-vs-repeat split, the recency-depth strata, the as-treated cut and the required boundary-bleed partition, each with its cell count. It runs and answers nothing yet: the corpus carries 8 correction rows and zero relabels, so every cell is empty and the bleed verdict is `insufficient`. The conditional mitigation task closed 2026-08-12 (Decision 14): unfireable by any agent session, its condition folds into the acceptance-verdict gate — a `hurting` bleed verdict there reopens the repair as the step before removal. 20 tasks: 17 done, 3 STOP acceptance gates no autonomous run may attempt. |
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | capture | 2026-05-06 | Done | full | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Capture Bundle Recorder](#capture-bundle-recorder) | capture | 2026-07-18 | Done | smol | Record a harness-replayable `PbMealFixture` bundle per estimation attempt to `Documents/captures/` (Files-app visible), so any field capture replays offline through the existing Mac harness with no harness changes. Always on incl. Release; no UI. All 5 tasks done; the on-device field-day pass closed 2026-08-11 (bundles for all 15 session attempts, stem↔outcome-row join, same-day pull + replay), and the emptyFoodMask refusal recording landed the same day (`pre_shutter_mask` fields 27-29, written on every bundle). |
| [Event Log Schema](#event-log-schema) | data | 2026-06-10 | Done | full | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |
| [Libre Ingestion](#libre-ingestion) | data | 2026-07-04 | Done | full | Extract glucose readings on-device from user-picked LibreLink screenshots into `bsl` events; Swift port of imgdatacollector gated by its 9-image accuracy corpus. |
| [iPhone Experience](#iphone-experience) | ui | 2026-05-22 | Done | full ·iterative | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. Visual design (Req 20) is iterative against [`design-system/`](../design-system/MASTER.md). |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | ui | 2026-05-31 | Done | smol | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. All 5 tasks done; the success-path device verify closed 2026-08-11 on the iPhone 16 Pro. |
| [Bubble-only Cleanup](#bubble-only-cleanup) | ui | 2026-06-24 | Done | smol | Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the device-confirmed .bubble guide as the sole design. |
| [Loading Symbol Animation](#loading-symbol-animation) | ui | 2026-07-04 | Done | smol | Reusable SwiftUI loader that draws the Medata mark stroke-by-stroke (bowl→bar→dot). All 6 tasks done — verified on device 2026-08-11; the `.estimating` call-site adoption had already landed via design-handoff-00. |
| [Design Handoff 00](#design-handoff-00) | ui | 2026-07-04 | Done | full | Adopt the first external design handoff, amended in use: Graph (carbs vs glucose, renamed from Trends) is the launch root (Decision 20 — since superseded by home-router Decision 7, HomeView); Capture/Data/Settings present as full-screen covers; redesigned screens, Meal overview, minimal wording, no disclaimer copy (dev-phase rule), versioned handoff archive. All 27 tasks done + Decisions 19–21; device-verify checklist in prerequisites.md. |
| [Home Router](#home-router) | ui | 2026-07-07 | Done | full | Home page becomes the launch root (no tab bar): six routed full-screen covers with Capture primary, unified Records timeline (meals + insulin + glucose, delete for manual entries only — since superseded by Records Deletion), Graph demoted to visualisation-only. All 11 tasks done; the on-device visual verify and the latest-glucose header STOP both closed 2026-08-13. |
| [Records Deletion](#records-deletion) | ui | 2026-07-26 | Done | smol | The Records list becomes the primary deletion surface: swipe-delete on every row type (glucose included, superseding home-router Req 3.5), edit-mode multi-select with Select All, a confirmed date-range purge, and one-tap Delete All Records. All 5 tasks done; device verify 2026-08-11 (which caught and fixed the literal inflect-markup dialog copy). |
| [Mass Readout](#mass-readout) | ui | 2026-07-26 | 3/4 | smol | Display-only mass readout: estimated grams beside carbs wherever scale-truth validation happens. Smolspec reconciled to the post-meal-review architecture (Decision 1): ResultView hero and Records rows shipped with meal-review; the at-capture MealReviewView line implemented 2026-08-10. Remaining: the human-gated device look check. |
| [Glucose Lock Screen Widget](#glucose-lock-screen-widget) | ui | 2026-07-27 | In Progress | full | WidgetKit accessory widget (circular/rectangular/inline + StandBy) showing the most-recent `bsl` reading + a derived trend arrow, fed by an app-written App Group snapshot; status is a non-colour channel that survives the Lock Screen's monochrome rendering, with a dim>15/hide>30 staleness ladder and a `medata://graph` tap target. 14 of 16 tasks done — the device pass (14) closed 2026-08-13 but surfaced the widget going stale while the app is suspended, now Decision 16 (accepted): the extension fetches LibreLinkUp itself under a shared 5-minute vendor budget (cgm-connect Decision 13), tasks 16.1–16.7; the trend-derivation tightening (15) also remains. |
| [Meal Review](#meal-review) | ui | 2026-08-06 | Done | full | Collapse the read-only segmentation review and the result screen into one post-capture surface: detected foods outlined on the photo, relabel and reject per food, serving/gram amounts, and one tap to record. The deliverable is the corpus — one correction record per detected food per capture, predicted values beside corrected ones, never discarded on age, count, or any sweep. All 22 tasks done — contracts and shared β re-derivation, the exempt correction store (self-healing upsert), MealReviewView with contour outlines/relabel/reject/scale, the capture-stack rewire (SegmentationReviewView deleted, ResultView collapsed to the history read path), the supersessions owed design-handoff-00 and serving-adjust, and the integration gate (build, 572 XCTest + 395 swift-testing green, spell). The device sheet in prerequisites.md stays open as human-gated verification, outside the task ledger. |
| [Regression Suggestion Integration](#regression-suggestion-integration) | data · ui | 2026-07-05 | Done | prd | Insulin dosing as a first-class event stream conforming to medreg's insulin-event convention: dose-entry sheet from the Graph toolbar, Graph dose markers/stats, `medata://` deep links, and lock-/home-screen launcher widgets (`MeDataWidgets`). All 20 tasks across 3 contexts done. |
| [CGM Connect](#cgm-connect) | data | 2026-07-10 | In Progress | full | Live glucose ingestion behind a source abstraction (HealthKit primary, LibreLinkUp follower complement) writing `bsl` events with cross-source 5-minute-grid dedup, firewalled from estimation by a package-graph test. Poll baseline redefined to a uniform 5 minutes (Decision 13; Decision 12's adaptive scheme dormant as the rollback). 17/19 tasks done; the on-device verify (task 14) and the uniform-poll STOP (task 16, redefined) are human-gated. |
| [Manual Carb Intake](#manual-carb-intake) | data · ui | 2026-07-07 | Done | full | Manual carb/macro logging without the camera: carb-entry sheet (keypad, 1–999 g, optional macros behind a disclosure), one-tap quick-add presets (`quick_presets` table, seeded defaults), inline edit/delete of manual entries, `EventType.intake` folded into the Graph carb series and Records timeline. All 11 tasks done; on-device verification checklist (design.md) human-gated. |
| [Snaqui](#snaqui) | ui · data | 2026-07-13 | In Progress | prd | SNAQ-inspired uplift: portion-adjustment control on the result screen (N-of-M fractions + multiples, persisted as append-only `PbUserCorrection`), Graph carb bars honour corrected totals, full-screen pages lose their redundant navigation titles, metric-chip row wraps instead of truncating. The global portion stepper is since superseded by Serving Adjust's per-food rows. 7/8 tasks done; on-device looks-right pass (task 8) human-gated. |
| [Serving Adjust](#serving-adjust) | data · ui | 2026-07-17 | Done | prd | Move the portion control onto the per-ingredient rows counting in household servings (spoons, potatoes) with grams secondary: a data-driven solid-food servings table in the DB generator (mirroring `liquid_servings`) and a reshaped result screen with per-row steppers + one-tap plate-fraction, persisted through the existing append-only `PbUserCorrection`. All 11 tasks done. |
| [Clean Build Baseline](#clean-build-baseline) | platform | 2026-06-03 | Done | smol | Zero-warning baseline: eliminate the five compiler/validator warnings (iPhone-only `TARGETED_DEVICE_FAMILY`, nonisolated reader, `UIScreen.main` deprecation) with the smallest viable changes. Relocated 2026-07-26 from `specs/bugfixes/` — warning cleanup, not a defect. All 4 tasks done. |

---

## Research

Low-compute on-device system estimating carbohydrate content from one or two iPhone photos. (Folder: `estimation/pipeline/`; formerly the flat `research/` spec.)

- [decision_log.md](estimation/pipeline/decision_log.md)
- [design.md](estimation/pipeline/design.md)
- [prerequisites.md](estimation/pipeline/prerequisites.md)
- [requirements.md](estimation/pipeline/requirements.md)
- [tasks.md](estimation/pipeline/tasks.md)

## Pipeline Real Device Correctness

Replace Phase-1 stop-gaps with a pre-shutter food-region mask, real foodRegionCoveragePercent, and Vision-backed CardDetector to unblock the iPhone 13 Pro Max fruit-plate MVP capture.

- [decision_log.md](estimation/pipeline-real-device-correctness/decision_log.md)
- [design.md](estimation/pipeline-real-device-correctness/design.md)
- [prerequisites.md](estimation/pipeline-real-device-correctness/prerequisites.md)
- [requirements.md](estimation/pipeline-real-device-correctness/requirements.md)
- [tasks.md](estimation/pipeline-real-device-correctness/tasks.md)

## Minimum Viable Volume Estimator

**Superseded / abandoned (no code landed).** Proposed decoupling the dev-stub volume path from the per-class segmenter so two-view capture completes with a rough, low-confidence carb number instead of refusing `noFoodVolumeRecovered`. Retired before tasks were written (decision_log Decision 5) — the dev-stub already paints a carveable food-class silhouette, so the framing solved a non-problem; the real two-view defect is tracked in `bugfixes/two-view-carve-no-volume`.

- [decision_log.md](estimation/mv-volume-estimator/decision_log.md)
- [smolspec.md](estimation/mv-volume-estimator/smolspec.md)

## LiDAR First Scale Fallback

Make a card-pose-solve failure non-fatal when LiDAR depth is present so the pipeline falls back to LiDAR-only scale instead of aborting.

- [decision_log.md](estimation/lidar-first-scale-fallback/decision_log.md)
- [smolspec.md](estimation/lidar-first-scale-fallback/smolspec.md)
- [tasks.md](estimation/lidar-first-scale-fallback/tasks.md)

## Model Production

Train → Core ML export → bundle the on-device segmenter. All 13 implementable tasks are done — Bundle.module loader, build lineage manifest, modelVersion derivation, export.py equivalence/parity/channel/budget/metadata gates, validation mIoU + export-eligibility reporting, and the palette↔DB edition bake lock. Two real models have shipped under the Decision 11 developer-phase override: `0295ea61edd9` (2026-07-05, heldout mean food-class IoU 0.4259) and the letterbox retrain `24e0b022241a` (2026-07-06, 0.4054, closing the train↔runtime square-resize skew; Decision 15 records `run_validation.py` as the developer-phase gate). Still gated as prerequisites: on-device capture verify (the MVP gate, Req 6.3) and β_c gravimetric calibration (deferred past the MVP).

- [decision_log.md](estimation/model-production/decision_log.md)
- [design.md](estimation/model-production/design.md)
- [prerequisites.md](estimation/model-production/prerequisites.md)
- [requirements.md](estimation/model-production/requirements.md)
- [tasks.md](estimation/model-production/tasks.md)

## Nutrition5k Calibration

Bridge Google Nutrition5k overhead RGB-D + per-ingredient gravimetric labels into the existing `.fixture`/`HarnessCLI calibrate` pipeline to fit per-class β bulk-correction factors (single-dominant + mixture BVLS paths), bake them into the food DB with lineage/provenance, report carb/protein/fat accuracy against a β=1.0 baseline, and add coarse standalone-liquid classes to the in-place-redefined palette. All 45 tasks done — the 39 implementation tasks including the pre-checkpoint end-to-end run (committed artifacts under [artifacts/](estimation/nutrition5k-calibration/artifacts/)) plus the closeout consolidation phase (tasks 40–45: worktree merges into `research`, index regeneration, branch cleanup, push; Decision 29). The post-checkpoint single-dominant re-fit + supersession re-run stays a documented manual step gated on model-production Bucket C.

- [decision_log.md](estimation/nutrition5k-calibration/decision_log.md)
- [design.md](estimation/nutrition5k-calibration/design.md)
- [prerequisites.md](estimation/nutrition5k-calibration/prerequisites.md)
- [requirements.md](estimation/nutrition5k-calibration/requirements.md)
- [tasks.md](estimation/nutrition5k-calibration/tasks.md)

## Resumable Segmenter Training

Give `train.py` crash-safe per-epoch checkpointing and a `--resume` flag for interruptible local-Mac (MPS) training runs; the shipped checkpoint format and export.py contract stay unchanged.

- [decision_log.md](estimation/resumable-segmenter-training/decision_log.md)
- [smolspec.md](estimation/resumable-segmenter-training/smolspec.md)
- [tasks.md](estimation/resumable-segmenter-training/tasks.md)

## Cross-dataset Calibration

Broaden per-class β calibration beyond Nutrition5k by rendering overhead depth from MetaFood3D single-food meshes and feeding them as single-class mixture rows to the existing harness, so carb staples gain samples N5k's mixed plates cannot.

- [decision_log.md](estimation/cross-dataset-calibration/decision_log.md)
- [design.md](estimation/cross-dataset-calibration/design.md)
- [requirements.md](estimation/cross-dataset-calibration/requirements.md)
- [tasks.md](estimation/cross-dataset-calibration/tasks.md)

## Estimation Quality

PRD-lane work (engage): kill the visible mask speckle ("linear stripes of spots") and stabilise run-to-run carb readings. Landed across four contexts — the segmenter-improvement research doc attributing the 0.40-mIoU plateau to unweighted cross-entropy over the 35-class imbalance ([docs/agent-notes/segmenter-improvement-research.md](../docs/agent-notes/segmenter-improvement-research.md)); opt-in `--loss {weighted_ce,focal,dice,combined}` + `--photometric-augment` training flags with torch-free tests; deterministic connected-component speckle regularisation default-on in `PostProcessing.swift`; plane-fit consensus polish and a fail-closed food-coverage gate. The on-device speckle/stability verify closed 2026-08-13 — speckle confirmed gone, accepted on the promoted model + PostProcessing cleanup without waiting on the retrain; the new-recipe training run + export/swap remains the one open human-gated STOP — the recommended run command is in [docs/ml-training.md](../docs/ml-training.md) §4.

- [prd.md](estimation/estimation-quality/prd.md)
- [tasks-estimation-runtime-consistency.md](estimation/estimation-quality/tasks-estimation-runtime-consistency.md)
- [tasks-mask-post-processing-cleanup.md](estimation/estimation-quality/tasks-mask-post-processing-cleanup.md)
- [tasks-segmentation-approach-research.md](estimation/estimation-quality/tasks-segmentation-approach-research.md)
- [tasks-segmenter-training-pipeline.md](estimation/estimation-quality/tasks-segmenter-training-pipeline.md)

## Segmenter Foundation

Decides the model foundation for the on-device segmenter, driven by the Track A deep-research findings ([docs/agent-notes/model-foundation-research.md](../docs/agent-notes/model-foundation-research.md)): the 0.60 heldout-mIoU gate sits above the FoodSeg103 compact-model frontier, so the bars are re-derived — mean IoU ≥ 0.48 (Decision 5) with 0.45 per-staple floors (Decision 14), uplift set anchored to the gate (Decision 18). The training-recipe upgrade on the existing DeepLabV3+MobileNetV3-Large is the primary lever (Decision 17 init survey + FoodSeg103-internal co-occurrence loss, Decision 15), measured against a stratified heldout re-cut (Req 2.6); a SegFormer-B0 backbone swap is explored only if a Core ML conversion spike passes size/latency/parity, latency measured directly on the hardware floor — re-based to the iPhone 16 Pro (Decisions 16/22); text-conditioning, SAM-family, and FoodSAM recorded as evaluated-and-rejected. 22 tasks: 19 done — the repo-wide 0.48/0.45 amendment pass, stratified heldout carve (`prepare_dataset.py`, `co_stats` restricted to food channels, Decision 20), co-occurrence loss wiring, checkpoint survey, adapter probe and SegFormer spike code, and the executed re-cut + baseline re-measure (task 17, Decision 21: frozen seed 20260715; the full-heldout re-measure is train-contaminated so uplift anchors to a leak-free 182-image table; three staples have zero FoodSeg103 images, so their floors stay unprovable on this dataset). The adapter probe FAILED, settling Decision 19 on torchvision `IMAGENET1K_V2` via the new `train.py --init-checkpoint` — then that init was itself rejected on a 20-epoch trajectory comparison (Decision 23). Tasks 18–19 executed 2026-07-16 with a NEGATIVE verdict (Decision 24): the co-occurrence recipe lifted dead tail classes but regressed the leak-free same-set mean 0.3776 → 0.3253 with four staple regressions beyond tolerance, so nothing was exported and `24e0b022241a` stays bundled; a combined-loss fallback run is in flight to attribute the regression to the inverse-frequency weighting or the co-occurrence term. 19 of 22 tasks done; remaining: the 16 Pro spike measurements (20–22). The 2026-07-15 improvement survey ([docs/agent-notes/estimation-improvement-avenues.md](../docs/agent-notes/estimation-improvement-avenues.md)) seeds the next cycle.

- [decision_log.md](estimation/segmenter-foundation/decision_log.md)
- [design.md](estimation/segmenter-foundation/design.md)
- [prerequisites.md](estimation/segmenter-foundation/prerequisites.md)
- [requirements.md](estimation/segmenter-foundation/requirements.md)
- [tasks.md](estimation/segmenter-foundation/tasks.md)

## SNAQ Parity

Makes carb-estimation quality measurable against SNAQ's published real-world accuracy and every estimation attempt diagnosable: an in-app weighed-meal benchmark (ground truth from the bundled food DB, ≥ 20 meals including staple-floor foods, MAE never reported without completion rate, paired-bootstrap promotion gate), a persistent bounded outcome store capturing per-stage measurements on success and refusal alike, and the ranked improvement levers from the 2026-07-15 survey — upsample-tail profiling, an EfficientViT/SeaFormer/PP-MobileSeg conversion bake-off with the winner trained via a shared architecture registry, Recipe1M+-derived co-occurrence statistics, and code-level removal of the Decision 25 inverse-frequency weighting. Bounded cycle (Decision 5): done on recorded verdicts; the MyFoodRepo-273 dataset bridge is the named successor if the ≤ 13 g target is unmet. All 24 tasks done: the diagnostics foundation (non-throwing `VolumeOutcome` estimators, `EstimationAttemptRecord`/`PipelineDiagnostics`, pipeline stage-measurement wiring), the persistent `estimation_outcomes` store with split eviction bounds and write-behind persistence from `CaptureFlowModel`, the `benchmark_meals` store and `Benchmark` target (SNAQ-anchored report maths + seeded paired-bootstrap promotion gate, Decision 15), the `EstimationLogView`/`BenchmarkView` Settings surfaces, and every Python lever (`archs.py` registry, `--class-weighting`, `build_external_co_stats.py`, `spike_convert.py`). The cycle's Req 8 exit condition — the ≥ 20-meal benchmark campaign, tail-profile budget derivation, bake-off conversion verdicts, and any retrain — is human-gated (prerequisites.md); each ends in a recorded verdict.

- [decision_log.md](estimation/snaq-parity/decision_log.md)
- [design.md](estimation/snaq-parity/design.md)
- [prerequisites.md](estimation/snaq-parity/prerequisites.md)
- [requirements.md](estimation/snaq-parity/requirements.md)
- [tasks.md](estimation/snaq-parity/tasks.md)

## MyFoodRepo Bridge

PRD-lane spec: the contingent big move named by SNAQ Parity — bridge a MyFoodRepo-derived dataset into the training corpus (the only verified fix for the three zero-image staples, segmenter-foundation Decision 21) and land the missing cereal class flagged as a required MVP fix. Four contexts: the cereal palette class (solid index 24, 36 channels, cereal CoFID row baked into both DBs under the bake lock, MD-29 — the "palette v2" label this shipped under was expunged by pipeline Decision 50); the dataset bridge; training and export; and specs/docs. The original MyFoodRepo-273 v0.4 pin proved unobtainable (AIcrowd's storage backend down, no mirror anywhere) — **MD-30** substituted the Food Recognition Benchmark 2022 release (same MyFoodRepo source, CC BY 4.0, 39,962 train images, 498 categories, Kaggle mirror), whose ontology covers all four target classes. The bridge then ran end-to-end: curated 498→36 mapping + coverage audit (cereal 592 / bread_wholemeal 2,547 / potato_mashed 150 / brown_rice 131 train images), COCO polygon rasterisation (40,962 masks), merged corpus (45,515/1,711/854, leak-free anchor preserved byte-identically), and a 12-epoch incumbent-recipe retrain that **beat the 0.3776 leak-free anchor at 0.3927** (0.4212 family-collapsed; cereal 0.4831 / bread_wholemeal 0.4787 / potato_mashed 0.3719 on merged val; brown_rice honestly unlearned). Promoted as Decision 27: `PipelineFactory` flipped to the 36-channel palette, bundled model swapped to `ab812dc3aa9d` through the export gates, release build installed on the iPhone 16 Pro. 19/22 tasks done; remaining: the device launch-log verify (phone locked at deploy) and the two human STOPs — the on-device capture pass including a cereal bowl, and the Xcode ANE residency check.

- [prd.md](estimation/myfoodrepo-bridge/prd.md)
- [tasks-dataset-bridge.md](estimation/myfoodrepo-bridge/tasks-dataset-bridge.md)
- [tasks-palette-and-food-db.md](estimation/myfoodrepo-bridge/tasks-palette-and-food-db.md)
- [tasks-specs-and-docs.md](estimation/myfoodrepo-bridge/tasks-specs-and-docs.md)
- [tasks-training-and-export.md](estimation/myfoodrepo-bridge/tasks-training-and-export.md)

## Support Plane Reference

The LiDAR support plane is fitted to the table rather than to the surface the food rests on — measured 26.1 mm too low — and because volume is integrated per-pixel above that plane, the offset is added to every food pixel and produces a 2–3.6× over-read that is proportionally largest on the flattest food (2 slices of bread weighed at 80 g read as 285.94 g; 208 g of rice read as 440 g). The current code faithfully implements the current specification, so this feature amends what the specification asks for: pipeline Req 4.2, pipeline design §6.2, the pipeline glossary and `DECISIONS.md` MD-9. Three things change — which samples compete (a millimetre-denominated annulus of 2 × `ringOuterMm` around the food mask, enumerated on the native 256×192 depth grid rather than the replicated colour grid), how a candidate is scored (largest 8-connected inlier component, amortised so the labelling cost cannot reproduce the earlier 32 GB allocation failure), and which candidate wins (a contact-ring admissibility filter over every candidate, scored on inner-band support with an angular sector guard as the straddle detector). Rejection routes to today's edge-band fit unchanged, so no capture that works today can fail. 25/27 tasks done: the geometry and selection phase — `MedataCore/Sources/SupportPlane/SupportRegion.swift` and 44 synthetic-scene tests — plus wiring and persistence: the fitter attempts the restricted fit first and falls back lazily to a byte-identical edge-band plane, the reference and ring measure are persisted on both paths, and the fallback carries a multiplicative σ_plane penalty. Harness parity then removed the divergence at its source: `FixtureRunner` no longer branches on the `estimator_path` stamp and calls `LiDARSupportPlaneFitter.fitFromDepth` — the device's own code — with the food mask derived from the segmenter's argmax, so Req 5.1 parity is structural rather than a convention (the flood fill survives, scoped to the mixture path, whose fixtures carry no segmentation output at all — Decision 17). The accuracy report gained the Req 4.4 fallback rate, segmented by reference and absent rather than zero when nothing was depth-derived, and the calibration artefact gained a per-class `support_plane_reference` with a fail-closed bake guard: an artefact recording none cannot bake, and a β fitted under another reference is left at unity and reported (Decisions 25–26). The regression-fixture phase then made three acceptance criteria executable off-device: `tools/fixture_slice.py` cuts a 290 KB depth-only slice from each 195 MB bundle (199 MB of which is the probability tensor the fit never reads), and measuring against the committed slices falsified three of the figures the spec stated — the pre-feature ring measure is +4.2 mm not +18…+26, the corrected volume 306.8 cm³ not 235.96, and Req 7.2's ~200 cm³ is unreachable by any plane because the mask covers ~298 cm² where the bread is ~200 (Decision 28). The two pre-feature volumes reproduce within 5 %, which is what says the slices are faithful. `PlateTopSupportPlaneTests` is un-skipped against the promoted path, the three prior plane-fit bugfixes are re-asserted on it, and Req 1.6's voxel-carve exposure measured to **zero** change in excluded voxels — the grid is anchored on the plane and translates with it, so it does not compound with the accepted overhang (Decision 27). The document amendments then landed as edits rather than cross-references, per Req 1.4: the π_sup glossary entry, pipeline Req 4.2 and design §6.2 now name the surface the food rests on and demote the edge-band scan to the fallback, `DECISIONS.md` MD-9 has its "table-plane prior" justification withdrawn in place and is superseded in part by the new MD-31, and the β_c transfer contract (`nutrition5k-calibration` Req 5.1) became two-part — masking **and** support-plane reference — closing the contradiction its own Req 3.6 already carried. The N5k rebase then ran (2026-08-05) and falsified the premise it was written on. Its cost had been booked as a segmenter pass over ~3,500 dishes; that cost belongs to `--checkpoint` ingestion, and this corpus is pre-checkpoint, so the whole regeneration took about four minutes. More consequentially, pre-checkpoint ingestion stamps every plate `mixture` — `run_summary.json` records `single_dominant: 0` — and mixture keeps the plate-region flood fill permanently (Decision 17), so `FixtureRunner.fitSupportPlane`, the branch task 16 promoted, is reached zero times on N5k. The promoted path gains corpus coverage only once model-production Bucket C lands and ingestion re-runs with `--checkpoint`, which also removes the cheap fallback-rate denominator Req 4.5 was expected to draw on. What the rebase does buy is the `support_plane_reference` stamp the Req 5.3 fail-closed guard demands: without it the bake aborts, so until it ran the corpus contributed no β at all. The numbers moved — 181 → 179 qualifying plates, broccoli β 0.516 → 0.495 — for a reason that is not the support plane: the stacking guard divides mapped mass by densities from the bundled DB, which was rebaked as food DB v2 in between. Every β stays `uncalibrated_unity`, because broccoli is the only calibrated class and Req 5.4 declines to apply a β fitted under `plateRegion`. Remaining: the corpus measurements Req 3.7 requires before the sector constants may be fixed, and the human-gated on-device weighed verify.

- [decision_log.md](estimation/support-plane-reference/decision_log.md)
- [design.md](estimation/support-plane-reference/design.md)
- [prerequisites.md](estimation/support-plane-reference/prerequisites.md)
- [requirements-notes.md](estimation/support-plane-reference/requirements-notes.md)
- [requirements.md](estimation/support-plane-reference/requirements.md)
- [tasks.md](estimation/support-plane-reference/tasks.md)

## Alternative Class Candidates

The segmenter computes a full class distribution for every pixel and the pipeline discards everything but the argmax, so the relabel shortlist meal-review ships can only be ordered by what the user chose before (recency). This spec retains per-detected-food alternative-class evidence on the meal record so the shortlist can offer a food the user has never chosen, with recency kept as a live component of the ordering rather than superseded — a record without candidate evidence yields exactly the shortlist meal-review would have produced, so no correction path can regress. Owed by meal-review Decision 18; measured against the recency prior alone via the corpus's `shortlist_source` partition, with the first-correction split as the measurement that matters most. Requirements and design approved 2026-08-10; the Decision 11 probe ran 2026-08-11 and closed the gate (Decision 13, `tools/candidate_probe.py`). Mean-over-region ships on evidence: the true class is in the top five on 78.2% of the segmenter's wrong regions against 68.6% for second-argmax share, and rank 1 agrees with the corpus prior only 15.7% of the time, so the early-exit condition was not met. The field bundles could not decide it — all five are single-food plates — so the verdict rests on a 200-plate validation leg, recorded as such. Boundary bleed is real and ships unmitigated (rank 1 touches the food 69.7% against a 9.1% chance floor; interior-only sampling measured and rejected), carried as a required adjacency partition of the Req 8 analysis, a conditional mitigation task, and the `docs/agent-notes/candidate-evidence.md` module note, rather than a footnote in a decision log. The conditional mitigation task closed 2026-08-12 without firing (Decision 14): the corpus holds zero relabels so its condition cannot be evaluated in a build session, and left pending it loops an autonomous runner — the condition now lives inside the acceptance-verdict gate, whose analysis reopens the repair if bleed measures as hurting. Three acceptance gates stay in a phase marked not agent-executable — Decision 5 gates closure on real use of the surface, so the verdict against recency cannot be reached in a build session and the ledger says so rather than implying otherwise. The analysis those gates read from now exists (`tools/shortlist_hit_rate.py`) and demonstrates the point rather than asserting it: run against every device pull it reports 8 correction rows, zero relabels and every cell empty, so the shape is fixed and the arithmetic exercised while the numbers wait on corrections nobody can manufacture.

- [decision_log.md](estimation/alternative-class-candidates/decision_log.md)
- [design.md](estimation/alternative-class-candidates/design.md)
- [requirements.md](estimation/alternative-class-candidates/requirements.md)
- [tasks.md](estimation/alternative-class-candidates/tasks.md)

## Rawframe Rgb Conversion

Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes.

- [decision_log.md](capture/rawframe-rgb-conversion/decision_log.md)
- [design.md](capture/rawframe-rgb-conversion/design.md)
- [requirements.md](capture/rawframe-rgb-conversion/requirements.md)
- [tasks.md](capture/rawframe-rgb-conversion/tasks.md)

## Capture Bundle Recorder

Record a harness-replayable `PbMealFixture` bundle per estimation attempt to `Documents/captures/` (Files-app visible, deletable), so any field capture — success, typed refusal, or non-typed error — replays offline through the existing Mac harness (`FixtureLoader.load` + `FixtureRunner.run`) with no harness changes. Developer-phase tooling: always on including Release (the research branch is pre-release), write-behind and failure-swallowing so recording never alters the estimation result, no in-app UI. All 5 tasks done — the on-device field-day pass closed 2026-08-11 (bundles for every attempt including refusals, stems joining outcome rows exactly, same-day pull + replay, stage timings unchanged), and the emptyFoodMask refusal recording landed the same day: `PbMealFixture` gains `pre_shutter_mask` plus its width and height (fields 27-29), written by `CaptureBundleRecorder.makeFixture` whenever a pre-shutter mask is present, so a refusal decided by the live preview segmenter is now replayable rather than unrecorded. Old bundles simply lack the field, so no loader change was needed.

- [decision_log.md](capture/capture-bundle-recorder/decision_log.md)
- [smolspec.md](capture/capture-bundle-recorder/smolspec.md)
- [tasks.md](capture/capture-bundle-recorder/tasks.md)

## Event Log Schema

Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata.

- [decision_log.md](data/event-log-schema/decision_log.md)
- [design.md](data/event-log-schema/design.md)
- [requirements.md](data/event-log-schema/requirements.md)
- [tasks.md](data/event-log-schema/tasks.md)

## Libre Ingestion

Extract glucose readings on-device from user-picked FreeStyle LibreLink screenshots (8-hour home view, 24-hour daily report) into `"bsl"` event rows (mmol/L): photo-picker import in Settings, Vision-OCR extraction ported verbatim from the imgdatacollector reference, keep-first merge with content-hash dedup, and the reference's 9-image ground-truth corpus committed as the `make test` accuracy gate (100% within ±0.3 mmol/L). The importer that feeds Design Handoff 00's Trends glucose series.

- [decision_log.md](data/libre-ingestion/decision_log.md)
- [design.md](data/libre-ingestion/design.md)
- [requirements.md](data/libre-ingestion/requirements.md)
- [tasks.md](data/libre-ingestion/tasks.md)

## iPhone Experience

v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. (Folder: `ui/iphone-experience/`; formerly the flat `ui/` spec.)

- [decision_log.md](ui/iphone-experience/decision_log.md)
- [design.md](ui/iphone-experience/design.md)
- [prerequisites.md](ui/iphone-experience/prerequisites.md)
- [requirements.md](ui/iphone-experience/requirements.md)
- [tasks.md](ui/iphone-experience/tasks.md)

## Shutter Blocked Feedback

Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped.

- [decision_log.md](ui/shutter-blocked-feedback/decision_log.md)
- [smolspec.md](ui/shutter-blocked-feedback/smolspec.md)
- [tasks.md](ui/shutter-blocked-feedback/tasks.md)

## Bubble-only Cleanup

Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the device-confirmed .bubble guide as the sole design.

- [decision_log.md](ui/bubble-only-cleanup/decision_log.md)
- [smolspec.md](ui/bubble-only-cleanup/smolspec.md)
- [tasks.md](ui/bubble-only-cleanup/tasks.md)

## Loading Symbol Animation

Reusable SwiftUI loader that draws the Medata mark stroke-by-stroke (bowl→bar→dot) with loop/once modes and a Reduce-Motion static fallback. All 6 tasks done — user verified the loader on device 2026-08-11; the call-site adoption (ldsym06) was found already landed via Design Handoff 00's estimating state plus seven further call sites.

- [decision_log.md](ui/loading-symbol-animation/decision_log.md)
- [smolspec.md](ui/loading-symbol-animation/smolspec.md)
- [tasks.md](ui/loading-symbol-animation/tasks.md)

## Design Handoff 00

Adopt the first external design handoff (archived wireframes + scaffold), amended in use (Decisions 19–21): the three-tab bar is gone — **Graph** (carbs charted against `bsl` glucose events; renamed from Trends everywhere in UI) is the launch root (Decision 20 — since superseded by home-router Decision 7, which makes HomeView the launch root), with Capture, Data, and Settings presenting as full-screen covers and the AR session running only while Capture is frontmost. Redesigned capture/result/data screens, Meal overview, mask-artefact persistence, a verbatim minimal-wording copy inventory (no reassurance/disclaimer copy — developer-phase rule, Req 14.5), and a numbered, versioned handoff archive under `design-system/wireframes/` with a 12-row deviations manifest. Supersedes parts of iPhone Experience per its §16 table. All 27 tasks done; on-device verification in prerequisites.md.

- [copy-inventory.md](ui/design-handoff-00/copy-inventory.md)
- [decision_log.md](ui/design-handoff-00/decision_log.md)
- [design.md](ui/design-handoff-00/design.md)
- [prerequisites.md](ui/design-handoff-00/prerequisites.md)
- [requirements.md](ui/design-handoff-00/requirements.md)
- [tasks.md](ui/design-handoff-00/tasks.md)

## Home Router

Home page becomes the launch root: no tab bar, six routed full-screen covers (Capture primary, plus Intake, Records, Graph, Settings, insulin), the deep-link handoff relocated to `AppRoot`, and `TrendsView` demoted to visualisation-only per the design's removal audit. Adds the unified Records timeline (meals + insulin + glucose most-recent-first; delete for manual entries only, glucose read-only — Req 3.5/Decision 5 since superseded by Records Deletion, which makes glucose deletable) and the `RecordRow.intake(IntakeRecord)` seam consumed by manual-carb-intake (Decisions 12–14). All 11 tasks done; the on-device visual verify (task 9) and the latest-glucose header STOP (task 11) both closed 2026-08-13 under the developer's device verdict.

- [decision_log.md](ui/home-router/decision_log.md)
- [design.md](ui/home-router/design.md)
- [requirements.md](ui/home-router/requirements.md)
- [tasks.md](ui/home-router/tasks.md)

## Records Deletion

The Records list becomes the primary deletion surface: swipe-delete on every row type — glucose rows lose their read-only rule (superseding home-router Req 3.5/Decision 5 via a bsl-gated `deleteBslEvent(id:)`) — plus edit-mode multi-select with Select All and a confirmed bulk delete, a From/To date-range purge with live in-range count, and a one-tap Delete All Records action. Store side: chunked single-transaction `deleteRecords(mealIDs:eventIDs:)` with one `eventsDidChange` notification per purge. Sourced from the 2026-07-26 Records-surface UX review (UI-IMPROVEMENTS.md, relocated here from `specs/general/`). All 5 tasks done; the 2026-08-11 device verify caught the delete-confirmation copy rendering its inflect markup literally, fixed same day with explicit pluralization.

- [UI-IMPROVEMENTS.md](ui/records-deletion/UI-IMPROVEMENTS.md)
- [decision_log.md](ui/records-deletion/decision_log.md)
- [smolspec.md](ui/records-deletion/smolspec.md)
- [tasks.md](ui/records-deletion/tasks.md)

## Mass Readout

Display-only mass readout: the estimated plate mass in grams shown beside the carb figure on the Result hero and Records rows, so field captures can be sanity-checked against scale truth. 3/4 tasks done — the ResultView hero and Records rows shipped with meal-review, the at-capture MealReviewView line landed 2026-08-10; the human-gated device look check (task 4) remains.

- [decision_log.md](ui/mass-readout/decision_log.md)
- [smolspec.md](ui/mass-readout/smolspec.md)
- [tasks.md](ui/mass-readout/tasks.md)

## Glucose Lock Screen Widget

A WidgetKit accessory widget added as a new data-driven kind inside the existing `MeDataWidgets` extension, surfacing the current/most-recent blood-glucose reading and a trend arrow on the Lock Screen and StandBy with a glance and no interaction beyond a tap to the Graph. The app publishes a versioned, atomically-written App Group snapshot (mmol/L value, timestamp, derived trend, target-band status) on `eventsDidChange` and reloads only the glucose kind; the widget reads solely from that snapshot (no GRDB/network in the extension). Trend is a pure `TrendsMath` function (least-squares slope over the last 15 min, guarded by a ≥10-min span), status is a non-colour glyph/token that survives the Lock Screen's monochrome vibrant rendering (colour only as a StandBy-day enhancement), and staleness is a pure render-point function (full ≤15 min → dimmed >15–30 → "last reading · Xh ago" >30, distinct from never-recorded) kept Foundation-only, with the WidgetKit `TimelineEntry`/reload-policy adaptation confined to the extension (Decision 12). Reuses the `bsl` stream from cgm-connect/libre-ingestion; no estimation-path code. 14 of 16 tasks done across the shared contract + pure logic, app integration, and widget-extension streams. The device pass (task 14) closed 2026-08-13 — renders and App Group round-trip fine — but surfaced the widget going stale whenever the app is suspended (StandBy-day colour unverifiable as a result); Decision 16 (accepted) answers it: the extension fetches LibreLinkUp itself in `getTimeline` under the shared 5-minute vendor budget (cgm-connect Decision 13), auth app-owned, database still the source of record — implementation ledgered as tasks 16.1–16.7. The trend-derivation tightening against observed CGM cadence (task 15) also remains, now more valuable with a true 5-minute feed.

- [decision_log.md](ui/glucose-lock-widget/decision_log.md)
- [design.md](ui/glucose-lock-widget/design.md)
- [prerequisites.md](ui/glucose-lock-widget/prerequisites.md)
- [requirements.md](ui/glucose-lock-widget/requirements.md)
- [tasks.md](ui/glucose-lock-widget/tasks.md)

## Meal Review

After a capture the estimate is split across two screens, and split exactly wrong: the segmentation review shows the photo with its detected foods but permits no editing, while the result screen permits amount editing but never shows the detected areas. This spec collapses both into one surface — detected foods outlined (not filled) on the photo with numbered badges as a non-colour identity channel, relabel and reject per food, serving/gram amounts and a whole-meal scale, and a single tap to record with no confirmation step. The deliverable is the corpus rather than the interface: one correction record per detected food per capture, the predicted side immutable beside a corrected side updated in place, each self-contained enough to read as a training example without the app, without the food database at the edition that produced it, and without the mask. Those records are the one store in the app exempt from every sweep, including the Debug reset — a discarded record is a regression that can no longer be run. Detected foods are keyed by class, not by blob, because the segmenter is semantic and produces no per-instance identity (Decision 10). The relabel shortlist ships recency-ordered; the candidate matrix that would order it by the model's own evidence is deferred to [Alternative Class Candidates](#alternative-class-candidates) (Decision 18), with `shortlist_source` on every record keeping the two orderings distinguishable in the corpus. All 22 tasks implemented (Decisions 19–20 recorded in flight; post-review hardening added a self-healing corpus upsert and a one-transaction whole-meal scale). The integration gate closed 2026-08-12: the SwiftPM core and the iOS app both build, the suite is green on both frameworks (572 XCTest, 3 skipped; 395 swift-testing in 48 suites), spell is clean, and the corpus's two durability guarantees are pinned in code and test — every mutation persists as it is made rather than at record(), and `deleteMeal`, `deleteRecords`, `deleteAllData` and the artefact sweep each exempt `correction_records`. The device sheet in prerequisites.md remains open as human-gated verification, outside the task ledger.

- [decision_log.md](ui/meal-review/decision_log.md)
- [design.md](ui/meal-review/design.md)
- [prerequisites.md](ui/meal-review/prerequisites.md)
- [requirements.md](ui/meal-review/requirements.md)
- [tasks.md](ui/meal-review/tasks.md)

## Regression Suggestion Integration

Insulin dosing joins meals and glucose as a first-class event stream, conforming byte-for-byte to medreg's `"insulin"` event convention so exported archives load in medreg unchanged. Dose-entry sheet from a syringe control on the Graph toolbar (two-tap default-bolus happy path, hold-to-repeat stepper, bolus/basal toggle, per-kind insulin-type Settings defaults), Graph dose markers/chip/stat card, `medata://insulin/add` and `medata://capture` deep links, and the `MeDataWidgets` extension with lock-/home-screen launcher widgets. PRD-lane spec (top-level folder, no domain directory); all 20 tasks across 3 contexts done.

- [prd.md](regression-suggestion-integration/prd.md)
- [tasks-app-ui.md](regression-suggestion-integration/tasks-app-ui.md)
- [tasks-core-events.md](regression-suggestion-integration/tasks-core-events.md)
- [tasks-lock-screen-widget.md](regression-suggestion-integration/tasks-lock-screen-widget.md)

## CGM Connect

Live glucose ingestion behind a source abstraction: connect once, readings flow into the event log as `bsl` events (mmol/L). Apple HealthKit is the primary on-device source (90-day backfill, background delivery with durable-ack anchor handling); a LibreLinkUp follower connection complements it for devices not yet writing to Health (on-device auth, Keychain credentials, uniform 5-minute poll — Decision 13, superseding Decision 12's adaptive scheme, which stays dormant in code as the rollback if the vendor rate-limits — plus BGAppRefreshTask). All sources snap to the shared 5-minute grid so keep-first dedup extends across screenshot import and live sources; the `GlucoseIngestion` module is excluded from every estimation target's dependency closure by an executable package-graph firewall test. 17/19 tasks done — the on-device verify (task 14) and the uniform-poll STOP (task 16, redefined for Decision 13) await the human loop.

- [decision_log.md](data/cgm-connect/decision_log.md)
- [design.md](data/cgm-connect/design.md)
- [prerequisites.md](data/cgm-connect/prerequisites.md)
- [requirements.md](data/cgm-connect/requirements.md)
- [tasks.md](data/cgm-connect/tasks.md)
- [userinput.md](data/cgm-connect/userinput.md)

## Manual Carb Intake

A direct manual carb-logging path alongside the photo pipeline: a carb-entry sheet modelled on the insulin-dose flow (numeric keypad, whole grams 1–999, back-dateable timestamp, optional protein/fat/fibre behind a disclosure — absent, never zero, when left empty) and one-tap quick-add presets (flat user-editable collection in the new `quick_presets` table, schema v5, seeded once with "A pint"/"Bagel"/"Chips"). Entries are `EventType.intake` events mirroring the insulin convention, distinguishable from photo meals, folded into the same Graph carb series and Records timeline, and editable/deletable inline from the Intake surface's recent-entries list. A manual entry can be saved as a new preset in one step. All 11 tasks done — the on-device verification checklist (design.md, Testing Strategy) awaits the human loop.

- [decision_log.md](data/manual-carb-intake/decision_log.md)
- [design.md](data/manual-carb-intake/design.md)
- [requirements.md](data/manual-carb-intake/requirements.md)
- [tasks.md](data/manual-carb-intake/tasks.md)

## Snaqui

SNAQ-inspired UI uplift, PRD-lane spec (top-level folder, no domain directory). The user states how much of the estimated plate they actually ate — a portion control on both result-screen presentations expressing N-of-M fractions and above-one multiples, persisted through the existing append-only `PbUserCorrection` mechanism so the original estimate is never overwritten and re-adjustment history is preserved. Closes the downstream gap where `TrendsModel` read raw `totalCarbsG`: Graph carb bars, Records rows, and Meal overview all show one corrected "eaten" number. Page chrome declutter: the seven full-screen pages drop their navigation titles (modal sheets keep theirs), and the Graph metric-chip row wraps onto a second line instead of truncating, with active chips coloured per series as the chart legend. The global "Ate N of M" portion stepper is since superseded by Serving Adjust's per-food serving rows (noted in the PRD); the correction persistence and corrected Graph totals remain in force. 7/8 tasks done; the on-device looks-right pass (task 8: portion ergonomics, portrait truncation, reclaimed band) is human-gated.

- [prd.md](snaqui/prd.md)
- [tasks-ios-app.md](snaqui/tasks-ios-app.md)

## Serving Adjust

PRD-lane spec (top-level folder, no domain directory). Reshape the snaqui portion control: move the less/more controls off the global "Ate 1 of 1" card and onto the per-ingredient rows, counting in each food's household serving unit ("spoons of peas", "number of potatoes") with grams as the secondary precise path, the hero carb total updating live and a one-tap plate-fraction control for the leftovers case. Serving units + gram weights are bundled data with per-row source citations (BDA Food Fact Sheet; Crawley, *Food Portion Sizes*) in a new solid-food servings table mirroring the existing `liquid_servings` precedent — tuneable without code. Two contexts: the food-database generator and the `App/` result surface; the estimation pipeline, segmenter, and volume/mass/β maths are untouched, and adjustments persist through the existing append-only `PbUserCorrection`. All 11 tasks done. Items 2 and 4 of the PRD's §iOS app — the global portion stepper and the confirm pill — are superseded by [Meal Review](#meal-review), recorded in its new decision log.

- [decision_log.md](serving-adjust/decision_log.md)
- [prd.md](serving-adjust/prd.md)
- [tasks-food-database-servings.md](serving-adjust/tasks-food-database-servings.md)
- [tasks-ios-app.md](serving-adjust/tasks-ios-app.md)

## Clean Build Baseline

Zero-warning baseline (top-level folder): eliminate the five compiler/validator warnings on the research branch — iPhone-only `TARGETED_DEVICE_FAMILY` (a product decision recorded in DECISIONS.md MD-23), a nonisolated reader, and the `UIScreen.main` deprecation — with the smallest viable changes. Relocated 2026-07-26 from `specs/bugfixes/` by the spec janitor: warning cleanup with product decisions, not a defect with a root cause. All 4 tasks done.

- [decision_log.md](clean-build-baseline/decision_log.md)
- [smolspec.md](clean-build-baseline/smolspec.md)
- [tasks.md](clean-build-baseline/tasks.md)
