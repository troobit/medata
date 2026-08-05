---
references:
    - specs/capture/capture-bundle-recorder/smolspec.md
    - specs/capture/capture-bundle-recorder/decision_log.md
---
# Capture Bundle Recorder

- [x] 1. Recorder produces harness-replayable bundles <!-- id:9r168or -->
  - CaptureBundleRecorder actor in MedataCore/Sources/Pipeline assembles a PbMealFixture (camera-resolution probs/argmax byte-for-byte, depth, intrinsics, gravity, BGRA-to-RGB8 PNG, provenance stamps per smolspec) and writes it atomically (temp+rename) with log-and-swallow error posture
  - Verified by a MedataCore round-trip test: a recorder-written bundle parses, passes FixtureLoader.validate for estimator path single_dominant with the stamped version string, and its tensor dimensions agree with the intrinsics (FixtureRunner sizing contract); make test green

- [x] 2. Every pipeline attempt records a bundle <!-- id:9r168os -->
  - Pipeline.estimate hands the Sendable payload (CaptureResult, stashed SegmentationResults, timestampMs, outcome) to the injected recorder on the success path and both catch arms, after didCompleteAttempt; cancellation and pre-pipeline refusals record nothing; recorder injected at Pipeline.init with nil default
  - Verified: existing PipelineTests unaffected with nil recorder, plus a test proving a refused attempt still records a bundle; make test green (report both totals)
  - Blocked-by: 9r168or (Recorder produces harness-replayable bundles)

- [x] 3. Bundles reachable from the Files app on device builds <!-- id:9r168ot -->
  - App.swift constructs the recorder over Documents/captures and passes it to Pipeline.init; MeData/Info.plist gains UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace; recording gated by neither DEBUG nor HARNESS_ENABLED
  - Verified: make build succeeds and the iOS app target builds
  - Blocked-by: 9r168os (Every pipeline attempt records a bundle)

- [-] 4. On-device pass confirms field-day readiness <!-- id:9r168ou -->
  - Deploy to the iPhone 16 Pro (match buildStamp), run success and refusal captures: bundles appear in the Files app, filenames join to Estimation Log timestampMs rows, stage timings comparable to pre-recorder records, no memory-warning kill
  - Close-out replay DONE 2026-08-05: `1785135663727-success.fixture` (195 MB, 27 Jul, palette v2) pulled with `devicectl copy from` and replayed through `make harness-accuracy`. It exposed two defects and one measurement, all now recorded — see docs/agent-notes/estimation-diagnostics.md 'Replaying a device bundle'
  - Defect 1 (FIXED): `HarnessCLI` hard-coded `ClassPalette.v1Standard`, so `C` was 35 against a 36-channel v2 bundle and `ProbabilityTensor`'s size precondition TRAPPED the process — no report, whole run lost. The palette is now resolved per fixture from its own `paletteVersion` via the existing `ClassPalette.standard(for:)`; empty/v1 labels resolve to v1 exactly as before, so N5k fixtures are unaffected. `seg-bench` had the same bug behind a size guard, which silently dropped every v2 bundle instead of trapping
  - Defect 2 (FIXED): `FixtureRunner.run` now throws `probsSizeMismatch` instead of relying on that precondition — a batch tool over operator-supplied files must skip a malformed bundle, not crash and lose every other fixture's result
  - Measurement: the replay produced bread_wholemeal **98.92 g** carbs against the device's own recorded **103.71 g** for the same attempt — **-4.79 g, -4.6 %**. Replay is close but NOT bit-exact, so a replayed error figure is not the device's figure. Truth is zero as designed, so it correctly reported UNSCORED and exited non-zero (that is the harness working, not a failure)
  - Still outstanding on this task: the on-device half — bundles in the Files app, filenames joining to Estimation Log rows, stage timings, no memory-warning kill; plus the estimation-diagnostics note and make spell
  - Blocked-by: 9r168ot (Bundles reachable from the Files app on device builds)
