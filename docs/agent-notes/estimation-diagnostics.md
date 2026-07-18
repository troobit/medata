# Estimation diagnostics (snaq-parity lane A)

State as of tasks 1–8 (diagnostics foundation + outcome store + write-behind)
plus the app surfaces (tasks 15–16, below) and the capture-bundle recorder
(specs/capture/capture-bundle-recorder, bottom section).

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
  `capturePresented()` and advanced to the counter's value at each *successful*
  persist (a failed store write leaves the baseline so the window's errors roll
  into the next attempt's delta instead of vanishing with the lost row); the
  persisted field is `max(0, count − baseline)`. Persisting the raw counter
  would misattribute every earlier attempt's errors to the current one.
- Capture-stage refusals in `performFlow`'s catch ladder (typed `CaptureError`
  cases, pre-pipeline `EstimationFailure`, non-typed errors) write slim
  records: outcome refused, failure domain `"capture"`, no stage measurements,
  `modelVersion` = the `segmenterSource` init parameter — required, no default
  (App.swift passes `Pipeline.segmenterSource`, now public). Every
  `CaptureError` case records its real case name (`sessionNotStarted`,
  `captureFailed` with its message as payload, …); only genuinely non-typed
  errors record `internalError`. `CancellationError` writes nothing.
- `CaptureFlowModel.benchmarkMealID: UUID?` tags rows while set (lane B sets
  and clears it; nothing writes it yet as of task 8). The tag is frozen into
  `inFlightBenchmarkMealID` at `beginCapture` and the persist path reads only
  the frozen copy — the write-behind task must not pick up a value the
  benchmark UI cleared/set after the attempt (wrong eviction population).

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

## App surfaces (tasks 15–16)

- `App/EstimationLogView.swift` + `App/BenchmarkView.swift` — Settings
  NavigationLinks beside About, deliberately OUTSIDE `#if DEBUG` (Req 2.3
  Release operation). Both are pushed inside Settings' NavigationStack, so
  neither owns a stack; both reload via `.task` only — no change stream
  exists for these tables by design (quick_presets convention).
- Export (log view toolbar) writes one JSON file (outcomes + benchmark meals
  + the computed report for the current lineage) to `temporaryDirectory` and
  presents `ShareSheet`, same seam as Settings' archive export. Stored
  `measurements`/`failure` JSON strings are embedded structurally via
  `JSONSerialization` so the file is a single well-formed document.
- **Benchmark capture launch route**: BenchmarkView's Capture button →
  `onBenchmarkCapture(mealID)` closure threaded AppRoot → SettingsView →
  BenchmarkView. AppRoot sets `captureModel.benchmarkMealID = mealID`, then
  `pendingDeepLink = .captureCover; activeSheet = nil` — the existing
  deep-link sequencing dismisses Settings fully before presenting Capture
  (covers are mutually exclusive; presenting mid-dismissal is dropped by
  SwiftUI). The tag is cleared in AppRoot's `.onChange(of: activeSheet)`
  ONLY on an `old == .capture` transition — clearing on any non-capture
  value would wipe the tag during the settings → nil handoff.
- The current lineage shown/scoped in both views is
  `captureModel.segmenterSource` (made non-private for this).
- Editing a benchmark meal that has attempts saves under a NEW id in
  `BenchmarkModel.save` — the store's `benchmarkMealImmutable` gate is
  routed around, not tripped. Truth lookups build a second
  `GRDBFoodDatabase.bundled()` lazily (PreShutterSegmenter second-instance
  precedent); the lookup closure is built in a `nonisolated` static so it
  is not MainActor-bound when the store calls it.
- The app links `Benchmark` via the `MedataCore` product
  (Package.swift products list) — the target still depends on Persistence
  only, keeping report maths under `make test`.

## Capture-bundle recorder (specs/capture/capture-bundle-recorder)

`MedataCore/Sources/Pipeline/CaptureBundleRecorder.swift` — an actor that
writes one `PbMealFixture` per attempt reaching `Pipeline.estimate` (success
AND refusal; cancellation and pre-pipeline capture refusals write nothing)
into `Documents/captures/`, exposed via the Files app (Info.plist
`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`). Bundles replay
through `FixtureLoader` + `FixtureRunner` with no harness changes.

- **NOT gated by DEBUG or HARNESS_ENABLED** — field Release builds must
  record (decision log Decision 2). Pre-release checklist: remove the
  recorder wiring and the two Info.plist keys before any non-developer build.
- **~200 MB per bundle** — probs are recorded at camera resolution
  (1920×1440×C×FP16) because FixtureRunner sizes from intrinsics and the
  height-field silhouette test reads the background channel per pixel
  (Decision 1). Clear `Documents/captures/` nightly via Finder/Files.
- **Join key**: filename `<13-digit zero-padded timestampMs>-<outcome>.fixture`
  equals `EstimationAttemptRecord.timestampMs`. Same-ms collision appends
  `-2`, never overwrites. Writes are atomic (`.atomic` temp+rename).
- **Replay**: `--checkpoint-sha256` must equal the stamp — the loaded model's
  `modelVersion` (12-hex checkpoint prefix), or `segmenterSource`
  (`"dev_stub"`) on stub builds. `estimatorPath` is `single_dominant`.
  Zero ground truth loads fine; accuracy metrics are meaningless until
  weighed truth is back-filled.
- **Hand-off shape**: stage bodies stash `SegmentationResult`s on
  `PipelineDiagnostics.debugNadir/ObliqueSegmentation` (carrier only — never
  encoded into the record; Req 2.6 applies to the record, not bundles).
  `Pipeline.estimate` extracts the Sendable payload BEFORE the unstructured
  `Task` — the diagnostics object is non-Sendable and must not cross.
  The recorder is injected at `Pipeline.init` (no delegate-style stamping
  dance needed).
- **Gotcha**: `rgb8Bytes` throws on an image byte-count mismatch and the
  whole bundle is then skipped (logged to the `CaptureBundle` category).
  `RawFrame.fixture`'s 16-byte image triggers exactly this — tests must
  build dimensionally consistent frames.
- The simulator destination fails at codesigning `MedataCore_Pipeline.bundle`
  ("bundle format unrecognized") — pre-existing and unrelated; build for
  device (`generic/platform=iOS` compiles, `make build-app` needs the phone).
