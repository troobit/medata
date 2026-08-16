import GlucoseWidgetShared
import Persistence
import SwiftUI

// The home page — launch root and the app's router (home-router Req 1). It
// carries exactly one piece of data, the latest glucose reading (Req 4,
// Decision 15, narrowing Decision 2's pure-router rule); everything else is a
// route. No presentation state of its own — each control fires a closure
// injected by AppRoot, which owns the cover/sheet state (Decision 9). Capture
// is the primary action (Req 1.3), accent-prominent per the established
// capture treatment.
// NOTE: sizing/`contentShape` live INSIDE each Button label — a Button's tap
// gesture covers only its label, so outside modifiers draw a dead surface
// (ui-capture-flow.md gotcha).
struct HomeView: View {
    let glucose: HomeGlucoseModel
    // The outstanding-dose surface (specs/data/dose-schedule Req 2.4, 4.5).
    // Empty when nothing is due, which is most of the day and is also the whole
    // of the feature's inert state when no schedule is defined (Req 1.7).
    var outstandingDoses: [OutstandingDose] = []
    var onLogDose: (OutstandingDose) -> Void = { _ in }
    var onAdjustDose: (OutstandingDose) -> Void = { _ in }
    var onSkipDose: (OutstandingDose) -> Void = { _ in }
    // Which of the two attempts is showing. A developer-phase comparison
    // switch, not a preference.
    var surfaceStyle: DoseScheduleSettings.SurfaceStyle = .banner
    let onCapture: () -> Void
    let onIntake: () -> Void
    let onDose: () -> Void
    let onActivity: () -> Void
    let onRecords: () -> Void
    let onGraph: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("MeData")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            glucoseHeader
            outstandingDoseSection
            Spacer()
            captureButton
            routeButton("Intake", systemImage: "fork.knife", identifier: "home.intake", action: onIntake)
            // `doseRoute` rather than a plain Dose button: dose-schedule
            // attempt 2 repurposes this control as the discharge action while a
            // dose is outstanding (see below).
            doseRoute
            // Activity sits beside Dose because it is the same kind of control:
            // a plain sheet raised over home, not a cover
            // (specs/data/activity-events Req 3.1).
            routeButton("Activity", systemImage: "figure.run", identifier: "home.activity", action: onActivity)
            routeButton("Records", systemImage: "square.stack.3d.up", identifier: "home.records", action: onRecords)
            routeButton("Graph", systemImage: "chart.xyaxis.line", identifier: "home.graph", action: onGraph)
            routeButton("Settings", systemImage: "gearshape.fill", identifier: "home.settings", action: onSettings)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
        .task { await glucose.start() }
    }

    // The two attempts at the outstanding-dose surface, switchable in Settings
    // so both can be seen on one build (specs/data/dose-schedule; tags
    // `dose-schedule-ui-attempt-1` and `-2`).
    //
    // Both read the LEDGER, not a notification: the surface appears because an
    // occurrence is open, not because a notification was delivered or seen,
    // which is what makes the refused-authorisation path (Req 7.2) the same
    // feature rather than a degraded one.

    // Attempt 1: a dedicated card per outstanding dose, above every route.
    @ViewBuilder
    private var outstandingDoseSection: some View {
        if surfaceStyle == .banner {
            ForEach(outstandingDoses) { dose in
                OutstandingDoseBanner(
                    dose: dose,
                    onLog: { onLogDose(dose) },
                    onAdjust: { onAdjustDose(dose) },
                    onSkip: { onSkipDose(dose) }
                )
            }
        }
    }

    // Attempt 2: the Dose route itself becomes the discharge control while a
    // dose is outstanding. Home keeps the same shape either way; the control
    // changes what it does. With more than one dose outstanding the oldest
    // takes the control and the rest wait, which is the honest limit of not
    // adding a surface.
    @ViewBuilder
    private var doseRoute: some View {
        if surfaceStyle == .doseRoute, let dose = outstandingDoses.first {
            OutstandingDoseControl(
                dose: dose,
                onLog: { onLogDose(dose) },
                onAdjust: { onAdjustDose(dose) },
                onSkip: { onSkipDose(dose) }
            )
        } else {
            routeButton(
                "Dose", systemImage: "syringe", identifier: "home.dose",
                action: onDose
            )
        }
    }

    // The most recent reading, the one thing on home that is not a route
    // (Req 4.1). `TimelineView(.periodic)` re-evaluates once a minute so the
    // age label ages while the page is open — the snapshot itself only changes
    // when a `bsl` row lands, which the model handles.
    private var glucoseHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            glucoseReadout(at: context.date)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("home.glucose")
    }

    // Unlike the lock-screen widget — which drops the number past 30 minutes
    // because a glanceable surface carries no context — home always shows the
    // most recent value and states its age beside it (Req 4.2, Decision 15).
    // The freshness ladder still governs the two *derived* signals: past
    // `staleAge` neither the trend arrow nor the band colour is shown, because
    // neither describes the present any more (Req 4.4).
    @ViewBuilder
    private func glucoseReadout(at date: Date) -> some View {
        if let mmolL = glucose.snapshot.mmolL, let readingDate = glucose.snapshot.readingDate {
            // A reading timestamped ahead of the device clock is skew, not a
            // prediction — clamp to zero, as GlucoseTimeline.render does.
            let age = max(0, date.timeIntervalSince(readingDate))
            let isFresh = age <= GlucoseTimeline.staleAge
            // Value, arrow and unit share ONE baseline; the age is a quiet
            // second line under all three. The unit and age were previously a
            // VStack baselined against the 44 pt number, which pushed the age
            // below the number's block and read as vertically offset.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", mmolL))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundStyle(isFresh ? tint(glucose.snapshot.status) : Color.textSecondary)
                        .contentTransition(.numericText())
                    if isFresh, let trend = glucose.snapshot.trend {
                        Text(trend.arrow)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tint(glucose.snapshot.status))
                            .accessibilityLabel(trendLabel(trend))
                    }
                    Text("mmol/L")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(ageLabel(age))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        } else {
            // Never recorded, or nothing inside the 24-hour horizon. A dash,
            // no explanatory copy (developer-phase no-disclaimer rule).
            Text("—")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .accessibilityLabel("No glucose reading")
        }
    }

    // Whole minutes for the first hour, whole hours beyond — the widget's
    // wording (GlucoseTimeline.ageString), spelled out for an in-app surface
    // that has the width for it.
    private func ageLabel(_ age: TimeInterval) -> String {
        if age < 60 { return "just now" }
        if age < 3600 { return "\(Int(age / 60)) min ago" }
        let hours = Int(age / 3600)
        return "\(hours) h ago"
    }

    // Colour is a secondary channel here as on the widget: the number carries
    // the reading, the tint only flags an out-of-band value.
    private func tint(_ status: GlucoseBandStatus?) -> Color {
        switch status {
        case .low: return Color(uiColor: .systemRed)
        case .high: return Color(uiColor: .systemOrange)
        case .inRange, nil: return Color.textPrimary
        }
    }

    private func trendLabel(_ trend: GlucoseTrend) -> String {
        switch trend {
        case .fallingFast: return "falling fast"
        case .falling: return "falling"
        case .fallingSlow: return "falling slowly"
        case .steady: return "steady"
        case .risingSlow: return "rising slowly"
        case .rising: return "rising"
        case .risingFast: return "rising fast"
        }
    }

    // The primary action (Req 1.3): the largest control, accent-filled via the
    // same `.borderedProminent` + `.tint(.medataAccent)` treatment the old
    // Graph-toolbar capture control carried. Dark foreground on the bright
    // accent, matching the metric-chip idiom.
    private var captureButton: some View {
        Button(action: onCapture) {
            Label("Capture", systemImage: "camera.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.captureBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.medataAccent)
        .accessibilityIdentifier("home.capture")
    }

    // The six secondary routes: one consistent full-width treatment on the
    // elevated surface (statCard idiom).
    private func routeButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
