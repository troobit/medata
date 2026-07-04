import Persistence
import SwiftUI

// The insulin dose-entry sheet (PRD regression-suggestion-integration App
// 1–5). Presented as a plain sheet from the Graph so it feels lighter than
// the Capture/Data/Settings covers. Opens pre-filled with 10 U bolus now, so
// the common case is exactly two taps: syringe → Save. The dose is a large
// numeral flanked by big +/− controls (tap = 1 U; hold repeats, accelerating
// after ~2 s — timing lives in `InsulinDoseModel`). The bolus/basal toggle
// and the compact back-dating control sit off the happy path: neither needs
// touching for the default save. No product-name field — `insulin_type`
// comes from the per-kind Settings defaults (App 5).
struct InsulinDoseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: InsulinDoseModel

    init(store: any PersistenceStore) {
        _model = State(initialValue: InsulinDoseModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                kindPicker
                stepper
                timeRow
                saveButton
                if let saveError = model.saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.surfacePrimary)
            .navigationTitle("Insulin")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
                Text("units")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
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

    // Compact back-dating control (App 4) — a forgotten dose is logged at its
    // real administration time; the default stays "now" on the happy path.
    private var timeRow: some View {
        DatePicker(
            "Time",
            selection: $model.timestamp,
            in: ...Date(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .environment(\.locale, Locale(identifier: "en_IE"))
        .accessibilityIdentifier("insulin.time")
    }

    private var saveButton: some View {
        Button {
            Task {
                if await model.save() { dismiss() }
            }
        } label: {
            if model.isSaving {
                MedataLoadingSymbol(mode: .loop, size: 22)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Save \(model.units) U \(model.kind == .bolus ? "bolus" : "basal")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.medataAccent)
        .foregroundStyle(Color.captureBackground)
        .disabled(model.isSaving)
        .accessibilityIdentifier("insulin.save")
    }
}
