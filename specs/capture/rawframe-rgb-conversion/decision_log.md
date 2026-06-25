# Decision Log: RawFrame YCbCr→RGB Conversion

## Decision 1: Target Format Is BGRA8

**Date**: 2026-05-24
**Status**: accepted

### Context

`ARFrame.capturedImage` is biplanar YCbCr. `RawFrame.imageBytes` must carry it as an RGB-family chunky buffer so that the segmenter pre-processor and any future `Vision` / `CGImage` consumer can decode pixels. The `PixelFormat` enum already supports `.bgra8`, `.rgba8`, and `.rgb8`. We had to pick one.

### Decision

The conversion target is `.bgra8` (4 bytes per pixel, B/G/R/A interleaved).

### Rationale

BGRA8 is the native output format for `CIContext.render` and `VNImageRequestHandler`. Any future `VisionCardDetector` that reconstructs a `CGImage` from `RawFrame.imageBytes` would want BGRA-with-alpha anyway; choosing RGB8 now would force a re-expansion later. Existing `SegmenterPreProcessor.canonicaliseToRGB8` already handles the BGRA→RGB swap in one pass, so picking BGRA does not penalise the downstream consumer. The existing `MockCaptureEngine` default and the `.bgra8` test fixtures across `PreProcessingTests` and `CoreMLSegmenterTests` are also BGRA, so no test rework is forced.

### Alternatives Considered

- **`.rgb8`**: 25% smaller buffer; matches downstream `canonicaliseToRGB8` output directly with no per-pixel swap. Rejected because `Vision` / `CGImage` / `CIContext` all expect a 4-byte stride; a future `VisionCardDetector` would have to re-expand RGB8 to BGRA before handing it to `VNImageRequestHandler`, undoing the saving.
- **`.rgba8`**: Same size as BGRA8, also Vision-friendly. Rejected because Apple's image pipelines default to BGRA on iOS; choosing RGBA would force every consumer to pay an extra swap to talk to CoreImage.

### Consequences

**Positive:**

- Existing `.bgra8` test fixtures and `MockCaptureEngine` need no change.
- A future `VisionCardDetector` can hand `imageBytes` straight to `CGImage` reconstruction.
- Downstream `canonicaliseToRGB8` handles the BGRA→RGB swap on the segmenter's existing code path.

**Negative:**

- 33% larger buffer than `.rgb8` for the same frame (≈11 MB at 1920×1440 instead of 8 MB).
- The single explicit per-pixel `B/G/R` byte ordering must be documented in `RawFrame.pixelFormat` so future authors don't assume RGB.

---

## Decision 2: Conversion Runs at Shutter Time Only

**Date**: 2026-05-24
**Status**: accepted

### Context

`ARKitCaptureEngine` exposes both a `frames: AsyncStream<ARFrame>` (running at the ARSession update rate, ~60 fps) and a `captureFrame(target:)` shutter call (one frame per user tap). YCbCr→BGRA conversion is non-trivial work that could in principle be performed on either path.

### Decision

The conversion runs only inside `captureFrame(target:)`. The `frames` stream continues to yield raw `ARFrame` objects to subscribers (tilt indicator, preview overlays) without any pixel conversion.

### Rationale

Current `frames` consumers read `ARFrame.camera.transform`, `.intrinsics`, and gravity — none read pixel bytes. Doing the conversion on every frame would burn ~60× the CPU per second for no consumer that needs it. The shutter-only path runs the conversion exactly once per estimation (or twice for the two-view path), keeping the work well inside Req 16.1's 1000 ms / 1800 ms end-to-end budget.

### Alternatives Considered

- **Convert every frame in the `frames` stream**: Would let a future live-preview overlay consume RGB bytes at 60 fps. Rejected because no current consumer needs it; introducing the cost speculatively risks dropping AR-session frames (visible to the user as tracking jitter), and adding it later is a one-line change in `ARKitCaptureEngine.session(_:didUpdate:)`.
- **Convert lazily on first read of `imageBytes`**: Would defer cost until needed. Rejected because `RawFrame` is a `Sendable` value type with eager fields; introducing lazy storage would require either a class wrapper or `@unchecked Sendable` indirection, both of which break the existing portable-contract design.

### Consequences

**Positive:**

- Zero per-frame steady-state CPU overhead on the ARSession path.
- Conversion happens on the actor the shutter call is awaited from, naturally bounded to one in-flight invocation.

**Negative:**

- A future live-preview feature that wants per-frame RGB bytes will need to opt-in by lifting the conversion into the stream path. The decision-log entry serves as the trigger to revisit Decision 2.

---

## Decision 3: Extract a `PixelBufferAdapter` Boundary for Testability

**Date**: 2026-05-24
**Status**: accepted

### Context

`ARKitCaptureEngine` is the only place in the codebase that holds a `CVPixelBuffer`. The conversion logic could live inline in `buildRawFrame` or be extracted to its own type. Tests need to drive the conversion against a synthetic YCbCr buffer; the engine itself cannot be instantiated on the simulator without an ARSession.

### Decision

A new file `MedataCore/Sources/CaptureKit/PixelBufferAdapter.swift` exposes a public enum `PixelBufferAdapter` with a single `static func convert(_ buffer: CVPixelBuffer) throws -> (bytes: Data, format: PixelFormat, width: Int, height: Int)` entry point. `ARKitCaptureEngine.buildRawFrame` delegates to it.

### Rationale

The conversion is a pure function from `CVPixelBuffer` to bytes-plus-format. Pulling it out of the engine isolates the only non-portable thing about the conversion (CoreVideo / vImage calls) and lets the test target drive it with a hand-built YCbCr buffer using only public CoreVideo APIs. The boundary is one type, ~50 LOC, and removes the need for `@testable import` gymnastics. It also gives the future `VisionCardDetector` a place to ask for an RGB representation without depending on the AR engine.

### Alternatives Considered

- **Keep conversion inline in `ARKitCaptureEngine.buildRawFrame`**: Fewer moving parts. Rejected because tests would need `@testable import CaptureKit` and would couple to private helper signatures, and because the conversion is conceptually independent of AR-session lifecycle.
- **Put the conversion behind a protocol with mockable implementations**: Maximum decoupling. Rejected as over-engineering for one production caller and one test caller; the static-method boundary on a `caseless` enum is the minimum interface that gives the same testability.

### Consequences

**Positive:**

- Conversion is unit-testable on iOS Simulator without an ARSession.
- A future `VisionCardDetector` has a clean call site for getting RGB bytes from a `CVPixelBuffer`.
- The engine file shrinks slightly and the conversion code lives next to the type it is most tightly coupled to (`CVPixelBuffer`).

**Negative:**

- Adds one new file (~50 LOC of production code) to `CaptureKit`.
- One more module-level public symbol to keep stable.

---

## Decision 4: No Hard Per-Frame Conversion Wall-Clock Target

**Date**: 2026-05-24
**Status**: accepted (decision stands; cited figures stale). The rationale below references the earlier research Req 16.1 "1000 ms / 1800 ms P95" budgets, the Req 16.2 per-stage budgets, the Req 16.7 perf harness, and the iPhone 12 Pro floor — all superseded by research §0 / Decision 40 (single soft 30 s end-to-end target, per-stage P95 removed, no Req 16.7) and the iPhone 13 Pro Max floor (Req 1.2). The decision itself — no per-call wall-clock gate; discipline the implementation; observe regressions at the end-to-end level — is unchanged.

### Context

Research Req 16.1 caps end-to-end single-view-LiDAR latency at 1000 ms P95 on the v1 hardware floor. Req 16.2 lists per-stage budgets totalling 590 ms, leaving 410 ms of unbudgeted slack. YCbCr→BGRA conversion runs at capture time, before the timed pipeline begins, and adds to the shutter-tap-to-result wall clock visible to the user. The research-spec hardware floor references iPhone 12 Pro, but the actual supported fleet is several generations newer and substantially faster — anchoring a CI threshold on the obsolete reference would either ratchet too tight (failing on Simulator) or too loose (missing real regressions on modern silicon).

### Decision

The spec does NOT impose a per-call wall-clock threshold on the conversion. Instead it requires (a) shutter-only execution, (b) bounded transient memory, (c) a hardware-accelerated path with cached helpers, and (d) coverage at the end-to-end level (originally the Req 16.7 perf harness; now research Req 16.1's soft 30 s end-to-end check after §0 / Decision 40 removed the per-stage harness). Regressions are detected at the end-to-end-budget level, not as a per-call assertion.

### Rationale

The conversion is one stage among many; if it bloats, the symptom shows up as Req 16.1 P95 drift, which the existing harness already watches. A per-call millisecond gate on the Simulator would either be too loose to catch real regressions (Simulator wall clock has little to do with device wall clock) or too tight and flaky (Simulator scheduling noise). Disciplining the *implementation* (no Swift per-pixel loops, no per-call `CIContext`) is a better signal than disciplining the wall clock at this layer. The actual hardware floor in production is well above iPhone 12 Pro, so even an unoptimised vImage path has enough headroom.

### Alternatives Considered

- **Hard 30 ms P95 device + 60 ms CI gate**: Concrete failure threshold, but anchored on a hardware reference that no longer matches the fleet, and the Simulator multiplier is a guess. Rejected because the threshold would either generate false positives on noisy CI or fail to catch slow paths on a fast Simulator host.
- **15 ms target**: Even more aggressive, would force Metal / cached `CIContext` straight away. Rejected for the same reasons as above plus implementation cost.
- **Document a qualitative cap and leave perf to the harness without any guidance**: Risks a Swift-loop implementation creeping in. Rejected in favour of the implementation-discipline constraints in Req 4.3.

### Consequences

**Positive:**

- Spec does not bind us to a number that depends on a stale hardware-floor reference.
- Implementation team is free to pick vImage, CoreImage, or Metal based on engineering judgement, provided the discipline rules in Req 4.3 are met.
- Regressions are still caught — at the level where they actually matter (Req 16.1 end-to-end P95).

**Negative:**

- No fast-fail signal at the unit-test layer for a per-call slowdown; the perf harness is the earliest gate.
- Implementation-discipline rules (Req 4.3) are subjective at the edges; reviewers must judge whether a chosen path counts as "hardware-accelerated".

---

## Decision 5: Conversion Backend Is vImage

**Date**: 2026-05-24
**Status**: accepted

### Context

Three viable hardware-accelerated paths exist for biplanar YCbCr → BGRA on iOS: vImage (Accelerate / CPU SIMD), CoreImage (`CIContext.render` on GPU), and a custom Metal compute shader. Req 4.3 forces *some* hardware-accelerated path with cached helpers. D4 frees us from a hard wall-clock target.

### Decision

Use vImage. Specifically: `vImageConvert_YpCbCrToARGB_GenerateConversion` once to build a cached `vImage_YpCbCrToARGB` info struct, then `vImageConvert_420Yp8_CbCr8ToARGB8888` per call with a `permuteMap` of `[3, 2, 1, 0]` to land bytes in BGRA order. Matrix: `kvImage_YpCbCrToARGBMatrix_ITU_R_601_4`. Pixel range: full-range (Yp 0..255, CbCr 0..255, zero offset 128) to match `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`.

### Rationale

vImage is the only option whose setup cost is genuinely one-time (the info struct is a plain C value type), whose per-call cost is allocation-free apart from the destination buffer, and which works identically on iOS device, iOS Simulator, and macOS without a Metal device. That cross-platform property is what lets the adapter live outside the `#if canImport(ARKit) && os(iOS)` guard (Req 3.2 — Simulator testability).

### Alternatives Considered

- **CoreImage (`CIContext` + `CIImage(cvPixelBuffer:)` + `render(toCVPixelBuffer:)`)**: GPU-accelerated. Rejected because `CIContext` construction is expensive (tens of ms first-call) and ties to a Metal device, complicating the Simulator and macOS paths. Per-call `CIImage` instantiation is also non-zero overhead. No measurable win at one conversion per shutter tap.
- **Metal compute shader**: Lowest steady-state cost in principle. Rejected because the shader, pipeline state, command queue, and buffer-pool plumbing dwarf the conversion code, and the gain over vImage is irrelevant at the required call rate (per D2, once per shutter tap).

### Consequences

**Positive:**

- Cross-platform: the same path works on iOS device, Simulator, and the macOS HarnessCLI.
- Cached info struct + allocation-free per-call meets the Req 4.3 discipline rules without further work.
- Deterministic (CPU SIMD) — no GPU driver variance, so the hand-computed reference patch test (Req 1.2) is byte-stable.

**Negative:**

- CPU rather than GPU; on hypothetical future per-frame conversion (if D2 is reversed) the cost would be higher than a Metal path. Acceptable because the D2 trigger remains "only when a consumer needs it".

---

## Decision 6: Pixel-Format Errors Are a Nested `ConversionError`, Not a `CaptureError` Case

**Date**: 2026-05-24
**Status**: accepted

### Context

Req 1.5 and 2.4 require the conversion path to throw on unrecognised four-CC. The error could be a new case on the existing `CaptureError` enum (`MedataCore/Sources/CaptureKit/CaptureSession.swift:12`) or a new type nested on `PixelBufferAdapter`.

### Decision

Define `PixelBufferAdapter.ConversionError` with cases `unsupportedSourceFormat(fourCC: String)` and `conversionFailed(vImageErrorCode: Int)`. `ARKitCaptureEngine.buildRawFrame` lets the error propagate as-is via its existing untyped `throws` clause.

### Rationale

`CaptureError` describes capture-session lifecycle problems (LiDAR unavailable, session not started, release timeout). Pixel-format issues are a property of an individual buffer and have no session-lifecycle meaning. A nested type also lets the adapter be used outside the capture-session context (e.g. a future macOS HarnessCLI tool that converts file-loaded `CVPixelBuffer`s) without dragging in capture-session vocabulary. UI / pipeline code that pattern-matches on `CaptureError` is unaffected because `ConversionError` is a distinct type.

### Alternatives Considered

- **Add `CaptureError.unsupportedPixelFormat(fourCC: String)`**: Keeps the error vocabulary in one place for capture callers. Rejected because it ties `PixelBufferAdapter` to a session-level error type that does not describe what went wrong, and would force any non-AR caller of the adapter to import or re-translate that error.
- **Reuse `CaptureError.captureFailed(String)` with a stringly-typed reason**: Minimal change. Rejected because losing the typed `fourCC` payload makes test assertions stringly-typed and makes the cause harder to consume programmatically.

### Consequences

**Positive:**

- `PixelBufferAdapter` carries no capture-session-specific types in its public API.
- Tests can assert on the typed `unsupportedSourceFormat(fourCC: "2vuy")` payload rather than parse strings.

**Negative:**

- Two error types now reach `captureFrame` callers (`CaptureError` and `PixelBufferAdapter.ConversionError`); any future code that wants a unified `catch` must match on `Error` or both types explicitly.

---

## Decision 7: Add `EstimationFailure.internalError(String)` for the untyped-error catch-all instead of mismapping to `.noScaleAvailable`

**Date**: 2026-06-04
**Status**: accepted

### Context

The 2026-06-04 device-log run on iPhone 13 Pro Max iOS 26.5 (post the OOM bugfix) surfaced `event=estimate.end success=false error=SegmentationError` and the user saw a "Meal scale unknown" modal — the UI string owned by `EstimationFailure.noScaleAvailable` (`App/RefusalSheet.swift:44`). The cause is the catch-all at `App/CaptureFlowModel.swift:502-506`, which routes every non-`EstimationFailure` error onto `.refused(.noScaleAvailable, retryStage: retryStage)`. The 2026-06-04 incident is the latest example; the same mismapping has shipped silently for every non-scale, non-typed pipeline failure since `CaptureFlowModel.runEstimation` was written.

Without a fix, the new `PixelBufferAdapter.ConversionError` cases introduced by this spec would themselves surface as "Meal scale unknown" on any future unsupported-format frame, repeating the same misdirection. The catch-all has to change in lock-step with the conversion landing.

### Decision

Add a new case to `MedataCore/Sources/Pipeline/EstimationFailure.swift`:

```swift
case internalError(String)
```

The `String` payload is the underlying error's Swift type name (`String(describing: type(of: error))`), to satisfy [Req 6.2](requirements.md#6.2). Rewrite the catch-all in `App/CaptureFlowModel.swift:502-506` to:

```swift
} catch {
    let typeName = String(describing: type(of: error))
    log.info("event=estimate.end success=false error=\(typeName, privacy: .public)")
    guard case .estimating = state else { return }
    state = .refused(.internalError(typeName), retryStage: retryStage)
}
```

Add `internalError` mappings to `App/RefusalSheet.swift`:

- Symbol: `"exclamationmark.triangle"` (existing SF Symbol; no asset addition).
- Title: `"Couldn't process the photo"`.
- Subtitle (DEBUG only, gated on `#if DEBUG` per the existing instrumentation pattern in `Pipeline.swift`): `"Internal error: \(typeName)"` so the developer log line and the on-screen message read alike at debug time.

`EstimationFailure` is an `Error` enum with associated values on other cases (`.lidarCoverageTooLow(Set<String>)`); the new `.internalError(String)` matches the existing payload style.

### Rationale

A new dedicated case is the smallest change that (a) stops the misdirection without touching unrelated cases, (b) preserves a usable retry path (`retryStage` still flows through), (c) keeps the catch-all single-line at the call site, and (d) keeps the error vocabulary truthful: untyped errors are not scale errors and should not borrow that label. The `String` payload carries the source-of-truth identifier for the underlying error type without committing the API to importing every downstream error namespace.

`"Couldn't process the photo"` is deliberately user-facing (not "Internal error" or "Pipeline failure"): the user does not know what a pipeline is, but knows what their photo is. The DEBUG subtitle gives the developer the error type at a glance without polluting the Release-build UI.

### Alternatives Considered

- **Reuse `.noScaleAvailable`, change its label to "Couldn't process the photo"**: One fewer case, but conflates two genuinely different user-recoverable problems (no metric scale → place a reference card vs. internal failure → try again / file a bug). Rejected.
- **Surface the raw error type name in the modal title**: e.g. "SegmentationError". Maximally honest, but exposes implementation vocabulary to end users for no benefit. Rejected; the type name goes into the DEBUG subtitle instead.
- **Add multiple new cases (`.segmenterError`, `.persistenceError`, `.conversionError`, …)**: Granular and honest per-domain. Rejected for this bugfix's scope — most downstream domains do not yet have UI affordances different from a generic "try again" path. The single `.internalError(String)` is the smallest change that resolves Req 6 without committing to a longer per-domain UI design. Future specs can split off cases as user-facing affordances diverge.
- **Crash on unknown errors (`fatalError`)**: Would force every error to be typed-through. Rejected because production users would see crashes for previously-soft failures (a regression in user experience), and because the typed-through model is exactly what the granular-cases alternative above proposes.

### Consequences

**Positive:**

- "Meal scale unknown" stops firing for non-scale failures, including for the new `PixelBufferAdapter.ConversionError` this spec introduces.
- The DEBUG subtitle correlates the on-screen message with the device log's `event=estimate.end success=false error=<Type>` line at a glance.
- Single new case keeps the `EstimationFailure` API surface small; the case can be expanded into more specific cases later without breaking call sites (additive switch).
- `retryStage` flows through, so the user still has a productive next action (re-shoot the same stage) for any internal failure that may be transient.

**Negative:**

- The catch-all is still a catch-all: a true internal bug is grouped with a transient device-side hiccup behind the same user-facing modal. Mitigation: the DEBUG subtitle distinguishes the cases for developers; a future spec can promote frequently-observed type names into their own `EstimationFailure` cases as the data justifies.
- `RefusalSheet`'s switch on `EstimationFailure` is no longer exhaustive without the new case — any caller pattern-matching on it elsewhere must add a branch. The compiler enforces this for switches over an enum without `@unknown default`, so the impact is visible at build time.

### Impact

`MedataCore/Sources/Pipeline/EstimationFailure.swift`, `App/CaptureFlowModel.swift`, `App/RefusalSheet.swift`. New unit test in the App test target (or `App/Tests/CaptureFlowModelTests.swift` if it exists; otherwise a new file) covering [Req 6.5](requirements.md#6.5).

---
