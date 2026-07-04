// UserDefaults keys kept in a single namespace to avoid stringly-typed access.
// `captureMode` is the persistent toggle introduced by Decision 35.
// IFCDB and retention keys removed per Decisions 37 and 39: photo lifecycle is
// delegated to PhotoKit (Req §17.3); macros source is fixed at CoFID + AFCD
// with no user-facing override (Req §11.1).
// `nonisolated` because the project sets
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise make this
// file-scope enum and its static constants implicitly MainActor-isolated.
// `defaultCaptureModeReader` (App/CaptureFlowModel.swift) is `nonisolated` and
// reads `captureMode`, so the keys must be reachable from any context. Plain
// string constants are inherently thread-safe.
nonisolated enum SettingsKeys {
    static let captureMode = "medata.captureMode"
    // Fork sheet §3.2 / Settings §12.1: the persistent "always include a
    // reference card" default. The fork-sheet card toggle seeds from this; a
    // per-capture override lives on CaptureFlowModel and does not write here.
    static let alwaysIncludeCard = "medata.alwaysIncludeCard"
}
