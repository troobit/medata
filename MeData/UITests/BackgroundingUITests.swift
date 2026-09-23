import XCTest

// Task 27 / design.md Testing Strategy (Req §8.3, best-effort per Decision 12):
// enter `.estimating`, background the app via the Home button, foreground it, and
// assert the UI has reset to `.initialising`.
//
// Per Decision 12 the underlying Pipeline has no cooperative cancellation, so a
// MealRecord may still be written to the persistent store — this test asserts UI
// state only. The `stall` pipeline mode suspends in `.estimating` long enough to
// background while the estimation is in flight.
final class BackgroundingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBackgroundingDuringEstimationResetsUIToInitialising() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestPipeline", "stall"]
        app.launch()

        // Drive to .ready, capture, release the gated frame → .estimating (stalls).
        app.buttons["uitest.driveToReady"].tap()

        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()

        XCTAssertTrue(app.staticTexts["hint.capturing"].waitForExistence(timeout: 5))
        app.buttons["uitest.releaseCapture"].tap()

        XCTAssertTrue(
            app.staticTexts["hint.estimating"].waitForExistence(timeout: 5),
            "Releasing the frame should move the flow into .estimating"
        )

        // Background, then foreground.
        XCUIDevice.shared.press(.home)
        // Give the scene-phase transition time to land before reactivating.
        _ = app.wait(for: .runningBackground, timeout: 5)
        app.activate()

        // §8.3: on foreground the in-flight estimation is abandoned and the UI
        // returns to .initialising.
        XCTAssertTrue(
            app.staticTexts["hint.initialising"].waitForExistence(timeout: 5),
            "Foregrounding after backgrounding mid-estimation should reset to .initialising"
        )
    }
}
