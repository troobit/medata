import CaptureKit
import Foundation
import PortableContracts
import SwiftProtobuf
@testable import SupportPlane
import Testing

// The gravity-lock measurement pass: the geometry half of what
// `docs/agent-notes/support-plane-fit.md` (2026-09-25) asks for before the lock's default
// is flipped. It runs `LiDARSupportPlaneFitter.fitFromDepth` twice per capture — free and
// gravity-locked — and prints the four columns that describe the PLANE:
//
//     reference | tilt to gravity | fit RMS | ring median
//
// It deliberately does NOT print a volume. The volume half is `HarnessCLI volumes` run
// with `MEDATA_GRAVITY_LOCK=0` and `=1`: it needs the segmenter output, the class palette,
// the growth pass and the food database, none of which this target can reach, and a
// reimplementation here would measure a different pipeline than the one that ships.
//
// Gated behind MEDATA_CORPUS=1 like the task-26 pass beside it, for the same reason: the
// slice arm alone refits five captures four times over.
@Suite(
    "Gravity-locked hypothesis normals: both arms over the same captures",
    .enabled(
        if: ProcessInfo.processInfo.environment["MEDATA_CORPUS"] == "1",
        "corpus measurement pass; run `make test-corpus`"))
struct GravityLockMeasurementTests {

    struct Reading {
        let reference: String
        let tiltDeg: Float
        let residualMm: Float
        let ringMedianMm: Float?
        let inliers: Int
    }

    static func read(depth: DepthMap, intrinsics: CameraIntrinsics,
                     mask: BinaryMask, gravity: Vec3, locked: Bool) -> Reading? {
        let outcome = LiDARSupportPlaneFitter.fitFromDepth(
            depth: depth, intrinsics: intrinsics, mask: mask, gravity: gravity,
            gravityLocked: locked)
        guard let plane = outcome.plane else { return nil }
        let g = gravity.normalised()
        let cosine = max(-1, min(1, plane.normal.normalised().dot(g)))
        return Reading(
            reference: outcome.stats.reference.map { "\($0)" } ?? "none",
            tiltDeg: acos(cosine) * 180 / .pi,
            residualMm: plane.residualMm,
            ringMedianMm: outcome.stats.ring?.medianMm,
            inliers: outcome.stats.inlierCount)
    }

    static func row(_ name: String, _ free: Reading?, _ locked: Reading?) -> String {
        func cell(_ r: Reading?) -> String {
            guard let r else { return "refused" }
            let ring = r.ringMedianMm.map { String(format: "%.2f", $0) } ?? "-"
            return String(format: "%@ tilt=%.3f rms=%.3f ring=%@ inliers=%d",
                          r.reference, r.tiltDeg, r.residualMm, ring, r.inliers)
        }
        return "\(name)\n    free   \(cell(free))\n    locked \(cell(locked))"
    }

    // MARK: - The committed depth slices

    @Test("both arms over every committed depth slice")
    func slices() throws {
        print("=== gravity lock: committed depth slices ===")
        for name in ["1785054950406", "1785135663727", "1785901032716",
                     "1786439141215", "1786450130307"] {
            let slice = try DepthSlice.load(name)
            let free = Self.read(depth: slice.depth, intrinsics: slice.colourIntrinsics,
                                 mask: slice.colourFoodMask, gravity: slice.gravity,
                                 locked: false)
            let locked = Self.read(depth: slice.depth, intrinsics: slice.colourIntrinsics,
                                   mask: slice.colourFoodMask, gravity: slice.gravity,
                                   locked: true)
            print(Self.row(name, free, locked))
        }
    }

    // MARK: - Field bundles

    // Walks a directory of `.fixture` bundles when `MEDATA_BUNDLE_DIR` names one, so the
    // same two arms can be read over the 2026-09-24/25 field corpus rather than over the
    // five committed slices alone. The bundles are ~195 MB each and live outside the
    // repository, which is why this is an environment variable and not a resource.
    //
    // Only bundles carrying the device's PRE-SHUTTER food mask are read. Deriving a mask
    // from `nadir_argmax` instead needs `ClassPalette.isVolumetricClass`, which lives in
    // `Foods`, and this target does not depend on it. The shipped fit uses the pre-shutter
    // mask whenever the bundle has one, so the bundles read here are read exactly as the
    // pipeline reads them; the rest are named as skipped rather than approximated.
    @Test("both arms over the field bundles under MEDATA_BUNDLE_DIR")
    func bundles() throws {
        guard let dir = ProcessInfo.processInfo.environment["MEDATA_BUNDLE_DIR"] else {
            print("=== gravity lock: MEDATA_BUNDLE_DIR unset, field arm skipped ===")
            return
        }
        let root = URL(fileURLWithPath: dir)
        let urls = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "fixture" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        print("=== gravity lock: field bundles under \(dir) ===")
        for url in urls {
            let fixture = try PbMealFixture(serializedBytes: try Data(contentsOf: url))
            let name = fixture.fixtureID.isEmpty
                ? url.deletingPathExtension().lastPathComponent : fixture.fixtureID
            guard fixture.hasNadirDepth else {
                print("\(name)\n    skipped: no nadir depth")
                continue
            }
            let intrinsics = CameraIntrinsics(pb: fixture.nadirIntrinsics)
            let w = intrinsics.imageWidth, h = intrinsics.imageHeight
            guard Int(fixture.preShutterMaskWidth) == w,
                  Int(fixture.preShutterMaskHeight) == h,
                  fixture.preShutterMask.count == w * h else {
                print("\(name)\n    skipped: no pre-shutter mask on the nadir grid")
                continue
            }
            let mask = BinaryMask(pixels: [UInt8](fixture.preShutterMask),
                                  width: w, height: h)
            let depth = DepthMap(pb: fixture.nadirDepth)
            let gravity = Vec3(pb: fixture.gravity)
            let free = Self.read(depth: depth, intrinsics: intrinsics, mask: mask,
                                 gravity: gravity, locked: false)
            let locked = Self.read(depth: depth, intrinsics: intrinsics, mask: mask,
                                   gravity: gravity, locked: true)
            print(Self.row(name, free, locked))
        }
    }
}
