import Pipeline
import SwiftUI

// Capture defaults, reached from Settings (specs/ui/settings-information-
// architecture): which path a fresh capture takes, and whether the ID-1 card is
// requested every time.
struct CaptureSettingsView: View {
    // Fresh-install default forks on device capability (iphone-experience
    // Req 16.2 / Decision 9): 1-view on LiDAR devices, 2-view otherwise. Passed
    // in so the Picker resolves an unset key the same way
    // `CaptureFlowView.effectiveMode` and `defaultCaptureModeReader` do,
    // instead of hard-defaulting to `.double`.
    let hasLiDAR: Bool

    // Empty string means the capture-mode key is unset — `captureModeBinding`
    // then resolves the effective default from `hasLiDAR`. Writing persists the
    // raw value back under the same `SettingsKeys.captureMode` key.
    @AppStorage(SettingsKeys.captureMode) private var captureModeRaw: String = ""
    @AppStorage(SettingsKeys.alwaysIncludeCard) private var alwaysIncludeCard = false

    private var captureModeBinding: Binding<CaptureMode> {
        Binding(
            get: { CaptureMode(rawValue: captureModeRaw) ?? (hasLiDAR ? .single : .double) },
            set: { captureModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Default path", selection: captureModeBinding) {
                    Text("1-view").tag(CaptureMode.single)
                    Text("2-view").tag(CaptureMode.double)
                }
                Toggle("Always include card", isOn: $alwaysIncludeCard)
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }
}
