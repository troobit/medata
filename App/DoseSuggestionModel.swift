import Dosing
import Foundation
import Observation
import Persistence

// The one place the pure calculator and the store meet
// (specs/data/insulin-dosing design.md "Data flow: estimate to suggestion to
// seed"). Owned by `AppRoot` so a seed armed inside the Capture cover survives
// that cover's dismissal.
//
// Producing a suggestion never writes an insulin event (Req 10.1). The ledger
// write is detached so a persistence failure can neither block nor delay
// recording a meal (Req 7.7).

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

/// The one input shape both carbohydrate paths produce.
nonisolated struct DoseSubject: Sendable, Equatable {
    let carbsG: Double?
    let instant: Date  // the meal's own timestamp (Req 2.4)
    let source: CarbsSource
    let sourceEventID: UUID?
    let fatG: Double?
    let proteinG: Double?
    let sigmaMeal: Double?
    let fatStale: Bool  // Req 8.3
}

/// Armed after a meal or intake is recorded; consumed by the dose sheet.
nonisolated struct DoseSeed: Sendable, Equatable {
    let units: Int
    let suggestionID: UUID
    let armedAt: Date
    /// The dose sheet's provenance caption — the carbohydrate figure the sheet
    /// cannot show and the divisor that produced the number, e.g.
    /// "from 60 g at 5 g/U". Rendered until the first edit, then gone.
    let provenance: String
}

/// What the readout surfaces render. A formatted string cannot serve two hosts
/// whose shed orders differ, so the parts travel and each surface composes its
/// own line.
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
}

// MARK: - The ledger (Req 7)

/// One `dose_suggestions` row, the column set of design.md "The ledger".
/// Composed in the app layer from the pure result, because the persisted type
/// lives in Persistence and the calculator must not reach it (Req 10.3).
nonisolated struct DoseSuggestionRow: Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let mealTimestamp: Date
    let rowVersion: Int
    let ruleID: String
    let ruleVersion: Int
    let outcome: String  // "suggested" | "suppressed"
    let suppression: String?
    let carbsG: Double?
    let carbsSource: String
    let sourceEventID: UUID?
    let exactUnits: Double?
    let roundedUnits: Double?
    let incrementU: Double
    let seedClamped: Bool
    let crGPerU: Double
    let crSource: String  // seed | manual | medreg
    let crFitRef: String?
    let band: String
    let localHour: Int
    let utcHour: Int
    let utcOffsetS: Int
    let iobU: Double
    let sigmaMeal: Double?
    let startBgMmol: Double?
    let startBgAgeS: Int?
    let fatG: Double?
    let proteinG: Double?
    let fpu: Double?
    let fatStale: Bool
    var givenUnits: Double?
    var insulinEventID: UUID?
    let buildStamp: String
}

/// The two writes insulin-dosing task 7 puts on `PersistenceStore`. Neither
/// notifies `eventsDidChange` (Req 7.4).
protocol DoseLedgerRecording: AnyObject, Sendable {
    func saveDoseSuggestion(_ row: DoseSuggestionRow) async throws
    func linkDose(suggestionID: UUID, insulinEventID: UUID, givenUnits: Double) async throws
}

/// STUB. `dose_suggestions` is insulin-dosing tasks 6–7 and is not on this
/// branch, so rows accumulate in memory for the life of the process. Nothing
/// in iteration 1 reads them back — the ledger has no UI surface — so the only
/// thing lost is durability, and every column is still composed and populated
/// so the shape is exercised. Replace with the store methods; the signatures
/// already match.
@MainActor
final class InMemoryDoseLedger: DoseLedgerRecording {
    private var rows: [UUID: DoseSuggestionRow] = [:]

    // `nonisolated` so it can stand as a default argument, which Swift
    // evaluates outside the actor.
    nonisolated init() {}

    func saveDoseSuggestion(_ row: DoseSuggestionRow) async throws {
        rows[row.id] = row  // INSERT OR REPLACE by id
    }

    func linkDose(suggestionID: UUID, insulinEventID: UUID, givenUnits: Double) async throws {
        guard var row = rows[suggestionID] else { return }
        row.givenUnits = givenUnits
        row.insulinEventID = insulinEventID
        rows[suggestionID] = row
    }
}

// MARK: - The model

@Observable
@MainActor
final class DoseSuggestionModel {
    /// Live readout for the current pending subject, or nil when the suggester
    /// suppressed. A suppression is an absent segment, never explanatory text.
    private(set) var readout: DoseReadout?
    private(set) var seed: DoseSeed?

    /// The same 45 minutes Req 11.2 uses to pair a meal with a bolus
    /// retrospectively, so the live association rule and the measurement's
    /// association rule are one constant, not two that drift.
    static let seedLifetime: TimeInterval = 45 * 60

    private let store: any PersistenceStore
    private let ledger: any DoseLedgerRecording
    private let calendar: Calendar
    /// One row per subject, rewritten in place: intermediate refreshes must
    /// not append a row per keystroke (design.md, data flow step 4).
    private var rowIDs: [String: UUID] = [:]
    private var lastRowID: UUID?

    init(
        store: any PersistenceStore,
        ledger: any DoseLedgerRecording = InMemoryDoseLedger(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.ledger = ledger
        self.calendar = calendar
    }

    // MARK: - Settings (Req 1.3, 9.4)

    private func ratioTable() -> CarbRatioTable {
        let defaults = UserDefaults.standard
        var configured: [DoseBand: CarbRatio] = [:]
        for band in DoseBand.allCases {
            let stored = defaults.double(forKey: SettingsKeys.ratioKey(for: band))
            if let ratio = CarbRatio(gramsPerUnit: stored) { configured[band] = ratio }
        }
        return CarbRatioTable(configured: configured)
    }

    private func increment() -> DosableIncrement {
        let stored = UserDefaults.standard.double(forKey: SettingsKeys.dosableIncrementU)
        return DosableIncrement(units: stored) ?? .standard
    }

    // MARK: - Refresh (Req 3.1, 3.2, 4.5)

    func refresh(for subject: DoseSubject) async {
        let iob = await insulinOnBoardUnits(at: subject.instant)
        let inputs = DoseInputs(
            carbsG: subject.carbsG,
            mealInstant: subject.instant,
            calendar: calendar,
            ratios: ratioTable(),
            iobUnits: iob,
            increment: increment(),
            bounds: .doseSheet
        )
        let outcome = DoseSuggester.suggest(inputs)
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
        let row = composeRow(subject: subject, outcome: outcome, glucose: glucose)
        lastRowID = row.id
        // Detached: a ledger failure must never block or delay the meal
        // (Req 7.7).
        Task { [ledger] in try? await ledger.saveDoseSuggestion(row) }
    }

    /// Arms the seed the dose sheet reads when it next opens through the
    /// existing route. No sheet is presented from here (Req 6.3).
    func arm(from subject: DoseSubject) async {
        await refresh(for: subject)
        guard let readout, let id = lastRowID else {
            seed = nil
            return
        }
        seed = DoseSeed(
            units: readout.units,
            suggestionID: id,
            armedAt: Date(),
            provenance: readout.provenanceLabel
        )
    }

    /// nil when nothing is armed or the armed seed has lapsed, so the home
    /// Dose control and `medata://insulin/add` open at 10 U exactly as today.
    func takeSeed() -> DoseSeed? {
        guard let seed else { return nil }
        self.seed = nil
        guard Date().timeIntervalSince(seed.armedAt) <= Self.seedLifetime else { return nil }
        return seed
    }

    func clearReadout() {
        readout = nil
    }

    /// An `UPDATE` on the side table only — the insulin event's metadata JSON
    /// is written exactly as it is today and no key is added (Req 7.3, 9.7).
    func noteSavedDose(suggestionID: UUID, eventID: UUID, units: Double) async {
        try? await ledger.linkDose(
            suggestionID: suggestionID, insulinEventID: eventID, givenUnits: units
        )
    }

    // MARK: - Store reads

    /// The window is exactly the duration of action, so the query returns only
    /// doses that can contribute (Req 4.3). Basal rows are skipped.
    private func insulinOnBoardUnits(at instant: Date) async -> Double {
        let window = InsulinActivityModel.rapidActing.durationMinutes * 60
        let start = instant.addingTimeInterval(-window)
        guard start <= instant else { return 0 }
        let rows = (try? await store.events(in: start...instant, type: EventType.insulin)) ?? []
        let boluses: [BolusHistoryEntry] = rows.compactMap { event in
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

    /// RECORDED ONLY — no correction term consumes it in iteration 1.
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

    // MARK: - Row composition (Req 7.1, 7.2, 8.1)

    private func composeRow(
        subject: DoseSubject, outcome: DoseOutcome, glucose: (mmolL: Double, ageS: Int)?
    ) -> DoseSuggestionRow {
        let key = subject.sourceEventID?.uuidString
            ?? "\(subject.source.rawValue)-\(subject.instant.timeIntervalSince1970)"
        let id = rowIDs[key] ?? UUID()
        rowIDs[key] = id

        let context: SuggestionContext
        var outcomeLabel = "suppressed"
        var suppression: String?
        var exact: Double?
        var rounded: Double?
        var clamped = false
        switch outcome {
        case .suggested(let dose):
            context = dose.context
            outcomeLabel = "suggested"
            exact = dose.exactUnits
            rounded = dose.roundedUnits
            clamped = dose.seedWasClamped
        case .suppressed(let reason, let suppressedContext):
            context = suppressedContext
            suppression = reason.rawValue
        }

        // fpu is computed at write time and stored, never derived on read, so
        // a later change to the formula cannot reinterpret old rows.
        let fpu: Double? = {
            guard let fat = subject.fatG, let protein = subject.proteinG else { return nil }
            return (fat * 9 + protein * 4) / 100
        }()

        let defaults = UserDefaults.standard
        let source = context.ratioIsSeed
            ? "seed" : (defaults.string(forKey: SettingsKeys.ratioSource) ?? "manual")

        return DoseSuggestionRow(
            id: id,
            timestamp: Date(),
            mealTimestamp: subject.instant,
            rowVersion: 1,
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
            crGPerU: context.gramsPerUnit,
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
            fpu: fpu,
            fatStale: subject.fatStale,
            givenUnits: nil,
            insulinEventID: nil,
            buildStamp: Self.buildStamp
        )
    }

    private static let buildStamp: String = {
        let stamp = Bundle.main.object(forInfoDictionaryKey: "MedataBuildStamp") as? String
        let trimmed = stamp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unstamped" : trimmed
    }()
}
