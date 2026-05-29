---
references:
    - specs/research/requirements.md
    - specs/research/design.md
    - specs/research/decision_log.md
---
# Research — Implementation Tasks

## Foundation

- [x] 1. Create Swift Package + Xcode project skeleton <!-- id:0f06zz7 -->
  - Create `MedataCore` Swift Package with module folders for CaptureKit, CardDetection, SupportPlane, MetricScale, Segmentation, Volume, Foods, Macros, Confidence, Persistence, PortableContracts, Pipeline (per design §2.1).
  - Create iOS app target referencing MedataCore; Swift 5.9+, deployment target iOS 17.
  - Create `HarnessCLI` SPM executable target for macOS.
  - Add Package.swift, .xcodeproj, .swiftformat, .gitattributes (Git LFS for fixtures dir convention).
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [18.1](requirements.md#18.1), [18.2](requirements.md#18.2)

- [x] 2. Write .proto schemas and round-trip tests for portable contracts <!-- id:0f06zz3 -->
  - Author all 24 .proto files listed in design §4.3 under `MedataCore/Sources/PortableContracts/Schemas/`.
  - Write XCTest cases: encode → decode → bit-equal for each top-level message (RawFrame, MealRecord, MealFixture, ProbabilityTensor, etc.).
  - Verify protobuf-JSON round-trip is deterministic (camelCase keys, RFC 7159 stable ordering) per Decision 31.
  - Tests will fail until task 3 generates the Swift sources.
  - Requirements: [18.1](requirements.md#18.1), [18.2](requirements.md#18.2), [14.4](requirements.md#14.4), [15.1](requirements.md#15.1)

- [x] 3. Generate Swift sources from .proto and integrate `swift-protobuf` <!-- id:0f06zz4 -->
  - Run `protoc --swift_out` against the schemas; commit generated sources to `PortableContracts/Generated/`.
  - Add `swift-protobuf` Package.swift dependency.
  - Confirm round-trip tests from task 2 pass.
  - Blocked-by: 0f06zz3 (Write .proto schemas and round-trip tests for portable contracts)
  - Requirements: [18.2](requirements.md#18.2)

- [x] 4. Write tests for `Vec3` / `Mat4` conventions and `simd` interop <!-- id:0f06zz5 -->
  - Test column-major layout, right-handed cross product, projection sign per design §6.0.
  - Test simd_float3↔Vec3 and simd_float4x4↔Mat4 conversion round-trip is bit-equal.
  - Test sign convention of `project(K, p)` for −Z forward.
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [18.1](requirements.md#18.1)

- [x] 5. Implement `Vec3` / `Mat4` extension operators and `simd` adapters <!-- id:0f06zz6 -->
  - Operator overloads for `+`, `-`, dot, cross, normalise, projection per design §6.0.
  - Adapter in `CaptureKit` only — every other module consumes the generated protobuf types directly.
  - Blocked-by: 0f06zz5 (Write tests for `Vec3` / `Mat4` conventions and `simd` interop)
  - Requirements: [18.1](requirements.md#18.1)

- [x] 6. Write tests for `MetalContext` lifecycle <!-- id:0f06zz8 -->
  - Test device init succeeds, command queue creation, library loading from .metal files.
  - Test `Sendable` conformance under `@unchecked` contract per design §3.1.1.
  - Blocked-by: 0f06zz7 (Create Swift Package + Xcode project skeleton)
  - Requirements: [18.1](requirements.md#18.1)

- [x] 7. Implement `MetalContext.shared` singleton with device/queue/libraries <!-- id:0f06zz9 -->
  - Load `segmenterLibrary` and `volumeLibrary` MTLLibraries at app launch.
  - Inject into `CoreMLSegmenter`, `VoxelCarvingEstimator`, `HeightFieldEstimator`.
  - Blocked-by: 0f06zz8 (Write tests for `MetalContext` lifecycle)
  - Requirements: [1.1](requirements.md#1.1), [16.5](requirements.md#16.5)

## Capture and Detection

- [x] 8. Write tests for `CaptureKit` configuration and `RawFrame` portable contract <!-- id:0f06zza -->
  - Test `RawFrame` carries `pixelFormat`, `colourSpace`, `orientation`, `timestampMonotonicNs` (no `TimeInterval`); per design §3.1.
  - Test simd→Vec3/Mat4 conversion at module boundary.
  - Test capture session releases within 200 ms (mocked AVCaptureSession).
  - Blocked-by: 0f06zz6 (Implement `Vec3` / `Mat4` extension operators and `simd` adapters), 0f06zz9 (Implement `MetalContext.shared` singleton with device/queue/libraries)
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6)

- [x] 9. Implement `CaptureKit` (AVFoundation + ARKit + Core Motion bridge) <!-- id:0f06zzb -->
  - Capture nadir + oblique frames; record intrinsics, gravity, world transform, LiDAR depth via `ARFrame.sceneDepth`.
  - Convert iOS-private `simd_*` types to portable `Vec3`/`Mat4` before exposing `RawFrame`.
  - Map ARKit `ARConfidenceLevel.{low,medium,high}` to UInt8 `{0,127,255}` per design §6.0.
  - Refuse capture flow on devices without rear LiDAR (Req 1.3).
  - Blocked-by: 0f06zza (Write tests for `CaptureKit` configuration and `RawFrame` portable contract)
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)

- [x] 10. Write tests for ID-1 P4P card-pose recovery (§6.1) <!-- id:0f06zzc -->
  - Synthesise known card poses; perturb image points by ≤1 px noise; assert recovered translation < 2 mm.
  - Test sign-of-λ enforcement (M3): if t_z ≥ 0 after first solve, λ flipped; if both signs land behind camera, throw `degenerateCardPose`.
  - Test SO(3) projection with `det(UV^T)` fix-up.
  - Test cardTooOblique refusal at |r3·ẑ_cam| < 0.2 (edge case 1).
  - Test SVD condition gate: σ_min/σ_max < 1e-6 → degenerateCardPose.
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)

- [x] 11. Implement P4P card-pose recovery (custom SVD-based, no OpenCV) <!-- id:0f06zzd -->
  - `VNDetectRectanglesRequest` + custom DLT homography decomposition using Accelerate's LAPACK.
  - Recover both `s_card_init` (card-plane scale, used by §6.3) and the scale at the food plane (used by §6.4) per design §6.1.
  - Persist PnP residual as informational sub-confidence input (not consumed by σ_meal in v1).
  - Blocked-by: 0f06zzc (Write tests for ID-1 P4P card-pose recovery (§6.1))
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)

- [x] 12. Write property-based tests for P4P round-trip <!-- id:0f06zze -->
  - Use `SwiftCheck` generators for camera intrinsics and card poses in a realistic envelope.
  - Property: `recover(project(pose))` returns a pose within ε of original (per design §7.2).
  - Adjacent to task 11; PBT augments example-based tests with broader input coverage.
  - Blocked-by: 0f06zzd (Implement P4P card-pose recovery (custom SVD-based, no OpenCV))
  - Requirements: [5.1](requirements.md#5.1)

- [x] 13. Write tests for LiDAR support-plane RANSAC fit (§6.2) <!-- id:0f06zzf -->
  - Synthesise plane + outliers; assert recovered normal within 1° of gravity, distance within 2 mm.
  - Test deterministic seed from `xxh64(depth.bytes)` — two runs on same fixture produce identical inlier set.
  - Test `lidarFitDegenerate` refusal when inlier covariance is singular.
  - Test `lidarFitResidualTooHigh` refusal at residual > 8 mm.
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 14. Implement LiDAR support-plane RANSAC fitter <!-- id:0f06zzg -->
  - Resample depth + confidence to colour-image grid (bilinear / nearest); apply confidence threshold τ_conf = 0.66 per §6.0.
  - Project lower-edge band points to camera-1 frame (mm); 256 RANSAC iterations with gravity bias 15°.
  - Refine via least-squares fit on inliers; persist residual_mm.
  - Blocked-by: 0f06zzf (Write tests for LiDAR support-plane RANSAC fit (§6.2))
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)

- [x] 15. Write tests for card-only iterative support-plane fit (§6.3) <!-- id:0f06zzh -->
  - Test h_food_(0) = 0 initialisation; π_sup_(0) at card-centre depth.
  - Test 1 mm convergence within 5 iterations; best-of-5 fallback at residual ≤ 1.5 mm.
  - Test `iterationDiverged` refusal when best residual > 1.5 mm.
  - Blocked-by: 0f06zzd (Implement P4P card-pose recovery (custom SVD-based, no OpenCV))
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3)

- [x] 16. Implement card-only iterative support-plane fitter <!-- id:0f06zzi -->
  - Three-unknown fixed-point: s_card → π_sup → h_food, per design §6.3.
  - Track best-residual across iterations; return best-of-5 when strict 1 mm not reached but ≤ 1.5 mm achieved.
  - Blocked-by: 0f06zzh (Write tests for card-only iterative support-plane fit (§6.3))
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3)

- [x] 17. Write tests for metric scale resolver (§6.4) and σ_s <!-- id:0f06zzj -->
  - Test all four cases of Req 7 (both signals, lidar-only, card-only, neither).
  - Test symmetric agreement formula `disagreement = |s_lidar - s_card| / ((s_lidar + s_card) / 2)` (M4): swapping inputs gives identical σ_s.
  - Test refusal `noScaleAvailable` when neither signal present.
  - Test LiDAR scale converted from m/px to mm/px before resolver runs (unit consistency).
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6)

- [x] 18. Implement metric scale resolver (pure function) <!-- id:0f06zzk -->
  - Symmetric agreement formula per design §6.4.
  - Output `MetricScale` struct with σ_s ∈ [ε, 1] and per-source availability flags.
  - Blocked-by: 0f06zzj (Write tests for metric scale resolver (§6.4) and σ_s)
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6)

## Segmentation

- [x] 19. Write tests for segmenter pre/post-processing (§6.5) <!-- id:0f06zzl -->
  - Test pixel-format canonicalisation: BGRA8→RGB8 swap, RGBA8→RGB8 alpha drop, RGB8 no-op (P3, P9).
  - Test letterbox resize + post-normalisation padding `pad[c] = (0 - mean[c]) / std[c]`.
  - Test resize-back to (W,H) with pixel-centre alignment.
  - Test σ_seg = mean over food pixels of max class prob (M8): excludes background, unknown_food, unsupported_liquid.
  - Test `noFoodPixels` refusal aligned with silhouette test `(1 − q[bg]) ≥ τ_sil`, NOT `argmax = bg` (edge case 3).
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [8.1](requirements.md#8.1), [8.4](requirements.md#8.4), [8.7](requirements.md#8.7), [8.8](requirements.md#8.8), [8.9](requirements.md#8.9), [13.1](requirements.md#13.1)

- [x] 20. Implement segmenter pre/post-processing pipeline <!-- id:0f06zzm -->
  - Steps 1–13 in design §6.5 verbatim; all FP32 internally before final FP16 cast.
  - Construct portable `ProbabilityTensor.bytes` (FP16 LE, HWC row-major) and `ArgmaxMap`.
  - Compute `perClassMeanProb` (informational) alongside σ_seg.
  - Blocked-by: 0f06zzl (Write tests for segmenter pre/post-processing (§6.5))
  - Requirements: [8.1](requirements.md#8.1), [8.6](requirements.md#8.6), [8.7](requirements.md#8.7), [8.8](requirements.md#8.8), [13.1](requirements.md#13.1)

- [x] 21. Write tests for `CoreMLSegmenter` wrapper (model loading + inference) <!-- id:0f06zzn -->
  - Test model loads from bundled file path (string, not URL per P8).
  - Test segmentation produces ProbabilityTensor with portable byte layout regardless of MTLBuffer backing.
  - Test segmenter weights file size ≤ 10 MB (Req 8.2).
  - Blocked-by: 0f06zz9 (Implement `MetalContext.shared` singleton with device/queue/libraries), 0f06zzm (Implement segmenter pre/post-processing pipeline)
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.5](requirements.md#8.5)

- [x] 22. Implement `CoreMLSegmenter` with ANE inference + Metal-backed probability tensor <!-- id:0f06zzo -->
  - Load Core ML model via `MLModel.compileModel` if needed; force ANE compute units where available, CPU fallback for dev builds.
  - Construct `ProbabilityTensor` whose canonical `bytes` field is the portable contract; `MTLBuffer` is private adaptor (P1).
  - Apply pre/post-processing from task 20.
  - Blocked-by: 0f06zzn (Write tests for `CoreMLSegmenter` wrapper (model loading + inference)), wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading, wrapper, loading
  - Requirements: [8.1](requirements.md#8.1), [8.3](requirements.md#8.3), [8.5](requirements.md#8.5), [16.5](requirements.md#16.5)

- [x] 23. Implement Python segmenter export pipeline (PyTorch → Core ML + TFLite) <!-- id:0f06zzp -->
  - Python script in `tools/segmenter/export.py`: torchvision DeepLabV3+MobileNetV3-Large checkpoint → `coremltools.convert(...)` → Core ML; same checkpoint → `ai-edge-torch` → TFLite (validation only in v1).
  - Verify both exports produce numerically equivalent output on a reference image.
  - Save Core ML weights into `MedataCore/Resources/segmenter.mlpackage` (bundled per Decision 27).
  - ONNX hop is bypassed (Decision 28).
  - Blocked-by: 0f06zz7 (Create Swift Package + Xcode project skeleton)
  - Requirements: [8.5](requirements.md#8.5), [18.3](requirements.md#18.3)

## Volume Estimation

- [x] 24. Write tests for two-view voxel carving Metal kernel (§6.6) <!-- id:0f06zzq -->
  - Synthetic cube of known side length: assert volume within 5% of analytical, in cm³ (M5 unit conversion verified).
  - Test silhouette test on `(1 - q[bg]) ≥ τ_sil` not argmax=bg (DB2).
  - Test FP32 product promotion for ownership argmax (§6.0 reproducibility).
  - Test voxel ownership disjointness: union of per-class O_c sets has no overlap.
  - Test single-class single-view fallback degraded extrusion path (edge case 4).
  - Test τ_v = 0.04 ambiguous-voxel discard.
  - Test `noFoodVolumeRecovered` refusal when all classes < 1 cm³ (edge case 2).
  - Blocked-by: 0f06zz9 (Implement `MetalContext.shared` singleton with device/queue/libraries), 0f06zzm (Implement segmenter pre/post-processing pipeline)
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5), [9.6](requirements.md#9.6), [9.7](requirements.md#9.7), [9.8](requirements.md#9.8), [9.9](requirements.md#9.9)

- [x] 25. Implement two-view voxel carving Metal kernel + Swift dispatcher <!-- id:0f06zzr -->
  - Metal kernel in `Volume/Kernels/voxel_carve.metal`; one thread per voxel, 8×8×8 threadgroups.
  - Per-class atomic counts in `MTLBuffer<atomic_uint>[C]` with `.storageModeShared`.
  - Single-class single-view fallback: silhouette extrusion to π_sup with prior 30 mm height, applied AFTER main kernel.
  - Output mm³, convert to cm³ in dispatcher per design §6.6 (M5).
  - Blocked-by: 0f06zzq (Write tests for two-view voxel carving Metal kernel (§6.6)), carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving, carving
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5), [9.6](requirements.md#9.6), [9.7](requirements.md#9.7), [9.8](requirements.md#9.8)

- [x] 26. Write tests for single-view height-field integration (§6.7) <!-- id:0f06zzs -->
  - Synthetic dome with known LiDAR depth: assert volume within 3% of analytical, cm³.
  - Test 1/cos³θ off-axis correction (M1) — corner pixels get ~54% larger area at 73° HFoV.
  - Test per-class `lidarCoverageFraction` tracking.
  - Test `lidarCoverageTooLow` refusal at any class < 50% LiDAR coverage (edge case 6).
  - Test mm³ → cm³ conversion (M5).
  - Blocked-by: 0f06zz9 (Implement `MetalContext.shared` singleton with device/queue/libraries), 0f06zzm (Implement segmenter pre/post-processing pipeline)
  - Requirements: [3.5](requirements.md#3.5), [9.1](requirements.md#9.1), [9.4](requirements.md#9.4), [9.7](requirements.md#9.7), [9.8](requirements.md#9.8), [13.2](requirements.md#13.2)

- [x] 27. Implement single-view height-field Metal kernel + Swift dispatcher <!-- id:0f06zzt -->
  - Metal kernel in `Volume/Kernels/height_field.metal`; one thread per nadir-view pixel.
  - Pixel area `a(p) = z_t² / (f_x · f_y · cos³θ_p)` with `cosθ_p = f / sqrt(f² + (u-c_x)² + (v-c_y)²)` (Decision 29).
  - Atomic accumulator per class; inter-class occlusion detection in same kernel (single-pass 4-neighbour scan) per design §6.8.
  - Blocked-by: 0f06zzs (Write tests for single-view height-field integration (§6.7))
  - Requirements: [3.5](requirements.md#3.5), [9.1](requirements.md#9.1), [9.4](requirements.md#9.4), [9.7](requirements.md#9.7), [9.8](requirements.md#9.8)

- [x] 28. Write property-based tests for voxel ownership disjointness <!-- id:0f06zzu -->
  - PBT generator for arbitrary probability tensor pairs.
  - Property: union of per-class O_c sets is pairwise disjoint (no voxel mass appears in two classes).
  - Blocked-by: 0f06zzr (Implement two-view voxel carving Metal kernel + Swift dispatcher)
  - Requirements: [9.5](requirements.md#9.5)

- [x] 29. Write tests for inter-class occlusion detector (§6.8) <!-- id:0f06zzv -->
  - Single-pass O(W·H) 4-neighbour scan.
  - Synthesise depth-discontinuity boundary > 10 mm between two food classes; assert detector returns true.
  - Assert returns false on flat or single-class boundaries.
  - Blocked-by: 0f06zzt (Implement single-view height-field Metal kernel + Swift dispatcher)
  - Requirements: [13.2](requirements.md#13.2)

- [x] 30. Implement inter-class occlusion detector inside height-field kernel <!-- id:0f06zzw -->
  - Lives inside the §6.7 Metal kernel so depth + label data are already in GPU memory.
  - Returns boolean flag consumed by σ_occl in §6.8.
  - Blocked-by: 0f06zzv (Write tests for inter-class occlusion detector (§6.8))
  - Requirements: [13.2](requirements.md#13.2)

- [x] 31. Write tests for voxel-grid sizing (§6.10) <!-- id:0f06zzx -->
  - Test bbox back-projection through π_sup using ray–plane intersection.
  - Test `ceil(extent/edge/8)*8` rounding (multiples of 8 for Metal threadgroups).
  - Test gravity-aligned axes: axis_z = −gravity, axis_y = axis_z × axis_x.
  - Test 360 mm horizontal cap and 120 mm vertical extent.
  - Test origin = food-silhouette centroid projected onto π_sup.
  - Blocked-by: 0f06zzk (Implement metric scale resolver (pure function))
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3)

- [x] 32. Implement voxel-grid sizing function <!-- id:0f06zzy -->
  - Pure function consumed by both two-view and single-view paths to define grid extents and origin.
  - Returns `VoxelGridSummary` ready for persistence.
  - Blocked-by: 0f06zzx (Write tests for voxel-grid sizing (§6.10))
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3)

- [x] 33. Write tests for mask matching across views (§6.11) <!-- id:0f06zzz -->
  - Test classes_in_view_1 ∩ classes_in_view_2 → matched_classes.
  - Test symmetric difference → single_view_only_classes flagged with σ_view = 0.75 per Req 10.2.
  - Blocked-by: 0f06zzm (Implement segmenter pre/post-processing pipeline)
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)

- [x] 34. Implement mask matching (class-equivalence) <!-- id:0f07000 -->
  - Pure function; simple class-label matching only (no Hungarian / spatial matching in v1).
  - Output consumed by §6.6 voxel kernel and §6.8 confidence factors.
  - Blocked-by: 0f06zzz (Write tests for mask matching across views (§6.11))
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)

## Database Macros and Confidence

- [x] 35. Write tests for `FoodDatabase` queries with IFCDB overlay merge <!-- id:0f07001 -->
  - Test CoFID-only lookup returns base values.
  - Test ATTACH + COALESCE merge query from design §4.1 returns overlay-where-present, base-otherwise.
  - Test `entry(for:edition:)` honours per-meal database edition (Decision 24).
  - Test density and macro coefficients are returned in canonical units (g/cm³, g per 100 g).
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.4](requirements.md#11.4), [11.5](requirements.md#11.5), [11.6](requirements.md#11.6), [11.7](requirements.md#11.7), [11.8](requirements.md#11.8), [11.9](requirements.md#11.9), [11.10](requirements.md#11.10)

- [x] 36. Implement `FoodDatabase` via GRDB.swift (CoFID + IFCDB overlay) <!-- id:0f07002 -->
  - GRDB connection to bundled `food_db.sqlite`; ATTACH `ifcdb_overlay.sqlite` when overlay enabled in settings.
  - Build CoFID + IFCDB SQLite assets from authoritative source data; bundle in app binary (Decision 27).
  - Persist `BetaCorrectionTable` integration: read β_c and `betaCalibrationStatus` per class per edition.
  - Blocked-by: 0f07001 (Write tests for `FoodDatabase` queries with IFCDB overlay merge)
  - Requirements: [10.1](requirements.md#10.1), [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.4](requirements.md#11.4), [11.5](requirements.md#11.5), [11.6](requirements.md#11.6), [11.7](requirements.md#11.7), [11.8](requirements.md#11.8), [11.9](requirements.md#11.9)

- [x] 37. Write tests for `Macros` calculation (Req 12) <!-- id:0f07003 -->
  - Test per-class `m_c = V_c · ρ_c` (cm³ × g/cm³ = g).
  - Test `C_c = m_c · κ_c / 100`.
  - Test meal-total `C_meal = Σ C_c` displayed rounded to 1 g (Req 12.4) but persisted at full precision (Req 12.5).
  - Test clinical macros (energy, protein, fat, fibre) computed but not surfaced to display per Req 12.6.
  - Blocked-by: 0f07002 (Implement `FoodDatabase` via GRDB.swift (CoFID + IFCDB overlay))
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [12.3](requirements.md#12.3), [12.4](requirements.md#12.4), [12.5](requirements.md#12.5), [12.6](requirements.md#12.6), [12.7](requirements.md#12.7), [12.8](requirements.md#12.8)

- [x] 38. Implement `Macros` module (per-class formulas + meal totals) <!-- id:0f07004 -->
  - Pure function module per design §3.8 / §6 macronutrient formulas.
  - Output `MacroResult` with per-class breakdown and clinical totals.
  - Blocked-by: 0f07003 (Write tests for `Macros` calculation (Req 12))
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [12.3](requirements.md#12.3), [12.4](requirements.md#12.4), [12.5](requirements.md#12.5), [12.6](requirements.md#12.6), [12.7](requirements.md#12.7), [12.8](requirements.md#12.8)

- [x] 39. Write tests for `Confidence` combination (§6.8) <!-- id:0f07005 -->
  - Test geometric mean `(σ_s_tilde · σ_seg_tilde · σ_geom_tilde)^(1/3)`.
  - Test ε = 0.05 floor per top-level input; σ_geom is product of three sub-factors NOT individually floored.
  - Test σ_geom_view lookup table for both capture paths per Req 13.2.
  - Test σ_geom_plane = exp(-r/5) with 0.9 penalty when card-only iteration fell back to best-of-5.
  - Test σ_geom_occl = 0.80 only on single-view path with inter-class occlusion detected.
  - Test bounds: σ_meal ∈ [ε, 1] always.
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [13.1](requirements.md#13.1), [13.2](requirements.md#13.2), [13.3](requirements.md#13.3), [13.4](requirements.md#13.4), [13.5](requirements.md#13.5), [13.6](requirements.md#13.6)

- [x] 40. Implement `Confidence` combination function <!-- id:0f07006 -->
  - Pure function consuming σ_s, σ_seg, plane fit residual, view-coverage state, and occlusion flag.
  - Persist all sub-factors to `ConfidenceResult` per Req 13.4.
  - Blocked-by: 0f07005 (Write tests for `Confidence` combination (§6.8))
  - Requirements: [13.1](requirements.md#13.1), [13.2](requirements.md#13.2), [13.3](requirements.md#13.3), [13.4](requirements.md#13.4)

## Persistence and Migration

- [x] 41. Write tests for SQLite schema + `MealRecord` save/load round-trip <!-- id:0f07007 -->
  - Test creation of meals / meal_classes / meal_artefacts / corrections / meta tables on first launch.
  - Test save → reload → deep-equal MealRecord (protobuf-JSON encoding, Decision 31).
  - Test denormalised columns (sigma_meal, total_carbs_g, capture_path, database_edition, palette_version) populated from MealRecord at write time.
  - Test meal_classes join table populated per class at write time.
  - Test correction append never mutates original (Req 14.2).
  - Blocked-by: 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [14.1](requirements.md#14.1), [14.2](requirements.md#14.2), [14.3](requirements.md#14.3), [14.4](requirements.md#14.4), [15.1](requirements.md#15.1), [15.2](requirements.md#15.2), [15.3](requirements.md#15.3), [15.4](requirements.md#15.4), [15.5](requirements.md#15.5), [15.6](requirements.md#15.6), [15.7](requirements.md#15.7), [18.4](requirements.md#18.4)

- [x] 42. Implement `Persistence` module (SQLite via GRDB + protobuf-JSON) <!-- id:0f07008 -->
  - Schema migration on first launch; handle `meals.sqlite.corrupt-{ts}` quarantine path per design §5.
  - `PersistenceStore` protocol implementation per design §3.8.
  - Write meal artefacts (image, depth, mask, probs) to per-meal directory; never as SQLite blobs.
  - Blocked-by: 0f07007 (Write tests for SQLite schema + `MealRecord` save/load round-trip)
  - Requirements: [14.1](requirements.md#14.1), [14.2](requirements.md#14.2), [14.3](requirements.md#14.3), [14.4](requirements.md#14.4), [15.1](requirements.md#15.1), [15.2](requirements.md#15.2), [15.3](requirements.md#15.3), [15.4](requirements.md#15.4), [15.5](requirements.md#15.5), [15.6](requirements.md#15.6), [15.7](requirements.md#15.7), [18.4](requirements.md#18.4)

- [x] 43. ~~Write tests for `RetentionScheduler` (Req 17)~~ **DEFERRED — REMOVED** per Req §17.3 (May 2026). Existing tests should be deleted alongside Task 44. <!-- id:0f07009 -->
  - Test 30-day default retention with sweep at `now`-stamped meals 29/30/31 days old.
  - Test foreground `sweepIfDue()` advances `last_sweep_at_ms` and is idempotent across two consecutive sweeps within 24h.
  - Test 90-day / 365-day / indefinite settings.
  - Test artefact deletion preserves macro/confidence/metadata in `meals` row (Req 17.3).
  - Blocked-by: 0f07008 (Implement `Persistence` module (SQLite via GRDB + protobuf-JSON))
  - Requirements: [17.1](requirements.md#17.1), [17.2](requirements.md#17.2), [17.3](requirements.md#17.3), [17.4](requirements.md#17.4)

- [x] 44. ~~Implement `RetentionScheduler` with `BackgroundTasks` + foreground fallback~~ **DEFERRED — REMOVED** per Req §17.3 (May 2026). Photos now live in the user's Photos library (Task 72); the app no longer has a retention sweep. Source files to delete in follow-up. <!-- id:0f0700a -->
  - Register `BackgroundTasks` identifier; schedule daily refresh.
  - `Persistence.sweepIfDue()` runs on app foregrounding and at end of every `Pipeline.estimate(_:)` if `last_sweep_at_ms` > 24 hours old.
  - Blocked-by: 0f07009 (~~Write tests for `RetentionScheduler` (Req 17)~~ **DEFERRED — REMOVED** per Req §17.3 (May 2026). Existing tests should be deleted alongside Task 44.), deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted, deleted
  - Requirements: [17.1](requirements.md#17.1), [17.2](requirements.md#17.2), [17.3](requirements.md#17.3), [17.4](requirements.md#17.4)

- [x] 45. Write tests for archive export (zip) <!-- id:0f0700b -->
  - Test export produces single zip containing `meals.sqlite` + per-meal artefact directories.
  - Test archive is consumable (verify by re-extracting and reading back via independent SQLite tool).
  - Blocked-by: 0f07008 (Implement `Persistence` module (SQLite via GRDB + protobuf-JSON))
  - Requirements: [15.8](requirements.md#15.8)

- [x] 46. Implement archive export via `ZIPFoundation` <!-- id:0f0700c -->
  - Return file path (String, not URL per P8); UI layer wraps in URL for `UIActivityViewController`.
  - Excludes the bundled CoFID database (only meal data + artefacts go in the export).
  - Blocked-by: 0f0700b (Write tests for archive export (zip)), archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive, archive
  - Requirements: [15.8](requirements.md#15.8)

- [x] 47. Write tests for `PaletteMigrator` (Req 11.10) <!-- id:0f0700d -->
  - Test v1→v2 mapping with one mappable + one unmappable class: original retained, shadow record created, mapping path persisted.
  - Test refusal when `class_mapping_v1_v2.json` is missing or malformed.
  - Test `m_c' = V_c · ρ_new · β_new / (ρ_old · β_old)` correctly cancels old β baked into persisted V_c.
  - Blocked-by: 0f07008 (Implement `Persistence` module (SQLite via GRDB + protobuf-JSON)), 0f07002 (Implement `FoodDatabase` via GRDB.swift (CoFID + IFCDB overlay))
  - Requirements: [11.10](requirements.md#11.10)

- [x] 48. Implement `PaletteMigrator` with `ClassMappingFile` schema <!-- id:0f0700e -->
  - Load `class_mapping_v1_v2.json` per `ClassMappingFile.proto` schema.
  - Per-class mapping decision: re-derive, retain-as-old-edition, or unmappable (preserve provenance per Decision 24).
  - Surface UI message: 'N classes re-derived under v2; M classes retained under v1.'
  - Blocked-by: 0f0700d (Write tests for `PaletteMigrator` (Req 11.10))
  - Requirements: [11.10](requirements.md#11.10)

## Pipeline and App Shell

- [x] 49. Write tests for capture-path dispatch (§2.3) <!-- id:0f0700f -->
  - Test LiDAR available + plane detected + ≥80% LiDAR coverage → `single_view_lidar`.
  - Test otherwise → `two_view_sfs`.
  - Test `capturePath` field is persisted on every meal record (Req 3.8).
  - Blocked-by: 0f06zzb (Implement `CaptureKit` (AVFoundation + ARKit + Core Motion bridge)), 0f06zzg (Implement LiDAR support-plane RANSAC fitter)
  - Requirements: [3.5](requirements.md#3.5), [3.8](requirements.md#3.8), [6.5](requirements.md#6.5)

- [x] 50. Implement `Pipeline.estimate(_:)` orchestration <!-- id:0f0700g -->
  - Async pipeline running stages C–L from design §2.2 sequentially; short-circuit on refusal.
  - Dispatch volume estimator by `capturePath`.
  - Wire MetalContext.shared, FoodDatabase, Persistence, Macros, Confidence into orchestrator.
  - Blocked-by: 0f0700f (Write tests for capture-path dispatch (§2.3)), 0f06zzd (Implement P4P card-pose recovery (custom SVD-based, no OpenCV)), 0f06zzi (Implement card-only iterative support-plane fitter), 0f06zzk (Implement metric scale resolver (pure function)), 0f06zzo (Implement `CoreMLSegmenter` with ANE inference + Metal-backed probability tensor), 0f06zzr (Implement two-view voxel carving Metal kernel + Swift dispatcher), 0f06zzt (Implement single-view height-field Metal kernel + Swift dispatcher), 0f06zzy (Implement voxel-grid sizing function), 0f07000 (Implement mask matching (class-equivalence)), 0f07002 (Implement `FoodDatabase` via GRDB.swift (CoFID + IFCDB overlay)), 0f07004 (Implement `Macros` module (per-class formulas + meal totals)), 0f07006 (Implement `Confidence` combination function), 0f07008 (Implement `Persistence` module (SQLite via GRDB + protobuf-JSON))
  - Requirements: [1.5](requirements.md#1.5), [3.5](requirements.md#3.5), [3.8](requirements.md#3.8), [6.5](requirements.md#6.5), [16.1](requirements.md#16.1), [16.4](requirements.md#16.4)

- [x] 51. Write tests for `EstimationFailure` error mapping (§5) <!-- id:0f0700h -->
  - Each failure case from design §5 throws the expected enum value end-to-end.
  - Verify `Pipeline.estimate` is `async throws -> MealRecord` (not `Result<...>`).
  - Blocked-by: 0f0700g (Implement `Pipeline.estimate(_:)` orchestration)
  - Requirements: [6.5](requirements.md#6.5), [7.5](requirements.md#7.5), [13.1](requirements.md#13.1), [13.5](requirements.md#13.5)

- [x] 52. Implement `EstimationFailure` enum and refusal-message localisation hooks <!-- id:0f0700i -->
  - Closed enum mapped one-to-one with design §5 table.
  - Localised Irish-English messages keyed by enum case for UI dispatch.
  - Blocked-by: 0f0700h (Write tests for `EstimationFailure` error mapping (§5)), mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping, mapping
  - Requirements: [6.5](requirements.md#6.5), [7.5](requirements.md#7.5), [13.1](requirements.md#13.1), [13.5](requirements.md#13.5), [19.1](requirements.md#19.1)

- [x] 53. Implement SwiftUI app shell with placeholder views and `CaptureFlowDelegate` <!-- id:0f0700j -->
  - `App.swift`, `CaptureFlowView`, `ResultView`, `SettingsView` as placeholders (UI design deferred to specs/ui per design §10).
  - Expose `CaptureFlowDelegate` protocol (didUpdateTilt, didUpdateLiDARCoverage, didDetectInterClassOcclusion, didProduceEstimate).
  - Confirm app builds and launches on iPhone 12 Pro+ device.
  - Blocked-by: 0f0700g (Implement `Pipeline.estimate(_:)` orchestration)
  - Requirements: [1.1](requirements.md#1.1), [3.1](requirements.md#3.1), [3.5](requirements.md#3.5), [13.5](requirements.md#13.5)

- [x] 54. ~~Implement Settings view (retention period, IFCDB overlay toggle)~~ **SUPERSEDED by Task 73** per §0 (May 2026). Retention and IFCDB toggle removed; Settings view rewritten in Task 73. <!-- id:0f0700k -->
  - Blocked-by: 0f0700j (Implement SwiftUI app shell with placeholder views and `CaptureFlowDelegate`)

## Harness and Calibration — Feature-flagged off (`HARNESS_ENABLED`)

- [x] 55. Define `HARNESS_ENABLED` compile flag in `Package.swift` and restore deleted harness file tree <!-- id:0f07011 -->
  - Add the `HarnessCLI` executable target back to `Package.swift` with `swiftSettings: [.define("HARNESS_ENABLED")]`.
  - Add the `HarnessCLITests` test target with the same `swiftSettings` define.
  - Add a `HarnessCore` library target consumed by both, with the same `.define("HARNESS_ENABLED")` so its sources compile under the flag when built as part of the harness graph.
  - Confirm the iOS app product (`App` / `MedataCore` library) has NO target that defines `HARNESS_ENABLED` in any configuration; reviewer-verifiable by grepping `Package.swift`.
  - Restore deleted files to the tree as empty stubs guarded by `#if HARNESS_ENABLED ... #endif`: `HarnessCore/AccuracyHarness.swift`, `BetaCalibrator.swift`, `FixtureLoader.swift`, `FixtureRunner.swift`, `SegBench.swift`, `HarnessCLI/main.swift`, and the `MedataCore/Tests/HarnessCLITests/` test files. The actual implementations are restored by tasks 55–64; this task only restores the file scaffolding and the gate.
  - Tests: `swift build` (iOS app) succeeds and links no harness symbols; `swift build --target HarnessCLI` succeeds and `nm` shows `AccuracyHarness` symbols only in the harness binary.
  - Decision: 41
  - Requirements: [21.9](requirements.md#21.9)

- [x] 56. Write tests for `MealFixture` .proto round-trip <!-- id:0f0700l -->
  - Test encode → decode → bit-equal for `MealFixture.proto` per design §7.3.
  - Test `segmenter_checkpoint_sha256` guard: fixture refused if hash mismatches bundled segmenter.
  - All test sources wrapped in `#if HARNESS_ENABLED`; live in the `HarnessCLITests` target whose `swiftSettings` define `HARNESS_ENABLED`.
  - Blocked-by: 0f07011 (Define `HARNESS_ENABLED` compile flag in `Package.swift` and restore deleted harness file tree), 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [20.1](requirements.md#20.1), [21.1](requirements.md#21.1), [21.9](requirements.md#21.9)

- [x] 57. Restore `HarnessCLI` fixture loader under `#if HARNESS_ENABLED` <!-- id:0f0700m -->
  - SPM executable target on macOS reads MealFixture batches from `medata-fixtures` repo.
  - Exposes `--fixtures-dir`, `--edge`, `--checkpoint-sha256` CLI flags.
  - Source file `HarnessCore/FixtureLoader.swift` wrapped in `#if HARNESS_ENABLED`; `HarnessCLI/main.swift` wrapped similarly.
  - Verify: `swift build` (iOS app product) succeeds without harness; `swift build --target HarnessCLI` succeeds with harness.
  - Blocked-by: 0f07011 (Define `HARNESS_ENABLED` compile flag in `Package.swift` and restore deleted harness file tree), 0f0700l (Write tests for `MealFixture` .proto round-trip)
  - Requirements: [20.1](requirements.md#20.1), [21.1](requirements.md#21.1), [21.5](requirements.md#21.5), [21.7](requirements.md#21.7), [21.9](requirements.md#21.9)

- [x] 58. Write tests for β_c calibration log-residual closed form (§6.9) <!-- id:0f0700n -->
  - Synthetic dataset where ground-truth β is known; assert recovered β_c within 5% (Decision 30 log-residual form).
  - Test path-specific clamp: (0, 1] for two-view, (0, 1.5] for single-view (M7).
  - Test 30-meal minimum per class → `calibrated`; below → `uncalibrated_pooled` with β_pool fallback.
  - Test pooled fallback: pool meals from under-sampled classes; if pool < 30 meals, β = 1.0 with `uncalibrated_unity`.
  - Test `predicted < 1e-9` denominator-collapse refusal.
  - Test sources wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f07011 (Define `HARNESS_ENABLED` compile flag in `Package.swift` and restore deleted harness file tree), 0f06zz4 (Generate Swift sources from .proto and integrate `swift-protobuf`)
  - Requirements: [11.7](requirements.md#11.7), [21.4](requirements.md#21.4), [21.9](requirements.md#21.9)

- [x] 59. Restore β_c calibration in `HarnessCLI` under `#if HARNESS_ENABLED` <!-- id:0f0700o -->
  - Stratified 60/40 cal/eval split per meal (path + dominant class).
  - Per-class log-residual fit; pooled fallback if applicable.
  - Emit new `food_db.sqlite` with calibrated β_c values + new edition string.
  - Output is for developer inspection only — promoting it into the shipping app's bundled assets is a deliberate later step, not automatic (per Decision 41).
  - `HarnessCore/BetaCalibrator.swift` wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f0700n (Write tests for β_c calibration log-residual closed form (§6.9)), 0f0700m (Restore `HarnessCLI` fixture loader under `#if HARNESS_ENABLED`), 0f07002 (Implement `FoodDatabase` via GRDB.swift (CoFID + IFCDB overlay))
  - Requirements: [11.4](requirements.md#11.4), [11.7](requirements.md#11.7), [21.4](requirements.md#21.4), [21.9](requirements.md#21.9)

- [x] 60. Write tests for accuracy harness (MAPE, MAE, per-class breakdown) <!-- id:0f0700p -->
  - Test point-estimate MAPE and MAE computation (Decision 23: bar is point estimate, CI is informational).
  - Test per-class breakdown distinguishes calibrated / uncalibrated_pooled / uncalibrated_unity (Req 21.4).
  - Test per-stage latency stats are produced for both `capturePath` values (Req 21.5).
  - Test sources wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f0700m (Restore `HarnessCLI` fixture loader under `#if HARNESS_ENABLED`)
  - Requirements: [21.2](requirements.md#21.2), [21.3](requirements.md#21.3), [21.4](requirements.md#21.4), [21.5](requirements.md#21.5), [21.7](requirements.md#21.7), [21.8](requirements.md#21.8), [21.9](requirements.md#21.9)

- [x] 61. Restore accuracy harness mode in `HarnessCLI` under `#if HARNESS_ENABLED` <!-- id:0f0700q -->
  - Run full pipeline (camera + segmenter mocked from fixtures) over eval subset.
  - Emit JSON report for developer inspection: MAPE, MAE, per-class, latency-per-stage, mIoU.
  - **No CI gate** in v1 (per Decision 41 and Req 21.7). The developer interprets the MAPE < 20% / MAE ≤ 25 g reference in Req 21.3 informationally.
  - `HarnessCore/AccuracyHarness.swift` and `FixtureRunner.swift` wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f0700p (Write tests for accuracy harness (MAPE, MAE, per-class breakdown)), harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, harness, 0f0700g (Implement `Pipeline.estimate(_:)` orchestration), 0f0700o (Restore β_c calibration in `HarnessCLI` under `#if HARNESS_ENABLED`)
  - Requirements: [21.2](requirements.md#21.2), [21.3](requirements.md#21.3), [21.4](requirements.md#21.4), [21.5](requirements.md#21.5), [21.6](requirements.md#21.6), [21.7](requirements.md#21.7), [21.8](requirements.md#21.8), [21.9](requirements.md#21.9)

- [x] 62. Write tests for calibration round-trip (§6.13) <!-- id:0f0700r -->
  - Run β_c calibration on cached fixtures; evaluate full pipeline on disjoint eval subset.
  - Assert MAPE and MAE bar met on synthetic test set with known ground truth.
  - Test sources wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f0700o (Restore β_c calibration in `HarnessCLI` under `#if HARNESS_ENABLED`), 0f0700q (Restore accuracy harness mode in `HarnessCLI` under `#if HARNESS_ENABLED`)
  - Requirements: [11.7](requirements.md#11.7), [21.3](requirements.md#21.3), [21.4](requirements.md#21.4), [21.9](requirements.md#21.9)

- [x] 63. Restore calibration round-trip mode in `HarnessCLI` under `#if HARNESS_ENABLED` <!-- id:0f0700s -->
  - `harness calibrate-and-eval` subcommand: end-to-end calibration → emit DB → run accuracy harness against the new DB.
  - Catches segmenter retrain → β_c invalidation regressions (per design §6.13).
  - Subcommand wrapped in `#if HARNESS_ENABLED` along with the rest of `HarnessCLI/main.swift`.
  - Blocked-by: 0f0700r (Write tests for calibration round-trip (§6.13))
  - Requirements: [11.7](requirements.md#11.7), [21.3](requirements.md#21.3), [21.4](requirements.md#21.4), [21.9](requirements.md#21.9)

- [x] 64. Write tests for segmenter mIoU bench (Req 8.9) <!-- id:0f0700t -->
  - Test mean IoU over 24 food classes (excludes background, unknown_food, unsupported_liquid per Decision 14).
  - Test per-class IoU and confusion matrix output.
  - Verify behaviour when mean food-class mIoU < 0.60 (warns the developer; does NOT fail CI per Decision 41).
  - Test sources wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f06zzo (Implement `CoreMLSegmenter` with ANE inference + Metal-backed probability tensor)
  - Requirements: [8.9](requirements.md#8.9), [21.9](requirements.md#21.9)

- [x] 65. Restore segmenter mIoU bench mode in `HarnessCLI` under `#if HARNESS_ENABLED` <!-- id:0f0700u -->
  - `harness seg-bench` subcommand consuming a held-out segmenter test set.
  - Reports IoU + confusion matrix for developer inspection.
  - **No CI gate** in v1 — the 0.60 mIoU floor is the developer's quality reference, not enforced.
  - `HarnessCore/SegBench.swift` wrapped in `#if HARNESS_ENABLED`.
  - Blocked-by: 0f0700t (Write tests for segmenter mIoU bench (Req 8.9))
  - Requirements: [8.9](requirements.md#8.9), [21.9](requirements.md#21.9)

## Performance and Cleanup

- [x] 66. ~~Write XCTest performance assertion: single-view P95 ≤ 1000 ms~~ **DEFERRED — REPLACED** by Task 74's single 30 s soft check. <!-- id:0f0700v -->
  - On-device XCTest with `XCTClockMetric` over 10 runs against a fixture batch.
  - Per Req 16.1 / 16.2 single-view path budget.
  - Mark test as device-only; CI runs on tethered iPhone 12 Pro per Req 16.7.
  - Blocked-by: 0f0700g (Implement `Pipeline.estimate(_:)` orchestration)
  - Requirements: [16.1](requirements.md#16.1), [16.2](requirements.md#16.2), [16.7](requirements.md#16.7), [21.5](requirements.md#21.5)

- [x] 67. ~~Write XCTest performance assertion: two-view P95 ≤ 1800 ms~~ **DEFERRED — REPLACED** by Task 74's single 30 s soft check. <!-- id:0f0700w -->
  - Same harness as task 65, two-view fixture batch.
  - Per Req 16.1 / 16.3 two-view path budget.
  - Blocked-by: 0f0700g (Implement `Pipeline.estimate(_:)` orchestration)
  - Requirements: [16.1](requirements.md#16.1), [16.3](requirements.md#16.3), [16.7](requirements.md#16.7), [21.5](requirements.md#21.5)

- [x] 68. ~~Implement performance harness instrumentation (per-stage timing)~~ **DEFERRED — REMOVED**: signpost intervals retained for ad-hoc Instruments inspection only; no XCTest assertions. <!-- id:0f0700x -->
  - OSSignpost intervals around each pipeline stage (CardDetection, SupportPlane, MetricScale, Segmentation, Volume, Macros, Confidence, Persistence).
  - Surface to dev-build only (Req 16.5 CPU fallback / dev-build gates).
  - Blocked-by: 0f0700g (Implement `Pipeline.estimate(_:)` orchestration)
  - Requirements: [16.2](requirements.md#16.2), [16.3](requirements.md#16.3), [16.5](requirements.md#16.5), [16.7](requirements.md#16.7)

- [x] 69. Write tests for Irish/British English spelling linter <!-- id:0f0700y -->
  - Test rejects 'recognized', 'color', 'fiber', 'favorite', 'center'.
  - Test allows 'recognised', 'colour', 'fibre', 'favourite', 'centre'.
  - Blocked-by: 0f06zz7 (Create Swift Package + Xcode project skeleton)
  - Requirements: [19.1](requirements.md#19.1), [19.2](requirements.md#19.2)

- [x] 70. Implement spelling linter as CI step <!-- id:0f0700z -->
  - Shell script or Swift CLI scanning `*.swift` and bundled string catalogs.
  - Runs in CI; failure blocks merge.
  - Blocked-by: 0f0700y (Write tests for Irish/British English spelling linter)
  - Requirements: [19.1](requirements.md#19.1), [19.2](requirements.md#19.2)

- [x] 71. Move SvelteKit MVP source to `legacy/` directory <!-- id:0f07010 -->
  - Move existing Svelte source tree to `legacy/svelte-mvp/` (Req 1.4).
  - Update root README to point at the new iOS app.
  - Blocked-by: 0f06zz7 (Create Swift Package + Xcode project skeleton)
  - Requirements: [1.4](requirements.md#1.4)

## v1 Adjustments — New Tasks (May 2026)

- [x] 72. Replace auto-derived capture path with persistent `CaptureMode` toggle
  - Add `CaptureMode` enum (`single`, `double`) in `MedataCore`.
  - Add `SettingsKeys.captureMode` UserDefaults key; default `.double` on first install.
  - Capture view: persistent segmented control above the shutter, single tap to switch; ignores in-flight estimations (matches §7.4 behaviour).
  - `Pipeline.estimate(_:mode:)` takes mode explicitly; `MealRecord.capturePath` copied from `mode` at capture time.
  - Single mode disabled (greyed) on non-LiDAR hardware; selecting it with no LiDAR returns the existing Irish-English refusal.
  - Delete `derivePathHint` / LiDAR-coverage threshold dispatch and the prior `.forcingTwoView` transient state.
  - Tests: round-trip UserDefaults persistence; control reflects current mode; Pipeline receives the correct mode for each capture; switching mode mid-session is ignored during in-flight estimation.
  - Decision: 35
  - Requirements: [3.5](requirements.md#3.5), [3.8](requirements.md#3.8)

- [x] 73. Migrate photo storage to PhotoKit (`PHAsset.localIdentifier`)
  - On successful capture, persist the original RGB nadir frame to the user's Photos library via `PHPhotoLibrary.shared().performChanges`; record the returned `PHAsset.localIdentifier` as `MealRecord.photoAssetID` and `meals.photo_asset_id`.
  - Request `PHAuthorizationStatus(for: .addOnly)` on first capture; show Irish-English permission-denied banner if refused (estimation still completes; `photoAssetID = ""`).
  - SQLite migration: add `photo_asset_id TEXT NOT NULL DEFAULT ''` column to `meals`; drop `image` artefact rows from existing meals (they remain on disk; cleanup is a separate dev task).
  - Remove image-bytes write from `Persistence` and from `RawFrameMetadata.imageFilename`.
  - Result view: fetch `PHAsset` by identifier; render thumbnail via `PHImageManager` if the user has full Photos access; otherwise show a placeholder.
  - Tests: PhotoKit add succeeds → identifier persisted and re-fetchable; user denies → meal saved with empty identifier; library access revoked between capture and history view → graceful placeholder.
  - Decision: 37
  - Requirements: [17.1](requirements.md#17.1), [17.2](requirements.md#17.2), [17.3](requirements.md#17.3)

- [x] 74. Rewrite Settings view; bundle CoFID + AFCD; remove IFCDB
  - Delete `SettingsKeys.ifcdbOverlayEnabled`, `SettingsKeys.retentionDays`, the Settings retention picker, and the IFCDB toggle.
  - Bundle `cofid_db.sqlite` and `afcd_db.sqlite` as fixed read-only assets; `FoodDatabase` ATTACHes both at launch and applies the CoFID-wins COALESCE lookup from design §4.1.
  - About / Legal screen: list both source attributions ("Macros: CoFID 2024 + AFCD 2024" + the respective licence statements).
  - Update `database_edition` string written into `MealRecord` and `meals.database_edition`.
  - Delete the previous IFCDB overlay file from the bundle.
  - Tests: lookup priority (CoFID wins for shared classes); lookup falls through to AFCD when CoFID lacks a class; database_edition string matches the bundled pair.
  - Decision: 39
  - Requirements: [11.1](requirements.md#11.1), [11.4](requirements.md#11.4)

- [x] 75. Narrow hardware floor + replace per-stage perf checks with single 30 s soft check
  - Update Info.plist `MinimumOSVersion` to 26.5; deployment target → iOS 26.5.
  - Remove the iPhone 12 Pro device-allow guard; document iPhone 13 Pro Max as the only supported device. Update Irish-English unsupported-device message.
  - Delete tasks 65/66's per-path XCTClockMetric tests; add a single end-to-end XCTest that asserts `< 30 s` for both `single` and `double` modes on the v1 device.
  - Keep `os_signpost` intervals around pipeline stages for ad-hoc Instruments inspection only (no assertions).
  - Tests: end-to-end-under-30 s for both modes on the v1 device; unsupported-device guard surfaces the new message on simulator / earlier hardware.
  - Decision: 40
  - Requirements: [1.2](requirements.md#1.2), [16.1](requirements.md#16.1)

## Phase 1 — Device MVP (RUNNING DEVICE)

- [x] 76. Fix `PipelineEstimator` protocol signature to include `mode:` <!-- id:0f07014 -->
  - Add `mode: CaptureMode` parameter to `PipelineEstimator.estimate` in `MedataCore/Sources/Pipeline/PipelineEstimator.swift` so the protocol matches the call site in `CaptureFlowModel` and the stand-in in `App.swift`.
  - Update `Pipeline.estimate` and any other conformers (`StallingPipeline`, test doubles in `Tests/PipelineTests/`).
  - Tests: existing `Tests/PipelineTests/` and `Tests/CaptureFlowTests/` must compile against the protocol and continue to pass; Xcode build (not just `swift build`) succeeds.
  - Decision: 42
  - Requirements: [23.1](requirements.md#23.1), [23.5](requirements.md#23.5)

- [x] 77. Write StubInferenceEngine tests <!-- id:0f07012 -->
  - In `MedataCore/Tests/SegmentationTests/StubInferenceEngineTests.swift`: probability tensor is deterministic across two runs with the same `ClassPalette`; argmax of every pixel equals `dominantClass`; mass at `dominantClass` ≥ 0.99 and remaining classes sum to ≤ 0.01.
  - FP16 layout (HWC row-major) matches `ProbabilityTensor` portable contract from design §3.5.
  - `infer(image:)` completes in under 50 ms on the v1 device (per Req §23.2).
  - Decision: 42
  - Requirements: [23.2](requirements.md#23.2), [23.5](requirements.md#23.5)

- [x] 78. Implement StubInferenceEngine <!-- id:0f07013 -->
  - Implement `StubInferenceEngine` as a `struct: SegmenterInferenceEngine` in `MedataCore/Sources/Segmentation/StubInferenceEngine.swift`.
  - Write the FP16 tensor directly without invoking image pre-processing (per design §3.5). No `.mlpackage`, no Core ML import.
  - Holds `palette: ClassPalette` and `dominantClass: Int = 0`.
  - Decision: 42
  - Blocked-by: 0f07012 (Write StubInferenceEngine tests)
  - Requirements: [23.2](requirements.md#23.2), [8.10](requirements.md#8.10)

- [x] 79. Define `DEV_STUB_SEGMENTER` Swift compile flag in `Package.swift` <!-- id:0f07015 -->
  - In `Package.swift`, add `.define("DEV_STUB_SEGMENTER", .when(configuration: .debug))` to the iOS app target's `swiftSettings`. Do NOT define it in Release.
  - Document the flag at the top of `Package.swift` alongside `HARNESS_ENABLED` (Decision 41).
  - Tests: `swift build` succeeds with and without the flag; `#if DEV_STUB_SEGMENTER` blocks compile correctly in both modes.
  - Decision: 42
  - Requirements: [23.4](requirements.md#23.4)

- [x] 80. Implement `Pipeline.makeForDevice(store:)` factory <!-- id:0f07016 -->
  - Add `static func makeForDevice(store: any PersistenceStore, palette: ClassPalette = .v1Standard) throws -> Pipeline` in `MedataCore/Sources/Pipeline/Pipeline.swift`.
  - Selects engine via `#if DEV_STUB_SEGMENTER` -> `StubInferenceEngine`, else `CoreMLInferenceEngine`.
  - Stamps `segmenterSource` as `"dev_stub"` or `"coreml_<modelVersion>"`. Constructs `GRDBFoodDatabase.bundled()`.
  - Tests: under DEV_STUB_SEGMENTER, factory returns a Pipeline whose end-to-end estimate succeeds against a fixture `CaptureResult` and produces a `MealRecord` with `segmenterSource == "dev_stub"`; without the flag, factory throws on missing `food_segmenter.mlpackage` (Phase 3 will bundle the model).
  - Decision: 42
  - Blocked-by: 0f07014 (Fix `PipelineEstimator` protocol signature to include `mode:`), 0f07013 (Implement StubInferenceEngine), 0f07015 (Define `DEV_STUB_SEGMENTER` Swift compile flag in `Package.swift`)
  - Requirements: [23.1](requirements.md#23.1), [23.5](requirements.md#23.5), [23.6](requirements.md#23.6)

- [x] 81. Replace `PendingPipeline` in App.swift with `Pipeline.makeForDevice` <!-- id:0f07017 -->
  - Delete the `PendingPipeline` stand-in in `App/App.swift`.
  - Replace `pipeline: PendingPipeline()` with `pipeline: try! Pipeline.makeForDevice(store: store)` in the `MedataApp.init` non-UI-test path.
  - Keep the `UITestSupport` stand-ins (`StallingPipeline`) — they exercise model state transitions, not the pipeline contract.
  - Tests: existing XCUITests in `MeData/UITests/` continue to pass under `-uitest`; app launches without crash on simulator and device.
  - Decision: 42
  - Blocked-by: 0f07016 (Implement `Pipeline.makeForDevice(store:)` factory)
  - Requirements: [23.1](requirements.md#23.1)

- [x] 82. Persist `segmenterSource` on `MealRecord` and SQLite `meals` <!-- id:0f07018 -->
  - Add `segmenterSource: String` to `MealRecord` (PortableContracts) and `segmenter_source TEXT NOT NULL DEFAULT ''` column to `meals` table via SQLite migration in `GRDBPersistenceStore`.
  - `Pipeline` writes the factory-stamped value at persist time (per task 80). The .proto `MealRecord` definition gains the same field.
  - Tests: round-trip write -> read of `segmenterSource` for both `dev_stub` and `coreml_v0.1` values; migration on an existing DB without the column adds the column with empty-string default; .proto round-trip serialises and reads the field.
  - Decision: 42
  - Requirements: [23.6](requirements.md#23.6)

- [x] 83. Add Irish-English placeholder banner on result view (gated on `segmenterSource == "dev_stub"`) <!-- id:0f07019 -->
  - In `App/ResultView.swift`, render a high-contrast Irish-English banner (system .yellow background, .black foreground, top-of-screen, persistent) when `record.segmenterSource == "dev_stub"`.
  - Copy: "Placeholder estimate. The food recogniser is a development stub — the carbohydrate value is not a real measurement."
  - Banner is NOT computed from `#if DEV_STUB_SEGMENTER` so Phase 1 records still surface the banner when viewed under a later Phase 3 build (per design §3.5).
  - Tests: `ResultView` shows the banner for a `MealRecord` with `segmenterSource = "dev_stub"`; banner is absent for `segmenterSource = "coreml_v0.1"`.
  - Decision: 42
  - Blocked-by: 0f07018 (Persist `segmenterSource` on `MealRecord` and SQLite `meals`)
  - Requirements: [23.3](requirements.md#23.3)
