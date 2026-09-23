import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Task 1: depth-intrinsics derivation and colour-to-depth mask downsampling
// (Reqs 2.1, 2.4).
@Suite("SupportRegion depth intrinsics and mask downsampling (Reqs 2.1, 2.4)")
struct SupportRegionGeometryTests {

    // The device's real grids: a 1920×1440 colour frame against a 256×192 depth map,
    // which is where the design's 3.25-colour-pixel figure comes from.
    private static let deviceColour = CameraIntrinsics(
        fx: 1312.5, fy: 1312.5, cx: 959.5, cy: 719.5,
        distortion: [], imageWidth: 1920, imageHeight: 1440
    )
    private static let deviceScale = Float(256) / Float(1920)

    @Test("focal length scales by W_d/W_c and the principal point carries the half-pixel terms")
    func derivesDepthIntrinsicsFromColour() {
        let depth = SPRScene.makeDepth(SPRScene.plateAboveTable())
        let kd = SupportRegion.depthIntrinsics(from: Self.deviceColour, depth: depth)
        let kc = Self.deviceColour
        let sx = Float(depth.width) / Float(kc.imageWidth)
        let sy = Float(depth.height) / Float(kc.imageHeight)

        #expect(abs(kd.fx - kc.fx * sx) < 1e-3, "fx_d must be fx_c · W_d/W_c; got \(kd.fx)")
        #expect(abs(kd.fy - kc.fy * sy) < 1e-3)
        #expect(abs(kd.cx - ((kc.cx + 0.5) * sx - 0.5)) < 1e-3,
                "cx_d must be (cx_c + 0.5)·W_d/W_c − 0.5; got \(kd.cx)")
        #expect(abs(kd.cy - ((kc.cy + 0.5) * sy - 0.5)) < 1e-3)
        #expect(kd.imageWidth == depth.width && kd.imageHeight == depth.height)
    }

    // The half-pixel terms are what this asserts; dropping them is a real offset, not
    // a rounding artefact. The design corrects the magnitude to 0.5(1 − s) = 0.433
    // depth px = 3.25 colour px (an earlier draft said 3.75).
    @Test("dropping the half-pixel terms shifts the principal point by 3.25 colour pixels")
    func halfPixelTermsAreNotOptional() {
        let depth = SPRScene.makeDepth(SPRScene.plateAboveTable())
        let kd = SupportRegion.depthIntrinsics(from: Self.deviceColour, depth: depth)
        let naive = Self.deviceColour.cx * Self.deviceScale
        let shiftDepthPx = naive - kd.cx

        #expect(abs(shiftDepthPx - 0.5 * (1 - Self.deviceScale)) < 1e-3,
                "expected a 0.5(1 − s) depth-pixel shift; got \(shiftDepthPx)")
        #expect(abs(shiftDepthPx / Self.deviceScale - 3.25) < 0.05,
                "0.433 depth px is 3.25 colour px; got \(shiftDepthPx / Self.deviceScale)")
    }

    // `ARKitCaptureEngine` writes CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, …) into
    // every device depth map. Reading it divides by zero and yields a NaN plane.
    @Test("derivation ignores depth.depthIntrinsics, which is all zeros on device")
    func doesNotReadDeviceDepthIntrinsics() {
        let depth = SPRScene.makeDepth(SPRScene.plateAboveTable())
        #expect(depth.depthIntrinsics.fx == 0, "scene must reproduce the device's zeroed intrinsics")

        let kd = SupportRegion.depthIntrinsics(from: SPRScene.colourIntrinsics, depth: depth)
        #expect(kd.fx > 0 && kd.fy > 0)

        // And the whole path stays finite: an fx of 0 would surface as a NaN plane.
        let mask = SPRScene.makeColourMask(SPRScene.plateAboveTable())
        let fit = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: mask, gravityCamera: SPRScene.gravity
        )
        guard let plane = fit?.plane else {
            Issue.record("expected a food-support fit on the plate scene")
            return
        }
        #expect(plane.distanceMm.isFinite, "plane distance must be finite")
        #expect(plane.normal.z.isFinite)
    }

    // Req 2.1 requires the fitted set to contain NO food pixel, so a depth pixel that
    // is only partly covered by food must resolve towards exclusion.
    @Test("a depth pixel is food when ANY covered colour pixel is food")
    func downsampleResolvesTowardsExclusion() {
        var pixels = [UInt8](repeating: 0, count: SPRScene.colourWidth * SPRScene.colourHeight)
        // A single food colour pixel, one of the sixteen covered by depth pixel (1,0).
        pixels[7] = 1
        let mask = BinaryMask(pixels: pixels, width: SPRScene.colourWidth, height: SPRScene.colourHeight)

        let down = SupportRegion.downsampleFoodMask(
            mask, width: SPRScene.depthWidth, height: SPRScene.depthHeight
        )
        #expect(down.isFood(x: 1, y: 0), "one food colour pixel must mark its depth pixel")
        #expect(!down.isFood(x: 0, y: 0), "an uncovered depth pixel must not be marked")
        #expect(!down.isFood(x: 2, y: 0))
        #expect(!down.isFood(x: 1, y: 1))
    }

    @Test("downsampling is the identity when the grids already match")
    func downsampleIsIdentityOnMatchingGrid() {
        var pixels = [UInt8](repeating: 0, count: 16 * 16)
        pixels[5 * 16 + 5] = 1
        let mask = BinaryMask(pixels: pixels, width: 16, height: 16)
        let down = SupportRegion.downsampleFoodMask(mask, width: 16, height: 16)
        #expect(down.pixels == mask.pixels)
    }

    @Test("the downsampled mask covers the scene's food region on the depth grid")
    func downsampleRoundTripsASceneMask() {
        let scene = SPRScene.plateAboveTable()
        let down = SupportRegion.downsampleFoodMask(
            SPRScene.makeColourMask(scene),
            width: scene.width, height: scene.height
        )
        var missing = 0
        for i in 0..<(scene.width * scene.height) where scene.food[i] && down.pixels[i] == 0 {
            missing += 1
        }
        #expect(missing == 0, "\(missing) food pixels were lost in the downsample")
    }
}
