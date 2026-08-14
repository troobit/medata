import Foundation

// The dose-suggestion ledger (specs/data/insulin-dosing Req 7, design "The
// ledger"). Rows live in their own `dose_suggestions` table following the
// `quick_presets` / `estimation_outcomes` convention: a DERIVED SIDE STORE,
// separate from the event log (Req 7.3). None of the three store methods
// touches `eventsDidChange` (Req 7.4), and none of them adds, alters or
// extends any key of the insulin event's metadata contract, which medreg owns
// and parses (Req 9.7).
//
// The record lives in Persistence, not in Dosing, so the firewall of Req 10.3
// holds: Persistence does not import Dosing and Dosing does not import
// Persistence. Values produced by Dosing — the suppression reason and the band
// — are therefore carried here as raw strings, exactly as `EstimationOutcome`
// carries its Pipeline-produced JSON opaquely.

// Outcome vocabulary for the `outcome` column. Centralised here so call sites
// cannot typo the literal (`EstimationOutcomeKind` precedent).
public enum DoseSuggestionOutcome: String, Sendable, Equatable, CaseIterable {
    case suggested
    case suppressed
}

// Where the carbohydrate total came from (design "The ledger", `carbs_source`).
// Raw values are the exact column strings.
public enum CarbsSource: String, Sendable, Equatable, CaseIterable {
    case meal
    case mealCorrected = "meal_corrected"
    case intake
    case quickPreset = "quick_preset"
}

// Provenance of the carbohydrate ratio a suggestion used (Req 9.4). `seed` is a
// shipped default, `manual` a hand-chosen Settings value, `medreg` a value
// transcribed from a medreg fit (with `crFitRef` naming that fit). `backfill`
// is reserved for the retrospective scoring script of design "Testing"; nothing
// in iteration 1 writes it.
public enum RatioSource: String, Sendable, Equatable, CaseIterable {
    case seed
    case manual
    case medreg
    case backfill
}

// One recorded dose suggestion — made or suppressed. A suppression is recorded
// as fully as a suggestion (Req 7.1): `band`, the hours, the offset, the ratio
// and the insulin-on-board are all present either way, and only the units are
// nil.
//
// `fpu` is DERIVED BY THE STORE at save from `fatG` and `proteinG`
// (`BenchmarkMeal.truthCarbsG` precedent): the value carried by a record passed
// to `saveDoseSuggestion` is ignored and the stored figure is authoritative.
// Storing it rather than deriving it on read means a later change to the
// formula cannot silently reinterpret old rows.
public struct DoseSuggestionRecord: Sendable, Equatable, Identifiable {
    // Shape version of the row itself (Req 7.8) — distinct from `ruleVersion`,
    // which versions the arithmetic that produced the numbers (Req 7.9).
    public static let currentRowVersion = 1

    // (fat_g × 9 + protein_g × 4) / 100, the fat-protein unit. Nil when either
    // input is absent: an absent macro is unrecorded, not zero, and inventing a
    // zero would make a fat-free reading indistinguishable from an unmeasured
    // one.
    public static func fatProteinUnits(fatG: Double?, proteinG: Double?) -> Double? {
        guard let fatG, let proteinG else { return nil }
        return (fatG * 9 + proteinG * 4) / 100
    }

    public let id: UUID
    public let timestampMs: Int64  // when computed, UTC ms
    public let mealTimestampMs: Int64  // the instant that selected the band
    public let rowVersion: Int
    public let ruleID: String  // "cr-v0"
    public let ruleVersion: Int
    public let fatRuleID: String?  // nil until a fat strategy ships (Req 8.5)
    public let fatRuleVersion: Int?
    public let outcome: String  // DoseSuggestionOutcome raw value
    public let suppression: String?  // Dosing's SuppressionReason raw value
    public let carbsG: Double?
    public let carbsSource: String  // CarbsSource raw value
    public let sourceEventID: UUID?
    public let exactUnits: Double?  // unrounded (Req 5.3)
    public let roundedUnits: Double?
    public let incrementU: Double
    public let seedClamped: Bool
    public let crGramsPerUnit: Double  // the ratio in g/U (Req 1.7)
    public let crSource: String  // RatioSource raw value
    public let crFitRef: String?
    public let band: String  // Dosing's DoseBand raw value
    public let localHour: Int
    public let utcHour: Int
    public let utcOffsetS: Int
    public let iobU: Double
    public let sigmaMeal: Double?
    public let startBgMmol: Double?
    public let startBgAgeS: Int?
    public let fatG: Double?
    public let proteinG: Double?
    public let fpu: Double?  // derived at save; see above
    public let fatStale: Bool
    public let givenUnits: Double?  // filled by linkDose (Req 7.5)
    public let insulinEventID: UUID?
    public let buildStamp: String

    public init(
        id: UUID = UUID(),
        timestampMs: Int64,
        mealTimestampMs: Int64,
        rowVersion: Int = DoseSuggestionRecord.currentRowVersion,
        ruleID: String,
        ruleVersion: Int,
        fatRuleID: String? = nil,
        fatRuleVersion: Int? = nil,
        outcome: String,
        suppression: String? = nil,
        carbsG: Double?,
        carbsSource: String,
        sourceEventID: UUID? = nil,
        exactUnits: Double? = nil,
        roundedUnits: Double? = nil,
        incrementU: Double,
        seedClamped: Bool,
        crGramsPerUnit: Double,
        crSource: String,
        crFitRef: String? = nil,
        band: String,
        localHour: Int,
        utcHour: Int,
        utcOffsetS: Int,
        iobU: Double,
        sigmaMeal: Double? = nil,
        startBgMmol: Double? = nil,
        startBgAgeS: Int? = nil,
        fatG: Double? = nil,
        proteinG: Double? = nil,
        fpu: Double? = nil,
        fatStale: Bool = false,
        givenUnits: Double? = nil,
        insulinEventID: UUID? = nil,
        buildStamp: String
    ) {
        self.id = id
        self.timestampMs = timestampMs
        self.mealTimestampMs = mealTimestampMs
        self.rowVersion = rowVersion
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.fatRuleID = fatRuleID
        self.fatRuleVersion = fatRuleVersion
        self.outcome = outcome
        self.suppression = suppression
        self.carbsG = carbsG
        self.carbsSource = carbsSource
        self.sourceEventID = sourceEventID
        self.exactUnits = exactUnits
        self.roundedUnits = roundedUnits
        self.incrementU = incrementU
        self.seedClamped = seedClamped
        self.crGramsPerUnit = crGramsPerUnit
        self.crSource = crSource
        self.crFitRef = crFitRef
        self.band = band
        self.localHour = localHour
        self.utcHour = utcHour
        self.utcOffsetS = utcOffsetS
        self.iobU = iobU
        self.sigmaMeal = sigmaMeal
        self.startBgMmol = startBgMmol
        self.startBgAgeS = startBgAgeS
        self.fatG = fatG
        self.proteinG = proteinG
        self.fpu = fpu
        self.fatStale = fatStale
        self.givenUnits = givenUnits
        self.insulinEventID = insulinEventID
        self.buildStamp = buildStamp
    }
}
