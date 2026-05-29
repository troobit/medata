import Pipeline
import SwiftUI

// Shared three-tier confidence pill rendering (UI Req §9.2 / Decision 8 / §19.2).
// Used by `ResultView` and `MealRow` so the visual treatment stays identical
// between the just-captured surface and the meal-history row.
struct ConfidencePill: View {
    let sigmaMeal: Float

    private var level: ConfidenceLevel { .forSigma(sigmaMeal) }

    var body: some View {
        Text(level.label)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(level.colour.opacity(0.25), in: Capsule())
            .overlay(Capsule().stroke(level.colour, lineWidth: 1.2))
            .accessibilityLabel("Confidence \(level.label)")
    }
}
