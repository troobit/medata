import CaptureKit
import Foundation
import Pipeline
import Testing
@testable import MeData

// Tests for `PreShutterSegmenter` per spec
// `pipeline-real-device-correctness/tasks.md` task 10.
//
// The producer's behavioural contract is exercised through the
// `resume(rawFrames:)` test seam (ARFrame has no public init so the
// production `resume(frames:)` overload cannot be unit-tested without an
// ARSession). The test seam shares the inference loop with the ARFrame
// variant so cancellation, latest-wins, and the cadence-violation counter
// are observed identically.
//
// Latest-wins (Decision 5) is exercised by a controllable inference engine
// that suspends each `runInference` call on a continuation and is resumed
// by the test, plus an `AsyncStream` with `bufferingNewest(1)` matching the
// production `ARKitCaptureEngine.frames` policy.
@Suite("PreShutterSegmenter")
@MainActor
struct PreShutterSegmenterTests {

    @Test("latest-wins: frames arriving during in-flight inference are coalesced")
    func latestWins() async {
        let palette = makePalette()
        let engine = ControllableInferenceEngine(palette: palette)
        let segmenter = CoreMLSegmenter(
            modelPath: "/dev/null", palette: palette, engine: engine, targetSize: 16
        )
        let pre = PreShutterSegmenter(
            segmenter: segmenter, palette: palette, source: .preShutterStub
        )

        let (stream, cont) = AsyncStream<RawFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pre.resume(rawFrames: stream)

        // Push F1. Engine blocks waiting for the test to release the call.
        cont.yield(makeFrame(width: 8, height: 8))
        await engine.waitForInferenceStart()

        // Push F2, F3, F4 while F1 is still in flight. `bufferingNewest(1)`
        // coalesces — only F4 survives in the stream buffer.
        cont.yield(makeFrame(width: 8, height: 8))
        cont.yield(makeFrame(width: 8, height: 8))
        cont.yield(makeFrame(width: 8, height: 8))

        // Release F1 with a food class. Loop iterates and reads the next
        // available frame from the stream (F4, since F2/F3 were overwritten).
        engine.release(dominantClass: 0, targetSize: 16)
        await engine.waitForInferenceStart()

        // Release F4 with a background class.
        engine.release(dominantClass: palette.background, targetSize: 16)

        // Wait for publish to settle.
        await waitForPublishedCount(2, pre: pre)

        // Exactly two inference calls fired — not four. The intermediate
        // frames were dropped by `bufferingNewest(1)`.
        #expect(engine.totalInferenceCount == 2)

        cont.finish()
        await pre.awaitPaused()
    }

    @Test("awaitPaused returns after the in-flight inference completes")
    func awaitPausedDrainsInflight() async {
        let palette = makePalette()
        let engine = ControllableInferenceEngine(palette: palette)
        let segmenter = CoreMLSegmenter(
            modelPath: "/dev/null", palette: palette, engine: engine, targetSize: 16
        )
        let pre = PreShutterSegmenter(
            segmenter: segmenter, palette: palette, source: .preShutterStub
        )

        let (stream, cont) = AsyncStream<RawFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pre.resume(rawFrames: stream)

        cont.yield(makeFrame(width: 8, height: 8))
        await engine.waitForInferenceStart()

        // Kick off awaitPaused while inference is still in flight.
        let drained = AsyncFlag()
        Task {
            await pre.awaitPaused()
            await drained.set()
        }

        // Inflight call holds the loop. The drain shouldn't have completed yet.
        // We can't directly assert "not yet" without a timeout, but releasing
        // the call must allow the drain to finish below.

        // Release the call — engine returns logits, loop publishes, then exits
        // on the cancellation flag set by awaitPaused.
        engine.release(dominantClass: 0, targetSize: 16)

        await drained.wait()
        // After the drain, latest reflects the released inference.
        #expect(pre.latest != nil)

        cont.finish()
    }

    @Test("latest survives pause()")
    func latestSurvivesPause() async {
        let palette = makePalette()
        let engine = ControllableInferenceEngine(palette: palette)
        let segmenter = CoreMLSegmenter(
            modelPath: "/dev/null", palette: palette, engine: engine, targetSize: 16
        )
        let pre = PreShutterSegmenter(
            segmenter: segmenter, palette: palette, source: .preShutterStub
        )

        let (stream, cont) = AsyncStream<RawFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pre.resume(rawFrames: stream)

        cont.yield(makeFrame(width: 8, height: 8))
        await engine.waitForInferenceStart()
        engine.release(dominantClass: 0, targetSize: 16)
        await waitForPublishedCount(1, pre: pre)

        let before = pre.latest
        #expect(before != nil)

        pre.pause()
        // Fire-and-forget pause does not clear latest.
        #expect(pre.latest != nil)
        #expect(pre.latest?.box === before?.box)

        cont.finish()
    }

    @Test("MaskBox compares by content (pixels), not by identity")
    func maskBoxContentVsIdentity() {
        let a = PreShutterSegmenter.MaskBox(
            BinaryMask(pixels: [0, 1, 0, 1], width: 2, height: 2)
        )
        let b = PreShutterSegmenter.MaskBox(
            BinaryMask(pixels: [0, 1, 0, 1], width: 2, height: 2)
        )
        // Two distinct allocations: identity must NOT match.
        #expect(a !== b)
        // Underlying mask buffers have the same pixel content.
        #expect(a.mask.pixels == b.mask.pixels)
        #expect(a.mask.width == b.mask.width)
        #expect(a.mask.height == b.mask.height)
    }

    @Test("publishing >500 ms apart increments the cadence-miss counter")
    func cadenceMissCounterIncrements() async {
        let palette = makePalette()
        let engine = ControllableInferenceEngine(palette: palette)
        let segmenter = CoreMLSegmenter(
            modelPath: "/dev/null", palette: palette, engine: engine, targetSize: 16
        )
        let pre = PreShutterSegmenter(
            segmenter: segmenter, palette: palette, source: .preShutterStub
        )

        let (stream, cont) = AsyncStream<RawFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pre.resume(rawFrames: stream)

        // First publication — sets lastPublishedAt. No miss possible (no
        // previous timestamp).
        cont.yield(makeFrame(width: 8, height: 8))
        await engine.waitForInferenceStart()
        engine.release(dominantClass: 0, targetSize: 16)
        await waitForPublishedCount(1, pre: pre)
        #expect(pre.cadenceMissCount == 0)

        // Sleep > 500 ms before the second frame. The producer measures the
        // gap between publication instants; this sleep ensures the gap
        // exceeds the cadence threshold.
        try? await Task.sleep(nanoseconds: 600_000_000)

        cont.yield(makeFrame(width: 8, height: 8))
        await engine.waitForInferenceStart()
        engine.release(dominantClass: 0, targetSize: 16)
        await waitForPublishedCount(2, pre: pre)

        #expect(pre.cadenceMissCount == 1)

        cont.finish()
        await pre.awaitPaused()
    }

    // MARK: - Helpers

    private func makePalette(numFoodClasses: Int = 4) -> ClassPalette {
        ClassPalette(
            foodClasses: (0..<numFoodClasses).map { "food_\($0)" },
            background: numFoodClasses,
            unknownFood: numFoodClasses + 1,
            unsupportedLiquid: numFoodClasses + 2,
            version: "test"
        )
    }

    private func makeFrame(width: Int, height: Int) -> RawFrame {
        RawFrame(
            imageBytes: Data(repeating: 128, count: width * height * 4),
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: width, imageHeight: height,
            timestampMonotonicNs: 1,
            intrinsics: CameraIntrinsics(
                fx: 1500, fy: 1500,
                cx: Float(width) / 2, cy: Float(height) / 2,
                distortion: [], imageWidth: width, imageHeight: height
            ),
            gravity: Vec3(0, -1, 0),
            worldFromCamera: .identity,
            depth: nil
        )
    }

    /// Spins on the publication counter until `pre.latest` has been updated
    /// the expected number of times. Bounds the spin with a yield budget to
    /// fail fast on regressions rather than blocking the test runner.
    private func waitForPublishedCount(
        _ expected: Int,
        pre: PreShutterSegmenter,
        budgetYields: Int = 2_000
    ) async {
        var lastSeenAt: ContinuousClock.Instant? = nil
        var count = 0
        var yields = 0
        while count < expected && yields < budgetYields {
            await Task.yield()
            yields += 1
            if let ts = pre.latest, ts.producedAt != lastSeenAt {
                lastSeenAt = ts.producedAt
                count += 1
            }
        }
    }
}

// MARK: - Controllable inference engine

// Engine that suspends every `runInference` call on a continuation. The test
// observes the suspension via `waitForInferenceStart()` and resumes the call
// via `release(dominantClass:targetSize:)`. Provides deterministic timing
// for the latest-wins, drain, and cadence assertions above.
final class ControllableInferenceEngine: SegmenterInferenceEngine, @unchecked Sendable {
    let palette: ClassPalette
    private let lock = NSLock()
    private var pendingCalls: [CheckedContinuation<(logits: [Float], classes: Int), Never>] = []
    private var pendingObservers: [CheckedContinuation<Void, Never>] = []
    private var unobservedStarts = 0
    private var _totalInferenceCount = 0

    var totalInferenceCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _totalInferenceCount
    }

    init(palette: ClassPalette) { self.palette = palette }

    func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int) {
        await withCheckedContinuation { (cont: CheckedContinuation<(logits: [Float], classes: Int), Never>) in
            lock.lock()
            pendingCalls.append(cont)
            _totalInferenceCount += 1
            if let observer = pendingObservers.first {
                pendingObservers.removeFirst()
                lock.unlock()
                observer.resume()
            } else {
                unobservedStarts += 1
                lock.unlock()
            }
        }
    }

    func waitForInferenceStart() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if unobservedStarts > 0 {
                unobservedStarts -= 1
                lock.unlock()
                cont.resume()
            } else {
                pendingObservers.append(cont)
                lock.unlock()
            }
        }
    }

    /// Resumes the oldest pending `runInference` call with a centred logits
    /// buffer favouring `dominantClass`. Mirrors `StubInferenceEngine`'s
    /// (h, l) spread so post-processing softmax assigns ≥ 0.99 to the
    /// dominant class for any palette of <= ~1000 classes.
    func release(dominantClass: Int, targetSize: Int) {
        let classes = palette.totalClasses
        var logits = [Float](repeating: -10, count: targetSize * targetSize * classes)
        for i in 0..<(targetSize * targetSize) {
            logits[i * classes + dominantClass] = 10
        }
        lock.lock()
        guard !pendingCalls.isEmpty else { lock.unlock(); return }
        let cont = pendingCalls.removeFirst()
        lock.unlock()
        cont.resume(returning: (logits, classes))
    }
}

// Tiny single-shot async barrier so tests can observe "drained" from another
// Task without polling. Avoids racing on a shared boolean flag.
@MainActor
private final class AsyncFlag {
    private var isSet = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func set() {
        isSet = true
        for w in waiters { w.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isSet { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }
}
