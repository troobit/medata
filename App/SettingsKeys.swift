import Dosing
import Foundation
import Persistence

// UserDefaults keys kept in a single namespace to avoid stringly-typed access.
// `captureMode` is the persistent toggle introduced by Decision 35.
// IFCDB and retention keys removed per Decisions 37 and 39: photo lifecycle is
// delegated to PhotoKit (Req §17.3); macros source is fixed at CoFID + AFCD
// with no user-facing override (Req §11.1).
// The `InsulinProduct` helper at the foot of this file is `nonisolated` for
// the same reason: the dose-schedule notification handler resolves the product
// string with the app not running.
//
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
    // Activity metric chip: show/hide the activity band on the Graph chart
    // (specs/data/activity-events Req 4.1).
    static let trendsShowActivity = "medata.trends.showActivity"

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
    // beside the field. An absent key means the seed default is in force
    // (Req 1.6). Flat keys of the same kind as
    // `insulinTypeBolus` — no structured or array-valued setting is
    // introduced.
    static let ratioOvernightGPerU = "medata.insulin.ratio.overnight"
    static let ratioBreakfastGPerU = "medata.insulin.ratio.breakfast"
    static let ratioLunchGPerU = "medata.insulin.ratio.lunch"
    static let ratioDinnerGPerU = "medata.insulin.ratio.dinner"
    // The dosable increment is fixed at 1 U (Req 5.1, Decision 17), so it has
    // no key and no control. A stale stored `medata.insulin.dosableIncrement`
    // value is simply never read again — no code references it and no
    // migration removes it.
    //
    // Provenance of the configured ratios: "manual" | "medreg" (Req 9.4); a
    // band with an absent per-band key runs on its seed default regardless.
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

    // Most recently saved activity kind (specs/data/activity-events Req 3.3),
    // stored as the kind's stable machine key so the entry sheet opens on it
    // and a repeat activity is a two-tap save. Written by ActivityModel on a
    // successful save only.
    static let activityLastKind = "medata.activity.lastKind"

    // The recurring dose schedule (specs/data/dose-schedule Req 1.1). A
    // Codable `[ScheduledDose]` array, JSON-encoded — configuration, not a
    // table, because a scheduled dose holds no history (design.md section 4).
    static let doseSchedules = "medata.doseSchedule.schedules"
    // One-shot seed marker (Req 1.2), the `quick_presets_seeded` idiom: the two
    // standing entries are written at most once per install, so a developer who
    // deletes both does not have them return on the next launch. An empty
    // schedule is a valid state and the whole feature is inert in it (Req 1.7).
    static let doseSchedulesSeeded = "medata.doseSchedule.seeded"
    // The repeat interval I and follow-up count K (Reqs 3.2, 3.3), seeded at 30
    // minutes and 4. Reasoned, not measured — the UI must not present them as
    // recommended values.
    static let doseReminderIntervalMinutes = "medata.doseSchedule.intervalMinutes"
    static let doseReminderFollowUps = "medata.doseSchedule.followUps"
    // Notification authorisation is asked for at most once, when the developer
    // first enables a scheduled dose, and never at launch (Req 7.1). This
    // records that the ask happened so a refusal is never re-prompted (Req 7.2);
    // the live grant/deny state is read from `notificationSettings`, never
    // cached here, so a revocation in system Settings is picked up on the next
    // foreground.
    static let doseNotificationAsked = "medata.doseSchedule.notificationAsked"
    // Which of the two in-app surfaces is showing (specs/data/dose-schedule UI
    // attempts 1 and 2). A developer-phase comparison switch, not a feature.
    static let doseSurfaceStyle = "medata.doseSchedule.surfaceStyle"

    // How long a blood reading outranks a newer sensor reading, in seconds
    // (specs/data/fingerprick-glucose Req 3.2). Deliberately APP-PRIVATE and
    // not App Group state (Decision 8): the widget extension never reads the
    // window, because the snapshot carries the resolved `holdsUntil` as an
    // absolute date instead. Seconds, so `GlucoseHoldWindow` hands a
    // `TimeInterval` straight to the derivation without a unit conversion in
    // between; the Settings control renders minutes.
    static let glucoseHoldWindowSeconds = "medata.glucose.holdWindowSeconds"
}

// The hold window, read from wherever it is needed (Req 3.2).
//
// `nonisolated` for the `InsulinProduct` reason above: `GlucoseWidgetPublisher`
// is an actor and deliberately not `@MainActor`, so it cannot reach a
// main-actor-isolated constant. Both it and `HomeGlucoseModel` read THIS, which
// is what makes Req 3.7's "same reading on every surface" structural rather
// than a matter of keeping two literals in step.
nonisolated enum GlucoseHoldWindow {
    // 15 minutes (Decision 3), chosen so a reading held to the end of the
    // window reaches exactly the boundary at which the staleness ladder begins
    // de-emphasising it.
    static let defaultSeconds: TimeInterval = 900

    // The range the Settings control offers. Zero is a valid setting — it
    // disables the hold outright — so an absent key cannot be detected with
    // `UserDefaults.double(forKey:)`, which returns 0 for both.
    static let rangeSeconds: ClosedRange<TimeInterval> = 0...(60 * 60)

    static func seconds(_ defaults: UserDefaults = .standard) -> TimeInterval {
        guard let stored = defaults.object(forKey: SettingsKeys.glucoseHoldWindowSeconds) as? Double
        else { return defaultSeconds }
        return min(max(stored, rangeSeconds.lowerBound), rangeSeconds.upperBound)
    }
}

// The per-kind product string every insulin write needs (PRD
// regression-suggestion-integration App 5). Lifted out of `InsulinDoseModel`
// when the dose schedule gained a second writer: the notification handler
// records a dose with the app not running, so this must be reachable without a
// main-actor context and without the sheet's view-model existing.
nonisolated enum InsulinProduct {
    static func name(for kind: InsulinKind) -> String {
        let key: String
        let fallback: String
        switch kind {
        case .bolus:
            key = SettingsKeys.insulinTypeBolus
            fallback = SettingsKeys.insulinTypeBolusDefault
        case .basal:
            key = SettingsKeys.insulinTypeBasal
            fallback = SettingsKeys.insulinTypeBasalDefault
        }
        let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? fallback : stored
    }
}
