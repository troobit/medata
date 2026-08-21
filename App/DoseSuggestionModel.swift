import Dosing
import Foundation
import Observation
import Persistence

// Where a carbohydrate figure came from (specs/data/insulin-dosing Req 7,
// `carbs_source`). Raw values are the exact ledger column strings.
enum CarbsSource: String, Sendable {
    case meal
    case mealCorrected = "meal_corrected"
    case intake
    case quickPreset = "quick_preset"
}

// The one input shape both paths produce — a recorded meal on the review
// screen, or a manual carbohydrate entry. `fatG` / `proteinG` / `sigmaMeal` /
// `fatStale` are the ledger's covariates (Req 8.1, 8.3); they change no
// number in this iteration and are carried so the row is complete the moment
// the ledger table lands.
struct DoseSubject: Sendable {
    let carbsG: Double?
    let instant: Date  // the meal's own timestamp (Req 2.4)
    let source: CarbsSource
    let sourceEventID: UUID?
    var fatG: Double?
    var proteinG: Double?
    var sigmaMeal: Double?
    var fatStale: Bool = false
}

// Armed after a meal or an intake is recorded; consumed once by the next dose
// sheet that opens (Req 6.4). Time-boxed rather than tied: a sheet opened 46
// minutes after a meal opens at the sheet's own default with no explanation,
// which is the intended behaviour of a 45-minute association window.
struct DoseSeed: Sendable, Equatable {
    let units: Int
    let armedAt: Date
    // What the sheet restates in place of its `units` caption, because the
    // carbohydrate figure the dose came from is not on that screen
    // (design-direction §1: provenance appears exactly where the source
    // number is not visible). A quantity and two units — no verb.
    let provenance: String
}

// The only place the pure calculator and the store meet (design "Data flow").
// Owned by `AppRoot` and published into the environment, so a seed armed
// inside the Capture cover survives that cover's dismissal.
//
// LEDGER STUB: `saveDoseSuggestion` / `linkDose` and the `dose_suggestions`
// table are insulin-dosing tasks 6–7 and are not merged. Everything that
// makes a number appear on screen works without them; `lastOutcome` holds the
// full `SuggestionContext` the row will be composed from, so wiring the write
// is one call site, not a redesign.
@Observable
@MainActor
final class DoseSuggestionModel {
    // Req 11.2 / design "arm(from:)": the same 45 minutes the retrospective
    // measurement uses to pair a meal with a bolus, so the live association
    // rule and the measurement's association rule are one constant.
    static let seedLifetime: TimeInterval = 45 * 60

    /// Live readout for the current pending subject, or nil on every
    /// suppression. Already formatted — "12 U".
    private(set) var readout: String?
    /// The last computed outcome, suppressions included (Req 7.1).
    private(set) var lastOutcome: DoseOutcome?

    private var seed: DoseSeed?

    private let store: any PersistenceStore
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        store: any PersistenceStore,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.defaults = defaults
        self.calendar = calendar
    }

    // MARK: - Computing

    // Recomputes the readout for a subject. The review screen calls this as
    // its corrections move `pendingTotalCarbsG`, so the figure on screen is
    // always the one the user will actually record (Req 3.2).
    func refresh(for subject: DoseSubject) async {
        let outcome = await suggest(for: subject)
        lastOutcome = outcome
        switch outcome {
        case .suggested(let dose):
            readout = Self.unitsLabel(dose.roundedUnits)
        case .suppressed:
            readout = nil
        }
    }

    func clear() {
        readout = nil
        lastOutcome = nil
    }

    // Arms the seed for the next dose sheet. Called on `onRecord` (meal) and
    // on save (manual entry, quick preset). A suppressed suggestion arms
    // nothing — there is no seed to offer and no placeholder to show.
    func arm(from subject: DoseSubject) async {
        let outcome = await suggest(for: subject)
        lastOutcome = outcome
        guard case .suggested(let dose) = outcome, let carbsG = subject.carbsG else {
            seed = nil
            return
        }
        seed = DoseSeed(
            units: dose.seedUnits,
            armedAt: Date(),
            provenance: Self.provenanceCaption(
                carbsG: carbsG, gramsPerUnit: dose.context.gramsPerUnit
            )
        )
    }

    // Consumed exactly once, and only while fresh. Returning nil is the
    // ordinary case: the home Dose control and `medata://insulin/add` open at
    // the sheet's own default, byte for byte as they do today (Req 6.3).
    func takeSeed() -> DoseSeed? {
        defer { seed = nil }
        guard let seed, Date().timeIntervalSince(seed.armedAt) <= Self.seedLifetime else {
            return nil
        }
        return seed
    }

    // MARK: - Inputs

    private func suggest(for subject: DoseSubject) async -> DoseOutcome {
        DoseSuggester.suggest(
            DoseInputs(
                carbsG: subject.carbsG,
                mealInstant: subject.instant,
                calendar: calendar,
                ratios: ratioTable(),
                iobUnits: await insulinOnBoardUnits(at: subject.instant),
                increment: increment(),
                bounds: .doseSheet
            )
        )
    }

    // The window is exactly the duration of action, so the query returns only
    // doses that can contribute (Req 4.3). Basal rows are skipped, matching
    // medreg's `bolus_iob`.
    private func insulinOnBoardUnits(at instant: Date) async -> Double {
        let duration = InsulinActivityModel.rapidActing.durationMinutes * 60
        let window = instant.addingTimeInterval(-duration)...instant
        let rows = (try? await store.events(in: window, type: EventType.insulin)) ?? []
        let boluses = rows.compactMap { event -> BolusHistoryEntry? in
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

    // Grams per unit, one direction, read straight from Settings. An absent
    // key leaves the band unconfigured and the seed applies (Req 1.6).
    private func ratioTable() -> CarbRatioTable {
        var configured: [DoseBand: CarbRatio] = [:]
        for (band, key) in Self.ratioKeys {
            guard defaults.object(forKey: key) != nil else { continue }
            if let ratio = CarbRatio(gramsPerUnit: defaults.double(forKey: key)) {
                configured[band] = ratio
            }
        }
        return CarbRatioTable(configured: configured)
    }

    private func increment() -> DosableIncrement {
        guard defaults.object(forKey: SettingsKeys.dosableIncrementU) != nil else {
            return .standard
        }
        return DosableIncrement(units: defaults.double(forKey: SettingsKeys.dosableIncrementU))
            ?? .standard
    }

    static let ratioKeys: [(DoseBand, String)] = [
        (.overnight, SettingsKeys.ratioOvernightGPerU),
        (.breakfast, SettingsKeys.ratioBreakfastGPerU),
        (.lunch, SettingsKeys.ratioLunchGPerU),
        (.dinner, SettingsKeys.ratioDinnerGPerU)
    ]

    // MARK: - Formatting

    // A quantity and a unit symbol, and nothing else (design-direction §2.2):
    // no verb, no range, no qualifier. Whole units drop the decimal so the
    // common case reads "12 U" rather than "12.0 U"; a 0.5 U pen shows the
    // half.
    static func unitsLabel(_ units: Double) -> String {
        let rounded = (units * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) U" }
        return String(format: "%.1f U", rounded)
    }

    static func gramsPerUnitLabel(_ gramsPerUnit: Double) -> String {
        let rounded = (gramsPerUnit * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) g/U" }
        return String(format: "%.1f g/U", rounded)
    }

    static func provenanceCaption(carbsG: Double, gramsPerUnit: Double) -> String {
        "from \(Int(carbsG.rounded())) g at \(gramsPerUnitLabel(gramsPerUnit))"
    }
}
