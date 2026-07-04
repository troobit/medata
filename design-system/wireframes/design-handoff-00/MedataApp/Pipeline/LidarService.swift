import Foundation
import CoreGraphics

// MARK: - LiDAR

@MainActor
protocol LidarService: AnyObject {
    var isAvailable: Bool { get }
    /// Most recent depth map aligned with the colour frame, in metres.
    func currentDepth() async -> DepthMap?
}

@MainActor
final class MockLidarService: LidarService {
    let isAvailable = true
    func currentDepth() async -> DepthMap? { nil }
}

// MARK: - Reference card detection (req §5)

struct CardPose: Hashable {
    /// Metric scale at the food plane (mm per pixel).
    let scaleMmPerPixel: Double
    let pose: PoseSE3
}

protocol CardDetector: AnyObject {
    func detect(in frame: CapturedFrame) async -> CardPose?
}

final class MockCardDetector: CardDetector {
    func detect(in frame: CapturedFrame) async -> CardPose? { nil }
}

// MARK: - Support plane (req §4)

struct SupportPlane: Hashable {
    let normal: [Double]        // unit, ~gravity-aligned
    let distanceMetres: Double  // signed distance from camera origin
    let residualStdDev: Double  // surfaced as a confidence input (req §4.6)
}

protocol SupportPlaneDetector: AnyObject {
    func fit(frame: CapturedFrame, depth: DepthMap?) async throws -> SupportPlane
}

final class MockSupportPlaneDetector: SupportPlaneDetector {
    func fit(frame: CapturedFrame, depth: DepthMap?) async throws -> SupportPlane {
        SupportPlane(normal: [0, 0, 1], distanceMetres: 0.34, residualStdDev: 0.002)
    }
}

// MARK: - Segmentation (req §8)

struct SegmentationResult: Hashable {
    /// Per-pixel argmax label (image-shaped).
    let labels: [UInt8]
    /// Per-pixel max class probability.
    let probabilities: [Float]
    let labelNames: [UInt8: String]
    let widthPx: Int
    let heightPx: Int
    let meanConfidenceOverFood: Double
}

protocol Segmenter: AnyObject {
    func segment(_ frame: CapturedFrame) async throws -> SegmentationResult
}

final class MockSegmenter: Segmenter {
    func segment(_ frame: CapturedFrame) async throws -> SegmentationResult {
        SegmentationResult(
            labels: [],
            probabilities: [],
            labelNames: [1: "rice_white", 2: "chicken_roast", 3: "broccoli"],
            widthPx: 0, heightPx: 0,
            meanConfidenceOverFood: 0.83
        )
    }
}
