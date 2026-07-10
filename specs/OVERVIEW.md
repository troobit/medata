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
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | capture | 2026-05-06 | Done | full | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Event Log Schema](#event-log-schema) | data | 2026-06-10 | Done | full | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |
| [Libre Ingestion](#libre-ingestion) | data | 2026-07-04 | Done | full | Extract glucose readings on-device from user-picked LibreLink screenshots into `bsl` events; Swift port of imgdatacollector gated by its 9-image accuracy corpus. |
| [iPhone Experience](#iphone-experience) | ui | 2026-05-22 | Done | full ·iterative | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. Visual design (Req 20) is iterative against [`design-system/`](../design-system/MASTER.md). |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | ui | 2026-05-31 | In Progress | smol | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. |
| [Bubble-only Cleanup](#bubble-only-cleanup) | ui | 2026-06-24 | Done | smol | Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the device-confirmed .bubble guide as the sole design. |
| [Loading Symbol Animation](#loading-symbol-animation) | ui | 2026-07-04 | In Progress | smol | Reusable SwiftUI loader that draws the Medata mark stroke-by-stroke (bowl→bar→dot); on-device verify and call-site adoption outstanding. |
| [Design Handoff 00](#design-handoff-00) | ui | 2026-07-04 | Done | full | Adopt the first external design handoff, amended in use: Graph (carbs vs glucose, renamed from Trends) is the launch root; Capture/Data/Settings present as full-screen covers; redesigned screens, Meal overview, minimal wording, no disclaimer copy (dev-phase rule), versioned handoff archive. All 27 tasks done + Decisions 19–21; device-verify checklist in prerequisites.md. |
| [Regression Suggestion Integration](#regression-suggestion-integration) | data · ui | 2026-07-05 | Done | prd | Insulin dosing as a first-class event stream conforming to medreg's insulin-event convention: dose-entry sheet from the Graph toolbar, Graph dose markers/stats, `medata://` deep links, and lock-/home-screen launcher widgets (`MeDataWidgets`). All 20 tasks across 3 contexts done. |
| [CGM Connect](#cgm-connect) | data | 2026-07-10 | In Progress | full | Live glucose ingestion behind a source abstraction (HealthKit primary, LibreLinkUp follower complement) writing `bsl` events with cross-source 5-minute-grid dedup, firewalled from estimation by a package-graph test. 13/14 tasks done; on-device verify (task 14) human-gated. |

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
