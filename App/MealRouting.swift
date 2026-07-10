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
// `MealRoute`, design: Navigation routes). Overview pushes the full Result or
// the correction; Done / Save pop one level; delete removes the meal and unwinds
// to the list.
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
            onAdjust: { path.wrappedValue.append(.correction(record)) },
            onFullResult: { path.wrappedValue.append(.result(record)) },
            onDeleted: { popOne(path) }
        )
    case .result(let record):
        ResultView(
            record: record,
            store: store,
            mode: .historyDetail,
            onAdjust: { path.wrappedValue.append(.correction(record)) },
            onDone: { popOne(path) },
            onDelete: {
                Task { try? await store.deleteMeal(id: record.id) }
                path.wrappedValue.removeAll()
            }
        )
    case .correction(let record):
        ManualCorrectionView(
            record: record,
            store: store,
            onSave: { popOne(path) }
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
// Open enum: `manual-carb-intake` (Track C) adds a single `.intake(IntakeRecord)`
// case plus one additive merge source in RecordsModel — the taxonomy of intake
// subtypes (carb, alcohol, …) lives inside `IntakeRecord` itself, not as
// separate RecordRow cases (Decision 14). Do NOT add that case here.
enum RecordRow: Identifiable {
    case meal(DisplayMeal)      // corrected total folded in (Req 3.2), not raw MealRecord
    case insulin(InsulinEntry)  // .id is UUID
    case glucose(GlucoseRow)    // (id: Event.id, timestamp, mmolL) — GlucoseReading has no id

    // Sort key for the Records timeline (Req 3.1, most-recent-first).
    var timestamp: Date {
        switch self {
        case .meal(let meal): meal.record.createdAt
        case .insulin(let entry): entry.timestamp
        case .glucose(let row): row.timestamp
        }
    }

    // Stable tie-break for rows sharing a timestamp (Req 3.1): the source
    // UUID for meal/insulin, the source Event.id for glucose.
    var id: String {
        switch self {
        case .meal(let meal): meal.id.uuidString
        case .insulin(let entry): entry.id.uuidString
        case .glucose(let row): row.id.uuidString
        }
    }
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
