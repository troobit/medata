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
    // Carried through untouched on save (manual-carb-intake Req 8.9): the
    // sheet reconstructs the QuickPreset, so an edit would otherwise silently
    // drop the capture-origin stamp.
    private let sourceMealID: UUID?
    private let isNew: Bool

    init(store: any PersistenceStore, preset: QuickPreset, isNew: Bool) {
        self.store = store
        self.presetID = preset.id
        self.sortOrder = preset.sortOrder
        self.sourceMealID = preset.sourceMealID
        self.isNew = isNew
        _name = State(initialValue: preset.name)
        _carbsText = State(initialValue: preset.carbsG >= 1 ? String(Int(preset.carbsG.rounded())) : "")
        _proteinText = State(initialValue: CarbEntryModel.macroText(preset.macros.proteinG))
        _fatText = State(initialValue: CarbEntryModel.macroText(preset.macros.fatG))
        _fibreText = State(initialValue: CarbEntryModel.macroText(preset.macros.fibreG))
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
                    if let saveError = saveError {
                        EntrySaveError(message: saveError)
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
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: Metrics.cornerChip))
            .accessibilityIdentifier("preset.name")
    }

    // Shared field bodies (specs/ui/shared-meal-components Req 2): the same
    // CarbAmountField / MacroDisclosure the entry surface renders, with this
    // sheet's accessibility ids; the commit button is the shared EntryChrome
    // treatment (Req 2.3).
    private var carbField: some View {
        CarbAmountField(text: $carbsText, identifier: "preset.amount")
    }

    private var macroDisclosure: some View {
        MacroDisclosure(
            isExpanded: $macrosExpanded,
            protein: $proteinText,
            fat: $fatText,
            fibre: $fibreText,
            idPrefix: "preset"
        )
    }

    private var saveButton: some View {
        EntrySaveButton(
            title: "Save preset",
            isSaving: isSaving,
            isEnabled: canSave,
            identifier: "preset.save"
        ) {
            Task { await save() }
        }
    }

    // Empty macro text stays absent, never 0 (Req 2.3 applies to presets too).
    // The guard re-checks the 1 g floor: presets have no store-side range
    // validation, so this is the only backstop against a sub-floor write.
    private func save() async {
        guard let carbs, carbs >= CarbEntryModel.minCarbs else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let preset = QuickPreset(
            id: presetID,
            name: trimmedName,
            carbsG: Double(carbs),
            macros: IntakeMacros(
                proteinG: CarbEntryModel.macroValue(proteinText),
                fatG: CarbEntryModel.macroValue(fatText),
                fibreG: CarbEntryModel.macroValue(fibreText)
            ),
            sortOrder: sortOrder,
            sourceMealID: sourceMealID
        )
        do {
            try await store.saveQuickPreset(preset)
            dismiss()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
