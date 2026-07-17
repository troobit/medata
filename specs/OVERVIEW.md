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
| [Nutrition5k Calibration](#nutrition5k-calibration) | estimation | 2026-07-01 | Done | full | Bridge the Nutrition5k RGB-D dataset into the harness to fit per-class β bulk-correction factors, bake them into the food DB with lineage, report carb/protein/fat accuracy against a β=1.0 baseline, and add standalone-liquid classes to a redefined palette v1. All 45 tasks done (39 implementation + closeout consolidation); the post-checkpoint single-dominant re-fit stays gated on model-production Bucket C. |
| [Resumable Segmenter Training](#resumable-segmenter-training) | estimation | 2026-07-02 | Done | smol | Give `train.py` crash-safe per-epoch checkpointing and a `--resume` flag for interruptible local-Mac (MPS) training runs. |
| [Cross-dataset Calibration](#cross-dataset-calibration) | estimation | 2026-07-04 | Planned | full | Broaden per-class β calibration beyond Nutrition5k by rendering overhead depth from MetaFood3D single-food meshes and feeding them as single-class mixture rows to the existing harness, so carb staples gain samples N5k's mixed plates cannot. 23 tasks planned. |
| [Estimation Quality](#estimation-quality) | estimation | 2026-07-09 | In Progress | prd | Kill the mask speckle and stabilise carb readings: imbalance-aware `--loss`/`--photometric-augment` training flags (torch-free tested), deterministic connected-component speckle cleanup (default-on), plane-fit consensus polish + fail-closed food-coverage gate, and the segmenter-improvement research doc. 4 contexts landed; the training run, export/swap, and on-device verify remain human-gated STOP points. |
| [Segmenter Foundation](#segmenter-foundation) | estimation | 2026-07-10 | In Progress | full | Re-derive the segmenter bars (gate 0.60 → mean IoU ≥ 0.48, staple floors 0.50 → 0.45), upgrade the training recipe (stronger init + co-occurrence loss, stratified heldout re-cut) as the primary lever, and gate a SegFormer-B0 backbone swap on a Core ML conversion spike measured on the hardware floor. 19 of 22 tasks done — training chain executed with a NEGATIVE verdict (Decision 24): the co-occurrence recipe regressed the leak-free same-set mean 0.3776 → 0.3253 with four staple regressions, so `24e0b022241a` stays bundled; V2 init was separately rejected mid-run (Decision 23) and the floor re-based to the iPhone 16 Pro (Decision 22). Combined-loss fallback run in flight as a weighting-vs-co-term experiment; spike measurements (20–22, on the 16 Pro) remain human-gated. |
| [SNAQ Parity](#snaq-parity) | estimation | 2026-07-17 | Planned | full | Make estimation quality measurable against SNAQ's real-world figure (per-meal carb MAE ≤ ~13 g, completion rate always reported): an in-app weighed-meal benchmark with a paired-bootstrap promotion gate, a persistent on-device outcome/diagnostics store so "no volume" refusals carry causal measurements (pre/post-β volumes, skip counters, plane/scale/tilt), and the ranked model levers — segmenter tail profiling, a 4-candidate conversion bake-off via a shared `archs.py` registry, Recipe1M+-derived co-occurrence statistics, inverse-frequency weighting removed (Decision 25 enforced in code). Bounded cycle: complete on evidence-backed verdicts, not on hitting the target; seeds the MyFoodRepo-273 bridge if unmet. 24 tasks planned (two streams); training runs, device measurements, and promotion human-gated (prerequisites.md). |
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | capture | 2026-05-06 | Done | full | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Event Log Schema](#event-log-schema) | data | 2026-06-10 | Done | full | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |
| [Libre Ingestion](#libre-ingestion) | data | 2026-07-04 | Done | full | Extract glucose readings on-device from user-picked LibreLink screenshots into `bsl` events; Swift port of imgdatacollector gated by its 9-image accuracy corpus. |
| [iPhone Experience](#iphone-experience) | ui | 2026-05-22 | Done | full ·iterative | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. Visual design (Req 20) is iterative against [`design-system/`](../design-system/MASTER.md). |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | ui | 2026-05-31 | In Progress | smol | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. |
| [Bubble-only Cleanup](#bubble-only-cleanup) | ui | 2026-06-24 | Done | smol | Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the device-confirmed .bubble guide as the sole design. |
| [Loading Symbol Animation](#loading-symbol-animation) | ui | 2026-07-04 | In Progress | smol | Reusable SwiftUI loader that draws the Medata mark stroke-by-stroke (bowl→bar→dot); on-device verify and call-site adoption outstanding. |
| [Design Handoff 00](#design-handoff-00) | ui | 2026-07-04 | Done | full | Adopt the first external design handoff, amended in use: Graph (carbs vs glucose, renamed from Trends) is the launch root; Capture/Data/Settings present as full-screen covers; redesigned screens, Meal overview, minimal wording, no disclaimer copy (dev-phase rule), versioned handoff archive. All 27 tasks done + Decisions 19–21; device-verify checklist in prerequisites.md. |
| [Home Router](#home-router) | ui | 2026-07-07 | In Progress | full | Home page becomes the launch root (no tab bar): six routed full-screen covers with Capture primary, unified Records timeline (meals + insulin + glucose, delete for manual entries only), Graph demoted to visualisation-only. 8/9 tasks done; on-device visual verify (task 9) human-gated. |
| [Regression Suggestion Integration](#regression-suggestion-integration) | data · ui | 2026-07-05 | Done | prd | Insulin dosing as a first-class event stream conforming to medreg's insulin-event convention: dose-entry sheet from the Graph toolbar, Graph dose markers/stats, `medata://` deep links, and lock-/home-screen launcher widgets (`MeDataWidgets`). All 20 tasks across 3 contexts done. |
| [CGM Connect](#cgm-connect) | data | 2026-07-10 | In Progress | full | Live glucose ingestion behind a source abstraction (HealthKit primary, LibreLinkUp follower complement) writing `bsl` events with cross-source 5-minute-grid dedup, firewalled from estimation by a package-graph test. 13/14 tasks done; on-device verify (task 14) human-gated. |
| [Manual Carb Intake](#manual-carb-intake) | data · ui | 2026-07-07 | In Progress | full | Manual carb/macro logging without the camera: carb-entry sheet (keypad, 1–999 g, optional macros behind a disclosure), one-tap quick-add presets (`quick_presets` table, seeded defaults), inline edit/delete of manual entries, `EventType.intake` folded into the Graph carb series and Records timeline. All 11 tasks done; on-device verification checklist (design.md) human-gated. |
| [Snaqui](#snaqui) | ui · data | 2026-07-13 | In Progress | prd | SNAQ-inspired uplift: portion-adjustment control on the result screen (N-of-M fractions + multiples, persisted as append-only `PbUserCorrection`), Graph carb bars honour corrected totals, full-screen pages lose their redundant navigation titles, metric-chip row wraps instead of truncating. 7/8 tasks done; on-device looks-right pass (task 8) human-gated. |

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

Bridge Google Nutrition5k overhead RGB-D + per-ingredient gravimetric labels into the existing `.fixture`/`HarnessCLI calibrate` pipeline to fit per-class β bulk-correction factors (single-dominant + mixture BVLS paths), bake them into the food DB with lineage/provenance, report carb/protein/fat accuracy against a β=1.0 baseline, and add coarse standalone-liquid classes to the in-place-redefined palette v1. All 45 tasks done — the 39 implementation tasks including the pre-checkpoint end-to-end run (committed artifacts under [artifacts/](estimation/nutrition5k-calibration/artifacts/)) plus the closeout consolidation phase (tasks 40–45: worktree merges into `research`, index regeneration, branch cleanup, push; Decision 29). The post-checkpoint single-dominant re-fit + supersession re-run stays a documented manual step gated on model-production Bucket C.

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

PRD-lane work (engage): kill the visible mask speckle ("linear stripes of spots") and stabilise run-to-run carb readings. Landed across four contexts — the segmenter-improvement research doc attributing the 0.40-mIoU plateau to unweighted cross-entropy over the 35-class imbalance ([docs/agent-notes/segmenter-improvement-research.md](../docs/agent-notes/segmenter-improvement-research.md)); opt-in `--loss {weighted_ce,focal,dice,combined}` + `--photometric-augment` training flags with torch-free tests; deterministic connected-component speckle regularisation default-on in `PostProcessing.swift`; plane-fit consensus polish and a fail-closed food-coverage gate. The training run, model export/swap, and on-device verify are human-gated STOP points — the recommended run command is in [docs/ml-training.md](../docs/ml-training.md) §4.

- [prd.md](estimation/estimation-quality/prd.md)
- [tasks-estimation-runtime-consistency.md](estimation/estimation-quality/tasks-estimation-runtime-consistency.md)
- [tasks-mask-post-processing-cleanup.md](estimation/estimation-quality/tasks-mask-post-processing-cleanup.md)
- [tasks-segmentation-approach-research.md](estimation/estimation-quality/tasks-segmentation-approach-research.md)
- [tasks-segmenter-training-pipeline.md](estimation/estimation-quality/tasks-segmenter-training-pipeline.md)

## Segmenter Foundation

Decides the model foundation for the on-device segmenter, driven by the Track A deep-research findings ([docs/agent-notes/model-foundation-research.md](../docs/agent-notes/model-foundation-research.md)): the 0.60 heldout-mIoU gate sits above the FoodSeg103 compact-model frontier, so the bars are re-derived — mean IoU ≥ 0.48 (Decision 5) with 0.45 per-staple floors (Decision 14), uplift set anchored to the gate (Decision 18). The training-recipe upgrade on the existing DeepLabV3+MobileNetV3-Large is the primary lever (Decision 17 init survey + FoodSeg103-internal co-occurrence loss, Decision 15), measured against a stratified heldout re-cut (Req 2.6); a SegFormer-B0 backbone swap is explored only if a Core ML conversion spike passes size/latency/parity, latency measured directly on the hardware floor — re-based to the iPhone 16 Pro (Decisions 16/22); text-conditioning, SAM-family, and FoodSAM recorded as evaluated-and-rejected. 22 tasks: 19 done — the repo-wide 0.48/0.45 amendment pass, stratified heldout carve (`prepare_dataset.py`, `co_stats.v2` restricted to food channels, Decision 20), co-occurrence loss wiring, checkpoint survey, adapter probe and SegFormer spike code, and the executed re-cut + baseline re-measure (task 17, Decision 21: frozen seed 20260715; the full-heldout re-measure is train-contaminated so uplift anchors to a leak-free 182-image table; three staples have zero FoodSeg103 images, so their floors stay unprovable on this dataset). The adapter probe FAILED, settling Decision 19 on torchvision `IMAGENET1K_V2` via the new `train.py --init-checkpoint` — then that init was itself rejected on a 20-epoch trajectory comparison (Decision 23). Tasks 18–19 executed 2026-07-16 with a NEGATIVE verdict (Decision 24): the co-occurrence recipe lifted dead tail classes but regressed the leak-free same-set mean 0.3776 → 0.3253 with four staple regressions beyond tolerance, so nothing was exported and `24e0b022241a` stays bundled; a combined-loss fallback run is in flight to attribute the regression to the inverse-frequency weighting or the co-occurrence term. 19 of 22 tasks done; remaining: the 16 Pro spike measurements (20–22). The 2026-07-15 improvement survey ([docs/agent-notes/estimation-improvement-avenues.md](../docs/agent-notes/estimation-improvement-avenues.md)) seeds the next cycle.

- [decision_log.md](estimation/segmenter-foundation/decision_log.md)
- [design.md](estimation/segmenter-foundation/design.md)
- [prerequisites.md](estimation/segmenter-foundation/prerequisites.md)
- [requirements.md](estimation/segmenter-foundation/requirements.md)
- [tasks.md](estimation/segmenter-foundation/tasks.md)

## SNAQ Parity

Makes carb-estimation quality measurable against SNAQ's published real-world accuracy and every estimation attempt diagnosable: an in-app weighed-meal benchmark (ground truth from the bundled food DB, ≥ 20 meals including staple-floor foods, MAE never reported without completion rate, paired-bootstrap promotion gate), a persistent bounded outcome store capturing per-stage measurements on success and refusal alike, and the ranked improvement levers from the 2026-07-15 survey — upsample-tail profiling, an EfficientViT/SeaFormer/PP-MobileSeg conversion bake-off with the winner trained via a shared architecture registry, Recipe1M+-derived co-occurrence statistics, and code-level removal of the Decision 25 inverse-frequency weighting. Bounded cycle (Decision 5): done on recorded verdicts; the MyFoodRepo-273 dataset bridge is the named successor if the ≤ 13 g target is unmet.

- [decision_log.md](estimation/snaq-parity/decision_log.md)
- [design.md](estimation/snaq-parity/design.md)
- [prerequisites.md](estimation/snaq-parity/prerequisites.md)
- [requirements.md](estimation/snaq-parity/requirements.md)
- [tasks.md](estimation/snaq-parity/tasks.md)

## Rawframe Rgb Conversion

Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes.

- [decision_log.md](capture/rawframe-rgb-conversion/decision_log.md)
- [design.md](capture/rawframe-rgb-conversion/design.md)
- [requirements.md](capture/rawframe-rgb-conversion/requirements.md)
- [tasks.md](capture/rawframe-rgb-conversion/tasks.md)

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

Reusable SwiftUI loader that draws the Medata mark stroke-by-stroke (bowl→bar→dot) with loop/once modes and a Reduce-Motion static fallback; tasks 1–4 landed, on-device verify (ldsym05) and call-site adoption (ldsym06 — now absorbed by Design Handoff 00's estimating state) outstanding.

- [decision_log.md](ui/loading-symbol-animation/decision_log.md)
- [smolspec.md](ui/loading-symbol-animation/smolspec.md)
- [tasks.md](ui/loading-symbol-animation/tasks.md)

## Design Handoff 00

Adopt the first external design handoff (archived wireframes + scaffold), amended in use (Decisions 19–21): the three-tab bar is gone — **Graph** (carbs charted against `bsl` glucose events; renamed from Trends everywhere in UI) is the launch root, with Capture, Data, and Settings presenting as full-screen covers and the AR session running only while Capture is frontmost. Redesigned capture/result/data screens, Meal overview, mask-artefact persistence, a verbatim minimal-wording copy inventory (no reassurance/disclaimer copy — developer-phase rule, Req 14.5), and a numbered, versioned handoff archive under `design-system/wireframes/` with a 12-row deviations manifest. Supersedes parts of iPhone Experience per its §16 table. All 27 tasks done; on-device verification in prerequisites.md.

- [copy-inventory.md](ui/design-handoff-00/copy-inventory.md)
- [decision_log.md](ui/design-handoff-00/decision_log.md)
- [design.md](ui/design-handoff-00/design.md)
- [prerequisites.md](ui/design-handoff-00/prerequisites.md)
- [requirements.md](ui/design-handoff-00/requirements.md)
- [tasks.md](ui/design-handoff-00/tasks.md)

## Home Router

Home page becomes the launch root: no tab bar, six routed full-screen covers (Capture primary, plus Intake, Records, Graph, Settings, insulin), the deep-link handoff relocated to `AppRoot`, and `TrendsView` demoted to visualisation-only per the design's removal audit. Adds the unified Records timeline (meals + insulin + glucose most-recent-first; delete for manual entries only, glucose read-only) and the `RecordRow.intake(IntakeRecord)` seam consumed by manual-carb-intake (Decisions 12–14). 8/9 tasks done; on-device visual verify (task 9) is human-gated.

- [decision_log.md](ui/home-router/decision_log.md)
- [design.md](ui/home-router/design.md)
- [requirements.md](ui/home-router/requirements.md)
- [tasks.md](ui/home-router/tasks.md)

## Regression Suggestion Integration

Insulin dosing joins meals and glucose as a first-class event stream, conforming byte-for-byte to medreg's `"insulin"` event convention so exported archives load in medreg unchanged. Dose-entry sheet from a syringe control on the Graph toolbar (two-tap default-bolus happy path, hold-to-repeat stepper, bolus/basal toggle, per-kind insulin-type Settings defaults), Graph dose markers/chip/stat card, `medata://insulin/add` and `medata://capture` deep links, and the `MeDataWidgets` extension with lock-/home-screen launcher widgets. PRD-lane spec (top-level folder, no domain directory); all 20 tasks across 3 contexts done.

- [prd.md](regression-suggestion-integration/prd.md)
- [tasks-app-ui.md](regression-suggestion-integration/tasks-app-ui.md)
- [tasks-core-events.md](regression-suggestion-integration/tasks-core-events.md)
- [tasks-lock-screen-widget.md](regression-suggestion-integration/tasks-lock-screen-widget.md)

## CGM Connect

Live glucose ingestion behind a source abstraction: connect once, readings flow into the event log as `bsl` events (mmol/L). Apple HealthKit is the primary on-device source (90-day backfill, background delivery with durable-ack anchor handling); a LibreLinkUp follower connection complements it for devices not yet writing to Health (on-device auth, Keychain credentials, ≤15-minute poll + BGAppRefreshTask). All sources snap to the shared 5-minute grid so keep-first dedup extends across screenshot import and live sources; the `GlucoseIngestion` module is excluded from every estimation target's dependency closure by an executable package-graph firewall test. 13/14 tasks done — on-device verification (task 14) awaits the human loop.

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

SNAQ-inspired UI uplift, PRD-lane spec (top-level folder, no domain directory). The user states how much of the estimated plate they actually ate — a portion control on both result-screen presentations expressing N-of-M fractions and above-one multiples, persisted through the existing append-only `PbUserCorrection` mechanism so the original estimate is never overwritten and re-adjustment history is preserved. Closes the downstream gap where `TrendsModel` read raw `totalCarbsG`: Graph carb bars, Records rows, and Meal overview all show one corrected "eaten" number. Page chrome declutter: the seven full-screen pages drop their navigation titles (modal sheets keep theirs), and the Graph metric-chip row wraps onto a second line instead of truncating, with active chips coloured per series as the chart legend. 7/8 tasks done; the on-device looks-right pass (task 8: portion ergonomics, portrait truncation, reclaimed band) is human-gated.

- [prd.md](snaqui/prd.md)
- [tasks-ios-app.md](snaqui/tasks-ios-app.md)
