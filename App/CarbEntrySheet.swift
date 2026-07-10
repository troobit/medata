import Persistence
import SwiftUI

// The manual carb-entry sheet (specs/data/manual-carb-intake Req 1, 2, 4.4,
// 7.2). Mirrors InsulinDoseSheet's presentation: a plain medium-detent sheet,
// drag-dismissable, no CloseCoverButton. The amount is a numeric-keypad field
// rather than a stepper (Req 1.1 — 1–999 g is too wide for ±1 taps), the time
// row reuses the insulin sheet's compact back-dating DatePicker, and the
// optional macros sit behind a DisclosureGroup (Req 2.1). Reused for editing
// via `editing:` (Req 7.2).
struct CarbEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CarbEntryModel
    // "Save as quick-add" (Req 4.4): the entry save is already committed when
    // this sub-sheet opens; cancelling it creates no preset and rolls back
    // nothing, so its dismissal always closes the entry sheet too.
    @State private var showingPresetSheet = false

    private let store: any PersistenceStore
    private let nextSortOrder: Int

    init(store: any PersistenceStore, editing: IntakeEntry? = nil, nextSortOrder: Int = 0) {
        self.store = store
        self.nextSortOrder = nextSortOrder
        _model = State(initialValue: CarbEntryModel(store: store, editing: editing))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    carbField
                    timeRow
                    macroDisclosure
                    saveButton
                    if model.editing == nil {
                        saveAsQuickAddButton
                    }
                    if let saveError = model.saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color.surfacePrimary)
            .navigationTitle(model.editing == nil ? "Carbs" : "Edit carbs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingPresetSheet, onDismiss: { dismiss() }) {
            QuickPresetEditSheet(
                store: store,
                preset: QuickPreset(
                    name: "",
                    carbsG: Double(model.carbs ?? 0),
                    macros: model.macros,
                    sortOrder: nextSortOrder
                ),
                isNew: true
            )
        }
    }

    // MARK: - Amount (Req 1.1, 1.4)

    private var carbField: some View {
        VStack(spacing: 0) {
            TextField("0", text: $model.carbsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .onChange(of: model.carbsText) { model.clampCarbsText() }
                .accessibilityLabel("Carbohydrates in grams")
                .accessibilityIdentifier("carb.amount")
            Text("grams")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Time (Req 1.2) — InsulinDoseSheet.timeRow pattern verbatim

    private var timeRow: some View {
        DatePicker(
            "Time",
            selection: $model.timestamp,
            in: ...Date(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .environment(\.locale, Locale(identifier: "en_IE"))
        .accessibilityIdentifier("carb.time")
    }

    // MARK: - Macros (Req 2.1–2.3)

    private var macroDisclosure: some View {
        DisclosureGroup(isExpanded: $model.macrosExpanded) {
            VStack(spacing: 8) {
                macroRow("Protein", text: $model.proteinText, identifier: "carb.protein")
                macroRow("Fat", text: $model.fatText, identifier: "carb.fat")
                macroRow("Fibre", text: $model.fibreText, identifier: "carb.fibre")
            }
            .padding(.top, 8)
        } label: {
            Text("Macros")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func macroRow(_ title: String, text: Binding<String>, identifier: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .accessibilityIdentifier(identifier)
            Text("g")
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Save (Req 1.3, 1.4)

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
                Text("Save \(model.carbs ?? 0) g")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.medataAccent)
        .foregroundStyle(Color.captureBackground)
        .disabled(!model.canSave)
        .accessibilityIdentifier("carb.save")
    }

    // Secondary action (Req 4.4): commits the entry save first, then prompts
    // for a preset name pre-filled with the just-entered values.
    private var saveAsQuickAddButton: some View {
        Button {
            Task {
                if await model.save() { showingPresetSheet = true }
            }
        } label: {
            Text("Save as quick-add")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .disabled(!model.canSave)
        .accessibilityIdentifier("carb.saveAsQuickAdd")
    }
}
