# MeData

First and foremost - this work is built on, and made possible by, the incredibly dilligent and generous expertise of others. This includes (but is most certainly not limited to - ):

  - Arjen Schwarz (`ArjenSchwarz`), for both guidance, and the amazing spec drivene development based toolset he's worked on:
    - [agentic-coding](https://github.com/ArjenSchwarz/agentic-coding)
    - An LLM context/task manager [rune](https://github.com/ArjenSchwarz/rune)
    - [orbit](https://github.com/ArjenSchwarz/orbit) to orchestrate agent sessions (hit go and come back in the morning to see what's been done.)
  - Sam McLeod (`sammcj`)
    - mcp-devtools — <https://github.com/sammcj/mcp-devtools> — Once MCP server to rule them all... Seriously. It's good. It's simple. It is immensely useful.

Academic and dataset [references are here](docs/references.md). Without public data and research, none of this is even feasible. The core of the project relies on the free exchange of information and academic research - to leave their credits to last would be an eggregious disservice.

Finally - for a more complete view of the app context, need, and general aspirations for the broader project, read the [project document here](docs/drivers.md).

## App Overview

The app that estimates the carbohydrate content of a meal from one or two
photographs using **on-device** compute. Deterministic geometry, 
food segmenter, a bundled food-comp database, and calibrated per-class
correction factors.

It is first built for iPhone devices, however it will be expanded to other OS's as the expertise and time becomes available.

The application prefers the use of LiDAR for depth mapping of food and geometry, but deferrs to a 2 photo mechanism (using a drivers licens card) for point of reference and scale.

LiDAR requirement at runtime — non-LiDAR devices fall through to the two-view + ID-1
card path with `noLidarConfidence` set on every meal — but the calibration and

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

## Documentation

The `docs/` folder has most of what you'll need to read up on to help you out on where we are. You should also read the [specs process document](specs/PROCESS.md).

| Document | Context |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Layers, modules, abstractions, and Swift / SwiftUI conventions. |
| [`docs/README.md`](docs/README.md) | Index of all docs |
| [`docs/agent-notes/`](docs/agent-notes/) | Module-level implementation notes and gotchas — read the relevant one before working in a module. |
| [`specs/OVERVIEW.md`](specs/OVERVIEW.md) | Index of specs |
| [`tools/segmenter/README.md`](tools/segmenter/README.md) | PyTorch → Core ML / TFLite export pipeline for the Phase 3 trained segmenter. |
| [`docs/ml-training.md`](docs/ml-training.md) | End-to-end training recipe. |

## Build and test

The **Makefile** is where to make things.

```sh
make build     # swift build — the MedataCore SwiftPM core + Harness targets
make test      # swift test; prints BOTH totals (XCTest AND swift-testing)
make spell     # Irish spelling linter (Req 19.2)
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
