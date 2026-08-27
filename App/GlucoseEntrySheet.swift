import Persistence
import SwiftUI

// The glucose entry surface (specs/data/fingerprick-glucose Req 2).
//
// Deliberately NOT a fourth mode of `LogSheet`, which is otherwise where a new
// manual-entry surface belongs. The other three modes share a shape — name a
// kind, give a quantity, say when — and share the chrome that follows from it.
// This one has no kind to name and, more decisively, opens with the keypad
// already up: it is a keyboard-first surface at the large detent, where the
// other three are fixed-height compositions at the medium one. Folding it in
// would have meant `LogSheet` presenting at two different heights depending on
// mode. `specs/data/fingerprick-glucose/design.md` names it as its own file.
//
// Req 2.3's four-interaction budget is the whole design. The pad takes digits
// from the right with an implicit tenths place — `1`, `2`, `1` is 12.1 — so no
// value in 1.0-30.0 costs more than three digits plus Save. See
// `GlucoseEntryModel` for the rule; this file is the layout over it.
struct GlucoseEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: GlucoseEntryModel
    @FocusState private var padFocused: Bool

    init(store: any PersistenceStore) {
        _model = State(initialValue: GlucoseEntryModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                pad
                EntryTimeRow(timestamp: $model.timestamp, identifier: "glucose.time")
                EntrySaveButton(
                    title: model.canSave ? "Save \(model.displayValue) mmol/L" : "Save",
                    isSaving: model.isSaving,
                    isEnabled: model.canSave,
                    identifier: "glucose.save"
                ) {
                    Task { if await model.save() { dismiss() } }
                }
                if let saveError = model.saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.surfacePrimary)
            .navigationTitle("Blood glucose")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Large, not medium. The numeric keypad claims roughly the bottom
        // two-fifths of the screen and SwiftUI insets the sheet's content by
        // it, so at the medium detent the numeral, the time row and the Save
        // button would be squeezed into what is left of half a screen.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // A focus request made in the same run loop as the sheet's
            // presentation is dropped — the field is not in the hierarchy yet
            // — and the keypad then needs a tap, which is the interaction
            // Req 2.3's budget cannot spare. One hop after presentation is
            // enough.
            try? await Task.sleep(for: .milliseconds(60))
            padFocused = true
        }
    }

    // The numeral IS the field. A separate visible text field would put a
    // second number on the screen and make the implicit decimal point a thing
    // to reconcile between them; instead the field is laid underneath at full
    // size with clear text and a clear caret, so it takes the keystrokes and
    // the tap target while the formatted value is what is drawn.
    private var pad: some View {
        VStack(spacing: 4) {
            ZStack {
                TextField("", text: digitsBinding)
                    .keyboardType(.numberPad)
                    .focused($padFocused)
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accessibilityLabel("Blood glucose in millimoles per litre")
                    .accessibilityValue(model.displayValue)
                    .accessibilityIdentifier("glucose.pad")
                // Formatted live, so the decimal point the developer never
                // types is visible rather than remembered.
                Text(model.displayValue)
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(model.canSave ? Color.textPrimary : Color.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: model.mmolL)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Text("mmol/L")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // Raw digits in, filtered digits out. The keypad's delete key simply hands
    // back a shorter string, so backspace needs no case of its own.
    private var digitsBinding: Binding<String> {
        Binding(get: { model.digits }, set: { model.setDigits($0) })
    }
}
