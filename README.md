# MeData

A native iOS app that estimates the carbohydrate content of a meal from one or two
photographs using **on-device** computer vision — deterministic geometry, an on-device
food segmenter, a bundled food-composition database, and offline-calibrated per-class
correction factors. No LLM, no network call in the estimation path.

Spec hardware floor: iPhone 13 Pro Max. OS floor: iOS 26.5. The engine relaxes the
LiDAR requirement at runtime — non-LiDAR devices fall through to the two-view + ID-1
card path with `noLidarConfidence` set on every meal — but the calibration and
performance targets are measured on iPhone 13 Pro Max (`specs/estimation/pipeline/requirements.md`
Req 1.2, [`docs/ios-device-setup.md`](docs/ios-device-setup.md) device matrix).

```
photo(s) → silhouettes → visual hull → V_c (volume per class)
        → m_c = V_c · ρ_c → C = Σ m_c · κ_c / 100
```

## Delivery phases (and what works today)

V1 ships in three ordered phases (`specs/estimation/pipeline/requirements.md` §0). Numeric
accuracy and segmenter-quality targets gate **Phase 3 only**; earlier phases are
sign-off-able with a development stub in the segmenter slot.

| Phase | Status | What it means in practice |
|---|---|---|
| **Phase 1 — running on device** | **current** | The full capture-flow + pipeline runs end-to-end on iPhone 13 Pro Max. The segmenter is a development stub (a centred ellipse food mask, per `specs/estimation/pipeline/requirements.md` §23) so the geometry, gating, persistence and refusal paths are real but carb numbers are placeholders. |
| Phase 2 — UI/UX iteration | not started | Capture-flow polish, gating affordances, result view, history and settings, refined against real-device usage. Still on the dev-stub segmenter. |
| Phase 3 — data veracity & modelling | not started | The trained Core ML segmenter ships, β_c calibration runs offline (`specs/estimation/pipeline/requirements.md` §11.7), and end-to-end MAPE/MAE bars (§21.3) are measured. |

### Why the fruit-plate MVP

The on-device test scene is a **plate of fruit** for two reasons:

1. **Geometry is friendly.** Mostly-convex items sitting flat on the support plane are
   the cleanest input to the LiDAR plane fit + voxel carve / height-field integration.
2. **Phase 1 segmenter is a stub.** The dev-stub emits a centred ellipse regardless of
   pixel content, so a fruit plate isn't strictly required for Phase 1 sign-off — but it
   keeps the visual debugging honest and the geometric inputs realistic.

In principle the pipeline is food-agnostic at the geometry layer (volume → mass → carbs
is just numbers). In practice generalisation beyond fruit is gated on two trained
components landing in Phase 3: the `ClassPalette` of food classes the segmenter
recognises, and the `Foods` density / carbs-per-gram look-up. Until both cover a
broader food set, mixed savoury dishes will segment poorly and density estimates will
fall back to defaults.

## Repo layout

```
medata/
├── App/                       SwiftUI iOS shell — the capture flow
├── MedataCore/                SwiftPM library — platform-neutral pipeline
│   ├── Sources/
│   │   ├── PortableContracts/   protobuf wire types + Vec3/Mat4 (shared by all)
│   │   ├── CaptureKit/          AVFoundation / ARKit / Core Motion bridge
│   │   ├── CardDetection/       ID-1 card detect + P4P pose
│   │   ├── SupportPlane/        RANSAC plane (LiDAR) / iterative card-only fit
│   │   ├── MetricScale/         mm-per-pixel resolver
│   │   ├── Segmentation/        Core ML wrapper + pre/post-process
│   │   ├── Volume/              Metal voxel-carve / height-field integration
│   │   ├── Foods/               CoFID + AFCD food-composition DB (cofid_db + afcd_db)
│   │   ├── Macros/              mass → carbs per class
│   │   ├── Confidence/          σ_meal combination
│   │   ├── Persistence/         SQLite meal records, artefacts, retention, export
│   │   └── Pipeline/            façade orchestrating the stage graph
│   └── Tests/                 per-module XCTest targets
│       (bundled resources sit beside their modules: Foods/Resources holds the
│        committed cofid_db.sqlite + afcd_db.sqlite; Pipeline/Resources holds the
│        gitignored, generated segmenter.mlpackage)
├── HarnessCore/               offline accuracy / β-calibration library
├── HarnessCLI/                macOS executable driving HarnessCore
├── MeData/                    Xcode project — iOS app target
│   ├── MeData.xcodeproj/        references ../App/*.swift and ../Package.swift
│   ├── Tests/                   Swift Testing unit tests (not wired in by default)
│   └── UITests/                 XCUITests for the capture flow
├── specs/                     Per-feature requirements / design / decisions / tasks
│   ├── estimation/              the on-device carb-estimation pipeline (+ volume, scale)
│   └── ui/                      the SwiftUI capture-flow shell
├── docs/                      Architecture overview, device setup, agent notes
├── tools/                     dev/CI scripts (segmenter export, food DB, appicon, linters)
├── static/                    brand source assets (icon.svg, favicons)
├── Package.swift              SwiftPM manifest — single source of truth for modules
└── CHANGELOG.md
```

The Xcode app project and the SwiftPM package coexist in one repo. The app depends on
the package via a local reference; the package never depends on the app. See
[`docs/architecture.md`](docs/architecture.md) §2 for the rationale.

## Documentation

Read in this order if you're new to the project:

| Document | When to read it |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | **Start here.** Layers, modules, abstractions, and Swift / SwiftUI conventions. The map to everything else. |
| [`docs/ios-device-setup.md`](docs/ios-device-setup.md) | Building, signing, and side-loading to iPhone 13 Pro Max (or any LiDAR-equipped device). |
| [`docs/README.md`](docs/README.md) | Index of all docs and how they relate to the specs. |
| [`docs/agent-notes/`](docs/agent-notes/) | Module-level implementation notes and gotchas — read the relevant one before working in a module. |
| [`specs/OVERVIEW.md`](specs/OVERVIEW.md) | **The spec index** — every feature/bugfix spec with status, summary, and links into its requirements / design / decision log / tasks. |
| [`specs/estimation/pipeline/`](specs/estimation/pipeline/) | The core pipeline: requirements (incl. §0 phase plan and §1.2 hardware floor), design (algorithms, schemas), decisions, tasks. |
| [`specs/ui/iphone-experience/`](specs/ui/iphone-experience/) | The capture-flow shell: state machine, components, AR-session ownership, decisions. |
| [`tools/segmenter/README.md`](tools/segmenter/README.md) | PyTorch → Core ML / TFLite export pipeline for the Phase 3 trained segmenter. |
| [`docs/ml-training.md`](docs/ml-training.md) | End-to-end training recipe for the Phase 3 segmenter + β_c calibration. |
| [`CHANGELOG.md`](CHANGELOG.md) | Notable changes since the first version. |

## Build and test

The repo-root **Makefile** is the canonical developer loop — use it rather than raw
`swift`/`xcodebuild` invocations:

```sh
make build     # swift build — the MedataCore SwiftPM core + Harness targets
make test      # swift test; prints BOTH totals (XCTest AND swift-testing)
make spell     # Irish/British spelling linter (Req 19.2)
```

The on-device loop drives the Xcode app target on a connected iPhone:

```sh
make deploy-device        # Debug build → install → launch (UI / non-capture work)
make deploy-release-stub  # Release + forced dev-stub segmenter (capture testing)
make logs-device          # pull filtered device logs (subsystem ie.medata.app)
```

`make build`/`make test` only cover the SwiftPM core; the iOS app builds from
`MeData/MeData.xcodeproj`. The clone directory must be named `medata` because the project
references the SwiftPM package via the relative path `../../medata`. See
[`docs/ios-device-setup.md`](docs/ios-device-setup.md) and
[`docs/agent-notes/device-build-and-test.md`](docs/agent-notes/device-build-and-test.md)
for the end-to-end iPhone setup.
</content>
