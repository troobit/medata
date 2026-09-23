# Decision Log: Capture Bundle Recorder

## Decision 1: Record full-resolution probability tensors despite ~200 MB bundles

**Date**: 2026-07-18
**Status**: accepted

### Context

Device bundles must replay through the existing Mac harness with no harness changes. `FixtureRunner.run` sizes segmentation buffers from the camera intrinsics, and `HeightFieldEstimator.integrate` consumes the background-probability channel per pixel for its silhouette test — so the probability tensor is load-bearing for exact volume replay, and it must match camera resolution (1920×1440). At 35 classes × FP16 that is ~190 MB per view, dominating bundle size (~200 MB total, ~6 GB per 30-capture field day).

### Decision

Record the probability tensor byte-for-byte at camera resolution. Accept the bundle size for the developer phase; manage disk by clearing `Documents/captures/` nightly via Finder.

### Rationale

Exact replay with zero harness changes is the entire point of the recorder during a one-week MVP push. Every smaller alternative either breaks the replay contract or requires harness-side work that costs runway. The on-device pipeline already retains the same tensor in memory per attempt, so recording adds only a transient serialisation copy, bounded to one in-flight encode by the actor.

### Alternatives Considered

- **Argmax-only bundles (~3 MB)**: Drop the probs field - `FixtureRunner.makeSegResult` constructs a `ProbabilityTensor` whose size precondition would trap on empty bytes, and the silhouette test would be unreplayable. Requires harness changes; rejected.
- **Model-resolution probs (513², ~18 MB)**: Store the pre-resize tensor - dimensions would disagree with the intrinsics the replay path sizes from; the fixture would be internally inconsistent and replay would not reproduce the on-device numbers. Rejected.
- **Background-channel-only tensor or on-disk compression**: Both shrink bundles ~10-35× but need loader/runner changes. Deferred as future levers, noted in the smolspec's Out of Scope.

### Consequences

**Positive:**
- Bit-exact replay of the on-device attempt through every downstream stage, today.
- No harness, schema, or loader changes; existing guards and tooling apply unmodified.

**Negative:**
- ~200 MB per attempt; disk management is manual (Files app / Finder) for the MVP week.
- Large Finder transfers (~GBs per field day) when pulling bundles to the Mac.

---

## Decision 2: Always-on recording, including Release builds, with no in-app UI

**Date**: 2026-07-18
**Status**: accepted

### Context

Field captures run on Release-configuration builds with the real Core ML segmenter (`DEV_STUB_SEGMENTER` makes Debug builds segment with a stub). Developer tooling in this repo is often gated by `DEBUG`/`HARNESS_ENABLED`; gating the recorder that way would make field-day builds record nothing. Separately, a Settings toggle and clear button were considered for managing recording and disk.

### Decision

The recorder operates unconditionally in all build configurations and has no in-app UI. `Documents/captures/` is exposed via the Files app (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`), which provides browsing and deletion for free.

### Rationale

The user confirmed (2026-07-18) that Release-build recording is acceptable on the research branch because no release is imminent. Files-app deletion makes a bespoke management UI redundant; less code, nothing to forget to wire. This mirrors the snaq-parity precedent of keeping diagnostics surfaces outside `#if DEBUG` (Req 2.3).

### Alternatives Considered

- **Gate behind `DEBUG`/`HARNESS_ENABLED`**: Consistent with other dev tooling - but Debug builds use the stub segmenter, so the recorded bundles would be worthless and Release field builds would record nothing. Rejected.
- **Settings toggle + clear button**: User control over recording and disk - ~40 LOC of UI for a single-developer phase where the Files app already covers management. Rejected as avoidable scope.

### Consequences

**Positive:**
- Field-day builds record by definition; no configuration to get wrong.
- Zero UI code; deletion, inspection, and Mac transfer all via Files/Finder.

**Negative:**
- Raw meal imagery persists in Documents on every build. **Pre-release checklist item: gate or remove the recorder (and the Info.plist file-sharing keys) before any non-developer release.**
- No in-app off switch if disk pressure bites mid-day; mitigation is deleting bundles in the Files app.

---

## Decision 3: Record only attempts that reach the pipeline

**Date**: 2026-07-18
**Status**: accepted

### Context

Capture-stage refusals (session not started, capture failed, pre-pipeline `EstimationFailure`) write slim attempt records from `CaptureFlowModel`'s catch ladder before a `SegmentationResult` — and in some cases before a usable `RawFrame` — exists.

### Decision

Bundles are recorded only for attempts that enter `Pipeline.estimate`. Pre-pipeline refusals keep their slim attempt records but produce no bundle.

### Rationale

A capture-stage refusal has no estimation inputs worth replaying — the capture itself failed, and the attempt record's failure case already names why. Recording partial bundles would complicate the recorder's contract (imagery-less fixtures) for no debugging value.

### Alternatives Considered

- **Partial bundles for pre-pipeline failures**: proto3 optionals make them legal - but there is nothing to replay and the slim record already covers diagnosis. Rejected.
- **Hook recording in `CaptureFlowModel` instead of `Pipeline`**: one seam for all outcomes - but the segmentation outputs never leave the pipeline, so the model-side hook cannot assemble a replayable bundle. Rejected.

### Consequences

**Positive:**
- Single clean hook in `Pipeline.estimate` where `CaptureResult` and the stashed segmentation coexist on every exit path.
- Recorder contract stays simple: a bundle always replays.

**Negative:**
- No imagery for capture-stage failures (e.g. ARKit session errors); those are diagnosed from attempt records and device logs only.

---
