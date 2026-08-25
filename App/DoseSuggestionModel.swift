import Dosing
import Foundation
import Observation
import Persistence

// `CarbsSource` (meal / meal_corrected / intake / quick_preset) comes from
// Persistence — the raw values are the exact `dose_suggestions` column
// strings (specs/data/insulin-dosing Req 7).

/// Display derivations for the Settings rows. They live here, not in the
/// `Dosing` target, because that target holds arithmetic and holds no strings.
extension DoseBand {
    var label: String {
        switch self {
        case .overnight: "Overnight"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    /// "06:00–11:00" — a fact about which meals the row governs, rendered as
    /// the Settings row's secondary text (design-direction §5).
    var windowLabel: String {
        String(format: "%02d:00–%02d:00", localHours.lowerBound, localHours.upperBound)
    }
}

// The one input shape both paths produce — a recorded meal on the review
// screen, or a manual carbohydrate entry. `fatG` / `proteinG` / `sigmaMeal` /
// `fatStale` are the ledger's covariates (Req 8.1, 8.3); they change no
// number in this iteration and are carried so the row is complete.
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

// The published readout — the derived-register number every surface renders
// (design-direction §1). Labels live here so "12 U" and "5 g/U" are formatted
// exactly once for the review line, the manual entry line and the history
// segment alike.
nonisolated struct DoseReadout: Sendable, Equatable {
    let units: Int
    let gramsPerUnit: Double
    let carbsG: Double
    let band: DoseBand

    var unitsLabel: String { "\(units) U" }
    /// `5 g/U` — one decimal only when the value has one.
    var ratioLabel: String {
        let value = gramsPerUnit
        let text = value == value.rounded()
            ? String(Int(value)) : String(format: "%.1f", value)
        return "\(text) g/U"
    }
    var provenanceLabel: String {
        "from \(Int(carbsG.rounded())) g at \(ratioLabel)"
    }

    // Shared formatting for surfaces that render a RECORDED row rather than
    // the live readout (Req 6.10). Whole values drop the decimal so the
    // common case reads "12 U"; a 0.5 U pen shows the half.
    static func wholeUnitsLabel(_ units: Double) -> String {
        let rounded = (units * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) U" }
        return String(format: "%.1f U", rounded)
    }

    static func gramsPerUnitLabel(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) g/U" }
        return String(format: "%.1f g/U", rounded)
    }
}

// Armed after a meal or an intake is recorded; consumed once by the next dose
// sheet that opens (Req 6.4). Time-boxed rather than tied: a sheet opened 46
// minutes after a meal opens at the sheet's own default with no explanation,
// which is the intended behaviour of a 45-minute association window.
struct DoseSeed: Sendable, Equatable {
    let units: Int
    // The ledger row this seed came from, so a saved dose can be linked back
    // to the suggestion it answered (Req 7.5).
    let suggestionID: UUID?
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
// Every computed outcome — suggestion or suppression — writes one
// `dose_suggestions` row through the real store (Req 7.1), detached and
// failure-swallowed so a persistence failure never blocks or delays recording
// (Req 7.7). Rows are INSERT OR REPLACE by id, and the id is stable per
// subject, so a review-screen correction rewrites the same row rather than
// appending one per adjustment.
@Observable
@MainActor
final class DoseSuggestionModel {
    // Req 11.2 / design "arm(from:)": the same 45 minutes the retrospective
    // measurement uses to pair a meal with a bolus, so the live association
    // rule and the measurement's association rule are one constant.
    static let seedLifetime: TimeInterval = 45 * 60

    /// Live readout for the current pending subject, or nil on every
    /// suppression (Req 6.6: absence, never a placeholder).
    private(set) var readout: DoseReadout?
    /// The last computed outcome, suppressions included (Req 7.1).
    private(set) var lastOutcome: DoseOutcome?

    private var seed: DoseSeed?
    /// The ledger row id of the last computed outcome, consumed by `arm`.
    private var lastRowID: UUID?
    /// Stable row id per subject, so recomputes rewrite rather than append.
    private var rowIDs: [String: UUID] = [:]

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

    // Recomputes the readout for a subject and records the outcome. The
    // review screen calls this as its corrections move `pendingTotalCarbsG`,
    // so the figure on screen is always the one the user will actually record
    // (Req 3.2), and the ledger row is rewritten in place as it moves.
    func refresh(for subject: DoseSubject) async {
        let outcome = await suggest(for: subject)
        lastOutcome = outcome
        switch outcome {
        case .suggested(let dose):
            readout = DoseReadout(
                units: dose.seedUnits,
                gramsPerUnit: dose.context.gramsPerUnit,
                carbsG: subject.carbsG ?? 0,
                band: dose.context.band
            )
        case .suppressed:
            readout = nil
        }
        let glucose = await startingGlucose(at: subject.instant)
        let record = composeRecord(subject: subject, outcome: outcome, glucose: glucose)
        lastRowID = record.id
        // Detached: a ledger failure must never block or delay the meal
        // (Req 7.7), and the write never notifies eventsDidChange (Req 7.4).
        Task { [store] in try? await store.saveDoseSuggestion(record) }
    }

    func clear() {
        readout = nil
        lastOutcome = nil
        lastRowID = nil
    }

    // Arms the seed for the next dose sheet. Called on `onRecord` (meal) and
    // on save (manual entry, quick preset). A suppressed suggestion arms
    // nothing — there is no seed to offer and no placeholder to show.
    func arm(from subject: DoseSubject) async {
        await refresh(for: subject)
        guard let readout else {
            seed = nil
            return
        }
        seed = DoseSeed(
            units: readout.units,
            suggestionID: lastRowID,
            armedAt: Date(),
            provenance: readout.provenanceLabel
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

    /// Req 7.5: an UPDATE on the side table only — the insulin event's
    /// metadata JSON is written exactly as it is today and no key is added
    /// (Req 7.3, 9.7).
    func noteSavedDose(suggestionID: UUID, eventID: UUID, units: Double) async {
        try? await store.linkDose(
            suggestionID: suggestionID, insulinEventID: eventID, givenUnits: units
        )
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

    /// RECORDED ONLY — no correction term consumes it in iteration 1
    /// (Req 4.7 analogue for glucose: a covariate, never a gate).
    private func startingGlucose(at instant: Date) async -> (mmolL: Double, ageS: Int)? {
        let start = instant.addingTimeInterval(-6 * 3600)
        guard start <= instant else { return nil }
        let rows = (try? await store.events(in: start...instant, type: EventType.bsl)) ?? []
        guard
            let latest = rows.filter({ $0.value != nil }).max(by: { $0.timestamp < $1.timestamp }),
            let value = latest.value
        else { return nil }
        return (value, Int(instant.timeIntervalSince(latest.timestamp)))
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

    // MARK: - Row composition (Req 7.1, 7.2, 8.1)

    private func composeRecord(
        subject: DoseSubject, outcome: DoseOutcome, glucose: (mmolL: Double, ageS: Int)?
    ) -> DoseSuggestionRecord {
        // Stable id per subject: a correction on the same meal rewrites the
        // row (INSERT OR REPLACE), never appends one per keystroke.
        let key = subject.sourceEventID?.uuidString
            ?? "\(subject.source.rawValue)-\(subject.instant.timeIntervalSince1970)"
        let id = rowIDs[key] ?? UUID()
        rowIDs[key] = id

        let context: SuggestionContext
        var outcomeLabel = DoseSuggestionOutcome.suppressed.rawValue
        var suppression: String?
        var exact: Double?
        var rounded: Double?
        var clamped = false
        switch outcome {
        case .suggested(let dose):
            context = dose.context
            outcomeLabel = DoseSuggestionOutcome.suggested.rawValue
            exact = dose.exactUnits
            rounded = dose.roundedUnits
            clamped = dose.seedWasClamped
        case .suppressed(let reason, let suppressedContext):
            context = suppressedContext
            suppression = reason.rawValue
        }

        let source = context.ratioIsSeed
            ? RatioSource.seed.rawValue
            : (defaults.string(forKey: SettingsKeys.ratioSource) ?? RatioSource.manual.rawValue)

        return DoseSuggestionRecord(
            id: id,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            mealTimestampMs: Int64(subject.instant.timeIntervalSince1970 * 1000),
            ruleID: SuggestedDose.ruleID,
            ruleVersion: SuggestedDose.ruleVersion,
            outcome: outcomeLabel,
            suppression: suppression,
            carbsG: subject.carbsG,
            carbsSource: subject.source.rawValue,
            sourceEventID: subject.sourceEventID,
            exactUnits: exact,
            roundedUnits: rounded,
            incrementU: increment().units,
            seedClamped: clamped,
            crGramsPerUnit: context.gramsPerUnit,
            crSource: source,
            crFitRef: defaults.string(forKey: SettingsKeys.ratioFitRef),
            band: context.band.rawValue,
            localHour: context.localHour,
            utcHour: context.utcHour,
            utcOffsetS: context.utcOffsetSeconds,
            iobU: context.iobUnits,
            sigmaMeal: subject.sigmaMeal,
            startBgMmol: glucose?.mmolL,
            startBgAgeS: glucose?.ageS,
            fatG: subject.fatG,
            proteinG: subject.proteinG,
            fpu: DoseSuggestionRecord.fatProteinUnits(
                fatG: subject.fatG, proteinG: subject.proteinG
            ),
            fatStale: subject.fatStale,
            buildStamp: Self.buildStamp
        )
    }

    private static let buildStamp: String = {
        let stamp = Bundle.main.object(forInfoDictionaryKey: "MedataBuildStamp") as? String
        let trimmed = stamp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unstamped" : trimmed
    }()
}
