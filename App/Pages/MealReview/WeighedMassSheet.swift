#if FIELD_LOOP
import Foods
import os
import Pipeline
import SwiftUI

// Weighed truth from the review screen (ml-feedback-loop Q1). The developer
// weighs the plate once the estimate is up and types the scale's reading
// here. The store writes a `fidelity=weighed` benchmark meal and points this
// capture's estimation outcome at it, so `make field-pull` carries the truth
// off the phone inside `meals.sqlite` and `make field-derive
// CALIBRATION_OUT=<dir>` joins it to the bundle with no hand edit. Before
// this, a weighed figure could only be typed as a field note and back-filled
// into the corpus index by hand (2026-09-29, the 104 g roll).
//
// One gram field per food on the plate, because truth is per item: each
// item's carbohydrate is resolved from its own class, and a plate total
// cannot be split honestly after the fact. The item class is the row's
// CURRENT class — a relabel is the developer saying what the food is — and a
// rejected row is not on the plate. FIELD_LOOP-only: a product build has no
// field truth to collect.
@Observable
@MainActor
final class WeighedMassModel {
    // One food on the plate, as the sheet lists it.
    struct Food: Identifiable, Equatable {
        let id: String           // the review row's id (ReviewFood.classId)
        let classID: String      // the class truth is resolved against
        let displayName: String
        // Unnamed or "not in the database": no coefficient to resolve truth
        // against, so the plate cannot be weighed until it is named or rejected.
        let isBlocked: Bool
    }

    // The benchmark meal this capture's attempt points at, if any: one entered
    // here, or one authored on the Benchmark surface before the capture.
    private(set) var truth: BenchmarkMeal?
    private(set) var outcomeID: UUID?

    private let store: any PersistenceStore
    private let record: MealRecord
    private let database: (any FoodDatabase)?
    private let log = Logger(subsystem: "ie.medata.app", category: "WeighedMass")

    init(store: any PersistenceStore, record: MealRecord, database: (any FoodDatabase)?) {
        self.store = store
        self.record = record
        self.database = database
    }

    var weighedTotalG: Double? {
        truth.map { $0.items.reduce(0) { $0 + $1.grams } }
    }

    // Truth needs an attempt to attach to: the review resolves its outcome
    // id after a possible 500 ms retry, and a history meal whose outcome row
    // aged out has none.
    var canWeigh: Bool { outcomeID != nil && database != nil }

    // Reads the truth already attached to this capture's attempt. Re-run
    // whenever the review model resolves its outcome id.
    func load(outcomeID raw: String) async {
        outcomeID = UUID(uuidString: raw)
        guard let outcomeID else {
            truth = nil
            return
        }
        let outcomes = (try? await store.estimationOutcomes(limit: 100)) ?? []
        guard let mealID = outcomes.first(where: { $0.id == outcomeID })?.benchmarkMealID else {
            truth = nil
            return
        }
        truth = (try? await store.benchmarkMeals())?.first { $0.id == mealID }
    }

    // The grams already recorded, matched to the listed foods by class in
    // order, so re-opening the sheet shows what was entered.
    func prefill(for foods: [Food]) -> [String: String] {
        var remaining = truth?.items ?? []
        var out: [String: String] = [:]
        for food in foods {
            guard let index = remaining.firstIndex(where: { $0.classID == food.classID }) else { continue }
            out[food.id] = String(Int(remaining[index].grams.rounded()))
            remaining.remove(at: index)
        }
        return out
    }

    // nil on success, or a message for the sheet. A re-entry replaces the
    // earlier one (the store deletes the meal it supersedes).
    func save(_ items: [BenchmarkMealItem], foods: [Food]) async -> String? {
        guard let outcomeID else { return "No estimation outcome for this meal" }
        guard let database else { return "Food database unavailable" }
        let meal = BenchmarkMeal(
            name: foods.map(\.displayName).joined(separator: ", ") + " — weighed after capture",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            items: items,
            dbEdition: record.databaseEdition,
            fidelity: .weighed
        )
        do {
            try await store.attachWeighedTruth(
                meal, toOutcome: outcomeID, carbsPer100g: Self.carbsLookup(database: database)
            )
        } catch PersistenceError.benchmarkClassUnresolvable(let classID) {
            return "No food-database entry for \(classID)"
        } catch PersistenceError.benchmarkGramsOutOfRange(let grams) {
            return "Grams out of range (1–5000): \(Int(grams))"
        } catch PersistenceError.outcomeNotFound {
            return "This capture's outcome row is no longer on the phone"
        } catch {
            return "Save failed: \(String(describing: error))"
        }
        let grams = items.map { "\($0.classID):\(Int($0.grams.rounded()))" }.joined(separator: ",")
        // .notice so `make logs` keeps it (iOS does not persist .info).
        log.notice("event=weighed.attach outcomeId=\(outcomeID.uuidString, privacy: .public) benchmarkMealId=\(meal.id.uuidString, privacy: .public) items=\(grams, privacy: .public)")
        await load(outcomeID: outcomeID.uuidString)
        return nil
    }

    // Built in a nonisolated context so the closure handed to the store is
    // not MainActor-bound (BenchmarkModel precedent).
    nonisolated private static func carbsLookup(
        database: any FoodDatabase
    ) -> (String, String) -> Double? {
        { classID, edition in
            database.entry(for: classID, edition: edition).map { Double($0.carbsMonoG) }
        }
    }
}

// The entry itself: a gram field per food, Save once every food has one.
struct WeighedMassSheet: View {
    let model: WeighedMassModel
    let foods: [WeighedMassModel.Food]

    @Environment(\.dismiss) private var dismiss
    @State private var gramsText: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var focusedID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(foods) { food in
                        row(food)
                    }
                } footer: {
                    if foods.contains(where: \.isBlocked) {
                        Text("Name or reject every food on the review first.")
                    }
                }
                if let saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Weighed mass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("weighedMass.save")
                }
            }
            // Keypad sanitiser (ServingStepLogic): digits only, 4 digits,
            // capped at 5000 g — the store's 1...5000 bound.
            .onChange(of: gramsText) {
                let clamped = gramsText.mapValues { ServingStepLogic.clampedRowGrams($0) }
                if clamped != gramsText { gramsText = clamped }
            }
            .onAppear {
                gramsText = model.prefill(for: foods)
                focusedID = foods.first { !$0.isBlocked }?.id
            }
        }
    }

    private func row(_ food: WeighedMassModel.Food) -> some View {
        HStack {
            Text(food.displayName)
            Spacer()
            TextField("0", text: grams(for: food.id))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .focused($focusedID, equals: food.id)
                .disabled(food.isBlocked)
                .accessibilityIdentifier("weighedMass.grams.\(food.id)")
            Text("g")
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func grams(for id: String) -> Binding<String> {
        Binding(
            get: { gramsText[id] ?? "" },
            set: { gramsText[id] = $0 }
        )
    }

    private func gramsValue(_ id: String) -> Int {
        Int(gramsText[id] ?? "") ?? 0
    }

    private var canSave: Bool {
        !foods.isEmpty && foods.allSatisfy { !$0.isBlocked && gramsValue($0.id) >= 1 }
    }

    private func save() {
        isSaving = true
        saveError = nil
        let items = foods.map {
            BenchmarkMealItem(classID: $0.classID, grams: Double(gramsValue($0.id)))
        }
        Task {
            defer { isSaving = false }
            if let error = await model.save(items, foods: foods) {
                saveError = error
            } else {
                dismiss()
            }
        }
    }
}
#endif
