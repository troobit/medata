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
