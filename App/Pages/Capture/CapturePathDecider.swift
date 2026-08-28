#if AUTO_CAPTURE_MODE
import Pipeline

// Preserved for Req 3.9: auto-selection of capture path when LiDAR coverage ≥ 80%.
// Not active in v1 — Decision 35 replaced this with a persistent user toggle.
// Enable by defining the AUTO_CAPTURE_MODE compile flag in the app target.
enum CapturePathDecider {
    static func decide(supportsLiDAR: Bool, latestCoveragePercent: Float) -> CapturePath {
        supportsLiDAR && latestCoveragePercent >= 80 ? .singleViewLidar : .twoViewSfS
    }
}
#endif
