# Estimation diagnostics (snaq-parity lane A)

State as of tasks 1–8 (diagnostics foundation + outcome store + write-behind).
The log browser and benchmark phases build on these seams.

## The pattern: outcome structs, not throws

Three stages now return non-throwing outcome structs so measurements survive
refusals (Req 3.1/3.2):

- `VolumeOutcome<Estimate>` (`MedataCore/Sources/Volume/VolumeTypes.swift`):
  `estimate` non-nil iff `refusal` nil; `stats: VolumeStats` populated on both
  exits (pre/post-β per-class volumes, β applied, threshold-discarded classes,
  degenerate voxel/ray skip counts, LiDAR coverage). `VoxelCarveEstimator.carve`
  and `HeightFieldEstimator.integrate` no longer throw.
- `SupportPlaneFitOutcome` (`MedataCore/Sources/SupportPlane/SupportPlaneFitter.swift`):
  same shape; `SupportPlaneFitStats` replaced the `LiDARPlaneFitter.debugLast*`
  statics (deleted). The protocol requirement is `fitOutcome(...)`; a protocol
  extension and `LiDARPlaneFitter.fit(_:)` provide throwing conveniences so
  harness/tests that don't need stats keep the old call shape.
- `SegmentationResult` gained `timings: SegmentationTimings?` (preprocess /
  prediction / argmax ms, measured in Release — Decision 11, Req 4.1) and
  `foodCoveragePercent: Float?`. Both nil for hand-built results (harness
  fixtures); `CoreMLSegmenter.segment` always populates them.

## PipelineDiagnostics / EstimationAttemptRecord

`MedataCore/Sources/Pipeline/PipelineDiagnostics.swift`.

- `PipelineDiagnostics` is a non-Sendable reference type created at the top of
  `Pipeline.estimate`; the body (`runEstimation`) appends stage measurements.
  `Pipeline.estimate` wraps the body in a do/catch: success is stamped inside
  the body (needs macros/confidence for the Req 3.4 decomposition), failures
  in the catch ladder. `CancellationError` produces NO record (user-abandoned
  capture must not depress benchmark completion rates).
- `delegate?.didCompleteAttempt(diagnostics.snapshot())` fires exactly once per
  non-cancelled attempt, after stamping.
- `EstimationAttemptRecord` is Codable + Sendable + Equatable. Founding
  required fields: `v`, `timestampMs`, `outcome`, `modelVersion`,
  `capturePath`; everything else optional so the browser tolerates older rows.
  Failure encodes as `{domain, case, payload}` (`caseName` maps to the JSON
  key `case`). `stampError` stores `String(describing: error)` so Release
  keeps the underlying description (Req 3.3). No raw imagery ever (Req 2.6).
- `withPreShutterSegmentationErrorCount(_:)` returns a copy — CaptureFlowModel
  merges the `PreShutterSegmenter.segmentationErrorCount` snapshot at persist
  time; the counter never crosses `CaptureResult`.

## Outcome store + write-behind (tasks 6–8)

- Store surface: `saveEstimationOutcome` / `estimationOutcomes(limit:)` on
  `PersistenceStore`; row shape, split eviction bounds, and the (timestamp, id)
  tie-break are in `docs/agent-notes/persistence.md`. The
  `EstimationOutcome(record:benchmarkMealID:)` bridge lives in Pipeline
  (PipelineDiagnostics.swift) because Persistence cannot see the typed record.
- **The pipeline's `delegate` is stamped inside `CaptureFlowModel.init`** —
  `Pipeline` is a struct, so `pipeline.delegate = model` after construction in
  App.swift would mutate a dead copy. The init downcasts
  `any PipelineEstimator` to `Pipeline`, sets the weak delegate on its own
  copy, and reassigns `self.pipeline`. Mock estimators skip the cast.
- `didCompleteAttempt` persists via `Task.detached` (write-behind, Req 2.4):
  cancelling the flow can never cancel the persist. Store errors are logged to
  the Shutter category and swallowed (MaskArtefactWriter precedent).
- Pre-shutter error merge is a **per-attempt delta**: the producer's counter is
  lifetime-cumulative with no reset, so `preShutterErrorBaseline` is reset in
  `capturePresented()` and advanced to the counter's value at each persist;
  the persisted field is `max(0, count − baseline)`. Persisting the raw counter
  would misattribute every earlier attempt's errors to the current one.
- Capture-stage refusals in `performFlow`'s catch ladder (worldTrackingDegraded,
  pre-pipeline `EstimationFailure`, non-typed errors) write slim records:
  outcome refused, failure domain `"capture"`, no stage measurements,
  `modelVersion` = the `segmenterSource` init parameter (App.swift passes
  `Pipeline.segmenterSource`, now public). `CancellationError` writes nothing.
- `CaptureFlowModel.benchmarkMealID: UUID?` tags rows while set (lane B sets
  and clears it; nothing writes it yet as of task 8).

## Gotchas

- `PipelineDiagnostics.recordScale(source:cardFallback:)` ORs `cardFallback`
  (sticky) — the card-detection fallback record must not be clobbered by the
  scale-stage record.
- Pipeline maps volume refusals via `estimationFailure(fromVolumeRefusal:)`:
  the two typed cases keep their `EstimationFailure` mapping; any other
  `VolumeError` (e.g. `mismatchedViewDimensions`) propagates unchanged, as the
  old uncaught throw did.
- Height-field estimate still returns sub-`minVolumeCm3` classes in
  `perClassVolumesCm3` (pre-existing behaviour); the threshold only gates the
  `noFoodVolumeRecovered` refusal. `VolumeStats.thresholdDiscardedClasses`
  names them.
- The `noLidarDevice` copy now states the iPhone 16 Pro floor (Decision 22,
  Req 3.5).
