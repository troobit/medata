# Prerequisites for Research

These tasks must be completed by the user before or during implementation. The coding agent cannot perform any of them.

## Before Starting

- [ ] **Apple Developer account** active, with iOS development certificate and provisioning profile installed in Xcode (required for any device build / TestFlight)
- [ ] **Xcode 16+** installed on macOS development machine
- [ ] **iPhone 13 Pro Max** (the v1 hardware floor per Req 1.2) with rear LiDAR available as a tethered test device (required for any task involving LiDAR, ARKit world tracking, or on-device performance assertions — blocks tasks 9, 22, 25, 27, 50, 65, 75)
- [ ] **macOS 14+** with Python 3.11+ installed for the segmenter export pipeline (blocks task 23)
- [ ] **Git LFS** installed locally and configured for the repository (blocks fixture pipeline used by tasks 56–62)
- [ ] **Create separate `medata-fixtures` Git LFS repository** on the project's Git host. This is the home for cached `MealFixture.proto` records (per design §7.3); fixtures must NOT live in the app source repository because of their size (blocks task 56)
- [ ] **Standard ID-1 reference card** (any expired credit card, library card, or printed ID-1 calibration target) for testing card-pose recovery (blocks tasks 10–12 device tests)

## During Implementation

- [ ] **Provision PyTorch training environment** with `torchvision`, `coremltools` 8.x, and `ai-edge-torch` installed (blocks task 23, segmenter export pipeline)
- [ ] **Acquire FoodSeg103 dataset** (Apache 2.0 licence, https://xiongweiwu.github.io/foodseg103.html) for transfer-learning the segmenter (blocks segmenter training that produces the bundled `.mlpackage` for task 22)
- [ ] **Curate v1 palette: 24 food classes (within the 24–40 range per Req 8.4) + 3 special classes** (co-curated with available CoFID/AFCD density coverage per Decision 25 / Req 8.4 / Req 11.4). Decision 8 lists this as composite-class selection. Required before training starts; required before task 36 implements the bundled `cofid_db.sqlite`
- [ ] **Source CoFID raw data** (Open Government Licence v3) and convert into the bundled `cofid_db.sqlite` per the schema in design §4.1 (blocks task 36). Attribution per OGL v3 must be added to the App / Legal screen
- [ ] **Source AFCD raw data** (Australian Food Composition Database, latest edition) and produce the bundled `afcd_db.sqlite` (blocks task 74; CoFID-wins COALESCE merge per design §4.1)
- [ ] **Author `class_mapping_v1_v2.json`** schema instance (template only — no real v2 mapping until v2 ships) for testing palette migration (blocks task 47)
- [ ] **Acquire / build a labelled segmenter test set** (held-out images with ground-truth masks for the 24 food classes) so the mIoU bar in Req 8.9 can be measured (blocks task 63)
- [ ] **Acquire gravimetric meal test set** with ≥30 calibration meals per class for the dominant classes (per Decision 20 / Req 21.1). This is the **single largest project risk** (Req 20.4): a v1 release with thin per-class data ships with most classes flagged `uncalibrated_pooled` or `uncalibrated_unity`. Each meal requires a calibrated kitchen scale, gravimetric weighing per food item, and matched two-view + LiDAR + ID-1 card photos. Blocks task 58 (calibration on real data) and task 60 (accuracy harness against the v1 acceptance bar)
- [ ] **Verify Apple Neural Engine residency** in Xcode's Core ML performance report after the segmenter is exported (blocks task 22 final acceptance)
- [ ] ~~**Set up `BackgroundTasks` framework identifier**~~ **DEFERRED** — the retention scheduler is removed in v1 (Req 17.3) and deferred behind the `RETENTION_SCHEDULER_ENABLED` compile flag (Req 17.6). Re-add this prerequisite only when the cloud-storage handoff that re-activates the scheduler is designed.

## Before Testing

- [ ] **Calibrate test devices' camera intrinsics** if `AVCameraCalibrationData` is unavailable on the chosen capture format (rare; blocks task 9 device verification)
- [ ] **Record fixture batches** of representative meals on the v1 hardware floor: at least 10 meals each for `single_view_lidar` and `two_view_sfs` paths, with cached probability tensors and gravimetric ground-truth (blocks tasks 60–62 accuracy harness end-to-end runs)
- [ ] **Confirm bundle artefacts produced**: `cofid_db.sqlite`, `afcd_db.sqlite`, `food_segmenter.mlpackage` (≤ 10 MB after FP16 quantisation per Req 8.2) (blocks any device build that reads bundled resources)

## Notes

- **Test set acquisition is the critical path.** Without ≥30 calibration meals per class, β_c calibration falls back to pooled or unity values and the v1 accuracy reference (MAPE < 20%, MAE ≤ 25 g per Req 21.3) is unverifiable for the affected classes. Plan dataset acquisition in parallel with implementation.
- **Anthropic / OpenAI / cloud-vendor API keys are NOT required** in v1 (cloud validation is Decision 22 deferred per Req 22).
- **No App Store registration is required** for v1 since the spec does not target store distribution; if TestFlight beta is needed later, App Store Connect setup is a separate prerequisite.
