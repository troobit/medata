import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Req 7.5: the three plane-fit bugfixes that predate this feature must still
// hold on the path that replaces the one they were fixed on. Their own
// regression tests (`LiDARPlaneFitterTests`) still guard the edge-band fitter,
// which is unchanged and remains the fallback — these assert the same three
// properties of `SupportRegion`, which is now what a device capture actually
// runs through.
@Suite("Prior plane-fit bugfixes hold on the promoted path (Req 7.5)")
struct SupportRegionPriorBugfixTests {

    // `lidar-plane-fit-oom-on-device-1920x1440`: the pre-feature scan enumerated
    // candidates over the 1920x1440 COLOUR grid while sampling depth from a
    // 256x192 map, replicating each measurement ~56x, and allocated 32 GB doing
    // it. The fix here is structural rather than a cap — `prepare` walks the
    // native depth grid and nothing downstream ever sees a colour index (Req 2.4)
    // — so the assertion is on the size of the set that competes.
    @Test("candidates are bounded by the depth grid, not the 1920x1440 colour grid")
    func candidateSetIsBoundedByTheDepthGrid() {
        let grid = SPRScene.plateAboveTable()
        let depth = SPRScene.makeDepth(grid)
        let colour = Self.deviceColourIntrinsics
        let mask = Self.expandMask(grid, toWidth: colour.imageWidth, height: colour.imageHeight)

        guard let fit = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: colour,
            foodRegionMask: mask, gravityCamera: SPRScene.gravity
        ) else {
            Issue.record("expected a food-support fit at device grids")
            return
        }

        let depthGridSize = depth.width * depth.height
        let colourGridSize = colour.imageWidth * colour.imageHeight
        #expect(fit.annulusSampleCount <= depthGridSize,
                """
                \(fit.annulusSampleCount) candidates against a \(depthGridSize)-sample \
                depth grid — the set is being enumerated on some grid other than depth's
                """)
        #expect(fit.inlierCount <= depthGridSize)
        // The margin the bugfix bought, stated rather than implied: ~56x on this
        // capture geometry, and it is the whole reason the allocation cannot recur.
        #expect(colourGridSize / depthGridSize >= 50,
                "scene must reproduce the device's colour-to-depth ratio")
    }

    // `lidar-plane-fit-degenerate-on-clean-capture`: an exactly-planar sample set
    // has a rank-2 scatter matrix, which `LiDARPlaneFitter.refine`'s stability
    // gate rejects. `SupportRegion` calls that same `refine`, so it inherits the
    // gate — and a clean capture, which is precisely the one whose plate and
    // table are nearly noiseless, must still produce a fit rather than a refusal.
    @Test("a clean, near-noiseless capture fits rather than refusing as degenerate")
    func cleanCaptureIsNotRejectedAsDegenerate() {
        let grid = SPRScene.plateAboveTable()
        // 0.05 mm is an order of magnitude below the scenes' default 0.3 mm and
        // two below the +/-5 mm inlier band: as close to exactly planar as a
        // capture gets before the scatter matrix loses rank.
        let depth = SPRScene.makeDepth(grid, noiseMm: 0.05)

        guard let fit = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: SPRScene.makeColourMask(grid), gravityCamera: SPRScene.gravity
        ) else {
            Issue.record("clean capture refused — the degeneracy gate has regressed")
            return
        }
        #expect(fit.plane.distanceMm.isFinite && fit.plane.normal.z.isFinite)
        #expect(fit.plane.residualMm <= LiDARPlaneFitter.residualMaxMm)
        #expect(abs(SPRScene.heightMm(of: fit.plane) - 20) < 3,
                "fitted \(SPRScene.heightMm(of: fit.plane)) mm above the table, not the plate's 20 mm")
    }

    // `lidar-plane-fit-matte-table-confidence` (2026-07-06: "1 view complained of
    // no flat surface on a matte table"). A matte surface returns a weaker LiDAR
    // signal, so ARKit reports MEDIUM (127) rather than HIGH; the pre-fix
    // tau_conf of 0.66 dropped every such sample and starved the fit. `prepare`
    // filters on the same `LiDARPlaneFitter.confidenceThreshold`, so the fix
    // carries — but only as long as nothing here re-tightens it.
    @Test("a matte table at uniform medium confidence still fits the plate")
    func matteTableAtMediumConfidenceStillFits() {
        var grid = SPRScene.plateAboveTable()
        grid.confidence = [UInt8](repeating: 127, count: grid.width * grid.height)

        guard let fit = SPRScene.fit(grid) else {
            Issue.record("medium-confidence capture refused — tau_conf has regressed above 127/255")
            return
        }
        #expect(abs(SPRScene.heightMm(of: fit.plane) - 20) < 3)
    }

    // The lower bound of the same fix: genuine LOW/zero-confidence returns must
    // still be dropped, or the fitter reads noise as geometry. With no valid
    // sample anywhere the restricted fit returns nil and the caller falls back.
    @Test("an all-low-confidence capture is starved rather than fitting noise")
    func lowConfidenceCaptureIsStarved() {
        var grid = SPRScene.plateAboveTable()
        grid.confidence = [UInt8](repeating: 0, count: grid.width * grid.height)
        #expect(SPRScene.fit(grid) == nil)
    }

    // MARK: - Helpers

    // The device's real colour intrinsics, sized so the derived depth focal
    // length matches the scenes' 175 px (fx_c = 175 x 1920/256).
    private static let deviceColourIntrinsics = CameraIntrinsics(
        fx: 1312.5, fy: 1312.5, cx: 959.5, cy: 719.5,
        distortion: [], imageWidth: 1920, imageHeight: 1440
    )

    // `SPRScene.makeColourMask` is fixed at 1024x768; this renders the same
    // depth-grid food region onto an arbitrary colour grid.
    private static func expandMask(_ grid: SPRScene.Grid, toWidth w: Int, height h: Int) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: w * h)
        let sx = Float(grid.width) / Float(w)
        let sy = Float(grid.height) / Float(h)
        for cy in 0..<h {
            let dy = min(grid.height - 1, max(0, Int((Float(cy) + 0.5) * sy)))
            for cx in 0..<w {
                let dx = min(grid.width - 1, max(0, Int((Float(cx) + 0.5) * sx)))
                pixels[cy * w + cx] = grid.food[dy * grid.width + dx] ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: w, height: h)
    }
}
