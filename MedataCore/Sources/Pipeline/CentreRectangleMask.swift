import SupportPlane

// Phase 1 spatial prior for the LiDAR support-plane fit: a `BinaryMask` whose
// `1` pixels form an axis-aligned, centred rectangle of size
// `fillFraction × fillFraction` (proportion of the image), and whose `0` pixels
// form the surrounding border. `LiDARPlaneFitter.collectCandidatePoints` reads
// the bounding box of the `1` region and scans the band *below* it for table
// pixels; with a centred rectangle the band sits on the table surrounding the
// plate. See `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/`.
//
// Until a pre-shutter segmentation pass is wired, this is the closest correct
// approximation to the real food region under the documented capture envelope
// (centred plate, near-0° tilt, ~30-40 cm distance).

// Fraction of the image width/height covered by the centred rectangle.
// 0.7 is calibrated to the iPhone 13 Pro Max main wide camera (~67° HFOV) at
// the gating distance (~30 cm): a ~25 cm plate fills ~63% of the frame, so a
// 70% inner rectangle contains it with a small margin and the bottom 15% band
// of the frame falls on visible table pixels. See decision_log.md Decision 1.
let centreRectangleFillFraction: Float = 0.7

// Build a `BinaryMask` whose `1` pixels form a centred rectangle of
// `fillFraction × fillFraction` of the image and whose `0` pixels form the
// surrounding border. Row-major pixel layout to match `BinaryMask`'s
// `isFood(x:y:)` accessor.
//
// `fillFraction` must be in `(0, 1]`. The horizontal span is
// `[ceil(border * width), floor((1 - border) * width))` where
// `border = (1 - fillFraction) / 2`, and likewise for the vertical span.
func makeCentreRectangleMask(width: Int, height: Int, fillFraction: Float) -> BinaryMask {
    precondition(fillFraction > 0 && fillFraction <= 1,
                 "fillFraction must be in (0, 1]")
    precondition(width > 0 && height > 0,
                 "width and height must be positive")
    let border = (1 - fillFraction) / 2
    let xMin = Int((border * Float(width)).rounded(.up))
    let xMax = Int(((1 - border) * Float(width)).rounded(.down))
    let yMin = Int((border * Float(height)).rounded(.up))
    let yMax = Int(((1 - border) * Float(height)).rounded(.down))
    var pixels = [UInt8](repeating: 0, count: width * height)
    if xMin < xMax && yMin < yMax {
        for y in yMin..<yMax {
            let rowBase = y * width
            for x in xMin..<xMax {
                pixels[rowBase + x] = 1
            }
        }
    }
    return BinaryMask(pixels: pixels, width: width, height: height)
}
