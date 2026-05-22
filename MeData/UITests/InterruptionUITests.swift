import XCTest

// Task 28 / design.md Testing Strategy (Req §16.1): an ARSession interruption
// (phone call, screen lock) drives the model to `.trackingLost`; when the
// interruption ends, the engine is restarted and the flow returns to
// `.initialising`.
//
// The harness owns the interruption AsyncStream the model observes, so the hidden
// "Began" / "Ended" controls yield the same `InterruptionEvent`s that
// `ARKitCaptureEngine.sessionWasInterrupted/Ended` would emit at runtime. The
// engine.start() re-call on `.ended` is an internal detail covered by the
// CaptureFlowModel unit tests; here we assert its observable proxy — the UI state
// returning to `.initialising`.
final class InterruptionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testInterruptionDrivesTrackingLostThenRecoversToInitialising() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()

        // Reach .ready so a meaningful interruption transition can occur.
        app.buttons["uitest.driveToReady"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 5))

        // Interruption begins → .trackingLost (tracking-lost banner).
        app.buttons["uitest.interruptionBegan"].tap()
        XCTAssertTrue(
            app.staticTexts["hint.trackingLost"].waitForExistence(timeout: 5),
            "sessionWasInterrupted should move the flow into .trackingLost (§16.1)"
        )

        // Interruption ends → engine restarted, flow returns to .initialising.
        app.buttons["uitest.interruptionEnded"].tap()
        XCTAssertTrue(
            app.staticTexts["hint.initialising"].waitForExistence(timeout: 5),
            "sessionInterruptionEnded should reset the flow to .initialising (§16.1)"
        )
    }
}
