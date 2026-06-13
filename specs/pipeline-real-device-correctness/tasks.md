---
references:
    - specs/pipeline-real-device-correctness/requirements.md
    - specs/pipeline-real-device-correctness/design.md
    - specs/pipeline-real-device-correctness/decision_log.md
    - specs/pipeline-real-device-correctness/prerequisites.md
---
# Pipeline Real-Device Correctness — Tasks

## MedataCore

- [x] 1. Write tests for SupportPlaneFitter protocol contract <!-- id:81wvfiq -->
  - New test file: MedataCore/Tests/SupportPlaneTests/SupportPlaneFitterTests.swift (or extend an existing SupportPlane test target file).
  - Cover the 2x2 decision table in design SupportPlaneFitter section: (depth nil | mask nil -> throws), (depth nil | mask empty -> throws), (depth nil | mask non-empty -> CardOnlyPlaneFitter branch returns finite plane on the existing card-only fixture), (depth present | mask nil -> throws), (depth present | mask empty -> throws), (depth present | mask non-empty -> LiDARPlaneFitter branch returns finite plane on synthetic fruit-plate fixture).
  - Empty-mask cases must throw EstimationFailure.noFoodPixels regardless of depth presence (Req 3.1 / Decision 2).
  - Reuse the synthetic depth fixture from SupportPlaneRoughMaskTests.swift for the LiDAR branch.
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 2. Implement SupportPlaneFitter protocol + LiDARSupportPlaneFitter + add CaptureResult.preShutterFoodMask field <!-- id:81wvfir -->
  - New file: MedataCore/Sources/SupportPlane/SupportPlaneFitter.swift containing the public protocol SupportPlaneFitter and public struct LiDARSupportPlaneFitter per design SupportPlaneFitter section.
  - Empty-mask rejection happens at the protocol entry, BEFORE the LiDAR-vs-card dispatch (Decision 2 / 2x2 decision table).
  - LiDARSupportPlaneFitter wraps the existing LiDARPlaneFitter.fit(_:) and CardOnlyPlaneFitter.fit(_:) call sites currently inlined in Pipeline.fitSupportPlane; SupportPlaneError -> EstimationFailure mapping is preserved unchanged.
  - Add `public let preShutterFoodMask: BinaryMask?` to CaptureResult (MedataCore/Sources/Pipeline/CaptureResult.swift), defaulted to nil in the initialiser so existing call sites compile.
  - All existing tests in PipelineTests and SupportPlaneTests must continue to pass.
  - Blocked-by: 81wvfiq (Write tests for SupportPlaneFitter protocol contract)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 3. Move NullCardDetector to its own file; change PipelineFactory.makeForDevice signature <!-- id:81wvfis -->
  - Move the private NullCardDetector struct out of MedataCore/Sources/Pipeline/PipelineFactory.swift into a new file MedataCore/Sources/Pipeline/NullCardDetector.swift with internal visibility.
  - Change PipelineFactory.makeForDevice signature to (store:cardDetector:palette:supportPlaneFitter:) per design PipelineFactory signature section. cardDetector is required (no default). supportPlaneFitter defaults to LiDARSupportPlaneFitter().
  - Remove the inline NullCardDetector() construction from makeForDevice; production builds wire VisionCardDetector from the App caller per task 14.
  - Existing MedataCore tests that called makeForDevice directly are updated to pass cardDetector: NullCardDetector() (now internal) explicitly.
  - Blocked-by: 81wvfir (Implement SupportPlaneFitter protocol + LiDARSupportPlaneFitter + add CaptureResult.preShutterFoodMask field)
  - Stream: 1
  - Requirements: [5.2](requirements.md#5.2)

- [x] 4. Write tests for StubInferenceEngine centred-ellipse output <!-- id:81wvfit -->
  - Update MedataCore/Tests/SegmentationTests/StubInferenceEngineTests.swift: rewrite testArgmaxOfEveryPixelEqualsDominantClass_defaultDominantZero, testArgmaxOfEveryPixelEqualsDominantClass_explicitDominantFive, and testDominantClassProbabilityAtLeastZeroPointNineNine per design StubInferenceEngine test impact table.
  - Add a new test asserting the food-pixel count is within 28-32% of `targetSize x targetSize` for targetSize = 256 (Decision 8: 30 +/- 2%).
  - Add a test asserting outside-ellipse pixels have mBackground >= 0.99 and inside-ellipse pixels have mDominant >= 0.99.
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5)

- [x] 5. Implement StubInferenceEngine centred-ellipse predicate <!-- id:81wvfiu -->
  - Modify MedataCore/Sources/Segmentation/StubInferenceEngine.swift per design StubInferenceEngine section: replace the uniform-dominant write loop with the centred-ellipse predicate (alpha = 0.618; inside -> dominant logit; outside -> background-class logit).
  - Tests rewritten in task 4 must now pass.
  - Audit HarnessCore/FixtureRunner.swift:153,221 and refresh any fixtures that pin pre-change spatial distribution.
  - Blocked-by: 81wvfit (Write tests for StubInferenceEngine centred-ellipse output)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5)

- [x] 6. Write tests for computeFoodRegionCoverage (256x192 confidence-buffer space) <!-- id:81wvfiv -->
  - New test file: MedataCore/Tests/PipelineTests/FoodRegionCoverageTests.swift.
  - Test: mask 1920x1440 with food-area >= 10000 pixels + synthetic 256x192 confidence buffer where 50% of food-projected pixels pass threshold -> returns 50% +/- 1% (Req 8.4).
  - Test: mask empty -> returns 0 (Req 4.2).
  - Test: depth confidence absent (nadir.depth == nil) -> returns 0 (Req 4.2).
  - Test: floor-projection algebra: at 256x192 confidence pixel (cx, cy), mask pixel is floor(cx * W_colour / 256, cy * H_colour / 192) (Decision 14).
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [8.4](requirements.md#8.4)

- [x] 7. Implement computeFoodRegionCoverage; integrate Pipeline.estimate with SupportPlaneFitter, mask, and recomputed coverage; add logging <!-- id:81wvfiw -->
  - Add computeFoodRegionCoverage(confidenceMap:confidenceThreshold:mask:colourWidth:colourHeight:) to MedataCore/Sources/Pipeline/ (helper file or inline in Pipeline.swift) per design Pipeline.estimate coverage recompute section.
  - Modify Pipeline.fitSupportPlane to delegate to supportPlaneFitter.fit(nadir:cardPose:corners:preShutterFoodMask:) (keep the SupportPlaneError -> EstimationFailure mapping at the call site).
  - Modify Pipeline.estimate to read captureResult.preShutterFoodMask, pass it through, then call computeFoodRegionCoverage after fitSupportPlane returns.
  - Update Pipeline.init to take supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter() parameter.
  - Logging changes (DEBUG-only, ie.medata.app / Shutter channel): supportplane.start gains source=pre_shutter; estimate.start gains maskAgeMs=<int> (if mask age is not threaded through CaptureResult, add a preShutterMaskAgeMs: Int? companion field in this task and update CaptureResult initialiser); estimate.end gains foodRegionCoveragePercent=<float>.
  - All existing Pipeline / SupportPlane tests must continue to pass; the FoodRegionCoverageTests from task 6 must now pass.
  - Blocked-by: 81wvfir (Implement SupportPlaneFitter protocol + LiDARSupportPlaneFitter + add CaptureResult.preShutterFoodMask field), 81wvfiv (Write tests for computeFoodRegionCoverage (256x192 confidence-buffer space)), 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192, 256x192
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [7.2](requirements.md#7.2), [7.4](requirements.md#7.4)

## Vision Card Detector

- [x] 8. Write tests for VisionCardDetector synthetic ID-1 detection and corner order <!-- id:81wvfix -->
  - New test file: MeData/Tests/VisionCardDetectorTests.swift (Swift Testing).
  - Synthesise a 1920x1440 BGRA buffer containing a single bright ID-1-aspect rectangle on a black background. Assert detector returns four PixelCorners in TL->TR->BR->BL order in RawFrame pixel coordinates (origin top-left, +y down).
  - Test: empty / unrecognisable buffer -> returns nil (Req 5.4).
  - Test: detector latency on the synth fixture is below the warm budget (Req 5.6 -- note this is on-host, not on-device; the on-device check is a manual prerequisite item).
  - Stream: 1
  - Requirements: [8.5](requirements.md#8.5), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6)

- [x] 9. Implement VisionCardDetector with warmup() and carddetect.end logging <!-- id:81wvfiy -->
  - New file: App/VisionCardDetector.swift per design VisionCardDetector section.
  - Configure VNDetectRectanglesRequest with the documented aspect / size / observation params; reuse a single warmRequest instance across calls; construct VNImageRequestHandler with CGImagePropertyOrientation.up; convert BGRA RawFrame.imageBytes to CGImage via CGContext/CGDataProvider.
  - Implement the Vision corner-order -> PixelCorner swap per design (Y-axis flip only since orientation is .up).
  - Implement warmup() that runs VNImageRequestHandler on a 64x64 blank buffer and drops the result (Req 5.7).
  - Add DEBUG-only `event=carddetect.end success=<bool> cornerCount=<int> latencyMs=<int>` log on the existing ie.medata.app / Shutter channel (Req 7.3, 7.4).
  - Blocked-by: 81wvfix (Write tests for VisionCardDetector synthetic ID-1 detection and corner order)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

## Pre-Shutter Producer + Wiring

- [x] 10. Write tests for PreShutterSegmenter (latest-wins, awaitPaused drain, MaskBox identity, cadence violation log) <!-- id:81wvfiz -->
  - New test file: MeData/Tests/PreShutterSegmenterTests.swift.
  - Mock the AsyncStream<ARFrame> source by hand-crafting frames (ARFrame has no public init -- use a protocol seam wrapping the ARFrame consumer, OR test via a nonisolated ingest hook on PreShutterSegmenter that accepts a RawFrame directly bypassing ARFrame conversion).
  - Test: rapid frame ingest only publishes the most recent completed inference's mask (latest-wins; Decision 5).
  - Test: awaitPaused() returns after the in-flight inference completes (Decision 13).
  - Test: latest survives pause() (Req 1.7 / design behavioural contract).
  - Test: two MaskBox references with the same underlying BinaryMask content compare equal via pixel content but reference-identity is checked when needed (Decision 12 / 13).
  - Test: when consecutive publishes are > 500 ms apart, `event=preshutter.cadence.miss` log line is emitted (verify via OSLog test harness or by intercepting Logger calls).
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.7](requirements.md#1.7)

- [x] 11. Implement PreShutterSegmenter with separate CoreMLSegmenter, off-actor conversion, pause/awaitPaused, and pre-shutter logging <!-- id:81wvfj0 -->
  - New file: App/PreShutterSegmenter.swift per design PreShutterSegmenter section.
  - Define MaskBox reference wrapper (avoid 2.7 MB value copies at 2 Hz).
  - Constructor takes a CoreMLSegmenter instance -- App-target callers construct a SEPARATE CoreMLSegmenter from the one passed into Pipeline.makeForDevice (Decision 12).
  - Implement resume(frames:), pause() (fire-and-forget), awaitPaused() (async) per design behavioural contracts.
  - Build RawFrame via PixelBufferAdapter and call segmenter.segment(_:) from a nonisolated helper so MainActor isn't blocked on conversion (design PreShutterSegmenter section).
  - Convert ArgmaxMap -> BinaryMask via existing PipelineBridges.foodMask(from:palette:).
  - DEBUG-only logging: `event=preshutter.mask.update foodPixels=<int> ageMs=<int> source=pre_shutter_stub|pre_shutter_coreml latencyMs=<int>` and `event=preshutter.cadence.miss expectedHz=2 actualMs=<int>` per design Logging section (Reqs 7.1, 7.4).
  - Inflight-task latest-wins discipline per Decision 5: cancel-then-await in awaitPaused(); drop frames while in-flight in resume(frames:).
  - Blocked-by: 81wvfiz (Write tests for PreShutterSegmenter (latest-wins, awaitPaused drain, MaskBox identity, cadence violation log)), cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, cadence, 81wvfiu (Implement StubInferenceEngine centred-ellipse predicate)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)

- [x] 12. Write tests for CaptureFlowModel staleness gate and firstFrameMaskBox lifecycle <!-- id:81wvfj1 -->
  - Extend MeData/Tests/CaptureFlowModelTests.swift (or new CaptureFlowModelPreShutterTests.swift).
  - Test: at shutter-tap, preShutterSegmenter.latest with producedAt > 750 ms ago is treated as unavailable; resulting CaptureResult.preShutterFoodMask == nil and the model's downstream estimate path throws EstimationFailure.noFoodPixels per Req 8.3.
  - Test: each existing `firstFrame = nil` site clears `firstFrameMaskBox = nil` in lockstep (Decision 11 clear-on-X table): backgrounding, interruption.began, scenePhase to background, tab change, trackingDegraded mid-two-view, .initialising re-entry, .refused, .showingResult.
  - Test: nadir-capture path calls await preShutterSegmenter.awaitPaused() before reading latest (test via a spy PreShutterSegmenter or protocol seam).
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [8.3](requirements.md#8.3)

- [x] 13. Integrate PreShutterSegmenter into CaptureFlowModel; wire state-machine resume/pause and freeze-at-nadir snapshot <!-- id:81wvfj2 -->
  - Add `private let preShutterSegmenter: PreShutterSegmenter` to CaptureFlowModel; constructor takes it (or builds it from an injected CoreMLSegmenter).
  - State transitions per design state-machine gating: resume(frames:) on .initialising, .ready, .trackingLost, .armed; pause() on .capturing, .estimating, .showingResult, .refused.
  - Nadir-capture path: after `capture.end success=true` for nadir, `await preShutterSegmenter.awaitPaused()`, then read latest, apply 750 ms staleness check, assign to firstFrameMaskBox (two-view) or use directly in CaptureResult (single-view) per design freeze-at-nadir invariant.
  - Add `private var firstFrameMaskBox: MaskBox?`; clear at every existing `firstFrame = nil` site per Decision 11 lifecycle table.
  - Remove the `frozen.lidarCoveragePercent` wiring at CaptureFlowModel.swift:464; pass LiDARStatus(available:supportsLiDAR, foodRegionCoveragePercent:0) so Pipeline recomputes.
  - Pass preShutterFoodMask through to CaptureResult construction.
  - Blocked-by: 81wvfj0 (Implement PreShutterSegmenter with separate CoreMLSegmenter, off-actor conversion, pause/awaitPaused, and pre-shutter logging), 81wvfj1 (Write tests for CaptureFlowModel staleness gate and firstFrameMaskBox lifecycle), 81wvfir (Implement SupportPlaneFitter protocol + LiDARSupportPlaneFitter + add CaptureResult.preShutterFoodMask field)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [4.3](requirements.md#4.3)

- [x] 14. Wire App.swift and CaptureFlowView.swift: construct VisionCardDetector, PreShutterSegmenter, and start producer; warmup Vision request on .ready <!-- id:81wvfj3 -->
  - App/App.swift: construct VisionCardDetector() and a dedicated CoreMLSegmenter for the pre-shutter producer (separate instance per Decision 12); pass both into PipelineFactory.makeForDevice and CaptureFlowModel respectively.
  - App/CaptureFlowView.swift: alongside `observer.start(frames: engine.frames)` at line 76, call `preShutterSegmenter.resume(frames: engine.frames)` (each call to engine.frames returns an independent per-subscriber stream per ARKitCaptureEngine.swift:111).
  - On entry to .ready state in CaptureFlowModel, kick off `Task { await visionCardDetector.warmup() }` once per session per Req 5.7.
  - Verify that the existing engine.frames subscription pattern in CaptureFlowView does not need refactoring (independent subscriptions are supported).
  - Blocked-by: 81wvfis (Move NullCardDetector to its own file; change PipelineFactory.makeForDevice signature), 81wvfiy (Implement VisionCardDetector with warmup() and carddetect.end logging), 81wvfj2 (Integrate PreShutterSegmenter into CaptureFlowModel; wire state-machine resume/pause and freeze-at-nadir snapshot)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.7](requirements.md#5.7)

## Integration Test

- [x] 15. Write integration test for mask routing (Req 8.7) <!-- id:81wvfj4 -->
  - New test file: MedataCore/Tests/PipelineTests/PreShutterMaskRoutingIntegrationTests.swift.
  - Implement ProbeFitter: SupportPlaneFitter that records the preShutterFoodMask argument on each fit(...) call.
  - Construct a Pipeline via PipelineFactory.makeForDevice(store:cardDetector:supportPlaneFitter:) injecting a LocalNoOpCardDetector and the ProbeFitter (pattern matches design Integration test section).
  - Build a synthetic plate BinaryMask at 1920x1440, place into CaptureResult.preShutterFoodMask, call Pipeline.estimate(...), and assert `probe.lastFoodMask?.pixels == mask.pixels` byte-identity.
  - Blocked-by: 81wvfiw (Implement computeFoodRegionCoverage; integrate Pipeline.estimate with SupportPlaneFitter, mask, and recomputed coverage; add logging), 81wvfj2 (Integrate PreShutterSegmenter into CaptureFlowModel; wire state-machine resume/pause and freeze-at-nadir snapshot)
  - Stream: 1
  - Requirements: [8.7](requirements.md#8.7), [2.3](requirements.md#2.3), [6.3](requirements.md#6.3)

## Cleanup

- [x] 16. Delete CentreRectangleMask.swift and verify regression sentinel still passes <!-- id:81wvfj5 -->
  - Delete MedataCore/Sources/Pipeline/CentreRectangleMask.swift (the makeCentreRectangleMask helper and the centreRectangleFillFraction constant) per Req 2.2.
  - Remove any remaining inline references; production Pipeline.fitSupportPlane by this point delegates entirely to LiDARSupportPlaneFitter.fit(...) (task 7), so the helper has no callers.
  - Verify MedataCore/Tests/PipelineTests/CentreRectangleMaskTests.swift is also deleted (it pinned the deleted helper's output).
  - Verify the existing MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift all-ones-mask sentinel still passes -- its assertion against LiDARPlaneFitter going degenerate on an all-ones mask is independent of the centred-rectangle helper (Req 8.6).
  - Blocked-by: 81wvfj4 (Write integration test for mask routing (Req 8.7)), routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing, routing
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [8.6](requirements.md#8.6)
