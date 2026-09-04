import CaptureKit
import CoreGraphics
import Foundation

// `CGImage` decode from `RawFrame.imageBytes` + `.pixelFormat`, shared by every
// capture-side surface that has to show or re-encode a captured buffer: the
// frozen `CapturedFramesView`, the oblique-aiming nadir thumbnail, and the
// PhotoKit saver that writes the nadir frame to the user's library.
//
// The portable contract is RGB8 in sRGB at the platform-native orientation;
// iOS captures BGRA8 and converts upstream (the rawframe-rgb-conversion fix),
// so the switch keeps the other portable formats decodable too rather than
// assuming one layout.
enum RawFrameImage {

    // Returns nil when the byte count does not match the declared geometry or
    // Core Graphics refuses the buffer; callers render a placeholder rather
    // than failing the capture.
    static func cgImage(_ frame: RawFrame) -> CGImage? {
        let bytesPerPixel: Int
        let bitmapInfo: CGBitmapInfo
        switch frame.pixelFormat {
        case .rgb8:
            bytesPerPixel = 3
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        case .rgba8:
            bytesPerPixel = 4
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        case .bgra8:
            bytesPerPixel = 4
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little)
        }
        let width = frame.imageWidth
        let height = frame.imageHeight
        let bytesPerRow = width * bytesPerPixel
        guard frame.imageBytes.count == bytesPerRow * height else { return nil }
        guard let provider = CGDataProvider(data: frame.imageBytes as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
