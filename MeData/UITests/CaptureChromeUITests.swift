import XCTest

// Task 52 / UI Req §20 / Decision 16: composition assertions for the new
// CaptureFlowView chrome — close button, capture-mode pill, shutter armed
// state, refusal-sheet present/dismiss. The XCUITest harness in App.swift
// drives the AR-gated flow through deterministic launch arguments since
// ARKit doesn't run on the simulator.
final class CaptureChromeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureTopBarCloseButtonIsPresent() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestResetSelectedTab"]
        app.launch()

        let close = app.buttons["captureTopBar.close"]
        XCTAssertTrue(
            close.waitForExistence(timeout: 5),
            "Top chrome close button should be visible on the Photo tab (Req §20.3)"
        )
    }

    func testCaptureModeToggleIsVisibleOnPhotoTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestResetSelectedTab"]
        app.launch()

        let toggle = app.otherElements["captureModeToggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Capture-mode pill should be visible above the shutter (Req §20.5)"
        )
    }

    func testShutterArmsWhenHarnessDrivesToReady() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestResetSelectedTab"]
        app.launch()

        app.buttons["uitest.driveToReady"].tap()

        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertTrue(
            shutter.isEnabled,
            "Shutter should be armed when tilt/distance/coverage are in-range (Req §20.6)"
        )
    }

    func testRefusalSheetPresentsAndDismissesViaTryAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitestResetSelectedTab", "-uitestPipeline", "refuse"]
        app.launch()

        app.buttons["uitest.driveToReady"].tap()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        app.buttons["uitest.releaseCapture"].tap()

        let tryAgain = app.buttons["refusal.tryAgain"]
        XCTAssertTrue(
            tryAgain.waitForExistence(timeout: 5),
            "Refusal sheet should present its Try again CTA (Req §20.7)"
        )
        tryAgain.tap()
        XCTAssertFalse(
            tryAgain.exists,
            "Try again should dismiss the refusal sheet"
        )
    }
}
