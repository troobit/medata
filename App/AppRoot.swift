import CaptureKit
import Persistence
import SwiftUI

// Home-rooted shell (home-router Req §1, superseding design-handoff-00
// Decision 20's Graph root). The launch root is `HomeView`, a pure router:
// Capture, Intake, Records, Graph, and Settings present as mutually-exclusive
// full-screen covers over it via a single optional `ActiveSheet` (Decision 19
// — full screens, not sheets); Dose stays the plain insulin `.sheet`
// (Decision 10) so `medata://insulin/add` and the home Dose control target the
// same surface. `HomeView` holds no presentation state — its controls fire the
// closures injected here (Decision 9). The AR session runs ONLY while the
// Capture cover is presented: presenting `.capture` arms it
// (`capturePresented`); any other value releases it (`captureDismissed`) — so
// at launch (home root) the camera stays off and no permission prompt fires
// (Req 1.5). Each cover carries its own explicit `Close` control (Req 1.4).
@MainActor
struct AppRoot: View {
    @Bindable var captureModel: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let glucoseConnections: GlucoseConnectionsModel
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?
    // Set by the ADJUST notification action, which is `.foreground` and so
    // arrives with the app coming to the front (dose-schedule Decision 2).
    let adjustRouter: DoseAdjustRouter

    @State private var activeSheet: ActiveSheet?
    // The insulin dose sheet is a plain sheet, not a cover (Decision 10),
    // presented directly from this root so the home Dose control and the
    // `medata://insulin/add` deep link raise the same surface from any app
    // state (PRD regression-suggestion-integration App 10). `pendingDeepLink`
    // defers a deep-linked present until the conflicting presentation's
    // dismissal completes.
    @State private var showInsulinSheet = false
    // The activity-entry sheet (specs/data/activity-events Req 3), the same
    // plain-sheet weight as the dose sheet and owned here for the same reason:
    // the home Activity control and `medata://activity/add` raise one surface
    // from any app state.
    @State private var showActivitySheet = false
    @State private var pendingDeepLink: DeepLinkTarget?
    // The home page's latest-reading header (Req 4). Owned here rather than by
    // HomeView so the subscription survives every cover present/dismiss —
    // HomeView is rebuilt on each of those, and a @State inside it would
    // re-subscribe every time.
    @State private var homeGlucose: HomeGlucoseModel
    // The dose schedule (specs/data/dose-schedule). Owned here for the same
    // reason `homeGlucose` is: HomeView is rebuilt on every cover
    // present/dismiss, and the outstanding set must survive that.
    @State private var doseSchedule: DoseScheduleModel
    // Which outstanding dose the pre-seeded sheet is adjusting, if any. The
    // sheet writes the insulin event; this is what tells the schedule which
    // occurrence that event discharges (Req 5.2).
    @State private var adjustingDose: OutstandingDose?
    // Set by the outstanding-dose gear before presenting `.settings`, so the
    // cover lands on the dose-schedule section rather than the top of the Form.
    // Reset on dismiss so a plain Settings open is unaffected.
    @State private var settingsOpensAtDoseSchedule = false
    @Environment(\.scenePhase) private var scenePhase

    // Owned here, as `DoseSuggestionModel`'s own header states, so a seed
    // armed inside the Capture cover survives that cover's dismissal, and
    // injected into the environment so the entry surfaces read one instance.
    @State private var doseSuggestions: DoseSuggestionModel
    // Read at the moment the sheet is raised, never inside the sheet builder:
    // `takeSeed()` consumes the seed, and consuming it during a view update
    // would be a state mutation mid-body.
    @State private var pendingSeed: DoseSeed?

    // The deep links under the `medata` scheme — each a single-tap lock-screen
    // widget target (PRD amendment to App 10; glucose-lock-widget Req 7.1).
    private enum DeepLinkTarget {
        case insulinSheet  // medata://insulin/add
        case activitySheet  // medata://activity/add
        case captureCover  // medata://capture
        case graphCover  // medata://graph — the glucose widget's tap target
    }

    init(
        captureModel: CaptureFlowModel,
        engine: ARKitCaptureEngine,
        store: any PersistenceStore,
        glucoseConnections: GlucoseConnectionsModel,
        visionCardDetector: VisionCardDetector? = nil,
        preShutterSegmenter: PreShutterSegmenter? = nil,
        adjustRouter: DoseAdjustRouter
    ) {
        self.captureModel = captureModel
        self.engine = engine
        self.store = store
        self.glucoseConnections = glucoseConnections
        self.visionCardDetector = visionCardDetector
        self.preShutterSegmenter = preShutterSegmenter
        self.adjustRouter = adjustRouter
        _homeGlucose = State(initialValue: HomeGlucoseModel(store: store))
        _doseSchedule = State(initialValue: DoseScheduleModel(store: store))
        _doseSuggestions = State(initialValue: DoseSuggestionModel(store: store))
    }

    // A single optional so the covers are mutually exclusive by construction —
    // dismiss-then-present is sequential, so the AR session never
    // double-toggles (design: Shell re-root). `.intake` presents the
    // `manual-carb-intake`-owned IntakeView (Decision 12).
    enum ActiveSheet: Identifiable {
        case capture
        case intake
        case records
        case graph
        case settings

        var id: Self { self }
    }

    var body: some View {
        HomeView(
            glucose: homeGlucose,
            outstandingDoses: doseSchedule.outstanding,
            onLogDose: { dose in Task { await doseSchedule.logNominal(dose) } },
            onAdjustDose: { dose in
                adjustingDose = dose
                showInsulinSheet = true
            },
            onScheduleSettings: {
                settingsOpensAtDoseSchedule = true
                activeSheet = .settings
            },
            surfaceStyle: doseSchedule.surfaceStyle,
            onCapture: {
                // The benchmark tag must not survive into a non-benchmark
                // capture — clear it here in case a deferred benchmark
                // present was dropped and left it set.
                captureModel.benchmarkMealID = nil
                activeSheet = .capture
            },
            onIntake: { activeSheet = .intake },
            onDose: { presentInsulinSheet() },
            onActivity: { showActivitySheet = true },
            onRecords: { activeSheet = .records },
            onGraph: { activeSheet = .graph },
            onSettings: { activeSheet = .settings }
        )
        .tint(.medataAccent)
        .environment(doseSuggestions)
        .fullScreenCover(item: $activeSheet, onDismiss: {
            settingsOpensAtDoseSchedule = false
            // A deep-linked present waits for the cover's dismissal to
            // finish; presenting mid-animation is silently dropped by SwiftUI.
            switch pendingDeepLink {
            case .insulinSheet:
                presentInsulinSheet()
            case .activitySheet:
                showActivitySheet = true
            case .captureCover:
                activeSheet = .capture
            case .graphCover:
                activeSheet = .graph
            case nil:
                break
            }
            pendingDeepLink = nil
        }) { sheet in
            switch sheet {
            case .capture:
                CaptureFlowView(
                    model: captureModel,
                    engine: engine,
                    store: store,
                    visionCardDetector: visionCardDetector,
                    preShutterSegmenter: preShutterSegmenter
                )
            case .intake:
                IntakeView(store: store)
            case .records:
                RecordsView(store: store)
            case .graph:
                TrendsView(store: store)
            case .settings:
                NavigationStack {
                    SettingsView(
                        store: store,
                        doseSchedule: doseSchedule,
                        hasLiDAR: captureModel.supportsLiDAR,
                        glucoseConnections: glucoseConnections,
                        captureLineage: captureModel.segmenterSource,
                        onBenchmarkCapture: { mealID in
                            // Benchmark capture launch (snaq-parity lane B):
                            // tag the model BEFORE the capture route presents,
                            // then reuse the deep-link sequencing — Settings
                            // must finish dismissing before Capture can
                            // present (the covers are mutually exclusive).
                            captureModel.benchmarkMealID = mealID
                            pendingDeepLink = .captureCover
                            activeSheet = nil
                        },
                        scrollToDoseSchedule: settingsOpensAtDoseSchedule
                    )
                }
            }
        }
        // Relocated from TrendsView (Decision 10): the dose sheet keeps its
        // native drag-to-dismiss (no CloseCoverButton — design: Cover
        // vocabulary). `onDismiss` sequences a pending cover present behind the
        // sheet's dismissal — every cover target, not just capture: a glucose
        // widget tap arriving while this sheet is up would otherwise be set and
        // then silently discarded (glucose-lock-widget design, Deep link).
        .sheet(isPresented: $showInsulinSheet, onDismiss: {
            adjustingDose = nil
            switch pendingDeepLink {
            case .captureCover:
                pendingDeepLink = nil
                activeSheet = .capture
            case .graphCover:
                pendingDeepLink = nil
                activeSheet = .graph
            case .activitySheet:
                pendingDeepLink = nil
                showActivitySheet = true
            case .insulinSheet, nil:
                break
            }
        }) {
            // Pre-seeded two ways and still one surface: the schedule's nominal
            // amount when an outstanding dose is being adjusted (dose-schedule
            // Req 5.1), the armed suggestion otherwise. No schedule-specific
            // control is added — only where `units` starts and who is told
            // about the saved event.
            LogSheet(
                store: store,
                mode: .insulin,
                seedUnits: adjustingDose?.nominalUnits,
                seedKind: adjustingDose?.schedule.kind,
                seed: pendingSeed,
                onInsulinSaved: { eventID in
                    guard let dose = adjustingDose else { return }
                    Task {
                        await doseSchedule.recordAdjusted(dose, insulinEventID: eventID)
                    }
                }
            )
        }
        // The activity mode of the same sheet resumes a pending target exactly
        // as the insulin mode above does — one surface, so a deep link
        // arriving while either mode is up must survive the dismissal
        // (specs/data/activity-events Req 3.5).
        .sheet(isPresented: $showActivitySheet, onDismiss: {
            switch pendingDeepLink {
            case .captureCover:
                pendingDeepLink = nil
                activeSheet = .capture
            case .graphCover:
                pendingDeepLink = nil
                activeSheet = .graph
            case .insulinSheet:
                pendingDeepLink = nil
                presentInsulinSheet()
            case .activitySheet, nil:
                break
            }
        }) {
            LogSheet(store: store, mode: .activity)
        }
        .onChange(of: activeSheet) { old, new in
            // The AR session runs only while Capture is the frontmost cover.
            if new == .capture {
                captureModel.capturePresented()
            } else {
                captureModel.captureDismissed()
                // The benchmark flow ends when the Capture cover closes.
                // Cleared only on a capture → elsewhere transition so the tag
                // survives the Settings-dismiss → Capture-present handoff the
                // benchmark launch above sequences (that transition is
                // settings → nil, which must not clear it).
                if old == .capture { captureModel.benchmarkMealID = nil }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        // The lazy pass of design.md section 5. Occurrences open, the
        // missed-successor rule runs and the notification plan is rebuilt when
        // something LOOKS — never on a timer and never on a background task,
        // because the CGM `BGAppRefreshTask` already spends that budget.
        .task { await doseSchedule.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await doseSchedule.refresh() }
            }
        }
        .onChange(of: adjustRouter.pending) { _, pending in
            guard let pending else { return }
            adjustRouter.pending = nil
            presentAdjust(for: pending)
        }
    }

    // The ADJUST action arrives with the app coming to the front. Route it
    // through the same `pendingDeepLink` resume every other deep link uses, so
    // landing during a dismissing presentation is not silently dropped
    // (docs/agent-notes/insulin-dose-ui.md).
    private func presentAdjust(for pending: PendingDoseAdjust) {
        adjustingDose = doseSchedule.outstanding.first {
            $0.schedule.id == pending.scheduleID
        }
        if activeSheet == nil {
            showInsulinSheet = true
        } else {
            pendingDeepLink = .insulinSheet
            activeSheet = nil
        }
    }

    // The `medata` scheme is registered in MeData/Info.plist (CFBundleURLTypes;
    // merged with the generated Info.plist). Both links land on their target
    // from any state, dismissing whatever is presented first (App 10):
    //   medata://insulin/add  — the dose-entry sheet
    //   medata://activity/add — the activity-entry sheet
    //                           (specs/data/activity-events Req 3.5)
    //   medata://capture      — the Capture cover
    //   medata://graph        — the Graph cover (glucose widget tap, Req 7.1).
    //                           From a locked device iOS defers the open until
    //                           the user authenticates, then `onOpenURL` fires
    //                           here as usual (Req 7.2) — nothing extra needed.
    // The two entry sheets are mutually exclusive in practice, so each link
    // dismisses the other one first and resumes through `pendingDeepLink`;
    // presenting a sheet over a sheet that is animating out is dropped.
    // Req 6.4: the sheet opens on the armed suggestion where one is in force
    // and at the standing default otherwise. `takeSeed()` returns nil once the
    // seed's 45 minutes have lapsed, so both two-tap paths are unchanged when
    // nothing is armed.
    private func presentInsulinSheet() {
        pendingSeed = doseSuggestions.takeSeed()
        showInsulinSheet = true
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "medata" else { return }
        switch (url.host, url.path) {
        case ("insulin", "/add"):
            if showActivitySheet {
                pendingDeepLink = .insulinSheet
                showActivitySheet = false
            } else if activeSheet == nil {
                presentInsulinSheet()
            } else {
                pendingDeepLink = .insulinSheet
                activeSheet = nil
            }
        case ("activity", "/add"):
            if showInsulinSheet {
                pendingDeepLink = .activitySheet
                showInsulinSheet = false
            } else if activeSheet == nil {
                showActivitySheet = true
            } else {
                pendingDeepLink = .activitySheet
                activeSheet = nil
            }
        case ("capture", ""), ("capture", "/"):
            if showInsulinSheet {
                pendingDeepLink = .captureCover
                showInsulinSheet = false
            } else if showActivitySheet {
                pendingDeepLink = .captureCover
                showActivitySheet = false
            } else if activeSheet == nil {
                activeSheet = .capture
            } else if activeSheet != .capture {
                pendingDeepLink = .captureCover
                activeSheet = nil
            }
        case ("graph", ""), ("graph", "/"):
            if showInsulinSheet {
                pendingDeepLink = .graphCover
                showInsulinSheet = false
            } else if showActivitySheet {
                pendingDeepLink = .graphCover
                showActivitySheet = false
            } else if activeSheet == nil {
                activeSheet = .graph
            } else if activeSheet != .graph {
                pendingDeepLink = .graphCover
                activeSheet = nil
            }
        default:
            break
        }
    }
}
