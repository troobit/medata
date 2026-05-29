// UserDefaults keys kept in a single namespace to avoid stringly-typed access.
// `captureMode` is the persistent toggle introduced by Decision 35.
enum SettingsKeys {
    static let captureMode = "medata.captureMode"
    // Legacy keys retained until Task 73 rewrites the Settings screen.
    static let retentionDays = "medata.retentionDays"
    static let ifcdbOverlayEnabled = "medata.ifcdbOverlayEnabled"
}
