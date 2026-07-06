import Pipeline
import SwiftUI

// Manual correction (§7, design-system/pages/correction.md). A total-carbs
// stepper, per-food value edits, and an optional note. Saving appends a
// correction alongside the original estimate (never overwrites it — Req 7.2);
// `appendCorrection` now emits `eventsDidChange` (Decision 18) so Data rows and
// Meal overview learn the correction landed. The `was N g` line reflects the
// value being corrected from — the latest stored correction if one exists, else
// the original estimate (`store.corrections(for:)`). Save pops one level via
// `onSave` (the route wiring supplies the pop/dismiss).
struct ManualCorrectionView: View {
    let record: MealRecord
    let store: any PersistenceStore
    var onSave: () -> Void = {}

    // Grams, integer for a whole-gram stepper. Total seeds from the prior value;
    // per-food seed from the original per-class carbs (or the prior correction).
    @State private var editedTotalG: Int = 0
    @State private var perFoodG: [String: Int] = [:]
    @State private var note: String = ""
    @State private var priorTotalG: Int = 0
    @State private var loaded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.captureBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    totalSection
                    perFoodSection
                    noteSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 96)
            }
            saveAction
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .navigationTitle("Adjust")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPriorState() }
    }

    // §7.1: total-carbs stepper with the `was N g` prior value beneath it.
    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL CARBS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.captureChromeText.opacity(0.6))
            Stepper(value: $editedTotalG, in: 0...1000) {
                Text("\(editedTotalG) g")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.captureChromeText)
            }
            .tint(.medataAccent)
            Text("was \(priorTotalG) g")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.captureChromeText.opacity(0.6))
        }
        .accessibilityIdentifier("correction.total")
    }

    // §7.1: per-food value edits. One stepper per detected class, in grams.
    private var perFoodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(foods, id: \.name) { food in
                Stepper(value: perFoodBinding(food.name), in: 0...1000) {
                    HStack {
                        Text(food.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.captureChromeText)
                        Spacer()
                        Text("\(perFoodG[food.name] ?? 0) g")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.captureChromeText.opacity(0.75))
                    }
                }
                .tint(.medataAccent)
            }
        }
        .accessibilityIdentifier("correction.perFood")
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Note", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color.captureChromeText)
                .padding(12)
                .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("correction.note")
        }
    }

    // §7.2 preservation notice removed under the developer-phase copy rule
    // (Req 14.5 / Decision 21); the original estimate is still preserved by
    // `appendCorrection`, which never overwrites it.

    // Pill sizing/background/contentShape live INSIDE the Button label so the
    // whole pill is tappable, not just the centred text (the dead-surface trap
    // fixed for CaptureErrorOverlay in 09aab63 and SegmentationReview here).
    private var saveAction: some View {
        Button(action: save) {
            Text("Save")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("correction.save")
    }

    private func perFoodBinding(_ name: String) -> Binding<Int> {
        Binding(
            get: { perFoodG[name] ?? 0 },
            set: { perFoodG[name] = $0 }
        )
    }

    private struct Food {
        let name: String
        let displayName: String
    }

    private var foods: [Food] {
        record.macros.perClass
            .map { name, macro in (name: name, displayName: Self.prettify(name), carbsG: macro.carbsG) }
            .sorted { $0.carbsG > $1.carbsG }
            .map { Food(name: $0.name, displayName: $0.displayName) }
    }

    // Seed the editors from the latest correction if one exists, else the
    // original estimate. The `was N g` line shows whichever value is being
    // corrected from.
    private func loadPriorState() async {
        guard !loaded else { return }
        loaded = true

        let originalTotal = Int(record.macros.totalCarbsG.rounded())
        var total = originalTotal
        var perFood: [String: Int] = record.macros.perClass.mapValues { Int($0.carbsG.rounded()) }
        var priorTotal = originalTotal

        if let last = (try? await store.corrections(for: record.id))?.last {
            if case .correctedTotalCarbsG(let v)? = last.correctedTotalCarbsGOneof {
                total = Int(v.rounded())
                priorTotal = total
            }
            for (name, v) in last.correctedPerClass {
                perFood[name] = Int(v.rounded())
            }
            note = last.note
        }

        editedTotalG = total
        priorTotalG = priorTotal
        perFoodG = perFood
    }

    private func save() {
        var correction = PbUserCorrection()
        correction.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        correction.correctedTotalCarbsG = Float(editedTotalG)
        correction.correctedPerClass = perFoodG.mapValues { Float($0) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { correction.note = trimmed }
        Task {
            try? await store.appendCorrection(mealId: record.id, correction: correction)
            onSave()
        }
    }

    // "white_rice" → "White rice".
    private static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
