import GlucoseWidgetShared
import Persistence
import PortableContracts
import SwiftUI

// Shared meal-routing plumbing for the Records/Trends/Data sheet stacks
// (home-router design: Architecture > Records replaces Data). Relocated out of
// DataView.swift (Decision 13) so removing that file does not orphan the
// symbols other surfaces still depend on: `mealRouteDestination` (RecordsView,
// TrendsView) and `CloseCoverButton` (RecordsView, TrendsView, SettingsView,
// CaptureFlowView).

// Shared destination builder for the Records and Trends sheet stacks (both key
// `MealRoute`, design: Navigation routes). `.result` is the single meal-detail
// surface (Decision 16 — the separate overview recap is retired, so a
// day/list row lands directly here): its per-food rows carry the adjustment
// surface (serving-adjust PRD, no separate correction screen); Done pops one
// level; delete removes the meal and unwinds to the list.
@MainActor
@ViewBuilder
func mealRouteDestination(
    _ route: MealRoute,
    store: any PersistenceStore,
    path: Binding<[MealRoute]>
) -> some View {
    switch route {
    case .result(let record):
        ResultView(
            record: record,
            store: store,
            onDone: { popOne(path) },
            onDelete: {
                Task { try? await store.deleteMeal(id: record.id) }
                path.wrappedValue.removeAll()
            }
        )
    }
}

@MainActor
private func popOne(_ path: Binding<[MealRoute]>) {
    if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() }
}

// Shared close control for the full-screen Records / Trends / Settings / Capture
// covers (Decision 19). Covers have no drag-to-dismiss, so each surface's
// toolbar carries this xmark button. Accessibility label `Close` per the copy
// inventory.
struct CloseCoverButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("cover.close")
    }
}

// One row on the unified Records timeline (design: Components and Interfaces).
// Open enum: `.intake(IntakeRecord)` is `manual-carb-intake`'s single additive
// case (Track C) — the taxonomy of intake subtypes (carb, alcohol, …) lives
// inside `IntakeRecord` itself, not as separate RecordRow cases (Decision 14).
enum RecordRow: Identifiable {
    case meal(DisplayMeal)      // corrected total folded in (Req 3.2), not raw MealRecord
    case insulin(InsulinEntry)  // .id is UUID
    case glucose(GlucoseRow)    // (id: Event.id, timestamp, mmolL) — GlucoseReading has no id
    case intake(IntakeRecord)   // manual carb entry (manual-carb-intake Req 6.1)
    case activity(ActivityEntry)  // logged activity (activity-events Req 4.3)

    // Sort key for the Records timeline (Req 3.1, most-recent-first).
    var timestamp: Date {
        switch self {
        case .meal(let meal): meal.record.createdAt
        case .insulin(let entry): entry.timestamp
        case .glucose(let row): row.timestamp
        case .intake(let record): record.timestamp
        case .activity(let entry): entry.timestamp
        }
    }

    // Stable tie-break for rows sharing a timestamp (Req 3.1): the source
    // UUID for meal/insulin/intake, the source Event.id for glucose.
    var id: String {
        switch self {
        case .meal(let meal): meal.id.uuidString
        case .insulin(let entry): entry.id.uuidString
        case .glucose(let row): row.id.uuidString
        case .intake(let record): record.id.uuidString
        case .activity(let entry): entry.id.uuidString
        }
    }
}

// A manual carb entry wrapped with the display contract RecordsView's row
// renderer needs (manual-carb-intake design: Records integration), so the
// renderer stays agnostic to intake's category set.
struct IntakeRecord: Identifiable, Equatable {
    let entry: IntakeEntry
    var id: UUID { entry.id }
    var timestamp: Date { entry.timestamp }
    var displayValue: String { "\(Int(entry.carbsG.rounded())) g" }
    // Only .carb ships in manual-carb-intake (Decision 6 / home-router
    // Decision 14), so the label is a plain constant, not a branch
    // pre-guessing a subtype this spec does not implement.
    var typeLabel: String { "Carbs" }
}

// A glucose reading kept with its source Event.id (design: Records data flow).
// `GlucoseReading` (TrendsMath.swift) carries no id, so this is the row shape
// for Records — mapped directly from `.bsl` Events, not via TrendsModel's
// id-dropping plotting decoder.
struct GlucoseRow: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let mmolL: Double
    // How it was measured (fingerprick-glucose Req 4.3). Defaulted so the
    // existing construction sites read unchanged, and `.sensor` because an
    // absent `metadata.provenance` key IS a sensor reading (Req 7.1).
    var provenance: GlucoseProvenance = .sensor

    // Req 4.3 labels BOTH provenances, unlike the Lock Screen, which has room
    // for one qualifier and marks blood alone: a timeline row is read against
    // its neighbours, and an unlabelled row beside a labelled one reads as
    // "unknown" rather than as the other kind.
    var provenanceLabel: String {
        switch provenance {
        case .sensor: return "Sensor"
        case .blood: return "Blood"
        }
    }
}

// The capture-born preset draft (specs/data/manual-carb-intake Req 8, task
// 15): a meal's DISPLAYED total, frozen at the moment of the tap, becomes a
// quick-add preset draft for the shared edit sheet. Lives here — the standing
// home for App-layer meal plumbing shared across surfaces — so the review and
// result surfaces build byte-identical drafts.
//
// Name: first two prettified food names joined with " + ", then " +N" when N
// further foods remain; empty when the caller passes no names (the sheet's
// name-required rule then holds Save disabled until one is typed). Carbs: the
// displayed total, corrections included (Req 8.3), clamped into the manual
// 1–999 g range — a meal rounding to 0 g yields an empty carb field and a
// disabled Save via the sheet's existing canSave rule. Macros stay absent
// (Req 8.4): clinicalTotals protein/fat/fibre are deliberately not carried.
func quickPresetDraft(
    displayedCarbsG: Float,
    foodNames: [String],
    sourceMealID: UUID,
    existingPresets: [QuickPreset]
) -> QuickPreset {
    let name: String
    if foodNames.isEmpty {
        name = ""
    } else {
        // Trimmed at the first comma before joining: CoFID display names carry
        // cooking-state descriptors ("Pasta, cooked"), and mixing
        // comma-as-descriptor with plus-as-join makes a two-food name read as
        // four items on a grid tile whose label width is already the scarce
        // thing (UI review 2026-09-04).
        let heads = foodNames.map { name in
            String(name.prefix(while: { $0 != "," }))
                .trimmingCharacters(in: .whitespaces)
        }
        let lead = heads.prefix(2).joined(separator: " + ")
        let rest = heads.count - 2
        name = rest > 0 ? "\(lead) +\(rest)" : lead
    }
    let rounded = Int(displayedCarbsG.rounded())
    let clamped = min(max(rounded, 0), CarbEntryModel.maxCarbs)
    return QuickPreset(
        name: name,
        carbsG: Double(clamped),
        sortOrder: QuickPreset.nextSortOrder(after: existingPresets),
        sourceMealID: sourceMealID
    )
}

// The whole create interaction for a capture-born preset
// (manual-carb-intake Req 8.2 as amended, Decision 13): the name, and nothing
// else. The carbohydrate value is already frozen by `quickPresetDraft`
// (Decision 8) and the macros are required to be absent (Decision 9), so the
// name is the only input the caller does not already hold. Every other field
// is reached afterwards through the Intake grid's edit path (Req 8.6), which
// still opens the full `QuickPresetEditSheet` unchanged.
//
// Shared because Decision 12 put the action on BOTH result surfaces, and this
// spec's whole point is that one shape is written once
// (specs/ui/shared-meal-components).
struct QuickAddNamePrompt: ViewModifier {
    @Binding var draft: QuickPreset?
    @Binding var name: String
    let store: any PersistenceStore
    let identifier: String

    // Dismissal — Cancel, Save, or a tap outside — clears the draft, so the
    // presented state has exactly one source of truth.
    private var presented: Binding<Bool> {
        Binding(
            get: { draft != nil },
            set: { shown in if !shown { draft = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert("Save as quick-add", isPresented: presented) {
            TextField("Name", text: $name)
                .accessibilityIdentifier(identifier)
            Button("Cancel", role: .cancel) {}
            Button("Save") { save() }
        }
    }

    // An empty name writes nothing and says nothing: the focused field is the
    // cue, and validation copy is off the table under the developer-phase copy
    // rule. `saveQuickPreset` is insert-or-replace by id, so this is the same
    // one save path the full sheet uses.
    private func save() {
        guard var preset = draft else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        preset.name = trimmed
        Task { try? await store.saveQuickPreset(preset) }
    }
}

extension View {
    func quickAddNamePrompt(
        draft: Binding<QuickPreset?>,
        name: Binding<String>,
        store: any PersistenceStore,
        identifier: String
    ) -> some View {
        modifier(QuickAddNamePrompt(
            draft: draft, name: name, store: store, identifier: identifier
        ))
    }
}

// One row's worth of display data for the Records timeline (design-handoff-00
// §8, critic R2; relocated from the retired MealHistoryModel.swift —
// specs/ui/shared-meal-components Req 6.2). `RecordsModel.reload()` composes
// each meal with its corrections so that a landed correction actually
// invalidates the SwiftUI row: a value-identical `MealRecord` refetch alone
// would diff as unchanged, so the corrected total and the corrected flag are
// folded into this struct (which IS `Equatable`).
struct DisplayMeal: Identifiable, Equatable {
    let record: MealRecord
    // True when any correction row exists for the meal (Req 7.3 marker).
    let isCorrected: Bool
    // The most-recent correction's total override, or nil when no correction set
    // a total — callers fall back to the original estimate.
    let correctedTotalCarbsG: Float?

    var id: UUID { record.id }

    // Total to show in the row: the corrected override when present, otherwise
    // the pipeline's original estimate.
    var displayTotalCarbsG: Float {
        correctedTotalCarbsG ?? record.macros.totalCarbsG
    }
}
