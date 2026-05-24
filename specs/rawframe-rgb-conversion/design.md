# Design: RawFrame YCbCr→RGB Conversion

## Overview

Introduce a `PixelBufferAdapter.convert` entry point that takes any supported `CVPixelBuffer` (YCbCr biplanar, BGRA, RGBA) and returns a contiguous BGRA8 `Data` plus its declared `PixelFormat`. `ARKitCaptureEngine.buildRawFrame` delegates to it in place of the broken `copyPixelBufferBytes` / `detectPixelFormat` helpers.

## Architecture

### Integration point

`ARKitCaptureEngine.buildRawFrame` (`MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:233-264`) replaces the two private helpers with a single call:

```swift
let (bytes, format, _, _) = try PixelBufferAdapter.convert(pixelBuffer)
return RawFrame(imageBytes: bytes, pixelFormat: format, …)
```

The private `copyPixelBufferBytes` and `detectPixelFormat` are deleted. `buildRawFrame` already throws (via `try`) so the new error is propagated upward without changing the method signature; `ARKitCaptureEngine.captureFrame` rethrows.

### File placement

New file: `MedataCore/Sources/CaptureKit/PixelBufferAdapter.swift`. CaptureKit has no platform guard at the SPM level — only `ARKitCaptureEngine.swift` is wrapped in `#if canImport(ARKit) && os(iOS)`. `PixelBufferAdapter` depends on CoreVideo + Accelerate, both available on iOS, iOS Simulator, and macOS, so it is **not** guarded — that is what makes it independently testable on Simulator (Req 3.2) and reachable from the macOS HarnessCLI later.

### Conversion backend: vImage

vImage's biplanar YpCbCr-to-ARGB8888 path is the chosen backend:

- `vImageConvert_YpCbCrToARGB_GenerateConversion(...)` builds a `vImage_YpCbCrToARGB` info struct once. Inputs: `kvImage_YpCbCrToARGBMatrix_ITU_R_601_4` for BT.601 coefficients, and a `vImage_YpCbCrPixelRange` configured for **full range** (Yp ∈ 0..255, Cb/Cr ∈ 0..255, zero offset 128) to match `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`.
- `vImageConvert_420Yp8_CbCr8ToARGB8888(...)` runs per-frame against the cached info struct. The `permuteMap: [UInt8] = [3, 2, 1, 0]` reorders ARGB→BGRA in the destination buffer, so no separate swizzle pass is needed.

The cached info struct is the "expensive helper" referenced by Req 4.3; it is built once at the first call and stored as a `static let` inside `PixelBufferAdapter`.

### Why not CoreImage or Metal

| Option | Setup cost | Per-call cost | Simulator-testable | Decision |
|---|---|---|---|---|
| vImage biplanar | one-time conversion-info struct | SIMD CPU, no allocations beyond destination | yes | **chosen** |
| `CIContext.render` | `CIContext` is expensive (≥ tens of ms first call) and ties to a Metal device on hardware | GPU, but per-call `CIImage(cvPixelBuffer:)` allocation | partial — `CIContext(options:)` differs on Simulator | rejected — heavier setup, no win at the required scale |
| Metal compute shader | shader compile + pipeline state | lowest steady-state | yes with `MTLCreateSystemDefaultDevice()` | rejected — most code; gain not justified per D4 |

## Components and Interfaces

```swift
public enum PixelBufferAdapter {
    public enum ConversionError: Error, Equatable {
        case unsupportedSourceFormat(fourCC: String)   // e.g. "v210"
        case conversionFailed(vImageErrorCode: Int)
    }

    public struct Output {
        public let bytes: Data            // contiguous, count == width * height * 4
        public let format: PixelFormat    // always .bgra8 for the YCbCr path; passthrough for BGRA/RGBA
        public let width: Int
        public let height: Int
    }

    public static func convert(_ buffer: CVPixelBuffer) throws -> Output
}
```

**Non-obvious contracts:**

- `Output.bytes` is contiguous: row stride equals `width * 4`, no per-row padding. The vImage destination buffer is allocated by the adapter at this exact stride.
- `Output.format` describes the **output bytes**, not the source `CVPixelBuffer`'s `CVPixelBufferGetPixelFormatType`. For any YCbCr input the format is `.bgra8`. For a BGRA source the bytes are still copied into a contiguous, owned buffer (the source `CVPixelBuffer` is locked only for the duration of the call) — the format tag matches.
- `convert` is thread-safe. The cached `vImage_YpCbCrToARGB` info struct is read-only after initialisation; the per-call destination buffer is local to the call.
- The source `CVPixelBuffer` is locked with `.readOnly` for the duration of the conversion and unlocked via `defer` even on the error paths.

### `ARKitCaptureEngine` changes

| Symbol | Action |
|---|---|
| `private func copyPixelBufferBytes(_ buffer: CVPixelBuffer) -> Data` | **delete** |
| `private func detectPixelFormat(_ buffer: CVPixelBuffer) -> PixelFormat` | **delete** |
| `private func buildRawFrame(arFrame: ARFrame) throws -> RawFrame` | replace the two helper calls with one `PixelBufferAdapter.convert` call |

`buildRawFrame` already had `try` in its signature for the depth path; it now also throws `PixelBufferAdapter.ConversionError`. No new code in `captureFrame(target:)` — the existing `try await` propagates.

### `CaptureError` left unchanged

The new error is `PixelBufferAdapter.ConversionError`, not a new case on `CaptureError`. Rationale: `CaptureError` is the vocabulary for the capture-session lifecycle (lidar unavailable, session not started, release timeout); pixel-format issues are a property of the buffer, not the session. `ARKitCaptureEngine.captureFrame` lets the `ConversionError` propagate up as-is — the throws clause is `throws` (untyped), so callers continue to receive `Error`. UI / pipeline layers that pattern-match on `CaptureError` are unaffected because `ConversionError` is a distinct type.

## Pattern Extension Audit

`copyPixelBufferBytes` and `detectPixelFormat` are private to `ARKitCaptureEngine`. Grep confirms no other call sites. There is no pattern to extend; the audit reduces to the consumer list of `RawFrame.imageBytes` / `pixelFormat`, already enumerated in the scope assessment:

| Consumer | Touch required |
|---|---|
| `SegmenterPreProcessor.process` (`Sources/Segmentation/PreProcessing.swift:53`) | none — already accepts `.bgra8` via `canonicaliseToRGB8` |
| `Bridges.swift:96-97` (PbRawFrame round-trip) | none — bytes + format tag round-trip unchanged |
| `MockCaptureEngine` (`Sources/CaptureKit/MockCaptureEngine.swift:48-57`) | none — already emits `.bgra8` placeholder |
| `RawFrameTests.swift:78` | none — uses `.bgra8` already |
| `PreProcessingTests.swift`, `CoreMLSegmenterTests.swift`, `RoundTripTests.swift` | none — already use `.bgra8` or synthetic `.rgb8` fixtures unrelated to the AR pipeline |
| `ARKitCaptureEngine.buildRawFrame` | **delegate to PixelBufferAdapter** |

## Data Models

No new public data models beyond `PixelBufferAdapter.Output` (a transport tuple, not a domain type). `RawFrame`, `PixelFormat`, and the `RawFrame.proto` wire format are untouched.

## Error Handling

| Condition | Error |
|---|---|
| Source pixel format is not in {YCbCr 420 biplanar full-range, BGRA8, RGBA8} | `ConversionError.unsupportedSourceFormat(fourCC: String)` |
| vImage call returns non-`kvImageNoError` | `ConversionError.conversionFailed(vImageErrorCode: Int)` |
| `CVPixelBufferLockBaseAddress` returns a non-success status | `ConversionError.conversionFailed(vImageErrorCode: Int(status))` |

The four-CC string for `unsupportedSourceFormat` is rendered from the `OSType` (UInt32) as four ASCII characters, matching how Core Video pixel formats are pronounced ("BGRA", "v210", "420v"), so the error message is human-debuggable.

## Testing Strategy

### Unit tests — `MedataCore/Tests/CaptureKitTests/PixelBufferAdapterTests.swift` (new)

Each test builds a `CVPixelBuffer` via `CVPixelBufferCreate` and populates planes manually using `CVPixelBufferLockBaseAddress(.readWrite)` + plane indices 0 (Y) and 1 (CbCr interleaved).

| Test | What it covers |
|---|---|
| `testFlatGrayYCbCrProducesGrayBGRA` | Constant Y=128, Cb=Cr=128 → every output BGRA pixel ≈ (128,128,128,255) within ±2. Covers [1.1](../rawframe-rgb-conversion/requirements.md#1.1), [1.2](#1.2), [1.4](#1.4). |
| `testKnownColourPatchMatchesBT601` | 2×2 patch with Y/Cb/Cr values for red, green, blue, white per BT.601 full-range formulas; output within ±2. Covers [1.2](#1.2). |
| `testOutputIsContiguousNoStridePadding` | Build a 6×4 buffer (width × 4 = 24 bytes/row, not stride-aligned), assert `bytes.count == 6*4*4` and that decoded row N starts at offset `N*24`. Covers [1.3](#1.3). |
| `testBGRASourcePassesThrough` | Source is `kCVPixelFormatType_32BGRA` with known bytes; output bytes == input bytes; `format == .bgra8`. Covers [2.1](#2.1), [5.2](#5.2). |
| `testRGBASourceReportsRGBA` | Source is `kCVPixelFormatType_32RGBA`; `format == .rgba8`; bytes round-tripped. Covers [2.2](#2.2). |
| `testYCbCrSourceReportsBGRAOnOutput` | Source is biplanar YCbCr full-range; `format == .bgra8` (describes output). Covers [2.3](#2.3). |
| `testUnsupportedFourCCThrows` | Source is `kCVPixelFormatType_422YpCbCr8` (a format the adapter does not handle); `ConversionError.unsupportedSourceFormat(fourCC: "2vuy")` is thrown. Covers [1.5](#1.5), [2.4](#2.4). |
| `testNonSquareDimensions` | 640×480 YCbCr buffer with row-major colour ramp; verify each row's first pixel matches the formula. Covers [1.1](#1.1), [1.3](#1.3). |
| `testRandomisedRoundTripWithinTolerance` (PBT-style) | Use the deterministic seeded RNG pattern from `CardPosePropertyTests` to generate 200 random (Y, Cb, Cr) triples, build a 1×1 buffer per triple, assert each output channel is within ±2 of the BT.601 reference. Covers the universal-guarantee aspect of [1.2](#1.2). |

PBT framework: deterministic seeded RNG matching `MedataCore/Tests/CardDetectionTests/CardPosePropertyTests.swift` (project convention — no SwiftCheck dependency). The test does not need shrinking because the formula is closed-form; a counter-example is the (Y,Cb,Cr) triple itself.

### Cross-target integration — `MedataCore/Tests/SegmentationTests/PreProcessorAcceptsAdapterOutputTests.swift` (new)

Builds a synthetic YCbCr `CVPixelBuffer`, runs it through `PixelBufferAdapter.convert`, hands the resulting `(bytes, format, width, height)` directly to `SegmenterPreProcessor.process(...)` and asserts no `SegmentationError.invalidInputDimensions` is raised. Covers [5.1](#5.1). The test depends on both targets via the existing `dependencies: ["Segmentation", "CaptureKit", "PortableContracts"]` in `Package.swift:134`.

### Existing tests — sanity checks

- `RawFrameTests` continues to pass unmodified (no contract change to `RawFrame` itself).
- `ARKitCaptureEngineStreamsTests` continues to pass — the `frames` AsyncStream is unchanged (D2: no per-frame conversion).
- `CaptureSessionTests` continues to pass — `CaptureSession` is unchanged.
- `RoundTripTests` continues to pass — `Bridges` round-trip is unchanged.

### Performance harness coverage

Req 4.4 routes performance regressions to the existing Req 16.7 perf harness. No per-call wall-clock assertion is added to the unit suite (per D4). The harness already runs the capture stage end-to-end; once the real Pipeline lands (Blocker 1), conversion cost shows up under shutter-to-result latency.

## Risks

- **vImage matrix selection silently wrong.** If the matrix is set to `ITU_R_601_4` but the range struct is misconfigured (e.g. video-range offsets while the source is full-range), greys look right but saturated colours skew. Mitigated by the `testKnownColourPatchMatchesBT601` patch test, which uses saturated red/green/blue — any mis-set range fails the ±2 tolerance immediately.
- **`vImage_YpCbCrToARGB` info struct lifetime.** Storing it as a `static let` requires Sendable safety. The struct is a C value type with no reference fields; wrapping the init in a `nonisolated(unsafe) static let` is the standard pattern. Alternative: lazy via a dispatch-once helper — same effect, more code.
- **Source `CVPixelBuffer` may not be readable while locked elsewhere.** ARKit guarantees `ARFrame.capturedImage` is valid for the lifetime of the `ARFrame`; `buildRawFrame` is called synchronously on the same actor that received the frame, so contention is impossible in practice. The adapter still uses `lock/defer unlock` for safety.
