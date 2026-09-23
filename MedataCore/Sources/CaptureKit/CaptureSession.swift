import Foundation

// Per design §3.1: CaptureSession is a serial-access actor wrapping an underlying
// platform engine. The engine produces RawFrames (already converted to portable types
// via SimdAdapter) and releases the camera within 200 ms of stop() per Req 2.5.

public enum CaptureTarget: Sendable {
    case nadir
    case oblique
}

public enum CaptureError: Error, Equatable {
    case lidarUnavailable
    case sessionNotStarted
    case captureFailed(String)
    case worldTrackingDegraded
    case releaseTimedOut
}

public protocol CaptureEngine: Sendable, AnyObject {
    func start() async throws
    func captureFrame(target: CaptureTarget) async throws -> RawFrame
    func release() async
}

public actor CaptureSession {
    private let engine: any CaptureEngine
    private var started = false

    public init(engine: any CaptureEngine) {
        self.engine = engine
    }

    public func start() async throws {
        try await engine.start()
        started = true
    }

    public func captureNadir() async throws -> RawFrame {
        guard started else { throw CaptureError.sessionNotStarted }
        return try await engine.captureFrame(target: .nadir)
    }

    public func captureOblique() async throws -> RawFrame {
        guard started else { throw CaptureError.sessionNotStarted }
        return try await engine.captureFrame(target: .oblique)
    }

    // Stop with a 200 ms ceiling per Req 2.5. Race the engine's release() against a
    // 200 ms timer; the timer wins → throw releaseTimedOut. The engine is left
    // responsible for any required teardown beyond the budget.
    public func stop() async throws {
        started = false
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [engine] in
                await engine.release()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 200 * 1_000_000)
                throw CaptureError.releaseTimedOut
            }
            // Whichever finishes first wins; cancel the loser.
            try await group.next()
            group.cancelAll()
        }
    }
}
