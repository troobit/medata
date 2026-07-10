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
                Section("Recent") {
                    ForEach(model.recentEntries, id: \.id) { entry in
                        entryRow(entry)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surfacePrimary)
            .navigationTitle("Intake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseCoverButton { dismiss() }
                }
            }
        }
        .task { await model.start() }
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
    private func presetButton(_ preset: QuickPreset) -> some View {
        Button {
            Task { await model.tapPreset(preset) }
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
            HStack {
                Image(systemName: "carrot")
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(entry.carbsG.rounded())) g")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text(entryTimeString(entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if let macros = macroSummary(entry.macros) {
                        Text(macros)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
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

private func entryTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IE")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
