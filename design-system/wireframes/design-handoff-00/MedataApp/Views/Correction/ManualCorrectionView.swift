import SwiftUI

/// Manual correction (req §14). Original values are preserved; corrections
/// are stored in `Meal.userCorrection` and never overwrite the derivation.
struct ManualCorrectionView: View {
    @State var meal: Meal
    @State private var totalCarbs: Double
    @State private var note: String = ""
    @Environment(\.dismiss) private var dismiss

    init(meal: Meal) {
        _meal = State(initialValue: meal)
        _totalCarbs = State(initialValue: Double(meal.displayCarbs))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingM) {
                totalCard
                SectionHeader(text: "Per food")
                ForEach(meal.classes) { c in
                    perClassRow(c)
                }
                noteBlock
                Label {
                    Text("Original estimate is preserved. Your correction is saved alongside it.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .padding(DS.spacingM)
                .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusS))
            }
            .padding(DS.spacingL)
        }
        .navigationTitle("Adjust")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { dismiss() }.tint(DS.success)
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            Text("TOTAL CARBS").font(.caption2.weight(.semibold)).tracking(1)
                .foregroundStyle(.tertiary)
            HStack(spacing: DS.spacingM) {
                Button {
                    totalCarbs = max(0, totalCarbs - 1)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                Stepper(
                    value: $totalCarbs, in: 0...300, step: 1
                ) {
                    Text("\(Int(totalCarbs)) g")
                        .font(.system(size: 36, weight: .light)).monospacedDigit()
                }
                .labelsHidden()
                Text("\(Int(totalCarbs))")
                    .font(.system(size: 36, weight: .light)).monospacedDigit()
                    .frame(maxWidth: .infinity)
                Text("g").foregroundStyle(.secondary)
                Button {
                    totalCarbs += 1
                } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
            }
            Text("was \(meal.displayCarbs) g · auto-estimated")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }

    private func perClassRow(_ c: FoodClass) -> some View {
        VStack(alignment: .leading, spacing: DS.spacingXS) {
            HStack {
                Text(c.name).font(.subheadline)
                Spacer()
                Text("\(Int(c.carbsGrams.rounded())) g").font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(1, c.carbsGrams / max(1, totalCarbs)))
                .tint(DS.ink)
        }
        .padding(.vertical, 6)
        .overlay(Divider(), alignment: .bottom)
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: DS.spacingXS) {
            Text("Note (optional)").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $note)
                .frame(minHeight: 80)
                .padding(DS.spacingS)
                .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusS))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusS)
                        .stroke(DS.separator, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                )
        }
    }
}
