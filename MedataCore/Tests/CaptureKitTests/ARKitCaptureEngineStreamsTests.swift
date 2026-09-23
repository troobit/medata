#if canImport(ARKit) && os(iOS)
import ARKit
import XCTest
@testable import CaptureKit

// Task 1: ARKitCaptureEngine streams + interruption observer contract tests.
//
// Notes on testability: `ARFrame` has no public initialiser, so end-to-end
// "frames stream yields an ARFrame from a synthesised delegate call" cannot
// be exercised in a host-side unit test. Those paths are covered on-device by
// PipelinePerformanceTests / capture-flow smoke tests. The tests below cover
// what can be verified purely against ARKit's public API surface:
//   • delegate identity (engine is its own ARSessionDelegate)
//   • interruption stream behaviour (.began / .ended ordering from
//     ARSessionObserver method calls)
//   • subscriber lifecycle (cancellation removes the continuation)
final class ARKitCaptureEngineStreamsTests: XCTestCase {

    func testEngineIsARSessionDelegateOnInit() {
        let engine = ARKitCaptureEngine()
        XCTAssertTrue(engine.arSession.delegate === engine)
    }

    func testArSessionAccessorReturnsSameInstance() {
        let engine = ARKitCaptureEngine()
        XCTAssertTrue(engine.arSession === engine.arSession)
    }

    func testFramesSubscriptionPreservesEngineDelegateIdentity() async {
        let engine = ARKitCaptureEngine()
        let stream = engine.frames
        var iterator = stream.makeAsyncIterator()
        let pollTask = Task { await iterator.next() }
        // Yield once to let the iteration spin up the continuation registration.
        await Task.yield()
        XCTAssertTrue(engine.arSession.delegate === engine)
        pollTask.cancel()
        _ = await pollTask.value
    }

    func testInterruptionStreamEmitsBeganThenEndedInOrder() async {
        let engine = ARKitCaptureEngine()
        var iterator = engine.interruptions.makeAsyncIterator()

        // Allow the iterator to register its continuation before we yield.
        let received = Task { () -> [ARKitCaptureEngine.InterruptionEvent] in
            var events: [ARKitCaptureEngine.InterruptionEvent] = []
            for _ in 0..<2 {
                guard let next = await iterator.next() else { break }
                events.append(next)
            }
            return events
        }
        await Task.yield()

        engine.sessionWasInterrupted(engine.arSession)
        engine.sessionInterruptionEnded(engine.arSession)

        let events = await received.value
        XCTAssertEqual(events, [.began, .ended])
    }

    func testInterruptionStreamCancellationStopsIteration() async {
        let engine = ARKitCaptureEngine()
        var iterator = engine.interruptions.makeAsyncIterator()

        let task = Task { await iterator.next() }
        await Task.yield()
        task.cancel()

        // After cancellation the awaited next() should return nil (no leak).
        let result = await task.value
        XCTAssertNil(result)
    }

    func testFramesStreamCancellationStopsIteration() async {
        let engine = ARKitCaptureEngine()
        var iterator = engine.frames.makeAsyncIterator()

        let task = Task { await iterator.next() }
        await Task.yield()
        task.cancel()

        let result = await task.value
        XCTAssertNil(result)
    }

    func testInterruptionStreamSupportsMultipleSubscribers() async {
        let engine = ARKitCaptureEngine()
        var iterA = engine.interruptions.makeAsyncIterator()
        var iterB = engine.interruptions.makeAsyncIterator()

        let taskA = Task { await iterA.next() }
        let taskB = Task { await iterB.next() }
        await Task.yield()

        engine.sessionWasInterrupted(engine.arSession)

        let (a, b) = await (taskA.value, taskB.value)
        XCTAssertEqual(a, .began)
        XCTAssertEqual(b, .began)
    }

    // Regression: bindPreviewSession must run the bound session immediately so
    // that ARView has a configured, running session to render. Before the fix,
    // bindPreviewSession deferred the run until CaptureFlowModel's async
    // start() task set runRequested=true, leaving the view rendering a
    // bound-but-unconfigured session and producing repeated
    // FigCaptureSourceRemote err=-12784 / Fig err=-12710 log lines on
    // iPhone 13 Pro Max during the gap.
    //
    // Asserts the engine's `isRunning` flag rather than `ARSession.configuration`
    // because the simulator does not reliably set `configuration` on `run(_:)`
    // without a camera; `isRunning` is the engine-internal post-condition that
    // proves `applyRunStateIfNeeded` cleared its guard and called `session.run`.
    @MainActor
    func testBindPreviewSessionRunsConfigImmediately() {
        let engine = ARKitCaptureEngine()
        let external = ARSession()
        XCTAssertFalse(engine.isRunning, "engine starts not-running")

        engine.bindPreviewSession(external)

        XCTAssertTrue(
            engine.isRunning,
            "bindPreviewSession must run the session immediately — deferring to the async start() task reopens the FigCaptureSourceRemote race"
        )
    }
}
#endif
