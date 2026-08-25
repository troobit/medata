import Persistence
import SwiftUI

// The carbohydrate mode of `LogSheet` (specs/data/manual-carb-intake Req 1, 2,
// 4.4, 7.2). The amount is a numeric-keypad field rather than a stepper
// (Req 1.1 — 1–999 g is two orders of magnitude too wide for ±1 taps), and the
// optional macros sit behind a DisclosureGroup (Req 2.1).
//
// This is the mode that fits the unified grammar least well, and the code
// shows it: there is no kind slot to fill (only `.carb` ships), the quantity
// is unbounded text rather than a bounded stepper, the macros disclosure can
// outgrow the medium detent so this mode keeps its own ScrollView, and it
// carries a second, non-committing action ("Save as quick-add") that neither
// other mode has. It is included anyway because the chrome — the back-dating
// row, the accent commit, the detent, the dismissal — really is the same job.
struct CarbEntryContent: View {
    @Bindable var model: CarbEntryModel
    let nextSortOrder: Int
    let onFinished: () -> Void

    // Optional so any surface can host this content without the app-level
    // model; absent simply means no suggestion segment.
    @Environment(DoseSuggestionModel.self) private var doseSuggestions: DoseSuggestionModel?

    // "Save as quick-add" (Req 4.4): the entry save is already committed when
    // this sub-sheet opens; cancelling it creates no preset and rolls back
    // nothing, so its dismissal always closes the entry sheet too. While it is
    // up the entry sheet stays visible underneath — the model's `didSave`
    // latch keeps both save buttons dead so no second row can be written.
    @State private var showingPresetSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                carbField
                EntryTimeRow(timestamp: $model.timestamp, identifier: "carb.time")
                macroDisclosure
                EntrySaveButton(
                    title: saveLabel,
                    isSaving: model.isSaving,
                    isEnabled: model.canSave,
                    identifier: "carb.save"
                ) {
                    Task {
                        if await model.save() {
                            await armSuggestion()
                            onFinished()
                        }
                    }
                }
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
        // Recomputed as the amount and the time change, so the figure on
        // screen is always the one this save would produce.
        .task(id: suggestionKey) { await refreshSuggestion() }
        .onDisappear { doseSuggestions?.clear() }
        .sheet(isPresented: $showingPresetSheet, onDismiss: { onFinished() }) {
            QuickPresetEditSheet(
                store: model.store,
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
        // The secondary line takes the same middle-dot segment the meal
        // review screen uses, in the same derived register: a quantity and
        // a unit symbol, no verb, no qualifier. A suppressed suggestion is
        // an absent segment, not a placeholder.
        CarbAmountField(text: $model.carbsText, identifier: "carb.amount") {
            if let readout = doseSuggestions?.readout {
                (
                    Text(" · ").foregroundStyle(Color.textSecondary.opacity(0.45))
                        + Text(readout.unitsLabel).fontWeight(.semibold)
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .contentTransition(.numericText())
                .animation(.smooth, value: readout)
                .accessibilityIdentifier("carb.doseSuggestion")
            }
        }
    }

    // MARK: - Macros (Req 2.1–2.3)

    private var macroDisclosure: some View {
        MacroDisclosure(
            isExpanded: $model.macrosExpanded,
            protein: $model.proteinText,
            fat: $model.fatText,
            fibre: $model.fibreText,
            idPrefix: "carb"
        )
    }

    // MARK: - Save (Req 1.3, 1.4)

    // Plain "Save" until a saveable value exists — "Save 0 g" reads as a
    // savable zero when it is neither.
    private var saveLabel: String {
        guard let carbs = model.carbs, carbs >= CarbEntryModel.minCarbs else { return "Save" }
        return "Save \(carbs) g"
    }

    // Secondary action (Req 4.4): commits the entry save first, then prompts
    // for a preset name pre-filled with the just-entered values.
    private var saveAsQuickAddButton: some View {
        Button {
            Task {
                if await model.save() {
                    await armSuggestion()
                    showingPresetSheet = true
                }
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

    // MARK: - Dose suggestion (insulin-dosing Req 6.5)

    private var suggestionKey: String { "\(model.carbs ?? 0)-\(model.timestamp.timeIntervalSince1970)" }

    private var subject: DoseSubject? {
        guard let carbs = model.carbs, carbs >= CarbEntryModel.minCarbs else { return nil }
        return DoseSubject(
            carbsG: Double(carbs),
            instant: model.timestamp,
            source: .intake,
            sourceEventID: model.editing?.id,
            fatG: model.macros.fatG,
            proteinG: model.macros.proteinG,
            sigmaMeal: nil
        )
    }

    private func refreshSuggestion() async {
        guard let subject else {
            doseSuggestions?.clear()
            return
        }
        await doseSuggestions?.refresh(for: subject)
    }

    private func armSuggestion() async {
        guard let subject else { return }
        await doseSuggestions?.arm(from: subject)
    }
}

// The edit path keeps its own sheet: `LogSheet` creates rows, and editing an
// existing row is a different job with a different title and no mode to
// switch to. Reusing the content view keeps the two from drifting.
struct CarbEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CarbEntryModel

    private let nextSortOrder: Int

    init(store: any PersistenceStore, editing: IntakeEntry? = nil, nextSortOrder: Int = 0) {
        self.nextSortOrder = nextSortOrder
        _model = State(initialValue: CarbEntryModel(store: store, editing: editing))
    }

    var body: some View {
        NavigationStack {
            CarbEntryContent(
                model: model, nextSortOrder: nextSortOrder, onFinished: { dismiss() }
            )
            .background(Color.surfacePrimary)
            .navigationTitle(model.editing == nil ? "Carbs" : "Edit carbs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Shared carb/macro fields (specs/ui/shared-meal-components Req 2)
//
// One implementation of the 56 pt centred carb keypad field and the macro
// disclosure, consumed by the entry surface above and by QuickPresetEditSheet
// — the two were byte-identical copies. The digits-only 3-digit clamp is
// baked in so pasted junk cannot persist or vanish a typed value on either
// surface.

struct CarbAmountField<SecondaryLine: View>: View {
    @Binding var text: String
    let identifier: String
    @ViewBuilder var secondaryLine: SecondaryLine

    init(
        text: Binding<String>,
        identifier: String,
        @ViewBuilder secondaryLine: () -> SecondaryLine = { EmptyView() }
    ) {
        _text = text
        self.identifier = identifier
        self.secondaryLine = secondaryLine()
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .onChange(of: text) {
                    let clamped = CarbEntryModel.clampedDigits(text)
                    if clamped != text { text = clamped }
                }
                .accessibilityLabel("Carbohydrates in grams")
                .accessibilityIdentifier(identifier)
            HStack(spacing: 0) {
                Text("grams")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                secondaryLine
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MacroDisclosure: View {
    @Binding var isExpanded: Bool
    @Binding var protein: String
    @Binding var fat: String
    @Binding var fibre: String
    let idPrefix: String

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                macroRow("Protein", text: $protein, identifier: "\(idPrefix).protein")
                macroRow("Fat", text: $fat, identifier: "\(idPrefix).fat")
                macroRow("Fibre", text: $fibre, identifier: "\(idPrefix).fibre")
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
                // Same sanitiser as the carb field: digits only, 3-digit cap.
                .onChange(of: text.wrappedValue) {
                    let clamped = CarbEntryModel.clampedDigits(text.wrappedValue)
                    if clamped != text.wrappedValue { text.wrappedValue = clamped }
                }
                .accessibilityIdentifier(identifier)
            Text("g")
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
    }
}
