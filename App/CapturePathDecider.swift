import Pipeline

enum CapturePathDecider {
    static func decide(supportsLiDAR: Bool, latestCoveragePercent: Float) -> CapturePath {
        supportsLiDAR && latestCoveragePercent >= 80 ? .singleViewLidar : .twoViewSfS
    }
}
