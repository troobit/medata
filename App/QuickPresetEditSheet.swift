import Persistence
import SwiftUI

// Create or edit one quick-add preset (specs/data/manual-carb-intake Req 4.1,
// 4.2, 4.4). Same field set as CarbEntrySheet minus the timestamp, plus the
// name — presented as the same plain medium-detent sheet. The caller supplies
// the full `QuickPreset` value: an existing preset for edit, or a fresh one
// (blank or pre-filled from a just-saved entry, with the next sortOrder) for
// create — `saveQuickPreset` is insert-or-replace by id, so one save path
// covers both. Duplicate names are allowed (Decision 6, no collision UI).
// Small enough to hold its state locally — no separate model file.
struct QuickPresetEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var fibreText: String
    @State private var macrosExpanded: Bool
    @State private var isSaving = false
    @State private var saveError: String?

    private let store: any PersistenceStore
    private let presetID: UUID
    private let sortOrder: Int
    private let isNew: Bool

    init(store: any PersistenceStore, preset: QuickPreset, isNew: Bool) {
        self.store = store
        self.presetID = preset.id
        self.sortOrder = preset.sortOrder
        self.isNew = isNew
        _name = State(initialValue: preset.name)
        _carbsText = State(initialValue: preset.carbsG >= 1 ? String(Int(preset.carbsG.rounded())) : "")
        _proteinText = State(initialValue: Self.macroText(preset.macros.proteinG))
        _fatText = State(initialValue: Self.macroText(preset.macros.fatG))
        _fibreText = State(initialValue: Self.macroText(preset.macros.fibreG))
        _macrosExpanded = State(initialValue: preset.macros != IntakeMacros())
    }

    private var carbs: Int? { Int(carbsText) }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // A preset needs a name and a carb value in the same 1–999 g range as a
    // manual entry (Req 4.1).
    private var canSave: Bool {
        !trimmedName.isEmpty && (carbs ?? 0) >= CarbEntryModel.minCarbs && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    nameField
                    carbField
                    macroDisclosure
                    saveButton
                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color.surfacePrimary)
            .navigationTitle(isNew ? "New quick-add" : "Edit quick-add")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var nameField: some View {
        TextField("Name", text: $name)
            .font(.headline)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("preset.name")
    }

    private var carbField: some View {
        VStack(spacing: 0) {
            TextField("0", text: $carbsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .onChange(of: carbsText) { clampCarbsText() }
                .accessibilityLabel("Carbohydrates in grams")
                .accessibilityIdentifier("preset.amount")
            Text("grams")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var macroDisclosure: some View {
        DisclosureGroup(isExpanded: $macrosExpanded) {
            VStack(spacing: 8) {
                macroRow("Protein", text: $proteinText, identifier: "preset.protein")
                macroRow("Fat", text: $fatText, identifier: "preset.fat")
                macroRow("Fibre", text: $fibreText, identifier: "preset.fibre")
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

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                MedataLoadingSymbol(mode: .loop, size: 22)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Save preset")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.medataAccent)
        .foregroundStyle(Color.captureBackground)
        .disabled(!canSave)
        .accessibilityIdentifier("preset.save")
    }

    private func clampCarbsText() {
        var text = String(carbsText.filter(\.isNumber).prefix(3))
        if let value = Int(text), value > CarbEntryModel.maxCarbs {
            text = String(CarbEntryModel.maxCarbs)
        }
        if text != carbsText { carbsText = text }
    }

    // Empty macro text stays absent, never 0 (Req 2.3 applies to presets too).
    private func save() async {
        guard let carbs else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let preset = QuickPreset(
            id: presetID,
            name: trimmedName,
            carbsG: Double(carbs),
            macros: IntakeMacros(
                proteinG: Self.macroValue(proteinText),
                fatG: Self.macroValue(fatText),
                fibreG: Self.macroValue(fibreText)
            ),
            sortOrder: sortOrder
        )
        do {
            try await store.saveQuickPreset(preset)
            dismiss()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
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
