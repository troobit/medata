// Household serving definition for a solid class, read from the bundled
// solid_servings table (serving-adjust PRD). The serving unit and stepper
// increment are data, tuneable in tools/food_db/generate.py without code
// changes.
public struct SolidServing: Equatable, Sendable {
    public let unitSingular: String
    public let unitPlural: String
    public let gramsPerUnit: Double
    public let step: Double

    public init(unitSingular: String, unitPlural: String,
                gramsPerUnit: Double, step: Double) {
        self.unitSingular = unitSingular
        self.unitPlural = unitPlural
        self.gramsPerUnit = gramsPerUnit
        self.step = step
    }
}

// Per design §3.7. Read-only access to the bundled food-composition database.
public protocol FoodDatabase: Sendable {
    // The current shipped edition string, e.g. "CoFID 2024" or "CoFID 2024 + IFCDB 2023".
    var version: String { get }

    // Lookup using the current (latest) bundled edition.
    func entry(for classId: String) -> FoodEntry?

    // Lookup honouring per-meal edition per §6.12 / Decision 24.
    // Falls back to the current edition when the requested edition is unavailable.
    func entry(for classId: String, edition: String) -> FoodEntry?

    // All edition strings bundled with this app version.
    func availableEditions() -> [String]

    // Household serving definition for a solid class (serving-adjust PRD).
    // nil for liquids and classes deliberately without one — the caller
    // falls back to grams.
    func solidServing(for classId: String) -> SolidServing?
}
