import Foundation
import Observation
import Persistence

// View-model for the insulin dose-entry sheet (PRD
// regression-suggestion-integration App 2–5). Opens pre-filled with the
// two-tap happy path — 10 U bolus, timestamped now — and owns the stepper
// behaviour: a tap steps 1 U, press-and-hold repeats at ~4 steps/s, and after
// ~2 s of continuous hold accelerates to ~10 steps/s. Floor 1 U, hard stop
// 60 U (the store accepts 0–60; the UI floor is deliberately 1 so a save can
// never read 0). `insulin_type` is filled from the per-kind Settings defaults
// at save time — the sheet never asks for the product name (App 5).
@Observable
@MainActor
final class InsulinDoseModel {
    static let minUnits = 1
    static let maxUnits = 60

    var units = 10
    var kind: InsulinKind = .bolus
    // Administration time; the compact back-dating control writes here and the
    // saved event carries it (UTC ms conversion happens in the store).
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let store: any PersistenceStore
    private var holdTask: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    enum StepDirection {
        case up, down
    }

    // MARK: - Stepping (App 3)

    func step(_ direction: StepDirection) {
        let delta = direction == .up ? 1 : -1
        units = min(max(units + delta, Self.minUnits), Self.maxUnits)
    }

    // Press-down: step once immediately (so a plain tap is ±1 U), then repeat
    // on the `repeatSteps(afterHold:)` schedule until `endHold()`. The task
    // polls rather than sleeping per-step so the pure schedule function stays
    // the single source of timing truth.
    func beginHold(_ direction: StepDirection) {
        endHold()
        step(direction)
        holdTask = Task { [weak self] in
            let start = Date()
            var fired = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled else { return }
                let due = Self.repeatSteps(afterHold: Date().timeIntervalSince(start))
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

    // Pure timing seam: how many REPEAT steps (beyond the initial press-down
    // step) are due after `elapsed` seconds of continuous hold. Repeats start
    // after a short delay so a quick tap stays exactly one step, run at
    // ~4 steps/s, and accelerate to ~10 steps/s after ~2 s so any value in
    // 1–60 is reachable within a few seconds.
    nonisolated static func repeatSteps(afterHold elapsed: TimeInterval) -> Int {
        let initialDelay = 0.4
        let slowRate = 4.0
        let fastRate = 10.0
        let accelerateAfter = 2.0
        guard elapsed >= initialDelay else { return 0 }
        if elapsed < accelerateAfter {
            return 1 + Int((elapsed - initialDelay) * slowRate)
        }
        let slowSteps = 1 + Int((accelerateAfter - initialDelay) * slowRate)
        return slowSteps + Int((elapsed - accelerateAfter) * fastRate)
    }

    // MARK: - Save (App 2)

    // One-tap save: writes the dose through the core API and returns true on
    // success so the view can dismiss. The Graph refreshes itself via the
    // store's `eventsDidChange` tick — no manual reload.
    func save() async -> Bool {
        endHold()
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let dose = InsulinDose(
            timestamp: timestamp,
            units: Double(units),
            kind: kind,
            insulinType: Self.insulinType(for: kind)
        )
        do {
            try await store.saveInsulinDose(dose)
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    // Per-kind product string from Settings (App 5), falling back to the
    // shipped defaults when the Settings field is unset or cleared.
    private static func insulinType(for kind: InsulinKind) -> String {
        let key: String
        let fallback: String
        switch kind {
        case .bolus:
            key = SettingsKeys.insulinTypeBolus
            fallback = SettingsKeys.insulinTypeBolusDefault
        case .basal:
            key = SettingsKeys.insulinTypeBasal
            fallback = SettingsKeys.insulinTypeBasalDefault
        }
        let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? fallback : stored
    }
}
