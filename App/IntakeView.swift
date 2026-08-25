import Persistence
import SwiftUI

// The Intake surface (specs/data/manual-carb-intake Req 3, 4, 5, 7) —
// replaces the home-router Decision 12 compile placeholder wholesale.
// Presented as a full-screen cover from AppRoot's `ActiveSheet.intake`, so it
// keeps the standard NavigationStack + CloseCoverButton shell. Hosts:
// - "Enter amount" opening the carb-entry sheet (Req 5.1),
// - the quick-add grid — one button per preset, tap writes instantly
//   (Req 3.1/3.2); context menu edits/deletes a preset and a trailing plus
//   tile creates one (Req 4.1/4.2),
// - the recent-entries list — swipe-delete, tap-to-edit inline (Req 7.1/7.5).
struct IntakeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DoseSuggestionModel.self) private var doseSuggestions: DoseSuggestionModel?
    @State private var model: IntakeModel
    @State private var activeSheet: IntakeSheet?

    private let store: any PersistenceStore

    init(store: any PersistenceStore) {
        self.store = store
        _model = State(initialValue: IntakeModel(store: store))
    }

    // One optional drives all four sheets so they are mutually exclusive by
    // construction (AppRoot's ActiveSheet idiom).
    private enum IntakeSheet: Identifiable {
        case newEntry
        case editEntry(IntakeEntry)
        case newPreset
        case editPreset(QuickPreset)

        var id: String {
            switch self {
            case .newEntry: "newEntry"
            case .editEntry(let entry): entry.id.uuidString
            case .newPreset: "newPreset"
            case .editPreset(let preset): preset.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    enterAmountButton
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    presetGrid
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if !model.recentEntries.isEmpty {
                    Section("Recent") {
                        ForEach(model.recentEntries, id: \.id) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surfacePrimary)
            // Deliberately untitled (snaqui Req 4).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseCoverButton { dismiss() }
                }
            }
        }
        .task { await model.start() }
        // The cover is dismissed, not deallocated straight away — tear the
        // eventsDidChange subscription down explicitly.
        .onDisappear { model.cancel() }
        // Success haptic for the one-tap quick-add (ShutterButton's
        // sensoryFeedback pattern); failed writes never bump the trigger.
        .sensoryFeedback(.success, trigger: model.quickAddSuccessCount)
        // Presets emit no change notification, so any sheet dismissal reloads
        // them (create/edit arrive only through these sheets); entry changes
        // refresh via the model's `eventsDidChange` subscription.
        .sheet(item: $activeSheet, onDismiss: {
            Task { await model.reloadPresets() }
        }) { sheet in
            switch sheet {
            case .newEntry:
                CarbEntrySheet(store: store, nextSortOrder: model.nextSortOrder)
            case .editEntry(let entry):
                CarbEntrySheet(store: store, editing: entry)
            case .newPreset:
                QuickPresetEditSheet(
                    store: store,
                    preset: QuickPreset(name: "", carbsG: 0, sortOrder: model.nextSortOrder),
                    isNew: true
                )
            case .editPreset(let preset):
                QuickPresetEditSheet(store: store, preset: preset, isNew: false)
            }
        }
    }

    // MARK: - Manual entry (Req 5.1)

    private var enterAmountButton: some View {
        Button {
            activeSheet = .newEntry
        } label: {
            Label("Enter amount", systemImage: "plus.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.captureBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.medataAccent)
        .accessibilityIdentifier("intake.enterAmount")
    }

    // MARK: - Quick-add grid (Req 3.1, 3.2, 4.1, 4.2)

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(model.presets) { preset in
                presetButton(preset)
            }
            addPresetButton
        }
    }

    // One tap writes the preset straight to the ledger (Req 3.2 — no sheet,
    // no confirmation). Edit/delete live on the long-press context menu
    // (Req 4.2). Sizing/contentShape stay INSIDE the label (Button gotcha).
    // The tile is disabled and dimmed while its write is in flight so a
    // double-tap cannot write two rows.
    private func presetSubject(_ preset: QuickPreset) -> DoseSubject {
        DoseSubject(
            carbsG: preset.carbsG,
            instant: Date(),
            source: .quickPreset,
            sourceEventID: nil,
            fatG: preset.macros.fatG,
            proteinG: preset.macros.proteinG,
            sigmaMeal: nil,
            fatStale: false
        )
    }

    private func presetButton(_ preset: QuickPreset) -> some View {
        let isSaving = model.savingPresetID == preset.id
        return Button {
            Task {
                await model.tapPreset(preset)
                // A preset tap shows NOTHING (specs/data/insulin-dosing
                // Req 6.6): a second number on a tile whose whole label is a
                // carbohydrate figure would rewrite the control and blunt its
                // one job. The suggestion still reaches the developer one tap
                // later, as the dose sheet's opening value.
                await doseSuggestions?.arm(from: presetSubject(preset))
            }
        } label: {
            VStack(spacing: 2) {
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(Int(preset.carbsG.rounded())) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .opacity(isSaving ? 0.4 : 1)
        .contextMenu {
            Button("Edit") { activeSheet = .editPreset(preset) }
            Button("Delete", role: .destructive) {
                Task { await model.deletePreset(preset) }
            }
        }
        .accessibilityIdentifier("intake.preset")
    }

    private var addPresetButton: some View {
        Button {
            activeSheet = .newPreset
        } label: {
            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.separatorSubtle, style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add quick-add preset")
        .accessibilityIdentifier("intake.addPreset")
    }

    // MARK: - Recent entries (Req 7.1, 7.5)

    // Tap opens the same carb-entry sheet pre-filled for edit (Req 7.2, 7.5 —
    // no intermediate screens); swipe deletes without confirmation
    // (RecordsView pattern).
    private func entryRow(_ entry: IntakeEntry) -> some View {
        Button {
            activeSheet = .editEntry(entry)
        } label: {
            TimelineRow(glyph: "carrot", glyphTint: Color.textSecondary, timestamp: entry.timestamp) {
                Text("\(Int(entry.carbsG.rounded())) g")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            } footer: {
                if let macros = macroSummary(entry.macros) {
                    Text(macros)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.delete(entry) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("intake.row.entry")
    }

    // Captured macros only — absent macros render nothing (Req 2.3/2.4).
    private func macroSummary(_ macros: IntakeMacros) -> String? {
        var parts: [String] = []
        if let protein = macros.proteinG { parts.append("Protein \(Int(protein.rounded())) g") }
        if let fat = macros.fatG { parts.append("Fat \(Int(fat.rounded())) g") }
        if let fibre = macros.fibreG { parts.append("Fibre \(Int(fibre.rounded())) g") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

