// Temporary diagnostic probe for the flat-food volume over-read bug.
// Not part of the shipping product; deleted after the investigation.
import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Volume

// MARK: - local copies of the fitter's internal samplers (kept byte-identical)

func depthValueMm(_ depth: DepthMap, x: Int, y: Int) -> Float {
    let offset = (y * depth.width + x) * 4
    var value: Float = 0
    depth.depthBytesMm.withUnsafeBytes { rawPtr in
        value = rawPtr.loadUnaligned(fromByteOffset: offset, as: Float.self)
    }
    return value
}

func sampleDepthBilinear(depth: DepthMap, colourX: Float, colourY: Float,
                         colourWidth: Int, colourHeight: Int) -> Float? {
    let fx = (colourX + 0.5) * Float(depth.width) / Float(colourWidth) - 0.5
    let fy = (colourY + 0.5) * Float(depth.height) / Float(colourHeight) - 0.5
    if fx < 0 || fy < 0 { return nil }
    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
    let x1 = min(depth.width - 1, x0 + 1), y1 = min(depth.height - 1, y0 + 1)
    if x0 >= depth.width || y0 >= depth.height { return nil }
    let ax = fx - Float(x0), ay = fy - Float(y0)
    let zx0 = (1 - ax) * depthValueMm(depth, x: x0, y: y0) + ax * depthValueMm(depth, x: x1, y: y0)
    let zx1 = (1 - ax) * depthValueMm(depth, x: x0, y: y1) + ax * depthValueMm(depth, x: x1, y: y1)
    return (1 - ay) * zx0 + ay * zx1
}

func sampleConfidenceNearest(depth: DepthMap, colourX: Int, colourY: Int,
                             colourWidth: Int, colourHeight: Int) -> UInt8 {
    guard !depth.confidenceBytes.isEmpty else { return .max }
    let dx = min(depth.width - 1, max(0, Int((Float(colourX) + 0.5) * Float(depth.width) / Float(colourWidth))))
    let dy = min(depth.height - 1, max(0, Int((Float(colourY) + 0.5) * Float(depth.height) / Float(colourHeight))))
    return depth.confidenceBytes[dy * depth.width + dx]
}

// MARK: - load

let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let fx = try PbMealFixture(serializedBytes: data)

let palette = ClassPalette.standard(for: fx.paletteVersion)
let k = CameraIntrinsics(pb: fx.nadirIntrinsics)
let gravity = Vec3(pb: fx.gravity)
let depth = DepthMap(pb: fx.nadirDepth)
let W = k.imageWidth, H = k.imageHeight
let C = palette.totalClasses

print("fixture=\(fx.fixtureID) palette=\(fx.paletteVersion) path=\(fx.capturePathCanonical)")
print("colour=\(W)x\(H) depth=\(depth.width)x\(depth.height) fx=\(k.fx) fy=\(k.fy) cx=\(k.cx) cy=\(k.cy)")
print("gravity=(\(gravity.x), \(gravity.y), \(gravity.z))")

// Food mask from argmax (stand-in for the device pre-shutter mask).
var maskPixels = [UInt8](repeating: 0, count: W * H)
var foodCount = 0
var classCounts: [Int: Int] = [:]
fx.nadirArgmax.withUnsafeBytes { raw in
    let l = raw.bindMemory(to: UInt8.self).baseAddress!
    for i in 0..<(W * H) {
        let c = Int(l[i])
        classCounts[c, default: 0] += 1
        if palette.isFoodClass(c) || palette.isLiquidClass(c) {
            maskPixels[i] = 1
            foodCount += 1
        }
    }
}
let mask = BinaryMask(pixels: maskPixels, width: W, height: H)
print("foodPixels=\(foodCount) (\(Float(foodCount) * 100 / Float(W * H))%)")
for (c, n) in classCounts.sorted(by: { $0.value > $1.value }).prefix(5) {
    print("  class \(c) [\(palette.className(at: c) ?? "-")] = \(n)")
}

var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
for y in 0..<H {
    for x in 0..<W where maskPixels[y * W + x] == 1 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let bw = max(1, maxX - minX), bh = max(1, maxY - minY)
print("bbox x=\(minX)..\(maxX) y=\(minY)..\(maxY) w=\(bw) h=\(bh)")

// MARK: - device-path plane fit (bands around the food region)

let bandsOutcome = LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
    depth: depth, colourIntrinsics: k, foodRegionMask: mask,
    gravityCamera: gravity, candidateRegion: .bandsAroundFoodRegion
))
guard let bandsPlane = bandsOutcome.plane else {
    print("BANDS FIT REFUSED: \(String(describing: bandsOutcome.refusal))")
    exit(1)
}
print("""
--- BANDS plane (device path) ---
normal=(\(bandsPlane.normal.x), \(bandsPlane.normal.y), \(bandsPlane.normal.z))
distanceMm=\(bandsPlane.distanceMm) residualMm=\(bandsPlane.residualMm)
candidates=\(bandsOutcome.stats.candidatePointCount) inliers=\(bandsOutcome.stats.inlierCount)
""")

// Reproduce the band candidate set locally to histogram it.
var bandPoints: [Vec3] = []
let scanRegions: [(ClosedRange<Int>, ClosedRange<Int>)] = [
    (minX...maxX, maxY...min(H - 1, maxY + bh)),
    (minX...maxX, max(0, minY - bh)...minY),
    (max(0, minX - bw)...minX, minY...maxY),
    (maxX...min(W - 1, maxX + bw), minY...maxY),
]
for (xr, yr) in scanRegions {
    for y in yr {
        for x in xr {
            if maskPixels[y * W + x] == 1 { continue }
            let conf = sampleConfidenceNearest(depth: depth, colourX: x, colourY: y,
                                               colourWidth: W, colourHeight: H)
            if Float(conf) / 255 < 0.40 { continue }
            guard let zMm = sampleDepthBilinear(depth: depth, colourX: Float(x), colourY: Float(y),
                                                colourWidth: W, colourHeight: H), zMm > 0 else { continue }
            bandPoints.append(Vec3((Float(x) - k.cx) / k.fx * zMm,
                                   (Float(y) - k.cy) / k.fy * zMm, -zMm))
        }
    }
}
print("local band point count=\(bandPoints.count)")
var bandHist: [Int: Int] = [:]
for p in bandPoints {
    let signed = bandsPlane.normal.dot(p) - bandsPlane.distanceMm
    bandHist[Int((signed / 5).rounded()), default: 0] += 1
}
print("--- band-point signed height above BANDS plane (5 mm bins) ---")
for (bin, n) in bandHist.sorted(by: { $0.key < $1.key }) where n > bandPoints.count / 400 {
    print(String(format: "  %+6.0f mm : %8d  %@", Float(bin) * 5, n,
                 String(repeating: "#", count: min(60, n * 60 / max(1, bandPoints.count)))))
}

// MARK: - height field

let probs = ProbabilityTensor(bytes: fx.nadirProbs, height: H, width: W,
                              classes: C, palette: palette)
let argmax = ArgmaxMap(pixels: fx.nadirArgmax, height: H, width: W)
let unityBeta = BetaCorrection(entries: [:], defaultBeta: 1.0)

func runHF(_ plane: SupportPlane, label: String) {
    let out = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
        probabilities: probs, argmax: argmax, depth: depth, intrinsics: k,
        supportPlane: plane, beta: unityBeta, palette: palette
    ))
    if let e = out.estimate {
        print("--- HF on \(label): vol=\(e.perClassVolumesCm3) cov=\(e.lidarCoverageFraction) px=\(e.perClassFoodPixelCount)")
    } else {
        print("--- HF on \(label): REFUSED \(String(describing: out.refusal))")
    }
}
runHF(bandsPlane, label: "BANDS plane (device)")

// Per-food-pixel height histogram + footprint area.
var heightHist: [Int: Int] = [:]
var areaMm2: Double = 0, sumH: Double = 0
var nH = 0
let fMean = (k.fx + k.fy) / 2
for y in 0..<H {
    for x in 0..<W where maskPixels[y * W + x] == 1 {
        guard let zt = sampleDepthBilinear(depth: depth, colourX: Float(x), colourY: Float(y),
                                           colourWidth: W, colourHeight: H), zt > 0 else { continue }
        let dir = Vec3((Float(x) - k.cx) / k.fx, (Float(y) - k.cy) / k.fy, -1).normalised()
        let pTop = dir * (zt / abs(dir.z))
        let denom = bandsPlane.normal.dot(dir)
        if abs(denom) < 1e-9 { continue }
        let pSup = dir * (bandsPlane.distanceMm / denom)
        let hMm = abs(pSup.z) - abs(pTop.z)
        heightHist[Int((hMm / 2).rounded()), default: 0] += 1
        let du = Float(x) - k.cx, dv = Float(y) - k.cy
        let cosT = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
        areaMm2 += Double(zt * zt) / Double(k.fx * k.fy * cosT * cosT * cosT)
        sumH += Double(max(0, hMm)); nH += 1
    }
}
print(String(format: "--- food footprint area = %.1f cm2, mean clamped height = %.2f mm over %d px",
             areaMm2 / 100, sumH / Double(max(1, nH)), nH))
print("--- per-food-pixel height above BANDS plane (2 mm bins) ---")
for (bin, n) in heightHist.sorted(by: { $0.key < $1.key }) where n > nH / 300 {
    print(String(format: "  %+6.0f mm : %8d  %@", Float(bin) * 2, n,
                 String(repeating: "#", count: min(60, n * 60 / max(1, nH)))))
}

// MARK: - signed-height map above the BANDS plane (reveals the plate as a ring)

func signedHeight(x: Int, y: Int) -> Float? {
    guard let zt = sampleDepthBilinear(depth: depth, colourX: Float(x), colourY: Float(y),
                                       colourWidth: W, colourHeight: H), zt > 0 else { return nil }
    let dir = Vec3((Float(x) - k.cx) / k.fx, (Float(y) - k.cy) / k.fy, -1).normalised()
    let pTop = dir * (zt / abs(dir.z))
    let denom = bandsPlane.normal.dot(dir)
    if abs(denom) < 1e-9 { return nil }
    let pSup = dir * (bandsPlane.distanceMm / denom)
    return abs(pSup.z) - abs(pTop.z)
}

print("--- median signed height (mm) above BANDS plane, 40x30 grid; 'F'=food-masked cell ---")
let gx = 40, gy = 30
for cy in 0..<gy {
    var row = ""
    for cx in 0..<gx {
        var vals: [Float] = []
        var foodN = 0, allN = 0
        for y in stride(from: cy * H / gy, to: (cy + 1) * H / gy, by: 6) {
            for x in stride(from: cx * W / gx, to: (cx + 1) * W / gx, by: 6) {
                allN += 1
                if maskPixels[y * W + x] == 1 { foodN += 1 }
                if let s = signedHeight(x: x, y: y) { vals.append(s) }
            }
        }
        if vals.isEmpty { row += "  .  "; continue }
        vals.sort()
        let med = vals[vals.count / 2]
        let isFood = foodN * 2 > allN
        row += isFood ? String(format: "%4.0fF", med) : String(format: "%4.0f ", med)
    }
    print(row)
}

// MARK: - plate-surface plane from an annulus just outside the food

// Chamfer distance transform: distance (px) from each pixel to nearest food pixel.
var dist = [Float](repeating: 1e9, count: W * H)
for i in 0..<(W * H) where maskPixels[i] == 1 { dist[i] = 0 }
for y in 0..<H {
    for x in 0..<W {
        let i = y * W + x
        var d = dist[i]
        if x > 0 { d = min(d, dist[i - 1] + 1) }
        if y > 0 { d = min(d, dist[i - W] + 1) }
        if x > 0 && y > 0 { d = min(d, dist[i - W - 1] + 1.414) }
        if x < W - 1 && y > 0 { d = min(d, dist[i - W + 1] + 1.414) }
        dist[i] = d
    }
}
for y in stride(from: H - 1, through: 0, by: -1) {
    for x in stride(from: W - 1, through: 0, by: -1) {
        let i = y * W + x
        var d = dist[i]
        if x < W - 1 { d = min(d, dist[i + 1] + 1) }
        if y < H - 1 { d = min(d, dist[i + W] + 1) }
        if x < W - 1 && y < H - 1 { d = min(d, dist[i + W + 1] + 1.414) }
        if x > 0 && y < H - 1 { d = min(d, dist[i + W - 1] + 1.414) }
        dist[i] = d
    }
}

for (lo, hi) in [(Float(6), Float(30)), (6, 60), (30, 90)] {
    var ring = [UInt8](repeating: 0, count: W * H)
    var n = 0
    var hs: [Float] = []
    for i in 0..<(W * H) where dist[i] >= lo && dist[i] <= hi {
        ring[i] = 1; n += 1
        if let s = signedHeight(x: i % W, y: i / W) { hs.append(s) }
    }
    hs.sort()
    let med = hs.isEmpty ? Float.nan : hs[hs.count / 2]
    print(String(format: "--- annulus %.0f..%.0f px outside food: %d px, median height above BANDS plane = %.1f mm",
                 lo, hi, n, med))
    let ringMask = BinaryMask(pixels: ring, width: W, height: H)
    let out = LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
        depth: depth, colourIntrinsics: k, foodRegionMask: ringMask,
        gravityCamera: gravity, candidateRegion: .insideMask
    ))
    if let p = out.plane {
        let dropMm = abs(p.distanceMm) - abs(bandsPlane.distanceMm)
        print(String(format: "    annulus plane distanceMm=%.2f residual=%.2f inliers=%d  (%.1f mm above BANDS plane)",
                     p.distanceMm, p.residualMm, out.stats.inlierCount, -dropMm))
        runHF(p, label: String(format: "ANNULUS %.0f..%.0f plane", lo, hi))
    } else {
        print("    annulus fit refused: \(String(describing: out.refusal))")
    }
}
