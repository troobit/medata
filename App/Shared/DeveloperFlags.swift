#if FIELD_LOOP
import CaptureKit
import Foundation

// Developer-phase runtime switches (two-view-trust Req 4.5 and the oblique-band
// measurement below). The WHOLE file is `#if FIELD_LOOP`, and so is every call
// site, so the ProductRelease build compiles exactly what it compiled before
// this file existed — there is no flag to read and no branch to fold away.
//
// FIELD_LOOP and not DEBUG: these switches exist to be flipped between two
// captures on the phone, and the phone runs a Release build — Debug substitutes
// the stub segmenter (`DEV_STUB_SEGMENTER`) and cannot recognise food at all.
// Gating them on DEBUG put them in the one build that could not use them.
//
// Why a runtime switch and not a compile-time flag: `HARNESS_ENABLED` and
// `DEV_STUB_SEGMENTER` gate code that must never be *compiled* into the
// shipping binary. These two are things the developer flips between two
// captures while standing over a plate, so they need a store the phone can
// change without a rebuild. `UserDefaults` is that store; Settings › Developer
// is the only writer.
//
// `nonisolated` because the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
// MainActor` and `CaptureFlowModel` reads these from a `@Sendable` closure.
// A `UserDefaults` read is thread-safe (Apple documents internal locking).
nonisolated enum DeveloperFlags {
    /// Clear depth from every frame the pipeline receives and report the device
    /// as having no LiDAR, so the non-LiDAR two-view + ID-1 card path runs on a
    /// phone that does have LiDAR (Req 4.5). Without it that branch is
    /// unreachable on the hardware in hand: `Pipeline.estimate` selects the
    /// card-only scale on `nadir.depth == nil`, and an iPhone 16 Pro never
    /// produces that.
    static let forceNonLiDARKey = "medata.debug.forceNonLiDAR"

    /// Stop the oblique tilt band from gating the shutter, so an oblique can be
    /// shot at any angle. Measured 2026-09-25 with a synthetic control (exact
    /// silhouettes, real intrinsics, real baseline): a 337 cm³ box carves as
    /// 801 cm³ at 26°, 712 cm³ at 40°, 552 cm³ at 60°. Two silhouette cones
    /// only close the top of the hull once h·tan(θ) exceeds the object's extent
    /// along the tilt direction — about 74° for that roll — so the shipped band
    /// (|Δθ − 25°| ≤ 15°, i.e. 10–40°) guarantees the hull never closes and,
    /// without LiDAR, leaves height unbounded. The switch exists to measure
    /// what a wider band buys before any band is changed. It changes ONLY
    /// whether the tilt blocks the shutter: the angle is measured, displayed
    /// and recorded exactly as before.
    static let unlockObliqueTiltKey = "medata.debug.unlockObliqueTilt"

    /// Meal review photo, attempt 2. The photo is upright either way; this
    /// chooses what the upright 3:4 photo does with a screen that is wider than
    /// it is tall at the 40% height budget. Off (attempt 1) shows the WHOLE
    /// photo, centred, with empty gutters at the sides. On (attempt 2) widens
    /// the photo to the full column and lets the rounded clip crop the top and
    /// bottom away, so the food is larger but the edges of the scene are gone.
    /// Overlays follow the photo in both: the contour unit square is always the
    /// whole image, visible or clipped.
    static let reviewPhotoFillsWidthKey = "medata.debug.reviewPhotoFillsWidth"

    /// Review swap loop, attempt 2 (specs/ui/review-swap-loop, MD-29). Off
    /// (attempt 1): a wrong food is swapped through the ⇄ sheet — two taps
    /// on the shortlist. On (attempt 2): each row also carries a chip line —
    /// the predicted food and the top three shortlist entries — so the swap
    /// is one tap and the predicted chip is the one-tap undo. The sheet stays
    /// either way; the chips only shortcut it.
    static let inlineFoodChipsKey = "medata.debug.inlineFoodChips"

    static var forceNonLiDAR: Bool {
        UserDefaults.standard.bool(forKey: forceNonLiDARKey)
    }

    static var unlockObliqueTilt: Bool {
        UserDefaults.standard.bool(forKey: unlockObliqueTiltKey)
    }

    static var reviewPhotoFillsWidth: Bool {
        UserDefaults.standard.bool(forKey: reviewPhotoFillsWidthKey)
    }

    static var inlineFoodChips: Bool {
        UserDefaults.standard.bool(forKey: inlineFoodChipsKey)
    }
}

extension RawFrame {
    /// The same frame with its depth map removed — the one thing that makes the
    /// pipeline take the card branch (`Pipeline.estimate` tests
    /// `nadir.depth == nil`). Everything else about the frame, including the
    /// intrinsics and the pose, is untouched: this rehearses a phone without a
    /// depth sensor, not a phone with a different camera.
    func clearingDepth() -> RawFrame {
        RawFrame(
            imageBytes: imageBytes,
            pixelFormat: pixelFormat,
            colourSpace: colourSpace,
            orientation: orientation,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            timestampMonotonicNs: timestampMonotonicNs,
            intrinsics: intrinsics,
            gravity: gravity,
            worldFromCamera: worldFromCamera,
            depth: nil,
            sessionGeneration: sessionGeneration
        )
    }
}
#endif
