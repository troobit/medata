// Three-tab shell defined by UI Decision 15. The order is fixed (§18.1) and
// persisted as a raw string so `@AppStorage("selectedTab")` round-trips.
enum AppTab: String, Hashable, Sendable {
    case photo
    case meals
    case settings
}
