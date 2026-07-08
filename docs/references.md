# References

This codebase was made possible by, and builds on the work of others, detailed below.

---

## 1. Academic references

### Methods and clinical foundations

1. Laurentini, A., 'The Visual Hull Concept for Silhouette-Based Image
   Understanding', *IEEE Transactions on Pattern Analysis and Machine
   Intelligence*, vol. 16, no. 2 (1994), pp. 150–162. DOI:
   [10.1109/34.273735](https://doi.org/10.1109/34.273735).
   — Theoretical basis for the shape-from-silhouette visual-hull volume
   reconstruction. Cited in `specs/estimation/pipeline/requirements.md`,
   `specs/estimation/pipeline/decision_log.md`, `specs/DECISIONS.md`.

2. Dehais, J., Anthimopoulos, M., Shevchik, S. and Mougiakakou, S., 'Two-View 3D
   Reconstruction for Food Volume Estimation', *IEEE Transactions on
   Multimedia*, vol. 19, no. 5 (2017), pp. 1090–1099. DOI:
   [10.1109/TMM.2016.2642792](https://doi.org/10.1109/TMM.2016.2642792);
   preprint [arXiv:1701.03330](https://arxiv.org/abs/1701.03330).
   — Two-view canonical capture path (25° oblique envelope, §III.B) and the
   Table II bulk-correction factors. Cited in
   `specs/estimation/pipeline/requirements.md`, `tools/food_db/generate.py`, and
   applied in `MedataCore/Sources/Pipeline/EstimationFailure.swift`.

3. Anthimopoulos, M., Gianola, L., Scarnato, L., Diem, P. and Mougiakakou, S.,
   'A Food Recognition System for Diabetic Patients Based on an Optimized
   Bag-of-Features Model', *IEEE Journal of Biomedical and Health Informatics*,
   vol. 18, no. 4 (2014), pp. 1261–1271. DOI:
   [10.1109/JBHI.2014.2308928](https://doi.org/10.1109/JBHI.2014.2308928).
   — Food-recognition design patterns and density-calibration methodology. Cited
   in `specs/estimation/pipeline/requirements.md`.

4. Anthimopoulos, M., Dehais, J., Shevchik, S., Ransford, B. H., Duke, D., Diem,
   P. and Mougiakakou, S., 'Computer Vision-Based Carbohydrate Estimation for
   Type 1 Patients With Diabetes Using Smartphones', *Journal of Diabetes
   Science and Technology*, vol. 9, no. 3 (2015), pp. 507–515. DOI:
   [10.1177/1932296815580159](https://doi.org/10.1177/1932296815580159).
   — GoCARB clinical-validation methodology for carbohydrate estimation. Cited
   in `specs/estimation/pipeline/requirements.md`,
   `specs/estimation/pipeline/decision_log.md`.

### Dataset papers

5. Wu, X., Fu, X., Liu, Y., Lim, E.-P., Hoi, S. C. H. and Sun, Q., 'A
   Large-Scale Benchmark for Food Image Segmentation', in *Proceedings of the
   29th ACM International Conference on Multimedia (MM '21)*, 2021. DOI:
   [10.1145/3474085.3475201](https://doi.org/10.1145/3474085.3475201); preprint
   [arXiv:2105.05409](https://arxiv.org/abs/2105.05409).
   — The FoodSeg103 benchmark used to transfer-learn the food-region segmenter.

6. Thames, Q., Karpur, A., Norris, W., Xia, F., Panait, L., Weyand, T. and Sim,
   J., 'Nutrition5k: Towards Automatic Nutritional Understanding of Generic
   Food', in *Proceedings of the IEEE/CVF Conference on Computer Vision and
   Pattern Recognition (CVPR)*, 2021, pp. 8903–8911. Preprint
   [arXiv:2103.03375](https://arxiv.org/abs/2103.03375).
   — Gravimetric RGB-D dishes used for per-class β (bulk-correction)
   calibration.

7. Kawano, Y. and Yanai, K., 'Automatic Expansion of a Food Image Dataset
   Leveraging Existing Categories with Domain Adaptation', in *Proceedings of
   the ECCV Workshop on Transferring and Adapting Source Knowledge in Computer
   Vision (TASK-CV)*, 2014.
   — The UECFOOD-256 dataset, an optional supplement for undersampled classes.

8. Chen, Y. *et al.*, 'MetaFood3D: 3D Food Dataset with Nutrition Values',
   preprint [arXiv:2409.01966](https://arxiv.org/abs/2409.01966) (2024).
   — Single-food 3D meshes earmarked for future cross-dataset calibration (not
   yet integrated).

---

## 2. Data sources and datasets

### Bundled food-composition databases

- **CoFID — Composition of Foods Integrated Dataset.** McCance & Widdowson /
  Food Standards Agency (UK). Crown Copyright, Open Government Licence v3.
  <https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid>.
  Primary nutrition source (CoFID-wins merge). Bundled as
  `MedataCore/Sources/Foods/Resources/cofid_db.sqlite`; built by
  `tools/food_db/generate.py`.

- **AFCD — Australian Food Composition Database.** Food Standards Australia New
  Zealand (FSANZ). CC BY 4.0.
  <https://www.foodstandards.gov.au/science/monitoringnutrients/afcd>.
  Regional supplement covering classes CoFID omits. Bundled as
  `MedataCore/Sources/Foods/Resources/afcd_db.sqlite`.

### Training and calibration datasets

- **FoodSeg103.** Wu et al. (ref. 5). Apache 2.0.
  <https://xiongweiwu.github.io/foodseg103.html>. 7,118 image–mask pairs, 103
  classes — primary segmenter training set. Local copy gitignored under
  `data/foodseg103/` with SHA-256 provenance in `data/foodseg103/SOURCE.md` /
  `build/lineage.json`.

- **Nutrition5k.** Google Research (ref. 6). CC BY 4.0.
  <https://github.com/google-research-datasets/Nutrition5k>. Overhead RGB-D +
  per-ingredient gravimetric labels — drives β calibration only (no per-pixel
  masks, so not used for segmenter training). Cited in
  `specs/estimation/nutrition5k-calibration/requirements.md`; attribution shown
  in `App/AboutView.swift`.

- **UECFOOD-256.** Kawano & Yanai (ref. 7). Per-image permissive licences.
  <http://foodcam.mobi/dataset256.html>. Optional supplement — not currently
  used. Cited in `docs/ml-training.md`.

- **MetaFood3D** (planned). Chen et al. (ref. 8).
  <https://lorenz.ecn.purdue.edu/~food3d/>. Future cross-dataset calibration.
  Cited in `specs/OVERVIEW.md`.

### Supporting reference data

- **FAO/INFOODS Density Database for Cooked Foods (v2.0, 2012).** Food and
  Agriculture Organization of the United Nations. Served-portion bulk-density
  fallback values. Cited in `tools/food_db/generate.py`,
  `specs/estimation/pipeline/requirements.md`.

- **Carbohydrate as Monosaccharide-Equivalents Guidance.** Food Safety Authority
  of Ireland (FSAI). Conversion factors (starch→glucose 1.05, sucrose split
  1.10). Cited in `tools/food_db/generate.py`,
  `specs/estimation/pipeline/requirements.md`.

- **USDA FoodData Central.** U.S. Department of Agriculture. Public domain.
  <https://fdc.nal.usda.gov/>. Liquid serving volumes and carbohydrate values.
  Cited in `docs/agent-notes/dataset-strategy.md`.

---

## 3. Software libraries, frameworks, and tools

### Swift package dependencies (`Package.swift`)

- **swift-protobuf** (≥ 1.27.0) — <https://github.com/apple/swift-protobuf> —
  wire types for the `PortableContracts` target.
- **GRDB.swift** (≥ 6.0.0) — <https://github.com/groue/GRDB.swift> — SQLite
  access for the bundled food databases.
- **ZIPFoundation** (≥ 0.9.19) — <https://github.com/weichsel/ZIPFoundation> —
  archive export for persistence.

### Apple frameworks (iOS 17+ / macOS 14+)

- **ARKit** — LiDAR scene depth (`ARFrame.sceneDepth`), world tracking.
- **Core ML** — on-device segmenter inference (`segmenter.mlpackage`).
- **Vision** — ID-1 card detection (`VNDetectRectanglesRequest`).
- **AVFoundation** — camera capture session.
- **Core Motion** — IMU gravity vector for tilt guidance.
- **Accelerate / vImage** — YCbCr→BGRA colour conversion (BT.601 full-range).

### Python segmenter tooling (`tools/segmenter/`)

- **PyTorch** — segmenter training (`train.py`).
- **Core ML Tools / TensorFlow Lite** — export targets from `export.py`.

### Test frameworks

- **Swift Testing** and **XCTest** — the MedataCore test suites reported by
  `make test`.

---

## 4. Standards and specifications

- **ISO/IEC 7810:2003 — Identification cards, physical characteristics (ID-1
  format).** 85.60 × 53.98 mm reference used for card-based metric scale
  (Perspective-n-Point). Implemented in
  `MedataCore/Sources/CardDetection/CardPoseSolver.swift`;
  cited in `specs/estimation/pipeline/requirements.md`.

- **ITU-R BT.601 — Studio encoding parameters (colour).** YCbCr→BGRA conversion
  for camera frames. Cited in
  `specs/capture/rawframe-rgb-conversion/requirements.md`.

---

## 5. Other references

- **Apple Developer documentation** — ARKit `sceneDepth`
  (<https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics/scenedepth>),
  Xcode release notes, iPhone LiDAR compatibility matrix.
- **Keep a Changelog v1.1.0** — <https://keepachangelog.com/en/1.1.0/> —
  `CHANGELOG.md` format.
- **Design Handoff 00** — `design-system/wireframes/design-handoff-00/`, archived
  verbatim as an inert reference.

---

## 6. Prior art — related applications

Applications that have previously attempted photo-based carbohydrate estimation
for diabetes management. Listed as prior art, not as inputs to this codebase.

- **GoCARB** — <https://gocarb.ch/>. A computer-vision smartphone system that
  estimates carbohydrate content from photos of plated meals, developed under an
  EU FP7 Marie Curie Industry–Academia Partnerships and Pathways project. It is
  the research system behind the Anthimopoulos and Dehais papers above (refs.
  2–4); a research prototype rather than a shipped consumer product. Clinical
  results: 'Carbohydrate Estimation Supported by the GoCARB System in
  Individuals with Type 1 Diabetes', *Diabetes Care*, vol. 40, no. 2 (2017),
  pp. e6–e7.

- **SNAQ** — <https://www.snaq.ai/>. A commercial iOS/Android app that estimates
  carbohydrates and nutrition from a meal photo, with CGM integration and
  post-meal glucose predictions (reported 300K+ members). Now distributed in
  partnership with Ascensia Diabetes Care (CONTOUR® meter integration). Premium
  is subscription-only; web pricing (cheapest tier) as of July 2026:
  - 3-month plan — **$9.00/month** ($27.00 billed quarterly)
  - 1-year plan — **$5.00/month** ($60.00 billed annually)
  - 3-year plan — **$2.66/month** ($96.00 billed every 3 years)

  App Store / Google Play subscriptions may cost more (store fees up to 30%
  passed through). Pricing per <https://www.snaq.ai/premium>.

---

## 7. Development tooling and workflow credits

This codebase matured on top of the open-source agentic-development tooling of
two individuals. Their work has been an input to how this project was specified,
tracked, and built from the outset, and is credited here as such.

### Sam McLeod (`sammcj`)

- **mcp-devtools** — <https://github.com/sammcj/mcp-devtools> — the MCP server
  providing the search, documentation-lookup, and code-analysis tooling used
  throughout development.

### Arjen Schwarz (`ArjenSchwarz`)

- **agentic-coding** — <https://github.com/ArjenSchwarz/agentic-coding> — the
  spec-driven development framework (agents, skills, workflow) this project's
  process follows.
- **rune** — <https://github.com/ArjenSchwarz/rune> — hierarchical markdown
  task-list CLI used for task management.
- **orbit** — <https://github.com/ArjenSchwarz/orbit> — CLI orchestration that
  runs coding agents through sequential implementation phases.
- **transit** — <https://github.com/ArjenSchwarz/transit> — the task tracker
  (kanban + MCP server) used for ticketing.
