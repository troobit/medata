import CaptureKit
import Pipeline
import SwiftUI

// Root of the Photo tab (UI Req §20 / Decision 16). Composes:
//   • `CaptureTopBar`            — close + flash/torch (top chrome)
//   • `LiveIndicatorBadge`       — consolidated tilt/distance/coverage chip
//   • `CaptureModeToggle`        — capsule pill above the shutter
//   • `ShutterButton`            — 76pt circle with press feedback
//   • `RefusalSheet`             — bottom-sheet refusal surface
// Behaviour lives in `CaptureFlowModel`; this is composition only.
// CaptureMode (Decision 35) is read via `@AppStorage` so any UI toggle change
// flows here without coupling.
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
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
            Color.captureBackground.ignoresSafeArea()
            ARPreviewView(engine: engine).ignoresSafeArea()

            VStack(spacing: 0) {
                CaptureTopBar()
                    .padding(.top, 8)
                Spacer().frame(height: 24)
                if model.currentSnapshot != nil, !isInitialising {
                    LiveIndicatorBadge(
                        model: model.indicators,
                        supportsLiDAR: model.supportsLiDAR,
                        isReady: isReady,
                        targetTiltDegrees: model.awaitingObliqueView ? 25 : 0
                    )
                } else {
                    initialisingHint
                }
                Spacer()
                bottomChrome
            }
        }
        .sheet(item: refusalBinding) { refusal in
            RefusalSheet(failure: refusal.failure) { model.retry() }
        }
        .onAppear {
            let obs = observer ?? LiveSampleObserver(model: model)
            observer = obs
            obs.start(frames: engine.frames)
        }
        .onDisappear { observer?.stop() }
    }

    private var bottomChrome: some View {
        VStack(spacing: 16) {
            // Decision 18 / research Decision 43: nadir captures always proceed
            // regardless of tilt; the oblique stage retains a |Δθ − 25°| ≤ 30°
            // hard cap. When the user is on the oblique stage but outside the
            // cap, surface the Irish-English failure copy above the shutter so
            // the disabled state has a written explanation (Req §2.3).
            if let message = model.obliqueTiltMessage {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.captureChromeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.captureChromeBG, in: Capsule())
                    .accessibilityIdentifier("hint.obliqueTilt")
            }
            CaptureModeToggle(supportsLiDAR: model.supportsLiDAR, interactive: !model.isBusy)
                .padding(.horizontal, 48)
            ShutterButton(
                state: shutterState,
                action: { model.shutter() },
                onBlockedTap: { model.shutterBlockedTapped() }
            )
            Color.clear.frame(height: ShutterButtonMetrics.bottomClearanceFromTabBar)
        }
    }

    @ViewBuilder
    private var initialisingHint: some View {
        let hint: (text: String, identifier: String, symbol: String)? = {
            switch model.state {
            case .initialising: return ("Initialising…", "hint.initialising", "hourglass")
            case .trackingLost: return ("Tracking lost — hold steady", "hint.trackingLost", "arrow.triangle.2.circlepath")
            case .estimating: return ("Estimating…", "hint.estimating", "hourglass")
            case .capturing: return ("Capturing…", "hint.capturing", "camera")
            default: return nil
            }
        }()
        if let hint {
            Label(hint.text, systemImage: hint.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.captureChromeText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.captureChromeBG, in: Capsule())
                .accessibilityIdentifier(hint.identifier)
        }
    }

    private var isInitialising: Bool {
        if case .initialising = model.state { return true }
        return false
    }

    private var isReady: Bool {
        if case .ready = model.state { return true }
        return false
    }

    private var shutterState: ShutterButtonState {
        if model.isBusy { return .capturing }
        return model.canShutter ? .ready : .disabled
    }

    // Bridges `model.refusal` (read-only on the model side; setting `nil`
    // currently has no effect) into a `Binding` for `.sheet(item:)`. A
    // swipe-down on the sheet writes `nil` here, which is a no-op against the
    // `.refused` state — the sheet re-presents on the next render if the
    // model is still `.refused`, so we collapse the binding to a get-only.
    private var refusalBinding: Binding<ActiveRefusal?> {
        Binding(
            get: { model.refusal },
            set: { _ in }
        )
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
