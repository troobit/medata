import Foundation
import Pipeline
import SwiftUI

// `CaptureMode` is defined in `PortableContracts` (Decision 35) and re-exported
// by the `Pipeline` module. The App-side adds a UI label here so the toggle and
// any future surfaces share the same string. Persistence is via
// `@AppStorage("captureMode")` per UI Req §4.1 / §20.5 / Decision 16.
extension CaptureMode {
    var label: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        }
    }
}

enum CaptureModeStorage {
    static let key = "captureMode"
    static let defaultValue: CaptureMode = .double
    // Irish-English refusal copy emitted when the user taps the disabled
    // `Single` segment on a device without LiDAR (Req §4.2).
    static let noLiDARRefusal =
        "This device does not have the required depth sensor. Single mode requires a LiDAR-equipped iPhone."
}

// Capsule pill with two text labels and an animated inner accent pill that
// slides between positions (UI Req §20.5 / Decision 16). Spec:
// `design-system/pages/photo-tab.md` §"Capture-mode pill".
struct CaptureModeToggle: View {
    @AppStorage(CaptureModeStorage.key) private var mode: CaptureMode = CaptureModeStorage.defaultValue
    let supportsLiDAR: Bool
    var interactive: Bool = true
    var onDisabledTap: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace

    private let pillCornerRadius: CGFloat = 22
    private let innerMargin: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            label(for: .single)
            label(for: .double)
        }
        .padding(innerMargin)
        .background(Color.captureChromeBG, in: Capsule())
        .frame(height: 44)
        .accessibilityIdentifier("captureModeToggle")
        .accessibilityElement(children: .contain)
        .disabled(!interactive)
    }

    @ViewBuilder
    private func label(for option: CaptureMode) -> some View {
        let active = mode == option
        let isDisabled = option == .single && !supportsLiDAR
        Button {
            handleTap(option, disabled: isDisabled)
        } label: {
            Text(option.label)
                .font(.body.weight(.semibold))
                .foregroundStyle(active ? Color.captureBackground : Color.captureChromeText)
                .opacity(isDisabled ? 0.4 : 1.0)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.medataAccent)
                            .matchedGeometryEffect(id: "activePill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityIdentifier("captureModeToggle.\(option.rawValue)")
        .animation(slideAnimation, value: mode)
    }

    private var slideAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .bouncy(duration: 0.2)
    }

    private func handleTap(_ option: CaptureMode, disabled: Bool) {
        if disabled {
            onDisabledTap?(CaptureModeStorage.noLiDARRefusal)
            return
        }
        guard interactive, mode != option else { return }
        mode = option
    }
}
