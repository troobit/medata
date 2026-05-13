import Pipeline
import SwiftUI

// Placeholder result view. Full UI design deferred to specs/ui per design §10.
struct ResultView: View {
    let record: MealRecord

    var body: some View {
        VStack(spacing: 16) {
            Text("Estimated Carbohydrates")
                .font(.headline)
            Text(String(format: "%.0f g", record.macros.totalCarbsG))
                .font(.largeTitle)
                .bold()
            Text("Confidence: \(Int(record.confidence.sigmaMeal * 100))%")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }
}
