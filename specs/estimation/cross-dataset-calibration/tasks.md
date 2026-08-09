---
references:
    - specs/estimation/cross-dataset-calibration/requirements.md
    - specs/estimation/cross-dataset-calibration/design.md
    - specs/estimation/cross-dataset-calibration/decision_log.md
---
# Tasks: cross-dataset-calibration

## Ingestion toolchain (Python)

- [x] 1. Write tests for the MetaFood3D-to-palette mapping builder <!-- id:fjp41x6 -->
  - pytest under tools/metafood3d/tests/
  - assert every mapped category targets a valid 35-class palette v1 id in order [superseded by Decision 15: valid class name in the palette v2 content list]
  - ambiguous cooking-method categories (potato_boiled/mashed/chips) excluded, not guessed
  - unmapped categories counted
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)

- [x] 2. Implement build_mapping.py + mapping_metafood3d_to_palette.json <!-- id:fjp41x7 -->
  - mirror tools/nutrition5k/build_mapping.py + mapping_n5k_to_palette.json
  - target ClassPalette.v1Standard ordering (load-bearing) [superseded by Decision 15: target v2Standard content; β is name-keyed, ordering is not load-bearing on the mixture path]
  - Blocked-by: fjp41x6 (Write tests for the MetaFood3D-to-palette mapping builder)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)

- [x] 3. Write render.py tests incl. Hypothesis determinism property <!-- id:fjp41x8 -->
  - same mesh+config yields byte-identical depth (Hypothesis)
  - nadir perspective at pinned RealSense-D435 640x480 intrinsics
  - output Float32 LE mm, 0 = miss
  - every food pixel nearer than the ~385mm plane (positive height-above-plane)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)

- [x] 4. Implement render.py (trimesh CPU ray-cast) <!-- id:fjp41x9 -->
  - first-hit ray depth per pixel; no GL context (Decision 12)
  - plate/plane depth ~385mm inside N5k CAMERA_TO_PLATE_BAND (250,400), below 0.4m cap
  - Blocked-by: fjp41x8 (Write render.py tests incl. Hypothesis determinism property)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)

- [x] 5. Write ingest.py tests incl. Hypothesis weight-plausibility <!-- id:fjp41xa -->
  - emits mixture fixtures: estimator_path mixture, sentinel no_segmenter, no probability tensor
  - writes run_summary.json (excluded/unmapped ids+counts) and metafood3d_truth.json {fixture_id: mesh_volume_mm3}
  - metric-scale check aborts on a mm/m unit error (unit-sanity) and on a weight-implausible k-scaled mesh (Hypothesis, Decision 14)
  - never writes MetaFood3D imagery/metadata into the repo
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.5](requirements.md#1.5)

- [x] 6. Implement ingest.py <!-- id:fjp41xb -->
  - mirror tools/nutrition5k/ingest.py; reuse build_fixture_bytes
  - authored SupportPlane params carried for the injected-plane branch
  - Blocked-by: fjp41xa (Write ingest.py tests incl. Hypothesis weight-plausibility), fjp41x7 (Implement build_mapping.py + mapping_metafood3d_to_palette.json), fjp41x9 (Implement render.py trimesh CPU ray-cast)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [3.1](requirements.md#3.1)

## Calibration harness (Swift)

- [ ] 7. Write CrossDatasetSkew TOST tests <!-- id:fjp41xc -->
  - equivalent vs inequivalent boundary beta pairs at given SEs
  - delta=0.20, alpha=0.05; CI of (betaA-betaB) with SE_delta=sqrt(seA^2+seB^2)
  - Stream: 2
  - Requirements: [5.2](requirements.md#5.2)

- [ ] 8. Implement HarnessCore/CrossDatasetSkew.swift <!-- id:fjp41xd -->
  - Blocked-by: fjp41xc (Write CrossDatasetSkew TOST tests)
  - Stream: 2
  - Requirements: [5.2](requirements.md#5.2)

- [ ] 9. Write VolumeFitDiagnostic tests <!-- id:fjp41xe -->
  - beta_geom = V_mesh_true / V_est aggregated per class from metafood3d_truth.json
  - reported, not baked
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3)

- [ ] 10. Implement HarnessCore/VolumeFitDiagnostic.swift <!-- id:fjp41xf -->
  - Blocked-by: fjp41xe (Write VolumeFitDiagnostic tests)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3)

- [ ] 11. Add CalibrationArtifact schema fields with serialization round-trip test <!-- id:fjp41xg -->
  - ClassEntry += contributing_datasets:{dataset:count}, single_source_uncorroborated:Bool
  - lineage += render_config (incl. noise-free-render note) + per_dataset
  - RunSummary += *_excluded_by_dataset buckets
  - types/serialization change: round-trip test included, no separate red task
  - Stream: 2
  - Requirements: [2.5](requirements.md#2.5), [4.3](requirements.md#4.3), [6.1](requirements.md#6.1), [9.1](requirements.md#9.1)

- [ ] 12. Write CalibrateRun injected-plane branch tests incl. steep food <!-- id:fjp41xh -->
  - MetaFood3D branch injects authored SupportPlane into TotalHullVolume, bypassing fitPlateRegionPlane RANSAC
  - steep-sided synthetic food yields correct volume where RANSAC would fit the food surface (Decision 13)
  - Stream: 2
  - Requirements: [2.4](requirements.md#2.4)

- [ ] 13. Implement CalibrateRun MetaFood3D injected-plane branch <!-- id:fjp41xi -->
  - Blocked-by: fjp41xh (Write CalibrateRun injected-plane branch tests incl. steep food), fjp41xg (Add CalibrationArtifact schema fields with serialization round-trip test)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4)

- [ ] 14. Write single-class mixture-fit + effective-sample/SE verification test <!-- id:fjp41xj -->
  - single-class row yields beta approx GT_mass/(V_est*rho_DB), no segmenter/checkpoint
  - row increments class effective-sample and lowers its SE (validates Decision 11 / M1)
  - test-only: existing mixture path unchanged
  - Blocked-by: fjp41xi (Implement CalibrateRun MetaFood3D injected-plane branch)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [ ] 15. Write CalibrationMerge corroboration + skew tests <!-- id:fjp41xk -->
  - single_source_uncorroborated set unless >=2 datasets independently identifiable AND TOST-agree
  - class present in two datasets but identifiable in only one is flagged
  - skew-inconsistent goes to pooled/unity
  - single-source flagged beta still bakes on effective-sample + relSE gates (not accuracy-gated)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [6.2](requirements.md#6.2), [8.1](requirements.md#8.1), [8.3](requirements.md#8.3)

- [ ] 16. Implement CalibrationMerge corroboration + skew wiring <!-- id:fjp41xl -->
  - Blocked-by: fjp41xk (Write CalibrationMerge corroboration + skew tests), fjp41xd (Implement HarnessCore/CrossDatasetSkew.swift), fjp41xg (Add CalibrationArtifact schema fields with serialization round-trip test)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [6.2](requirements.md#6.2), [8.1](requirements.md#8.1), [8.3](requirements.md#8.3)

## Reporting and bake

- [ ] 17. Write AccuracyHarness reporting tests <!-- id:fjp41xm -->
  - per-class beta delta + effective-sample/status before(N5k-only) vs after(combined)
  - carb MAPE/MAE delta on N5k eval pool, per-class only above a min eval-plate count
  - staple absent from eval pool marked no-in-harness-accuracy-validation
  - held-out MetaFood3D anchor (mass = V_est*beta*rho_DB) + broccoli cross-check; reported, not gating
  - Stream: 2
  - Requirements: [8.2](requirements.md#8.2), [10.1](requirements.md#10.1), [10.2](requirements.md#10.2)

- [ ] 18. Implement AccuracyHarness additions <!-- id:fjp41xn -->
  - Blocked-by: fjp41xm (Write AccuracyHarness reporting tests), fjp41xg (Add CalibrationArtifact schema fields with serialization round-trip test)
  - Stream: 2
  - Requirements: [8.2](requirements.md#8.2), [10.1](requirements.md#10.1), [10.2](requirements.md#10.2)

- [ ] 19. Wire HarnessCLI/main.swift for multi-dataset calibrate <!-- id:fjp41xo -->
  - merge multi-dataset --ingest-summary
  - add --heldout-frac for the MetaFood3D anchor
  - wiring: no separate red task
  - Blocked-by: fjp41xl (Implement CalibrationMerge corroboration + skew wiring), fjp41xn (Implement AccuracyHarness additions)
  - Stream: 2
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2)

- [ ] 20. Write generate.py persistence tests <!-- id:fjp41xp -->
  - persists calibration_contributing_datasets_per_class + calibration_single_source_classes meta dicts
  - palette-to-DB edition lock still holds
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [7.2](requirements.md#7.2)

- [ ] 21. Implement generate.py meta-dict persistence <!-- id:fjp41xq -->
  - Blocked-by: fjp41xp (Write generate.py persistence tests), fjp41xg (Add CalibrationArtifact schema fields with serialization round-trip test)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [7.2](requirements.md#7.2)

## Integration

- [ ] 22. Write backwards-compat golden test <!-- id:fjp41xr -->
  - N5k-only calibrate at fixed seed reproduces current baseline beta byte-for-byte through the pooling path
  - Blocked-by: fjp41xl (Implement CalibrationMerge corroboration + skew wiring)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1)

- [ ] 23. Write end-to-end calibrate-to-bake integration test <!-- id:fjp41xs -->
  - synthetic MetaFood3D fixture set to HarnessCLI calibrate to calibrate.json to generate.py bake
  - new per-class fields persist; palette lock holds
  - Blocked-by: fjp41xo (Wire HarnessCLI/main.swift for multi-dataset calibrate), fjp41xq (Implement generate.py meta-dict persistence), fjp41xb (Implement ingest.py)
  - Stream: 2
  - Requirements: [7.2](requirements.md#7.2)
