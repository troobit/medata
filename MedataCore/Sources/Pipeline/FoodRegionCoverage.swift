import CaptureKit
import Foundation
import Segmentation
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

// MARK: - Fail-closed food-coverage gate (estimation-runtime-consistency)

// Minimum fraction of frame pixels that must carry a food or recognised liquid
// argmax label for the estimate to proceed. Below this the volume→β→carbs
// chain is driven by a handful of noisy depth samples and β multiplies that
// noise straight into the carb number, so run-to-run readings of the same
// plate vary wildly. 0.001 (0.1 % of the frame, ~2 765 px at 1920×1440) sits
// well below any genuine meal — device masks put food at 1–8 % of the frame —
// so real plates are unaffected while speckle-only masks refuse legibly.
let minimumFoodCoverageFraction: Float = 0.001

// Fraction of frame pixels whose argmax label is a food or recognised liquid
// class — exactly the pixels eligible to contribute volume in either estimator
// (HeightFieldEstimator / VoxelCarveEstimator integration predicates).
func foodCoverageFraction(argmax: ArgmaxMap, palette: ClassPalette) -> Float {
    let total = argmax.width * argmax.height
    guard total > 0 else { return 0 }
    var food = 0
    argmax.pixels.withUnsafeBytes { raw in
        let buf = raw.bindMemory(to: UInt8.self).baseAddress!
        for i in 0..<total {
            let c = Int(buf[i])
            if palette.isFoodClass(c) || palette.isLiquidClass(c) { food += 1 }
        }
    }
    return Float(food) / Float(total)
}

// Refuses a near-empty mask with the EXISTING `noFoodPixels` refusal — §5 edge
// case 3 ("zero food pixels survive the silhouette test") extends naturally to
// "too few food pixels to estimate". Coverage exactly at the threshold accepts.
func enforceMinimumFoodCoverage(argmax: ArgmaxMap, palette: ClassPalette) throws {
    if foodCoverageFraction(argmax: argmax, palette: palette) < minimumFoodCoverageFraction {
        throw EstimationFailure.noFoodPixels
    }
}
