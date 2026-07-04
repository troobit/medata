import Foundation
import Combine

/// Persistence boundary — req §15. v1 wireframe uses an in-memory mock; the
/// production target swaps in a SQLite-backed implementation that conforms.
@MainActor
protocol MealStore: AnyObject {
    var mealsPublisher: Published<[Meal]>.Publisher { get }
    var meals: [Meal] { get }
    func add(_ meal: Meal)
    func update(_ meal: Meal)
    func delete(id: UUID)
}

@MainActor
final class InMemoryMealStore: ObservableObject, MealStore {
    @Published private(set) var meals: [Meal] = []
    var mealsPublisher: Published<[Meal]>.Publisher { $meals }

    func add(_ meal: Meal)    { meals.insert(meal, at: 0) }
    func update(_ meal: Meal) {
        if let i = meals.firstIndex(where: { $0.id == meal.id }) { meals[i] = meal }
    }
    func delete(id: UUID) { meals.removeAll { $0.id == id } }

    static func seeded() -> InMemoryMealStore {
        let store = InMemoryMealStore()
        store.meals = SampleMeals.seed
        return store
    }
}

/// Static sample data so the wireframe is populated on first run.
enum SampleMeals {
    static let seed: [Meal] = {
        let cal = Calendar.current
        let now = Date()
        func date(_ hours: Int) -> Date {
            cal.date(byAdding: .hour, value: -hours, to: now) ?? now
        }
        return [
            Meal(
                id: UUID(),
                capturedAt: date(2),
                title: "Lunch",
                capturePath: .singleViewLidar,
                classes: [
                    FoodClass(name: "White rice",     classKey: "rice_white",     volumeCubicCm: 142, massGrams: 168, carbsGrams: 38.0, confidence: 0.88),
                    FoodClass(name: "Roast chicken",  classKey: "chicken_roast",  volumeCubicCm: 88,  massGrams: 95,  carbsGrams: 0.0,  confidence: 0.81),
                    FoodClass(name: "Broccoli",       classKey: "broccoli",       volumeCubicCm: 58,  massGrams: 62,  carbsGrams: 4.0,  confidence: 0.74)
                ],
                confidence: Confidence(scale: 0.92, segmentation: 0.83, geometric: 0.85),
                databaseEdition: "CoFID 2024 + IFCDB 2023"
            ),
            Meal(
                id: UUID(),
                capturedAt: date(5),
                title: "Snack",
                capturePath: .singleViewLidar,
                classes: [
                    FoodClass(name: "Apple",   classKey: "apple",   volumeCubicCm: 145, massGrams: 138, carbsGrams: 18.0, confidence: 0.91)
                ],
                confidence: Confidence(scale: 0.88, segmentation: 0.91, geometric: 0.90),
                databaseEdition: "CoFID 2024 + IFCDB 2023"
            ),
            Meal(
                id: UUID(),
                capturedAt: date(20),
                title: "Dinner",
                capturePath: .twoViewSfS,
                classes: [
                    FoodClass(name: "Pasta",        classKey: "pasta_cooked", volumeCubicCm: 210, massGrams: 240, carbsGrams: 56.0, confidence: 0.62),
                    FoodClass(name: "Tomato sauce", classKey: "tomato_sauce", volumeCubicCm: 60,  massGrams: 65,  carbsGrams: 5.0,  confidence: 0.55)
                ],
                confidence: Confidence(scale: 0.85, segmentation: 0.55, geometric: 0.60),
                databaseEdition: "CoFID 2024 + IFCDB 2023"
            )
        ]
    }()
}
