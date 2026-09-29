import SwiftUI

/// Meal overview — reached from the Data list. A middle ground between
/// Result (the number) and Segmentation review (the masks): the captured
/// photo with masks, the carb total, and the per-class detail in one view.
struct MealOverviewView: View {
    let meal: Meal
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingM) {
                // Captured photo with per-class masks overlaid.
                PlaceholderImage(label: "capture · masks overlaid")
                    .aspectRatio(4/3, contentMode: .fit)

                // Compact total row — not the full hero.
                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(meal.displayCarbs)")
                            .font(.system(size: 40, weight: .light))
                            .monospacedDigit()
                        Text("g carbs").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ConfidenceChip(confidence: meal.confidence)
                }

                Text("\(meal.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(meal.capturePath == .singleViewLidar ? "Single-view LiDAR" : "Two-view") · \(meal.databaseEdition)")
                    .font(.caption2).foregroundStyle(.secondary)

                if meal.userCorrection != nil {
                    Label("User-corrected — original estimate preserved", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Per-class detail with mask swatches.
                SectionHeader(text: "Foods (\(meal.classes.count))")
                VStack(spacing: 0) {
                    ForEach(meal.classes) { c in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(DS.ink2.opacity(0.6))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.subheadline)
                                Text("\(Int(c.massGrams)) g · \(Int(c.volumeCubicCm)) cm³")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(c.carbsGrams == 0 ? "≈0 g" : "\(Int(c.carbsGrams.rounded())) g")
                                    .font(.subheadline.monospacedDigit())
                                Text("σ \(c.confidence, specifier: "%.2f")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .overlay(Divider(), alignment: .bottom)
                    }
                }

                HStack(spacing: DS.spacingS) {
                    NavigationLink(value: Route.correction(meal)) {
                        Label("Adjust", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    NavigationLink(value: Route.result(meal)) {
                        Text("Full result").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, DS.spacingL)
            .padding(.bottom, DS.spacingXL)
        }
        .navigationTitle("Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete", role: .destructive) {
                        env.mealStore.delete(id: meal.id)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}
