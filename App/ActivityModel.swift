import Foundation
import Observation

// View-model for the activity-entry sheet (specs/data/activity-events Req 3).
// Modelled on `InsulinDoseModel`: the sheet is composition only, all behaviour
// lives here.
//
// Two deliberate divergences from the dose sheet, both from design.md §3:
//  - the kind preselects to the most recently saved kind, so a repeat activity
//    is open -> Save with no kind tap at all;
//  - the timestamp is freely movable rather than now-only, because activity is
//    routinely logged after the fact.
//
// Duration is optional and never blocks Save: blank stores nil, never 0
// (Req 1.5). It steps in 5-minute grains and reuses `InsulinDoseModel`'s pure
// hold schedule, so a 45-minute session is one press-and-hold rather than nine
// taps — the same timing seam, not a second one that can drift.
@Observable
@MainActor
final class ActivityModel {
    static let durationStep = 5
    static let maxDurationMinutes = 600

    var kind: ActivityKind
    /// nil == unrecorded. The numeral renders an em dash for this state — the
    /// slot exists and has no value, which is the app's established treatment.
    var durationMinutes: Int?
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let activities: any ActivityStoring
    private var holdTask: Task<Void, Never>?

    init(activities: any ActivityStoring, kind: ActivityKind? = nil) {
        self.activities = activities
        self.kind = kind ?? Self.lastUsedKind()
    }

    // MARK: - Kind (Req 3.3)

    static func lastUsedKind() -> ActivityKind {
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.activityLastKind) ?? ""
        return ActivityKind(rawValue: raw) ?? .walk
    }

    // MARK: - Duration stepping (Req 3.4)

    enum StepDirection {
        case up, down
    }

    /// Stepping up from blank lands on one grain, not on zero: the control's
    /// first press must produce a usable value. Stepping down through the
    /// first grain returns to blank rather than to 0, so "unrecorded" stays
    /// reachable without a clear button.
    func step(_ direction: StepDirection) {
        let delta = direction == .up ? Self.durationStep : -Self.durationStep
        let next = (durationMinutes ?? 0) + delta
        if next < Self.durationStep {
            durationMinutes = direction == .up ? Self.durationStep : nil
        } else {
            durationMinutes = min(next, Self.maxDurationMinutes)
        }
    }

    func beginHold(_ direction: StepDirection) {
        endHold()
        step(direction)
        holdTask = Task { [weak self] in
            let start = Date()
            var fired = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled else { return }
                let due = InsulinDoseModel.repeatSteps(afterHold: Date().timeIntervalSince(start))
                while fired < due {
                    self.step(direction)
                    fired += 1
                }
            }
        }
    }

    func endHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    // MARK: - Save (Req 3.1)

    var durationLabel: String {
        guard let durationMinutes else { return "—" }
        return "\(durationMinutes)"
    }

    /// Names exactly what the tap writes, the same way `Save 12 U bolus` does.
    var saveLabel: String {
        guard let durationMinutes else { return "Save \(kind.label.lowercased())" }
        return "Save \(durationMinutes) min \(kind.label.lowercased())"
    }

    func save() async -> Bool {
        endHold()
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
            try await activities.saveActivity(event)
            UserDefaults.standard.set(kind.rawValue, forKey: SettingsKeys.activityLastKind)
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }
}
