import CaptureKit
import Persistence
import SwiftUI

// Graph-rooted shell (Decision 20 / Req §1). The launch root is the Graph screen
// (`TrendsView`, which owns its own `NavigationStack`); Capture, Data, and
// Settings present as mutually-exclusive full-screen covers over it via a single
// optional `ActiveSheet` (Decision 19 — full screens, not sheets). Graph-chrome
// buttons set it through the closures passed into `TrendsView`. The AR session
// runs ONLY while the Capture cover is presented: presenting `.capture` arms it
// (`capturePresented`); any other value releases it (`captureDismissed`) — so at
// launch (Graph root) the camera stays off and no permission prompt fires
// (Req §1.5). Each cover carries its own explicit `Close` control (Decision 19).
@MainActor
struct AppRoot: View {
    @Bindable var captureModel: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?

    @State private var activeSheet: ActiveSheet?
    // The insulin dose sheet is presented by TrendsView (a plain sheet, not a
    // cover) but the state lives here so the `medata://insulin/add` deep link
    // can raise it from any app state (PRD regression-suggestion-integration
    // App 10). `pendingDeepLink` defers a deep-linked present until the
    // conflicting presentation's dismissal completes.
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

    // A single optional so the three covers are mutually exclusive by
    // construction — dismiss-then-present is sequential, so the AR session
    // never double-toggles (design: Shell change).
    enum ActiveSheet: Identifiable {
        case capture
        case data
        case settings

        var id: Self { self }
    }

    var body: some View {
        TrendsView(
            store: store,
            showInsulinSheet: $showInsulinSheet,
            onInsulinSheetDismiss: {
                // medata://capture arrived while the dose sheet was up: the
                // cover presents once the sheet's dismissal completes.
                if pendingDeepLink == .captureCover {
                    pendingDeepLink = nil
                    activeSheet = .capture
                }
            },
            onOpenCapture: { activeSheet = .capture },
            onOpenData: { activeSheet = .data },
            onOpenSettings: { activeSheet = .settings }
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
            case .data:
                DataView(store: store)
            case .settings:
                NavigationStack {
                    SettingsView(store: store, hasLiDAR: captureModel.supportsLiDAR)
                }
            }
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
