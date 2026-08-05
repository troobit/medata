#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Task 15: the device and the offline replay derive the SAME support plane
// (Req 5.1), so a β_c fitted offline is valid when applied on device.
//
// The tolerance documented by Req 5.1 is ZERO here, and that is the point of the
// test: parity is structural rather than numerical, because `FixtureRunner` and
// `Pipeline` call one implementation — `LiDARSupportPlaneFitter.fitFromDepth`.
// A non-zero tolerance would only be needed if the two paths held separate code,
// which is exactly what this test exists to prevent regrowing. (The separate
// device-versus-replay divergence measured on a real capture — ~5 %, from camera
// and segmenter differences that precede the fitter — is a task 26 corpus
// measurement, not a property of this function.)
@Suite("Device and offline derive the same support plane (Req 5.1)")
struct SupportPlaneParityTests {

    // MARK: – Parity

    @Test("the restricted fit is bit-identical across the device and offline entry points")
    func restrictedFitIsIdenticalOnBothPaths() throws {
        let scene = ParityScene.plateAboveTable()
        let device = ParityScene.deviceFit(scene)
        let offline = try ParityScene.offlineFit(scene)

        let devicePlane = try #require(device.plane)
        #expect(device.stats.reference == .foodSupport,
                "precondition: the scene must take the restricted fit")
        #expect(offline.reference == .foodSupport)
        expectIdentical(offline.plane, devicePlane)
    }

    @Test("the fallback plane is bit-identical across the device and offline entry points")
    func fallbackFitIsIdenticalOnBothPaths() throws {
        // Food across a flat plate's edge is rejected on sectors (Decision 18), so
        // this scene reaches the edge-band fallback through the selection path.
        let scene = ParityScene.foodAcrossPlateEdge(edgeOffsetPx: 2)
        let device = ParityScene.deviceFit(scene)
        let offline = try ParityScene.offlineFit(scene)

        let devicePlane = try #require(device.plane)
        #expect(device.stats.reference == .edgeBand,
                "precondition: the scene must fall back")
        #expect(offline.reference == .edgeBand)
        expectIdentical(offline.plane, devicePlane)
    }

    // A refusal must also transfer: the offline runner converts it into a skipped
    // fixture rather than substituting a plane of its own.
    @Test("a capture the device refuses is skipped offline, not fitted differently")
    func refusalTransfers() {
        let scene = ParityScene.plateAboveTable()
        let blank = ParityScene.blankDepth()
        let device = LiDARSupportPlaneFitter().fitOutcome(
            nadir: ParityScene.frame(scene, depth: blank), cardPose: nil, corners: nil,
            preShutterFoodMask: ParityScene.colourMask(scene))
        #expect(device.plane == nil)
        #expect(throws: FixtureRunner.Error.self) {
            _ = try FixtureRunner.fitSupportPlane(
                depth: blank, intrinsics: ParityScene.colourIntrinsics,
                gravity: ParityScene.gravity, foodMask: ParityScene.colourMask(scene),
                fixtureID: "blank")
        }
    }

    private func expectIdentical(_ offline: SupportPlane, _ device: SupportPlane) {
        #expect(offline.normal.x == device.normal.x)
        #expect(offline.normal.y == device.normal.y)
        #expect(offline.normal.z == device.normal.z)
        #expect(offline.distanceMm == device.distanceMm)
        #expect(offline.residualMm == device.residualMm)
        #expect(offline.convergedIterations == device.convergedIterations)
    }
}

// Nadir scenes for the parity suite. Deliberately a small local copy of the
// `SupportPlaneTests` scene builder rather than a shared target: the two suites
// are in different modules, and the geometry a parity test needs is two scenes,
// not the fourteen the selection suite exercises.
//
// The camera looks straight down, so a gravity-aligned plane has normal (0,0,1)
// and a point's signed height above a plane at depth Z is (Z − depth). The
// intrinsics resolve ~2 mm per depth pixel at 350 mm: fx_d = 700 × 256/1024 = 175,
// and 350/175 = 2.0.
enum ParityScene {
    static let colourWidth = 1024
    static let colourHeight = 768
    static let depthWidth = 256
    static let depthHeight = 192
    static let tableDepthMm: Float = 350

    static let colourIntrinsics = CameraIntrinsics(
        fx: 700, fy: 700, cx: 511.5, cy: 383.5,
        distortion: [], imageWidth: colourWidth, imageHeight: colourHeight)
    static let gravity = Vec3(0, 0, 1)

    struct Grid {
        var heightMm: [Float]      // mm above the table, +ve towards the camera
        var food: [Bool]
    }

    static func grid(_ build: (Int, Int) -> (heightMm: Float, isFood: Bool)) -> Grid {
        var heights = [Float](repeating: 0, count: depthWidth * depthHeight)
        var food = [Bool](repeating: false, count: depthWidth * depthHeight)
        for y in 0..<depthHeight {
            for x in 0..<depthWidth {
                let sample = build(x, y)
                heights[y * depthWidth + x] = sample.heightMm
                food[y * depthWidth + x] = sample.isFood
            }
        }
        return Grid(heightMm: heights, food: food)
    }

    // A plate 20 mm above the table with food on it — the case the pre-feature
    // band scan fits the table on.
    static func plateAboveTable(foodRadiusPx: Float = 12.5, plateRadiusPx: Float = 28,
                                plateHeightMm: Float = 20, foodHeightMm: Float = 8) -> Grid {
        grid { x, y in
            let r = radius(x, y)
            if r <= foodRadiusPx { return (plateHeightMm + foodHeightMm, true) }
            return (r <= plateRadiusPx ? plateHeightMm : 0, false)
        }
    }

    // Food half on a plate and half on the worktop; the plate edge is rotated so
    // the supported arc is centred on a sector rather than a sector boundary.
    static func foodAcrossPlateEdge(foodRadiusPx: Float = 12.5, edgeOffsetPx: Float,
                                    edgeAngleDeg: Float = 22.5,
                                    plateHeightMm: Float = 20,
                                    foodHeightMm: Float = 8) -> Grid {
        let theta = edgeAngleDeg * .pi / 180
        let ux = cos(theta), uy = sin(theta)
        return grid { x, y in
            let dx = Float(x) - 128, dy = Float(y) - 96
            if radius(x, y) <= foodRadiusPx { return (plateHeightMm + foodHeightMm, true) }
            return (dx * ux + dy * uy <= edgeOffsetPx ? plateHeightMm : 0, false)
        }
    }

    static func radius(_ x: Int, _ y: Int) -> Float {
        let dx = Float(x) - 128, dy = Float(y) - 96
        return (dx * dx + dy * dy).squareRoot()
    }

    // `depthIntrinsics` is written as ALL ZEROS, exactly as ARKitCaptureEngine
    // writes it on device. A deterministic ±0.3 mm of noise keeps the scatter
    // matrix well conditioned without moving any sample out of the ±5 mm band.
    static func depth(_ g: Grid) -> DepthMap {
        var bytes = Data(count: depthWidth * depthHeight * 4)
        bytes.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for i in 0..<(depthWidth * depthHeight) {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let unit = Float(state >> 40) / Float(1 << 24)
                buffer[i] = tableDepthMm - g.heightMm[i] + (unit - 0.5) * 0.6
            }
        }
        return DepthMap(
            depthBytesMm: bytes,
            confidenceBytes: Data(repeating: 255, count: depthWidth * depthHeight),
            width: depthWidth, height: depthHeight, rowStrideBytes: depthWidth * 4,
            depthIntrinsics: CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, distortion: [],
                                              imageWidth: depthWidth, imageHeight: depthHeight),
            depthFromColour: .identity)
    }

    static func blankDepth() -> DepthMap {
        DepthMap(
            depthBytesMm: Data(count: depthWidth * depthHeight * 4),
            confidenceBytes: Data(repeating: 255, count: depthWidth * depthHeight),
            width: depthWidth, height: depthHeight, rowStrideBytes: depthWidth * 4,
            depthIntrinsics: CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, distortion: [],
                                              imageWidth: depthWidth, imageHeight: depthHeight),
            depthFromColour: .identity)
    }

    // The mask the pipeline hands the fitter is colour-grid; scenes author it on
    // the depth grid. The grids differ by exactly 4×, so the expansion is lossless.
    static func colourMask(_ g: Grid) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: colourWidth * colourHeight)
        for cy in 0..<colourHeight {
            let dy = min(depthHeight - 1, Int((Float(cy) + 0.5) * Float(depthHeight) / Float(colourHeight)))
            for cx in 0..<colourWidth {
                let dx = min(depthWidth - 1, Int((Float(cx) + 0.5) * Float(depthWidth) / Float(colourWidth)))
                pixels[cy * colourWidth + cx] = g.food[dy * depthWidth + dx] ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: colourWidth, height: colourHeight)
    }

    static func frame(_ g: Grid, depth d: DepthMap? = nil) -> RawFrame {
        RawFrame(
            imageBytes: Data(count: colourWidth * colourHeight * 4),
            pixelFormat: .bgra8, colourSpace: .sRGB, orientation: 1,
            imageWidth: colourWidth, imageHeight: colourHeight,
            timestampMonotonicNs: 1,
            intrinsics: colourIntrinsics, gravity: gravity,
            worldFromCamera: .identity, depth: d ?? depth(g))
    }

    // The device entry point: the pipeline's fitter, driven by a `RawFrame`.
    static func deviceFit(_ g: Grid) -> SupportPlaneFitOutcome {
        LiDARSupportPlaneFitter().fitOutcome(
            nadir: frame(g), cardPose: nil, corners: nil, preShutterFoodMask: colourMask(g))
    }

    // The offline entry point: the harness replay path used by `FixtureRunner.run`.
    static func offlineFit(_ g: Grid) throws -> FixtureRunner.SingleViewPlaneFit {
        try FixtureRunner.fitSupportPlane(
            depth: depth(g), intrinsics: colourIntrinsics, gravity: gravity,
            foodMask: colourMask(g), fixtureID: "parity")
    }
}
#endif
