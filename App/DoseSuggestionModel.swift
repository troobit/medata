import Dosing
import Foundation
import Observation
import Persistence

// Where a carbohydrate figure came from (specs/data/insulin-dosing Req 7.2).
// Raw values are the ledger's `carbs_source` column strings.
enum CarbsSource: String, Sendable {
    case meal
    case mealCorrected = "meal_corrected"
    case intake
    case quickPreset = "quick_preset"
}

// The one input shape both carbohydrate paths produce (design: Data flow).
// The camera path fills it from the review model; the manual path from the
// entry sheet or a quick-add preset.
struct DoseSubject: Sendable {
    let carbsG: Double?
    let instant: Date  // the meal's own timestamp (Req 2.4)
    let source: CarbsSource
    let sourceEventID: UUID?
    let fatG: Double?
    let proteinG: Double?
    let sigmaMeal: Double?
    let fatStale: Bool  // Req 8.3

    init(
        carbsG: Double?,
        instant: Date,
        source: CarbsSource,
        sourceEventID: UUID? = nil,
        fatG: Double? = nil,
        proteinG: Double? = nil,
        sigmaMeal: Double? = nil,
        fatStale: Bool = false
    ) {
        self.carbsG = carbsG
        self.instant = instant
        self.source = source
        self.sourceEventID = sourceEventID
        self.fatG = fatG
        self.proteinG = proteinG
        self.sigmaMeal = sigmaMeal
        self.fatStale = fatStale
    }
}

// Armed after a meal or intake is recorded; consumed by the dose sheet's
// optional `seed:` parameter. Carries the two facts the sheet's provenance
// caption restates — the carbohydrate figure the sheet cannot see and the
// divisor that produced the number — because on that surface the source
// number is not on screen (design-direction §3.1). Storage stays g/U; the
// caption is rendered from it, never the other way round.
struct DoseSeed: Sendable, Equatable {
    let units: Int
    let suggestionID: UUID
    let armedAt: Date
    let carbsG: Double
    let gramsPerUnit: Double

    // The same 45 minutes Req 11.2 uses to pair a meal with a bolus
    // retrospectively — one constant for the live association and the
    // measurement's association, not two that drift.
    static let lifetime: TimeInterval = 45 * 60

    var provenance: String {
        "from \(Self.grams(carbsG)) g at \(Self.ratio(gramsPerUnit)) g/U"
    }

    private static func grams(_ value: Double) -> String { String(Int(value.rounded())) }

    private static func ratio(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// The one place the pure calculator and the store meet (design: Overview).
// Owned by AppRoot so a seed armed inside the Capture cover survives that
// cover's dismissal, and injected into the environment so the review screen,
// the carb sheet and the dose sheet all read the same instance without being
// threaded through four initialisers.
//
// Producing a suggestion NEVER writes an insulin event (Req 10.1). The only
// thing this model writes is its own ledger row, and that write is the one
// piece of this feature not yet wired — see `ledgerSeam` below.
@Observable
@MainActor
final class DoseSuggestionModel {
    // Live readout for the current pending carbohydrate figure, or nil. One
    // stored fact; `readout` is the "12 U" rendering of it, and the numeral
    // is exposed separately so a surface can weight the number without
    // weighting its unit symbol.
    private(set) var readoutUnits: Int?
    var readout: String? { readoutUnits.map { "\($0) U" } }
    private(set) var seed: DoseSeed?

    private let store: any PersistenceStore
    private let calendar: Calendar

    init(store: any PersistenceStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    // MARK: - Suggestion

    // Recomputes the readout for the figure the user will actually record
    // (Req 3.2) — the review screen calls this as its corrections move the
    // pending total, so the number ticks with the plate scale.
    func refresh(for subject: DoseSubject) async {
        let outcome = await suggest(for: subject)
        switch outcome {
        case .suggested(let dose):
            readoutUnits = dose.seedUnits
        case .suppressed:
            // A suppressed suggestion has no slot — nothing on the screen
            // distinguishes "below 0.5 U", "no ratio in force" and "IOB
            // covers it". The reason is a ledger column, not a word on the
            // capture screen (Req 6.8).
            readoutUnits = nil
        }
    }

    func clearReadout() { readoutUnits = nil }

    // Called when a meal is recorded or an intake row is written. Arms the
    // seed the dose sheet opens at; the readout is left alone because the
    // surface that showed it is on its way out.
    func arm(from subject: DoseSubject) async {
        guard case .suggested(let dose) = await suggest(for: subject) else {
            seed = nil
            return
        }
        seed = DoseSeed(
            units: dose.seedUnits,
            suggestionID: UUID(),
            armedAt: Date(),
            carbsG: subject.carbsG ?? 0,
            gramsPerUnit: dose.context.ratio.gramsPerUnit
        )
    }

    // Consumed once, and only inside its lifetime. Returns nil when no seed
    // is armed or the armed seed has lapsed, so the home Dose control and
    // `medata://insulin/add` open at 10 U exactly as they do today (Req 6.3).
    func takeSeed() -> DoseSeed? {
        guard let armed = seed else { return nil }
        seed = nil
        guard Date().timeIntervalSince(armed.armedAt) <= DoseSeed.lifetime else { return nil }
        return armed
    }

    private func suggest(for subject: DoseSubject) async -> DoseOutcome {
        let inputs = DoseInputs(
            carbsG: subject.carbsG,
            mealInstant: subject.instant,
            calendar: calendar,
            ratios: Self.ratioTable(),
            iobUnits: await insulinOnBoardUnits(at: subject.instant),
            increment: Self.increment(),
            bounds: .stepper
        )
        let outcome = DoseSuggester.suggest(inputs)
        ledgerSeam(outcome, subject: subject)
        return outcome
    }

    // MARK: - The ledger seam (Req 7)
    //
    // NOT WIRED IN THIS BRANCH. `dose_suggestions` (insulin-dosing tasks 6
    // and 7) does not exist yet: there is no table, no `DoseSuggestionRecord`
    // and no `saveDoseSuggestion` / `linkDose` / `doseSuggestions` on
    // `PersistenceStore`. Every input the row needs is present at this call —
    // the outcome carries band, clock, ratio, provenance, increment and
    // insulin-on-board; the subject carries carbohydrate source, source event
    // id, fat, protein and `fat_stale`. When the table lands, this becomes a
    // detached `Task { try? await store.saveDoseSuggestion(…) }` so a
    // persistence failure can neither block nor delay recording the meal
    // (Req 7.7), and `InsulinDoseModel.save()` gains the matching `linkDose`.
    private func ledgerSeam(_ outcome: DoseOutcome, subject: DoseSubject) {}

    // MARK: - Inputs

    // Exactly the duration of action, so the query returns only doses that
    // can contribute (Req 4.3). Basal rows are excluded, matching medreg's
    // `bolus_iob`.
    private func insulinOnBoardUnits(at instant: Date) async -> Double {
        let window = instant.addingTimeInterval(-InsulinActivityModel.rapidActing.durationMinutes * 60)
        let events = (try? await store.events(in: window...instant, type: EventType.insulin)) ?? []
        let boluses: [BolusHistoryEntry] = events.compactMap { event in
            guard
                let units = event.value,
                let data = event.metadata.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let kindRaw = object["kind"] as? String,
                InsulinKind(rawValue: kindRaw) == .bolus
            else { return nil }
            return BolusHistoryEntry(
                minutesBefore: instant.timeIntervalSince(event.timestamp) / 60,
                units: units
            )
        }
        return insulinOnBoard(boluses)
    }

    // Settings are read at suggestion time, never cached: a ratio edited
    // between two meals must take effect on the second one.
    static func ratioTable() -> CarbRatioTable {
        var configured: [DoseBand: CarbRatio] = [:]
        for band in DoseBand.allCases {
            let stored = UserDefaults.standard.double(forKey: ratioKey(for: band))
            if let ratio = CarbRatio(gramsPerUnit: stored) { configured[band] = ratio }
        }
        return CarbRatioTable(configured: configured)
    }

    // The band → key mapping lives here rather than on `SettingsKeys` so that
    // namespace stays a flat list of strings with no module dependency.
    static func ratioKey(for band: DoseBand) -> String {
        switch band {
        case .overnight: SettingsKeys.ratioOvernightGPerU
        case .breakfast: SettingsKeys.ratioBreakfastGPerU
        case .lunch: SettingsKeys.ratioLunchGPerU
        case .dinner: SettingsKeys.ratioDinnerGPerU
        }
    }

    static func increment() -> DosableIncrement {
        DosableIncrement(units: UserDefaults.standard.double(forKey: SettingsKeys.dosableIncrementU))
            ?? .standard
    }
}
