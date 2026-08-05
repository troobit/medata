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

## Replaying a device bundle through HarnessCLI (first done 2026-08-05)

The recipe, and the traps it hit. `capture-bundle-recorder` task 4's close-out.

```bash
xcrun devicectl device info files --device <udid> \
  --domain-type appDataContainer --domain-identifier rtob.MeData \
  --subdirectory Documents/captures
xcrun devicectl device copy from --device <udid> \
  --domain-type appDataContainer --domain-identifier rtob.MeData \
  --source Documents/captures/<stem>.fixture --destination <stem>.fixture
make harness-accuracy FIXTURES=<dir> SHA=<stamp> OUT=<report.json>
```

**The `SHA` is the bare 12-hex, not the app's lineage string.** A bundle stamps
`segmenter_checkpoint_sha256 = "ab812dc3aa9d"` while `EstimationOutcome.modelVersion` reads
`"coreml_ab812dc3aa9d"`. Passing the app-facing form fails the load — usefully, since
`FixtureLoader.Error.checkpointMismatch` prints `got:`, so the first failed run tells you the
right value. Worth knowing that the same model carries two different identifiers across the
two records; anything keying an error log on "segmenter sha" must pick one and normalise.

**Two defects this exposed, both now fixed:**

1. `HarnessCLI` hard-coded `ClassPalette.v1Standard`, so `C = 35` against a 36-channel palette-v2
   bundle. `FixtureRunner` derives the probability tensor's shape as `H*W*C*2` with `H`/`W` from
   the nadir intrinsics — those were right (1920×1440, matching the argmax byte-for-byte) — so
   only `C` was wrong, and `ProbabilityTensor`'s `precondition` **trapped the process**. No
   report, and every other bundle in the directory lost with it. The palette is now resolved per
   fixture from its own `paletteVersion` (`ClassPalette.standard(for:)`, which already existed for
   the app's v1/v2 display split). `seg-bench` carried the same bug behind a size guard, so it
   silently dropped every v2 bundle rather than trapping — quieter, equally wrong.
2. `FixtureRunner.run` now throws `probsSizeMismatch` rather than leaving that precondition to
   fire. A batch tool over operator-supplied files must skip a bad bundle with a message.

**Replay is not bit-exact — measured, not assumed.** Same attempt (`1785135663727`), device vs
replay:

| | Device (recorded `measurements`) | Replay |
|---|---|---|
| class | bread_wholemeal | bread_wholemeal |
| carbs | **103.71 g** | **98.92 g** |
| β | 1.0 | 1.0 (pinned) |

**−4.79 g, −4.6 %**, with no error raised. β is not the cause — the device recorded β = 1 for this
attempt too. The prime suspect is the support plane: the bundle stamps
`estimator_path = 'single_dominant'`, which routes `FixtureRunner` to `fitPlateRegionPlane` (the
centre-seeded flood fill written for the N5k overhead rig), whereas replay's other branch,
`fitPlaneFromDepth`, masks the whole frame. The device's own fit recorded
`planeResidualMm 1.94, candidates 1,065,089, inliers 639,569` for comparison. Note this
**refutes** the standing roadmap §5 prediction that handheld captures would *skip* or throw
`volumeEstimationFailed` on this branch: the flood fill succeeded. A silent few-percent drift is
the actual failure mode, and it is harder to notice than a crash.

**Untruthed bundles report UNSCORED and exit 1 — that is correct.** The recorder leaves
`ground_truth_*` at proto3 defaults by design (truth is back-filled off-device), so a field
bundle scores nothing: `scoredCount: 0`, `passesBar: false`, per-row `scored: false` with the
error fields absent rather than zero, plus a stderr warning. Do not read the non-zero exit as a
defect in the capture. `predictedCarbsG` is still on the row, which is the main reason to replay
an untruthed bundle at all.

## Why the support-plane defect survived every diagnostic (2026-08-05)

The plane fitted to the table for months while `planeResidualMm`, `planeInlierCount` and
`foodRegionCoveragePercent` all read healthy. Three independent reasons, each verified in
source during the `support-plane-reference` design. **Do not trust these three signals to
tell you a plane fit is correct.**

### 1. The residual cannot discriminate — it is bounded by the inlier band

`LiDARPlaneFitter.fitOutcome` computes `computeResidual(points: polishedInliers…)`, and
inliers are re-selected within `inlierBandMm = 5` of the refined plane. **RMS over points
each within ±5 mm is ≤ 5 mm by construction.** The residual therefore measures how tightly
the winning inliers hug their own plane, never whether that plane is the right surface.

This is why the diagnosis found the *wrong* (table) plane at **1.95 mm** and the *correct*
(plate) plane at **2.27 mm** — the wrong plane scored better. Any guard keyed on residual
inherits the same blindness; a straddling region does not present as high residual, because
straddling points are never inliers.

### 2. Inlier and candidate counts are inflated ~56×

`collectCandidatePoints` enumerates on the **colour** grid (1920×1440) and samples depth
bilinearly from the **256×192** map. Each real depth measurement is therefore counted about
56 times, and neighbouring colour pixels are not independent observations.

"1,286,181 inliers" is roughly 23,000 independent measurements. That inflation is what made
the wrong fit look statistically overwhelming, and it means any threshold on candidate or
inlier count is calibrated against replicas rather than data. Counts recorded before the
`support-plane-reference` work are colour-grid counts; counts on a `.foodSupport` row after
it are native depth samples. **They differ by ~56× and must never be compared across
references** — `planeReference` is what disambiguates them.

### 3. RANSAC selects on area, and the table is the largest flat thing in frame

`ransac` scores `bestScore = inliers.count`. Nothing in the selection knows where the food
is. In the diagnosed capture the worktop took 510,499 votes against roughly 64,000 for the
plate. The algorithm worked exactly as designed and returned the biggest gravity-aligned
plane; that is simply not the surface the food rests on.

### Latent trap: `depthIntrinsics` is all zeros on device

`ARKitCaptureEngine` constructs `CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, …)` for the
depth map — only `imageWidth`/`imageHeight` are real. It has **no production readers today**,
so nothing has failed yet. Any code back-projecting native depth samples must derive them
from the colour intrinsics:

```
fx_d = fx_c · W_d/W_c        cx_d = (cx_c + 0.5) · W_d/W_c − 0.5
```

Reaching for `depth.depthIntrinsics` yields a divide-by-zero and a NaN plane; passing
`colourIntrinsics` straight through yields a 7.5× lateral error that tilts the plane. The
half-pixel terms are not optional — dropping them shifts the principal point by ~3.75 colour
pixels.
