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

### Changed

- `Pipeline.fitSupportPlane` is now a thin wrapper that delegates to the injected `SupportPlaneFitter` and maps `SupportPlaneError` to `EstimationFailure` exactly as before.
- `PipelineFactory.makeForDevice` now takes a required `cardDetector` parameter and an optional `supportPlaneFitter` (defaulting to `LiDARSupportPlaneFitter()`); production wires `VisionCardDetector` at task 14.
- `Pipeline.init` accepts `supportPlaneFitter:` so the protocol seam is injectable end-to-end.
- `StubInferenceEngine` returns a centred-ellipse food region covering 30 ± 2 % of the input under `DEV_STUB_SEGMENTER` (Decision 8) instead of a uniform-dominant frame.
- `event=estimate.start` log gains `maskAgeMs`; `event=estimate.end` gains `foodRegionCoveragePercent`; `event=supportplane.start` reports `source=pre_shutter` and drops `fillFraction` (Decision 15).

### Removed

- `CentreRectangleMask.swift`, the `centreRectangleFillFraction` constant, and `CentreRectangleMaskTests.swift` — the centred-rectangle placeholder is superseded by the real pre-shutter mask (Req 2.2). The all-ones-mask regression sentinel in `SupportPlaneRoughMaskTests` is preserved per Req 8.6.
