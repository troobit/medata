import XCTest
@testable import CaptureKit

// Task 8: CaptureSession contract tests.
final class CaptureSessionTests: XCTestCase {
    func testCaptureNadirDeliversQueuedFrame() async throws {
        let frame = RawFrame.fixture(timestampMonotonicNs: 42)
        let engine = MockCaptureEngine(nadirFrame: frame)
        let session = CaptureSession(engine: engine)
        try await session.start()
        let captured = try await session.captureNadir()
        XCTAssertEqual(captured.timestampMonotonicNs, 42)
        try await session.stop()
    }

    func testCaptureBeforeStartFails() async {
        let engine = MockCaptureEngine(nadirFrame: .fixture())
        let session = CaptureSession(engine: engine)
        do {
            _ = try await session.captureNadir()
            XCTFail("expected sessionNotStarted")
        } catch let err as CaptureError {
            XCTAssertEqual(err, .sessionNotStarted)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // Req 2.5 / design §3.1: stop() releases the engine within 200 ms. The mock
    // engine's release is instant; this test verifies the success path.
    func testStopReturnsWithin200msForFastEngine() async throws {
        let engine = MockCaptureEngine(nadirFrame: .fixture())
        engine.releaseDelayNs = 10_000_000 // 10 ms — well inside budget.
        let session = CaptureSession(engine: engine)
        try await session.start()
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            try await session.stop()
        }
        XCTAssertLessThan(elapsed, .milliseconds(200))
    }

    // Req 2.5 / design §3.1: a slow engine triggers releaseTimedOut.
    func testStopThrowsWhenEngineExceedsBudget() async {
        let engine = MockCaptureEngine(nadirFrame: .fixture())
        engine.releaseDelayNs = 500_000_000 // 500 ms — over the budget.
        let session = CaptureSession(engine: engine)
        try? await session.start()
        do {
            try await session.stop()
            XCTFail("expected releaseTimedOut")
        } catch let err as CaptureError {
            XCTAssertEqual(err, .releaseTimedOut)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
