# Pipeline factory wiring — status and next steps

**Status:** Largely landed. The 2026-05-23 investigation below is **superseded** —
the real factory, the RGB conversion, and `VisionCardDetector` have all since
shipped. The only remaining blocker is **Blocker 1 (no trained segmenter
checkpoint)**. The rest of this note is kept as historical context; see the
"Update (current state)" section directly below for what's actually true now.

## Update (current state)

What changed since the original 2026-05-23 investigation:

- **`PendingPipeline` is gone.** `App/App.swift` now wires a real pipeline via
  `Pipeline.makeForDevice(store:cardDetector:)`
  (`MedataCore/Sources/Pipeline/PipelineFactory.swift`). Engine selection is a
  compile-time gate: `DEV_STUB_SEGMENTER` (Phase 1/Debug) uses
  `StubInferenceEngine` and stamps `segmenterSource = "dev_stub"`; without it
  (Phase 3/Release) it loads the bundled Core ML model. So **Step 3 below is
  done** and **Step 1 (Blocker 2) is done** (see next bullet).
- **Blocker 2 (YCbCr→RGB) is resolved.** `copyPixelBufferBytes` /
  `detectPixelFormat` are deleted; `PixelBufferAdapter.convert`
  (`MedataCore/Sources/CaptureKit/PixelBufferAdapter.swift`) converts captured
  frames to BGRA8 at the capture boundary and `pixelFormat` is now truthful.
  Shipped via `specs/capture/rawframe-rgb-conversion/` (all tasks complete).
- **`VisionCardDetector` exists** (`App/VisionCardDetector.swift`) — so **Step 4
  below is done**, not deferred. Tests use `NullCardDetector`
  (`MedataCore/Sources/Pipeline/NullCardDetector.swift`, a production source file
  now, not lifted from a test target).
- **Artefact name is settled: `segmenter.mlpackage`.** `export.py`, `.gitignore`,
  and `PipelineFactory.makeSegmenter` all use that one name — no renaming step.
  The loader resolves it via `Bundle.module` and the resource is declared in
  `Package.swift` (`.copy("Resources")`); see `docs/architecture.md` §9.

**Bottom line:** only **Blocker 1** (train + export the checkpoint) remains.
Everything else in the original note is history.

---

## Original investigation (2026-05-23, superseded)

> The remainder of this note records the state at the time of the 2026-05-23
> investigation. It is retained for context; see the update above for what is
> true now.

The iOS app at the time wired `pipeline: PendingPipeline()` in `App/App.swift`. `PendingPipeline.estimate(_:)` unconditionally threw `EstimationFailure.noScaleAvailable`. The user-visible effect was that every tap of the shutter resulted in an `Estimating…` flash followed by the refusal banner — the pipeline was *engaged* (the protocol call went through) but could not *produce* a `MealRecord` because the real `Pipeline` factory was not constructed.

This was by design, documented at the time in:
- `specs/ui/iphone-experience/requirements.md:14` Out of Scope: *"Bundling the Core ML segmenter weights (separate smolspec)"*
- `App/App.swift` PendingPipeline doc-comment: *"used until the segmenter-weights smolspec bundles the Core ML model and a real `Pipeline` factory lands"*

Wiring the real factory was attempted as a smolspec on 2026-05-23 and parked when two upstream blockers were discovered. This note records them and what's needed to unblock.

## Blocker 1 — no segmenter checkpoint

`tools/segmenter/export.py` produces `MedataCore/Resources/segmenter.mlpackage` from a fine-tuned PyTorch checkpoint. The export script works; the **checkpoint does not exist** in the repo, agent-notes, or any branch. The model artefacts are explicitly `.gitignore`d:

```
MedataCore/Resources/segmenter.mlpackage/
MedataCore/Resources/segmenter.mlmodel
MedataCore/Resources/segmenter.mlmodelc/
```

Producing the checkpoint requires:

- A PyTorch training environment with `torchvision`, `coremltools` 8.x, `ai-edge-torch` (per `specs/estimation/pipeline/prerequisites.md:17`)
- The FoodSeg103 dataset (per `specs/estimation/pipeline/prerequisites.md:18`)
- A GPU and time to transfer-learn DeepLabV3 + MobileNetV3-Large to the 27-class palette (24 food + background + unknown_food + unsupported_liquid)
- Held-out labelled test set to measure mIoU against the bar in research Req 8.9 (`specs/estimation/pipeline/prerequisites.md:23`)
- Apple Neural Engine residency verification in Xcode's Core ML performance report (`specs/estimation/pipeline/prerequisites.md:25`)

This is days of ML work, not a code task. It is **the** prerequisite for the food-estimation pipeline going live.

## Blocker 2 — `RawFrame.imageBytes` is unusable for RGB consumers

> **RESOLVED** (see "Update (current state)" above). Shipped via
> `specs/capture/rawframe-rgb-conversion/` — `PixelBufferAdapter` now converts to BGRA8.
> The diagnosis below is retained as the historical record of the bug.

Any code that needs to read the captured image as RGB — the segmenter pre-processor, a future `VisionCardDetector`, or anything else hitting `CGImage` / `Vision` — needs `RawFrame.imageBytes` to be a known-format contiguous RGB buffer. It isn't.

### What's wrong

`ARFrame.capturedImage` is a `CVPixelBuffer` with format `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (biplanar YCbCr). `ARKitCaptureEngine.copyPixelBufferBytes` (`MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:315-321`) reads from it as if it were chunky non-planar:

```swift
private func copyPixelBufferBytes(_ buffer: CVPixelBuffer) -> Data {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Data() }
    let length = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
    return Data(bytes: base, count: length)
}
```

For biplanar buffers Apple documents `CVPixelBufferGetBaseAddress` as returning the plane-0 base (Y plane) or nil. `CVPixelBufferGetBytesPerRow` returns plane-0 stride. So the call either returns empty `Data` or the luma plane only — never anything Vision or a segmenter pre-processor can consume.

`detectPixelFormat` (`ARKitCaptureEngine.swift:307-313`) compounds it:

```swift
case kCVPixelFormatType_32BGRA: return .bgra8
case kCVPixelFormatType_32RGBA: return .rgba8
default: return .bgra8   // ← lies for YCbCr
```

YCbCr falls into the default branch and the frame claims to be `.bgra8`. Anything downstream that trusts `pixelFormat` reads the wrong layout.

### Why this matters more than it looks

Both the segmenter and `VisionCardDetector` are blocked on this. Bundling a trained segmenter `.mlpackage` would still produce wrong results because `SegmenterPreProcessor` would consume miscoded bytes. Writing `VisionCardDetector` against the current shape silently fails — Vision can't reconstruct a `CGImage` from luma-only data.

### Scope

This is its own piece of work, not a smolspec:

- Choose a target RGB-family format for `RawFrame.imageBytes` (BGRA likely, since CoreImage and Vision both consume it natively)
- Convert YCbCr → BGRA in `buildRawFrame`, using `vImage` / `CIContext` / `CVPixelBufferCreate` + Metal — pick one based on performance and memory budgets (research Req 16.1 / 16.7 give the wall-clock floor)
- Update `detectPixelFormat` to return the actual format, not the default
- Decide where the conversion lives — `ARKitCaptureEngine` is the only place that has `CVPixelBuffer`, so probably here; alternatively introduce a `PixelBufferAdapter` boundary so the conversion is testable in isolation
- Tests: synthesise a known-content YCbCr `CVPixelBuffer`, run it through the conversion, assert RGB output matches a hand-computed reference patch

It touches one source file but is load-bearing for every downstream consumer of `imageBytes`. Probably a full spec or at minimum a careful smolspec with its own decision-log entry. Affects the `RawFrame` contract — anyone who has tested against `imageBytes.count == bytesPerRow × height` will need to update.

## What is *not* blocked

- LiDAR-path scale resolution. The pipeline's `fitSupportPlane` uses LiDAR when available and only falls back to the card-plane path when LiDAR coverage is insufficient. v1 hardware floor (research Req 1.2) is iPhone 13 Pro Max with rear LiDAR, so on-target devices have a usable scale source without a card detector. A real `Pipeline` could be wired today with `NilCardDetector` (already exists at `MedataCore/Tests/PipelineTests/EstimationFailureTests.swift:168`, would need lifting to production code) — provided segmenter weights exist (which they don't, hence Blocker 1).

## Next steps — order of operations

> **Mostly superseded.** Steps 1, 3, and 4 below have shipped (see "Update
> (current state)" above). Only **Step 2 (train + export the segmenter
> checkpoint)** plus the minor `Bundle.module`/`Package.swift` loader tidy-up
> remain. The sequenced list is kept for the rationale.

These were sequenced. Do not skip ahead.

### 1. Resolve Blocker 2 (RawFrame YCbCr → RGB)

**Owner:** whoever picks up the pipeline next.

**Why first:** unblocks both Blocker 1's downstream consumer (the segmenter) and any future VisionCardDetector. Doable without ML infrastructure. Spec-able and testable in isolation. Without this, even a perfect segmenter checkpoint produces wrong results.

**Output:** `RawFrame.imageBytes` is a contiguous BGRA (or chosen target format) buffer; `RawFrame.pixelFormat` accurately reports the format; a test fixture proves round-trip from YCbCr `CVPixelBuffer` → RGB bytes.

**Acceptance:** new tests in `MedataCore/Tests/CaptureKitTests/` pass on iOS Simulator; existing tests still pass; tasks 12–17 of the UI spec (the capture-flow tests) still pass.

**Estimate:** 1–2 days. Probably its own spec (`specs/capture/rawframe-rgb-conversion/` or similar).

### 2. Resolve Blocker 1 (train + export segmenter)

**Owner:** ML engineer or person with PyTorch + GPU access.

**Why second:** needs Step 1's RGB pipeline to be correct, otherwise the model trained on properly-converted inputs will see miscoded bytes at runtime.

**Output:** `MedataCore/Resources/segmenter.mlpackage` produced by `tools/segmenter/export.py`, size ≤10 MB (research Req 8.2), per-view inference ≤250 ms on iPhone 13 Pro Max (research Req 8.3 — v1 hardware floor per Req 1.2), mIoU bar per research Req 8.9.

**Acceptance:** `SegmenterWeightsBudget.validate(at:)` passes; `CoreMLInferenceEngine` loads and runs the model on-device with Neural Engine residency confirmed via Xcode's Core ML performance report.

**Estimate:** days, gated on dataset and GPU.

### 3. Wire the real `Pipeline` factory in `App/App.swift`

**Owner:** any iOS developer.

**Why third:** trivial once Steps 1 and 2 are done; pointless before.

**Output:** `App.swift` constructs `Pipeline(cardDetector:, segmenter:, database:, store:)` using:
- `cardDetector`: a production-grade `NilCardDetector` (lift from test target) — leave VisionCardDetector for a future step if needed
- `segmenter`: `CoreMLSegmenter(modelPath: Bundle.main.url(forResource: "segmenter", withExtension: "mlmodelc")!.path, palette: .v1Standard, engine: try CoreMLInferenceEngine(modelPath:, useNeuralEngine: true, targetSize: 513))`
- `database`: `try GRDBFoodDatabase.bundled()` (already exists)
- `store`: existing wiring at `App.swift:61-71`

`PendingPipeline` can be removed in the same change, or kept behind a bundle-presence check for development builds without weights.

**Acceptance:** end-to-end on iPhone 13 Pro Max — tap shutter → real estimation → `MealRecord` reaches the result view with a non-placeholder carb total.

**Estimate:** smolspec-sized, <50 LOC across 1–2 files.

### 4. (Optional, deferred) `VisionCardDetector`

**Owner:** any iOS developer, after Step 1.

**Why optional:** v1 hardware floor has LiDAR, which is sufficient for scale. The card path is only relevant if the v1 floor is relaxed to non-LiDAR devices — that direction is signalled in `ARKitCaptureEngine.swift:16-18`:

> *"The hardware-floor refusal (Req 1.3) is no longer enforced at this boundary so non-LiDAR developer / test devices run the full app in both Debug and Release."*

So it's loosened but not productionised. Don't build VisionCardDetector until that policy is settled.

**If you do build it:**
- New file `App/VisionCardDetector.swift`
- `VNDetectRectanglesRequest` with `minimumAspectRatio: 1.5`, `maximumAspectRatio: 1.7` (ID-1 is 85.60/53.98 ≈ 1.586), `maximumObservations: 1`
- Reconstruct a `CGImage` from `RawFrame.imageBytes` (relies on Step 1)
- Map Vision's normalised origin-bottom-left observation corners to `PixelCorner` in pixel origin-top-left in the **TL, TR, BR, BL** order matching `ISO7810.cornersMm` at `MedataCore/Sources/CardDetection/CardPoseSolver.swift:11-16`
- Estimate: smolspec-sized, ~60 LOC + tests

## Pointers

- Real `Pipeline` shape: `MedataCore/Sources/Pipeline/Pipeline.swift:27-44`
- `PendingPipeline` placeholder: `App/App.swift:79-83`
- Card detector contract + ordering convention: `MedataCore/Sources/CardDetection/CardPoseSolver.swift:5-23`
- Segmenter constructor + weights budget: `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift:18-44, 66-91`
- Bundled food DB factory: `MedataCore/Sources/Foods/GRDBFoodDatabase.swift:21-30`
- Persistence store wiring: `App/App.swift:61-71`
- Segmenter export pipeline + README: `tools/segmenter/export.py`, `tools/segmenter/README.md`
- ML prerequisites: `specs/estimation/pipeline/prerequisites.md`
- Sibling fix (camera config race) that came out of the same investigation: `specs/bugfixes/arview-session-config-race/report.md`, `docs/agent-notes/camera-input-fix.md`
