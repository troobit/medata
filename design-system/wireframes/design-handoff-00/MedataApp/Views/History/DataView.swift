import SwiftUI

/// "Data" — the meal log. Rows are deliberately anonymous: no meal names,
/// just carb content, time, and confidence. Selecting a row opens the
/// meal overview (a middle ground between Result and Segmentation review).
struct DataView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(grouped, id: \.day) { group in
                Section {
                    ForEach(group.meals) { m in
                        NavigationLink(value: Route.overview(m)) {
                            DataRow(meal: m)
                        }
                    }
                } header: {
                    Text(group.day)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .overview(let meal):   MealOverviewView(meal: meal)
            case .result(let meal):     ResultView(meal: meal)
            case .correction(let meal): ManualCorrectionView(meal: meal)
            default: EmptyView()
            }
        }
    }

    private var grouped: [(day: String, meals: [Meal])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: env.mealStore.meals) { meal in
            cal.isDateInToday(meal.capturedAt) ? "Today"
                : cal.isDateInYesterday(meal.capturedAt) ? "Yesterday"
                : meal.capturedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return ["Today", "Yesterday"]
            .compactMap { d in dict[d].map { (day: d, meals: $0) } }
            + dict.filter { !["Today", "Yesterday"].contains($0.key) }
                  .sorted { $0.value.first?.capturedAt ?? .now > $1.value.first?.capturedAt ?? .now }
                  .map { (day: $0.key, meals: $0.value) }
    }
}

struct DataRow: View {
    let meal: Meal
    var body: some View {
        HStack(spacing: DS.spacingM) {
            PlaceholderImage(label: "")
                .frame(width: 44, height: 44)
            Text(meal.capturedAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            HStack(spacing: DS.spacingS) {
                Text("\(meal.displayCarbs) g")
                    .font(.headline.monospacedDigit())
                ConfidenceChip(confidence: meal.confidence, compact: true)
            }
        }
        .padding(.vertical, 4)
    }
}
