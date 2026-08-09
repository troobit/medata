import Foods
import Foundation
import Macros
import Observation
import os
import Pipeline
import Volume

// One relabel target offered by the shortlist or the full eligible list
// (specs/ui/meal-review Req 3.1, 3.4).
struct FoodCandidate: Identifiable, Equatable {
    let classId: String
    let displayName: String
    var id: String { classId }
}

// Independent, composable correction facts (meal-review design Data Models):
// a food can be relabelled AND amount-corrected, and one enum cannot say so.
struct CorrectionFlags: Equatable {
    var classCorrected = false
    var rejected = false
    var absent = false
    var amountCorrected = false
    var pickerOpenedUnchanged = false
    var captureAbandoned = false
    var wasReverted = false

    // "Actual" correction per Req 8.4 — mere row existence does not count.
    var hasActualCorrection: Bool {
        classCorrected || rejected || absent || amountCorrected
    }
}

// One detected food under review. `classId` stays the identity key after a
// relabel — relabelling two foods to the same target does not merge their
// rows, and `predicted.classIndex` remains a valid mask join (Req 9.12).
struct ReviewFood: Identifiable {
    let classId: String
    let predicted: PbFoodDerivation     // never mutated (Req 8.1, 9.2)
    let isLiquid: Bool
    var corrected: PbFoodDerivation?    // nil until any dimension is corrected
    var flags = CorrectionFlags()
    var massSource: PbMassSource = .none
    var shortlistRank: Int32 = 0        // 1-based; 0 = no relabel / full list (Req 9.7)
    var absentQueryText = ""
    // Fixed at review-session start; re-presentation adopts the stored value
    // so created_at never resets (Req 9.2).
    var createdAtMs: Int64 = 0
    // Session-local, never persisted: true from a user mutation until that
    // mutation's first successful store write, so adoptStoredRows cannot
    // clobber a change made during start()'s creation window.
    var isDirty = false

    // The base the whole-meal scale multiplies (Req 6.4): the currently
    // derived mass — post-relabel — or a user-set assertion. Repeated scaling
    // derives from this base, never from a previously scaled value, so it
    // cannot compound.
    var scaleBaseMassG: Double = 0
    var baseIsUserSet = false

    var id: String { classId }

    // The class the row currently stands for: corrected when relabelled,
    // predicted otherwise. Absent foods keep the predicted class for display.
    var currentClassId: String {
        flags.classCorrected ? (corrected?.classID ?? predicted.classID) : predicted.classID
    }

    var currentMassG: Double {
        if flags.rejected { return 0 }
        return corrected?.massG ?? predicted.massG
    }

    var currentCarbsG: Double {
        if flags.rejected { return 0 }
        return corrected?.carbsG ?? predicted.carbsG
    }

    // Coefficient applied to the current mass: the corrected side always
    // carries one when present (copied from predicted for amount-only and
    // absent corrections), so this never re-consults the database (Req 9.11).
    var currentCarbsPer100G: Double {
        corrected?.carbsPer100G ?? predicted.carbsPer100G
    }
}

// Pending state for the single review surface (meal-review design
// "Components and Interfaces"). The view is composition only.
//
// Every mutator writes its CorrectionRecord and the reconciling
// PbUserCorrection in one transaction before returning — written on every
// mutation, not at record(), so a session killed mid-review leaves the corpus
// and Records agreeing (Decision 6/12). Persistence failure is logged and
// swallowed, never surfaced (Req 8.5), per the MaskArtefactWriter precedent.
@Observable
@MainActor
final class MealReviewModel {
    private(set) var foods: [ReviewFood]        // order fixed at init (Req 6.10)
    private(set) var selected: String?
    private(set) var scale: PlateFraction = .all
    // The food whose relabel alternatives are open, and its recency shortlist
    // (Req 3.1, Decision 18). Loaded by openAlternatives.
    private(set) var alternativesFor: String?
    private(set) var shortlist: [FoodCandidate] = []

    let record: MealRecord
    private let store: any PersistenceStore
    private let database: (any FoodDatabase)?
    private let palette: ClassPalette
    private let sessionStartMs: Int64
    private var outcomeID = ""
    private let buildStamp: String
    private let log = Logger(subsystem: "ie.medata.app", category: "MealReview")

    // Abandonment signal (Req 9.5, Decision 5): armed by openAlternatives,
    // discharged by any change to that food while the picker is open.
    private var pickerFoodChanged = false
    // Per-food debounce for amount persists (Decision 12: 500 ms per food) —
    // the UI state updates immediately; only the store write coalesces.
    private var amountPersistTasks: [String: Task<Void, Never>] = [:]

    static let shortlistLimit = 5
    static let shortlistSource = "recency"

    init(
        record: MealRecord,
        store: any PersistenceStore,
        database: (any FoodDatabase)?
    ) {
        self.record = record
        self.store = store
        self.database = database
        self.palette = ClassPalette.standard(for: record.paletteVersion)
        self.sessionStartMs = Int64(Date().timeIntervalSince1970 * 1000)
        let plistStamp = Bundle.main.object(forInfoDictionaryKey: "MedataBuildStamp") as? String
        self.buildStamp = (plistStamp?.isEmpty ?? true) ? "unstamped" : plistStamp!

        // Row order fixed at init (Req 6.10): carbs descending, id tie-break —
        // the ResultView convention, so the surfaces agree.
        let preBeta = record.volumes.perClassVolumesPreBetaCm3
        let palette = ClassPalette.standard(for: record.paletteVersion)
        self.foods = record.macros.perClass
            .map { classId, macro -> ReviewFood in
                var food = ReviewFood(
                    classId: classId,
                    predicted: Self.predictedDerivation(
                        classId: classId, macro: macro,
                        preBetaCm3: preBeta[classId], palette: palette
                    ),
                    isLiquid: macro.isLiquid
                )
                food.scaleBaseMassG = Double(macro.massG)
                return food
            }
            .sorted {
                ($0.predicted.carbsG, $1.classId) > ($1.predicted.carbsG, $0.classId)
            }
    }

    // MARK: - Derived state

    // Meal total under the stored-total-plus-per-class-delta rule
    // (ResultView.swift meal-total rule; design "Meal total"): per-food
    // contributions replace the stored per-class figures, never the stored
    // total itself, so historic records do not jump across database editions.
    var pendingTotalCarbsG: Double {
        let predictedSum = foods.reduce(0.0) { $0 + $1.predicted.carbsG }
        let currentSum = foods.reduce(0.0) { $0 + $1.currentCarbsG }
        return Double(record.macros.totalCarbsG) - predictedSum + currentSum
    }

    var pendingTotalMassG: Double {
        foods.reduce(0.0) { $0 + $1.currentMassG }
    }

    // Corrected-marker input (Req 8.6): any actual correction on any row.
    var hasActualCorrections: Bool {
        foods.contains { $0.flags.hasActualCorrection }
    }

    // Rows the list shows: rejected foods leave the editable list (Req 4.1)
    // and render as de-emphasised remnants with a restore affordance (Req 4.2, 4.3).
    var activeFoods: [ReviewFood] { foods.filter { !$0.flags.rejected } }
    var rejectedFoods: [ReviewFood] { foods.filter { $0.flags.rejected } }

    func food(_ classId: String) -> ReviewFood? {
        foods.first { $0.classId == classId }
    }

    // Badge number for a class — 1-based position in the fixed row order,
    // the non-colour identity channel between photo and row (Req 2.3).
    func badgeNumber(for classId: String) -> Int? {
        foods.firstIndex { $0.classId == classId }.map { $0 + 1 }
    }

    // Mask join for the overlay: the predicted class index in the record's
    // palette (the raster never re-labels).
    func classIndex(for classId: String) -> Int? {
        Self.paletteIndex(of: classId, in: palette)
    }

    // Serving definition for a row's CURRENT class (Req 6.9: a relabel to or
    // from a class without one carries grams rather than resetting).
    func solidServing(for classId: String) -> SolidServing? {
        guard let food = food(classId), !food.isLiquid else { return nil }
        return database?.solidServing(for: food.currentClassId)
    }

    // A relabel needs the pre-β volume; records written before it was
    // persisted fall back to the division, refused where betaUsed is
    // unusable (Decision 17). Reject, absent and amount stay available.
    func canRelabel(_ classId: String) -> Bool {
        guard let food = food(classId) else { return false }
        if food.baseIsUserSet { return database != nil }
        return preBetaVolumeCm3(for: food) != nil && database != nil
    }

    // MARK: - Session lifecycle

    // Creates one row per detected food in state UNCHANGED the moment the
    // surface appears (Req 9.1, 9.5) — INSERT ... DO NOTHING, so
    // re-presentation neither resets created_at nor overwrites a predicted
    // side (Req 9.2). Existing corrected state is adopted so a back-gesture
    // re-push does not clear a correction already made.
    func start() async {
        await resolveOutcomeID()
        let initial = foods.map { food -> PbCorrectionRecord in
            var seeded = food
            seeded.createdAtMs = sessionStartMs
            return correctionRecord(for: seeded)
        }
        do {
            try await store.createCorrectionRecords(initial)
        } catch {
            log.error("event=correction.create.failed error=\(String(describing: error), privacy: .public)")
        }
        await adoptStoredRows()
    }

    // The primary action records what is displayed and dismisses — every
    // correction is already persisted, so this only flushes the amount
    // debounce (Req 7.1, design: record() dismisses only).
    func record() async {
        await flushAmountPersists()
    }

    // Retake or delete (Req 1.3): the capture is abandoned — a per-meal fact
    // held per-row because no meal-scoped row survives deletion (Req 9.5,
    // 9.10). The caller deletes the meal after this returns.
    func discard() async {
        await flushAmountPersists()
        for index in foods.indices {
            foods[index].flags.captureAbandoned = true
            // No reconciling corrections write: the meal is about to be
            // deleted, and this must not mark it corrected (Req 8.6).
            await persist(foods[index], reconcile: false)
        }
    }

    // MARK: - Selection and alternatives

    // Selection only — does NOT open the alternatives (Req 2.7).
    func select(classId: String?) {
        selected = (selected == classId) ? nil : classId
    }

    // Opens the relabel picker and arms the abandonment signal (Req 9.5).
    func openAlternatives(for classId: String) async {
        alternativesFor = classId
        pickerFoodChanged = false
        shortlist = await buildShortlist(for: classId)
    }

    // Writes picker_opened_unchanged when the picker closes with nothing
    // changed; any subsequent change to that food clears it, so the signal
    // means only what it says (Decision 5).
    func dismissAlternatives() async {
        defer {
            alternativesFor = nil
            shortlist = []
        }
        guard let classId = alternativesFor, !pickerFoodChanged,
              let index = index(of: classId) else { return }
        guard !foods[index].flags.pickerOpenedUnchanged else { return }
        foods[index].flags.pickerOpenedUnchanged = true
        foods[index].isDirty = true
        // Corpus-only fact: no displayed value changes, so no reconciling write.
        await persist(foods[index], reconcile: false)
    }

    func alternatives(for classId: String) -> [FoodCandidate] {
        alternativesFor == classId ? shortlist : []
    }

    // The full eligible list (Req 3.4): 25 solid classes or 8 liquid ones from
    // the record's palette, filtered to foods the bundled database gives both
    // a density and a coefficient (Req 3.8) — an ineligible food is
    // unreachable at relabel time. No solid-to-liquid relabel in either
    // direction (Req 3.9).
    func eligibleFoods(for classId: String) -> [FoodCandidate] {
        guard let food = food(classId), let database else { return [] }
        let names = food.isLiquid ? palette.liquidClasses : palette.foodClasses
        return names
            .filter { $0 != food.predicted.classID }
            .compactMap { candidateId in
                guard
                    let entry = database.entry(for: candidateId, edition: record.databaseEdition),
                    entry.densityGPerCm3 > 0
                else { return nil }
                return FoodCandidate(classId: candidateId, displayName: Self.prettify(candidateId))
            }
    }

    // MARK: - Mutators
    //
    // Each is idempotent per (classId, resulting state) and always derives
    // from `predicted`, never from a previous corrected value, so repeated
    // relabels cannot compound Float32 drift (design: β divide-out).

    func relabel(classId: String, to candidate: FoodCandidate, shortlistRank: Int = 0) async {
        guard let index = index(of: classId), let database else { return }
        var food = foods[index]
        // Idempotent: relabelling to the current target is a no-op write.
        if food.flags.classCorrected, food.corrected?.classID == candidate.classId { return }
        // Choosing the predicted class back is the reversal path.
        if candidate.classId == food.predicted.classID {
            await reverseRelabel(classId: classId)
            return
        }
        guard let entry = database.entry(for: candidate.classId, edition: record.databaseEdition) else {
            return  // unreachable from the UI (Req 3.8)
        }

        var derivation: PbFoodDerivation
        if food.baseIsUserSet {
            // Req 3.6 / 6.9: a user-set mass is an assertion — keep it, derive
            // carbohydrate from the chosen food's coefficient only, skipping
            // the β and density steps entirely.
            derivation = Self.derivation(
                classId: candidate.classId, entry: entry, palette: palette,
                volumeCm3: food.predicted.volumeCm3,
                volumePreBetaCm3: food.predicted.volumePreBetaCm3
            )
            let massG = food.currentMassG
            derivation.massG = massG
            derivation.carbsG = massG * derivation.carbsPer100G / 100
        } else {
            guard let preBeta = preBetaVolumeCm3(for: food) else {
                // Decision 14 fallback refusal: never ship one class's β on
                // another's figure. Reject, absent and amount stay available.
                log.error("event=relabel.refused mealId=\(self.record.id.uuidString, privacy: .public) class=\(classId, privacy: .public) reason=preBetaUnrecoverable")
                return
            }
            let beta = Macros.betaCorrection(
                for: [candidate.classId], database: database, edition: record.databaseEdition
            )
            let result = Macros.reDerive(
                preBetaVolumeCm3: preBeta,
                as: candidate.classId,
                beta: beta,
                database: database,
                edition: record.databaseEdition,
                liquidClassIds: food.isLiquid ? [candidate.classId] : [],
                liquidOverEstimate: food.isLiquid && record.macros.liquidOverEstimate
            )
            guard let perClass = result.perClass[candidate.classId] else { return }
            derivation = Self.derivation(
                classId: candidate.classId, entry: entry, palette: palette,
                volumeCm3: Double(perClass.volumeCm3),
                volumePreBetaCm3: Double(preBeta)
            )
            // The scale applies to the currently derived amount — post-relabel
            // (Req 6.4) — so a standing meal scale re-applies to the new figure.
            food.scaleBaseMassG = Double(perClass.massG)
            derivation.massG = food.scaleBaseMassG * scale.factor
            derivation.carbsG = derivation.massG * derivation.carbsPer100G / 100
        }

        food.corrected = derivation
        food.flags.classCorrected = true
        food.flags.absent = false
        food.absentQueryText = ""
        food.shortlistRank = Int32(shortlistRank)
        commit(food, at: index)
        await persist(foods[index])
    }

    // Reversal is per correction dimension, not per row (Req 3.11): restoring
    // the predicted class leaves a co-existing user-set mass in place, and
    // was_reverted is set so a corrected-then-uncorrected food stays
    // distinguishable from a confirmed correct prediction (Decision 5).
    func reverseRelabel(classId: String) async {
        guard let index = index(of: classId) else { return }
        var food = foods[index]
        guard food.flags.classCorrected else { return }
        clearRelabel(&food)
        rebuildCorrectedSide(&food)
        commit(food, at: index)
        await persist(foods[index])
    }

    // The relabel-reversal state change shared by reverseRelabel and
    // markAbsent: drops the relabel dimension, stamps was_reverted so the
    // reversal stays visible to Decision 5's precision numerator, and
    // restores the derived scale base so a later derivation cannot carry
    // the old target's mass under another class's coefficients.
    private func clearRelabel(_ food: inout ReviewFood) {
        food.flags.classCorrected = false
        food.flags.wasReverted = true
        food.shortlistRank = 0
        if !food.baseIsUserSet {
            food.scaleBaseMassG = food.predicted.massG
        }
    }

    // Strikes the entry out (Req 4.1): contribution removed, row leaves the
    // list, the marking stays in a de-emphasised state (Req 4.2). The record
    // keeps a readable corrected side — class unchanged, mass and carbs zero —
    // so a rejection is a training example, not an absence.
    func reject(classId: String) async {
        guard let index = index(of: classId) else { return }
        var food = foods[index]
        guard !food.flags.rejected else { return }
        food.flags.rejected = true
        rebuildCorrectedSide(&food)
        commit(food, at: index)
        await persist(foods[index])
    }

    // Req 4.3: restores the contribution from the surviving dimensions.
    func reverseReject(classId: String) async {
        guard let index = index(of: classId) else { return }
        var food = foods[index]
        guard food.flags.rejected else { return }
        food.flags.rejected = false
        food.flags.wasReverted = true
        rebuildCorrectedSide(&food)
        commit(food, at: index)
        await persist(foods[index])
    }

    // Not-in-the-database (Req 5.1, 5.2): retains any search text alongside
    // the original prediction and leaves the contribution in place and
    // adjustable — density and coefficient copied from predicted, never
    // re-looked-up.
    func markAbsent(classId: String, query: String?) async {
        guard let index = index(of: classId) else { return }
        var food = foods[index]
        let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if food.flags.absent, food.absentQueryText == trimmed { return }
        // A standing relabel is reversed first — the reverseRelabel path —
        // otherwise the absent row would keep the relabel-derived mass under
        // the predicted class's coefficients and hide the reversal from
        // Decision 5's precision numerator.
        if food.flags.classCorrected {
            clearRelabel(&food)
        }
        food.flags.absent = true
        food.absentQueryText = trimmed
        rebuildCorrectedSide(&food)
        commit(food, at: index)
        await persist(foods[index])
    }

    // Per-food amount (Req 6.1, 6.8): state updates immediately; the store
    // write is debounced per food so a held stepper coalesces to one UPDATE.
    func setAmount(classId: String, grams: Double) {
        guard let index = index(of: classId) else { return }
        var food = foods[index]
        let clamped = max(0, grams)
        food.scaleBaseMassG = clamped
        food.baseIsUserSet = true
        food.massSource = .perFood
        food.flags.amountCorrected = true
        rebuildCorrectedSide(&food)
        commit(food, at: index)
        scheduleAmountPersist(classId)
    }

    // Whole-meal scale (Req 6.3–6.5): applies each row's base — currently
    // derived, or the user's own assertion — and never compounds. A row
    // already carrying a user-set mass is scaled from that mass and its
    // mass_source becomes MEAL_SCALE.
    func setScale(_ fraction: PlateFraction) async {
        guard scale != fraction else { return }
        scale = fraction
        for index in foods.indices where !foods[index].flags.rejected {
            var food = foods[index]
            food.massSource = fraction == .all
                ? (food.baseIsUserSet ? .perFood : .none)
                : .mealScale
            food.flags.amountCorrected = food.baseIsUserSet || fraction != .all
            rebuildCorrectedSide(&food)
            commit(food, at: index)
        }
        // One store call for the whole tap: every row update and the
        // reconciling corrections upsert share a single transaction, so a
        // force-quit mid-write cannot leave some rows scaled while Records
        // shows the unscaled total (design "the reconciling write").
        let affected = foods.filter { !$0.flags.rejected }
        guard !affected.isEmpty else { return }
        do {
            try await store.updateCorrectionRecords(
                affected.map { correctionRecord(for: $0) },
                upsertingCorrection: reconcilingCorrection()
            )
            for food in affected { markClean(food.classId) }
        } catch {
            // Req 8.5: never surfaced, never blocks recording.
            log.error("event=correction.persist.failed mealId=\(self.record.id.uuidString, privacy: .public) class=scale error=\(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Corrected-side maintenance

    // Rebuilds the mutable corrected side from the immutable predicted side
    // plus the current flags (Req 9.3: updated in place; intermediate values
    // are not retained). Order of precedence: rejection zeroes the figures,
    // absent empties the class, a relabel carries its own derivation, and the
    // amount applies to whichever class survives.
    private func rebuildCorrectedSide(_ food: inout ReviewFood) {
        if food.flags.classCorrected, food.corrected != nil {
            // Keep the relabel derivation; refresh mass and carbs below.
        } else if food.flags.hasActualCorrection {
            var derivation = food.predicted
            if food.flags.absent {
                derivation.classID = ""  // stated gap, not a forced class (Req 5.2)
            }
            food.corrected = derivation
        } else {
            // No dimension remains corrected: unset (design corrected-side table).
            food.corrected = nil
            food.massSource = food.baseIsUserSet ? .perFood : .none
            return
        }

        guard var derivation = food.corrected else { return }
        if food.flags.rejected {
            derivation.massG = 0
            derivation.carbsG = 0
        } else {
            let massG = food.scaleBaseMassG * scale.factor
            derivation.massG = massG
            derivation.carbsG = massG * derivation.carbsPer100G / 100
        }
        food.corrected = derivation
    }

    // Writes the row back and discharges the picker-abandonment arm when this
    // change concerns the food whose picker is open.
    private func commit(_ food: ReviewFood, at index: Int) {
        var updated = food
        if updated.flags.pickerOpenedUnchanged {
            updated.flags.pickerOpenedUnchanged = false
        }
        updated.isDirty = true
        if alternativesFor == food.classId { pickerFoodChanged = true }
        foods[index] = updated
    }

    // MARK: - Persistence

    private func persist(_ food: ReviewFood, reconcile: Bool = true) async {
        let record = correctionRecord(for: food)
        let correction = reconcile ? reconcilingCorrection() : nil
        do {
            try await store.updateCorrectionRecord(record, upsertingCorrection: correction)
            markClean(food.classId)
        } catch {
            // Req 8.5: never surfaced, never blocks recording.
            log.error("event=correction.persist.failed mealId=\(self.record.id.uuidString, privacy: .public) class=\(food.classId, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    // The stored row now carries the mutation, so adoptStoredRows may adopt it.
    private func markClean(_ classId: String) {
        guard let index = index(of: classId) else { return }
        foods[index].isDirty = false
    }

    private func scheduleAmountPersist(_ classId: String) {
        amountPersistTasks[classId]?.cancel()
        amountPersistTasks[classId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.amountPersistTasks[classId] = nil
            if let food = self.food(classId) {
                await self.persist(food)
            }
        }
    }

    private func flushAmountPersists() async {
        let pending = amountPersistTasks
        amountPersistTasks = [:]
        for (classId, task) in pending {
            task.cancel()
            if let food = food(classId) {
                await persist(food)
            }
        }
    }

    private func correctionRecord(for food: ReviewFood) -> PbCorrectionRecord {
        var out = PbCorrectionRecord()
        out.schemaVersion = "1"
        out.mealID = record.id.uuidString
        out.outcomeID = outcomeID
        out.createdAtMs = food.createdAtMs == 0 ? sessionStartMs : food.createdAtMs
        out.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        out.paletteVersion = record.paletteVersion
        out.databaseEdition = record.databaseEdition
        out.segmenterSource = record.segmenterSource
        out.buildStamp = buildStamp
        out.predicted = food.predicted
        if let corrected = food.corrected { out.corrected = corrected }
        out.classCorrected = food.flags.classCorrected
        out.rejected = food.flags.rejected
        out.absent = food.flags.absent
        out.amountCorrected = food.flags.amountCorrected
        out.pickerOpenedUnchanged = food.flags.pickerOpenedUnchanged
        out.captureAbandoned = food.flags.captureAbandoned
        out.massSource = food.massSource
        out.shortlistRank = food.shortlistRank
        out.absentQueryText = food.absentQueryText
        out.shortlistSource = Self.shortlistSource  // Req 3.3, Decision 18
        out.wasReverted = food.flags.wasReverted
        return out
    }

    // The reconciling display value (design "the reconciling write"): one
    // corrections row per meal, created_at fixed at review-session start, so
    // every latest-row reader sees the corrected total and names (Req 8.6, 8.7).
    private func reconcilingCorrection() -> PbUserCorrection {
        var out = PbUserCorrection()
        out.createdAtMs = sessionStartMs
        out.correctedTotalCarbsG = Float(pendingTotalCarbsG)
        out.correctedPerClass = Dictionary(uniqueKeysWithValues: foods.map {
            ($0.classId, Float($0.currentCarbsG))
        })
        out.correctedClassIds = Dictionary(uniqueKeysWithValues: foods.compactMap { food in
            guard food.flags.classCorrected, let corrected = food.corrected,
                  !corrected.classID.isEmpty else { return nil }
            return (food.classId, corrected.classID)
        })
        // Machine-readable amounts (ServingNote), so ResultView's history
        // seeding keeps working unchanged on corrected meals.
        out.note = ServingNote.note(foods.map { food -> (classId: String, amount: ServingNote.Amount) in
            if let serving = solidServing(for: food.classId) {
                return (classId: food.classId, amount: .servings(
                    ServingMath.servings(grams: food.currentMassG, gramsPerUnit: serving.gramsPerUnit)
                ))
            }
            return (classId: food.classId, amount: .grams(food.currentMassG))
        })
        return out
    }

    // MARK: - Session seeding

    private func resolveOutcomeID() async {
        // The outcome row for this meal joins the record to a capture bundle
        // where one survives (Req 8.3). Newest first; the just-captured meal
        // sits at or near the top.
        let outcomes = (try? await store.estimationOutcomes(limit: 100)) ?? []
        outcomeID = outcomes.first { $0.mealID == record.id }?.id.uuidString ?? ""
    }

    // Adopts rows already in the store — the re-presentation case: created_at
    // keeps its first value and a correction already made is not cleared.
    // Merge, not overwrite: a stored row wins only when it carries state of
    // its own or the in-memory row is untouched, so a mutation landing during
    // start()'s creation window is not clobbered by the freshly created
    // UNCHANGED row it raced against.
    private func adoptStoredRows() async {
        guard let stored = try? await store.correctionRecords(for: record.id) else { return }
        let byClass = Dictionary(uniqueKeysWithValues: stored.map { ($0.predicted.classID, $0) })
        for index in foods.indices {
            guard let row = byClass[foods[index].classId] else { continue }
            let storedHasState = row.classCorrected || row.rejected || row.absent
                || row.amountCorrected || row.pickerOpenedUnchanged
                || row.captureAbandoned || row.wasReverted
            guard storedHasState || !foods[index].isDirty else {
                // Keep the pending mutation; adopt only the fixed created_at
                // (Req 9.2) so its next persist writes the right identity.
                foods[index].createdAtMs = row.createdAtMs
                continue
            }
            var food = foods[index]
            food.createdAtMs = row.createdAtMs
            food.flags.classCorrected = row.classCorrected
            food.flags.rejected = row.rejected
            food.flags.absent = row.absent
            food.flags.amountCorrected = row.amountCorrected
            food.flags.pickerOpenedUnchanged = row.pickerOpenedUnchanged
            food.flags.captureAbandoned = row.captureAbandoned
            food.flags.wasReverted = row.wasReverted
            food.massSource = row.massSource
            food.shortlistRank = row.shortlistRank
            food.absentQueryText = row.absentQueryText
            food.corrected = row.hasCorrected ? row.corrected : nil
            if row.hasCorrected, !row.rejected {
                // The stored mass becomes the new scale base; the meal-scale
                // factor itself is session-local, so it re-derives from here.
                food.scaleBaseMassG = row.corrected.massG
                food.baseIsUserSet = row.massSource == .perFood
            }
            foods[index] = food
        }
    }

    // MARK: - Shortlist (Req 3.1, 3.2 — Decision 18 recency ordering)

    private func buildShortlist(for classId: String) async -> [FoodCandidate] {
        let eligible = eligibleFoods(for: classId)
        let eligibleIds = Dictionary(uniqueKeysWithValues: eligible.map { ($0.classId, $0) })
        let recents = (try? await store.recentCorrectedClassIds(
            forPredictedClass: classId, limit: Self.shortlistLimit
        )) ?? []
        var out = recents.compactMap { eligibleIds[$0] }
        // Top up from the eligible list so the shortlist is useful before any
        // history exists; recency-chosen entries always order first.
        for candidate in eligible where out.count < Self.shortlistLimit {
            if !out.contains(candidate) { out.append(candidate) }
        }
        return Array(out.prefix(Self.shortlistLimit))
    }

    // MARK: - Derivation helpers

    private func index(of classId: String) -> Int? {
        foods.firstIndex { $0.classId == classId }
    }

    // Pre-β volume for a relabel: the persisted map (Decision 17), falling
    // back to the division for records written before the field existed —
    // nil (relabel refused) where betaUsed is unusable.
    private func preBetaVolumeCm3(for food: ReviewFood) -> Float? {
        if let stored = record.volumes.perClassVolumesPreBetaCm3[food.classId] {
            return stored
        }
        return Macros.preBetaVolume(
            storedVolumeCm3: Float(food.predicted.volumeCm3),
            betaUsed: Float(food.predicted.betaUsed)
        )
    }

    // Predicted side, built once from the stored record. Density and
    // coefficient are derived arithmetically from the stored figures —
    // ρ = m/V, κ = 100·c/m, guarding zero — never re-looked-up (Req 9.11,
    // Decision 16).
    private static func predictedDerivation(
        classId: String,
        macro: PbPerClassMacros,
        preBetaCm3: Float?,
        palette: ClassPalette
    ) -> PbFoodDerivation {
        var out = PbFoodDerivation()
        out.classID = classId
        out.classIndex = UInt32(paletteIndex(of: classId, in: palette) ?? 0)
        out.volumeCm3 = Double(macro.volumeCm3)
        out.volumePreBetaCm3 = Double(preBetaCm3 ?? 0)
        out.betaUsed = Double(macro.betaUsed)
        out.betaStatus = macro.betaStatus
        out.densityGPerCm3 = macro.volumeCm3 > 0 ? Double(macro.massG / macro.volumeCm3) : 0
        out.carbsPer100G = macro.massG > 0 ? Double(100 * macro.carbsG / macro.massG) : 0
        out.densitySource = macro.densitySource
        out.coefficientSource = macro.coefficientSource
        out.massG = Double(macro.massG)
        out.carbsG = Double(macro.carbsG)
        return out
    }

    // Corrected side for a relabel: the chosen food's own database figures,
    // stamped at correction time so the row stays a self-contained training
    // example (Req 9.11).
    private static func derivation(
        classId: String,
        entry: FoodEntry,
        palette: ClassPalette,
        volumeCm3: Double,
        volumePreBetaCm3: Double
    ) -> PbFoodDerivation {
        var out = PbFoodDerivation()
        out.classID = classId
        out.classIndex = UInt32(paletteIndex(of: classId, in: palette) ?? 0)
        out.volumeCm3 = volumeCm3
        out.volumePreBetaCm3 = volumePreBetaCm3
        out.betaUsed = Double(entry.beta)
        out.betaStatus = Self.pbStatus(entry.calibrationStatus)
        out.densityGPerCm3 = Double(entry.densityGPerCm3)
        out.carbsPer100G = Double(entry.carbsMonoG)
        out.densitySource = entry.densitySource
        out.coefficientSource = entry.compositionSource
        return out
    }

    private static func paletteIndex(of classId: String, in palette: ClassPalette) -> Int? {
        if let index = palette.foodClasses.firstIndex(of: classId) { return index }
        if let index = palette.liquidClasses.firstIndex(of: classId) {
            return palette.foodClasses.count + index
        }
        return nil
    }

    private static func pbStatus(_ status: BetaCalibrationStatus) -> PbBetaCalibrationStatus {
        switch status {
        case .calibrated: return .calibrated
        case .uncalibratedPooled: return .uncalibratedPooled
        case .uncalibratedUnity: return .uncalibratedUnity
        }
    }

    // "white_rice" → "White rice" (shared display convention).
    static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
