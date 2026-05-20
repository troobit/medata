import ARKit
import Combine
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
    @State private var diagnostics: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Point the camera at the meal")
                    .font(.headline)

                Button("Run self-check") {
                    runSelfCheck()
                }
                .buttonStyle(.borderedProminent)

                if !diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diagnostics, id: \.self) { line in
                            Text(line)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let record = viewModel.mealRecord {
                    NavigationLink("View Result", value: record)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Capture")
            .navigationDestination(for: MealRecord.self) { record in
                ResultView(record: record)
            }
        }
    }

    private func runSelfCheck() {
        let device = UIDevice.current
        let lidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let pipelineProof = EstimationFailure.noLidarDevice.localisedMessage

        let lines = [
            "Device model: \(device.model)",
            "iOS: \(device.systemVersion)",
            "LiDAR available: \(lidar ? "yes" : "no")",
            "Pipeline reachable: yes",
            "  sample error string from Pipeline:",
            "  \"\(pipelineProof)\""
        ]
        diagnostics = lines
        print("[medata self-check]")
        for line in lines { print("  \(line)") }
    }
}
