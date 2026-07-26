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

    // Deletion surfaces (specs/ui/records-deletion): edit-mode multi-select
    // with Select All + confirmed bulk delete, and a date-range purge sheet.
    // Selection keys are RecordRow.id (String).
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showDateRangeSheet = false
    @State private var showDeleteAllConfirm = false

    init(store: any PersistenceStore) {
        self.store = store
        _model = State(initialValue: RecordsModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(selection: $selection) {
                ForEach(model.rows) { row in
                    rowView(row)
                        .tag(row.id)
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { model.rows[$0] }
                    Task {
                        for row in toDelete { await model.delete(row) }
                    }
                }
            }
            // Deliberately untitled (snaqui Req 4); inline mode so no
            // large-title band is reserved.
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Delete ^[\(selection.count) record](inflect: true)?",
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete all ^[\(model.rows.count) record](inflect: true)?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    let rows = model.rows
                    Task { await model.deleteBulk(rows) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDateRangeSheet) {
                DateRangePurgeSheet(model: model)
            }
            .navigationDestination(for: MealRoute.self) { route in
                mealRouteDestination(route, store: store, path: $path)
            }
        }
        .task { await model.start() }
    }

    private var isEditing: Bool { editMode == .active }

    private var allSelected: Bool {
        !model.rows.isEmpty && selection.count == model.rows.count
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            CloseCoverButton { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isEditing ? "Done" : "Select") {
                let exiting = isEditing
                withAnimation {
                    editMode = exiting ? .inactive : .active
                    if exiting { selection.removeAll() }
                }
            }
            .accessibilityIdentifier("records.selectToggle")
        }
        if !isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete by Date…", role: .destructive) {
                        showDateRangeSheet = true
                    }
                    // One-tap full-history purge: clearing debug-era records
                    // must not require picker work — stale records would
                    // otherwise feed the meal-glucose regression suggestions
                    // (records-deletion smolspec).
                    Button("Delete All Records…", role: .destructive) {
                        showDeleteAllConfirm = true
                    }
                    .disabled(model.rows.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("records.menu")
            }
        }
        if isEditing {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(model.rows.map(\.id))
                }
                .accessibilityIdentifier("records.selectAll")
                Spacer()
                Button(role: .destructive) {
                    showBulkDeleteConfirm = true
                } label: {
                    Text("Delete (\(selection.count))")
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("records.deleteSelected")
            }
        }
    }

    private func deleteSelected() {
        let rows = model.rows.filter { selection.contains($0.id) }
        Task {
            await model.deleteBulk(rows)
            withAnimation {
                selection.removeAll()
                editMode = .inactive
            }
        }
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
            // Deletable since records-deletion Decision 3 (supersedes
            // home-router Req 3.5 read-only).
            GlucoseRecordRow(reading: reading)
        case .intake(let record):
            IntakeRecordRow(record: record)
        }
    }
}

// Date-range purge sheet (records-deletion): From/To pickers defaulting to
// the earliest record → now, a live count of records in range, and a
// confirmed destructive delete through the same batched path as bulk
// selection. Colocated to avoid a project.pbxproj entry for a new file.
private struct DateRangePurgeSheet: View {
    let model: RecordsModel

    @Environment(\.dismiss) private var dismiss
    @State private var fromDate: Date = .now
    @State private var toDate: Date = .now
    @State private var showConfirm = false

    private var range: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: fromDate)
        let end = Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: toDate)
        ) ?? toDate
        return start...max(start, end)
    }

    private var inRangeCount: Int { model.rows(in: range).count }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $fromDate, displayedComponents: .date)
                DatePicker("To", selection: $toDate, displayedComponents: .date)
                LabeledContent("Records in range", value: "\(inRangeCount)")
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Text("Delete ^[\(inRangeCount) record](inflect: true)")
                        .frame(maxWidth: .infinity)
                }
                .disabled(inRangeCount == 0)
                .accessibilityIdentifier("records.rangeDelete")
            }
            .navigationTitle("Delete by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete ^[\(inRangeCount) record](inflect: true)?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let rows = model.rows(in: range)
                    Task {
                        await model.deleteBulk(rows)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if let earliest = model.rows.last?.timestamp {
                    fromDate = earliest
                }
                toDate = .now
            }
        }
    }
}

// Meal row: corrected carb total (Req 3.2) + timestamp. Navigates to the
// shared meal overview (Req 3.3).
private struct MealRecordRow: View {
    let meal: DisplayMeal

    private var carbs: Int { Int(meal.displayTotalCarbsG.rounded()) }
    // Estimated plate mass (specs/ui/mass-readout): the number a kitchen
    // scale can validate, alongside the carb figure it cannot.
    private var massG: Int {
        Int(meal.record.macros.perClass.values
            .reduce(Float(0)) { $0 + $1.massG }.rounded())
    }

    var body: some View {
        HStack {
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(carbs) g carbs")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("≈ \(massG) g")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
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

// Intake row: manual/quick-add carbs + type label (manual-carb-intake
// Req 6.1). No navigation; swipe-to-delete via the list's onDelete.
private struct IntakeRecordRow: View {
    let record: IntakeRecord

    var body: some View {
        HStack {
            Image(systemName: "carrot")
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(record.displayValue)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text(record.typeLabel)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(timeString(record.timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .accessibilityIdentifier("records.row.intake")
    }
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IE")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}
