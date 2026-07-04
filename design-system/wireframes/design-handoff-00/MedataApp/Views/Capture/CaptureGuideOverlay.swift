import SwiftUI

/// Ghost outline + status hints over the live viewfinder.
struct CaptureGuideOverlay: View {
    var body: some View {
        ZStack {
            // Top-edge hint
            VStack {
                Text("Move closer · ID-1 card optional")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 130)
                Spacer()
            }
            // Ghost target
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 240, height: 240)
                .overlay {
                    Text("ALIGN PLATE\nWITHIN OUTLINE")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
        }
    }
}
