import CaptureKit
import Pipeline
import SwiftUI

// Root view of the capture flow. Composes the AR preview, the live indicators,
// the shutter, the refusal banner overlay, and the settings entry. Behaviour
// lives in CaptureFlowModel; this is composition only.
struct CaptureFlowView: View {
    @Bindable var model: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore

    @State private var observer: LiveSampleObserver?

    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            content
                .navigationDestination(for: MealRecord.self) { record in
                    ResultView(
                        record: record,
                        mode: .justCaptured,
                        onNewCapture: { model.dismissResult() },
                        onRetake: { model.dismissResult() }
                    )
                }
                .navigationTitle("Capture")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .permissionDenied(let subject):
            PermissionDeniedView(subject: subject) { model.openSettings() }
        default:
            capture
        }
    }

    private var capture: some View {
        ZStack {
            ARPreviewView(engine: engine)
                .ignoresSafeArea()

            VStack {
                topHints
                Spacer()
                LiveIndicatorView(
                    model: model.indicators,
                    supportsLiDAR: model.currentSnapshot?.distanceCm != nil,
                    targetTiltDegrees: model.awaitingObliqueView ? 25 : 0
                )
                shutterButton
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .top) {
            if case .refused(let failure, _) = model.state {
                RefusalBanner(failure: failure) { model.tryAgain() }
                    .padding(.top, 8)
            }
        }
        .onAppear {
            let obs = observer ?? LiveSampleObserver(model: model)
            observer = obs
            obs.start(frames: engine.frames)
        }
        .onDisappear { observer?.stop() }
    }

    @ViewBuilder
    private var topHints: some View {
        VStack(spacing: 6) {
            switch model.state {
            case .initialising:
                Label("Initialising…", systemImage: "hourglass")
                    .accessibilityIdentifier("hint.initialising")
            case .trackingLost:
                Label("Tracking lost — hold steady", systemImage: "arrow.triangle.2.circlepath")
                    .accessibilityIdentifier("hint.trackingLost")
            case .estimating:
                Label("Estimating…", systemImage: "hourglass")
                    .accessibilityIdentifier("hint.estimating")
            case .capturing:
                Label("Capturing…", systemImage: "camera")
                    .accessibilityIdentifier("hint.capturing")
            default:
                if model.awaitingObliqueView {
                    Text("Angled view — tilt to about 25°")
                } else if model.currentSnapshot?.pathHint == .twoViewSfS {
                    Text("Top-down view")
                    Label("Include an ID-1 reference card, flat in the scene", systemImage: "creditcard")
                        .font(.caption)
                }
            }
        }
        .font(.callout)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    @ViewBuilder
    private var shutterButton: some View {
        VStack(spacing: 12) {
            if case .ready(let snapshot) = model.state, snapshot.pathHint == .singleViewLidar {
                Button("Use two views instead") { model.forceTwoView() }
                    .font(.footnote)
            }
            Button {
                model.shutter()
            } label: {
                Circle()
                    .fill(model.canShutter ? Color.medataAccent : Color.gray.opacity(0.5))
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(.white, lineWidth: 4))
            }
            .disabled(!model.canShutter || model.isBusy)
            .accessibilityIdentifier("shutter")
        }
    }
}

// Permission-denied branch with a deep link to the app's iOS Settings (§1.3).
private struct PermissionDeniedView: View {
    let subject: PermissionSubject
    let openSettings: () -> Void

    private var message: String {
        switch subject {
        case .camera:
            return "MeData needs camera access to capture your meal. Enable it in Settings to continue."
        case .motion:
            return "MeData needs motion access for the tilt indicator. Enable it in Settings to continue."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .padding(.horizontal)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .tint(.medataAccent)
        }
        .padding()
    }
}
