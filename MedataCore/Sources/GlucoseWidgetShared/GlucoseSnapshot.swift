import Foundation

// The trend arrow states (Req 3.2, Decision 4). Derived from recent readings by
// `TrendsMath.trend`; the widget only ever reads the already-derived value.
public enum GlucoseTrend: String, Codable, Sendable, CaseIterable {
    case fallingFast, falling, fallingSlow, steady, risingSlow, rising, risingFast

    public var arrow: String {
        switch self {
        case .fallingFast: return "↓↓"
        case .falling: return "↓"
        case .fallingSlow: return "↘"
        case .steady: return "→"
        case .risingSlow: return "↗"
        case .rising: return "↑"
        case .risingFast: return "↑↑"
        }
    }
}

// The reading's position against the target band (Req 4.1).
public enum GlucoseBandStatus: String, Codable, Sendable {
    case low, inRange, high
}

// The whole app→widget contract (Req 1.1). Every field is optional except the
// schema version: all-nil IS the never-recorded state (Req 8.1), which is why
// there is no separate flag.
//
// `status` is derivable from `mmolL`, but it is carried here so the widget never
// re-derives band logic — `TrendsMath` stays the single source of truth.
public struct GlucoseSnapshot: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    // The plausible measurable range, in mmol/L (Req 2.7). Inclusive.
    public static let plausibleRange = 1.0...35.0

    public let version: Int
    public let mmolL: Double?
    public let readingDate: Date?
    public let trend: GlucoseTrend?
    public let status: GlucoseBandStatus?

    public init(
        version: Int, mmolL: Double?, readingDate: Date?,
        trend: GlucoseTrend?, status: GlucoseBandStatus?
    ) {
        self.version = version
        self.mmolL = mmolL
        self.readingDate = readingDate
        self.trend = trend
        self.status = status
    }

    public static let neverRecorded = GlucoseSnapshot(
        version: schemaVersion, mmolL: nil, readingDate: nil, trend: nil, status: nil)

    // The publisher's only construction path, so the value sanity guard cannot
    // be bypassed: a non-finite or implausible reading yields `.neverRecorded`
    // rather than a snapshot carrying a fabricated decimal (Req 2.7). No
    // ingestion source encodes an out-of-range HI/LO sentinel today — should one
    // ever land, rendering it AS a sentinel is a new requirement, not a tweak
    // here.
    public static func make(
        mmolL: Double, readingDate: Date, trend: GlucoseTrend?, status: GlucoseBandStatus
    ) -> GlucoseSnapshot {
        guard mmolL.isFinite, plausibleRange.contains(mmolL) else { return .neverRecorded }
        return GlucoseSnapshot(
            version: schemaVersion, mmolL: mmolL, readingDate: readingDate,
            trend: trend, status: status)
    }
}

// The shared container the app writes and the widget reads.
//
// One Codable value under one key, so a concurrent reader sees the old blob or
// the new one and never a spliced mixture (Req 1.5) — plist-level atomicity,
// which also sidesteps the App Group file-write trap where `containerURL` is
// non-nil but the sandbox refuses the write. Atomicity is not freshness: each
// process caches its own CFPreferences view, so nothing here may depend on an
// immediate cross-process read-back. The ordering is safe because the widget
// reads in a freshly-launched `getTimeline` that the app's reload triggered.
//
// A nil suite is NOT a misprovisioning detector: `UserDefaults(suiteName:)`
// returns nil only for an invalid or own-bundle name, so a missing App Group
// entitlement still hands back a non-nil PRIVATE store. The app then writes
// where the widget cannot see and the widget shows never-recorded. Only the
// on-device round trip (prerequisites.md) catches that.
public enum GlucoseSnapshotStore {
    public static let appGroupID = "group.rtob.MeData"

    // Pinned here because the app's `reloadTimelines(ofKind:)` and the
    // extension's `StaticConfiguration(kind:)` live in different targets and
    // must match exactly. Follows the existing launcher convention
    // (ie.medata.widget.insulin / .capture — docs/agent-notes/widget-extension.md).
    public static let widgetKind = "ie.medata.widget.glucose"

    static let snapshotKey = "glucose.snapshot"

    public static var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    // No-ops when the suite is nil or encoding fails, leaving any previously
    // written snapshot untouched (Req 1.6).
    public static func write(
        _ snapshot: GlucoseSnapshot, to defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        guard let defaults, let blob = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(blob, forKey: snapshotKey)
    }

    // Never-recorded when the suite is nil, the key is absent, the blob does not
    // decode, or the schema version is not the one this build understands
    // (Req 1.7).
    public static func read(
        from defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> GlucoseSnapshot {
        guard
            let defaults,
            let blob = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(GlucoseSnapshot.self, from: blob),
            snapshot.version == GlucoseSnapshot.schemaVersion
        else { return .neverRecorded }
        return snapshot
    }
}
