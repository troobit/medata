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
// `MealRoute`, design: Navigation routes). Overview pushes the full Result —
// whose per-food rows carry the adjustment surface (serving-adjust PRD, no
// separate correction screen); Done pops one level; delete removes the meal
// and unwinds to the list.
@MainActor
@ViewBuilder
func mealRouteDestination(
    _ route: MealRoute,
    store: any PersistenceStore,
    path: Binding<[MealRoute]>
) -> some View {
    switch route {
    case .overview(let record):
        MealOverviewView(
            store: store,
            record: record,
            onFullResult: { path.wrappedValue.append(.result(record)) },
            onDeleted: { popOne(path) }
        )
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
}
