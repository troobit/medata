import Foundation
import Observation
import Persistence

// @Observable @MainActor data source for the Intake surface
// (specs/data/manual-carb-intake Req 3, 5, 7). Loads the quick-add presets and
// the recent intake entries, owns the one-tap quick-add write and the
// delete paths. Entries refresh on every `eventsDidChange` tick (same
// subscription shape as MealHistoryModel/RecordsModel); presets have no change
// notification, so the preset list reloads after any local preset mutation and
// on preset-sheet dismissal.
@Observable
@MainActor
final class IntakeModel {
    // "Recent" cap for the entries list (design: sorted desc + truncated in
    // Swift — the sheet-based edit surface, not an unbounded history).
    static let recentLimit = 20

    private(set) var presets: [QuickPreset] = []
    private(set) var recentEntries: [IntakeEntry] = []
    // In-flight quick-add marker: the tapped tile is disabled and dimmed for
    // the duration of its write so an accidental double-tap cannot write two
    // rows; deliberate repeat taps work again once the write returns.
    private(set) var savingPresetID: UUID?
    // Bumped only when a quick-add write commits — the view's
    // `.sensoryFeedback` success haptic triggers off it, so a failed write
    // stays silent but never fires the success haptic.
    private(set) var quickAddSuccessCount = 0

    private let store: any PersistenceStore
    private var subscription: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    // No deinit: under MainActor-default isolation a deinit cannot touch
    // `subscription`. The subscription Task captures `self` weakly so the
    // model can be dropped, and the AsyncStream tears down its continuation
    // when the model and its iterator deallocate (MealHistoryModel pattern).

    func start() async {
        await reloadPresets()
        await reloadEntries()
        subscription?.cancel()
        let stream = store.eventsDidChange
        subscription = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.reloadEntries()
            }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    // Insertion order for a NEW preset: max existing sortOrder + 1 (flat
    // list, Decision 6).
    var nextSortOrder: Int {
        (presets.map(\.sortOrder).max() ?? -1) + 1
    }

    func reloadPresets() async {
        presets = (try? await store.quickPresets()) ?? []
    }

    // One-tap quick-add (Req 3.2): writes straight to the ledger with the
    // preset's stored values, timestamped now — no sheet, no confirmation.
    // The entries list refreshes via the `eventsDidChange` tick the save emits.
    func tapPreset(_ preset: QuickPreset) async {
        guard savingPresetID == nil else { return }
        savingPresetID = preset.id
        defer { savingPresetID = nil }
        let entry = IntakeEntry(
            timestamp: Date(),
            carbsG: preset.carbsG,
            macros: preset.macros,
            source: .quickadd,
            presetID: preset.id
        )
        do {
            try await store.saveIntakeEntry(entry)
            quickAddSuccessCount += 1
        } catch {
            // Silent on failure (Req 3.2 minimalism) — the success haptic
            // simply does not fire and no row appears in Recent.
        }
    }

    // Best-effort deletes (MealHistoryModel pattern): a failure leaves the row
    // in the store and the next reload restores the displayed state.
    func delete(_ entry: IntakeEntry) async {
        try? await store.deleteIntakeEntry(id: entry.id)
    }

    // Presets emit no change notification — reload locally after the delete.
    func deletePreset(_ preset: QuickPreset) async {
        try? await store.deleteQuickPreset(id: preset.id)
        await reloadPresets()
    }

    // `events(in:type:)` is range-bounded; this all-time sentinel is the
    // established "no natural window" shape (RecordsModel.allTime).
    private static let allTime: ClosedRange<Date> = .distantPast...Date.distantFuture

    private func reloadEntries() async {
        let events = (try? await store.events(in: Self.allTime, type: EventType.intake)) ?? []
        let entries = events
            .compactMap { Self.intakeEntry(from: $0) }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        recentEntries = Array(entries.prefix(Self.recentLimit))
    }

    // Decodes an `intake` event row: `value` = carbs (g), metadata JSON
    // carries `subtype`/`source` plus optional macro keys and `preset_id`.
    // Deliberately duplicated per model, not shared (home-router Decision 13)
    // — same convention as RecordsModel.intakeEntry(from:). Rows whose
    // metadata does not decode are dropped rather than crashing the list.
    private static func intakeEntry(from event: Event) -> IntakeEntry? {
        guard
            let carbsG = event.value,
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            // `subtype` tolerates an absent key (only .carb ships, so absence
            // is unambiguous); `source` is strict — with two live values, a
            // missing key cannot be defaulted without guessing.
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
}
