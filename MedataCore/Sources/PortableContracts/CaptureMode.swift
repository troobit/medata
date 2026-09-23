// User-selected capture mode per Decision 35. Replaces auto-derived path dispatch.
// Persisted in UserDefaults under SettingsKeys.captureMode; default = .double.
public enum CaptureMode: String, Sendable, Codable, CaseIterable, Equatable {
    case single
    case double

    public var capturePath: CapturePath {
        switch self {
        case .single: return .singleViewLidar
        case .double: return .twoViewSfS
        }
    }
}
