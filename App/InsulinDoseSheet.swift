import Persistence
import SwiftUI

// The insulin mode of `LogSheet` (PRD regression-suggestion-integration App
// 1–5). Opens pre-filled with 10 U bolus now — or with a suggested value when
// one was armed (specs/data/insulin-dosing Req 6.4) — so the common case is
// exactly two taps: syringe → Save. The dose is a large numeral flanked by big
// +/− controls (tap = 1 U; hold repeats, accelerating after ~2 s — timing
// lives in `InsulinDoseModel`). The bolus/basal toggle and the compact
// back-dating control sit off the happy path: neither needs touching for the
// default save. No product-name field — `insulin_type` comes from the per-kind
// Settings defaults (App 5).
//
// Chrome (title, detent, dismissal) belongs to `LogSheet`; this is the
// quantity control and nothing else.
struct InsulinDoseContent: View {
    @Bindable var model: InsulinDoseModel
    let onSaved: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            kindPicker
            stepper
            EntryTimeRow(timestamp: $model.timestamp, identifier: "insulin.time")
            EntrySaveButton(
                title: "Save \(model.units) U \(model.kind == .bolus ? "bolus" : "basal")",
                isSaving: model.isSaving,
                isEnabled: true,
                identifier: "insulin.save"
            ) {
                Task { if await model.save() { onSaved() } }
            }
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onChange(of: model.kind) { model.consumeSeedCaption() }
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

    // MARK: - Dose stepper (App 3)

    private var stepper: some View {
        HStack(spacing: 28) {
            stepControl("minus", direction: .down, identifier: "insulin.minus")
            VStack(spacing: 0) {
                Text("\(model.units)")
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: model.units)
                    .accessibilityIdentifier("insulin.units")
                // One slot, two states. While a seeded value is untouched the
                // caption names where the number came from — the carbohydrate
                // figure is not on this screen, so the sheet restates it. The
                // first press of either step control replaces it with the
                // plain unit label, permanently for this presentation, so the
                // screen can never describe a number as derived once a human
                // has overridden it. Same font in both states: the slot must
                // not change height on the swap.
                Text(model.unitsCaption)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("insulin.caption")
            }
            .frame(minWidth: 120)
            stepControl("plus", direction: .up, identifier: "insulin.plus")
        }
        .frame(maxWidth: .infinity)
    }

    // Press-down steps once (a plain tap = ±1 U); keeping the finger down
    // hands over to the model's repeat schedule. `minimumDuration: .infinity`
    // means the gesture never "performs" — only the pressing callback drives
    // the model, so tap and hold share one code path.
    private func stepControl(
        _ symbol: String, direction: InsulinDoseModel.StepDirection, identifier: String
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 68, height: 68)
            .background(Color.surfaceElevated, in: Circle())
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: .infinity) {
            } onPressingChanged: { pressing in
                if pressing {
                    model.beginHold(direction)
                } else {
                    model.endHold()
                }
            }
            .accessibilityLabel(direction == .up ? "Increase dose" : "Decrease dose")
            .accessibilityIdentifier(identifier)
    }
}
