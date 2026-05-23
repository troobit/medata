# MeData

A native iOS app that estimates the carbohydrate content of a meal from one or two
photographs using **on-device** computer vision — deterministic geometry, an on-device
food segmenter, a bundled food-composition database, and offline-calibrated per-class
correction factors. No LLM, no network call in the estimation path.

Hardware floor: iPhone 12 Pro and later (rear LiDAR). OS floor: iOS 17.

```
photo(s) → silhouettes → visual hull → V_c (volume per class)
        → m_c = V_c · ρ_c → C = Σ m_c · κ_c / 100
```

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
│   │   ├── Foods/               CoFID + IFCDB food-composition DB
│   │   ├── Macros/              mass → carbs per class
│   │   ├── Confidence/          σ_meal combination
│   │   ├── Persistence/         SQLite meal records, artefacts, retention, export
│   │   └── Pipeline/            façade orchestrating the stage graph
│   ├── Resources/             segmenter.mlpackage + food_db.sqlite (bundled)
│   └── Tests/                 per-module XCTest targets
├── HarnessCore/               offline accuracy / β-calibration library
├── HarnessCLI/                macOS executable driving HarnessCore
├── MeData/                    Xcode project — iOS app target
│   ├── MeData.xcodeproj/        references ../App/*.swift and ../Package.swift
│   ├── Tests/                   Swift Testing unit tests (not wired in by default)
│   └── UITests/                 XCUITests for the capture flow
├── specs/                     Per-feature requirements / design / decisions / tasks
│   ├── research/                the on-device estimation pipeline
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
| [`docs/ios-device-setup.md`](docs/ios-device-setup.md) | Building, signing, and side-loading to a physical iPhone. |
| [`docs/README.md`](docs/README.md) | Index of all docs and how they relate to the specs. |
| [`docs/agent-notes/`](docs/agent-notes/) | Module-level implementation notes and gotchas — read the relevant one before working in a module. |
| [`specs/research/`](specs/research/) | The core pipeline: requirements, design (algorithms, schemas), decisions, tasks. |
| [`specs/ui/`](specs/ui/) | The capture-flow shell: state machine, components, AR-session ownership, decisions. |
| [`tools/segmenter/README.md`](tools/segmenter/README.md) | PyTorch → Core ML / TFLite export pipeline for the bundled segmenter. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed and when. |

## Build and test

```sh
swift build                      # all MedataCore modules + HarnessCLI
swift test                       # all SwiftPM test targets
bash tools/check_spelling.sh     # Irish/British spelling linter (Req 19.2)
```

The iOS app builds from `MeData/MeData.xcodeproj`. The clone directory must be named
`medata` because the project references the SwiftPM package via the relative path
`../../medata`. See [`docs/ios-device-setup.md`](docs/ios-device-setup.md) for the
end-to-end iPhone setup.
</content>
