import CaptureKit
import Foundation
import SupportPlane

// Recomputes `LiDARStatus.foodRegionCoveragePercent` at shutter time per
// Req 4.1 and Decision 14. Iteration runs in confidence-buffer space (256×192
// on iPhone 13 Pro Max) — iterating colour-image space would be 56× more work
// for no additional signal because neighbouring 56-pixel mask blocks map to a
// single confidence value.
//
// Returns 0 when `depth` or `mask` is nil, or when no confidence pixel projects
// onto a 1-bit of the mask (Req 4.2). Otherwise returns
// `100 · numerator / denominator` where:
//   - denominator = count of (cx, cy) where mask.isFood(mx, my)
//   - numerator   = count of those (cx, cy) where confidence[cx,cy]/255 >= threshold
// and (mx, my) = (floor(cx·W_colour/W_conf), floor(cy·H_colour/H_conf)).
func computeFoodRegionCoverage(
    depth: DepthMap?,
    confidenceThreshold: Float,
    mask: BinaryMask?,
    colourWidth: Int,
    colourHeight: Int
) -> Float {
    guard let depth, let mask else { return 0 }
    let confW = depth.width
    let confH = depth.height
    guard confW > 0, confH > 0 else { return 0 }

    let thresholdByte = UInt8(min(255, max(0, Int((confidenceThreshold * 255).rounded()))))
    var foodCount = 0
    var hiConfCount = 0
    depth.confidenceBytes.withUnsafeBytes { rawConf in
        let confBuf = rawConf.bindMemory(to: UInt8.self).baseAddress!
        mask.pixels.withUnsafeBytes { rawMask in
            let maskBuf = rawMask.bindMemory(to: UInt8.self).baseAddress!
            for cy in 0..<confH {
                let my = (cy * mask.height) / confH
                let maskRow = my * mask.width
                let confRow = cy * confW
                for cx in 0..<confW {
                    let mx = (cx * mask.width) / confW
                    if maskBuf[maskRow + mx] != 0 {
                        foodCount += 1
                        if confBuf[confRow + cx] >= thresholdByte {
                            hiConfCount += 1
                        }
                    }
                }
            }
        }
    }
    _ = colourWidth     // signature retained for design clarity
    _ = colourHeight
    guard foodCount > 0 else { return 0 }
    return 100 * Float(hiConfCount) / Float(foodCount)
}
