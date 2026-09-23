import CoreGraphics
import Foundation
import Vision

// Vision OCR wrapper: image -> [TextBox]. Port of the reference `ocr.py`
// (imgdatacollector). Vision returns bounding boxes normalised with a
// bottom-left origin; the conversion to top-left pixel coordinates happens
// once, here, so no other file ever sees Vision's coordinate space.
public struct TextBox: Sendable, Equatable {
    public let text: String
    // x, y, w, h in pixels, top-left origin.
    public let pixelRect: CGRect
    public let confidence: Double

    public init(text: String, pixelRect: CGRect, confidence: Double) {
        self.text = text
        self.pixelRect = pixelRect
        self.confidence = confidence
    }

    public var centre: CGPoint {
        CGPoint(x: pixelRect.midX, y: pixelRect.midY)
    }
}

public enum TextRecogniser {

    // OCR the whole image. Recognition level `.accurate`, no language
    // correction (labels are digits and short tokens), per reference.
    public static func recognise(_ image: CGImage) throws -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let bb = observation.boundingBox
            let rect = CGRect(
                x: bb.origin.x * width,
                y: (1.0 - bb.origin.y - bb.size.height) * height,
                width: bb.size.width * width,
                height: bb.size.height * height
            )
            return TextBox(
                text: candidate.string,
                pixelRect: rect,
                confidence: Double(candidate.confidence)
            )
        }
    }
}
