import Testing
@testable import MeData
import Pipeline

@Suite("CapturePathDecider boundary table")
struct CapturePathDeciderTests {
    @Test(
        "decides the correct path at each boundary",
        arguments: [
            (supportsLiDAR: false, coverage: Float(100), expected: CapturePath.twoViewSfS),
            (supportsLiDAR: true,  coverage: Float(0),   expected: CapturePath.twoViewSfS),
            (supportsLiDAR: true,  coverage: Float(79.99), expected: CapturePath.twoViewSfS),
            (supportsLiDAR: true,  coverage: Float(80),  expected: CapturePath.singleViewLidar),
            (supportsLiDAR: true,  coverage: Float(100), expected: CapturePath.singleViewLidar),
        ] as [(supportsLiDAR: Bool, coverage: Float, expected: CapturePath)]
    )
    func decideAtBoundary(supportsLiDAR: Bool, coverage: Float, expected: CapturePath) {
        let path = CapturePathDecider.decide(
            supportsLiDAR: supportsLiDAR,
            latestCoveragePercent: coverage
        )
        #expect(path == expected)
    }
}
