// UserDefaults keys kept in a single namespace to avoid stringly-typed access.
// `captureMode` is the persistent toggle introduced by Decision 35.
// IFCDB and retention keys removed per Decisions 37 and 39: photo lifecycle is
// delegated to PhotoKit (Req §17.3); macros source is fixed at CoFID + AFCD
// with no user-facing override (Req §11.1).
// `nonisolated` because the project sets
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise make this
// file-scope enum and its static constants implicitly MainActor-isolated.
// `defaultCaptureModeReader` (App/CaptureFlowModel.swift) is `nonisolated` and
// reads `captureMode`, so the keys must be reachable from any context. Plain
// string constants are inherently thread-safe.
nonisolated enum SettingsKeys {
    static let captureMode = "medata.captureMode"
    // Fork sheet §3.2 / Settings §12.1: the persistent "always include a
    // reference card" default. The fork-sheet card toggle seeds from this; a
    // per-capture override lives on CaptureFlowModel and does not write here.
    static let alwaysIncludeCard = "medata.alwaysIncludeCard"

    // Trends graph-options (design-handoff-00 §10.8). Persisted via @AppStorage
    // so the options sheet and the chart share one source of truth.
    static let trendsShowCarbs = "medata.trends.showCarbs"
    static let trendsShowGlucose = "medata.trends.showGlucose"
    static let trendsShowTargetBand = "medata.trends.showTargetBand"
    // Glucose y-scale: false = Auto, true = Fixed at `trendsFixedMax` mmol/L.
    static let trendsScaleFixed = "medata.trends.scaleFixed"
    static let trendsFixedMax = "medata.trends.fixedMax"
    // Insulin metric chip: show/hide the dose markers on the Graph chart
    // (PRD regression-suggestion-integration App 9).
    static let trendsShowInsulin = "medata.trends.showInsulin"

    // Per-kind insulin product defaults (PRD regression-suggestion-integration
    // App 5). Free-text editable in Settings; the dose sheet reads them at
    // save time and never asks for the product. The `…Default` constants are
    // the fallbacks when a key is unset or cleared to whitespace.
    static let insulinTypeBolus = "medata.insulin.bolusType"
    static let insulinTypeBasal = "medata.insulin.basalType"
    static let insulinTypeBolusDefault = "NovoRapid"
    static let insulinTypeBasalDefault = "Lantus"

    // Per-band carbohydrate ratios in GRAMS PER UNIT — grams of carbohydrate
    // covered by one unit of insulin (specs/data/insulin-dosing Req 1.1). The
    // reciprocal direction is NEVER stored; Settings renders it read-only
    // beside the field. An absent key means the seed default is in force and
    // the suggestion row records that (Req 1.6). Flat keys of the same kind as
    // `insulinTypeBolus` — no structured or array-valued setting is
    // introduced.
    static let ratioOvernightGPerU = "medata.insulin.ratio.overnight"
    static let ratioBreakfastGPerU = "medata.insulin.ratio.breakfast"
    static let ratioLunchGPerU = "medata.insulin.ratio.lunch"
    static let ratioDinnerGPerU = "medata.insulin.ratio.dinner"
    // Pen increment in units: 0.5 or 1.0 (Req 5.1, 5.6).
    static let dosableIncrementU = "medata.insulin.dosableIncrement"
    // Provenance of the configured ratios: "manual" | "medreg" (Req 9.4); an
    // absent per-band key overrides this with "seed" on that band's rows.
    static let ratioSource = "medata.insulin.ratioSource"
    // Free text naming the medreg fit the values came from, e.g. an export
    // date or run label. Recorded verbatim, never parsed (Req 9.4).
    static let ratioFitRef = "medata.insulin.ratioFitRef"

    static func ratioKey(for band: DoseBand) -> String {
        switch band {
        case .overnight: ratioOvernightGPerU
        case .breakfast: ratioBreakfastGPerU
        case .lunch: ratioLunchGPerU
        case .dinner: ratioDinnerGPerU
        }
    }

    // Most recently saved activity kind, so the entry sheet opens on it and a
    // repeat activity is open -> Save (specs/data/activity-events Req 3.3).
    static let activityLastKind = "medata.activity.lastKind"
    // Activity metric chip: show/hide the activity band on the Graph chart.
    static let trendsShowActivity = "medata.trends.showActivity"
}
