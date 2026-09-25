#if HARNESS_ENABLED
// Scratch investigation (uncommitted): depth-grown region leaking onto a
// speckled plate. Gated on SPECKLE=1; writes dumps into SPECKLE_OUT.
import CaptureKit
import Foods
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume
@testable import HarnessCore

@Suite("speckle probe", .enabled(if: ProcessInfo.processInfo.environment["SPECKLE"] == "1"))
struct SpeckleProbeTests {

    static let defaultFixtures = [
        "/Users/r/repos/medata-corpus/pulls/20260924-1/captures/1790223818017-success.fixture",
        "/Users/r/repos/medata-corpus/pulls/20260924-2/captures/1790232681422-success.fixture",
        "/Users/r/repos/medata-corpus/pulls/20260925-1/captures/1790242780378-success.fixture",
        "/Users/r/repos/medata-corpus/pulls/20260925-2/captures/1790310107431-success.fixture",
    ]

    static var outDir: String {
        ProcessInfo.processInfo.environment["SPECKLE_OUT"]
            ?? "/private/tmp/claude-501/-Users-r-repos-medata/9cb788cf-c2e2-418b-9aa9-b8a48842c9e3/scratchpad/speckle"
    }

    static func fixtures() -> [String] {
        if let s = ProcessInfo.processInfo.environment["SPECKLE_FIXTURES"], !s.isEmpty {
            return s.split(separator: ":").map(String.init)
        }
        return defaultFixtures
    }

    static func say(_ s: String) {
        FileHandle.standardError.write(("SPECKLE " + s + "\n").data(using: .utf8)!)
    }

    static func load(_ path: String) throws -> PbMealFixture {
        try PbMealFixture(serializedBytes: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    static func write<T>(_ arr: [T], _ name: String) {
        let d = arr.withUnsafeBufferPointer { Data(buffer: $0) }
        try? d.write(to: URL(fileURLWithPath: outDir + "/" + name))
    }

    @Test("floor sweep through FixtureRunner")
    func sweep() throws {
        let palette = ClassPalette.standard
        let floors: [Float] = (ProcessInfo.processInfo.environment["SPECKLE_FLOORS"] ?? "3,5,8,12")
            .split(separator: ",").compactMap { Float($0) }
        for path in Self.fixtures() {
            let fx = try Self.load(path)
            var configs: [(String, FoodRegionGrowthConfig)] = [("disabled", .disabled)]
            for f in floors {
                configs.append(("floor\(Int(f))", FoodRegionGrowthConfig(cliffMm: 3, floorMm: f, frameFractionCap: 0.35)))
            }
            for (name, cfg) in configs {
                let m = try FixtureRunner.run(fixture: fx, palette: palette, database: EmptyDB(),
                                              regularisation: .standard, growth: cfg)
                let total = m.perClassVolumesCm3.values.reduce(0, +)
                let per = m.perClassVolumesCm3.sorted { $0.value > $1.value }
                    .map { "\($0.key)=\(String(format: "%.1f", $0.value))" }.joined(separator: ",")
                Self.say("sweep fixture=\(fx.fixtureID) config=\(name) before=\(m.regionGrowth?.foodPixelsBefore ?? -1) after=\(m.regionGrowth?.foodPixelsAfter ?? -1) applied=\(m.regionGrowth?.applied ?? false) cap=\(m.regionGrowth?.capTripped ?? false) plane=\(m.supportPlaneReference?.rawValue ?? "nil") residual=\(String(format: "%.2f", m.supportPlaneResidualMm ?? -1)) refit=\(m.regionGrowth?.refitReference?.rawValue ?? "none") refused=\(m.regionGrowth?.refitRefused ?? false) volume=\(String(format: "%.1f", total)) per=\(per)")
            }
        }
    }

    // Guard candidate: adopt the refit only when its reference is foodSupport
    // (never trade the plane the volume integrates from for a table fallback).
    @Test("refit-adoption guard across floors")
    func guardSweep() throws {
        let palette = ClassPalette.standard
        let floors: [Float] = (ProcessInfo.processInfo.environment["SPECKLE_FLOORS"] ?? "3,5,8")
            .split(separator: ",").compactMap { Float($0) }
        for path in Self.fixtures() {
            let fx = try Self.load(path)
            let id = fx.fixtureID
            let k = CameraIntrinsics(pb: fx.nadirIntrinsics)
            let W = k.imageWidth, H = k.imageHeight
            let C = palette.totalClasses
            let gravity = Vec3(pb: fx.gravity)
            let depth = DepthMap(pb: fx.nadirDepth)
            let probs = ProbabilityTensor(bytes: fx.nadirProbs, height: H, width: W, classes: C, palette: palette)
            let cleaned = SegmenterPostProcessor.regularise(
                argmax: fx.nadirArgmax, width: W, height: H, palette: palette, config: .standard)
            let argmax = ArgmaxMap(pixels: cleaned, height: H, width: W)
            // SPECKLE_FIRST=preshutter fits the first plane from the bundle's
            // pre-shutter mask, as the device does; default is the replay's argmax mask.
            var firstMask = FixtureRunner.foodRegionMask(argmax: argmax, palette: palette)
            if ProcessInfo.processInfo.environment["SPECKLE_FIRST"] == "preshutter",
               fx.preShutterMask.count == Int(fx.preShutterMaskWidth) * Int(fx.preShutterMaskHeight), fx.preShutterMask.count > 0 {
                firstMask = BinaryMask(pixels: [UInt8](fx.preShutterMask), width: Int(fx.preShutterMaskWidth), height: Int(fx.preShutterMaskHeight))
                Self.say("guard fixture=\(id) firstMask=preshutter \(firstMask.width)x\(firstMask.height) ones=\(firstMask.pixels.reduce(0) { $0 + Int($1 != 0 ? 1 : 0) })")
            }
            let fit = try FixtureRunner.fitSupportPlane(
                depth: depth, intrinsics: k, gravity: gravity,
                foodMask: firstMask, fixtureID: id)
            Self.say("guard fixture=\(id) first plane ref=\(fit.reference?.rawValue ?? "nil") d=\(fit.plane.distanceMm) residual=\(fit.plane.residualMm) ringMedian=\(fit.ringMedianMm ?? .nan)")
            for f in floors {
                let cfg = FoodRegionGrowthConfig(cliffMm: 3, floorMm: f, frameFractionCap: 0.35)
                let candidate = FoodRegionGrowth.grow(
                    argmax: argmax, depth: depth, intrinsics: k, supportPlane: fit.plane,
                    supportOffsetMm: fit.supportOffsetMm, palette: palette, config: cfg)
                for guarded in [false, true] {
                    var grown = candidate
                    var adopted = fit
                    var refitLabel = "none"
                    if candidate.applied {
                        let refit = try? FixtureRunner.fitSupportPlane(
                            depth: depth, intrinsics: k, gravity: gravity,
                            foodMask: FixtureRunner.foodRegionMask(argmax: candidate.argmax, palette: palette), fixtureID: id)
                        refitLabel = refit?.reference?.rawValue ?? "refused"
                        let usable = refit.map { !guarded || $0.reference == .foodSupport } ?? false
                        let pruneFit = usable ? refit! : fit
                        grown = FoodRegionGrowth.prune(candidate, depth: depth, intrinsics: k, supportPlane: pruneFit.plane,
                                                       supportOffsetMm: pruneFit.supportOffsetMm, palette: palette, config: cfg)
                        if grown.applied, usable { adopted = refit! }
                    }
                    let seg = grown.applied ? grown.argmax : argmax
                    let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                        probabilities: probs, argmax: seg, depth: depth, intrinsics: k,
                        supportPlane: adopted.plane, beta: BetaCorrection(entries: [:], defaultBeta: 1.0),
                        palette: palette, grownRegion: grown.applied ? grown.grownRegion : nil))
                    let total = outcome.estimate?.perClassVolumesCm3.values.reduce(0, +) ?? -1
                    Self.say("guard fixture=\(id) floor=\(Int(f)) guarded=\(guarded) first=\(fit.reference?.rawValue ?? "nil") refit=\(refitLabel) adopted=\(adopted.reference?.rawValue ?? "nil") before=\(grown.foodPixelsBefore) after=\(grown.foodPixelsAfter) volume=\(String(format: "%.1f", total))")
                }
            }
        }
    }

    @Test("dump grow/refit/prune internals for .standard")
    func dump() throws {
        let palette = ClassPalette.standard
        let bands: [Float] = (ProcessInfo.processInfo.environment["SPECKLE_BANDS"] ?? "")
            .split(separator: ",").compactMap { Float($0) }
        let floorEnv = Float(ProcessInfo.processInfo.environment["SPECKLE_FLOOR"] ?? "3") ?? 3
        let cfg = FoodRegionGrowthConfig(cliffMm: 3, floorMm: floorEnv, frameFractionCap: 0.35)
        let tag = "f\(Int(floorEnv))" + (ProcessInfo.processInfo.environment["SPECKLE_FIRST"] == "preshutter" ? "p" : "a")
        for path in Self.fixtures() {
            let fx = try Self.load(path)
            let id = fx.fixtureID
            let k = CameraIntrinsics(pb: fx.nadirIntrinsics)
            let W = k.imageWidth, H = k.imageHeight
            let C = palette.totalClasses
            let gravity = Vec3(pb: fx.gravity)
            let depth = DepthMap(pb: fx.nadirDepth)
            let dw = depth.width, dh = depth.height
            let probs = ProbabilityTensor(bytes: fx.nadirProbs, height: H, width: W, classes: C, palette: palette)
            let cleaned = SegmenterPostProcessor.regularise(
                argmax: fx.nadirArgmax, width: W, height: H, palette: palette, config: .standard)
            let argmax = ArgmaxMap(pixels: cleaned, height: H, width: W)
            let labels = [UInt8](cleaned)

            var firstMask = FixtureRunner.foodRegionMask(argmax: argmax, palette: palette)
            if ProcessInfo.processInfo.environment["SPECKLE_FIRST"] == "preshutter",
               fx.preShutterMask.count == Int(fx.preShutterMaskWidth) * Int(fx.preShutterMaskHeight), fx.preShutterMask.count > 0 {
                firstMask = BinaryMask(pixels: [UInt8](fx.preShutterMask), width: Int(fx.preShutterMaskWidth), height: Int(fx.preShutterMaskHeight))
            }
            let fit = try FixtureRunner.fitSupportPlane(
                depth: depth, intrinsics: k, gravity: gravity, foodMask: firstMask, fixtureID: id)
            let candidate = FoodRegionGrowth.grow(
                argmax: argmax, depth: depth, intrinsics: k, supportPlane: fit.plane,
                supportOffsetMm: fit.supportOffsetMm, palette: palette, config: cfg)
            let refit = candidate.applied
                ? try? FixtureRunner.fitSupportPlane(
                    depth: depth, intrinsics: k, gravity: gravity,
                    foodMask: FixtureRunner.foodRegionMask(argmax: candidate.argmax, palette: palette), fixtureID: id)
                : nil
            let pruneFit = refit ?? fit
            let pruned = candidate.applied
                ? FoodRegionGrowth.prune(candidate, depth: depth, intrinsics: k, supportPlane: pruneFit.plane,
                                         supportOffsetMm: pruneFit.supportOffsetMm, palette: palette, config: cfg)
                : candidate
            let adopted = pruned.applied ? pruneFit : fit

            func planeStr(_ f: FixtureRunner.SingleViewPlaneFit) -> String {
                "n=(\(f.plane.normal.x),\(f.plane.normal.y),\(f.plane.normal.z)) d=\(f.plane.distanceMm) residual=\(f.plane.residualMm) ref=\(f.reference?.rawValue ?? "nil") ringMedian=\(f.ringMedianMm ?? .nan) offset=\(f.supportOffsetMm)"
            }
            Self.say("dump tag=\(tag) fixture=\(id) W=\(W) H=\(H) dw=\(dw) dh=\(dh) fx=\(k.fx) fy=\(k.fy) cx=\(k.cx) cy=\(k.cy)")
            Self.say("dump fixture=\(id) first: \(planeStr(fit))")
            if let refit { Self.say("dump fixture=\(id) refit: \(planeStr(refit))") } else { Self.say("dump fixture=\(id) refit: refused") }
            Self.say("dump fixture=\(id) grow before=\(candidate.foodPixelsBefore) after=\(candidate.foodPixelsAfter) cap=\(candidate.capTripped) pruned after=\(pruned.foodPixelsAfter) applied=\(pruned.applied)")

            // Per-cell arrays.
            let n = dw * dh
            var z = [Float](repeating: 0, count: n)
            var conf = [UInt8](repeating: 0, count: n)
            var hFirst = [Float](repeating: .nan, count: n)
            var hRefit = [Float](repeating: .nan, count: n)
            var seed = [UInt8](repeating: 0, count: n)
            var added = [UInt8](repeating: 0, count: n)
            var kept = [UInt8](repeating: 0, count: n)
            let colX = (0..<W).map { x in min(dw - 1, max(0, Int((Float(x) + 0.5) * Float(dw) / Float(W)))) }
            let colY = (0..<H).map { y in min(dh - 1, max(0, Int((Float(y) + 0.5) * Float(dh) / Float(H)))) }
            for y in 0..<H { for x in 0..<W where palette.isVolumetricClass(Int(labels[y * W + x])) {
                seed[colY[y] * dw + colX[x]] = 1
            } }
            for dy in 0..<dh { for dx in 0..<dw {
                let i = dy * dw + dx
                z[i] = readDepthMm(depth, x: dx, y: dy)
                conf[i] = i < depth.confidenceBytes.count ? depth.confidenceBytes[i] : 255
                let cxCol = (Float(dx) + 0.5) * Float(W) / Float(dw) - 0.5
                let cyCol = (Float(dy) + 0.5) * Float(H) / Float(dh) - 0.5
                if z[i] > 0, z[i].isFinite {
                    hFirst[i] = heightAboveSupportPlaneMm(colourX: cxCol, colourY: cyCol, depthMm: z[i], intrinsics: k, plane: fit.plane) ?? .nan
                    hRefit[i] = heightAboveSupportPlaneMm(colourX: cxCol, colourY: cyCol, depthMm: z[i], intrinsics: k, plane: pruneFit.plane) ?? .nan
                }
                if candidate.applied, candidate.addedCells[i] { added[i] = 1 }
                if pruned.applied, pruned.addedCells[i] { kept[i] = 1 }
            } }
            Self.write(z, "\(id)-\(tag)-z.f32"); Self.write(conf, "\(id)-\(tag)-conf.u8")
            Self.write(hFirst, "\(id)-\(tag)-hfirst.f32"); Self.write(hRefit, "\(id)-\(tag)-hrefit.f32")
            Self.write(seed, "\(id)-\(tag)-seed.u8"); Self.write(added, "\(id)-\(tag)-added.u8"); Self.write(kept, "\(id)-\(tag)-kept.u8")

            // Per-pixel: input label, grown state, height above the adopted plane.
            var grownState = [UInt8](repeating: 0, count: W * H)
            if candidate.applied, let r = candidate.grownRegion { for p in 0..<(W * H) where r.pixels[p] != 0 { grownState[p] = 2 } }
            if pruned.applied, let r = pruned.grownRegion { for p in 0..<(W * H) where r.pixels[p] != 0 { grownState[p] = 1 } }
            var hPix = [Float](repeating: .nan, count: W * H)
            var seedHeights: [Float] = []
            for y in 0..<H { for x in 0..<W {
                let p = y * W + x
                let isFood = palette.isVolumetricClass(Int(labels[p]))
                guard isFood || grownState[p] != 0 else { continue }
                if let zz = sampleDepthBilinearMm(depth: depth, colourX: Float(x), colourY: Float(y), colourWidth: W, colourHeight: H), zz > 0,
                   let hh = heightAboveSupportPlaneMm(colourX: Float(x), colourY: Float(y), depthMm: zz, intrinsics: k, plane: adopted.plane) {
                    hPix[p] = hh
                    if isFood { seedHeights.append(hh) }
                }
            } }
            Self.write(labels, "\(id)-\(tag)-labels.u8"); Self.write(grownState, "\(id)-\(tag)-grown.u8"); Self.write(hPix, "\(id)-\(tag)-hpix.f32")
            seedHeights.sort()
            let seedMedian = seedHeights.isEmpty ? Float.nan : seedHeights[seedHeights.count / 2]
            Self.say("dump fixture=\(id) adopted=\(adopted.reference?.rawValue ?? "nil") offset=\(adopted.supportOffsetMm) seedPixelMedianHeightAboveAdoptedPlane=\(seedMedian) seedPixels=\(seedHeights.count)")

            // Alternative gate: added pixel kept iff h - offset >= seedMedian - offset - N  (one-sided, lower bound).
            guard pruned.applied, let region = pruned.grownRegion else { continue }
            for N in bands {
                var lab = labels
                var reg = [UInt8](repeating: 0, count: W * H)
                var keptPix = 0
                let grownLabels = [UInt8](pruned.argmax.pixels)
                for p in 0..<(W * H) where region.pixels[p] != 0 {
                    let h = hPix[p]
                    if h.isFinite, h >= seedMedian - N {
                        lab[p] = grownLabels[p]; reg[p] = 1; keptPix += 1
                    }
                }
                let seg = SegmentationResult(probabilities: probs, argmax: ArgmaxMap(pixels: Data(lab), height: H, width: W),
                                             perClassMeanProb: [:], sigmaSeg: 1.0)
                let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                    probabilities: seg.probabilities, argmax: seg.argmax, depth: depth, intrinsics: k,
                    supportPlane: adopted.plane, beta: BetaCorrection(entries: [:], defaultBeta: 1.0),
                    palette: palette, grownRegion: BinaryMask(pixels: reg, width: W, height: H)))
                let total = outcome.estimate?.perClassVolumesCm3.values.reduce(0, +) ?? -1
                Self.say("band fixture=\(id) N=\(N) seedMedian=\(seedMedian) before=\(pruned.foodPixelsBefore) after=\(pruned.foodPixelsBefore + keptPix) volume=\(String(format: "%.1f", total))")
            }
        }
    }
}

private struct EmptyDB: FoodDatabase {
    var version: String { "speckle" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}
#endif
