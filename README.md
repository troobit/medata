# MeData

First and foremost - this work is built on, and made possible by, the incredibly dilligent and generous expertise of others. This includes (but is most certainly not limited to - ):

  - Arjen Schwarz (`ArjenSchwarz`), for both guidance, and the amazing spec drivene development based toolset he's worked on:
    - [agentic-coding](https://github.com/ArjenSchwarz/agentic-coding)
    - An LLM context/task manager [rune](https://github.com/ArjenSchwarz/rune)
    - [orbit](https://github.com/ArjenSchwarz/orbit) to orchestrate agent sessions (hit go and come back in the morning to see what's been done.)
  - Sam McLeod (`sammcj`)
    - mcp-devtools — <https://github.com/sammcj/mcp-devtools> — Once MCP server to rule them all... Seriously. It's good. It's simple. It is immensely useful.

Without public data and research, none of this is even feasible. The core of the project relies on the free exchange of information and academic research - to leave their credits to last would be an eggregious disservice. The full credits document (including software, standards, and prior art) is [docs/references.md](docs/references.md); the academic references and data sources are below.

## Academic references

### Methods and clinical foundations

1. Laurentini, A., 'The Visual Hull Concept for Silhouette-Based Image Understanding', *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol. 16, no. 2 (1994), pp. 150–162. DOI: [10.1109/34.273735](https://doi.org/10.1109/34.273735). — Theoretical basis for the shape-from-silhouette visual-hull volume reconstruction.
2. Dehais, J., Anthimopoulos, M., Shevchik, S. and Mougiakakou, S., 'Two-View 3D Reconstruction for Food Volume Estimation', *IEEE Transactions on Multimedia*, vol. 19, no. 5 (2017), pp. 1090–1099. DOI: [10.1109/TMM.2016.2642792](https://doi.org/10.1109/TMM.2016.2642792); preprint [arXiv:1701.03330](https://arxiv.org/abs/1701.03330). — Two-view canonical capture path and the bulk-correction factors.
3. Anthimopoulos, M., Gianola, L., Scarnato, L., Diem, P. and Mougiakakou, S., 'A Food Recognition System for Diabetic Patients Based on an Optimized Bag-of-Features Model', *IEEE Journal of Biomedical and Health Informatics*, vol. 18, no. 4 (2014), pp. 1261–1271. DOI: [10.1109/JBHI.2014.2308928](https://doi.org/10.1109/JBHI.2014.2308928). — Food-recognition design patterns and density-calibration methodology.
4. Anthimopoulos, M., Dehais, J., Shevchik, S., Ransford, B. H., Duke, D., Diem, P. and Mougiakakou, S., 'Computer Vision-Based Carbohydrate Estimation for Type 1 Patients With Diabetes Using Smartphones', *Journal of Diabetes Science and Technology*, vol. 9, no. 3 (2015), pp. 507–515. DOI: [10.1177/1932296815580159](https://doi.org/10.1177/1932296815580159). — GoCARB clinical-validation methodology for carbohydrate estimation.

### Dataset papers

5. Wu, X., Fu, X., Liu, Y., Lim, E.-P., Hoi, S. C. H. and Sun, Q., 'A Large-Scale Benchmark for Food Image Segmentation', in *Proceedings of the 29th ACM International Conference on Multimedia (MM '21)*, 2021. DOI: [10.1145/3474085.3475201](https://doi.org/10.1145/3474085.3475201); preprint [arXiv:2105.05409](https://arxiv.org/abs/2105.05409). — The FoodSeg103 benchmark used to transfer-learn the food-region segmenter.
6. Thames, Q., Karpur, A., Norris, W., Xia, F., Panait, L., Weyand, T. and Sim, J., 'Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food', in *Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR)*, 2021, pp. 8903–8911. Preprint [arXiv:2103.03375](https://arxiv.org/abs/2103.03375). — Gravimetric RGB-D dishes used for per-class β (bulk-correction) calibration.
7. Kawano, Y. and Yanai, K., 'Automatic Expansion of a Food Image Dataset Leveraging Existing Categories with Domain Adaptation', in *Proceedings of the ECCV Workshop on Transferring and Adapting Source Knowledge in Computer Vision (TASK-CV)*, 2014. — The UECFOOD-256 dataset, an optional supplement for undersampled classes.
8. Chen, Y., He, J., Czarnecki, C., Vinod, G., Mahmud, T. I., Raghavan, S., Ma, J., Mao, D., Nair, S., Xi, P., Wong, A., Delp, E. and Zhu, F., 'MetaFood3D: Large 3D Food Object Dataset with Nutrition Values', preprint [arXiv:2409.01966](https://arxiv.org/abs/2409.01966) (2024). — Single-food 3D meshes and per-object nutrition values used for cross-dataset β calibration.

## Data sources

### Bundled food-composition databases

- **CoFID — Composition of Foods Integrated Dataset.** McCance & Widdowson / Food Standards Agency (UK). Crown Copyright, Open Government Licence v3. <https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid>. Primary nutrition source (CoFID-wins merge); bundled as `cofid_db.sqlite`.
- **AFCD — Australian Food Composition Database.** Food Standards Australia New Zealand (FSANZ). CC BY 4.0. <https://www.foodstandards.gov.au/science/monitoringnutrients/afcd>. Regional supplement covering classes CoFID omits; bundled as `afcd_db.sqlite`.

### Training and calibration datasets

- **FoodSeg103.** Wu et al. (ref. 5). Apache 2.0. <https://xiongweiwu.github.io/foodseg103.html>. Primary segmenter training set (7,118 image–mask pairs, 103 classes).
- **Nutrition5k.** Google Research (ref. 6). CC BY 4.0. <https://github.com/google-research-datasets/Nutrition5k>. Overhead RGB-D + per-ingredient gravimetric labels; drives β calibration only.
- **UECFOOD-256.** Kawano & Yanai (ref. 7). Per-image permissive licences. <http://foodcam.mobi/dataset256.html>. Optional supplement — not currently used.
- **MetaFood3D.** Chen et al. (ref. 8). CC BY-NC 4.0 (non-commercial). <https://lorenz.ecn.purdue.edu/~food3d/>. Single-food 3D meshes + nutrition values for cross-dataset β calibration. Access is request-gated (form + password); access obtained 2026-08-10. Only the 3D meshes and nutrition values (plus the dataset README) are collected — depth is rendered deterministically from the meshes, so the Blender renders, RGBD videos, and point clouds are not used. Commercial use is governed by cross-dataset-calibration Decision 18: research βs may use it freely; a commercial ship requires an NC-free re-bake or a commercial licence.

### Supporting reference data

- **FAO/INFOODS Density Database for Cooked Foods (v2.0, 2012).** Food and Agriculture Organization of the United Nations. Served-portion bulk-density fallback values.
- **Carbohydrate as Monosaccharide-Equivalents Guidance.** Food Safety Authority of Ireland (FSAI). Conversion factors (starch→glucose 1.05, sucrose split 1.10).
- **USDA FoodData Central.** U.S. Department of Agriculture. Public domain. <https://fdc.nal.usda.gov/>. Liquid serving volumes and carbohydrate values.

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
make spell     # Spelling linter
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

## Quickstart: recording field feedback

Development builds carry a field-note layer (`FIELD_LOOP`, compiled out of
product builds). It is a small draggable button floating above every screen:
tap it and write — or dictate — what is wrong, right where it is wrong. The note
carries the screen it was taken on, a screenshot of exactly what was displayed,
and, on a capture surface, a link to the most recent estimation attempt.

Nothing about it is capture-specific. A note on a chart, a wording problem, or a
layout that reads badly is worth taking the same way.

**On the phone**

```sh
make deploy-device        # any Debug or Release build carries the note layer
```

Tap the button → type or hit **Speak** → **Save**. The Context section of the
sheet tells you what the note is tied to before you save it:

```
Screen    capture.ready
Attempt   1c9a2f4b · 40 sec. ago      ← or "none linked"
```

`Attempt` appears whenever an estimation attempt has been recorded, **including
one that failed before drawing anything** — a capture that never reaches the
result screen is exactly when a note is worth taking. The button can be dragged
to any corner and stays there; it never appears in its own screenshots.

**On the Mac**

```sh
make field-notes   # notes + the events DB only — seconds. Use this during a session.
make field-pull    # everything, including capture bundles — minutes to hours.
```

Reach for `field-notes` while work is in flight; it leaves the multi-gigabyte
capture bundles on the phone and still ingests every note, screenshot and
outcome row. A note whose bundle is still on the device is not lost — the join
is re-resolved on every ingest, so it links itself once `field-pull` brings the
bundle across.

`field-pull` prints one line per file with percent, throughput and an ETA, and
is resumable: interrupt it and the next run picks up where it stopped rather
than re-copying. It is slow because the data is large — measured at ~14.5 MB/s
over the cable, with two-view successes around 390 MB each — not because it is
stuck.

Both land in `../medata-corpus/`. To read what came across:

```sh
make field-report          # alignment metrics across the whole corpus
sqlite3 ../medata-corpus/index.sqlite \
  "SELECT screen_id, text, meal_linked FROM notes ORDER BY created_at_ms DESC LIMIT 10;"
```

**Adding a screen.** A new surface reports whatever screen it was pushed from
until it names itself. One line at its root fixes that:

```swift
SomeNewScreen()
    .fieldScreen("some.new.screen")
```

The rest of the loop — diagnosis, the cycle task file, the guarded fixes — is in
[`specs/estimation/ml-feedback-loop/`](specs/estimation/ml-feedback-loop/) and
[`docs/agent-notes/ml-feedback-loop.md`](docs/agent-notes/ml-feedback-loop.md).
