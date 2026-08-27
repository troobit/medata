// Which Apple Health writers are blood meters (specs/data/fingerprick-glucose
// Reqs 1.1, 1.2, 1.5).
//
// HealthKit carries no CGM/BGM flag — `HKMetadataKeyBloodGlucoseMealTime`
// encodes meal timing only — so classification keys on
// `sample.sourceRevision.source.bundleIdentifier`, which is always present,
// unlike `HKDevice`, which any writer may leave nil.
//
// Deliberately outside the `#if canImport(HealthKit)` wall that
// `HealthKitGlucoseSource` sits behind: this is a plain UserDefaults-backed
// map, and keeping it host-buildable is what makes it testable at all.
//
// No Contour bundle identifier is hard-coded here or anywhere else. The literal
// is read off a real sample on device (prerequisites.md) and set through
// Settings — the classification list is what makes that possible without a
// rebuild, and is why Req 1.5 exists.
import Foundation
import GlucoseWidgetShared

// One Apple Health app that has contributed a glucose sample.
public struct HealthKitGlucoseWriter: Codable, Sendable, Equatable, Identifiable {
    public let bundleID: String
    public var displayName: String?
    // Whatever `HKDevice` reported, when it reported anything — carried purely
    // so a person can recognise the writer in Settings.
    public var deviceName: String?
    public var deviceManufacturer: String?
    // nil until classified. Unclassified is NOT the same as classified sensor:
    // Settings shows the difference, even though both yield `.sensor`.
    public var classification: GlucoseProvenance?

    public var id: String { bundleID }

    public init(
        bundleID: String, displayName: String? = nil, deviceName: String? = nil,
        deviceManufacturer: String? = nil, classification: GlucoseProvenance? = nil
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.deviceName = deviceName
        self.deviceManufacturer = deviceManufacturer
        self.classification = classification
    }
}

public struct HealthKitWriterRegistry {

    public static let defaultsKey = "glucose.healthkit.writers"

    // Injected rather than reaching for `.standard` directly so the registry is
    // testable from a throwaway suite while `HealthKitGlucoseSource` stays
    // device-only. The app and the source both pass `.standard`; this is
    // ordinary app-private state, not App Group state.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Every writer seen so far, ordered by bundle identifier so the Settings
    // list does not reshuffle itself between launches.
    public func writers() -> [HealthKitGlucoseWriter] {
        stored().values.sorted { $0.bundleID < $1.bundleID }
    }

    // Req 1.2. Unclassified yields sensor — the fail-safe direction, since
    // mistaking a sensor for blood grants it a hold it has not earned, while
    // the reverse merely records a true reading without precedence.
    public func provenance(for bundleID: String) -> GlucoseProvenance {
        stored()[bundleID]?.classification ?? .sensor
    }

    // Records a writer seen on an arriving sample. Idempotent on the bundle
    // identifier, and it never touches an existing classification — a sample
    // arriving is not a reason to reconsider what the person decided.
    //
    // Device details are filled in but never erased: `HKDevice` is nil on many
    // samples, so a later sample naming the device is new information while a
    // later sample without one is not a retraction.
    public func observe(
        bundleID: String, displayName: String? = nil, deviceName: String? = nil,
        deviceManufacturer: String? = nil
    ) {
        var writers = stored()
        var writer = writers[bundleID] ?? HealthKitGlucoseWriter(bundleID: bundleID)
        writer.displayName = displayName ?? writer.displayName
        writer.deviceName = deviceName ?? writer.deviceName
        writer.deviceManufacturer = deviceManufacturer ?? writer.deviceManufacturer
        writers[bundleID] = writer
        save(writers)
    }

    // Req 1.5. Takes effect on subsequently arriving samples only: rows already
    // recorded keep the provenance they were written with, and are correctable
    // only by deletion (Decision 2 — no data is destroyed by a reclassification).
    public func classify(bundleID: String, as classification: GlucoseProvenance?) {
        var writers = stored()
        var writer = writers[bundleID] ?? HealthKitGlucoseWriter(bundleID: bundleID)
        writer.classification = classification
        writers[bundleID] = writer
        save(writers)
    }

    // An absent or unreadable store reads as no writers rather than failing —
    // the next observation writes a well-formed one over it. Nothing here may
    // be able to break ingestion.
    private func stored() -> [String: HealthKitGlucoseWriter] {
        guard let blob = defaults.data(forKey: Self.defaultsKey),
            let writers = try? JSONDecoder().decode(
                [String: HealthKitGlucoseWriter].self, from: blob)
        else { return [:] }
        return writers
    }

    private func save(_ writers: [String: HealthKitGlucoseWriter]) {
        guard let blob = try? JSONEncoder().encode(writers) else { return }
        defaults.set(blob, forKey: Self.defaultsKey)
    }
}
