import SwiftUI

@main
struct MedataApp: App {
    @StateObject private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootNavigation()
                .environmentObject(env)
                .tint(DS.ink)
        }
    }
}

/// Single NavigationStack rooted on Capture; History & Settings present as sheets.
struct RootNavigation: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var path = NavigationPath()
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingTrends = false

    var body: some View {
        NavigationStack(path: $path) {
            CaptureView(
                onOpenHistory: { showingHistory = true },
                onOpenSettings: { showingSettings = true },
                onOpenTrends: { showingTrends = true }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .lidarFork:
                    LidarForkSheet().toolbar(.hidden, for: .navigationBar)
                case .segmentationReview(let meal):
                    SegmentationReviewView(meal: meal)
                case .result(let meal):
                    ResultView(meal: meal)
                case .correction(let meal):
                    ManualCorrectionView(meal: meal)
                case .captureError(let kind):
                    CaptureErrorView(kind: kind)
                case .overview(let meal):
                    MealOverviewView(meal: meal)
                }
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack { DataView() }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showingTrends) {
                NavigationStack { TrendsView() }
            }
        }
    }
}

/// Typed routes for the root NavigationStack.
enum Route: Hashable {
    case lidarFork
    case segmentationReview(Meal)
    case result(Meal)
    case overview(Meal)
    case correction(Meal)
    case captureError(CaptureErrorKind)
}
