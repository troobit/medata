import XCTest

// Task 26 / design.md Testing Strategy: trip `EstimationFailure.noScaleAvailable`
// via the launch-argument harness, assert the refusal banner shows the localised
// Irish-English message verbatim (Req §10.1, §12.2), tap "Try Again", and assert
// the banner dismisses and the flow re-enters `.capturing` at the nadir stage
// (Req §10.2, §10.3).
//
// The capture flow is AR-gated and ARKit doesn't run on the simulator, so the app
// is launched with `-uitest` and driven through the DEBUG harness in App.swift
// (UITestControlPanel + UITestCaptureEngine). The default pipeline mode refuses
// with `.noScaleAvailable`.
final class RefusalFlowUITests: XCTestCase {
    // Must match EstimationFailure.noScaleAvailable.localisedMessage verbatim (§12.2).
    private let refusalMessage =
        "Unable to determine meal scale. Please include the reference card in the image."

    override func setUp() {
        continueAfterFailure = false
    }

    func testRefusalBannerShowsLocalisedMessageAndTryAgainReturnsToCapturing() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestPipeline", "refuse"]
        app.launch()

        // Arm the shutter, then capture: shutter → .capturing, release the gated
        // frame → .estimating → .refused.
        app.buttons["uitest.driveToReady"].tap()

        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()

        XCTAssertTrue(
            app.staticTexts["hint.capturing"].waitForExistence(timeout: 5),
            "Shutter tap should move the flow into .capturing"
        )

        app.buttons["uitest.releaseCapture"].tap()

        // Refusal banner appears with the verbatim localised message. The message
        // Label and the Try Again button are the reliable accessibility elements;
        // querying the message by its label text also asserts §12.2 verbatim copy.
        let message = app.staticTexts[refusalMessage]
        XCTAssertTrue(
            message.waitForExistence(timeout: 5),
            "Estimation failure must surface the refusal banner with the verbatim "
                + "localised message (§10.1, §12.2)"
        )
        XCTAssertTrue(app.buttons["refusal.tryAgain"].exists)

        // Try Again clears the banner and re-arms capture at the nadir stage.
        app.buttons["refusal.tryAgain"].tap()

        XCTAssertTrue(
            app.staticTexts["hint.capturing"].waitForExistence(timeout: 5),
            "Try Again should re-enter .capturing at the retry stage (§10.2)"
        )
        XCTAssertFalse(
            message.exists,
            "Try Again should dismiss the refusal banner"
        )
    }
}
