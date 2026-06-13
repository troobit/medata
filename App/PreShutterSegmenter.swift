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
// Concurrency contract (Decisions 5, 12, 13):
//   - `@MainActor`-isolated for publication atomicity; the heavy work inside
//     the inflight `Task` is dispatched off MainActor via the segmenter's
//     non-isolated `segment(_:)` and a nonisolated frame-conversion helper.
//   - Latest-wins on both sides: the AsyncStream is configured for
//     `bufferingNewest(1)` by its producer, and the inference loop runs one
//     `segment(_:)` call at a time — frames arriving while a call is in flight
//     are coalesced by the buffer to the most recent one.
//   - `pause()` is fire-and-forget (cancels the inflight `Task`); `awaitPaused`
//     is async and additionally awaits the in-flight inference to drain, so
//     `CaptureFlowModel.performFlow` can read `latest` atomically at the
//     nadir-capture instant (Decision 13).
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
    /// Subscribe to an ARFrame stream and start the inference loop. Idempotent:
    /// a second call while a loop is already running is a no-op. The producer
    /// stops on `pause()`/`awaitPaused()` and the same instance can be resumed
    /// against a fresh stream after that.
    func resume(frames: AsyncStream<ARFrame>) {
        guard inflight == nil else { return }
        let segmenter = self.segmenter
        inflight = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled else { return }
                guard let raw = await Self.makeRawFrame(from: frame) else { continue }
                guard !Task.isCancelled else { return }
                let startedAt = ContinuousClock.now
                guard let result = try? await segmenter.segment(raw) else { continue }
                guard !Task.isCancelled else { return }
                let latencyMs = millisecondsBetween(startedAt, ContinuousClock.now)
                await self?.publish(argmax: result.argmax, latencyMs: latencyMs)
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
    /// hand-craft `RawFrame`s and push them through this entry point. The
    /// loop body is identical to the ARFrame variant minus the conversion
    /// step, so the latest-wins / cancellation contracts are exercised by
    /// either entry point.
    func resume(rawFrames: AsyncStream<RawFrame>) {
        guard inflight == nil else { return }
        let segmenter = self.segmenter
        inflight = Task { [weak self] in
            for await raw in rawFrames {
                guard !Task.isCancelled else { return }
                let startedAt = ContinuousClock.now
                guard let result = try? await segmenter.segment(raw) else { continue }
                guard !Task.isCancelled else { return }
                let latencyMs = millisecondsBetween(startedAt, ContinuousClock.now)
                await self?.publish(argmax: result.argmax, latencyMs: latencyMs)
            }
        }
    }

    /// Fire-and-forget cancel for non-async state-machine callsites
    /// (`didSet`-style transitions). The cancelled task observes
    /// `Task.isCancelled` at its next suspension point and drops without
    /// publishing further updates.
    func pause() {
        inflight?.cancel()
        inflight = nil
    }

    /// Async drain. Cancels the inflight task and awaits its completion so
    /// the caller is guaranteed no further `latest` writes after the call
    /// returns. Used by `CaptureFlowModel.performFlow` immediately after
    /// `capture.end stage=nadir` to atomically read `latest` (Decision 13).
    func awaitPaused() async {
        let task = inflight
        inflight = nil
        task?.cancel()
        _ = await task?.value
    }

    private func publish(argmax: ArgmaxMap, latencyMs: Int) {
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
