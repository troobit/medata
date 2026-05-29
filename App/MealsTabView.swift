import Persistence
import SwiftUI

// Meals tab root — owns its own NavigationStack per the iOS one-stack-per-tab
// rule (UI Req §19.1). Pushes `ResultView(record:, mode: .historyDetail)` on
// row tap. Empty state copy and the fork-knife icon per Req §19.5; trailing
// swipe-to-delete per Req §19.7.
struct MealsTabView: View {
    @Bindable var model: MealHistoryModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Meals")
                .navigationDestination(for: MealRecord.self) { record in
                    ResultView(record: record, mode: .historyDetail)
                }
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        if model.meals.isEmpty {
            emptyState
        } else {
            MealListView(model: model)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "fork.knife")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No meals yet. Tap the Photo tab to capture your first meal.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("meals.emptyState")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Plain List with one trailing swipe action — no .searchable, no EditButton,
// no selection binding (Req §19.8).
struct MealListView: View {
    @Bindable var model: MealHistoryModel

    var body: some View {
        List {
            ForEach(model.meals, id: \.id) { record in
                NavigationLink(value: record) {
                    MealRow(record: record)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await model.delete(record) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("meals.delete")
                }
            }
        }
        .listStyle(.plain)
    }
}
