import CaptureKit
import Foundation

// Protocol for Vision-based card rectangle detection. The concrete implementation
// (VisionCardDetector) lives in the CardDetectionVision target so this target
// never imports Vision. Tests inject a mock conformance directly.
public protocol CardDetector: Sendable {
    /// Every rectangle candidate in the detector's ranking order; empty when
    /// none. Which one is the card is `CardPoseSolver.pick`'s decision.
    func detect(in frame: RawFrame) async -> [[PixelCorner]]
}
