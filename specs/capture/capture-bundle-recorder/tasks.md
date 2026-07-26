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
  - Close-out: pull one bundle to the Mac and replay it through HarnessCLI accuracy mode (zero ground truth tolerated); update docs/agent-notes/estimation-diagnostics.md with the recorder seam and gotchas; make spell green
  - Blocked-by: 9r168ot (Bundles reachable from the Files app on device builds)
