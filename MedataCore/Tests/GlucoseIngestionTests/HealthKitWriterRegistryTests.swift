import Foundation
import GlucoseWidgetShared
import XCTest

@testable import GlucoseIngestion

// The Apple Health writer classification (specs/data/fingerprick-glucose
// Reqs 1.1, 1.2, 1.5).
//
// HealthKit carries no CGM/BGM flag, so classification keys on the writing
// app's bundle identifier. No Contour bundle id is hard-coded anywhere: the
// literal is read off a real sample on device and set through Settings, which
// is exactly why the registry exists.
final class HealthKitWriterRegistryTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var registry: HealthKitWriterRegistry!

    override func setUp() {
        super.setUp()
        suiteName = "HealthKitWriterRegistryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        registry = HealthKitWriterRegistry(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        registry = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - The fail-safe direction (Req 1.2)

    // Mistaking a sensor for a blood meter would grant it a 15-minute hold it
    // has not earned; the reverse merely records a true reading without
    // precedence. So an unknown writer is a sensor.
    func testAnUnclassifiedBundleIDYieldsSensor() {
        XCTAssertEqual(registry.provenance(for: "com.unknown.app"), .sensor)

        registry.observe(bundleID: "com.unknown.app", displayName: "Unknown")
        XCTAssertEqual(
            registry.provenance(for: "com.unknown.app"), .sensor,
            "merely being seen is not a classification")
    }

    func testAClassifiedBundleIDYieldsItsClassification() {
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.classify(bundleID: "com.example.meter", as: .blood)

        XCTAssertEqual(registry.provenance(for: "com.example.meter"), .blood)

        registry.classify(bundleID: "com.example.meter", as: .sensor)
        XCTAssertEqual(registry.provenance(for: "com.example.meter"), .sensor)
    }

    // MARK: - Observation (Req 1.5)

    func testObservingRecordsIdentityIncludingDeviceDetails() {
        registry.observe(
            bundleID: "com.example.meter", displayName: "Meter",
            deviceName: "Contour Next One", deviceManufacturer: "Ascensia")

        let writers = registry.writers()
        XCTAssertEqual(writers.count, 1)
        XCTAssertEqual(writers[0].bundleID, "com.example.meter")
        XCTAssertEqual(writers[0].displayName, "Meter")
        XCTAssertEqual(writers[0].deviceName, "Contour Next One")
        XCTAssertEqual(writers[0].deviceManufacturer, "Ascensia")
        XCTAssertNil(writers[0].classification)
    }

    func testReObservingNeitherDuplicatesNorOverwritesTheClassification() {
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.classify(bundleID: "com.example.meter", as: .blood)

        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")

        let writers = registry.writers()
        XCTAssertEqual(writers.count, 1, "the bundle id is the identity")
        XCTAssertEqual(writers[0].classification, .blood)
        XCTAssertEqual(registry.provenance(for: "com.example.meter"), .blood)
    }

    // HKDevice is nil on many samples, so a later sample naming the device is
    // new information — but a later sample without one is not a retraction.
    func testReObservingFillsInDeviceDetailsWithoutErasingKnownOnes() {
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.observe(
            bundleID: "com.example.meter", displayName: "Meter",
            deviceName: "Contour Next One", deviceManufacturer: "Ascensia")
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")

        let writers = registry.writers()
        XCTAssertEqual(writers.count, 1)
        XCTAssertEqual(writers[0].deviceName, "Contour Next One")
        XCTAssertEqual(writers[0].deviceManufacturer, "Ascensia")
    }

    func testEveryObservedWriterIsListed() {
        registry.observe(bundleID: "com.example.sensor", displayName: "Sensor")
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.classify(bundleID: "com.example.meter", as: .blood)

        let writers = registry.writers()
        XCTAssertEqual(writers.map(\.bundleID), ["com.example.meter", "com.example.sensor"])
        XCTAssertEqual(writers.map(\.classification), [.blood, nil])
    }

    // MARK: - Persistence

    func testClassificationSurvivesANewRegistryOverTheSameDefaults() {
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        registry.classify(bundleID: "com.example.meter", as: .blood)

        let reopened = HealthKitWriterRegistry(defaults: defaults)
        XCTAssertEqual(reopened.provenance(for: "com.example.meter"), .blood)
        XCTAssertEqual(reopened.writers().count, 1)
    }

    func testAnUnreadableStoreReadsAsNoWritersRatherThanFailing() {
        defaults.set(Data("not a registry".utf8), forKey: HealthKitWriterRegistry.defaultsKey)

        XCTAssertTrue(registry.writers().isEmpty)
        XCTAssertEqual(registry.provenance(for: "com.example.meter"), .sensor)

        // And it heals: the next observation writes a well-formed store.
        registry.observe(bundleID: "com.example.meter", displayName: "Meter")
        XCTAssertEqual(registry.writers().count, 1)
    }
}
