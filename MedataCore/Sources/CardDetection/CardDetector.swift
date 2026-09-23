import CaptureKit
import Foundation

// Protocol for Vision-based card rectangle detection. The concrete implementation
// (VisionCardDetector) lives in the App target to avoid importing Vision into
// MedataCore. Tests inject a mock conformance directly.
public protocol CardDetector: Sendable {
    func detect(in frame: RawFrame) async -> [PixelCorner]?
}
