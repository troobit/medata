import Persistence
import SwiftUI

// The glucose mode of `LogSheet` (specs/data/fingerprick-glucose Req 2).
//
// This was its own sheet until 2026-08-28, and its own header recorded why:
// `LogSheet` was a fixed-height composition at the medium detent while glucose
// is keyboard-first at the large one, so folding it in would have made one
// sheet present at two heights depending on mode. Giving the insulin mode a
// keypad dissolved that — every mode is keypad-first or content-light at
// `.large` now, and the sheet has one height again
// (specs/ui/unified-entry-sheet Decision 3).
//
// Req 2.3's four-interaction budget is still the whole design, and it is why
// the mode menu can never sit on the way in: three digits plus Save spends all
// four. The pad itself is `NumericEntryPad`, shared with the insulin mode; the
// rule that fills it is `DigitEntry`. What is left here is the composition.
//
// Chrome (title, detent, dismissal, focus) belongs to `LogSheet`.
struct GlucoseEntryContent: View {
    @Bindable var model: GlucoseEntryModel
    let onSaved: () -> Void
    @FocusState.Binding var padFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            NumericEntryPad(
                digits: Binding(get: { model.digits }, set: { model.setDigits($0) }),
                displayValue: model.displayValue,
                isComplete: model.canSave,
                unitLabel: "mmol/L",
                accessibilityLabel: "Blood glucose in millimoles per litre",
                identifier: "glucose.pad",
                focused: $padFocused
            )
            EntryTimeRow(timestamp: $model.timestamp, identifier: "glucose.time")
            EntrySaveButton(
                title: model.canSave ? "Save \(model.displayValue) mmol/L" : "Save",
                isSaving: model.isSaving,
                isEnabled: model.canSave,
                identifier: "glucose.save"
            ) {
                Task { if await model.save() { onSaved() } }
            }
            EntrySaveError(message: model.saveError)
            Spacer(minLength: 0)
        }
        .padding(20)
    }
}
