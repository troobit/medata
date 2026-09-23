import Dosing
import Foundation
import Observation
import Persistence

// Where the pure calculator and the store meet (specs/data/insulin-dosing
// design.md "Data flow", Decision 19).
//
// There is no suggestion model class. Each surface computes its own readout
// where it renders — a pure helper fetches the event window, calls the
// suggester, and the view holds the result as local state. Shared readout
// state is where stale-display bugs live: a surface that computes on
// appearance cannot show another surface's leftovers.
//
// The one genuinely cross-surface piece is the dose sheet's seed (Req 6.4),
// armed inside the Capture cover and consumed by a sheet presented from
// `AppRoot` after that cover is gone. `DoseSeedHolder` is that, and nothing
// else. Nothing is written: the dose is a pure function of recorded events and
// the settings in force, recomputed wherever it is read (Req 6.11).

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

/// The one input shape every path produces: a carbohydrate total, the instant
/// it belongs to, and — where the subject is already a recorded event — its own
/// id, which the offset query must know so a meal never offsets its own
/// pre-bolus (Req 4.8).
struct DoseSubject: Sendable, Equatable {
    let carbsG: Double?
    /// The meal's own timestamp, which selects the band (Req 2.4).
    let instant: Date
    let sourceEventID: UUID?
}

// The readout every surface renders (design-direction §1) — the computed dose
// and everything the working needs behind it, so the tap reveals arithmetic
// rather than a second computation. Labels live here so "12 U" and "5 g/U" are
// formatted exactly once for the review line, the manual entry line and the
// history segment alike.
nonisolated struct DoseReadout: Sendable, Equatable {
    let carbsG: Double
    let dose: SuggestedDose

    var units: Int { Int(dose.roundedUnits) }
    var gramsPerUnit: Double { dose.context.gramsPerUnit }
    var band: DoseBand { dose.context.band }

    var unitsLabel: String { "\(units) U" }
    /// `5 g/U` — one decimal only when the value has one.
    var ratioLabel: String { Self.gramsPerUnitLabel(gramsPerUnit) }
    var provenanceLabel: String {
        "from \(Int(carbsG.rounded())) g at \(ratioLabel)"
    }

    // Spoken form for VoiceOver labels: "12 U" reads as "twelve you" if the
    // display string is spoken verbatim (ui-ux review 2026-08-25).
    //
    // There is no spoken ratio here. The ratio left every readout line with
    // design-direction §10's device verdict (2026-08-28) and is now stated
    // only in the working, which carries its own spoken form.
    var spokenUnits: String { "\(units) units" }

    /// What the dose sheet opens at, or nil where the dose rounds to `0 U`:
    /// a zero renders its readout and its working but seeds no control
    /// (Req 3.4, 6.4).
    var seed: DoseSeed? {
        guard dose.seedUnits >= 1 else { return nil }
        return DoseSeed(
            units: dose.seedUnits, armedAt: Date(), provenance: provenanceLabel)
    }

    // Shared formatting for the whole-unit dose figures on history surfaces.
    static func wholeUnitsLabel(_ units: Double) -> String {
        MedataFormat.quantity(units, unit: "U")
    }

    static func gramsPerUnitLabel(_ value: Double) -> String {
        MedataFormat.quantity(value, unit: "g/U")
    }
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
    // (design-direction §3.1: provenance appears exactly where the source
    // number is not visible). A quantity and two units — no verb.
    let provenance: String
}

/// The only shared object left (Decision 19). Owned by `AppRoot` and published
/// into the environment, so a seed armed inside the Capture cover survives that
/// cover's dismissal.
@Observable
@MainActor
final class DoseSeedHolder {
    /// Req 11.2 / Req 4.8: the same 45 minutes the retrospective measurement
    /// uses to pair a meal with a bolus, and the same window that marks a bolus
    /// offset by food — one association rule, not three.
    static let seedLifetime: TimeInterval = FoodOffsetWindow.window

    private var seed: DoseSeed?

    func arm(_ seed: DoseSeed) {
        self.seed = seed
    }

    /// Consumed exactly once, and only while fresh. Returning nil is the
    /// ordinary case: the home Dose control and `medata://insulin/add` open at
    /// the sheet's own default, byte for byte as they do today (Req 6.3).
    func take() -> DoseSeed? {
        defer { seed = nil }
        guard let seed, Date().timeIntervalSince(seed.armedAt) <= Self.seedLifetime else {
            return nil
        }
        return seed
    }
}

/// Pure App-layer computation — no state, no observation, nothing written.
/// Fetches the event window through the existing `events(in:type:)` API and
/// calls `DoseSuggester`. One code path, so a live surface and a history
/// recompute cannot disagree (Req 6.11).
enum DoseComputation {

    static func outcome(
        for subject: DoseSubject,
        store: any PersistenceStore,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) async -> DoseOutcome {
        DoseSuggester.suggest(
            DoseInputs(
                carbsG: subject.carbsG,
                mealInstant: subject.instant,
                calendar: calendar,
                ratios: ratioTable(defaults),
                unoffsetIOBUnits: await unoffsetIOB(for: subject, store: store),
                increment: .standard,
                bounds: .doseSheet
            )
        )
    }

    /// The readout a surface renders, or nil where no carbohydrate total exists
    /// (Req 3.5). A computed `0 U` is a readout, not an absence (Req 6.6).
    static func readout(
        for subject: DoseSubject,
        store: any PersistenceStore,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) async -> DoseReadout? {
        let outcome = await outcome(
            for: subject, store: store, defaults: defaults, calendar: calendar)
        guard case .suggested(let dose) = outcome else { return nil }
        return DoseReadout(carbsG: subject.carbsG ?? 0, dose: dose)
    }

    /// The bolus units actually given for a meal (Req 6.10): the same
    /// ±45-minute window that decides whether a bolus is offset by food, read
    /// from the other side. No stored link exists and none is needed.
    static func givenUnits(
        at instant: Date, store: any PersistenceStore
    ) async -> Double? {
        let window = FoodOffsetWindow.window
        let span = instant.addingTimeInterval(-window)...instant.addingTimeInterval(window)
        let units = await boluses(in: span, store: store).map(\.units).reduce(0, +)
        return units > 0 ? units : nil
    }

    // MARK: - Inputs

    // Three queries, all through the existing `events(in:type:)` — no new store
    // API exists or is needed. The bolus span is exactly the duration of
    // action, so it returns only doses that can contribute (Req 4.3); the meal
    // and intake span is that span widened by the association window at BOTH
    // ends, because the ±45-minute test is symmetric (Req 4.8).
    private static func unoffsetIOB(
        for subject: DoseSubject, store: any PersistenceStore
    ) async -> Double {
        let instant = subject.instant
        let boluses = await boluses(in: FoodOffsetWindow.bolusSpan(at: instant), store: store)
        guard !boluses.isEmpty else { return 0 }

        let foodSpan = FoodOffsetWindow.mealOrIntakeSpan(at: instant)
        var instants: [Date] = []
        for type in [EventType.meal, EventType.intake] {
            let rows = (try? await store.events(in: foodSpan, type: type)) ?? []
            // Where the subject is already a recorded event (the history
            // recompute), its own row is dropped: a meal never offsets its own
            // pre-bolus, so the live computation and the recompute agree by
            // construction.
            instants += rows.filter { $0.id != subject.sourceEventID }.map(\.timestamp)
        }

        return unoffsetInsulinOnBoard(boluses, mealOrIntakeInstants: instants, at: instant)
    }

    private static func boluses(
        in span: ClosedRange<Date>, store: any PersistenceStore
    ) async -> [DatedBolus] {
        let rows = (try? await store.events(in: span, type: EventType.insulin)) ?? []
        return rows.compactMap { event in
            guard let units = event.value else { return nil }
            switch classify(event) {
            case .bolus:
                return DatedBolus(instant: event.timestamp, units: units)
            case .basal:
                return nil          // Req 4.2: a CLASSIFIED exclusion.
            case nil:
                // Req 4.9: an unclassifiable event must not vanish from the
                // sum, and `assertionFailure` is a no-op in Release — the very
                // build the developer carries. Counting it raises insulin on
                // board and so LOWERS the suggestion, the only direction a
                // mistake here is safe to make: dropping it would understate
                // insulin already given and suggest too much on top of it.
                return DatedBolus(instant: event.timestamp, units: units)
            }
        }
    }

    // Fail-loud classification (Req 4.9). Basal exclusion is a CLASSIFIED
    // exclusion and returns normally; an event whose metadata cannot be
    // classified at all is a defect — the app writes its own insulin events, so
    // an unclassifiable one is a bug, not data, and it must not simply vanish
    // from the sum. `nil` here means "unclassifiable", NOT "ignore": the caller
    // counts it toward insulin on board. Debug builds trap on it as well.
    private static func classify(_ event: Event) -> InsulinKind? {
        guard
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["kind"] as? String,
            let kind = InsulinKind(rawValue: raw)
        else {
            assertionFailure(
                "insulin event \(event.id) has no classifiable kind (Req 4.9)")
            return nil
        }
        return kind
    }

    // Grams per unit, one direction, read straight from Settings. An absent
    // key leaves the band unconfigured and the seed applies (Req 1.6).
    private static func ratioTable(_ defaults: UserDefaults) -> CarbRatioTable {
        var configured: [DoseBand: CarbRatio] = [:]
        for band in DoseBand.allCases {
            let key = SettingsKeys.ratioKey(for: band)
            guard defaults.object(forKey: key) != nil else { continue }
            if let ratio = CarbRatio(gramsPerUnit: defaults.double(forKey: key)) {
                configured[band] = ratio
            }
        }
        return CarbRatioTable(configured: configured)
    }
}
