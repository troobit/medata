# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (Research spec — Harness and Calibration phase, tasks 55–65)

- `HarnessCore/AccuracyHarness.swift`, `BetaCalibrator.swift`, `FixtureLoader.swift`, `FixtureRunner.swift`, `SegBench.swift` — restored as `HarnessCore` SPM library target with every file wrapped in `#if HARNESS_ENABLED ... #endif`. Implements the §6.9 β_c log-residual calibration, §7.3 fixture-driven pipeline runner, §7.3 accuracy harness (MAPE, MAE, per-class breakdown, per-stage latency), and §7.5 segmenter mIoU bench per Decision 41.

### Changed (Research spec — Harness and Calibration phase, tasks 55–65)

- `Package.swift` — added `HarnessCore` library, `HarnessCLI` executable, and `HarnessCLITests` test target. All three define `HARNESS_ENABLED` only in their own `swiftSettings` so the iOS app product (`MedataCore` / `Pipeline`) links zero harness code (Decision 41). `HarnessCLITests` deps expanded to include `Pipeline`, `CardDetection`, `CaptureKit`, `Persistence` to satisfy the landed `PipelinePerformanceTests` imports.
- `HarnessCLI/main.swift` — entire file wrapped in `#if HARNESS_ENABLED ... #endif`.
- `MedataCore/Tests/HarnessCLITests/*.swift` (6 files) — wrapped in `#if HARNESS_ENABLED ... #endif` per Req 21.9.

### Fixed (Camera input rendering on iPhone 13 Pro Max)

- `App/ARPreviewView.swift` — added `ensureSessionConfigured()` method called from `makeUIView()` to synchronously configure and run the ARSession before ARView attempts to render. This eliminates a race condition where the view tried to display camera input before the session was initialized, causing FigCapture errors (err=-12710, err=-12784, err=-17281) and blank camera feed.
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — updated `start()` method to check if the session is already configured (e.g., by ARPreviewView) and skip re-running if so, while still supporting LiDAR frame semantics updates. This prevents duplicate initialization and works harmoniously with the view-layer session setup.

### Added (UI spec — end-to-end verification phase, tasks 26–28)

- `MeData/UITests/RefusalFlowUITests.swift` — XCUITest for the refusal flow (task 26, Req 10.1–10.3, 12.1–12.2): drives the flow to a refusal, asserts the banner shows `EstimationFailure.noScaleAvailable.localisedMessage` verbatim, taps "Try Again", and asserts the banner dismisses and capture re-enters `.capturing` at the retry stage.
- `MeData/UITests/BackgroundingUITests.swift` — XCUITest for §8.3 backgrounding (task 27, best-effort per Decision 12): enters `.estimating` via the `stall` pipeline, backgrounds with the Home button, foregrounds, and asserts the UI resets to `.initialising` (UI state only — a `MealRecord` may still persist).
- `MeData/UITests/InterruptionUITests.swift` — XCUITest for AR-interruption recovery (task 28, Req 16.1): emits `.began` on the interruption stream and asserts `.trackingLost`, then `.ended` and asserts recovery to `.initialising`.

### Changed (UI spec — end-to-end verification phase, tasks 26–28)

- `App/App.swift` — added a `#if DEBUG` XCUITest harness (`UITestSupport`, `UITestHarness`, `UITestCaptureEngine`, `UITestControlPanel`) activated by the `-uitest` launch argument. The AR-gated flow can't reach `.ready` on the simulator, so the harness injects a gated `CaptureEngine`, a launch-arg-selected stub pipeline (`-uitestPipeline refuse|stall`), and an interruption `AsyncStream` it owns; hidden accessibility-identified controls drive the model's public commands. Not compiled into release builds.
- `App/CaptureFlowView.swift`, `App/RefusalBanner.swift` — added accessibility identifiers (`shutter`, `hint.{initialising,trackingLost,estimating,capturing}`, `refusal.message`, `refusal.tryAgain`) so the XCUITests can query state.

### Added (UI spec — UI components phase, tasks 12–24)

- `App/CaptureFlowModel.swift` — `@Observable @MainActor` orchestrator conforming to `CaptureFlowDelegate` (tasks 12–13). Implements the full state machine from design.md, the path-hint freeze-at-shutter-tap rule, `Task`-wrapped estimation with `cancelInFlight()`, interruption-stream observation, scene-phase permission re-checks, and no-op delegate conformances (Decisions 9, 11).
- `App/LiveSampleObserver.swift` — `@MainActor` observer iterating `engine.frames`, computing per-frame tilt/distance/coverage via a pure `LiveSampleMath` seam and write-gating on model state (task 15).
- `App/ARPreviewView.swift` — `UIViewRepresentable` over `ARView` with `reassertDelegate()` called from both `makeUIView` and `updateUIView` to keep the engine the sole session delegate (task 17).
- `App/RefusalBanner.swift` — inline refusal-banner overlay rendering `localisedMessage` verbatim; only "Try Again" dismisses it (task 18, Decision 5).
- `App/LiveIndicatorView.swift` — child view rendering tilt/distance/coverage/path indicators from `LiveIndicatorModel` (task 19).
- `MeData/Tests/{CaptureFlowModelTests,LiveSampleObserverTests,ARPreviewViewTests,ResultViewTests}.swift` — Swift Testing suites for the state machine (~18 transition rows plus freeze/debounce/backgrounding/permission/interruption cases), per-frame maths + write-gating, delegate-reassertion guard, and confidence-pill thresholds (tasks 12, 14, 16, 20).

### Changed (UI spec — UI components phase, tasks 12–24)

- `App/CaptureFlowView.swift` — rewritten as the `NavigationStack` root composing the AR preview, live indicators, shutter, refusal overlay, and settings entry, with the permission-denied branch and `MealRecord` navigation destination (task 23).
- `App/ResultView.swift` — rewritten to show rounded total carbs and a three-state confidence pill with an uncertain-estimate Retake prompt below σ 0.60; no per-class breakdown or clinical macros (task 21, Decision 3).
- `App/SettingsView.swift` — added the Export-archive control calling `PersistenceStore.exportArchive()` and presenting `ShareSheet` via `.sheet(item:)` (task 22).
- `MeData/MeData.xcodeproj/project.pbxproj` — wired the new `App/*.swift` files into the `MeData` target.

### Added (UI spec — asset generation phase, task 25)

- `tools/appicon/generate.sh` — renders `static/icon.svg` to all Apple-required AppIcon sizes (40–1024 px) via `rsvg-convert`/`sips` and writes the matching `Contents.json` (task 25, Req 15.2).
- `MeData/MeData/Assets.xcassets/AppIcon.appiconset/icon-*.png` — generated AppIcon PNGs (40, 58, 60, 80, 87, 120, 180, 1024).
- `docs/agent-notes/appicon-pipeline.md` — notes on the icon-generation pipeline.

### Added (UI spec — agent notes)

- `docs/agent-notes/ui-capture-flow.md` — architecture, gotchas, test setup, and the build-path caveat for the `App/` capture flow.

### Added (UI spec — UI building blocks phase, tasks 5–11)

- `App/Colors.swift` — brand colour tokens (task 5, Req 15.1, 9.2): `Color.medataAccent = #63ff00`, plus `confidenceHigh` (= accent), `confidenceModerate` (.orange), and `confidenceLow` (.red) for the result-view confidence pill.
- `App/GatingSnapshot.swift` — `struct GatingSnapshot: Equatable, Sendable` (task 6, Req 4.1, 7.2): carries `pathHint`, `tiltInRange`, `distanceCm`, `lidarCoveragePercent` plus `withPath(_:)` helper. Frozen at shutter-tap to satisfy the design's path-hint freeze rule.
- `App/CaptureState.swift` — nine-case `CaptureState` enum plus `CaptureStage` and `PermissionSubject` sub-enums (task 7, Req 1.6, 5.5, 5.6, 13.3, 16.1). Manual `Equatable` conformance because `CaptureResult` (and its inner `RawFrame`) is not `Equatable`; the `.estimating` case compares case-only.
- `MeData/Tests/CapturePathDeciderTests.swift` — Swift Testing boundary table for `CapturePathDecider.decide` (task 8, Req 4.1): five rows covering (no LiDAR), (LiDAR + 0% / 79.99% / 80% / 100% coverage).
- `App/CapturePathDecider.swift` — pure decider `decide(supportsLiDAR:latestCoveragePercent:) -> CapturePath` (task 9, Req 4.1); returns `.singleViewLidar` only when LiDAR is present and coverage ≥ 80%, else `.twoViewSfS`.
- `App/LiveIndicatorModel.swift` — `@Observable @MainActor final class LiveIndicatorModel` (task 10, Req 2.1, 3.1, 4.1) holding `liveTiltDegrees`, `liveDistanceCm`, `liveLiDARCoveragePercent`. Split from `CaptureFlowModel` per design.md so 60 Hz frame-stream writes don't retrigger `CaptureFlowView.body`.
- `App/ShareSheet.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController` (task 11, Req 11.4) for Settings → Export archive.

### Changed (UI spec — UI building blocks phase, tasks 5–11)

- `MeData/MeData.xcodeproj/project.pbxproj` — wired the six new `App/*.swift` files into the `MeData` target's `Sources` build phase (file references under `SOURCE_ROOT` via `../App/...`, matching the existing pattern for `App.swift`, `CaptureFlowView.swift`, etc.).
- `specs/ui/tasks.md` — marked tasks 5–11 complete via `rune complete`.

### Added (UI spec — SPM prerequisites phase, tasks 1–4)

- `MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift` — contract tests for the new `ARKitCaptureEngine` accessors (task 1): delegate identity on init, identical `arSession` instance, delegate preservation after `frames` subscription, interruption ordering (`.began` → `.ended`), cancellation cleanup on both streams, and multi-subscriber fan-out. Guarded with `#if canImport(ARKit) && os(iOS)`. ARFrame end-to-end yield is documented as on-device-only because `ARFrame` has no public initialiser.
- `MedataCore/Sources/Pipeline/PipelineEstimator.swift` — `public protocol PipelineEstimator: Sendable` with `func estimate(captureResult:) async throws -> MealRecord`, plus `extension Pipeline: PipelineEstimator {}` (task 3, Decision 13). Test seam used by `CaptureFlowModel` so unit tests can inject a mock without spinning up the real `Pipeline` / segmenter weights / `FoodDatabase`.
- `static/icon.svg` — brand master logo ported from `main` (task 4, Decision 7); 1024×1024 SVG with `stroke="#63ff00"`, the canonical accent colour consumed by AppIcon generation (task 5) and SwiftUI `Color.medataAccent` (task 25).

### Changed (UI spec — SPM prerequisites phase, tasks 1–4)

- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — added three additive public accessors per design §3.1 (task 2): `var arSession: ARSession` (for `ARView` preview binding), `var frames: AsyncStream<ARFrame>` and `var interruptions: AsyncStream<InterruptionEvent>` (both per-subscriber with `BufferingPolicy.bufferingNewest(1)`). Implemented `ARSessionObserver.sessionWasInterrupted/Ended` to feed the interruption stream and extended `session(_:didUpdate:)` to fan out to all frame subscribers alongside the existing single-shot capture continuation. New `public enum InterruptionEvent: Sendable, Equatable { case began, ended }`. The engine remains the sole `ARSessionDelegate`.

### Added (Performance and Cleanup phase — tasks 65–70)

- `MedataCore/Tests/HarnessCLITests/PipelinePerformanceTests.swift` — XCTest P95 latency assertions for single-view (≤ 1000 ms, task 65) and two-view (≤ 1800 ms, task 66) end-to-end pipelines; device-gated with `#if !os(iOS)` + `XCTSkip`; 10-iteration `XCTClockMetric` measurement with synthetic FP16 probability tensors, depth maps, and calibration fixtures built inline.
- `tools/check_spelling.sh` — Irish/British English spelling linter (Req 19.2, task 69); scans `*.swift` files under `MedataCore/Sources`, `HarnessCore`, `HarnessCLI`, and `App`, plus `.xcstrings` catalogs; exits 0 if clean, 1 on violations; ~80 banned US-English words with `\b` word-boundary anchors; respects `REPO_ROOT` env-var override for test isolation.
- `MedataCore/Tests/SpellingLinterTests/SpellingLinterTests.swift` — 23 XCTest cases for `check_spelling.sh` (task 68): rejected US spellings (recognized, color, fiber, …), accepted British/Irish equivalents (recognised, colour, fibre, …), word-boundary edge cases, empty file, and multiple-violation detection; uses `Process` with a temp-dir `REPO_ROOT` wrapper for isolation; macOS-only via `XCTSkip`.
- `legacy/svelte-mvp/` — archived SvelteKit MVP (task 70, Req 1.4): moved from repo root to `legacy/` to make way for the iOS-native project structure.

### Changed (Performance and Cleanup phase — tasks 65–70)

- `MedataCore/Sources/Pipeline/Pipeline.swift` — added `#if DEBUG` OSSignpost instrumentation (`OSSignposter`, subsystem `ie.medata.pipeline`, category `Stages`) across all 8 pipeline stages (task 67, Req 16.5); each stage is wrapped with `beginInterval`/`endInterval` including on throw paths to prevent unclosed intervals in Instruments.
- `Package.swift` — added `Volume`, `CaptureKit`, `SupportPlane`, `Macros` to `HarnessCLITests` dependencies for performance-test fixture construction; added new `SpellingLinterTests` target (no dependencies).
- `README.md` — rewritten to describe the iOS-native project structure (task 70); includes module table, build commands, and CI-script reference.
- `MedataCore/Sources/Persistence/MealRecord.swift` — fixed US spellings in comments: `denormalised`, `serialisation` (Req 19.2).

### Added (Volume Estimation phase — tasks 24–34)

- `MedataCore/Sources/Volume/{VolumeTypes,VoxelCarveEstimator,HeightFieldEstimator,InterClassOcclusionDetector,VoxelGridSizer,MaskMatcher}.swift` — complete Volume module per design §6.6–6.11: shared types (`VoxelGrid`, `BetaCorrection`, `VolumeError`, `VoxelCarveView`/`VoxelCarveEstimate`/`HeightFieldEstimate`/`MaskMatchingResult`) plus internal helpers (`projectCamera1`, `applyMat4`, `signedDistanceToPlane`, `sampleDepthBilinearMm`, `sampleConfidenceUInt8`); two-view voxel-carving estimator with FP32-promoted per-pixel argmax, τ_sil/τ_v thresholds, single-view-only degraded fallback (silhouette extrusion at 30 mm prior height), and β-correction; single-view height-field integrator with 1/cos³θ off-axis pixel-area correction (Decision 29), per-class LiDAR-coverage tracking, and ≥50% coverage enforcement; inter-class occlusion detector (single-pass 4-neighbour scan, 10 mm depth-discontinuity threshold); gravity-aligned voxel-grid sizer with threadgroup-multiple rounding and 360 mm horizontal / 120 mm vertical caps; pure class-equivalence mask matcher producing matched/single-view-only class sets.
- `MedataCore/Sources/Volume/Kernels/voxel_carve.metal` — GPU compute kernel (one thread per voxel, 8×8×8 threadgroups): two-view projection, silhouette test, FP32-product argmax, per-class `atomic_uint` counts, ambiguous-count and silhouette-count accumulators.
- `MedataCore/Sources/Volume/Kernels/height_field.metal` — GPU compute kernel (one thread per nadir-view pixel): off-axis pixel-area integration with fixed-point `atomic_uint` volume accumulator, LiDAR confidence gate, and inline inter-class occlusion detection (4-neighbour scan, satisfies §6.8 Req 13.2 in a single GPU pass).
- `MedataCore/Tests/VolumeTests/{Helpers,VoxelCarveEstimatorTests,HeightFieldEstimatorTests,VoxelGridSizerTests,MaskMatcherTests,VoxelOwnershipDisjointnessTests,InterClassOcclusionDetectorTests}.swift` — 37 new tests: synthetic cube volume within 5% (two-view), silhouette-test exclusion, FP32 promotion winner, ownership disjointness, single-view fallback in `degradedClasses`, τ_v = 0.04 ambiguous discard, `noFoodVolumeRecovered` refusal; flat-food volume within 3% (height-field), off-axis area inflation, coverage-fraction tracking, `lidarCoverageTooLow` refusal; bbox back-projection, multiples-of-8 rounding, gravity-aligned axes, 360 mm cap, centroid origin, summary proto; mask-matcher intersection and symmetric difference; 7-seed PBT for voxel disjointness; 7 occlusion detector cases covering discontinuity thresholds, single class, background boundary, and flat surfaces.

### Changed

- `Package.swift` — added `Volume` library target (depends on `PortableContracts`, `CaptureKit`, `Segmentation`, `SupportPlane`, `MetricScale`) with `.copy("Kernels")` resource bundle; added `VolumeTests` test target.
- `MedataCore/Sources/Volume/VolumeTypes.swift` — added `import Segmentation` to expose `ProbabilityTensor` used by internal helpers.

### Added

- `MedataCore/Sources/Segmentation/{ClassPalette,SegmentationTypes,FP16Bytes,PreProcessing,PostProcessing,CoreMLSegmenter}.swift` — Segmentation module per design §3.5 / §6.5: Swift `ClassPalette` with `Pb*` bridges and `isFoodClass(_:)` that excludes the three special indices; `ProbabilityTensor` / `ArgmaxMap` / `SegmentationResult` Swift wrappers enforcing the portable FP16-LE HWC-row-major byte contract; pre-processing pipeline (canonicalise BGRA8/RGBA8 → RGB8, aspect-preserving letterbox bilinear resize with pixel-centre alignment, ImageNet normalisation, FP16 cast, pad with `(0 − mean[c]) / std[c]`); post-processing pipeline (max-subtracted FP32 softmax, crop letterbox, bilinear resize back to original W × H, argmax → UInt8 label map, σ_seg = mean top-class probability over food pixels per M8 pin, refusal predicate aligned with silhouette test `(1 − q[bg]) ≥ τ_sil` rather than argmax = bg per edge case 3); `SegmenterInferenceEngine` protocol + `CoreMLSegmenter` wrapper taking a string model path (P8) + `CoreMLInferenceEngine` that auto-detects CHW vs HWC input/output layout from the `MLMultiArrayConstraint.shape` so the same wrapper consumes models exported by `coremltools` or `ai-edge-torch` without per-tool code paths; `SegmenterWeightsBudget.validate(at:)` that walks `.mlpackage` directories recursively to enforce Req 8.2 (≤ 10 MB) (research tasks 19, 20, 21, 22).
- `MedataCore/Tests/SegmentationTests/{PreProcessingTests,PostProcessingTests,CoreMLSegmenterTests}.swift` — 22 new tests covering BGRA8 / RGBA8 / RGB8 canonicalisation, letterbox dimension calculation for wide/tall/square aspect, post-normalisation pad-value verification (black input matches pad value), σ_seg exclusion of background / unknown_food / unsupported_liquid, `noFoodPixels` refusal aligned with silhouette test (NOT argmax = bg), refusal-not-triggered when argmax = bg but silhouette holds, perClassMeanProb food-only inclusion, resize-back pixel-centre alignment, string-not-URL model path, portable FP16-LE byte layout regardless of inference backend, pre-processed FP16 buffer wiring, and weights-budget validation for files and recursive `.mlpackage` directories.
- `tools/segmenter/{export.py,requirements.txt,README.md}` — Python export pipeline (research task 23) per Decision 28: torchvision DeepLabV3 + MobileNetV3-Large checkpoint → `coremltools.convert(...)` → `MedataCore/Resources/segmenter.mlpackage` with FP16 compute and weights; same checkpoint → `ai-edge-torch` → TFLite (validation only in v1). ONNX hop bypassed. Reference-image run through both artefacts asserts per-pixel argmax agreement >99% with max-abs logit error <0.05; disagreement fails the export.
- `MedataCore/Resources/README.md` — placeholder + intent for bundled segmenter/database artefacts (Decision 27); heavy artefacts excluded from version control via `.gitignore`.

### Changed

- `Package.swift` — `SegmentationTests` target now depends on `Segmentation`, `CaptureKit`, `PortableContracts`.
- `MedataCore/Sources/Segmentation/Module.swift` — placeholder replaced with a file-map comment for the module's public surface.
- `MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift` — placeholder test expanded to cover `ClassPalette` `Pb*` round-trip and `isFoodClass` boundary cases.
- `.gitignore` — added segmenter / database build artefacts (`MedataCore/Resources/segmenter.mlpackage/`, `food_db.sqlite`, `ifcdb_overlay.sqlite`, `tools/segmenter/build/`, `tools/segmenter/.venv/`).
- `docs/agent-notes/swift-package.md` — appended a "Segmentation phase is complete" section documenting the new module file map, the σ_seg silhouette-AND-food-argmax filter rule, the FP16 round-trip accuracy tolerance, and the manually-unrolled channel loop in the resize hot path.
- `specs/research/tasks.md` — Segmentation phase tasks 19–23 marked complete.

### Added (Capture and Detection phase)

- `MedataCore/Sources/CaptureKit/{RawFrame,Bridges,CaptureSession,ARKitCaptureEngine,MockCaptureEngine}.swift` — Swift-ergonomic `RawFrame` (Int64 ns timestamps, explicit `PixelFormat`/`ColourSpace`, EXIF-style orientation), Pb-bridge extensions, `CaptureSession` actor with a 200 ms `stop()` ceiling per Req 2.5, an iOS-only ARKit + Core Motion engine that maps `ARConfidenceLevel.{low,medium,high}` to UInt8 `{0,127,255}` and refuses devices without rear LiDAR per Req 1.3, and a `MockCaptureEngine` for tests/HarnessCLI (research tasks 8, 9).
- `MedataCore/Sources/CardDetection/{LinearAlgebra,CardPoseSolver}.swift` — Accelerate-backed SVD wrapper (`sgesvd_` + 3×3 helpers, made `public` so SupportPlane can reuse) and a custom no-OpenCV P4P solver per design §6.1: 8×9 DLT with the −Z-forward sign convention, sign-of-λ enforcement, SO(3) projection with `det(UV^T)` fix-up, edge-on refusal at `|r3·ẑ_cam| < 0.2`, and an SVD numerical-stability gate at σ_min/σ_max < 1e−6 (research tasks 10, 11).
- `MedataCore/Sources/SupportPlane/{SupportPlane,Hash,LiDARPlaneFitter,CardOnlyPlaneFitter}.swift` — `SupportPlane` Swift struct + `BinaryMask`, an FNV-1a-based deterministic seed and `SplitMix64` RNG for the §6.0 reproducibility requirement, a 256-iteration RANSAC fitter per design §6.2 with gravity-bias filtering and inlier-covariance stability gate, and the iterative card-only fixed-point per §6.3 with strict-1mm convergence and best-of-5 fallback (research tasks 13, 14, 15, 16).
- `MedataCore/Sources/MetricScale/MetricScaleResolver.swift` — pure-function symmetric agreement formula per design §6.4 (M4 fix; symmetric in inputs), σ_s clamped to [ε, 1] per Req 13.1, and a `LiDARScaleAdapter.mmPerPx(fromMetresPerPx:)` helper that performs the m/px → mm/px conversion at the resolver boundary per §6.4 (research tasks 17, 18).
- `MedataCore/Tests/CaptureKitTests/{RawFrameTests,CaptureSessionTests}.swift` — 11 new tests covering portable RawFrame/protobuf round-trip, the simd boundary rule, `LidarConfidenceLevel` mapping, and the 200 ms `stop()` budget under both fast and slow engines.
- `MedataCore/Tests/CardDetectionTests/{CardPoseSolverTests,CardPosePropertyTests}.swift` — 10 tests covering noise-robustness (≤1 px → < 2 mm), sign-of-λ, SO(3) properness, cardTooOblique refusal, degenerate H, scale at the card plane, and 400 deterministic property-based round-trip samples in a realistic intrinsics/pose envelope.
- `MedataCore/Tests/SupportPlaneTests/{LiDARPlaneFitterTests,CardOnlyPlaneFitterTests}.swift` — 8 tests covering plane recovery within 1°/2 mm of ground truth, deterministic-seed reproducibility, degenerate-covariance refusal, residual-cap refusal, h_food=0/π_sup-at-card-depth initialisation, 5-iteration convergence, best-of-5 fallback, and iterationDiverged refusal.
- `MedataCore/Tests/MetricScaleTests/MetricScaleResolverTests.swift` — 7 tests covering all four cases of Req 7, symmetric-agreement input-swap invariance, the noScaleAvailable refusal, the LiDARScaleAdapter unit conversion, and σ_s floor/ceiling clamping.
- `Package.swift`, `MedataCore/Sources/{12 modules}/`, `HarnessCLI/main.swift` — Swift Package skeleton per design §2.1 (research tasks 1, 7); twelve module targets plus a macOS executable target and three test bundles, building with `swift build` and `swift test` on macOS 14 / iOS 17.
- `MedataCore/Sources/PortableContracts/Schemas/*.proto` — 27 canonical schemas covering every record that crosses a module boundary per design §4.3 and Decision 31; `generate.sh` regenerates the committed `Generated/*.pb.swift` sources via `protoc-gen-swift` (research tasks 2, 3).
- `MedataCore/Sources/PortableContracts/{Vec3,Mat4,Projection}.swift` — Swift-ergonomic types per design §3.1 with right-handed cross product, column-major Mat4 storage, `−Z`-forward projection, and bridges to/from the generated `Pb*` types (research task 5).
- `MedataCore/Sources/CaptureKit/SimdAdapter.swift` — `simd_float3` ↔ `Vec3` and `simd_float4x4` ↔ `Mat4` conversions, scoped to `CaptureKit` only per the design boundary rule.
- `MedataCore/Sources/CaptureKit/MetalContext.swift` — `@unchecked Sendable` shared device/queue/library context per design §3.1.1; falls back to an empty in-memory library so the lifecycle test runs on hosts without a bundled metallib (research tasks 6, 7).
- `MedataCore/Tests/PortableContractsTests/` — 21 round-trip and convention tests covering protobuf binary, deterministic protobuf-JSON, Vec3/Mat4 conventions, and the `Pb` ↔ Swift bridge (research tasks 2, 4).
- `MedataCore/Tests/CaptureKitTests/` — 5 tests covering simd interop and the MetalContext lifecycle (research tasks 4, 6); skip gracefully when no Metal device is available.
- `.swiftformat`, `.gitattributes` — Swift formatting config and Git LFS rules for fixture artefacts and the bundled segmenter package per task 1.
- `docs/agent-notes/swift-package.md` — agent context note describing the package topology, generated-protobuf naming, and build/test entry points.

### Changed

- `Package.swift` — added three test targets (`CardDetectionTests`, `SupportPlaneTests`, `MetricScaleTests`) for the Capture and Detection phase.
- `.gitignore` — added Swift / Xcode build artefact patterns (`.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj/xcuserdata/`, `Package.resolved`).
- `docs/agent-notes/swift-package.md` — appended a "Capture and Detection phase is complete" section documenting the new modules, key gotchas (−Z-forward DLT signs, FNV-1a vs xxh64, residual-threshold testability), and the next phase's entry point.
- `specs/research/tasks.md` — Foundation phase tasks 1–7 and Capture and Detection tasks 8–18 marked complete.

### Previously added

- `src/routes/capture/+page.svelte` — full capture page wiring: fetch `/api/recognition/status` on mount with skeleton loading state, conditional ManualEntryCTA/MockModeBanner rendering, 10MB client-side image size check, `handleSave()` wired to `POST /api/meals` with Blob Storage image upload (Req 6.4, 11.1, 11.3)

### Added

- `src/routes/capture/page.test.ts` — 7 tests for capture page status detection and conditional rendering: skeleton/loading state, ManualEntryCTA for unconfigured/error states, MockModeBanner for mock mode, recognition path for configured state (Task 22)

### Removed

- `@anthropic-ai/sdk` dependency — removed from `package.json` and `pnpm-lock.yaml` (D-MVR-013)
- `src/lib/services/claude-food-recognition.ts` — old Anthropic SDK-based service (replaced by `HttpRecognitionService`)
- `src/lib/services/food-recognition.ts` — old interface with `LabelContext`, `IFoodRecognitionService` (replaced by `recognition.ts`)
- `src/routes/api/ai/recognise/+server.ts` — old API route (replaced by `/api/recognition/analyse`)

### Changed

- `src/routes/capture/+page.svelte` — updated to call `/api/recognition/analyse` instead of `/api/ai/recognise`, removed label scanning references
- `src/lib/services/index.ts` — removed barrel exports for deleted `food-recognition` and `claude-food-recognition` modules
- Renamed route test files from `+page.test.ts` to `page.test.ts` to fix SvelteKit build compatibility

### Previously added

- `createRecognitionService()` factory in `src/lib/services/recognition.ts` — returns `MockRecognitionService` when `RECOGNITION_MOCK_MODE=true`, `HttpRecognitionService` otherwise
- `recognition.test.ts` — unit tests for `createRecognitionService()` factory (3 tests)
- `/api/recognition/status` endpoint (`src/routes/api/recognition/status/+server.ts`) — returns `{ configured, mockMode }` with fail-safe default on error
- `/api/recognition/status` tests — 5 tests covering configured/unconfigured/mock/error scenarios
- `/api/recognition/analyse` endpoint (`src/routes/api/recognition/analyse/+server.ts`) — POST handler with image size validation, base64→Blob conversion, `RecognitionError` → HTTP status mapping, Irish English error messages (Req 11.4)
- `/api/recognition/analyse` tests — 9 tests covering success, 503/504/422/413/429/502 error codes, and Irish English spelling validation
- `IRecognitionService` interface, `RecognitionError` class, and canonical types in `src/lib/services/recognition.ts` — provider-agnostic recognition layer (D-MVR-013, D-MVR-015)
- `MockModeBanner.svelte` component — amber banner indicating mock mode is active
- `ManualEntryCTA.svelte` component — call-to-action when recognition is not configured
- `CameraCapture.test.ts` — tests for stream cleanup, camera detection via `enumerateDevices`, and gallery upload parity
- Property-based tests for `sumMacros` using `fast-check` — validates macro sum identity, zero totals, and non-negativity invariants
- `MockRecognitionService` implementation (`src/lib/services/mock-recognition.ts`) — returns realistic fake food data with 500–1500ms simulated delay (Req 5.1–5.5)
- `mock-recognition.test.ts` — unit tests for `MockRecognitionService` covering schema, delay, notes prefix, and macro validity
- `MealEditor.svelte` — `mockMode` prop with `MockModeBanner` rendering, error toast with state retention on failed save (Req 5.5, 11.1)
- `src/routes/manual/+page.test.ts` — manual entry flow tests (Req 7.1–7.3)
- `src/routes/+page.test.ts` — logbook display, meal edit/delete tests (Req 8.1–8.5)
- `src/routes/presets/+page.test.ts` — preset save, apply, edit, delete tests (Req 9.1–9.4)
- HTTPS dev server via `@vitejs/plugin-basic-ssl` with LAN binding (`server.host: true`) for mobile camera access (Req 1.1, 1.2)
- Provider-agnostic environment variables: `RECOGNITION_BASE_URL`, `RECOGNITION_MODEL`, `RECOGNITION_API_KEY`, `RECOGNITION_MOCK_MODE`, `RECOGNITION_TIMEOUT_MS`
- Developer setup guide with Ollama, cloud model, and mock mode configuration options
- `HttpRecognitionService` implementation (`src/lib/services/http-recognition.ts`) — OpenAI-compatible `/v1/chat/completions` client with configurable timeout, optional auth, and AbortController support (Req 4.3, 11.2)
- `parseAnalysisResult()` function — validates and extracts `FoodAnalysisResult` from OpenAI-compat response envelopes, handles markdown-fenced JSON and pre-parsed objects
- `http-recognition.test.ts` — 23 unit tests covering `parseAnalysisResult` (JSON extraction, markdown fence stripping, schema validation, error codes) and `HttpRecognitionService` (isReady, auth headers, request shape, timeout, backend errors)

### Changed

- `CameraCapture.svelte` — replaced UA-string detection with `enumerateDevices()` feature detection; added `onDestroy`/`beforeNavigate` stream cleanup (Req 2.4, D-MVR-011, D-MVR-018); gallery-only mode when no camera detected
- `RecognisedFoodItem` no longer extends with `quantity` and `unit` fields (D-MVR-017)
- `FoodRecognitionResult` no longer includes `totalMacros`, `provider`, or `processingTimeMs` fields
- `MealDataSource` type removes `label_scan` value — label scanning deferred (D-MVR-017)
- `RecognisedFoodItemSchema` and `MealDataSourceSchema` updated to match type changes
- `/api/ai/recognise` endpoint response simplified to return only `items` and `confidence`
- `FoodRecognitionResult.svelte` computes totals locally instead of receiving from API
- Dev server now serves HTTPS-only at `https://localhost:5173` (D-MVR-010)

### Removed

- `ANTHROPIC_API_KEY` from `.env.example` — replaced by `RECOGNITION_API_KEY`
- `label_scan` source type from `MealDataSource`, schemas, and UI components
- `quantity`/`unit` display from `FoodRecognitionResult.svelte`
