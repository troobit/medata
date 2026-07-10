# Specs Overview

| Name | Creation Date | Status | Summary |
|------|---------------|--------|---------|
| [Bubble Only Cleanup](#bubble-only-cleanup) | 2026-06-24 | Done | Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the .bubble guide as sole design. |
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | 2026-06-25 | Done | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Event Log Schema](#event-log-schema) | 2026-06-25 | Done | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |
| [Lidar First Scale Fallback](#lidar-first-scale-fallback) | 2026-06-25 | Done | Make card-pose-solve failures non-fatal when LiDAR depth is present, falling back to LiDAR-only scale. |
| [Mv Volume Estimator](#mv-volume-estimator) | 2026-06-25 | No Tasks | Retired plan to decouple the dev-stub volume path from the per-class segmenter (superseded, no code). |
| [Pipeline Real Device Correctness](#pipeline-real-device-correctness) | 2026-06-25 | Done | Replace Phase-1 stop-gaps with a pre-shutter food-region mask, real coverage value, and Vision-backed CardDetector. |
| [Iphone Experience](#iphone-experience) | 2026-06-25 | Done | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | 2026-06-25 | In Progress | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. |
| [Pipeline](#pipeline) | 2026-06-27 | Done | Low-compute on-device system estimating carbohydrate content from one or two iPhone photos. |
| [Model Production](#model-production) | 2026-06-29 | Done | Repeatable process from documented recipe to a trained segmenter.mlpackage bundled in the iOS app. |
| [Nutrition5k Calibration](#nutrition5k-calibration) | 2026-07-02 | Done | Derive per-class β bulk-correction factors from Nutrition5k gravimetric ground truth, baked into the food database. |
| [Resumable Segmenter Training](#resumable-segmenter-training) | 2026-07-02 | Done | Give train.py crash-safe per-epoch checkpointing and a --resume flag for interruptible local-Mac training runs. |
| [Cross Dataset Calibration](#cross-dataset-calibration) | 2026-07-04 | Planned | Broaden per-class β calibration by ingesting MetaFood3D single-food captures into the existing calibration harness. |
| [Loading Symbol Animation](#loading-symbol-animation) | 2026-07-04 | In Progress | Reusable SwiftUI loader that draws the Medata brand mark stroke-by-stroke as an indeterminate spinner. |
| [Design Handoff 00](#design-handoff-00) | 2026-07-04 | Done | Adopt the first external design handoff: redesigned capture/result screens, Graph and Meal overview, versioned archive. |
| [Libre Ingestion](#libre-ingestion) | 2026-07-04 | Done | Extract glucose readings on-device from user-picked LibreLink screenshots into bsl events in the event log. |
| [Regression Suggestion Integration](#regression-suggestion-integration) | 2026-07-05 | Done | Insulin dosing as a first-class event stream conforming to medreg's insulin-event convention. |
| [Home Router](#home-router) | 2026-07-07 | In Progress | New home page as launch root routing to all surfaces, demoting Graph to visualisation only. |
| [Manual Carb Intake](#manual-carb-intake) | 2026-07-08 | No Tasks | Direct manual carb intake: entry sheet and one-tap quick-add presets writing straight to the ledger. |
| [Estimation Quality](#estimation-quality) | 2026-07-09 | In Progress | Kill mask speckle and stabilise carb readings: imbalance-aware training recipe, mask cleanup, variance reduction. |
| [Cgm Connect](#cgm-connect) | 2026-07-10 | In Progress | Connect a continuous glucose source once and have readings flow into MeData as bsl events. |
| [Segmenter Foundation](#segmenter-foundation) | 2026-07-10 | Planned | Decide the segmenter's model foundation: re-derived accuracy gate, training recipe, and backbone choice. |

---

## Bubble Only Cleanup

Remove the unused .gauge/.dial tilt-guide designs and selector, leaving the .bubble guide as sole design.

- [decision_log.md](ui/bubble-only-cleanup/decision_log.md)
- [smolspec.md](ui/bubble-only-cleanup/smolspec.md)
- [tasks.md](ui/bubble-only-cleanup/tasks.md)

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

## Lidar First Scale Fallback

Make card-pose-solve failures non-fatal when LiDAR depth is present, falling back to LiDAR-only scale.

- [decision_log.md](estimation/lidar-first-scale-fallback/decision_log.md)
- [smolspec.md](estimation/lidar-first-scale-fallback/smolspec.md)
- [tasks.md](estimation/lidar-first-scale-fallback/tasks.md)

## Mv Volume Estimator

Retired plan to decouple the dev-stub volume path from the per-class segmenter (superseded, no code).

- [decision_log.md](estimation/mv-volume-estimator/decision_log.md)
- [smolspec.md](estimation/mv-volume-estimator/smolspec.md)

## Pipeline Real Device Correctness

Replace Phase-1 stop-gaps with a pre-shutter food-region mask, real coverage value, and Vision-backed CardDetector.

- [decision_log.md](estimation/pipeline-real-device-correctness/decision_log.md)
- [design.md](estimation/pipeline-real-device-correctness/design.md)
- [prerequisites.md](estimation/pipeline-real-device-correctness/prerequisites.md)
- [requirements.md](estimation/pipeline-real-device-correctness/requirements.md)
- [tasks.md](estimation/pipeline-real-device-correctness/tasks.md)

## Iphone Experience

v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings.

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

## Pipeline

Low-compute on-device system estimating carbohydrate content from one or two iPhone photos.

- [decision_log.md](estimation/pipeline/decision_log.md)
- [design.md](estimation/pipeline/design.md)
- [prerequisites.md](estimation/pipeline/prerequisites.md)
- [requirements.md](estimation/pipeline/requirements.md)
- [tasks.md](estimation/pipeline/tasks.md)

## Model Production

Repeatable process from documented recipe to a trained segmenter.mlpackage bundled in the iOS app.

- [decision_log.md](estimation/model-production/decision_log.md)
- [design.md](estimation/model-production/design.md)
- [prerequisites.md](estimation/model-production/prerequisites.md)
- [requirements.md](estimation/model-production/requirements.md)
- [tasks.md](estimation/model-production/tasks.md)

## Nutrition5k Calibration

Derive per-class β bulk-correction factors from Nutrition5k gravimetric ground truth, baked into the food database.

- [decision_log.md](estimation/nutrition5k-calibration/decision_log.md)
- [design.md](estimation/nutrition5k-calibration/design.md)
- [prerequisites.md](estimation/nutrition5k-calibration/prerequisites.md)
- [requirements.md](estimation/nutrition5k-calibration/requirements.md)
- [tasks.md](estimation/nutrition5k-calibration/tasks.md)

## Resumable Segmenter Training

Give train.py crash-safe per-epoch checkpointing and a --resume flag for interruptible local-Mac training runs.

- [decision_log.md](estimation/resumable-segmenter-training/decision_log.md)
- [smolspec.md](estimation/resumable-segmenter-training/smolspec.md)
- [tasks.md](estimation/resumable-segmenter-training/tasks.md)

## Cross Dataset Calibration

Broaden per-class β calibration by ingesting MetaFood3D single-food captures into the existing calibration harness.

- [decision_log.md](estimation/cross-dataset-calibration/decision_log.md)
- [design.md](estimation/cross-dataset-calibration/design.md)
- [requirements.md](estimation/cross-dataset-calibration/requirements.md)
- [tasks.md](estimation/cross-dataset-calibration/tasks.md)

## Loading Symbol Animation

Reusable SwiftUI loader that draws the Medata brand mark stroke-by-stroke as an indeterminate spinner.

- [decision_log.md](ui/loading-symbol-animation/decision_log.md)
- [smolspec.md](ui/loading-symbol-animation/smolspec.md)
- [tasks.md](ui/loading-symbol-animation/tasks.md)

## Design Handoff 00

Adopt the first external design handoff: redesigned capture/result screens, Graph and Meal overview, versioned archive.

- [copy-inventory.md](ui/design-handoff-00/copy-inventory.md)
- [decision_log.md](ui/design-handoff-00/decision_log.md)
- [design.md](ui/design-handoff-00/design.md)
- [prerequisites.md](ui/design-handoff-00/prerequisites.md)
- [requirements.md](ui/design-handoff-00/requirements.md)
- [tasks.md](ui/design-handoff-00/tasks.md)

## Libre Ingestion

Extract glucose readings on-device from user-picked LibreLink screenshots into bsl events in the event log.

- [decision_log.md](data/libre-ingestion/decision_log.md)
- [design.md](data/libre-ingestion/design.md)
- [requirements.md](data/libre-ingestion/requirements.md)
- [tasks.md](data/libre-ingestion/tasks.md)

## Regression Suggestion Integration

Insulin dosing as a first-class event stream conforming to medreg's insulin-event convention.

- [prd.md](regression-suggestion-integration/prd.md)
- [tasks-app-ui.md](regression-suggestion-integration/tasks-app-ui.md)
- [tasks-core-events.md](regression-suggestion-integration/tasks-core-events.md)
- [tasks-lock-screen-widget.md](regression-suggestion-integration/tasks-lock-screen-widget.md)

## Home Router

New home page as launch root routing to all surfaces, demoting Graph to visualisation only.

- [decision_log.md](ui/home-router/decision_log.md)
- [design.md](ui/home-router/design.md)
- [requirements.md](ui/home-router/requirements.md)
- [tasks.md](ui/home-router/tasks.md)

## Manual Carb Intake

Direct manual carb intake: entry sheet and one-tap quick-add presets writing straight to the ledger.

- [decision_log.md](data/manual-carb-intake/decision_log.md)
- [requirements.md](data/manual-carb-intake/requirements.md)

## Estimation Quality

Kill mask speckle and stabilise carb readings: imbalance-aware training recipe, mask cleanup, variance reduction.

- [prd.md](estimation/estimation-quality/prd.md)
- [tasks-estimation-runtime-consistency.md](estimation/estimation-quality/tasks-estimation-runtime-consistency.md)
- [tasks-mask-post-processing-cleanup.md](estimation/estimation-quality/tasks-mask-post-processing-cleanup.md)
- [tasks-segmentation-approach-research.md](estimation/estimation-quality/tasks-segmentation-approach-research.md)
- [tasks-segmenter-training-pipeline.md](estimation/estimation-quality/tasks-segmenter-training-pipeline.md)

## Cgm Connect

Connect a continuous glucose source once and have readings flow into MeData as bsl events.

- [decision_log.md](data/cgm-connect/decision_log.md)
- [design.md](data/cgm-connect/design.md)
- [prerequisites.md](data/cgm-connect/prerequisites.md)
- [requirements.md](data/cgm-connect/requirements.md)
- [tasks.md](data/cgm-connect/tasks.md)
- [userinput.md](data/cgm-connect/userinput.md)

## Segmenter Foundation

Decide the segmenter's model foundation: re-derived accuracy gate, training recipe, and backbone choice.

- [decision_log.md](estimation/segmenter-foundation/decision_log.md)
- [design.md](estimation/segmenter-foundation/design.md)
- [requirements.md](estimation/segmenter-foundation/requirements.md)
- [tasks.md](estimation/segmenter-foundation/tasks.md)
