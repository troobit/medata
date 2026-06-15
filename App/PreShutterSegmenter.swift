import CaptureKit
import Foundation
import Pipeline
#if canImport(ARKit) && os(iOS)
import ARKit
#endif
#if DEBUG
import os
#endif

// Pre-shutter food-region producer per spec `pipeline-real-device-correctness`
// design PreShutterSegmenter section. Subscribes to the ARFrame stream from
// `ARKitCaptureEngine.frames`, runs the segmenter on each completed inference
// cycle, and publishes the latest `BinaryMask` via `latest` for the shutter-
// tap consumer in `CaptureFlowModel`.
//
// Concurrency contract (Decisions 5, 12, 13; smolspec H4 fix):
//   - `@MainActor`-isolated for publication atomicity; the heavy work inside
//     the inflight `Task` is dispatched off MainActor via the segmenter's
//     non-isolated `segment(_:)` and a nonisolated frame-conversion helper.
//   - Latest-wins on both sides: the AsyncStream is configured for
//     `bufferingNewest(1)` by its producer, and the inference loop runs one
//     `segment(_:)` call at a time — frames arriving while a call is in flight
//     are coalesced by the buffer to the most recent one.
//   - `pause()` flips an `isPaused` flag — it does NOT cancel the inflight
//     Task. Cancelling mid-segment dropped publishes silently and left
//     `latest` nil for entire `.ready` windows (smolspec H4). The Task lives
//     forever once started; the for-await body checks `isPaused` at the top
//     of each iteration and drops the frame without publishing while paused.
//   - `awaitPaused()` additionally awaits the in-flight inference to drain
//     so `CaptureFlowModel.performFlow` can read `latest` atomically at the
//     nadir-capture instant (Decision 13). The drain continuation is resumed
//     inside `finishSegmentCycle` AFTER the publish completes.
//   - `resume(frames:)` caches the AsyncStream on the first call. Subsequent
//     resumes reuse the cached stream rather than calling `engine.frames` for
//     a fresh per-subscriber continuation (smolspec H4 — subscription leak).
//
// Memory: the published `latest.box` is a reference wrapper (`MaskBox`) so a
// 1920x1440 mask buffer (~2.7 MB at 1 bit per pixel stored as `[UInt8]`) is
// not copied on every `set`/`get` at 2 Hz.
// Read-side seam consumed by `CaptureFlowModel`. The production conformance is
// `PreShutterSegmenter`; tests inject a spy that pre-populates `latest` and
// records pause/awaitPaused call order to verify the freeze-at-nadir invariant
// (Decision 11) and the snapshot atomicity contract (Decision 13).
@MainActor
protocol PreShutterMaskSource: AnyObject {
    var latest: PreShutterSegmenter.TimestampedMask? { get }
    func pause()
    func awaitPaused() async
}

@MainActor
final class PreShutterSegmenter: PreShutterMaskSource {
    final class MaskBox: @unchecked Sendable {
        let mask: BinaryMask
        init(_ mask: BinaryMask) { self.mask = mask }
    }

    struct TimestampedMask: @unchecked Sendable {
        let box: MaskBox
        let producedAt: ContinuousClock.Instant
        let source: Source
    }

    enum Source: String, Sendable {
        case preShutterStub = "pre_shutter_stub"
        case preShutterCoreML = "pre_shutter_coreml"
    }

    /// Most recently published mask. Reset is never automatic — the value
    /// survives `pause()` so a shutter-tap immediately following a pause still
    /// has a fresh mask candidate, subject to the 750 ms staleness gate
    /// applied by the consumer (Req 1.2).
    private(set) var latest: TimestampedMask?

    /// Number of times a publication arrived more than 500 ms after the
    /// previous one. Mirrors the DEBUG-only `preshutter.cadence.miss` Logger
    /// line so unit tests can observe the cadence-violation contract without
    /// an OSLog harness (Decision 3 / design Logging section).
    private(set) var cadenceMissCount: Int = 0

    private var inflight: Task<Void, Never>?
    private var lastPublishedAt: ContinuousClock.Instant?

    #if canImport(ARKit) && os(iOS)
    // Captured on the first `resume(frames:)` call so subsequent resumes reuse
    // the same per-subscriber `AsyncStream<ARFrame>` rather than registering a
    // fresh continuation on `ARKitCaptureEngine.frameContinuations` every time.
    // Each access to `engine.frames` creates a new continuation; without
    // caching, every state-transition into a producing state leaked one more
    // continuation into the engine's dict (smolspec H4 — subscription leak).
    private var cachedStream: AsyncStream<ARFrame>?
    #endif
    // Pause gate: `pause()` flips this to true rather than cancelling the
    // for-await Task. The loop body checks it at the top of each iteration and
    // drops paused frames without segmenting or publishing. The AsyncStream
    // keeps draining at full cadence (so `bufferingNewest(1)` doesn't pile up)
    // but no work is done while paused (smolspec H4 — pause-cancels-mid-segment).
    private var isPaused = false
    // Resumed by `finishSegmentCycle` once an in-flight publish has completed,
    // so `awaitPaused()` can guarantee no further `latest` writes after it
    // returns (Decision 13 — snapshot atomicity at the nadir-capture instant).
    private var drainContinuation: CheckedContinuation<Void, Never>?
    // 0 or 1 in practice — incremented before `segmenter.segment(raw)` and
    // decremented inside `finishSegmentCycle`. Drives the `awaitPaused()` drain.
    private var inflightSegmentCycles = 0

    private let segmenter: CoreMLSegmenter
    private let palette: ClassPalette
    private let source: Source

    #if DEBUG
    private let log = Logger(subsystem: "ie.medata.app", category: "Shutter")
    #endif

    init(segmenter: CoreMLSegmenter, palette: ClassPalette, source: Source) {
        self.segmenter = segmenter
        self.palette = palette
        self.source = source
    }

    #if canImport(ARKit) && os(iOS)
    /// Subscribe to an ARFrame stream and start the inference loop. The first
    /// call caches the stream so subsequent calls reuse the same per-subscriber
    /// AsyncStream rather than registering a fresh continuation on the engine
    /// (which would leak — `engine.frames` cannot reliably tear down
    /// continuations on Task cancellation; see smolspec H4). The Task itself
    /// lives forever once started; `pause()`/`awaitPaused()` flip `isPaused`
    /// and the loop body drops frames without publishing while paused.
    func resume(frames: AsyncStream<ARFrame>) {
        isPaused = false
        if inflight != nil { return }
        if cachedStream == nil { cachedStream = frames }
        guard let stream = cachedStream else { return }
        let segmenter = self.segmenter
        inflight = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                let shouldProcess = await MainActor.run { self?.isPaused == false }
                guard shouldProcess else { continue }
                guard let raw = await Self.makeRawFrame(from: frame) else { continue }
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.inflightSegmentCycles += 1 }
                let startedAt = ContinuousClock.now
                let segmentResult = try? await segmenter.segment(raw)
                let latencyMs = millisecondsBetween(startedAt, ContinuousClock.now)
                await self?.finishSegmentCycle(result: segmentResult, latencyMs: latencyMs)
            }
        }
    }

    // Off-MainActor ARFrame → RawFrame conversion. `nonisolated` + `async`
    // ensures the heavy pixel-buffer copy runs on the cooperative pool, not on
    // MainActor (design PreShutterSegmenter section: "PixelBufferAdapter
    // conversion is CPU-heavy and would jank the UI at 2 Hz").
    private nonisolated static func makeRawFrame(from frame: ARFrame) async -> RawFrame? {
        guard let converted = try? PixelBufferAdapter.convert(frame.capturedImage) else {
            return nil
        }
        let intrinsics = CameraIntrinsics(
            fx: frame.camera.intrinsics[0, 0],
            fy: frame.camera.intrinsics[1, 1],
            cx: frame.camera.intrinsics[2, 0],
            cy: frame.camera.intrinsics[2, 1],
            distortion: [],
            imageWidth: converted.width,
            imageHeight: converted.height
        )
        return RawFrame(
            imageBytes: converted.bytes,
            pixelFormat: converted.format,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: converted.width,
            imageHeight: converted.height,
            timestampMonotonicNs: Int64(frame.timestamp * 1_000_000_000),
            intrinsics: intrinsics,
            gravity: Vec3(0, -1, 0),
            worldFromCamera: .identity,
            depth: nil
        )
    }
    #endif

    /// Test seam: same inference loop as `resume(frames:)` but reads
    /// `RawFrame` directly. ARFrame has no public initialiser so unit tests
    /// hand-craft `RawFrame`s and push them through this entry point. Pause
    /// gating mirrors the ARFrame path; this entry point doesn't cache the
    /// stream (it's a test seam — tests construct a fresh stream per case).
    func resume(rawFrames: AsyncStream<RawFrame>) {
        isPaused = false
        if inflight != nil { return }
        let segmenter = self.segmenter
        inflight = Task { [weak self] in
            for await raw in rawFrames {
                guard !Task.isCancelled else { return }
                let shouldProcess = await MainActor.run { self?.isPaused == false }
                guard shouldProcess else { continue }
                await MainActor.run { self?.inflightSegmentCycles += 1 }
                let startedAt = ContinuousClock.now
                let segmentResult = try? await segmenter.segment(raw)
                let latencyMs = millisecondsBetween(startedAt, ContinuousClock.now)
                await self?.finishSegmentCycle(result: segmentResult, latencyMs: latencyMs)
            }
        }
    }

    /// Fire-and-forget pause for non-async state-machine callsites
    /// (`didSet`-style transitions). Flips an internal flag; the for-await
    /// loop body checks it at the top of each iteration and drops the frame
    /// without segmenting or publishing. The Task itself is never cancelled
    /// — it lives for the whole app session and gates work on `isPaused`.
    /// This avoids interrupting an in-flight `segmenter.segment(raw)` mid-
    /// cycle (smolspec H4 — pause-cancels-mid-segment).
    func pause() {
        isPaused = true
    }

    /// Async drain. Sets `isPaused = true` and awaits any in-flight segment
    /// cycle so the caller is guaranteed no further `latest` writes after the
    /// call returns. Used by `CaptureFlowModel.performFlow` immediately after
    /// `capture.end stage=nadir` to atomically read `latest` (Decision 13).
    /// The drain continuation is resumed inside `finishSegmentCycle` AFTER
    /// `publishInternal` has written `latest`, so the caller sees the most
    /// recent value with no further writes coming.
    func awaitPaused() async {
        isPaused = true
        if inflightSegmentCycles == 0 { return }
        await withCheckedContinuation { cont in
            drainContinuation = cont
        }
    }

    // Joins the segmenter return back to MainActor: writes `latest` via
    // `publishInternal` (skipped only when the segmenter threw), decrements
    // the in-flight counter, and resumes any `awaitPaused()` waiter once the
    // counter reaches zero. Called from both the ARFrame and RawFrame paths.
    private func finishSegmentCycle(result: SegmentationResult?, latencyMs: Int) {
        if let result = result {
            publishInternal(argmax: result.argmax, latencyMs: latencyMs)
        }
        inflightSegmentCycles -= 1
        if inflightSegmentCycles == 0, let cont = drainContinuation {
            drainContinuation = nil
            cont.resume()
        }
    }

    private func publishInternal(argmax: ArgmaxMap, latencyMs: Int) {
        let mask = Self.foodMask(from: argmax, palette: palette)
        let now = ContinuousClock.now
        if let last = lastPublishedAt {
            let gapMs = millisecondsBetween(last, now)
            if gapMs > 500 {
                cadenceMissCount += 1
                #if DEBUG
                log.debug(
                    "event=preshutter.cadence.miss expectedHz=2 actualMs=\(gapMs, privacy: .public)"
                )
                #endif
            }
        }
        lastPublishedAt = now
        latest = TimestampedMask(box: MaskBox(mask), producedAt: now, source: source)
        #if DEBUG
        var foodPixels = 0
        for byte in mask.pixels where byte != 0 { foodPixels += 1 }
        log.debug(
            """
            event=preshutter.mask.update foodPixels=\(foodPixels, privacy: .public) \
            ageMs=0 source=\(self.source.rawValue, privacy: .public) \
            latencyMs=\(latencyMs, privacy: .public)
            """
        )
        #endif
    }

    // ArgmaxMap → BinaryMask reduction. Mirrors `PipelineBridges.foodMask`
    // (internal to the Pipeline module); reimplemented here so the App
    // target doesn't need cross-module visibility into Pipeline internals.
    private static func foodMask(from argmax: ArgmaxMap, palette: ClassPalette) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: argmax.width * argmax.height)
        argmax.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(argmax.width * argmax.height) {
                let c = Int(buf[i])
                pixels[i] = palette.isFoodClass(c) ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: argmax.width, height: argmax.height)
    }
}

// Free function (not a method on ContinuousClock.Instant) so it doesn't add to
// the public surface of an Apple type.
private func millisecondsBetween(
    _ start: ContinuousClock.Instant,
    _ end: ContinuousClock.Instant
) -> Int {
    let d = end - start
    let comps = d.components
    // attoseconds-per-millisecond = 10^15.
    return Int(comps.seconds * 1_000 + comps.attoseconds / 1_000_000_000_000_000)
}
