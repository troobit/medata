import SwiftUI

/// Result variant A — single-number hero. Per req §12.4 the displayed total
/// is rounded to 1 g; full precision is preserved on the meal record.
struct ResultView: View {
    let meal: Meal
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: DS.spacingM) {
                heroBlock
                summaryCard
                breakdown
                futureMacros
                actions
            }
            .padding(.horizontal, DS.spacingL)
            .padding(.bottom, DS.spacingXL)
        }
        .navigationTitle("Estimate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Retake") {}
                    Button("Delete", role: .destructive) {
                        env.mealStore.delete(id: meal.id)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var heroBlock: some View {
        VStack(spacing: DS.spacingS) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(meal.displayCarbs)")
                    .font(.system(size: 80, weight: .light, design: .default))
                    .monospacedDigit()
                Text("g carbs")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            ConfidenceChip(confidence: meal.confidence)
            Text("\(meal.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(meal.capturePath == .singleViewLidar ? "Single-view LiDAR" : "Two-view")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, DS.spacingL)
    }

    private var summaryCard: some View {
        HStack(spacing: DS.spacingM) {
            PlaceholderImage(label: "photo")
                .frame(width: 64, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(meal.classes.count) foods recognised").font(.caption)
                Text("Total mass \(Int(meal.totalMass.rounded())) g · \(meal.databaseEdition)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Per-class breakdown")
            ForEach(meal.classes) { c in
                ClassBreakdownRow(foodClass: c) {}
                    .overlay(Divider(), alignment: .bottom)
            }
        }
    }

    /// Reserved slots so the layout doesn't shift when protein & fat land.
    private var futureMacros: some View {
        HStack(spacing: DS.spacingS) {
            ForEach(["Protein — soon", "Fat — soon"], id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        Capsule().strokeBorder(Color(.separator),
                                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
            }
            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: DS.spacingS) {
            Button {} label: {
                Label("Adjust manually", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button {} label: {
                Text("Save to history").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
