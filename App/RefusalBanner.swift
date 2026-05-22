import Pipeline
import SwiftUI

// Inline refusal banner shown via `.overlay(alignment: .top)` on the capture
// view (Decision 5). The AR preview keeps rendering behind it; only the "Try
// Again" control clears the banner — no tap-outside dismiss. The failure's
// `localisedMessage` is rendered verbatim (Req §12.2).
struct RefusalBanner: View {
    let failure: EstimationFailure
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(failure.localisedMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .accessibilityIdentifier("refusal.message")

            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.medataAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("refusal.tryAgain")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        // Block tap-through to the shutter; only the button dismisses.
        .allowsHitTesting(true)
        .accessibilityIdentifier("refusalBanner")
    }
}
