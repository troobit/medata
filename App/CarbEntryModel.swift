import Foundation
import Observation
import Persistence

// View-model for the carb-entry sheet (specs/data/manual-carb-intake Req 1, 2,
// 7.2). Follows the InsulinDoseModel split: the sheet is composition only, all
// behaviour lives here. One model serves both "new entry" and "edit entry" —
// an `editing: IntakeEntry?` init param switches save() between
// `saveIntakeEntry` (source .manual) and `updateIntakeEntry` (same row id,
// original source/presetID preserved).
@Observable
@MainActor
final class CarbEntryModel {
    static let minCarbs = 1
    static let maxCarbs = 999

    // Carb amount as keypad text (Req 1.1: 1–999 g is two orders of magnitude
    // too wide for the insulin stepper). The view routes edits through
    // `clampCarbsText()` so the field never holds a value above 999 (Req 1.4);
    // the 1 g floor is enforced by `canSave`, not by rewriting the text.
    var carbsText = ""
    // Optional macro fields (Req 2.2). Empty text means the macro is absent —
    // it maps to `nil` in IntakeMacros, never 0 (Req 2.3).
    var proteinText = ""
    var fatText = ""
    var fibreText = ""
    // Disclosure state (Req 2.1, 2.4): collapsed for a new entry; expanded
    // when editing an entry that already carries any macro, so captured
    // macros are visible on open.
    var macrosExpanded = false
    // Entry time (Req 1.2): defaults to now, back-dateable; the DatePicker's
    // `...Date()` range forbids future dates.
    var timestamp = Date()
    private(set) var isSaving = false
    // One-way latch: set when a save commits. The save-as-quick-add path
    // keeps the sheet open while the preset sheet animates in, and
    // `isSaving` re-enables after the write — without the latch both save
    // buttons become tappable again in that window and a second tap writes
    // a duplicate ledger row.
    private(set) var didSave = false
    private(set) var saveError: String?

    let editing: IntakeEntry?
    // Exposed so the "save as quick-add" sub-sheet can be built beside this
    // model rather than threading the store through the content view twice.
    let store: any PersistenceStore

    init(store: any PersistenceStore, editing: IntakeEntry? = nil) {
        self.store = store
        self.editing = editing
        if let editing {
            carbsText = String(Int(editing.carbsG.rounded()))
            proteinText = Self.macroText(editing.macros.proteinG)
            fatText = Self.macroText(editing.macros.fatG)
            fibreText = Self.macroText(editing.macros.fibreG)
            macrosExpanded = editing.macros != IntakeMacros()
            timestamp = editing.timestamp
        }
    }

    var carbs: Int? { Int(carbsText) }

    // Save is available only from 1 g (Req 1.4); the ceiling is held by the
    // text clamp so `carbs` can never read above 999.
    var canSave: Bool { (carbs ?? 0) >= Self.minCarbs && !isSaving && !didSave }

    // Called from the view's onChange: strips non-digits (hardware keyboards
    // bypass the number pad) and clamps at 999 (Req 1.4).
    func clampCarbsText() {
        let text = Self.clampedDigits(carbsText)
        if text != carbsText { carbsText = text }
    }

    // Shared sanitiser for every gram-valued keypad field (carbs and macros,
    // here and in QuickPresetEditSheet): strips non-digits so pasted text
    // like "abc"/"-5"/"1e6" cannot persist garbage, caps at 3 digits, and
    // round-trips through Int so leading zeros normalise ("099" → "99").
    static func clampedDigits(_ text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(3))
        guard let value = Int(digits) else { return "" }
        return String(min(value, maxCarbs))
    }

    // Macro fields decode only when non-empty (Req 2.3): `Double(text)` is
    // never read from empty text, so an untouched field stays absent.
    var macros: IntakeMacros {
        IntakeMacros(
            proteinG: Self.macroValue(proteinText),
            fatG: Self.macroValue(fatText),
            fibreG: Self.macroValue(fibreText)
        )
    }

    // Writes (new) or updates (editing) the entry through the store; returns
    // true on success so the view can dismiss (Req 1.3, 7.2). Dependent views
    // refresh via `eventsDidChange` — no manual reload.
    func save() async -> Bool {
        guard let carbs, carbs >= Self.minCarbs else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if let editing {
                let updated = IntakeEntry(
                    id: editing.id,
                    timestamp: timestamp,
                    carbsG: Double(carbs),
                    subtype: editing.subtype,
                    macros: macros,
                    source: editing.source,
                    presetID: editing.presetID
                )
                try await store.updateIntakeEntry(updated)
            } else {
                let entry = IntakeEntry(
                    timestamp: timestamp,
                    carbsG: Double(carbs),
                    macros: macros,
                    source: .manual
                )
                try await store.saveIntakeEntry(entry)
            }
            didSave = true
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private static func macroValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private static func macroText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(Int(value.rounded()))
    }
}
