import Pipeline
import SwiftUI

// Placeholder capture-flow view. Full UI design deferred to specs/ui per design §10.
// Implements CaptureFlowDelegate to receive pipeline events on the main actor.
@MainActor
final class CaptureFlowViewModel: ObservableObject, CaptureFlowDelegate {
    @Published var tiltDegrees: Float = 0
    @Published var lidarCoveragePercent: Float = 0
    @Published var interClassOcclusionDetected = false
    @Published var mealRecord: MealRecord?

    nonisolated func didUpdateTilt(angleDegrees: Float) {
        Task { @MainActor in tiltDegrees = angleDegrees }
    }

    nonisolated func didUpdateLiDARCoverage(percent: Float) {
        Task { @MainActor in lidarCoveragePercent = percent }
    }

    nonisolated func didDetectInterClassOcclusion() {
        Task { @MainActor in interClassOcclusionDetected = true }
    }

    nonisolated func didProduceEstimate(_ record: MealRecord) {
        Task { @MainActor in mealRecord = record }
    }
}

struct CaptureFlowView: View {
    @StateObject private var viewModel = CaptureFlowViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Point the camera at the meal")
                    .font(.headline)
                if let record = viewModel.mealRecord {
                    NavigationLink("View Result", value: record)
                }
            }
            .navigationTitle("Capture")
            .navigationDestination(for: MealRecord.self) { record in
                ResultView(record: record)
            }
        }
    }
}
