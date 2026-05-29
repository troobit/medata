import Pipeline
import SwiftUI

// Three-state confidence band keyed off σ_meal per Req §9.2 / Decision 8.
// Boundaries: High σ ≥ 0.75, Moderate 0.60 ≤ σ < 0.75, Low σ < 0.60.
enum ConfidenceLevel: Equatable {
    case low
    case moderate
    case high

    static func forSigma(_ sigma: Float) -> ConfidenceLevel {
        if sigma >= 0.75 { return .high }
        if sigma >= 0.60 { return .moderate }
        return .low
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var colour: Color {
        switch self {
        case .low: return .confidenceLow
        case .moderate: return .confidenceModerate
        case .high: return .confidenceHigh
        }
    }
}

enum ResultFormat {
    // §9.1: total meal carbohydrates in grams rounded to 1 g.
    static func carbsGrams(_ totalCarbsG: Float) -> Int {
        Int(totalCarbsG.rounded())
    }

    // §9.3: uncertain-estimate prompt shown when σ_meal < 0.60.
    static func showsUncertainPrompt(_ sigma: Float) -> Bool {
        sigma < 0.60
    }

    // Decision 42 / Req §23.3: placeholder banner shown only for meals stamped
    // by the Phase 1 dev-stub segmenter. Gated on the persisted record value,
    // NOT on the build flag, so a Phase 1 record viewed under a later Phase 3
    // build still surfaces the banner per design §3.5.
    static let devStubSegmenterSource = "dev_stub"
    static func showsPlaceholderBanner(segmenterSource: String) -> Bool {
        segmenterSource == devStubSegmenterSource
    }

    static let placeholderBannerCopy =
        "Placeholder estimate. The food recogniser is a development stub — the carbohydrate value is not a real measurement."
}

// Post-capture result. Shows only the carb total and the confidence pill —
// no per-class breakdown, no clinical macros (Req §9.5, Decision 3).
struct ResultView: View {
    let record: MealRecord
    var onNewCapture: () -> Void = {}
    var onRetake: () -> Void = {}

    private var sigma: Float { record.confidence.sigmaMeal }
    private var level: ConfidenceLevel { .forSigma(sigma) }

    var body: some View {
        VStack(spacing: 0) {
            if ResultFormat.showsPlaceholderBanner(segmenterSource: record.segmenterSource) {
                placeholderBanner
            }
            VStack(spacing: 24) {
                carbs
                pill
                if ResultFormat.showsUncertainPrompt(sigma) { uncertainPrompt }
                Spacer()
                Button("New Capture", action: onNewCapture)
                    .buttonStyle(.borderedProminent)
                    .tint(.medataAccent)
            }
            .padding()
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Req §23.3 / Decision 42: high-contrast (system .yellow / .black) banner
    // pinned to the top of the screen above the carb total. Persistent — the
    // user cannot dismiss it because the underlying record is not a real
    // measurement. Removed only when Phase 3 ships the trained Core ML model.
    private var placeholderBanner: some View {
        Text(ResultFormat.placeholderBannerCopy)
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.yellow)
            .accessibilityIdentifier("result.placeholderBanner")
    }

    private var carbs: some View {
        VStack(spacing: 4) {
            Text("\(ResultFormat.carbsGrams(record.macros.totalCarbsG)) g")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Color.medataAccent)
            Text("Total carbohydrates")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var pill: some View {
        Text(level.label)
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(level.colour.opacity(0.25), in: Capsule())
            .overlay(Capsule().stroke(level.colour, lineWidth: 1.5))
    }

    private var uncertainPrompt: some View {
        VStack(spacing: 10) {
            Text("This estimate is uncertain. Consider retaking the photo for a better result.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retake", action: onRetake)
                .buttonStyle(.bordered)
        }
    }
}
