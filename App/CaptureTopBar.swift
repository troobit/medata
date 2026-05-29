import AVFoundation
import SwiftUI

// Top chrome for the Photo tab (UI Req §20.3 / Decision 16). Two 40pt circular
// `captureChromeBG` capsules: close (`xmark`) on the leading edge and a
// flash/torch toggle (`bolt.fill` / `bolt.slash.fill`) on the trailing edge.
// Spec: `design-system/pages/photo-tab.md` §"Top chrome".
//
// The flash/torch toggle is visible only when the active capture device has a
// torch — the on-screen widget reads `AVCaptureDevice.default(for: .video)`
// via the injected `torchAvailable` closure to keep this view test-shaped.

struct CaptureTopBar: View {
    var hasPresentedSheet: Bool = false
    var close: () -> Void = {}
    var torchAvailable: () -> Bool = { Self.defaultTorchAvailable() }
    var torchActive: () -> Bool = { Self.defaultTorchActive() }
    var setTorch: (Bool) -> Void = { Self.defaultSetTorch($0) }

    @State private var torchOn: Bool = false

    var body: some View {
        HStack {
            closeButton
            Spacer()
            if torchAvailable() {
                torchButton
            }
        }
        .padding(.horizontal, 16)
        .onAppear { torchOn = torchActive() }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.captureChromeText)
                .frame(width: 40, height: 40)
                .background(Color.captureChromeBG, in: Circle())
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("captureTopBar.close")
    }

    private var torchButton: some View {
        Button {
            torchOn.toggle()
            setTorch(torchOn)
        } label: {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.captureChromeText)
                .frame(width: 40, height: 40)
                .background(Color.captureChromeBG, in: Circle())
        }
        .accessibilityLabel(torchOn ? "Turn off torch" : "Turn on torch")
        .accessibilityIdentifier("captureTopBar.torch")
    }
}

extension CaptureTopBar {
    // MARK: - Default AVCaptureDevice plumbing

    static func defaultTorchAvailable() -> Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    static func defaultTorchActive() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.torchMode == .on
    }

    static func defaultSetTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
