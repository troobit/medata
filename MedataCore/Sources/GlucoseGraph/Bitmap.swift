import CoreGraphics
import Foundation

// RGBA8 pixel buffer decoded from a CGImage. The draw pass uses the image's
// OWN colour space (identity transfer — no colour management), so channel
// values are the file's raw numbers: the same values PIL's unmanaged decode
// fed the reference implementation's colour thresholds (Decision 5). iPhone
// screenshots are Display P3; a colour-managed sRGB decode would shift every
// channel and silently move the tuned thresholds.
public struct Bitmap: Sendable {
    public let width: Int
    public let height: Int
    private let bytesPerRow: Int
    private let pixels: [UInt8]

    public enum DecodeError: Error {
        case contextCreationFailed
    }

    public init(cgImage: CGImage) throws {
        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        // Prefer the image's own space; fall back to sRGB for images whose
        // space cannot back a bitmap context (e.g. indexed).
        let imageSpace = cgImage.colorSpace
        let space: CGColorSpace
        if let imageSpace, imageSpace.model == .rgb {
            space = imageSpace
        } else {
            space = CGColorSpace(name: CGColorSpace.sRGB)!
        }

        let w = width
        let h = height
        let stride = bytesPerRow
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw DecodeError.contextCreationFailed }
        pixels = buffer
    }

    // Raw channel values at (x, y), top-left origin. Screenshots are opaque
    // (alpha 255) so premultiplication is the identity.
    @inline(__always)
    public func rgb(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let offset = y * bytesPerRow + x * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
    }
}
