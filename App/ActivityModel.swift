import Foundation
import Observation
import Persistence

// View-model for the activity mode of `LogSheet` (specs/data/activity-events
// Req 3). Follows InsulinDoseModel's split exactly: the view is composition
// only, all behaviour lives here.
//
// The two-tap contract (Req 3.1, 3.3): the sheet opens on the most recently
// saved kind with the timestamp at now and the duration blank, so a repeat
// activity is open → Save. Nothing on the happy path needs touching.
@Observable
@MainActor
final class ActivityModel {
    // Req 2.4 — no intensity, no effort rating, no calorie figure. Duration is
    // the only quantity, and it is optional.
    static let minDurationMinutes = 5
    static let maxDurationMinutes = 480
    static let durationStep = 5

    var kind: ActivityKind {
        didSet { rememberKind() }
    }
    // nil means unrecorded, and is written as an absent `value`, never 0
    // (Req 1.5). The stepper starts here and `clearDuration()` returns here.
    var durationMinutes: Int?
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let store: any PersistenceStore
    private let defaults: UserDefaults

    init(store: any PersistenceStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let remembered = defaults.string(forKey: SettingsKeys.activityLastKind)
            .flatMap(ActivityKind.init(rawValue:))
        self.kind = remembered ?? ActivityKind.allCases[0]
    }

    // MARK: - Duration (Req 3.4)

    // The first tap of `+` on a blank duration lands on the floor rather than
    // on `floor + step`, so one tap means "the shortest thing I would bother
    // logging" instead of an arbitrary second value.
    func stepDuration(_ delta: Int) {
        guard let current = durationMinutes else {
            durationMinutes = delta > 0 ? Self.minDurationMinutes : nil
            return
        }
        let next = current + delta * Self.durationStep
        durationMinutes = next < Self.minDurationMinutes
            ? nil
            : min(next, Self.maxDurationMinutes)
    }

    var durationLabel: String {
        guard let durationMinutes else { return "—" }
        return "\(durationMinutes)"
    }

    // MARK: - Save (Req 1.1–1.6)

    // Returns true on success so the sheet can dismiss. Every dependent
    // surface refreshes through the store's `eventsDidChange` tick.
    func save() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let event = ActivityEvent(
            timestamp: timestamp,
            kind: kind,
            durationMinutes: durationMinutes.map(Double.init),
            provenance: .manual
        )
        do {
            try await store.saveActivity(event)
            rememberKind()
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    var saveTitle: String {
        guard let durationMinutes else { return "Save \(Self.label(for: kind))" }
        return "Save \(Self.label(for: kind)) \(durationMinutes) min"
    }

    private func rememberKind() {
        defaults.set(kind.rawValue, forKey: SettingsKeys.activityLastKind)
    }

    // Display labels are UI-only; the stored key is the enum's raw value
    // (Req 1.4), so renaming any of these orphans nothing.
    static func label(for kind: ActivityKind) -> String {
        switch kind {
        case .swim: "Swim"
        case .waterpolo: "Water polo"
        case .cycle: "Cycle"
        case .run: "Run"
        case .walk: "Walk"
        case .gym: "Gym"
        case .other: "Other"
        }
    }
}
