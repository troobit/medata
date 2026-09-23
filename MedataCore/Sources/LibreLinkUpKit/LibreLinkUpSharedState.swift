// The state the app and the MeDataWidgets extension both need in order to
// fetch from LibreLinkUp (glucose-lock-widget Decision 16, Req 6.2–6.4).
//
// Everything here lives in the App Group suite rather than
// `UserDefaults.standard`, because the widget process cannot see the app's
// private store. The keychain items move for the same reason — see
// `LibreLinkUpKeychain.accessGroup`.
import Foundation
import GlucoseWidgetShared

// The one vendor poll interval (cgm-connect Decision 13). The app's poll loop
// and the widget's rate gate both read it, so the steady-state vendor request
// rate is one fetch per interval regardless of which process asks.
//
// 5 minutes matches the cadence LibreLinkUp actually serves and stays clear of
// the ~3-minute rate with known ban evidence, but the vendor's tolerance at
// this rate is untested. The recorded rollback is 15 minutes here, which
// re-arms cgm-connect Decision 12's adaptive tightening without further code
// change — see task 16.7's vendor-signal watch.
public enum LibreLinkUpPolling {
    public static let interval: TimeInterval = 5 * 60
}

// The shared vendor request budget (Req 6.3). One timestamp, written by both
// processes after every successful fetch and consulted before every fetch.
//
// Advisory, not atomic: check-then-fetch on a UserDefaults timestamp has no
// cross-process compare-and-set, and `cfprefsd` visibility lags, so an app poll
// and a widget wake landing together can both pass. The accepted outcome is a
// rare double fetch — the ban evidence concerns sustained fast polling, not
// occasional overlap.
public enum LibreLinkUpRateGate {

    static let lastFetchKey = "glucose.source.librelinkup.lastVendorFetchAt"

    public static func lastFetchAt(
        from defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> Date? {
        guard let defaults else { return nil }
        let stored = defaults.double(forKey: lastFetchKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    public static func recordFetch(
        at instant: Date = Date(), in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        defaults?.set(instant.timeIntervalSince1970, forKey: lastFetchKey)
    }

    // Open when no fetch is on record, or the recorded one is at least
    // `interval` old. A last-fetch stamp in the future (clock skew) closes the
    // gate until the clock catches up rather than opening it forever.
    public static func isOpen(
        now: Date = Date(), interval: TimeInterval = LibreLinkUpPolling.interval,
        in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> Bool {
        guard let last = lastFetchAt(from: defaults) else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}

// The non-secret connection state: whether LibreLinkUp is connected at all, the
// regional host the login redirect resolved, and the followed patient id. The
// widget reads all three and writes none of them — auth and connection
// lifecycle are app-owned (design.md).
public enum LibreLinkUpSharedState {

    public static let sourceID = "librelinkup"

    // Same key names they had in `UserDefaults.standard`, so the migration is a
    // move between suites and not also a rename.
    static let connectedKey = "glucose.source.librelinkup.connected"
    static let hostKey = "glucose.source.librelinkup.host"
    static let patientIDKey = "glucose.source.librelinkup.patientId"

    public static func isConnected(
        in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> Bool {
        defaults?.bool(forKey: connectedKey) ?? false
    }

    public static func setConnected(
        _ connected: Bool, in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        defaults?.set(connected, forKey: connectedKey)
    }

    public static func host(
        in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> String? {
        defaults?.string(forKey: hostKey)
    }

    public static func setHost(
        _ host: String?, in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        set(host, forKey: hostKey, in: defaults)
    }

    public static func patientID(
        in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) -> String? {
        defaults?.string(forKey: patientIDKey)
    }

    public static func setPatientID(
        _ patientID: String?, in defaults: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        set(patientID, forKey: patientIDKey, in: defaults)
    }

    private static func set(_ value: String?, forKey key: String, in defaults: UserDefaults?) {
        if let value {
            defaults?.set(value, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    // MARK: - One-time migration

    // Existing installs hold these three values in `UserDefaults.standard` and
    // the keychain items in the app's private access group. Copy each across
    // and remove the old copy. Idempotent: once the private store is empty this
    // is a no-op, so it is safe to call on every launch.
    //
    // The keychain half re-saves through the shared-group keychain and deletes
    // the private-group items. A partial migration (shared write succeeded,
    // private delete did not) leaves a stale private copy that nothing reads.
    public static func migrateFromAppPrivateStorage(
        from appPrivate: UserDefaults = .standard,
        to shared: UserDefaults? = GlucoseSnapshotStore.sharedDefaults
    ) {
        guard let shared else { return }
        if appPrivate.object(forKey: connectedKey) != nil {
            shared.set(appPrivate.bool(forKey: connectedKey), forKey: connectedKey)
            appPrivate.removeObject(forKey: connectedKey)
        }
        for key in [hostKey, patientIDKey] {
            if let value = appPrivate.string(forKey: key) {
                shared.set(value, forKey: key)
                appPrivate.removeObject(forKey: key)
            }
        }

        // The old group is named explicitly, NOT left nil: adding the
        // keychain-access-groups entitlement makes the shared group the
        // process's DEFAULT group, so a nil group here would read — and then
        // delete — the very items the migration just wrote.
        let appPrivateKeychain = LibreLinkUpKeychain(accessGroup: appPrivateAccessGroup)
        let sharedKeychain = LibreLinkUpKeychain()
        let credentials = appPrivateKeychain.credentials()
        let session = appPrivateKeychain.session()
        guard credentials != nil || session != nil else { return }
        if let credentials { try? sharedKeychain.saveCredentials(credentials) }
        if let session { sharedKeychain.saveSession(session) }
        appPrivateKeychain.deleteAll()
    }

    // Where the keychain items lived before the shared group existed: the app's
    // own application-identifier, which is the default access group for a
    // target with no keychain-access-groups entitlement.
    static let appPrivateAccessGroup = "6G974YC4Z2.rtob.MeData"
}
