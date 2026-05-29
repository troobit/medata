import SwiftUI

// Shutter control extracted from `CaptureFlowView` per UI Req §20.6 /
// Decision 16. Spec: `design-system/pages/photo-tab.md` §"Shutter".
//
// Sizing constants are deliberately kept on the type so the wiring code in
// `CaptureFlowView` can preserve the ≥24pt clearance above the tab bar (§20.6)
// without re-deriving the dimensions inline.

enum ShutterButtonState: Equatable {
    case ready
    case capturing
    case disabled

    var isInteractive: Bool { self == .ready }

    var accessibilityValue: String {
        switch self {
        case .ready: return "Ready"
        case .capturing: return "Capturing"
        case .disabled: return "Disabled"
        }
    }
}

enum ShutterButtonMetrics {
    static let outerDiameter: CGFloat = 76
    static let outerStrokeRest: CGFloat = 4
    static let outerStrokePressed: CGFloat = 6
    static let innerDiameterRest: CGFloat = 60
    static let innerDiameterPressed: CGFloat = 52
    static let pressDurationSeconds: Double = 0.1
    static let releaseDurationSeconds: Double = 0.15
    static let bottomClearanceFromTabBar: CGFloat = 24
}

struct ShutterButton: View {
    let state: ShutterButtonState
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(
                        Color.captureChromeText,
                        lineWidth: isPressed
                            ? ShutterButtonMetrics.outerStrokePressed
                            : ShutterButtonMetrics.outerStrokeRest
                    )
                    .frame(
                        width: ShutterButtonMetrics.outerDiameter,
                        height: ShutterButtonMetrics.outerDiameter
                    )
                Circle()
                    .fill(Color.captureChromeText)
                    .opacity(state == .disabled ? 0.4 : 1.0)
                    .frame(
                        width: isPressed
                            ? ShutterButtonMetrics.innerDiameterPressed
                            : ShutterButtonMetrics.innerDiameterRest,
                        height: isPressed
                            ? ShutterButtonMetrics.innerDiameterPressed
                            : ShutterButtonMetrics.innerDiameterRest
                    )
            }
            // Reserve the outer ring footprint so the surrounding chrome layout
            // never shifts during the press animation (Req §20.6).
            .frame(
                width: ShutterButtonMetrics.outerDiameter,
                height: ShutterButtonMetrics.outerDiameter
            )
        }
        .buttonStyle(.plain)
        .disabled(!state.isInteractive)
        .simultaneousGesture(pressGesture)
        .accessibilityLabel("Capture meal")
        .accessibilityHint("Double-tap to take a photo")
        .accessibilityValue(state.accessibilityValue)
        .accessibilityIdentifier("shutter")
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard state.isInteractive else { return }
                withAnimation(pressAnimation) { isPressed = true }
            }
            .onEnded { _ in
                withAnimation(releaseAnimation) { isPressed = false }
            }
    }

    private var pressAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .easeOut(duration: ShutterButtonMetrics.pressDurationSeconds)
    }

    private var releaseAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0)
            : .snappy(duration: ShutterButtonMetrics.releaseDurationSeconds)
    }
}
