import Foundation
import Observation
import Persistence
import PortableContracts

// @Observable @MainActor data source for the Records surface (home-router
// design: Records data flow, Req 3.1/3.6/3.7). Merges meals, insulin, and
// glucose into one most-recent-first timeline, refreshing on every
// `eventsDidChange` tick the same way MealHistoryModel/TrendsModel already do,
// so deletes/adds anywhere reflect here without a manual refresh.
@Observable
@MainActor
final class RecordsModel {
    private(set) var rows: [RecordRow] = []

    private let store: any PersistenceStore
    // The one seam for all three deletion paths (fingerprick-glucose Req 6.2).
    // Held here rather than called from the view because there are three delete
    // call sites in `RecordsView` — the swipe, the bulk confirm and the
    // date-range purge — and they funnel through the two functions below; a
    // fourth added later inherits the route by construction. nil under the
    // UI-test harness, which builds no publisher.
    private let glucoseWidget: GlucoseWidgetPublisher?
    private var subscription: Task<Void, Never>?

    init(store: any PersistenceStore, glucoseWidget: GlucoseWidgetPublisher? = nil) {
        self.store = store
        self.glucoseWidget = glucoseWidget
    }

    // No deinit: under MainActor-default isolation a deinit cannot touch
    // `subscription`. The subscription Task captures `self` weakly so the
    // model can be dropped, and the AsyncStream tears down its continuation
    // when the model and its iterator deallocate (MealHistoryModel pattern).

    func start() async {
        await reload()
        subscription?.cancel()
        let stream = store.eventsDidChange
        subscription = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    func reload() async {
        async let meals = loadMeals()
        async let insulin = loadInsulin()
        async let glucose = loadGlucose()
        async let intake = loadIntake()
        async let activity = loadActivity()
        var merged: [RecordRow] = []
        merged.append(contentsOf: await meals)
        merged.append(contentsOf: await insulin)
        merged.append(contentsOf: await glucose)
        merged.append(contentsOf: await intake)
        merged.append(contentsOf: await activity)
        merged.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
            return lhs.id < rhs.id
        }
        rows = merged
    }

    func delete(_ row: RecordRow) async {
        switch row {
        case .meal(let meal):
            try? await store.deleteMeal(id: meal.id)
        case .insulin(let entry):
            try? await store.deleteInsulinEvent(id: entry.id)
        case .glucose(let reading):
            // Deletable since records-deletion Decision 3 (supersedes
            // home-router Req 3.5). A reading inside the live ingestion
            // window may re-ingest on the next poll — accepted.
            try? await store.deleteBslEvent(id: reading.id)
            // Req 6.2: every current-value surface must now report what it
            // would have reported had this reading never existed. The instant
            // is what authorises the snapshot to roll back past the monotonic
            // guard, and only for this reading.
            await glucoseWidget?.publishRemoval(of: [reading.timestamp])
        case .intake(let record):
            try? await store.deleteIntakeEntry(id: record.id)
        case .activity(let entry):
            // The same swipe the insulin rows use
            // (specs/data/activity-events Req 3.6).
            try? await store.deleteActivityEvent(id: entry.id)
        }
    }

    // Bulk/date-range purge (records-deletion Decision 2): meals carry a
    // cascade, everything else is an events row — one batched store call,
    // one transaction, one change notification regardless of size.
    func deleteBulk(_ rowsToDelete: [RecordRow]) async {
        var mealIDs: [UUID] = []
        var eventIDs: [UUID] = []
        // Collected alongside the ids, so the date-range and delete-all purges
        // (records-deletion) reach Req 6.2 by the same route the swipe does —
        // both call this function.
        var removedGlucose: [Date] = []
        for row in rowsToDelete {
            switch row {
            case .meal(let meal): mealIDs.append(meal.id)
            case .insulin(let entry): eventIDs.append(entry.id)
            case .glucose(let reading):
                eventIDs.append(reading.id)
                removedGlucose.append(reading.timestamp)
            case .intake(let record): eventIDs.append(record.id)
            case .activity(let entry): eventIDs.append(entry.id)
            }
        }
        try? await store.deleteRecords(mealIDs: mealIDs, eventIDs: eventIDs)
        // Deletions carrying no glucose row pass nothing and behave exactly as
        // they did — the rollback is never authorised by an unrelated purge.
        if !removedGlucose.isEmpty {
            await glucoseWidget?.publishRemoval(of: removedGlucose)
        }
    }

    // Rows inside a closed date range — the source for the date-range purge
    // sheet's live count and its delete. The timeline is fully loaded and
    // unwindowed by design (Decision 8), so filtering in memory is exact.
    func rows(in range: ClosedRange<Date>) -> [RecordRow] {
        rows.filter { range.contains($0.timestamp) }
    }

    // Reuses MealHistoryModel's corrections-overlay composition (Decision 13)
    // so the row shows the corrected total (Req 3.2), not MealRecord's
    // original pipeline estimate.
    private func loadMeals() async -> [RecordRow] {
        guard let records = try? await store.allMeals() else { return [] }
        var composed: [RecordRow] = []
        composed.reserveCapacity(records.count)
        for record in records {
            let corrections = (try? await store.corrections(for: record.id)) ?? []
            let correctedTotal = corrections
                .last { $0.correctedTotalCarbsGOneof != nil }?
                .correctedTotalCarbsG
            let meal = DisplayMeal(
                record: record,
                isCorrected: !corrections.isEmpty,
                correctedTotalCarbsG: correctedTotal
            )
            composed.append(.meal(meal))
        }
        return composed
    }

    // `events(in:type:)` is range-bounded — there is no unbounded events
    // accessor (only `allMeals()` is unbounded). This sentinel is intentional
    // (all-time, unwindowed per Decision 8), not an oversight.
    private static let allTime: ClosedRange<Date> = .distantPast...Date.distantFuture

    private func loadInsulin() async -> [RecordRow] {
        let events = (try? await store.events(in: Self.allTime, type: EventType.insulin)) ?? []
        return events.compactMap { Self.insulinEntry(from: $0) }.map { .insulin($0) }
    }

    // Decodes an `insulin` event row the same way TrendsModel.insulinEntry(from:)
    // does — reused convention, not the TrendsModel type itself (that decoder
    // is private to TrendsModel).
    private static func insulinEntry(from event: Event) -> InsulinEntry? {
        guard
            let units = event.value,
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = InsulinKind(rawValue: kindRaw)
        else { return nil }
        return InsulinEntry(id: event.id, timestamp: event.timestamp, units: units, kind: kind)
    }

    private func loadIntake() async -> [RecordRow] {
        let events = (try? await store.events(in: Self.allTime, type: EventType.intake)) ?? []
        return events.compactMap { Self.intakeEntry(from: $0) }.map { .intake(IntakeRecord(entry: $0)) }
    }

    // Decodes an `intake` event row: `value` = carbs (g), metadata JSON
    // carries `subtype`/`source` plus optional macro keys and `preset_id`
    // (manual-carb-intake design: Event type and storage). Deliberately
    // duplicated per model, not shared (home-router Decision 13) — same
    // convention as `insulinEntry(from:)` above. Rows whose metadata does not
    // decode are dropped rather than crashing the list.
    private static func intakeEntry(from event: Event) -> IntakeEntry? {
        guard
            let carbsG = event.value,
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            // `subtype` tolerates an absent key (only .carb ships, so absence is
            // unambiguous); `source` is strict — with two live values, a missing
            // key cannot be defaulted without guessing, so the row is dropped.
            let subtype = IntakeSubtype(rawValue: object["subtype"] as? String ?? "carb"),
            let sourceRaw = object["source"] as? String,
            let source = IntakeSource(rawValue: sourceRaw)
        else { return nil }
        let macros = IntakeMacros(
            proteinG: object["protein_g"] as? Double,
            fatG: object["fat_g"] as? Double,
            fibreG: object["fibre_g"] as? Double
        )
        let presetID = (object["preset_id"] as? String).flatMap(UUID.init(uuidString:))
        return IntakeEntry(
            id: event.id,
            timestamp: event.timestamp,
            carbsG: carbsG,
            subtype: subtype,
            macros: macros,
            source: source,
            presetID: presetID
        )
    }

    private func loadActivity() async -> [RecordRow] {
        let events = (try? await store.events(in: Self.allTime, type: EventType.activity)) ?? []
        return events.compactMap { Self.activityEntry(from: $0) }.map { .activity($0) }
    }

    // Decodes an `activity` event row: `value` = duration in minutes, ABSENT
    // when unrecorded (activity-events Req 1.5 — nil, never 0), metadata JSON
    // carries `kind`. Deliberately duplicated per model rather than shared
    // (home-router Decision 13), same as `insulinEntry(from:)` above.
    private static func activityEntry(from event: Event) -> ActivityEntry? {
        guard
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = ActivityKind(rawValue: kindRaw)
        else { return nil }
        return ActivityEntry(
            id: event.id,
            timestamp: event.timestamp,
            kind: kind,
            durationMinutes: event.value
        )
    }

    // Maps `.bsl` Events directly to GlucoseRow, keeping Event.id — does NOT
    // reuse TrendsModel's glucose decoder, which drops the id (Decision 13).
    // Provenance comes from the shared `GlucoseSnapshotSource.provenance(of:)`
    // (fingerprick-glucose Req 4.3) rather than a fourth reading of the same
    // metadata key; the id is what this loader still cannot borrow.
    private func loadGlucose() async -> [RecordRow] {
        let events = (try? await store.events(in: Self.allTime, type: EventType.bsl)) ?? []
        return events.compactMap { event -> RecordRow? in
            guard let mmolL = event.value else { return nil }
            return .glucose(
                GlucoseRow(
                    id: event.id, timestamp: event.timestamp, mmolL: mmolL,
                    provenance: GlucoseSnapshotSource.provenance(of: event)))
        }
    }
}
