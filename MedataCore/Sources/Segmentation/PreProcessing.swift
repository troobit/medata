import Foundation
import CaptureKit

// Steps 1–7 of design §6.5. Output is a normalised FP16 LE buffer of shape
// [targetSize × targetSize × 3], HWC row-major. All intermediate computation runs
// in FP32 per Decision 25 / §6.0; the final cast to FP16 is the only precision
// reduction. The pad value for letterbox padding is the per-channel post-
// normalisation value `(0 - mean[c]) / std[c]`, identical to what the network
// sees for a perfect-black input — keeping the pad region indistinguishable from
// genuine black pixels (regardless of input pixel ordering, P3 / P9 fix).

public struct NormalisationStatistics: Sendable, Equatable {
    public let mean: (Float, Float, Float)
    public let std: (Float, Float, Float)

    public init(mean: (Float, Float, Float), std: (Float, Float, Float)) {
        self.mean = mean
        self.std = std
    }

    public static let imageNet = NormalisationStatistics(
        mean: (0.485, 0.456, 0.406),
        std: (0.229, 0.224, 0.225)
    )

    public static func == (lhs: NormalisationStatistics, rhs: NormalisationStatistics) -> Bool {
        return lhs.mean == rhs.mean && lhs.std == rhs.std
    }
}

public struct PreProcessedFrame: Sendable {
    public let bytes: Data            // FP16 LE, [targetSize × targetSize × 3], HWC row-major
    public let targetSize: Int
    public let scaledWidth: Int       // pre-pad width (≤ targetSize)
    public let scaledHeight: Int      // pre-pad height (≤ targetSize)
    public let originalWidth: Int
    public let originalHeight: Int

    public init(bytes: Data, targetSize: Int, scaledWidth: Int, scaledHeight: Int,
                originalWidth: Int, originalHeight: Int) {
        self.bytes = bytes
        self.targetSize = targetSize
        self.scaledWidth = scaledWidth
        self.scaledHeight = scaledHeight
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
    }
}

public enum SegmenterPreProcessor {
    public static let defaultTargetSize: Int = 513  // Decision 25

    public static func process(
        imageBytes: Data,
        pixelFormat: PixelFormat,
        width: Int,
        height: Int,
        targetSize: Int = defaultTargetSize,
        normalisation: NormalisationStatistics = .imageNet
    ) throws -> PreProcessedFrame {
        guard width > 0, height > 0, targetSize > 0 else {
            throw SegmentationError.invalidInputDimensions(
                "width=\(width), height=\(height), targetSize=\(targetSize) must be positive"
            )
        }
        try validateInputSize(imageBytes: imageBytes, format: pixelFormat, width: width, height: height)

        // Step 1: canonicalise to RGB8 (the platform-invariant point per §6.0 / P3).
        let rgb = canonicaliseToRGB8(imageBytes, format: pixelFormat, width: width, height: height)

        // Steps 2–3: aspect-preserving letterbox scale.
        let scale = Float(targetSize) / Float(max(width, height))
        let scaledW = max(1, Int((Float(width) * scale).rounded()))
        let scaledH = max(1, Int((Float(height) * scale).rounded()))

        // Steps 4–5: bilinear resize to (scaledW × scaledH) and normalise in one FP32 pass.
        // Both operations are linear; combining them avoids a redundant intermediate buffer.
        var fp32 = [Float](repeating: 0, count: scaledW * scaledH * 3)
        bilinearResizeRGB8ToNormalisedFP32(
            src: rgb, srcW: width, srcH: height,
            dst: &fp32, dstW: scaledW, dstH: scaledH,
            normalisation: normalisation
        )

        // Step 6: pad to (targetSize × targetSize) with pad[c] = (0 − mean[c]) / std[c].
        let padR = (0 - normalisation.mean.0) / normalisation.std.0
        let padG = (0 - normalisation.mean.1) / normalisation.std.1
        let padB = (0 - normalisation.mean.2) / normalisation.std.2

        var padded = [Float](repeating: 0, count: targetSize * targetSize * 3)
        var idx = 0
        for _ in 0..<(targetSize * targetSize) {
            padded[idx] = padR
            padded[idx + 1] = padG
            padded[idx + 2] = padB
            idx += 3
        }
        // Blit scaled region into top-left of the padded canvas.
        for y in 0..<scaledH {
            let srcRow = y * scaledW * 3
            let dstRow = y * targetSize * 3
            for c in 0..<(scaledW * 3) {
                padded[dstRow + c] = fp32[srcRow + c]
            }
        }

        // Step 7: cast to FP16 LE bytes (the only precision reduction in the pipeline).
        let bytes = FP16Bytes.encode(padded)
        return PreProcessedFrame(
            bytes: bytes,
            targetSize: targetSize,
            scaledWidth: scaledW,
            scaledHeight: scaledH,
            originalWidth: width,
            originalHeight: height
        )
    }

    private static func validateInputSize(
        imageBytes: Data, format: PixelFormat, width: Int, height: Int
    ) throws {
        let expected: Int
        switch format {
        case .rgb8: expected = width * height * 3
        case .bgra8, .rgba8: expected = width * height * 4
        }
        guard imageBytes.count == expected else {
            throw SegmentationError.invalidInputDimensions(
                "imageBytes has \(imageBytes.count) bytes; expected \(expected) for \(format) \(width)×\(height)"
            )
        }
    }
}

// MARK: - Internals

@inline(__always)
func canonicaliseToRGB8(_ src: Data, format: PixelFormat, width: Int, height: Int) -> Data {
    let n = width * height
    var rgb = Data(count: n * 3)
    src.withUnsafeBytes { srcRaw in
        rgb.withUnsafeMutableBytes { dstRaw in
            let s = srcRaw.bindMemory(to: UInt8.self).baseAddress!
            let d = dstRaw.bindMemory(to: UInt8.self).baseAddress!
            switch format {
            case .rgb8:
                for i in 0..<(n * 3) { d[i] = s[i] }
            case .bgra8:
                // Input: B G R A → output: R G B (channel swap + alpha drop).
                for i in 0..<n {
                    d[i * 3 + 0] = s[i * 4 + 2]
                    d[i * 3 + 1] = s[i * 4 + 1]
                    d[i * 3 + 2] = s[i * 4 + 0]
                }
            case .rgba8:
                // Input: R G B A → output: R G B (alpha drop).
                for i in 0..<n {
                    d[i * 3 + 0] = s[i * 4 + 0]
                    d[i * 3 + 1] = s[i * 4 + 1]
                    d[i * 3 + 2] = s[i * 4 + 2]
                }
            }
        }
    }
    return rgb
}

// Pixel-centre alignment (align_corners=False) — the default for PyTorch,
// coremltools, and ai-edge-torch resize ops, so the §6.5 contract holds across
// both export targets without tweaking.
func bilinearResizeRGB8ToNormalisedFP32(
    src: Data, srcW: Int, srcH: Int,
    dst: inout [Float], dstW: Int, dstH: Int,
    normalisation: NormalisationStatistics
) {
    let scaleX = Float(srcW) / Float(dstW)
    let scaleY = Float(srcH) / Float(dstH)
    let m0 = normalisation.mean.0; let s0 = normalisation.std.0
    let m1 = normalisation.mean.1; let s1 = normalisation.std.1
    let m2 = normalisation.mean.2; let s2 = normalisation.std.2

    src.withUnsafeBytes { srcRaw in
        let s = srcRaw.bindMemory(to: UInt8.self).baseAddress!
        for yd in 0..<dstH {
            let ys = (Float(yd) + 0.5) * scaleY - 0.5
            let ys0i = Int(ys.rounded(.down))
            let dy = ys - Float(ys0i)
            let y0 = max(0, min(srcH - 1, ys0i))
            let y1 = max(0, min(srcH - 1, ys0i + 1))
            for xd in 0..<dstW {
                let xs = (Float(xd) + 0.5) * scaleX - 0.5
                let xs0i = Int(xs.rounded(.down))
                let dx = xs - Float(xs0i)
                let x0 = max(0, min(srcW - 1, xs0i))
                let x1 = max(0, min(srcW - 1, xs0i + 1))

                let off00 = (y0 * srcW + x0) * 3
                let off01 = (y0 * srcW + x1) * 3
                let off10 = (y1 * srcW + x0) * 3
                let off11 = (y1 * srcW + x1) * 3
                let dstOff = (yd * dstW + xd) * 3

                // Channel 0 (R)
                let r00 = Float(s[off00]); let r01 = Float(s[off01])
                let r10 = Float(s[off10]); let r11 = Float(s[off11])
                let r0 = r00 * (1 - dx) + r01 * dx
                let r1 = r10 * (1 - dx) + r11 * dx
                let r  = r0  * (1 - dy) + r1  * dy
                dst[dstOff] = (r / 255 - m0) / s0

                // Channel 1 (G)
                let g00 = Float(s[off00 + 1]); let g01 = Float(s[off01 + 1])
                let g10 = Float(s[off10 + 1]); let g11 = Float(s[off11 + 1])
                let g0 = g00 * (1 - dx) + g01 * dx
                let g1 = g10 * (1 - dx) + g11 * dx
                let g  = g0  * (1 - dy) + g1  * dy
                dst[dstOff + 1] = (g / 255 - m1) / s1

                // Channel 2 (B)
                let b00 = Float(s[off00 + 2]); let b01 = Float(s[off01 + 2])
                let b10 = Float(s[off10 + 2]); let b11 = Float(s[off11 + 2])
                let b0 = b00 * (1 - dx) + b01 * dx
                let b1 = b10 * (1 - dx) + b11 * dx
                let b  = b0  * (1 - dy) + b1  * dy
                dst[dstOff + 2] = (b / 255 - m2) / s2
            }
        }
    }
}
