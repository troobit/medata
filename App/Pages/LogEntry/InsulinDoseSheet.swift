import Persistence
import SwiftUI

// The insulin mode of `LogSheet` (PRD regression-suggestion-integration App
// 1–5). Opens pre-filled — at an armed suggestion, else this kind's remembered
// value, else 10 U — so the common case is exactly two taps: syringe → Save.
//
// The dose is TYPED on the shared keypad (specs/ui/unified-entry-sheet Req 1),
// the same control the glucose mode holds. The `+`/`−` circles and their
// hold-acceleration are deleted: a relative control cannot share a value with
// a digit buffer without the two disagreeing (Decision 1). What replaces the
// nudge is a row of chips that set the value absolutely (Req 1.5).
//
// The bolus/basal picker is now load-bearing rather than incidental — it
// selects which remembered value applies. The compact back-dating control
// still sits off the happy path. No product-name field — `insulin_type` comes
// from the per-kind Settings defaults (App 5).
//
// Chrome (title, detent, dismissal) belongs to `LogSheet`; this is the
// quantity control and nothing else.
struct InsulinDoseContent: View {
    @Bindable var model: InsulinDoseModel
    let onSaved: () -> Void
    @FocusState.Binding var padFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            kindPicker
            pad
            chips
            EntryTimeRow(timestamp: $model.timestamp, identifier: "insulin.time")
            EntrySaveButton(
                title: "Save \(model.units) U \(model.kind == .bolus ? "bolus" : "basal")",
                isSaving: model.isSaving,
                isEnabled: model.canSave,
                identifier: "insulin.save"
            ) {
                Task { if await model.save() { onSaved() } }
            }
            EntrySaveError(message: model.saveError)
            Spacer(minLength: 0)
        }
        .padding(20)
        // A kind change reloads that kind's opening value WITH its caption
        // (Req 3.5), so the caption is not consumed here — the model owns it.
        .onChange(of: model.timestamp) { model.consumeSeedCaption() }
    }

    // Bolus default; switching kind preserves the chosen units (App 4).
    private var kindPicker: some View {
        Picker("Kind", selection: $model.kind) {
            Text("Bolus").tag(InsulinKind.bolus)
            Text("Basal").tag(InsulinKind.basal)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("insulin.kind")
    }

    // MARK: - Quantity

    private var pad: some View {
        VStack(spacing: 4) {
            NumericEntryPad(
                digits: Binding(get: { model.entry.digits }, set: { model.setDigits($0) }),
                displayValue: "\(model.units)",
                isComplete: model.canSave,
                unitLabel: model.unitsCaption,
                accessibilityLabel: "Insulin dose in units",
                identifier: "insulin.pad",
                focused: $padFocused
            )
        }
    }

    // One tap to a named value. Absent when there is nothing to name — a chip
    // repeating the number already on screen is noise, which is why the model
    // filters those out rather than the view.
    private var chips: some View {
        ChipFlow(spacing: 8, lineSpacing: 8) {
            ForEach(model.chips, id: \.title) { chip in
                EntryChip(
                    title: chip.title,
                    isActive: false,
                    identifier: "insulin.chip.\(chip.units)"
                ) {
                    model.apply(units: chip.units)
                }
            }
        }
    }
}
