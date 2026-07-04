import CaptureKit
import Persistence
import SwiftUI

// Capture-rooted shell (Decision 11 / Req §1). The three-tab TabView is gone:
// AppRoot hosts `CaptureFlowView` full-screen and presents Data, Trends, and
// Settings as mutually-exclusive full-screen covers over it via a single
// optional `ActiveSheet` (Decision 19 — full screens, not sheets). Capture-chrome
// buttons set it through the closures passed into `CaptureFlowView`. Presenting a
// cover releases the AR session (`sheetDidPresent`); dismissing re-arms it
// (`sheetDidDismiss`) — Req §1.5. Full-screen covers have no drag-to-dismiss, so
// each surface carries its own explicit `Close` control (Decision 19).
@MainActor
struct AppRoot: View {
    @Bindable var captureModel: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?

    @State private var activeSheet: ActiveSheet?

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

    // A single optional so the three sheets are mutually exclusive by
    // construction — dismiss-then-present is sequential, so the AR session
    // never double-toggles (design: Shell change).
    enum ActiveSheet: Identifiable {
        case data
        case trends
        case settings

        var id: Self { self }
    }

    var body: some View {
        CaptureFlowView(
            model: captureModel,
            engine: engine,
            store: store,
            visionCardDetector: visionCardDetector,
            preShutterSegmenter: preShutterSegmenter,
            onOpenData: { activeSheet = .data },
            onOpenTrends: { activeSheet = .trends },
            onOpenSettings: { activeSheet = .settings }
        )
        .tint(.medataAccent)
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .data:
                DataView(store: store)
            case .trends:
                TrendsView(store: store)
            case .settings:
                NavigationStack {
                    SettingsView(store: store, hasLiDAR: captureModel.supportsLiDAR)
                }
            }
        }
        .onChange(of: activeSheet) { _, new in
            if new == nil {
                captureModel.sheetDidDismiss()
            } else {
                captureModel.sheetDidPresent()
            }
        }
    }
}
