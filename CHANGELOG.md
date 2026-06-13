# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `SupportPlaneFitter` protocol + `LiDARSupportPlaneFitter` production conformance in `SupportPlane` module (Decision 9) so `Pipeline.estimate` delegates the LiDAR-vs-card dispatch through an injectable seam.
- `CaptureResult.preShutterFoodMask` and `preShutterMaskAgeMs` fields carrying the pre-shutter food region from the App layer into the pipeline.
- `computeFoodRegionCoverage` helper that recomputes `LiDARStatus.foodRegionCoveragePercent` in 256×192 confidence-buffer space per Decision 14.
- `SupportPlaneError.emptyFoodMask` case mapped to `EstimationFailure.noFoodPixels` so empty/missing masks refuse with the existing modal copy (Decision 2).
- `MedataCore/Sources/Pipeline/NullCardDetector.swift` so MedataCore tests can reuse the no-op detector without redefining it.
- `App/VisionCardDetector.swift`: Vision-backed `CardDetector` conformance reusing a single `VNDetectRectanglesRequest` configured for the ID-1 aspect / size envelope, BGRA→`CGImage` conversion, async `warmup()` over a 64×64 blank buffer (Req 5.7), and a DEBUG-gated `event=carddetect.end success=… cornerCount=… latencyMs=…` log on `ie.medata.app`/`Shutter` (Reqs 7.3, 7.4).
- `MeData/Tests/VisionCardDetectorTests.swift`: Swift Testing suite that synthesises a 1920×1440 BGRA buffer with a single ID-1-aspect rectangle and asserts corner order TL→TR→BR→BL, nil return on an unrecognisable buffer (Req 5.4), and warm detection latency within the on-host CI ceiling (Req 5.6).
- `App/PreShutterSegmenter.swift`: `@MainActor` pre-shutter food-region producer with reference-typed `MaskBox`, `TimestampedMask`, latest-wins inference loop, fire-and-forget `pause()` + async `awaitPaused()` drain (Decision 13), nonisolated ARFrame→RawFrame conversion to keep PixelBufferAdapter off MainActor, cadence-miss counter mirroring the DEBUG `event=preshutter.cadence.miss` log, and a `PreShutterMaskSource` protocol seam consumed by `CaptureFlowModel` and exercised by test spies.
- `MeData/Tests/PreShutterSegmenterTests.swift`: Swift Testing suite covering latest-wins (`bufferingNewest(1)` coalesces frames arriving during in-flight inference), `awaitPaused()` drains the inflight task, `latest` survives `pause()`, `MaskBox` reference vs content semantics, and the cadence-miss counter increments when consecutive publishes are > 500 ms apart.
- `MeData/Tests/CaptureFlowModelPreShutterTests.swift`: Swift Testing suite covering the 750 ms staleness gate (fresh mask flows through `CaptureResult.preShutterFoodMask`; stale mask reaches the pipeline as nil), `awaitPaused()` is called before reading `latest` at the nadir-capture instant (Decision 13 / no TOCTOU), and the `firstFrameMaskBox` lifecycle clears in lockstep with `firstFrame` at backgrounding, interruption, tab change, tracking degradation, dismissResult, and dismissRefusal sites (Decision 11).
- `PipelineFactory.makeSegmenter`, `Pipeline.segmenterSourceTag`, and `Pipeline.preShutterSourceTag` helpers so App-target callers can construct a separate pre-shutter `CoreMLSegmenter` (Decision 12) without duplicating the `#if DEV_STUB_SEGMENTER` engine-selection gate.
- `MedataCore/Tests/PipelineTests/PreShutterMaskRoutingIntegrationTests.swift`: Swift Testing integration suite asserting that a `BinaryMask` placed into `CaptureResult.preShutterFoodMask` reaches `SupportPlaneFitter.fit`'s `preShutterFoodMask` argument byte-identical, using a local `ProbeFitter` injected via `PipelineFactory.makeForDevice(supportPlaneFitter:)` (Req 8.7).

### Changed

- `Pipeline.fitSupportPlane` is now a thin wrapper that delegates to the injected `SupportPlaneFitter` and maps `SupportPlaneError` to `EstimationFailure` exactly as before.
- `PipelineFactory.makeForDevice` now takes a required `cardDetector` parameter and an optional `supportPlaneFitter` (defaulting to `LiDARSupportPlaneFitter()`); production wires `VisionCardDetector` at task 14.
- `Pipeline.init` accepts `supportPlaneFitter:` so the protocol seam is injectable end-to-end.
- `StubInferenceEngine` returns a centred-ellipse food region covering 30 ± 2 % of the input under `DEV_STUB_SEGMENTER` (Decision 8) instead of a uniform-dominant frame.
- `event=estimate.start` log gains `maskAgeMs`; `event=estimate.end` gains `foodRegionCoveragePercent`; `event=supportplane.start` reports `source=pre_shutter` and drops `fillFraction` (Decision 15).
- `CaptureFlowModel` takes an optional `preShutterSegmenter: any PreShutterMaskSource`, owns a `firstFrameMaskBox` that travels with `firstFrame` through the two-view dance, calls `awaitPaused()` then applies the 750 ms staleness gate at the nadir-capture instant, and passes the frozen mask through to `CaptureResult` (Decisions 11 / 13). The old `frozen.lidarCoveragePercent` wiring is replaced with `foodRegionCoveragePercent: 0` so `Pipeline.estimate` recomputes the real food-region value (Decision 14).
- `App.swift` constructs a single `VisionCardDetector` (passed to both `Pipeline.makeForDevice` and the warmup path) and a SEPARATE `CoreMLSegmenter` for the pre-shutter producer (Decision 12).
- `CaptureFlowView` starts the pre-shutter producer on `.onAppear` alongside `LiveSampleObserver`, re-subscribes each `engine.frames` on state transitions back into producing states (Req 1.4), `pause()`s the producer when leaving those states, and triggers a one-shot `Task { await visionCardDetector.warmup() }` on first entry to `.ready` (Req 5.7).
- `Pipeline` re-exports `Segmentation` and `SupportPlane` so the App target can construct `CoreMLSegmenter` / refer to `BinaryMask` and `ClassPalette` via a single `import Pipeline`.

### Removed

- `CentreRectangleMask.swift`, the `centreRectangleFillFraction` constant, and `CentreRectangleMaskTests.swift` — the centred-rectangle placeholder is superseded by the real pre-shutter mask (Req 2.2). The all-ones-mask regression sentinel in `SupportPlaneRoughMaskTests` is preserved per Req 8.6.
