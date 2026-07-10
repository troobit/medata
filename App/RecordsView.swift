import Persistence
import PortableContracts
import SwiftUI

// The unified Records surface (home-router design: Records replaces Data,
// Req 3). Supersedes the meal-only DataView (Decision 6): one chronological
// timeline of meals, insulin doses, and glucose readings, most-recent-first,
// with no filtering or windowing (Decision 8). Owns its own NavigationStack
// per the one-stack-per-sheet rule, same as DataView did.
struct RecordsView: View {
    let store: any PersistenceStore

    @Environment(\.dismiss) private var dismiss
    @State private var model: RecordsModel
    @State private var path: [MealRoute] = []

    init(store: any PersistenceStore) {
        self.store = store
        _model = State(initialValue: RecordsModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(model.rows) { row in
                    rowView(row)
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { model.rows[$0] }
                    Task {
                        for row in toDelete { await model.delete(row) }
                    }
                }
            }
            .navigationTitle("Records")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseCoverButton { dismiss() }
                }
            }
            .navigationDestination(for: MealRoute.self) { route in
                mealRouteDestination(route, store: store, path: $path)
            }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private func rowView(_ row: RecordRow) -> some View {
        switch row {
        case .meal(let meal):
            NavigationLink(value: MealRoute.overview(meal.record)) {
                MealRecordRow(meal: meal)
            }
        case .insulin(let entry):
            InsulinRecordRow(entry: entry)
        case .glucose(let reading):
            GlucoseRecordRow(reading: reading)
                .deleteDisabled(true)
        }
    }
}

// Meal row: corrected carb total (Req 3.2) + timestamp. Navigates to the
// shared meal overview (Req 3.3).
private struct MealRecordRow: View {
    let meal: DisplayMeal

    private var carbs: Int { Int(meal.displayTotalCarbsG.rounded()) }

    var body: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(carbs) g")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text(timeString(meal.record.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if meal.isCorrected {
                Text("corrected")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.surfaceElevated, in: Capsule())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityIdentifier("records.row.meal")
    }
}

// Insulin row: units + bolus/basal (Req 3.2). No navigation (Req 3.3).
private struct InsulinRecordRow: View {
    let entry: InsulinEntry

    var body: some View {
        HStack {
            Image(systemName: "syringe")
                .foregroundStyle(entry.kind == .basal ? Color.seriesInsulinBasal : Color.seriesInsulinBolus)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("\(Int(entry.units.rounded())) U")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text(entry.kind == .bolus ? "Bolus" : "Basal")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(timeString(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .accessibilityIdentifier("records.row.insulin")
    }
}

// Glucose row: mmol/L (Req 3.2, metric-only). Read-only — no navigation, no
// delete (Req 3.5).
private struct GlucoseRecordRow: View {
    let reading: GlucoseRow

    var body: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundStyle(Color.seriesGlucose)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f mmol/L", reading.mmolL))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text(timeString(reading.timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .accessibilityIdentifier("records.row.glucose")
    }
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IE")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
