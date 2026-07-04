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
            onOpenCapture: { activeSheet = .capture },
            onOpenData: { activeSheet = .data },
            onOpenSettings: { activeSheet = .settings }
        )
        .tint(.medataAccent)
        .fullScreenCover(item: $activeSheet) { sheet in
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
    }
}
