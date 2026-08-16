import Foundation
import Persistence
import PortableContracts
import Testing
@testable import MeData

// Tests for `MealHistoryModel` per UI Req §19.1 / §19.6 / §19.7 (task 31).
// The model is the @MainActor data source for the Meals tab: loads on start,
// reloads on `eventsDidChange`, and routes deletes through the store.
@Suite("MealHistoryModel reload + delete + subscription lifecycle")
@MainActor
struct MealHistoryModelTests {

    @Test("start() loads meals via store.allMeals()")
    func startLoadsInitialMeals() async {
        let a = makeMealRecord()
        let b = makeMealRecord()
        let store = FakeStore(meals: [a, b])
        let model = MealHistoryModel(store: store)
        await model.start()
        #expect(model.meals.count == 2)
    }

    @Test("eventsDidChange tick triggers a reload")
    func changeTickReloads() async throws {
        let initial = makeMealRecord()
        let store = FakeStore(meals: [initial])
        let model = MealHistoryModel(store: store)
        await model.start()
        #expect(model.meals.count == 1)

        let added = makeMealRecord()
        store.append(added)
        // The model is subscribed; the next tick triggers a reload.
        try await waitFor(timeout: 1) { model.meals.count == 2 }
    }

    @Test("delete(_:) calls store.deleteMeal and reloads on tick")
    func deleteRoutesThroughStore() async throws {
        let record = makeMealRecord()
        let store = FakeStore(meals: [record])
        let model = MealHistoryModel(store: store)
        await model.start()
        #expect(model.meals.count == 1)

        await model.delete(record)
        #expect(store.deletedIds == [record.id])
        try await waitFor(timeout: 1) { model.meals.isEmpty }
    }

    @Test("cancel() stops the subscription without leaking the continuation")
    func cancelStopsSubscription() async throws {
        let store = FakeStore(meals: [])
        let model = MealHistoryModel(store: store)
        await model.start()
        model.cancel()

        let added = makeMealRecord()
        store.append(added)
        // No reload after cancellation; small wait to confirm the state stays put.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(model.meals.isEmpty)
        #expect(store.activeContinuationCount == 0)
    }
}

// MARK: - Fixtures

@MainActor
private final class FakeStore: PersistenceStore, @unchecked Sendable {
    private var rows: [MealRecord]
    private(set) var deletedIds: [UUID] = []
    private let broadcaster = TickBroadcaster()

    init(meals: [MealRecord]) {
        self.rows = meals
    }

    var activeContinuationCount: Int { broadcaster.count }

    func append(_ record: MealRecord) {
        rows.append(record)
        broadcaster.tick()
    }

    // PersistenceStore
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {}
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {}
    func meal(id: UUID) async throws -> MealRecord { throw PersistenceError.mealNotFound(id) }
    func deleteArtefacts(olderThan date: Date) async throws {}
    func exportArchive() async throws -> String { "" }
    func sweepIfDue() async throws {}

    func allMeals() async throws -> [MealRecord] {
        rows.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteMeal(id: UUID) async throws {
        rows.removeAll { $0.id == id }
        deletedIds.append(id)
        broadcaster.tick()
    }

    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] {
        fatalError("unused")
    }
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection] {
        fatalError("unused")
    }
    func isImageProcessed(hash: String) async throws -> Bool {
        fatalError("unused")
    }
    func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func saveInsulinDose(_ dose: InsulinDose) async throws {
        fatalError("unused")
    }
    func deleteInsulinEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func saveActivity(_ activity: ActivityEvent) async throws {
        fatalError("unused")
    }
    func deleteActivityEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func activities(
        before instant: Date, within interval: TimeInterval
    ) async throws -> [ActivityEvent] {
        fatalError("unused")
    }
    func saveIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func updateIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func deleteIntakeEntry(id: UUID) async throws {
        fatalError("unused")
    }
    func deleteBslEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func deleteRecords(mealIDs: [UUID], eventIDs: [UUID]) async throws {
        fatalError("unused")
    }
    func quickPresets() async throws -> [QuickPreset] {
        fatalError("unused")
    }
    func saveQuickPreset(_ preset: QuickPreset) async throws {
        fatalError("unused")
    }
    func deleteQuickPreset(id: UUID) async throws {
        fatalError("unused")
    }
    func saveEstimationOutcome(_ outcome: EstimationOutcome) async throws {
        fatalError("unused")
    }
    func estimationOutcomes(limit: Int) async throws -> [EstimationOutcome] {
        fatalError("unused")
    }
    func saveBenchmarkMeal(
        _ meal: BenchmarkMeal, carbsPer100g: (String, String) -> Double?
    ) async throws {
        fatalError("unused")
    }
    func saveDoseSuggestion(_ row: DoseSuggestionRecord) async throws {
        fatalError("unused")
    }
    func linkDose(
        suggestionID: UUID, insulinEventID: UUID, givenUnits: Double
    ) async throws {
        fatalError("unused")
    }
    func doseSuggestions(limit: Int) async throws -> [DoseSuggestionRecord] {
        fatalError("unused")
    }
    func openOccurrence(scheduleID: UUID, dueAt: Date) async throws -> DoseOccurrence {
        fatalError("unused")
    }
    func closeOccurrence(
        id: UUID, outcome: OccurrenceOutcome, closedAt: Date,
        insulinEventID: UUID?, wasNominal: Bool?
    ) async throws -> Bool {
        fatalError("unused")
    }
    func closeOccurrencesAsMissed(ids: [UUID], closedAt: Date) async throws -> Int {
        fatalError("unused")
    }
    func outstandingOccurrences() async throws -> [DoseOccurrence] {
        fatalError("unused")
    }
    func doseOccurrences(limit: Int) async throws -> [DoseOccurrence] {
        fatalError("unused")
    }
    func benchmarkMeals() async throws -> [BenchmarkMeal] {
        fatalError("unused")
    }

    var eventsDidChange: AsyncStream<Void> { broadcaster.subscribe() }
}

private final class TickBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return continuations.count
    }

    func subscribe() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func tick() {
        lock.lock()
        let snapshot = Array(continuations.values)
        lock.unlock()
        for c in snapshot { c.yield() }
    }
}

@MainActor
private func waitFor(
    timeout: TimeInterval,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("condition was not satisfied within \(timeout)s")
}

private func makeMealRecord() -> MealRecord {
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.8
    var macros = PbMacroResult()
    macros.totalCarbsG = 42
    return MealRecord(
        capturePath: .singleViewLidar,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v0",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}
