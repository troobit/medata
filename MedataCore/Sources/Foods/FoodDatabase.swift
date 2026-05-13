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
}
