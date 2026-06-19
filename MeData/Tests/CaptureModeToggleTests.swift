import Foundation
import Testing
@testable import MeData

// Task 47 / Req §20.5 / Decision 16. Behavioural assertions for the
// CaptureModeToggle's persistence + no-LiDAR refusal copy. Visual layout
// (capsule pill, sliding accent) is verified by XCUITest, not here.
@Suite("CaptureModeToggle persistence + no-LiDAR refusal")
@MainActor
struct CaptureModeToggleTests {

    private let testSuiteName = "CaptureModeToggleTests"

    init() {
        UserDefaults.standard.removeObject(forKey: CaptureModeStorage.key)
    }

    @Test("default value is .double on fresh install (Req §4.1)")
    func defaultDouble() {
        UserDefaults.standard.removeObject(forKey: CaptureModeStorage.key)
        #expect(CaptureModeStorage.defaultValue == .double)
    }

    @Test("CaptureMode round-trips through UserDefaults via rawValue")
    func roundTripUserDefaults() {
        UserDefaults.standard.set(CaptureMode.single.rawValue, forKey: CaptureModeStorage.key)
        let raw = UserDefaults.standard.string(forKey: CaptureModeStorage.key)
        let restored = raw.flatMap(CaptureMode.init(rawValue:))
        #expect(restored == .single)
    }

    // Regression: single-mode-toggle-key-mismatch. The toggle persists via
    // @AppStorage(CaptureModeStorage.key); the capture flow resolves the mode
    // through defaultCaptureModeReader(), which reads SettingsKeys.captureMode.
    // Before the fix these were "captureMode" vs "medata.captureMode", so a
    // Single selection never reached the reader and every capture ran as
    // .double regardless of the toggle. The pre-existing roundTripUserDefaults
    // test missed this because it both wrote AND read CaptureModeStorage.key.
    @Test("a Single selection written via the toggle key is observed by the reader")
    func toggleSelectionReachesReader() {
        UserDefaults.standard.set(CaptureMode.single.rawValue, forKey: CaptureModeStorage.key)
        defer { UserDefaults.standard.removeObject(forKey: CaptureModeStorage.key) }
        #expect(defaultCaptureModeReader() == .single)
    }

    @Test("toggle storage key is identical to the reader's key (regression guard)")
    func toggleAndReaderKeysAreUnified() {
        #expect(CaptureModeStorage.key == SettingsKeys.captureMode)
    }

    @Test("no-LiDAR refusal copy is Irish-English (Req §4.2 / §12.1)")
    func noLiDARRefusalCopy() {
        // British/Irish spelling: "sensor" is the same in both; key word here
        // is "LiDAR-equipped" + product-line phrasing matches existing
        // EstimationFailure.noLidarDevice (which uses "depth sensor").
        let copy = CaptureModeStorage.noLiDARRefusal
        #expect(copy.contains("depth sensor"))
        #expect(copy.contains("LiDAR"))
    }

    @Test("label values are Irish-English")
    func labels() {
        #expect(CaptureMode.single.label == "Single")
        #expect(CaptureMode.double.label == "Double")
    }
}
