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
    // Version 2 adds `provenance` and `holdsUntil` (specs/data/
    // fingerprick-glucose Decision 8). A v1 blob already reads as
    // `.neverRecorded` on the version check, so there is no migration and no
    // backfill; app and extension ship in one build, so the mismatch window is
    // a single launch.
    public static let schemaVersion = 2

    // The plausible measurable range, in mmol/L (Req 2.7). Inclusive.
    public static let plausibleRange = 1.0...35.0

    public let version: Int
    public let mmolL: Double?
    public let readingDate: Date?
    public let trend: GlucoseTrend?
    public let status: GlucoseBandStatus?
    // How the DISPLAYED reading was measured (Req 3.5). The trend beside it may
    // derive from the other provenance — see `GlucoseDerivation.trend`.
    public let provenance: GlucoseProvenance?
    // Non-nil only while a blood reading holds the display: the ABSOLUTE
    // instant the hold expires, computed app-side as blood instant + the hold
    // window. Absolute rather than a duration so the extension — which cannot
    // see blood readings or app settings — compares a date it already holds
    // (Decision 8), and the window stays an ordinary app-private setting.
    public let holdsUntil: Date?

    public init(
        version: Int, mmolL: Double?, readingDate: Date?,
        trend: GlucoseTrend?, status: GlucoseBandStatus?,
        provenance: GlucoseProvenance? = nil, holdsUntil: Date? = nil
    ) {
        self.version = version
        self.mmolL = mmolL
        self.readingDate = readingDate
        self.trend = trend
        self.status = status
        self.provenance = provenance
        self.holdsUntil = holdsUntil
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
        mmolL: Double, readingDate: Date, trend: GlucoseTrend?, status: GlucoseBandStatus,
        provenance: GlucoseProvenance? = nil, holdsUntil: Date? = nil
    ) -> GlucoseSnapshot {
        guard mmolL.isFinite, plausibleRange.contains(mmolL) else { return .neverRecorded }
        return GlucoseSnapshot(
            version: schemaVersion, mmolL: mmolL, readingDate: readingDate,
            trend: trend, status: status, provenance: provenance, holdsUntil: holdsUntil)
    }
}

// The shared container BOTH the app and the widget write, and the widget reads.
//
// Because there are two writers, the store is monotonic in `readingDate`: a
// write carrying an older reading than the stored one is dropped (Req 1.8,
// Decision 19 — see `merged`, which extends that guard with the hold rule and
// the deletion-authorised rollback).
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
    // written snapshot untouched (Req 1.6) — and, per `merged` below, when the
    // policy says the stored snapshot should stand.
    //
    // `replacingDeleted` carries the instants a deletion has just removed from
    // the event log (fingerprick-glucose Req 6.2, Decision 11). Defaulted to
    // empty, so every existing caller behaves exactly as before.
    //
    // Returns whether the snapshot was stored, so a caller can skip the
    // timeline reload (app) or the render (widget) it would otherwise base on a
    // write that did not happen.
    @discardableResult
    public static func write(
        _ snapshot: GlucoseSnapshot, replacingDeleted removed: [Date] = [],
        to defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> Bool {
        guard let defaults else { return false }
        let stored = read(from: defaults)
        // The deletion-authorised rollback, narrowed to the reading actually
        // removed. The app is authoritative about a row it has just destroyed
        // in a way it is not authoritative about dates generally; an
        // unconditional force-write would reinstate the Decision 19 regression,
        // where a stale app-side recompute rolled back over a newer reading the
        // extension had fetched while the app was suspended.
        //
        // Exact instant equality: both sides carry the same `Date` values,
        // read from the same rows and round-tripped losslessly through JSON.
        let resolved: GlucoseSnapshot?
        if let storedDate = stored.readingDate, removed.contains(storedDate) {
            resolved = snapshot
        } else {
            resolved = merged(snapshot, into: stored, now: Date())
        }
        guard let resolved, let blob = try? JSONEncoder().encode(resolved) else { return false }
        defaults.set(blob, forKey: snapshotKey)
        return true
    }

    /// The longest hold any setting may express (the app clamps its control to
    /// this). A `holdsUntil` further than this past its own reading cannot have
    /// been produced by the derivation, so it is not a hold — it is a bad date.
    static let maxHoldSeconds: TimeInterval = 60 * 60

    /// Whether a stored snapshot is still holding its displayed reading.
    ///
    /// The hold is bounded by the reading it belongs to, not trusted as an
    /// absolute date on its own. `holdsUntil` is always `readingDate +
    /// holdWindow` at the moment it is written, so a device clock that ran
    /// fast — a reading entered while the clock was days ahead, the clock then
    /// corrected — leaves a hold that would otherwise pin a stale glucose value
    /// on the Lock Screen until that future date arrived. On a surface a person
    /// reads before dosing, an old number that refuses to move is the worst
    /// failure available, so a hold that outruns its own reading by more than
    /// any setting could ask for is treated as expired.
    static func isHolding(_ stored: GlucoseSnapshot, now: Date) -> Bool {
        guard let holdsUntil = stored.holdsUntil, holdsUntil > now else { return false }
        guard let readingDate = stored.readingDate else { return false }
        return holdsUntil <= readingDate.addingTimeInterval(maxHoldSeconds)
    }

    // The write policy, and the one place it lives. There are TWO writers: the
    // app publishes what the database holds, and the widget publishes what it
    // fetched for itself while the app was suspended (glucose-lock-widget
    // Decision 16). Neither can see the other's data, so the reconciliation
    // belongs to the store — any future writer inherits it by construction.
    //
    // Returns the snapshot to store, or nil to leave the stored one alone.
    //
    // Case 1 — a sensor candidate arriving while a blood reading holds keeps
    // the held reading and adopts only the candidate's trend. Required for
    // correctness, not polish: the extension fetching a 13:05 sensor reading
    // knows nothing of the 13:02 blood reading holding the display, and case 3
    // alone would accept the clobber (fingerprick-glucose Req 3.8, Decision 9).
    //
    // Case 2 — a candidate carrying the same displayed reading is admitted only
    // when its trend differs. During a hold the app republishes that same
    // reading with a freshly derived arrow; under a strictly-newer rule the
    // write is refused and the arrow freezes for the whole window, foreground
    // included. A candidate whose displayed reading is identical cannot roll
    // anything back, so admitting it costs the guard nothing.
    //
    // Case 3 — Decision 19 unchanged. `readingDate` is the ordering key, not
    // wall-clock write order: it is the only clock the two processes already
    // agree on. Strictly newer, so an equal-dated recompute is a no-op rather
    // than two writers alternating derivations of the same reading. A candidate
    // carrying NO reading is not an older reading: it is the never-recorded
    // state, which the app must still be able to write when the `bsl` history
    // empties.
    //
    // The invariant across all three: the displayed reading's date never
    // decreases. Cases 1 and 2 do not move it at all.
    //
    // Advisory in the same way the vendor rate gate is — read-then-write across
    // two processes has no compare-and-set, so a simultaneous pair can still
    // interleave. This closes an observed regression, not a race that would
    // need a lock the App Group does not offer.
    static func merged(
        _ candidate: GlucoseSnapshot, into stored: GlucoseSnapshot, now: Date
    ) -> GlucoseSnapshot? {
        if isHolding(stored, now: now), candidate.provenance == .sensor {
            return GlucoseSnapshot(
                version: stored.version, mmolL: stored.mmolL,
                readingDate: stored.readingDate, trend: candidate.trend,
                status: stored.status, provenance: stored.provenance,
                holdsUntil: stored.holdsUntil)
        }
        if let candidateDate = candidate.readingDate, candidateDate == stored.readingDate {
            if candidate.provenance == stored.provenance {
                return candidate.trend == stored.trend ? nil : candidate
            }
            // Case 2b — blood displaces sensor at an EQUAL instant. Neither of
            // the rules either side admits it: case 2 wanted matching
            // provenance and case 3 wants a strictly newer date, so a blood
            // reading recorded on the same instant as the stored sensor one
            // never reached the App Group. Home derives locally and showed the
            // blood value while the Lock Screen kept the sensor one, and the
            // divergence did not clear on republish: for as long as the hold
            // runs the app's candidate carries the blood instant, so it stays
            // equal rather than becoming newer. Precedence is the derivation's
            // rule (Req 3.9) and it has to survive the store.
            if candidate.provenance == .blood, stored.provenance == .sensor {
                return candidate
            }
            return nil
        }
        guard let candidateDate = candidate.readingDate,
            let storedDate = stored.readingDate
        else { return candidate }
        return candidateDate > storedDate ? candidate : nil
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
