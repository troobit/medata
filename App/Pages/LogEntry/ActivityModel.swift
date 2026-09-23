import Foundation
import Observation
import Persistence
import SwiftUI

// View-model for the activity-entry sheet (specs/data/activity-events Req 3).
// Modelled on `InsulinDoseModel`: it owns the whole entry state so the sheet is
// composition only, and the two sheet layouts under comparison share this one
// model — only the view differs between them.
//
// The happy path is two taps (Req 3.1/3.3): the sheet opens on the most
// recently saved kind, so a repeat activity is open → Save. Duration is
// optional and never blocks a save (Req 3.4) — blank saves `nil`, never `0`
// (Req 1.5). The timestamp defaults to now and can be moved, the one place
// this diverges from the dose sheet, because activity is routinely logged
// after the fact (Req 3.2). Nothing here asks for intensity, effort or
// calories (Req 2.4).
@Observable
@MainActor
final class ActivityModel {
    // Duration bounds for the stepper layout. The floor is the step itself:
    // stepping below it clears the value back to "unrecorded" rather than
    // walking down to a meaningless one-minute activity.
    static let durationStep: Double = 5
    static let maxDurationMinutes: Double = 600
    // One-tap durations for the preset layout, in minutes.
    static let durationPresets: [Double] = [20, 30, 45, 60, 90]

    var kind: ActivityKind
    // nil == unrecorded (Req 1.5). Never written as zero.
    var durationMinutes: Double?
    // Activity START (Req 6.1). Defaults to now; the sheet's time control
    // moves it (Req 3.2).
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let store: any PersistenceStore

    init(store: any PersistenceStore) {
        self.store = store
        kind = Self.lastUsedKind()
    }

    // MARK: - Duration (Req 3.4)

    func stepDurationUp() {
        let next = (durationMinutes ?? 0) + Self.durationStep
        durationMinutes = min(next, Self.maxDurationMinutes)
    }

    // Stepping down off the floor clears the field: "no duration" is a value
    // the developer must be able to get back to without closing the sheet.
    func stepDurationDown() {
        guard let current = durationMinutes else { return }
        let next = current - Self.durationStep
        durationMinutes = next < Self.durationStep ? nil : next
    }

    func clearDuration() {
        durationMinutes = nil
    }

    // Preset layout: tapping the selected preset again clears it, so blank
    // stays one tap away.
    func toggleDuration(_ minutes: Double) {
        durationMinutes = durationMinutes == minutes ? nil : minutes
    }

    // "45 min" or an em dash when unrecorded — never "0 min".
    var durationLabel: String {
        guard let minutes = durationMinutes else { return "—" }
        return "\(Int(minutes.rounded())) min"
    }

    // MARK: - Save

    // Writes one activity event and returns true so the view can dismiss. The
    // Graph and Records surfaces refresh themselves off the store's
    // `eventsDidChange` tick — no manual reload. Provenance is `manual` for
    // everything this spec writes (Req 1.6 / Decision 4).
    func save() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let event = ActivityEvent(
            timestamp: timestamp,
            kind: kind,
            durationMinutes: durationMinutes,
            provenance: .manual
        )
        do {
            try await store.saveActivity(event)
            Self.recordLastUsedKind(kind)
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Most recently used kind (Req 3.3)

    // Stored as the kind's stable machine key, the same value the metadata
    // carries (Req 1.4), so a renamed display label never orphans the
    // preference. An unreadable or retired key falls back to the first kind
    // rather than failing the sheet.
    private static func lastUsedKind() -> ActivityKind {
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.activityLastKind) ?? ""
        return ActivityKind(rawValue: raw) ?? .swim
    }

    private static func recordLastUsedKind(_ kind: ActivityKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: SettingsKeys.activityLastKind)
    }
}

// Display shape for an activity kind, kept App-side: `ActivityKind`'s raw
// values are storage keys (Req 1.4) and must not be pressed into service as
// user-facing labels. The sheet, the Graph day list and the Records row all
// read these, so a label change lands in one place.
extension ActivityKind {
    var displayLabel: String {
        switch self {
        case .swim: "Swim"
        case .waterpolo: "Waterpolo"
        case .cycle: "Cycle"
        case .run: "Run"
        case .walk: "Walk"
        case .gym: "Gym"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .swim: "figure.pool.swim"
        case .waterpolo: "figure.waterpolo"
        case .cycle: "figure.outdoor.cycle"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .gym: "figure.strengthtraining.traditional"
        case .other: "figure.mixed.cardio"
        }
    }
}
