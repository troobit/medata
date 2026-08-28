import Foundation
import GlucoseWidgetShared
import Observation
import Persistence

// View-model for the glucose entry sheet (specs/data/fingerprick-glucose
// Req 2). Modelled on `ActivityModel`: it owns the whole entry state so the
// sheet is composition only.
//
// The one design constraint that shaped everything here is Req 2.3 — any value
// from 1.0 to 30.0 must be reachable and recorded within FOUR interactions of
// the surface appearing. That excludes both obvious controls. The insulin
// sheet's 0.1-step accelerating stepper needs 51 taps for 7.0 → 12.1. A
// decimal-point text field costs five for 12.1 (`1`, `2`, `.`, `1`, Save).
//
// So the value is entered as DIGITS SHIFTING IN FROM THE RIGHT with an implicit
// tenths place, the way a cash machine takes an amount: `1`, `2`, `1` reads as
// 12.1. No value in range needs more than three digits, so nothing in range
// costs more than four interactions including Save.
//
// That rule now lives in `DigitEntry` and is shared with the insulin mode
// (specs/ui/unified-entry-sheet Req 1.1). What stays here is everything the
// rule is not: the rounding join with ingested readings, and the save.
@Observable
@MainActor
final class GlucoseEntryModel {
    // The same bound the store enforces. Stated here as well because the pad
    // must be unable to EXPRESS an out-of-range value — the store's guard is
    // then a backstop for a deep link or a future caller, not the thing the
    // developer meets.
    static let range: ClosedRange<Double> = 1.0...30.0

    // The shared digit-shift buffer. One decimal place, and the same bound the
    // store enforces — stated here as well because the pad must be unable to
    // EXPRESS an out-of-range value.
    private(set) var entry = DigitEntry(decimals: 1, range: GlucoseEntryModel.range)

    var digits: String { entry.digits }
    // Defaults to now and is never on the path to Save (Req 2.4).
    var timestamp = Date()
    private(set) var isSaving = false
    private(set) var saveError: String?
    private(set) var savedEventID: UUID?

    private let store: any PersistenceStore

    init(store: any PersistenceStore) {
        self.store = store
    }

    // MARK: - The pad

    // Rounded at the one point the whole app rounds glucose, so a hand entry
    // and an ingested reading of the same number compare equal.
    var mmolL: Double { GlucoseGrid.roundedMmolL(entry.value) }

    var displayValue: String { String(format: "%.1f", mmolL) }

    var canSave: Bool { Self.range.contains(mmolL) }

    // Applies whatever the keypad produced — an appended digit, or a shorter
    // string from the delete key. The filtering rules live in `DigitEntry`.
    func setDigits(_ raw: String) { entry.setDigits(raw) }

    // MARK: - Save

    // Writes one blood reading at the chosen instant and returns true so the
    // sheet can dismiss (Req 2.3). `manual` is the route (Req 2.6) and carries
    // no native id, so two entries a minute apart are two readings and a double
    // tap on Save records two rows — hand entries are never deduplicated
    // (Decision 10).
    //
    // Every surface refreshes off the store's `eventsDidChange` tick, so
    // nothing here reloads anything.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            savedEventID = try await store.recordBloodBsl(
                BloodBslReading(
                    instant: timestamp, mmolL: mmolL, sourceID: "manual", nativeID: nil))
            return true
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return false
        }
    }
}
