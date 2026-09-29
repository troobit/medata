# Handoff: Medata — food-photo carb estimation app

## Overview
Medata is an iOS app that estimates the carbohydrate content of a meal from
one or two photographs. It uses on-device geometry (LiDAR depth or two-view
shape-from-silhouette) plus food segmentation to compute per-food volume,
mass, and carbs, and presents a confidence-scored result. Historical data is
graphed as carbs over time alongside blood-glucose readings imported
(read-only) from an external CGM/meter.

This bundle contains **two artifacts**:

1. `wireframes/` — HTML wireframes (design reference)
2. `MedataApp/` — a SwiftUI scaffold that already implements the wireframes
   as navigable screens with protocol stubs for the pipeline

## About the Design Files
The files in `wireframes/` are **design references created in HTML** — they
show intended layout, flow, and behavior. They are NOT production code.

The **SwiftUI scaffold in `MedataApp/` is the intended implementation
starting point.** If the target codebase is this Swift project, extend it
in place. Camera, ARKit/LiDAR, segmentation, and persistence are
deliberately stubbed behind protocols (see "State Management & Stubs").

## Fidelity
**Low-fidelity wireframes.** Grayscale + two accents. Use them for layout,
flow, copy, and state logic — not for final visual styling. The SwiftUI
scaffold intentionally re-interprets them with native iOS chrome (SF
Symbols, system colors, Form/NavigationStack idioms); follow that
direction, not the hand-drawn look.

## Screens / Views

### 1. Capture (selected variant: "Sequential · telemetry + bubble level")
- Full-bleed camera viewfinder (placeholder backdrop in scaffold —
  real app hosts `AVCaptureVideoPreviewLayer` / `ARView` behind the overlay).
- **No conversational copy.** Chrome is data only:
  - Mode capsule top-center: `1-VIEW · LiDAR` / `2-VIEW · NADIR` (monospaced).
  - Bubble level top-right: green centered bubble within ±5° of flat,
    amber + drifted when off (drive from CoreMotion in production).
  - Telemetry capsule above shutter: `tilt 1.8° · dist 34 cm · LiDAR ●`
    (monospaced, LiDAR dot green when depth available).
- Bottom row: mode button (tap toggles 1-view/2-view; long-press opens the
  capture-path fork sheet), shutter, settings.
- Swift file: `Views/Capture/CaptureView.swift`

### 2. Result (selected variant: "Single-number hero")
- Hero: carb total rounded to 1 g (req §12.4), 80pt light, "g carbs" suffix.
- Confidence chip below hero (High ≥0.8 / Moderate 0.6–0.8 / Low <0.6;
  green / neutral / amber; meal confidence = geometric mean of
  scale × segmentation × geometric sub-confidences).
- Summary card: photo thumbnail, "N foods recognised", total mass, DB edition.
- Per-class breakdown rows: name, mass g, volume cm³, carbs g, per-class σ.
- **Future macros**: dashed "Protein — soon" and "Fat — soon" capsules
  reserved in the layout so nothing shifts when they land.
- Actions: "Adjust manually" (bordered) then "Save to history" (prominent).
- Swift file: `Views/Result/ResultView.swift`

### 3. Trends (historical graphs) — NEW
- Segmented range picker: Day / Week / Month.
- **Day view**: dual-series chart —
  - Blood glucose: amber line, mmol/L, left axis, 15-min mock CGM samples.
  - Carbs: gray bars at meal timestamps, g, right axis (0–80 g).
  - Green translucent band = target range 3.9–10.0 mmol/L.
  - Swift Charts has one y-scale per chart, so carbs are mapped into the
    glucose domain and the trailing axis is relabelled in grams — see
    `TrendsView.dayChart`.
- **Week view**: bars = total carbs/day, line = avg glucose/day.
- Metric chips under chart: Carbs ✓ / Glucose ✓ toggle inclusion;
  Protein and Fat are dashed + disabled (future).
- Summary stat cards: Total (or avg) carbs, Time in range %, Avg glucose.
- Day view lists that day's meals below the chart; each row navigates to
  its Result screen.
- Footer note: "Glucose data imported from CGM — read-only. Medata never
  writes to your glucose device."
- **Graph options sheet** (slider icon in nav bar):
  - Metric toggles with source captions ("bars · from meal captures",
    "line · from CGM / meter import"), target-band toggle.
  - Protein · Fat row present but disabled ("coming later").
  - Scale: Auto / Fixed segmented control; Fixed reveals a stepper
    (8–25 mmol/L max).
- Swift files: `Views/Trends/TrendsView.swift`,
  `Views/Trends/TrendsOptionsSheet.swift`, `Models/GlucoseReading.swift`

### 4. LiDAR vs no-LiDAR fork
- Sheet offering "Quick (1 photo)" (recommended, LiDAR) vs
  "Two-view (canonical)". Optional ID-1 reference-card toggle
  ("any bank card improves scale confidence").
- Swift file: `Views/Capture/LidarForkSheet.swift`

### 5. Segmentation review
- Captured photo with per-class mask overlays; class list with confidence
  chips; amber banner for unknown regions ("unknown carbs") and unsupported
  liquids. CTA: "Estimate carbs".
- Swift file: `Views/Review/SegmentationReviewView.swift`

### 6. Capture error (tilt off)
- Soft failure: amber ghost outline + "too tilted" chip, plain-language fix
  ("Top-down view needs ±5° of vertical"), escape hatches: "Skip to 2-view"
  / Cancel.
- Swift file: `Views/Capture/CaptureErrorView.swift`

### 7. Manual correction
- Total-carbs stepper + per-food values. Original estimate is never
  overwritten — corrections stored alongside (req §14). Optional note field.
- Swift file: `Views/Correction/ManualCorrectionView.swift`

### 8. Data (meal log)
- Renamed from "History". Meals grouped by day; rows are **anonymous** — no
  meal names like "Lunch": thumbnail, time, carbs g, confidence chip only.
- Row → **Meal overview** (below), not straight to Result.
- Swift file: `Views/History/DataView.swift`

### 8b. Meal overview
- Middle ground between Result and Segmentation review, reached from Data:
  captured photo with masks overlaid, compact carb total (40pt) +
  confidence chip, capture metadata line, per-class rows with mask
  swatches (mass, volume, carbs, σ), "user-corrected" marker when present.
- Actions: "Adjust" (bordered → Correction) and "Full result"
  (prominent → Result). Delete via ⋯ menu.
- Swift file: `Views/History/MealOverviewView.swift`

### 9. Settings
- "Account" row present but **disabled/greyed** (placeholder for future
  sign-in; no auth in v1).
- Photo retention (keep-for duration, delete-all), food database
  (CoFID 2024 active, IFCDB 2023 overlay toggle), capture defaults
  (single-view default, always-include-card toggle), About.
- Swift file: `Views/Settings/SettingsView.swift`

### 10. About / Legal
- CoFID attribution (Crown Copyright, Open Government Licence v3 — required),
  IFCDB note, method summary, "Not a medical device", privacy (all
  processing on-device).
- Swift file: `Views/Settings/AboutView.swift`

## Interactions & Behavior
- Navigation: single `NavigationStack` rooted on Capture. History, Settings,
  and Trends present as sheets. Typed routes in `Route` enum
  (`App/MedataApp.swift`).
- Capture → (estimate) → Segmentation review → Result → optional Correction.
- Graceful validation: capture errors are inline, plain-language, and always
  offer an escape hatch (retry / skip to two-view / cancel). Never a dead end.
- No sign-in anywhere; Account row disabled in Settings.

## State Management & Stubs
Protocol boundaries other devs plug into (all in `MedataApp/`):
- `CaptureService` (`Pipeline/CaptureService.swift`) — camera frames;
  mock returns canned frames.
- `LidarService` (`Pipeline/LidarService.swift`) — depth availability/maps.
- `EstimationPipeline` (`Pipeline/EstimationPipeline.swift`,
  `Pipeline/Pipeline.swift`) — segmentation → volume → mass → carbs;
  mock returns sample meals.
- `MealStore` (`Models/MealStore.swift`) — persistence;
  `InMemoryMealStore.seeded()` for the wireframe, SQLite planned.
- `GlucoseSource` (`Models/GlucoseReading.swift`) — read-only glucose
  import; `MockGlucoseSource` synthesizes a plausible daily curve.
  Production wraps HealthKit / vendor SDK.
- `AppEnvironment` (`App/AppEnvironment.swift`) — DI container.

## Design Tokens (wireframe palette; scaffold maps to system colors)
- Ink #1a1a1a · ink-2 #4a4a4a · ink-3 #8a8a8a · ink-4 #c4c4c4
- Paper #fafaf7 · elevated #f0eee9
- Success (green) #2d8b5f — in-range, high confidence, "plate detected"
- Warning (amber) #c97a1f — low confidence, capture errors, glucose series
- SwiftUI tokens: `Models/DesignSystem.swift` (`DS` enum)
- Confidence thresholds: high ≥ 0.8, moderate 0.6–0.8, low < 0.6
- Carb display rounding: nearest 1 g

## Assets
None — all imagery is placeholder (striped blocks / SVG plates). Real food
photos come from the camera at runtime.

## Files
- `wireframes/Medata Wireframes v2.html` — current canvas (selected flow +
  Trends). Open in a browser.
- `wireframes/Medata Wireframes.html` — v1 with all 3 capture and 3 result
  variations (context for decisions).
- `wireframes/screens/*.jsx`, `wireframes/styles/wireframe.css` — wireframe
  source components.
- `MedataApp/**/*.swift` — SwiftUI scaffold (iOS 17+, Swift Charts).
  Drop into an Xcode iOS App project (delete the template's App/ContentView
  first; `MedataApp.swift` holds the only `@main`).

## Functional requirements source
https://github.com/troobit/medata/blob/research/specs/research/requirements.md
(section numbers cited above, e.g. §3.5 single-view shortcut, §12.4 rounding,
§13 confidence, §14 corrections, §15 persistence).
