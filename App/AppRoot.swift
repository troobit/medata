import CaptureKit
import Persistence
import SwiftUI

// Three-tab shell per UI Decision 15 / Req §18. Owns the capture and history
// models so they survive tab switches; the system tab bar uses its default
// Liquid Glass material — no custom appearance (Req §18.4). `@AppStorage`
// persists the selected tab across cold/warm launches (Req §18.6).
@MainActor
struct AppRoot: View {
    @AppStorage("selectedTab") private var selectedTabRaw: String = AppTab.photo.rawValue
    @Bindable var captureModel: CaptureFlowModel
    @State private var historyModel: MealHistoryModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?

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
        _historyModel = State(initialValue: MealHistoryModel(store: store))
    }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .photo },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            CaptureFlowView(
                model: captureModel,
                engine: engine,
                store: store,
                visionCardDetector: visionCardDetector,
                preShutterSegmenter: preShutterSegmenter
            )
            .tabItem { Label("Photo", systemImage: "camera.fill") }
            .tag(AppTab.photo)
            MealsTabView(model: historyModel)
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(AppTab.meals)
            NavigationStack {
                SettingsView(store: store)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .tint(.medataAccent)
        .onChange(of: selectedTab.wrappedValue) { _, new in
            captureModel.tabSelectionChanged(to: new)
        }
    }
}
