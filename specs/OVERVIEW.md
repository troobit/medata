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
| [Model Production](#model-production) | estimation | 2026-06-29 | Done | full | Train → Core ML export → bundle the on-device segmenter. All 13 code tasks done (Bundle.module loader, build lineage, modelVersion derivation, export.py gates, validation IoU + export-eligibility reporting, palette↔DB bake lock); producing the trained model itself is human/GPU/device-gated — see [prerequisites.md](estimation/model-production/prerequisites.md). |
| [Nutrition5k Calibration](#nutrition5k-calibration) | estimation | 2026-07-01 | In Progress | full | Bridge the Nutrition5k RGB-D dataset into the harness to fit per-class β bulk-correction factors, bake them into the food DB with lineage, report carb/protein/fat accuracy against a β=1.0 baseline, and add standalone-liquid classes to a redefined palette v1. |
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | capture | 2026-05-06 | Done | full | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Event Log Schema](#event-log-schema) | data | 2026-06-10 | Done | full | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |
| [iPhone Experience](#iphone-experience) | ui | 2026-05-22 | Done | full ·iterative | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. Visual design (Req 20) is iterative against [`design-system/`](../design-system/MASTER.md). |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | ui | 2026-05-31 | In Progress | smol | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. |
| [Bubble-only Cleanup](#bubble-only-cleanup) | ui | 2026-06-24 | Done | smol | Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the device-confirmed .bubble guide as the sole design. |

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

Train → Core ML export → bundle the on-device segmenter. All 13 implementable tasks are done — Bundle.module loader, build lineage manifest, modelVersion derivation, export.py equivalence/parity/channel/budget/metadata gates, validation mIoU + export-eligibility reporting, and the palette↔DB edition bake lock. What remains is human/data/hardware-gated and tracked as prerequisites, not tasks: acquire FoodSeg103, run the GPU training to the mIoU bar, run export.py on a Mac, and verify on-device (the MVP gate, Req 6.3). β_c gravimetric calibration is deferred past the MVP.

- [decision_log.md](estimation/model-production/decision_log.md)
- [design.md](estimation/model-production/design.md)
- [prerequisites.md](estimation/model-production/prerequisites.md)
- [requirements.md](estimation/model-production/requirements.md)
- [tasks.md](estimation/model-production/tasks.md)

## Nutrition5k Calibration

Bridge Google Nutrition5k overhead RGB-D + per-ingredient gravimetric labels into the existing `.fixture`/`HarnessCLI calibrate` pipeline to fit per-class β bulk-correction factors (single-dominant + mixture BVLS paths), bake them into the food DB with lineage/provenance, report carb/protein/fat accuracy against a β=1.0 baseline, and add coarse standalone-liquid classes to the in-place-redefined palette v1.

- [decision_log.md](estimation/nutrition5k-calibration/decision_log.md)
- [design.md](estimation/nutrition5k-calibration/design.md)
- [prerequisites.md](estimation/nutrition5k-calibration/prerequisites.md)
- [requirements.md](estimation/nutrition5k-calibration/requirements.md)
- [tasks.md](estimation/nutrition5k-calibration/tasks.md)

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
