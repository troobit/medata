import Persistence
import PortableContracts
import SwiftUI
import UIKit

// The Data (meal log) screen — design-handoff-00 §8, design-system/pages/data.md.
// A plain chronological log grouped by day (Today / Yesterday / date), newest
// first. Rows are anonymous (thumbnail, time, carbs, confidence — no meal names,
// Req 8.2) and open the Meal overview, not the full Result (Req 8.3). Owns its
// own NavigationStack per the one-stack-per-sheet rule.
struct DataView: View {
    let store: any PersistenceStore

    @Environment(\.dismiss) private var dismiss
    @State private var model: MealHistoryModel
    @State private var path: [MealRoute] = []

    init(store: any PersistenceStore) {
        self.store = store
        _model = State(initialValue: MealHistoryModel(store: store))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Data")
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
    private var content: some View {
        if model.displayMeals.isEmpty {
            emptyState
        } else {
            List {
                ForEach(dayGroups) { group in
                    Section(group.title) {
                        ForEach(group.meals) { meal in
                            NavigationLink(value: MealRoute.overview(meal.record)) {
                                DataRow(meal: meal)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // §8.5 minimal empty state — not a blank list.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("No meals yet")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("data.emptyState")
    }

    // Groups the (already newest-first) display meals into day buckets, keeping
    // the descending order.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [DisplayMeal]] = [:]
        for meal in model.displayMeals {
            let day = calendar.startOfDay(for: meal.record.createdAt)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(meal)
        }
        return order.map {
            DayGroup(id: $0, title: DataView.dayTitle($0, calendar: calendar), meals: buckets[$0] ?? [])
        }
    }

    static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }

    private struct DayGroup: Identifiable {
        let id: Date
        let title: String
        let meals: [DisplayMeal]
    }
}

// One anonymous row in the Data list (Req 8.2): thumbnail (§6.8 fallback), time,
// and carbs (the corrected total when a correction exists, with a `corrected`
// marker). No meal name. No confidence pill — next to a carb total on the
// summary page a "High/Moderate/Low" badge reads as a claim about carb level
// rather than estimate confidence; the pill stays on meal detail and the
// just-captured result, where the context is unambiguous.
struct DataRow: View {
    let meal: DisplayMeal

    @State private var thumbnail: UIImage?

    private var carbs: Int { Int(meal.displayTotalCarbsG.rounded()) }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text("\(carbs) g")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("data.row.carbs")
                    if meal.isCorrected { correctedMarker }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .task {
            thumbnail = await MealPhotoLoader.loadImage(
                assetID: meal.record.photoAssetID,
                targetSize: CGSize(width: 120, height: 120)
            )
        }
    }

    private var thumbnailView: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.surfaceElevated
                Image(systemName: "fork.knife")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("data.row.photoFallback")
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var correctedMarker: some View {
        Text("corrected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.surfaceElevated, in: Capsule())
            .foregroundStyle(Color.textSecondary)
            .accessibilityIdentifier("data.row.correctedMarker")
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: meal.record.createdAt)
    }
}

// Shared destination builder for the Data and Trends sheet stacks (both key
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

// Shared close control for the full-screen Data / Trends / Settings covers
// (Decision 19). Covers have no drag-to-dismiss, so each surface's toolbar
// carries this xmark button. Accessibility label `Close` per the copy inventory.
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
