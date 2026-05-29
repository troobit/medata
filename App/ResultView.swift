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
}

// Controls how `ResultView` is presented. The just-captured path (Photo tab)
// shows the "New capture" action; the history-detail path (Meals tab) hides it
// because the user got there from the list and the back button is the way out.
enum ResultPresentation: Equatable {
    case justCaptured
    case historyDetail

    var showsNewCapture: Bool {
        switch self {
        case .justCaptured: return true
        case .historyDetail: return false
        }
    }
}

// Post-capture result. Shows only the carb total and the confidence pill —
// no per-class breakdown, no clinical macros (Req §9.5, Decision 3).
struct ResultView: View {
    let record: MealRecord
    var mode: ResultPresentation = .justCaptured
    var onNewCapture: () -> Void = {}
    var onRetake: () -> Void = {}

    private var sigma: Float { record.confidence.sigmaMeal }

    var body: some View {
        VStack(spacing: 24) {
            carbs
            ConfidencePill(sigmaMeal: sigma)
            if ResultFormat.showsUncertainPrompt(sigma) { uncertainPrompt }
            Spacer()
            if mode.showsNewCapture {
                Button("New Capture", action: onNewCapture)
                    .buttonStyle(.borderedProminent)
                    .tint(.medataAccent)
                    .accessibilityIdentifier("result.newCapture")
            }
        }
        .padding()
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
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
