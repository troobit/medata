import Benchmark
import Foods
import Persistence
import Segmentation
import SwiftUI

// Wraps the editor's target so it can drive `.sheet(item:)`: nil meal means
// a new meal; a non-nil meal pre-fills the form.
private struct MealEditorTarget: Identifiable {
    let id = UUID()
    let meal: BenchmarkMeal?
}

// The weighed-meal benchmark surface (snaq-parity Req 1, design lane B
// "Ground truth in-app" + "Report"), reached from Settings as a sibling of
// the log browser. Renders the SNAQ-comparable report for the current model
// lineage — anchor block and not-headline-valid marker included (Req 1.4/1.6,
// Decision 15 verdict bands) — and manages the meal set. A meal's "Capture"
// action launches the capture flow tagged with the meal id via the closure
// AppRoot injects (Settings and Capture are sibling covers, so the launch is
// sequenced through AppRoot's deep-link machinery).
struct BenchmarkView: View {
    @State private var model: BenchmarkModel
    @State private var editor: MealEditorTarget?

    private let onCapture: (UUID) -> Void

    init(
        store: any PersistenceStore, lineage: String,
        onCapture: @escaping (UUID) -> Void
    ) {
        _model = State(initialValue: BenchmarkModel(store: store, lineage: lineage))
        self.onCapture = onCapture
    }

    var body: some View {
        List {
            if let report = model.report {
                reportSection(report)
            }
            mealsSection
        }
        .navigationTitle("Benchmark")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(item: $editor) { target in
            BenchmarkMealEditorSheet(model: model, editing: target.meal)
        }
    }

    // MARK: - Report (Req 1.1, 1.4, 1.6)

    private func reportSection(_ report: Report) -> some View {
        Section("Report — \(model.lineage)") {
            if !report.headlineValid {
                // Req 1.6: below-floor reports carry an explicit marker
                // naming what is missing.
                Label(headlineMarker(report), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.confidenceModerate)
                    .accessibilityIdentifier("benchmark.notHeadlineValid")
            }
            LabeledContent("Meals (N)", value: "\(report.mealCount)")
            // MAE is never separable from the completion rate (Req 1.1):
            // both figures share one row.
            LabeledContent("MAE / completion", value:
                "\(gramsText(report.maeGrams)) / \(percentText(report.completionRate))")
            LabeledContent("MAPE", value: percentText(report.mapePercent.map { $0 / 100 }))
            LabeledContent("Within ±10 g", value: percentText(report.within10gShare))
            LabeledContent("Attempts", value: attemptsText(report))
            LabeledContent("Verdict", value: verdictText(report.anchorVerdict))
            anchorBlock
        }
        .font(.subheadline)
    }

    // Anchor comparison block (Req 1.4): published figures with their
    // citations, pinned in BenchmarkAnchors.
    private var anchorBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(
                format: "SNAQ anchor %.1f g MAE / %.1f%% MAPE — %@",
                BenchmarkAnchors.snaqMAEGrams,
                BenchmarkAnchors.snaqMAPEPercent,
                BenchmarkAnchors.snaqCitation
            ))
            Text(String(
                format: "Within ±10 g: GoCARB %.1f%%, dietitians %.1f%% — %@",
                BenchmarkAnchors.goCarbWithin10gPercent,
                BenchmarkAnchors.dietitiansWithin10gPercent,
                BenchmarkAnchors.within10gCitation
            ))
        }
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
    }

    private func headlineMarker(_ report: Report) -> String {
        var reasons: [String] = []
        if report.mealCount < BenchmarkReport.headlineMealFloor {
            reasons.append("N \(report.mealCount) < \(BenchmarkReport.headlineMealFloor)")
        }
        if !report.missingStaples.isEmpty {
            reasons.append("missing staples: \(report.missingStaples.joined(separator: ", "))")
        }
        return "Not headline-valid — \(reasons.joined(separator: "; "))"
    }

    private func verdictText(_ verdict: Report.AnchorVerdict) -> String {
        switch verdict {
        case .betterThanAnchor: "Better than SNAQ anchor"
        case .withinNoiseOfAnchor: "Within noise of SNAQ anchor"
        case .worseThanAnchor: "Worse than SNAQ anchor"
        case .insufficientData: "Insufficient data"
        }
    }

    private func attemptsText(_ report: Report) -> String {
        var text = "\(report.totalAttemptCount) (\(report.refusedAttemptCount) refused)"
        if report.undecodableAttemptCount > 0 {
            text += ", \(report.undecodableAttemptCount) undecodable"
        }
        return text
    }

    private func gramsText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f g", value)
    }

    private func percentText(_ share: Double?) -> String {
        guard let share else { return "—" }
        return String(format: "%.0f%%", share * 100)
    }

    // MARK: - Meals (Req 1.2, 1.3)

    private var mealsSection: some View {
        Section("Meals") {
            if model.meals.isEmpty {
                Text("No benchmark meals")
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(model.meals) { meal in
                BenchmarkMealRow(
                    meal: meal,
                    attemptCount: model.attemptCount(for: meal.id),
                    onEdit: { editor = MealEditorTarget(meal: meal) },
                    onCapture: { onCapture(meal.id) }
                )
            }
            Button {
                editor = MealEditorTarget(meal: nil)
            } label: {
                Label("New meal", systemImage: "plus")
            }
            .accessibilityIdentifier("benchmark.newMeal")
        }
    }
}

// One benchmark meal: derived truth, item/attempt counts, fidelity, and the
// two actions — edit (row body) and a tagged capture launch. Both are
// explicit buttons with non-default styles so the List row does not swallow
// either tap.
private struct BenchmarkMealRow: View {
    let meal: BenchmarkMeal
    let attemptCount: Int
    let onEdit: () -> Void
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Capture", action: onCapture)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("benchmark.capture")
        }
        .accessibilityIdentifier("benchmark.row")
    }

    private var subtitle: String {
        let truth = String(format: "%.1f g truth", meal.truthCarbsG)
        let items = "\(meal.items.count) item\(meal.items.count == 1 ? "" : "s")"
        let attempts = "\(attemptCount) attempt\(attemptCount == 1 ? "" : "s")"
        return "\(truth) · \(items) · \(meal.fidelity.rawValue) · \(attempts)"
    }
}

// Meal creation / editing (design lane B): palette class picker, grams
// keypad (1–5000 per item, store-enforced), fidelity toggle. Editing a meal
// that already has attempts SAVES UNDER A NEW ID — the store rejects such
// updates (`benchmarkMealImmutable`) because edits would silently re-score
// history; the UI routes around the gate instead of tripping it.
private struct BenchmarkMealEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let model: BenchmarkModel
    let editing: BenchmarkMeal?

    @State private var name: String
    @State private var fidelity: BenchmarkFidelity
    @State private var items: [EditorItem]
    @State private var isSaving = false
    @State private var saveError: String?

    // Pickable classes: the current 36-class palette minus its three
    // sentinels — the same surface the segmenter emits and Macros resolves
    // against (v2 since the ab812dc3aa9d promotion, adding cereal).
    private static let classIDs =
        ClassPalette.v2Standard.foodClasses + ClassPalette.v2Standard.liquidClasses

    struct EditorItem: Identifiable {
        let id = UUID()
        var classID: String
        var gramsText: String
    }

    init(model: BenchmarkModel, editing: BenchmarkMeal?) {
        self.model = model
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _fidelity = State(initialValue: editing?.fidelity ?? .weighed)
        _items = State(initialValue: editing.map { meal in
            meal.items.map {
                EditorItem(classID: $0.classID, gramsText: String(Int($0.grams.rounded())))
            }
        } ?? [EditorItem(classID: Self.classIDs[0], gramsText: "")])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("benchmark.mealName")
                    Picker("Fidelity", selection: $fidelity) {
                        Text("Weighed").tag(BenchmarkFidelity.weighed)
                        Text("Package").tag(BenchmarkFidelity.package)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Items") {
                    ForEach($items) { $item in
                        HStack {
                            Picker("", selection: $item.classID) {
                                ForEach(Self.classIDs, id: \.self) { classID in
                                    Text(classID).tag(classID)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            TextField("0", text: $item.gramsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                // CarbEntryModel.clampedDigits idiom: digits
                                // only, capped, so pasted junk cannot persist.
                                .onChange(of: item.gramsText) {
                                    let clamped = Self.clampedGrams(item.gramsText)
                                    if clamped != item.gramsText { item.gramsText = clamped }
                                }
                                .accessibilityIdentifier("benchmark.itemGrams")
                            Text("g")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        items.append(EditorItem(classID: Self.classIDs[0], gramsText: ""))
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .accessibilityIdentifier("benchmark.addItem")
                }
                if savesAsNewMeal {
                    Text("Has attempts — saves as a new meal")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                if let saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(editing == nil ? "New meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(savesAsNewMeal ? "Save new" : "Save") { save() }
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("benchmark.saveMeal")
                }
            }
        }
    }

    private var savesAsNewMeal: Bool {
        guard let editing else { return false }
        return model.attemptCount(for: editing.id) > 0
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !items.isEmpty
            && items.allSatisfy { (Int($0.gramsText) ?? 0) >= 1 }
    }

    // Grams keypad sanitiser, 1–5000 per item (`BenchmarkMeal.itemGramsRange`):
    // strips non-digits, caps at 4 digits, clamps the ceiling; the 1 g floor
    // is enforced by `canSave`, matching CarbEntryModel's split.
    static func clampedGrams(_ text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(4))
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(BenchmarkMeal.itemGramsRange.upperBound)))
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            let mealItems = items.map {
                BenchmarkMealItem(classID: $0.classID, grams: Double(Int($0.gramsText) ?? 0))
            }
            if let error = await model.save(
                name: name.trimmingCharacters(in: .whitespaces),
                fidelity: fidelity,
                items: mealItems,
                editing: editing
            ) {
                saveError = error
            } else {
                dismiss()
            }
        }
    }
}

// Data source for the benchmark surface: meals, per-meal attempt counts, and
// the computed report for the current lineage. Fetch-on-appear only, same as
// the log browser (no change stream exists for these tables by design).
@Observable
@MainActor
final class BenchmarkModel {
    private(set) var meals: [BenchmarkMeal] = []
    private(set) var report: Report?
    private(set) var attemptCounts: [UUID: Int] = [:]

    let lineage: String

    private let store: any PersistenceStore
    // The bundled food DB, opened lazily on first save. A second instance
    // beside the pipeline's own is deliberate (PreShutterSegmenter precedent);
    // truth lookups go through the same `FoodDatabase.entry(for:edition:)`
    // surface `Macros.compute` uses (Req 1.2).
    @ObservationIgnored private var foodDatabase: (any FoodDatabase)?

    init(store: any PersistenceStore, lineage: String) {
        self.store = store
        self.lineage = lineage
    }

    func load() async {
        meals = (try? await store.benchmarkMeals()) ?? []
        let outcomes = (try? await store.estimationOutcomes(
            limit: EstimationLogModel.fetchLimit
        )) ?? []
        var counts: [UUID: Int] = [:]
        for outcome in outcomes {
            if let mealID = outcome.benchmarkMealID {
                counts[mealID, default: 0] += 1
            }
        }
        attemptCounts = counts
        report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
    }

    func attemptCount(for mealID: UUID) -> Int {
        attemptCounts[mealID] ?? 0
    }

    // Returns nil on success, or a message for the editor to show. The store
    // derives truth at save and enforces the 1...5000 g bounds, class
    // resolvability, and post-attempt immutability; the id choice here routes
    // around the immutability gate (corrections create a new meal).
    func save(
        name: String, fidelity: BenchmarkFidelity,
        items: [BenchmarkMealItem], editing: BenchmarkMeal?
    ) async -> String? {
        guard let database = database() else { return "Food database unavailable" }
        let reuseID = editing.map { attemptCount(for: $0.id) == 0 } ?? false
        let meal = BenchmarkMeal(
            id: reuseID ? editing!.id : UUID(),
            name: name,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            items: items,
            dbEdition: database.version,
            fidelity: fidelity
        )
        do {
            try await store.saveBenchmarkMeal(
                meal, carbsPer100g: Self.carbsLookup(database: database)
            )
            await load()
            return nil
        } catch PersistenceError.benchmarkClassUnresolvable(let classID) {
            return "No food-database entry for \(classID)"
        } catch PersistenceError.benchmarkGramsOutOfRange(let grams) {
            return "Grams out of range (1–5000): \(Int(grams))"
        } catch {
            return "Save failed: \(String(describing: error))"
        }
    }

    private func database() -> (any FoodDatabase)? {
        if foodDatabase == nil {
            foodDatabase = try? GRDBFoodDatabase.bundled()
        }
        return foodDatabase
    }

    // Built in a nonisolated context so the closure handed to the store is
    // not MainActor-bound (the app target defaults to MainActor isolation).
    nonisolated private static func carbsLookup(
        database: any FoodDatabase
    ) -> (String, String) -> Double? {
        { classID, edition in
            database.entry(for: classID, edition: edition).map { Double($0.carbsMonoG) }
        }
    }
}
