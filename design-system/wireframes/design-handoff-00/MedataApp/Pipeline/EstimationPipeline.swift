import Foundation

/// Orchestrates the 9-stage pipeline. The wireframe presents this protocol
/// surface; production code wires the real services in `live()`.
@MainActor
protocol EstimationPipeline: AnyObject {
    func estimate(_ request: EstimationRequest) async throws -> Meal
}

struct EstimationRequest: Hashable {
    let nadir: CapturedFrame
    let oblique: CapturedFrame?
    let relativePose: PoseSE3?
    let title: String           // "Lunch", auto-derived from time of day
}

@MainActor
final class MockEstimationPipeline: EstimationPipeline {
    func estimate(_ request: EstimationRequest) async throws -> Meal {
        // Returns the first sample meal so screens have data to render.
        var meal = SampleMeals.seed[0]
        meal = Meal(
            id: UUID(),
            capturedAt: .now,
            title: request.title,
            capturePath: request.oblique == nil ? .singleViewLidar : .twoViewSfS,
            classes: meal.classes,
            confidence: meal.confidence,
            databaseEdition: meal.databaseEdition,
            userCorrection: nil
        )
        return meal
    }
}
