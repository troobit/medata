# Requirements: RawFrame YCbCr→RGB Conversion

## Introduction

`ARFrame.capturedImage` arrives from ARKit as a biplanar YCbCr `CVPixelBuffer`, but `ARKitCaptureEngine.copyPixelBufferBytes` reads it as if it were chunky RGB-family, producing either an empty buffer or the luma plane alone. `detectPixelFormat` compounds the bug by reporting `.bgra8` for every YCbCr frame. Every downstream consumer of `RawFrame.imageBytes` (the segmenter pre-processor today, a future `VisionCardDetector`, any other `CGImage` / `Vision` reader) is therefore reading miscoded bytes against a lying contract. This spec converts captured frames to BGRA8 at the capture boundary, makes `pixelFormat` truthful, and proves the conversion correct with a hand-computed reference patch.

### 2026-06-04 device evidence (post-OOM-fix run)

On-device verification on iPhone 13 Pro Max iOS 26.5 after the `lidar-plane-fit-oom-on-device-1920x1440` bugfix landed shows the pipeline now reaches the segmenter — and fails there with `event=estimate.end success=false error=SegmentationError` (`nextup.md` lines 90-96 and 150-156, both nadir-stage successes with `event=supportplane.end success=true residual_mm≈2.87 inliers≈37-46k`). The pre-OOM-fix `Fatal error: failed to allocate 32198713632 bytes` is gone; the YCbCr-mismatch defect this spec scopes is now the first reachable failure mode on a real device build. The OOM bugfix is therefore the prerequisite that exposed the latent YCbCr defect this spec resolves. (The same on-device run also surfaced a UI mislabelling problem covered by [Requirement 6](#6-honest-error-surfacing-for-pipeline-failures).)

## Non-Goals

- Training, exporting, or bundling the Core ML segmenter `.mlpackage` (Blocker 1 in `docs/agent-notes/pipeline-wiring-status.md`).
- Building a `VisionCardDetector` against the new RGB contract.
- Wiring the real `Pipeline` factory in `App/App.swift` (Step 3 in the agent-note; blocked on Blocker 1).
- Converting the per-frame `frames` AsyncStream — only `captureFrame()` shutter-time conversion is in scope.
- Changing the `PixelFormat` enum, the `RawFrame` proto wire format, or the `MockCaptureEngine` default (all already accept BGRA8).
- Removing `PendingPipeline` or other application-layer wiring.

## Requirements

### 1. Correct YCbCr→BGRA Conversion at Capture

**User Story:** As the segmenter pre-processor (and any future `Vision` consumer), I want `RawFrame.imageBytes` to be a contiguous, correctly-encoded BGRA8 buffer that matches the frame's declared dimensions, so that I can decode pixels without guessing the source layout.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN `ARKitCaptureEngine.captureFrame(target:)` returns a `RawFrame` derived from an ARKit `CVPixelBuffer` of format `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`, THEN `imageBytes.count` SHALL equal `imageWidth * imageHeight * 4`.  
2. <a name="1.2"></a>WHEN the conversion is fed a known-content YCbCr `CVPixelBuffer` whose ITU-R BT.601 full-range luma/chroma values are hand-computed to encode an arbitrary BGRA reference patch, THEN every output byte SHALL be within ±2 of the reference patch byte (tolerance covers fixed-point YCbCr rounding).  
3. <a name="1.3"></a>WHEN the conversion runs, the output buffer SHALL be contiguous (no per-row stride padding beyond `imageWidth * 4`).  
4. <a name="1.4"></a>WHEN `RawFrame.pixelFormat` is read by a downstream consumer, it SHALL equal `.bgra8` for any frame produced by `ARKitCaptureEngine.buildRawFrame` from a YCbCr or BGRA source.  
5. <a name="1.5"></a>WHEN the source `CVPixelBuffer` format is neither YCbCr biplanar nor a BGRA-family format supported by the conversion routine, THEN `captureFrame` SHALL throw `CaptureError.captureFailed` with a message naming the unrecognised pixel-format four-character code.

### 2. Truthful PixelFormat Reporting

**User Story:** As any code reading `RawFrame.pixelFormat`, I want the reported format to match the bytes in `imageBytes`, so that I don't decode the wrong layout.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN `detectPixelFormat` is called on a `CVPixelBuffer` whose `CVPixelBufferGetPixelFormatType` is `kCVPixelFormatType_32BGRA`, THEN it SHALL return `.bgra8`.  
2. <a name="2.2"></a>WHEN `detectPixelFormat` is called on a `CVPixelBuffer` whose `CVPixelBufferGetPixelFormatType` is `kCVPixelFormatType_32RGBA`, THEN it SHALL return `.rgba8`.  
3. <a name="2.3"></a>WHEN `detectPixelFormat` is called on a `CVPixelBuffer` whose `CVPixelBufferGetPixelFormatType` is a YCbCr biplanar format AND the conversion routine emits BGRA8 from that buffer, THEN the format reported on the resulting `RawFrame` SHALL be `.bgra8` (i.e. the format describes the *output* bytes, not the source buffer).  
4. <a name="2.4"></a>The `detectPixelFormat` helper SHALL NOT silently fall through to a default for unrecognised four-character codes; unrecognised inputs SHALL trip the error path described in [1.5](#1.5).

### 3. Conversion Is Independently Testable

**User Story:** As a test author, I want to verify the YCbCr→BGRA conversion without spinning up an `ARSession`, so that the correctness test runs on the iOS Simulator and in CI.

**Acceptance Criteria:**

1. <a name="3.1"></a>The conversion routine SHALL be invokable from a test target via a public or `internal` entry point that accepts a `CVPixelBuffer` (or an equivalent injectable seam) and returns the BGRA byte buffer together with its declared `PixelFormat`.  
2. <a name="3.2"></a>The test target SHALL be able to construct a YCbCr biplanar `CVPixelBuffer` of arbitrary dimensions populated with caller-supplied luma and chroma values, using only public CoreVideo APIs available on the iOS Simulator, with no ARKit dependency.  
3. <a name="3.3"></a>The existing `CaptureKitTests` suite SHALL continue to pass against the unmodified `RawFrame`, `MockCaptureEngine`, and `Bridges` surfaces.

### 4. Per-Frame Conversion Cost Discipline

**User Story:** As a user tapping the shutter, I want the food estimate to appear within Req 16.1's 1000 ms P95 budget without the conversion stage tanking the capture path, so that the pipeline stays inside its end-to-end budget on the actual fleet of supported devices (current floor is several generations newer than the research-spec iPhone 12 Pro reference).

**Acceptance Criteria:**

1. <a name="4.1"></a>The conversion SHALL run only at `captureFrame(target:)` shutter time. The per-frame `frames: AsyncStream<ARFrame>` SHALL NOT trigger the conversion.  
2. <a name="4.2"></a>The conversion SHALL NOT allocate more than 2× the output buffer's worth of transient memory per call (input is the immutable source `CVPixelBuffer`, output is the returned `Data`; intermediates SHALL fit in one additional buffer at most).  
3. <a name="4.3"></a>The conversion SHALL use a hardware-accelerated path (vImage, CoreImage, or Metal) on every call — no per-pixel Swift loop. The implementation SHALL NOT instantiate per-call helpers that are documented as expensive to construct (notably `CIContext`); any such helper SHALL be cached across calls.  
4. <a name="4.4"></a>The conversion path SHALL be exercised by the Req 16.7 performance harness so that any end-to-end-budget regression introduced by the conversion stage is detected at the harness level rather than via a per-call wall-clock assertion.

### 5. Contract Preservation for Existing Consumers

**User Story:** As a maintainer of code that already reads `RawFrame.imageBytes` and `pixelFormat`, I want the existing length-and-format invariant to hold after the fix, so that I do not need to update unrelated consumers.

**Acceptance Criteria:**

1. <a name="5.1"></a>`SegmenterPreProcessor.process(imageBytes:pixelFormat:width:height:)` SHALL accept the output of the conversion path without raising `SegmentationError.invalidInputDimensions` for any frame returned by `ARKitCaptureEngine.captureFrame`.  
2. <a name="5.2"></a>The `Bridges` round-trip from `RawFrame` to `PbRawFrame` and back SHALL preserve the BGRA byte content and the `.bgra8` format tag bit-for-bit.  
3. <a name="5.3"></a>`MockCaptureEngine` SHALL continue to emit `.bgra8` frames whose `imageBytes.count == imageWidth * imageHeight * 4`; the mock SHALL NOT be required to perform any YCbCr conversion.

### 6. Honest Error Surfacing for Pipeline Failures

**User Story:** As a user whose shutter tap fails for a non-scale reason (segmenter error, conversion error, persistence error, anything else the pipeline raises that is not already a typed `EstimationFailure`), I want the refusal modal to NOT lie about the cause being "Meal scale unknown", so that I do not waste time framing-and-retrying a problem that is unrelated to scale, and so that a developer reading the device log can correlate the on-screen message with the logged error type.

**Background.** `App/CaptureFlowModel.swift:502-506` currently has:

```swift
} catch {
    log.info("event=estimate.end success=false error=\(String(describing: type(of: error)), privacy: .public)")
    guard case .estimating = state else { return }
    state = .refused(.noScaleAvailable, retryStage: retryStage)
}
```

That maps every non-`EstimationFailure` error (including every `SegmentationError` case except `noFoodPixels`, every `PixelBufferAdapter.ConversionError` once this spec lands, every `MetricScaleError` case other than `noScaleAvailable`, every persistence error, and every CoreML inference error) onto the single UI string "Meal scale unknown" (`App/RefusalSheet.swift:44`). That string is owned by `EstimationFailure.noScaleAvailable` and is correct only for that case. The 2026-06-04 device log shows the failure pattern: `event=estimate.end success=false error=SegmentationError` followed by a "Meal scale unknown" refusal modal that the user cannot dismiss into a productive next step.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the pipeline throws an error that is not an `EstimationFailure` case, THEN the UI SHALL surface a refusal whose label is distinct from "Meal scale unknown" and whose icon and message do not falsely imply a scale problem. The exact wording is left to design.md; the requirement is non-confusion.
2. <a name="6.2"></a>WHEN such an error is surfaced, THEN the refusal payload SHALL retain enough information (at minimum, the error type's Swift name as `String(describing: type(of: error))`) for the device log's `event=estimate.end success=false error=<Type>` line to be correlated with the on-screen message at debug time.
3. <a name="6.3"></a>The new refusal SHALL NOT regress any existing `EstimationFailure` case's UI label or symbol — the catch-all replacement only affects the previously-unmatched error path.
4. <a name="6.4"></a>WHEN `pipeline.estimate(...)` throws `PixelBufferAdapter.ConversionError` (newly introduced by this spec), THEN the catch-all SHALL route it to the new refusal label rather than to `.noScaleAvailable` — i.e., the new label is the correct outcome for the entire untyped-error path including this spec's own new error type.
5. <a name="6.5"></a>The mapping change SHALL be unit-tested via a synthetic injected pipeline error that exercises the catch-all branch of `CaptureFlowModel.runEstimation`, asserting that the resulting `CaptureState` is the new refusal case and NOT `.refused(.noScaleAvailable, …)`.
