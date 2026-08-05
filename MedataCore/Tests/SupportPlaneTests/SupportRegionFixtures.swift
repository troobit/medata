import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane

// Shared synthetic-scene builders for the support-plane-reference tests (tasks
// 1, 3, 5, 7). Scenes follow the same convention as `LiDARPlaneFitterTests`:
// gravity = Vec3(0, 1, 0), and a region's target plane is given by its signed
// height `d` along that axis (n̂·p = d). `cy` is pinned negative so every
// pixel's ray has dirY = (y-cy)/fy > 0 everywhere in the image, keeping the
// ray/plane intersection t = d/dirY positive (a valid depth) for any positive
// `d` — no image-centre sign flip to work around.

let fixtureIntrinsics = CameraIntrinsics(
    fx: 1500, fy: 1500, cx: 320, cy: -400,
    distortion: [], imageWidth: 640, imageHeight: 900
)

// Ring/candidate/guard scene geometry (tasks 3, 5, 7). Chosen so the resulting
// mmPerPixel ≈ 0.548 (derived from the food centre's own depth at d = 126),
// giving ring/band pixel radii comfortably inside a 320×360 grid:
// ringInnerMm(8) ≈ 14.6 px, one band width ≈ 10.3 px, ringOuterMm(25) ≈ 45.6
// px, the 2×ringOuterMm candidate annulus ≈ 91.3 px — all measured from the
// food MASK BOUNDARY, i.e. offset by the food radius from the centroid.
let sceneIntrinsics = CameraIntrinsics(fx: 900, fy: 900, cx: 150, cy: -50, imageWidth: 320, imageHeight: 360)
let sceneWidth = 320
let sceneHeight = 360
let sceneFoodCentre: (x: Float, y: Float) = (150, 180)
let sceneFoodRadiusPx: Float = 6
let sceneRingInnerPx: Float = 14.6
let sceneBandWidthPx: Float = 10.34
let sceneRingOuterPx: Float = 45.6
let sceneAnnulusPx: Float = 91.3
// Boundaries measured from the food centroid (mask-boundary distance + food radius),
// valid ONLY when foodHeightMm = 126 (the value they were derived from — see
// `scenePixelRadius` for scenes that use a different food height).
let sceneRingInnerBoundaryPx = sceneFoodRadiusPx + sceneRingInnerPx
let sceneMidBoundaryPx = sceneFoodRadiusPx + sceneRingInnerPx + sceneBandWidthPx
let sceneOuterBoundaryPx = sceneFoodRadiusPx + sceneRingInnerPx + 2 * sceneBandWidthPx
let sceneRingOuterBoundaryPx = sceneFoodRadiusPx + sceneRingOuterPx
let sceneAnnulusBoundaryPx = sceneFoodRadiusPx + sceneAnnulusPx

// End-to-end `fitFoodSupportPlane` scene geometry (task 7): a SMALLER focal
// length than the ring/candidate-only scenes above, so the candidate annulus
// stays a few thousand pixels (CC-RANSAC's cost is linear in candidate count)
// while still comfortably clearing `ringMinSamples` per band. Colour grid ==
// depth grid here (both callers pass the same resolution), so
// `depthGridMask`/`depthIntrinsics` downsampling is an identity transform.
let guardIntrinsics = CameraIntrinsics(fx: 250, fy: 250, cx: 60, cy: -20, imageWidth: 130, imageHeight: 150)
let guardWidth = 130
let guardHeight = 150
let guardFoodCentre: (x: Float, y: Float) = (60, 70)
let guardFoodRadiusPx: Float = 10

// Pixel radius corresponding to `mm` physical distance in the guard scene,
// for a scene whose FOOD HEIGHT is `foodHeightMm` — mirrors exactly the
// scale `SupportRegion` itself derives.
func guardPixelRadius(mm: Float, foodHeightMm: Float) -> Float {
    scenePixelRadius(mm: mm, foodHeightMm: foodHeightMm, intrinsics: guardIntrinsics, foodCentreY: guardFoodCentre.y)
}

// Computes the pixel radius corresponding to `mm` physical distance for a
// scene whose FOOD HEIGHT is `foodHeightMm` — mirrors exactly the scale
// SupportRegion itself derives (mmPerPixel = medianFoodDepthMm / focalAvg),
// so scenes that need a food height other than 126 (the constants above's
// baseline) can still place surface transitions at the boundary the SUT will
// actually compute, rather than one baked in for a different depth.
func scenePixelRadius(mm: Float, foodHeightMm: Float,
                      intrinsics: CameraIntrinsics = sceneIntrinsics,
                      foodCentreY: Float = sceneFoodCentre.y) -> Float {
    let dirY = (foodCentreY - intrinsics.cy) / intrinsics.fy
    let z = foodHeightMm / dirY
    let mmPerPixel = z / ((intrinsics.fx + intrinsics.fy) / 2)
    return mm / mmPerPixel
}

// Builds a depth map where pixel (x, y)'s target signed height along gravity
// is `heightMmAt(x, y)`; nil means "no measurement" (left at depth 0, dropped
// by callers' `zMm > 0` guards).
func heightFieldDepthMap(
    intrinsics: CameraIntrinsics = fixtureIntrinsics,
    depthWidth: Int, depthHeight: Int,
    heightMmAt: (Int, Int) -> Float?,
    confidenceAt: (Int, Int) -> UInt8 = { _, _ in 255 }
) -> DepthMap {
    let sx = Float(depthWidth) / Float(intrinsics.imageWidth)
    let sy = Float(depthHeight) / Float(intrinsics.imageHeight)
    let kd = CameraIntrinsics(
        fx: intrinsics.fx * sx, fy: intrinsics.fy * sy,
        cx: (intrinsics.cx + 0.5) * sx - 0.5, cy: (intrinsics.cy + 0.5) * sy - 0.5,
        distortion: [], imageWidth: depthWidth, imageHeight: depthHeight
    )
    var depthBytes = Data(count: depthWidth * depthHeight * 4)
    var confBytes = Data(count: depthWidth * depthHeight)
    depthBytes.withUnsafeMutableBytes { rawPtr -> Void in
        let buf = rawPtr.bindMemory(to: Float.self)
        for y in 0..<depthHeight {
            for x in 0..<depthWidth {
                guard var d = heightMmAt(x, y) else { buf[y * depthWidth + x] = 0; continue }
                // Deterministic, ZERO-MEAN jitter: real depth data is never
                // perfectly flat, and `refine`'s SVD stability gate (rightly)
                // treats an exactly-zero smallest singular value as
                // degenerate. The amplitude must be large enough to survive
                // Float32 cancellation against the scatter matrix's X/Z terms
                // (millions at these scales — a sub-0.01 mm jitter's variance
                // is below Float32's relative precision there and gets lost
                // to noise, which is a SEPARATE failure from the zero-
                // variance case this guards against). Non-zero mean would
                // bias every median-based statistic in the ring/food tests,
                // so the 0..4 residue is centred before scaling.
                d += (Float((x &* 7 &+ y &* 13) % 5) - 2.0) * 0.6
                let dirY = (Float(y) - kd.cy) / kd.fy
                guard dirY > 0 else { buf[y * depthWidth + x] = 0; continue }
                let t = d / dirY
                buf[y * depthWidth + x] = t > 0 ? t : 0
            }
        }
    }
    for y in 0..<depthHeight {
        for x in 0..<depthWidth {
            confBytes[y * depthWidth + x] = confidenceAt(x, y)
        }
    }
    return DepthMap(
        depthBytesMm: depthBytes, confidenceBytes: confBytes,
        width: depthWidth, height: depthHeight, rowStrideBytes: depthWidth * 4,
        depthIntrinsics: kd, depthFromColour: .identity
    )
}

// A filled ellipse mask at the given (grid-native) resolution.
func ellipseFoodMask(width: Int, height: Int, cx: Float, cy: Float, rx: Float, ry: Float) -> BinaryMask {
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            let nx = (Float(x) - cx) / rx
            let ny = (Float(y) - cy) / ry
            if nx * nx + ny * ny <= 1 { pixels[y * width + x] = 1 }
        }
    }
    return BinaryMask(pixels: pixels, width: width, height: height)
}

// Radially-concentric scene: food disc at `foodHeightMm`, then the first
// matching (outerRadiusPx, heightMm) ring (ordered inner→outer, radius
// measured from the food CENTROID), else `backgroundHeightMm`.
func concentricScene(
    depthWidth: Int = sceneWidth, depthHeight: Int = sceneHeight,
    intrinsics: CameraIntrinsics = sceneIntrinsics,
    centre: (x: Float, y: Float) = sceneFoodCentre, foodRadiusPx: Float = sceneFoodRadiusPx,
    foodHeightMm: Float,
    rings: [(outerRadiusPx: Float, heightMm: Float)],
    backgroundHeightMm: Float,
    confidenceAt: (Int, Int) -> UInt8 = { _, _ in 255 }
) -> DepthMap {
    heightFieldDepthMap(
        intrinsics: intrinsics, depthWidth: depthWidth, depthHeight: depthHeight,
        heightMmAt: { x, y in
            let dx = Float(x) - centre.x, dy = Float(y) - centre.y
            let r = (dx * dx + dy * dy).squareRoot()
            if r <= foodRadiusPx { return foodHeightMm }
            for ring in rings where r <= ring.outerRadiusPx { return ring.heightMm }
            return backgroundHeightMm
        },
        confidenceAt: confidenceAt
    )
}

// Angularly-split scene beyond the food disc: the arc [0, angleFractionA·2π)
// (about the food centroid, atan2 convention matching `SupportRegion`) reads
// `heightA`; the remainder reads `heightB`. Used for the sector straddle
// tests (Req 3.6 / Decision 18), where the failure is spatial arrangement,
// not aggregate mixture fraction.
func angularSplitScene(
    depthWidth: Int = sceneWidth, depthHeight: Int = sceneHeight,
    intrinsics: CameraIntrinsics = sceneIntrinsics,
    centre: (x: Float, y: Float) = sceneFoodCentre, foodRadiusPx: Float = sceneFoodRadiusPx,
    foodHeightMm: Float,
    angleFractionA: Float, heightA: Float, heightB: Float,
    confidenceAt: (Int, Int) -> UInt8 = { _, _ in 255 }
) -> DepthMap {
    heightFieldDepthMap(
        intrinsics: intrinsics, depthWidth: depthWidth, depthHeight: depthHeight,
        heightMmAt: { x, y in
            let dx = Float(x) - centre.x, dy = Float(y) - centre.y
            let r = (dx * dx + dy * dy).squareRoot()
            if r <= foodRadiusPx { return foodHeightMm }
            var angle = atan2(dy, dx)
            if angle < 0 { angle += 2 * Float.pi }
            let boundary = angleFractionA * 2 * Float.pi
            return angle < boundary ? heightA : heightB
        },
        confidenceAt: confidenceAt
    )
}
