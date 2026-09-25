import CoreGraphics
import SwiftUI

// The ONE place the captured buffer is turned upright for the post-capture
// surfaces (meal review, meal detail).
//
// `RawFrame.imageBytes` — and therefore the saved Photos asset, the mask PNG
// and every unit coordinate derived from it — is ARKit's sensor-native
// landscape 4:3 buffer. The phone is held portrait, and the capture screen
// already turns its own previews with `RawFrameImage.portraitOrientation`
// (`.right`, a quarter turn clockwise). The review and detail surfaces used to
// show the buffer unturned, so the photo read 90° off from the viewfinder.
//
// Photo, contours, badges, the card quad and tap hit-testing must all take the
// SAME turn or they come apart, so they all come through here: the photo (and
// the tinted mask overlay) through `displayRotation`, and every unit-square
// coordinate through `displayPoint`. There is deliberately no second mapping —
// callers never write their own transpose.
enum ReviewPhotoOrientation {

    // The display turn: a quarter turn clockwise, matching
    // `RawFrameImage.portraitOrientation` (`.right`). Applied to whole raster
    // layers (the photo, the tinted mask overlay) with `.rotationEffect`.
    static let displayRotation = Angle.degrees(90)

    // A unit-square point in BUFFER space to the same point in upright DISPLAY
    // space. A quarter turn clockwise sends (x, y) to (1 - y, x): buffer
    // top-left lands at display top-right. Unit-to-unit, so the 4:3 -> 3:4
    // aspect change is already carried by whatever size the unit square is
    // drawn at.
    static func displayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.y, y: point.x)
    }

    // Width over height of the upright photo: the buffer's 4:3 landscape,
    // turned.
    static let displayAspect: CGFloat = 3.0 / 4.0

    // The largest whole upright photo that fits `available`.
    static func fittedBox(in available: CGSize) -> CGSize {
        let height = min(available.height, available.width / displayAspect)
        return CGSize(width: height * displayAspect, height: height)
    }
}

extension MaskContour {
    // The same loop with its geometry turned upright. Points and centroid go
    // through `displayPoint`; `area` is a fraction of the image and a rotation
    // does not change it.
    func uprightForDisplay() -> MaskContour {
        MaskContour(
            points: points.map(ReviewPhotoOrientation.displayPoint),
            area: area,
            centroid: ReviewPhotoOrientation.displayPoint(centroid)
        )
    }
}

extension MaskContourSet {
    // Every contour turned upright, once, at the point the set enters the view.
    // Badges, dimming, the accessibility shadow and hit-testing all read the
    // contours, so turning them here turns all four with no further mapping.
    //
    // `rasterWidth` / `rasterHeight` deliberately stay the BUFFER raster's
    // dimensions: they exist only to normalise pipeline pixel geometry (the
    // card's `cornersImagePx`), which is itself in buffer pixels. That
    // normalised point is then passed through `displayPoint` like everything
    // else, so both paths end in the same upright unit square.
    func uprightForDisplay() -> MaskContourSet {
        MaskContourSet(
            presentClassIds: presentClassIds,
            contoursByClassId: contoursByClassId.mapValues { loops in
                loops.map { $0.uprightForDisplay() }
            },
            rasterWidth: rasterWidth,
            rasterHeight: rasterHeight
        )
    }
}
