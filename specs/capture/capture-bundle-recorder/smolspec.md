# Capture Bundle Recorder

## Overview

Every estimation attempt persists an `EstimationAttemptRecord` (stats only) — but the inputs that produced a bad estimate (RGB frame, depth map, segmentation output) are discarded, so field failures cannot be reproduced. This feature records a `PbMealFixture` bundle per attempt to `Documents/captures/`, exposed in the Files app, so any capture can be replayed offline through the existing Mac harness (`HarnessCore/FixtureRunner.swift`) with no harness changes. Developer-phase tooling: always on, no UI.

## Requirements

- The system MUST write one fixture bundle per estimation attempt that reaches `Pipeline.estimate`, for successes, typed refusals, and non-typed errors alike — including in Release builds (the research branch is pre-release; a field-day build must record). Recording MUST NOT be gated by `DEBUG` or `HARNESS_ENABLED`.
- The system MUST NOT write a bundle for cancelled attempts (mirroring the attempt-record rule) or for capture-stage refusals that never reach the pipeline (no imagery exists to record).
- Each bundle MUST replay through `FixtureLoader.load` + `FixtureRunner.run` unmodified. Concretely: probability tensors and argmax at the camera resolution the intrinsics declare (the replay path sizes from intrinsics and the height-field silhouette test consumes the background-probability channel per pixel — argmax alone is insufficient), nadir depth, intrinsics, gravity, estimator path `single_dominant`, and the segmenter version stamp `Pipeline.segmenterSource` (compared verbatim against `--checkpoint-sha256`). Oblique-view data MUST be included when the attempt captured it.
- Each bundle MUST carry provenance for replay fidelity: `palette_version` (from `CaptureResult.paletteVersion`), `database_edition` (from the pipeline's `FoodDatabase.currentEdition`), `fixture_revision` `"rev-1"` (the `tools/segmenter/make_fixtures.py` convention), and `fixture_id` = the attempt's `timestampMs`.
- The nadir RGB frame MUST be stored as PNG-encoded RGB8 (explicit BGRA→RGB8 repack before encode — the fixture contract; replay never decodes it, but Python re-segmentation tooling will).
- Bundle filenames MUST be `<timestampMs zero-padded to 13 digits>-<outcome>.fixture` so Estimation Log rows join to bundles and `FixtureLoader`'s lexicographic sort is chronological; on a filename collision a numeric suffix is appended, never an overwrite.
- Recording MUST NOT alter, delay, or fail the estimation result: only Sendable values (`CaptureResult`, `SegmentationResult`, scalars) are extracted and handed to a write-behind task — never the non-Sendable `PipelineDiagnostics` object — and any recording error is logged and swallowed (`MaskArtefactWriter` precedent).
- Bundle writes MUST be serialised one at a time (actor), bounding transient memory to a single in-flight encode.
- A partially written bundle MUST never be left on disk (write-to-temp then rename).
- Bundle files MUST be visible and deletable in the iOS Files app — the only management surface; no in-app UI.
- Ground-truth fields MAY be left zero at record time; back-filling weighed truth is done off-device.

## Implementation Approach

- **New: `MedataCore/Sources/Pipeline/CaptureBundleRecorder.swift`** — an actor that assembles a `PbMealFixture` from the attempt's `CaptureResult` + `SegmentationResult`(s) and writes it atomically to a directory URL injected at init. Follows `MaskArtefactWriter.swift` (same module) for the log-and-swallow posture and ImageIO PNG encoding; Pb bridging for frames/depth/intrinsics exists in `MedataCore/Sources/CaptureKit/Bridges.swift` (exercised by `RoundTripTests`). `ProbabilityTensor.bytes` (FP16 LE HWC) and `ArgmaxMap.pixels` (UInt8 [H,W]) copy byte-for-byte into the fixture.
- **`MedataCore/Sources/Pipeline/Pipeline.swift`** — optional `bundleRecorder` property injected at `Pipeline.init` (present at construction, so the post-construction delegate-stamping dance in `CaptureFlowModel.init` is NOT needed; nil default keeps harness/tests unchanged). `runEstimation` stashes the nadir/oblique `SegmentationResult` on the `PipelineDiagnostics` reference object (carrier only — NOT encoded into `EstimationAttemptRecord`; snaq-parity Req 2.6 applies to the record, not to bundles). `estimate`'s success path and both catch arms extract the Sendable payload and fire the recorder after `didCompleteAttempt`.
- **`App/App.swift`** — constructs the recorder with `Documents/captures/` and passes it to `Pipeline.init`.
- **`MeData/Info.plist`** — add `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` (both `true`).
- **Dependencies**: `PortableContracts`, ImageIO, the snaq-parity diagnostics seam.
- **Out of Scope**: bundles for pre-pipeline capture refusals; ground-truth back-fill tooling; storage eviction; any Settings/in-app UI; harness-side changes (including probs compression or a background-channel-only tensor — future levers if bundle size becomes limiting); the two-view descope decision.

## Risks and Assumptions

- Risk: bundles are ~200 MB each — the probability tensor at camera resolution (1920×1440×35 classes×FP16 ≈ 190 MB) dominates; a 30-capture field day is ~6 GB | Mitigation: nightly clear via Finder/Files app; accepted for the MVP week because full-resolution probs are the only zero-harness-change option that replays exactly (see decision log).
- Risk: transient memory spike (~200 MB serialisation copy) on top of the ~190 MB `SegmentationResult` the pipeline already retains, during a live ARKit session | Mitigation: actor-serialised writes bound this to one in-flight encode; verify on device via a capture session with recorder active — no memory-warning kills, result latency per the Estimation Log stage timings comparable to pre-recorder records.
- Risk: raw meal imagery lands in Documents, Finder-visible | Mitigation: developer-phase only; recorded in the decision log as a pre-release checklist item (gate or remove before any non-developer build).
- Assumption: attempts arrive ≥ seconds apart (capture flow pacing), so the one-at-a-time write queue never accumulates a deep backlog of retained payloads.
- Prerequisite: none — all consumed types and the harness replay path exist on the research branch.
