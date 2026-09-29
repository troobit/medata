#if HARNESS_ENABLED
import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Tests for the plate-region support-plane mask (spec tasks 11–12, design
// §Support plane, Decision 15 amendment).
//
// N5k's overhead frame shows the table around the plate, and the table is the
// largest planar region — an unrestricted RANSAC lands on it, violating
// Req 3.6 (integrate above the plate top). The fix: a flood fill on 4-neighbour
// depth continuity (|Δz| ≤ documented threshold) seeded at the frame centre
// stops at the plate-rim discontinuity; the plane is then fitted inside that
// region only.
//
// Geometry: camera at origin, −Z forward, gravity (0,0,−1) (nadir rig).
// Table at 600 mm, plate top at 580 mm (20 mm rim — well above the 5 mm
// continuity threshold and the RANSAC inlier band).
@Suite("Plate-region support plane (N5k)")
struct PlateRegionPlaneTests {

    static let w = 100, h = 100
    static let tableMm: Float = 600
    static let plateMm: Float = 580
    static let plateCentre = (x: 50, y: 50)
    static let plateRadius = 32

    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: w, imageHeight: h)
    let gravity = Vec3(0, 0, -1)

    static func isOnPlate(_ x: Int, _ y: Int) -> Bool {
        let dx = x - plateCentre.x, dy = y - plateCentre.y
        return dx * dx + dy * dy <= plateRadius * plateRadius
    }

    func makeDepth(confidence: Data? = nil,
                   depthMm: (Int, Int) -> Float) -> DepthMap {
        var bytes = Data(count: Self.w * Self.h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Float.self).baseAddress!
            for y in 0..<Self.h {
                for x in 0..<Self.w {
                    buf[y * Self.w + x] = depthMm(x, y)
                }
            }
        }
        return DepthMap(
            depthBytesMm: bytes,
            confidenceBytes: confidence ?? Data(repeating: 255, count: Self.w * Self.h),
            width: Self.w, height: Self.h, rowStrideBytes: Self.w * 4,
            depthIntrinsics: k, depthFromColour: .identity
        )
    }

    // Plate raised above the table, with a gently-sloped food dome at the
    // centre (max gradient < continuity threshold, so the fill crosses it).
    func plateSceneDepth(x: Int, y: Int) -> Float {
        guard Self.isOnPlate(x, y) else { return Self.tableMm }
        let dx = Float(x - Self.plateCentre.x), dy = Float(y - Self.plateCentre.y)
        let r = (dx * dx + dy * dy).squareRoot()
        // Food dome: 15 mm peak over radius 12 → slope ≤ 2.5 mm/px.
        let domeHeight = max(0, 15 * (1 - r / 12))
        return Self.plateMm - domeHeight
    }

    // MARK: - Flood-fill mask (task 11)

    @Test("Flood fill from the frame centre stops at the plate-rim discontinuity")
    func floodFillStopsAtPlateRim() throws {
        let depth = makeDepth(depthMm: plateSceneDepth)
        let mask = try #require(FixtureRunner.plateRegionMask(depth: depth))

        #expect(mask.isFood(x: 50, y: 50), "seed (frame centre) must be inside the region")
        #expect(mask.isFood(x: 50, y: 75), "plate annulus must be inside the region")
        #expect(!mask.isFood(x: 5, y: 5), "table corner must be outside the region")
        #expect(!mask.isFood(x: 50, y: 85), "table just beyond the rim must be outside the region")
    }

    @Test("Flood fill survives a sentinel patch at the exact seed pixel")
    func floodFillSurvivesSentinelSeed() throws {
        // Specular centre: 3×3 sentinel hole where the seed would land.
        let depth = makeDepth { x, y in
            (abs(x - 50) <= 1 && abs(y - 50) <= 1) ? 0 : plateSceneDepth(x: x, y: y)
        }
        let mask = try #require(FixtureRunner.plateRegionMask(depth: depth))

        #expect(mask.isFood(x: 50, y: 75), "plate annulus reachable from a near-centre seed")
        #expect(!mask.isFood(x: 5, y: 5))
    }

    @Test("An all-sentinel frame yields no plate region")
    func allSentinelYieldsNoRegion() {
        let depth = makeDepth { _, _ in 0 }
        #expect(FixtureRunner.plateRegionMask(depth: depth) == nil)
    }

    @Test("Sentinel pixels inside the plate are barriers, never members (Req 3.2)")
    func sentinelPixelsAreNotMembers() throws {
        let depth = makeDepth { x, y in
            (x == 60 && y == 50) ? 0 : plateSceneDepth(x: x, y: y)
        }
        let mask = try #require(FixtureRunner.plateRegionMask(depth: depth))
        #expect(!mask.isFood(x: 60, y: 50), "sentinel dropout must not join the region")
        #expect(mask.isFood(x: 65, y: 50), "fill must route around the dropout")
    }

    // MARK: - Plane fit restricted to the plate region (task 12)

    @Test("Plate-region plane lands on the plate top, not the table")
    func planeLandsOnPlateTopNotTable() throws {
        let depth = makeDepth(depthMm: plateSceneDepth)

        let plane = try FixtureRunner.fitPlateRegionPlane(
            depth: depth, intrinsics: k, gravity: gravity, fixtureID: "dish_test"
        )

        // Plate top at z = −580: n̂ = (0,0,−1) (n̂·gravity > 0), d = 580.
        // The table would be d = 600 — integrating above it would include the
        // 20 mm plate rim in every food column (Req 3.6).
        #expect(abs(plane.distanceMm - Self.plateMm) <= 2,
                "plane at \(plane.distanceMm) mm; expected plate top ≈ \(Self.plateMm) mm")
        #expect(abs(plane.distanceMm - Self.tableMm) >= 10,
                "plane must not land on the table at \(Self.tableMm) mm")
        #expect(plane.normal.dot(gravity) > 0.9, "normal oriented n̂·gravity > 0, near-vertical")
    }

    @Test("An empty confidence map means no confidence filtering, not a crash")
    func emptyConfidenceMapIsTolerated() throws {
        // N5k fixtures carry no confidence bytes (RealSense publishes none;
        // invalid returns are already zeroed and excluded by the zMm > 0
        // guard). Found in the first real end-to-end run: subscripting the
        // empty Data trapped inside LiDARPlaneFitter's confidence sample.
        let depth = makeDepth(confidence: Data(), depthMm: plateSceneDepth)

        let plane = try FixtureRunner.fitPlateRegionPlane(
            depth: depth, intrinsics: k, gravity: gravity, fixtureID: "dish_noconf"
        )
        #expect(abs(plane.distanceMm - Self.plateMm) <= 2)
    }

    @Test("Poor plate-plane fit (high residual) throws so the plate is skipped and recorded")
    func poorPlaneFitThrows() {
        // Plate region carries ±2 mm deterministic noise: inside the flood-fill
        // continuity threshold and the RANSAC inlier band, but the RMS residual
        // (≈1.3 mm) exceeds a 1 mm residual ceiling → Req 3.4/3.8 skip path.
        let depth = makeDepth { x, y in
            guard Self.isOnPlate(x, y) else { return Self.tableMm }
            let noise = Float((x * 31 + y * 17) % 9 - 4) / 2.0
            return Self.plateMm + noise
        }

        #expect(throws: FixtureRunner.Error.self) {
            _ = try FixtureRunner.fitPlateRegionPlane(
                depth: depth, intrinsics: k, gravity: gravity,
                fixtureID: "dish_noisy", residualMaxMm: 1.0
            )
        }
    }
}
#endif
