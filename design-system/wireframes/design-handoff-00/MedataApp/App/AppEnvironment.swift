import Foundation
import Combine

/// Dependency container — held in `@StateObject` at the app root so views
/// can inject mocks in previews via plain initialisers if needed.
@MainActor
final class AppEnvironment: ObservableObject {
    let pipeline: EstimationPipeline
    let mealStore: MealStore

    init(pipeline: EstimationPipeline, mealStore: MealStore) {
        self.pipeline = pipeline
        self.mealStore = mealStore
    }

    static func live() -> AppEnvironment {
        AppEnvironment(
            pipeline: MockEstimationPipeline(),
            mealStore: InMemoryMealStore.seeded()
        )
    }
}
