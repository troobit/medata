import CaptureKit
import Foundation

// Protocol for Vision-based card rectangle detection. The concrete implementation
// (VisionCardDetector) lives in the CardDetectionVision target so this target
// never imports Vision. Tests inject a mock conformance directly.
public protocol CardDetector: Sendable {
    func detect(in frame: RawFrame) async -> [PixelCorner]?
}
