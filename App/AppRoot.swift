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
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?

    @State private var activeSheet: ActiveSheet?
    // The insulin dose sheet is a plain sheet, not a cover (Decision 10),
    // presented directly from this root so the home Dose control and the
    // `medata://insulin/add` deep link raise the same surface from any app
    // state (PRD regression-suggestion-integration App 10). `pendingDeepLink`
    // defers a deep-linked present until the conflicting presentation's
    // dismissal completes.
    @State private var showInsulinSheet = false
    @State private var pendingDeepLink: DeepLinkTarget?

    // The two deep links under the `medata` scheme — each a single-tap
    // lock-screen widget launcher (PRD amendment to App 10).
    private enum DeepLinkTarget {
        case insulinSheet  // medata://insulin/add
        case captureCover  // medata://capture
    }

    init(
        captureModel: CaptureFlowModel,
        engine: ARKitCaptureEngine,
        store: any PersistenceStore,
        visionCardDetector: VisionCardDetector? = nil,
        preShutterSegmenter: PreShutterSegmenter? = nil
    ) {
        self.captureModel = captureModel
        self.engine = engine
        self.store = store
        self.visionCardDetector = visionCardDetector
        self.preShutterSegmenter = preShutterSegmenter
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
            onCapture: { activeSheet = .capture },
            onIntake: { activeSheet = .intake },
            onDose: { showInsulinSheet = true },
            onRecords: { activeSheet = .records },
            onGraph: { activeSheet = .graph },
            onSettings: { activeSheet = .settings }
        )
        .tint(.medataAccent)
        .fullScreenCover(item: $activeSheet, onDismiss: {
            // A deep-linked present waits for the cover's dismissal to
            // finish; presenting mid-animation is silently dropped by SwiftUI.
            switch pendingDeepLink {
            case .insulinSheet:
                showInsulinSheet = true
            case .captureCover:
                activeSheet = .capture
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
                IntakeView()
            case .records:
                RecordsView(store: store)
            case .graph:
                TrendsView(store: store)
            case .settings:
                NavigationStack {
                    SettingsView(store: store, hasLiDAR: captureModel.supportsLiDAR)
                }
            }
        }
        // Relocated from TrendsView (Decision 10): the dose sheet keeps its
        // native drag-to-dismiss (no CloseCoverButton — design: Cover
        // vocabulary). `onDismiss` sequences a pending medata://capture
        // present behind the sheet's dismissal.
        .sheet(isPresented: $showInsulinSheet, onDismiss: {
            if pendingDeepLink == .captureCover {
                pendingDeepLink = nil
                activeSheet = .capture
            }
        }) {
            InsulinDoseSheet(store: store)
        }
        .onChange(of: activeSheet) { _, new in
            // The AR session runs only while Capture is the frontmost cover.
            if new == .capture {
                captureModel.capturePresented()
            } else {
                captureModel.captureDismissed()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    // The `medata` scheme is registered in MeData/Info.plist (CFBundleURLTypes;
    // merged with the generated Info.plist). Both links land on their target
    // from any state, dismissing whatever is presented first (App 10):
    //   medata://insulin/add — the dose-entry sheet
    //   medata://capture     — the Capture cover
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "medata" else { return }
        switch (url.host, url.path) {
        case ("insulin", "/add"):
            if activeSheet == nil {
                showInsulinSheet = true
            } else {
                pendingDeepLink = .insulinSheet
                activeSheet = nil
            }
        case ("capture", ""), ("capture", "/"):
            if showInsulinSheet {
                pendingDeepLink = .captureCover
                showInsulinSheet = false
            } else if activeSheet == nil {
                activeSheet = .capture
            } else if activeSheet != .capture {
                pendingDeepLink = .captureCover
                activeSheet = nil
            }
        default:
            break
        }
    }
}
