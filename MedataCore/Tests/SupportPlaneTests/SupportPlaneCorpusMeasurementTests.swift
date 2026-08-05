import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// The task 26 corpus measurement pass: the instrumented run, guards disabled, that
// `prerequisites.md` asks for. It dumps per-candidate `supportFraction`,
// `bandMedianMm`, `supportVisibility`, the PER-SECTOR support fractions and the raw
// signed heights for every committed depth slice, and derives from them the
// `[owed]` constants the design deliberately left unstated.
//
// Why this is a test rather than a CLI. Every input it needs — `SupportRegion.prepare`,
// `ringSamples`, `extractCandidates`, `admissibility` — is internal, and the corpus is
// the two `.depthslice` fixtures in this target's bundle. A CLI would have to widen the
// module's public surface to reach the same numbers.
//
// The corpus is TWO captures, both flat bread on a white plate, and that bounds what
// can be concluded here. Constants this pass can set two-sidedly — a floor from what a
// correct capture achieves, a ceiling from the Decision 18 silent-failure geometry —
// are set. Constants that need a scene the corpus does not contain (a rimmed plate, a
// bowl, food at a small plate's edge) stay `[owed]`, and `decision_log.md` records
// which and why. Fitting a bar to the pass side alone is the circularity Req 3.7
// forbids.
@Suite("Task 26 corpus measurement: the constants the design left unstated")
struct SupportPlaneCorpusMeasurementTests {

    static let captures = ["1785135663727", "1785901032716"]

    // MARK: - The dump

    // Prints the pass. Assertions live in the derivation tests below; this one exists
    // so the numbers those derivations quote can be reproduced by running the suite.
    @Test("dump the measurement pass over every committed slice")
    func dumpCorpusMeasurements() throws {
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(SupportRegion.prepare(
                depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
                foodRegionMask: slice.foodMask))
            let samples = SupportRegion.ringSamples(geometry: g)

            print("=== \(name) ===")
            print("  depth grid        \(g.width)x\(g.height)")
            print("  mmPerPx           \(g.mmPerPx)")
            print("  median food depth \(g.mmPerPx * g.intrinsics.fx) mm")
            print("  4 px smear        \(4 * g.mmPerPx) mm")
            print("  food samples      \(g.foodSampleCount)")
            print("  food radius       \(Self.foodRadiusPx(g)) px = \(Self.foodRadiusPx(g) * g.mmPerPx) mm")
            print("  ring samples      \(samples.ring.count)")
            print("  annulus samples   \(samples.annulus.count)")

            var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
            let candidates = SupportRegion.extractCandidates(
                annulus: samples.annulus, geometry: g,
                gravity: slice.gravity.normalised(), rng: &rng)

            for (i, candidate) in candidates.enumerated() {
                print("  --- candidate \(i) ---")
                print("    residual \(candidate.residualMm) mm, component \(candidate.componentSize),"
                      + " extent \(candidate.extentPx) px,"
                      + " residue inlier ratio \(candidate.residueInlierRatio)")
                guard let ring = SupportRegion.ringStatistics(
                    samples: samples, geometry: g,
                    normal: candidate.normal, d: candidate.d) else {
                    print("    ring UNAVAILABLE — a band held < ringMinSamples")
                    continue
                }
                print("    ring median      \(ring.medianMm) mm")
                print("    band medians     \(ring.bandMedianMm)")
                print("    band samples     \(ring.bandSampleCount)")
                print("    supportFraction  \(ring.supportFraction)")
                print("    supportingSectors \(ring.supportingSectors)/\(SupportRegion.ringSectorCount)")
                print("    supportVisibility \(ring.supportVisibility)")
                let sectors = Self.sectorFractions(
                    samples: samples, geometry: g, normal: candidate.normal, d: candidate.d)
                print("    per-sector n     \(sectors.map(\.total))")
                print("    per-sector frac  \(sectors.map { fmt($0.fraction) })")
                let noise = Self.innerBandNoise(
                    samples: samples, geometry: g, normal: candidate.normal, d: candidate.d)
                print("    inner-band robust sigma \(noise.robustSigmaMm) mm"
                      + " (median \(noise.medianMm), p10 \(noise.p10Mm), p90 \(noise.p90Mm))")
                print("    annulus median   \(SupportRegion.medianHeight(indices: samples.annulus, geometry: g, normal: candidate.normal, d: candidate.d)) mm")
                print("    food envelope    \(SupportRegion.foodEnvelopeMm(geometry: g, normal: candidate.normal, d: candidate.d)) mm")
                let verdict = SupportRegion.admissibility(
                    ring: ring,
                    annulusMedianMm: SupportRegion.medianHeight(
                        indices: samples.annulus, geometry: g,
                        normal: candidate.normal, d: candidate.d),
                    foodEnvelopeMm: SupportRegion.foodEnvelopeMm(
                        geometry: g, normal: candidate.normal, d: candidate.d),
                    extentPx: candidate.extentPx)
                print("    admissibility    \(verdict?.rawValue ?? "ADMITTED")")
            }
        }
    }

    // MARK: - Derivations

    // `ringInnerMm = 8` is `[derived]` from "~4 px of depth smoothing ~= 8 mm at 350 mm
    // range", which holds at ONE range. The smear is a fixed count of depth pixels, so
    // its size in millimetres scales with distance. This measures the range envelope the
    // corpus actually occupies and states whether 8 mm covers it.
    @Test("the 4 px depth smear at corpus range fits inside ringInnerMm")
    func depthSmearFitsInsideRingInner() throws {
        for name in Self.captures {
            let g = try #require(Self.geometry(name))
            let smearMm = 4 * g.mmPerPx
            print("\(name): mmPerPx \(g.mmPerPx), 4 px smear \(smearMm) mm")
            #expect(smearMm <= SupportRegion.ringInnerMm,
                    "\(name) smear \(smearMm) mm exceeds ringInnerMm \(SupportRegion.ringInnerMm)")
        }
    }

    // `ringMinSamples = 200` holds PER radial band. If a real capture cannot fill three
    // bands at 200 apiece, `ringStatistics` returns nil for every candidate and the
    // feature falls back unconditionally — the floor would be the whole fallback rate.
    // This is the feasibility check the constant never had.
    @Test("every band on every corpus capture clears ringMinSamples")
    func bandsClearTheSampleFloor() throws {
        for name in Self.captures {
            let (_, samples) = try #require(Self.prepared(name))
            var counts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
            for band in samples.band { counts[band] += 1 }
            print("\(name): band samples \(counts)")
            for (band, count) in counts.enumerated() {
                #expect(count >= SupportRegion.ringMinSamples,
                        "\(name) band \(band) holds \(count) samples, below the \(SupportRegion.ringMinSamples) floor")
            }
        }
    }

    // Req 3.9's guard is stated as a ratio of visible support to food. Task 26 records a
    // suspicion that it is unfirable: for a support strip w px wide around food of
    // radius f px the ratio is ~2w/f, so 0.15 needs w < 0.075f — a strip that thin sits
    // inside `ringInnerMm`, where the ring never looks. This measures w/f on real
    // captures so the suspicion is settled by the corpus rather than by algebra.
    @Test("measure supportVisibility against the food radius on real captures")
    func supportVisibilityAgainstFoodRadius() throws {
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            let f = Self.foodRadiusPx(g)
            let annulusWidthPx = (SupportRegion.annulusOuterMultiple * SupportRegion.ringOuterMm)
                / g.mmPerPx
            print("\(name): food radius \(f) px, annulus width \(annulusWidthPx) px,"
                  + " 2w/f \(2 * annulusWidthPx / f), annulus/food samples"
                  + " \(Float(samples.annulus.count) / Float(g.foodSampleCount))")
            // The ceiling on `supportVisibility`: every annulus sample an inlier.
            let ceiling = Float(samples.annulus.count) / Float(g.foodSampleCount)
            let unfirable = "\(name) cannot reach supportVisibilityMin even with every"
                + " annulus sample an inlier (ceiling \(ceiling)) — the guard is unfirable"
            #expect(ceiling > SupportRegion.supportVisibilityMin, "\(unfirable)")
        }
    }

    // The support-surface depth-noise distribution, and the Decision 46 tension.
    // `ringSupportMin = 0.6` over a +/-`ringBandMm` band is a statement about noise: a
    // plane truly on the support surface passes only if a 0.6 share of inner-band
    // samples lands within +/-5 mm, which implies sigma_z <~ 5.9 mm. Decision 46's
    // matte-table evidence puts a 20 mm residual bar elsewhere in the codebase.
    //
    // Both are right about different things, and the measurement is what separates
    // them. The inner band as a WHOLE is not a sample of one surface — it holds
    // whatever the ring crossed onto — so its spread measures scene structure. The
    // support MODE within it is what sensor noise governs, and that is tight.
    //
    // The estimate is taken over EVERY candidate and the tightest mode wins, rather
    // than over the highest-support candidate: on `1785901032716` the highest-support
    // candidate is the table, whose mode spans the table AND the plate, so its spread
    // is a plate rim rather than a noise figure.
    @Test("the corpus straddles ringBandMm rather than settling it")
    func supportSurfaceNoiseStraddlesTheBand() throws {
        var tightestPerCapture: [Float] = []
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            var tightest: NoiseSummary?
            for candidate in try #require(Self.candidates(name)) {
                let noise = Self.innerBandNoise(
                    samples: samples, geometry: g, normal: candidate.normal, d: candidate.d)
                print("\(name): candidate at \(noise.medianMm) mm — robust sigma"
                      + " \(noise.robustSigmaMm) mm, core sigma \(noise.coreSigmaMm) mm over"
                      + " \(noise.coreFraction) of the band, p10 \(noise.p10Mm),"
                      + " p90 \(noise.p90Mm), within +/-\(SupportRegion.ringBandMm) mm"
                      + " \(noise.withinBandFraction)")
                if tightest == nil || noise.coreSigmaMm < tightest!.coreSigmaMm { tightest = noise }
            }
            let noise = try #require(tightest)
            print("\(name): tightest core sigma \(noise.coreSigmaMm) mm")
            // The band as a whole is wider than its own mode on every capture, which is
            // the structural finding: the inner band around real food is contaminated by
            // whatever the ring crossed onto, not merely noisy.
            let contaminated = "\(name) inner band is a single population (sigma"
                + " \(noise.robustSigmaMm) vs core \(noise.coreSigmaMm)) — the"
                + " contamination argument does not hold on this capture"
            #expect(noise.robustSigmaMm > noise.coreSigmaMm, "\(contaminated)")
            tightestPerCapture.append(noise.coreSigmaMm)
        }

        // The result task 26 needs and does NOT get: at essentially the same range —
        // 338.9 mm and 336.9 mm — the two captures disagree about per-sample noise on a
        // flat surface by 2x, and `ringBandMm = 5` falls between them. That is a surface
        // difference, not a range one, which is exactly what Decision 46's matte-table
        // evidence predicts. A constant cannot be set from a corpus that straddles it,
        // so `ringSupportMin` stays `[owed]` and `prerequisites.md`'s "capture at least
        // one on a matte surface" becomes a requirement rather than a suggestion.
        let low = try #require(tightestPerCapture.min())
        let high = try #require(tightestPerCapture.max())
        print("corpus tightest core sigma spans \(low)...\(high) mm"
              + " around ringBandMm \(SupportRegion.ringBandMm)")
        let settled = "the corpus no longer straddles ringBandMm (\(low)...\(high) mm) —"
            + " the noise question can be settled and ringSupportMin derived"
        #expect(low <= SupportRegion.ringBandMm && high > SupportRegion.ringBandMm, "\(settled)")
    }

    // The sector trio. A candidate resting on the surface the food rests on must clear
    // `minSupportingSectors`, and the Decision 18 silent-failure case — a ring 65 % on
    // the table over one contiguous arc — must not. This measures whether the shipped
    // placeholders separate the two, using the corpus for the first and the geometry
    // Decision 18 states for the second.
    @Test("the placeholder sector trio does not separate a correct fit from Decision 18's case")
    func sectorTrioDoesNotSeparateTheDecision18Case() throws {
        // Decision 18: a contiguous arc covering fraction 0.65 of the ring. Sectors are
        // equal arcs, so the supporting count lands within +/-1 of 0.65 x ringSectorCount.
        let decision18Low = Int((0.65 * Float(SupportRegion.ringSectorCount)).rounded(.down)) - 1
        let decision18High = Int((0.65 * Float(SupportRegion.ringSectorCount)).rounded(.up)) + 1

        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            let best = try #require(Self.bestCandidate(name))
            let sectors = Self.sectorFractions(
                samples: samples, geometry: g, normal: best.normal, d: best.d)
            let occupied = sectors.filter { $0.total > 0 }.count
            let meeting = sectors.filter {
                $0.total > 0 && $0.fraction >= SupportRegion.sectorSupportMin
            }.count
            let medians = Self.sectorMedianMm(
                samples: samples, geometry: g, normal: best.normal, d: best.d)
            print("\(name): sector fractions \(sectors.map { fmt($0.fraction) }),"
                  + " sector medians \(medians.map { fmt($0) }),"
                  + " occupied \(occupied), meeting \(SupportRegion.sectorSupportMin): \(meeting),"
                  + " minSupportingSectors \(SupportRegion.minSupportingSectors),"
                  + " Decision 18 band \(decision18Low)...\(decision18High)")
            // Every sector holds samples, so no count is lost to an empty arc — the
            // supporting count is a measurement rather than an artefact of coverage.
            let empty = "\(name) leaves \(SupportRegion.ringSectorCount - occupied) sectors"
                + " empty — ringSectorCount is too high for this capture's ring"
            #expect(occupied == SupportRegion.ringSectorCount, "\(empty)")
            // The negative result this pass exists to record: the best candidate's
            // supporting-sector count falls INSIDE the range the Decision 18 failure
            // case produces, so `minSupportingSectors` cannot be set to admit one and
            // reject the other. Neither corpus capture supplies a clean "correct fit"
            // side, which is why the trio stays `[owed]`.
            let separable = "\(name) scores \(meeting) supporting sectors, OUTSIDE the"
                + " \(decision18Low)...\(decision18High) Decision 18 band — the trio is"
                + " now separable on this corpus and can be set"
            #expect(meeting >= decision18Low && meeting <= decision18High, "\(separable)")
        }
    }

    // MARK: - Helpers

    static func geometry(_ name: String) -> SupportRegion.DepthGeometry? {
        guard let slice = try? DepthSlice.load(name) else { return nil }
        return SupportRegion.prepare(depth: slice.depth,
                                     colourIntrinsics: slice.colourIntrinsics,
                                     foodRegionMask: slice.foodMask)
    }

    static func prepared(_ name: String) -> (SupportRegion.DepthGeometry, SupportRegion.RingSamples)? {
        guard let g = geometry(name) else { return nil }
        return (g, SupportRegion.ringSamples(geometry: g))
    }

    static func candidates(_ name: String) -> [SupportRegion.PlaneCandidate]? {
        guard let slice = try? DepthSlice.load(name), let (g, samples) = prepared(name) else {
            return nil
        }
        var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
        return SupportRegion.extractCandidates(
            annulus: samples.annulus, geometry: g,
            gravity: slice.gravity.normalised(), rng: &rng)
    }

    // Highest inner-band support, taken BEFORE admissibility — the candidate the design
    // intends to select, independent of the constants this pass is measuring.
    static func bestCandidate(_ name: String) -> SupportRegion.PlaneCandidate? {
        guard let (g, samples) = prepared(name), let candidates = candidates(name) else {
            return nil
        }
        return candidates.max {
            (SupportRegion.ringStatistics(samples: samples, geometry: g,
                                          normal: $0.normal, d: $0.d)?.supportFraction ?? -1)
            < (SupportRegion.ringStatistics(samples: samples, geometry: g,
                                            normal: $1.normal, d: $1.d)?.supportFraction ?? -1)
        }
    }

    struct SectorSupport {
        let total: Int
        let supported: Int
        var fraction: Float { total == 0 ? 0 : Float(supported) / Float(total) }
    }

    static func sectorFractions(samples: SupportRegion.RingSamples,
                                geometry g: SupportRegion.DepthGeometry,
                                normal: Vec3, d: Float) -> [SectorSupport] {
        var total = [Int](repeating: 0, count: SupportRegion.ringSectorCount)
        var supported = [Int](repeating: 0, count: SupportRegion.ringSectorCount)
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            let s = samples.sector[i]
            guard s >= 0 else { continue }
            total[s] += 1
            if abs(normal.dot(g.points[idx]) - d) <= SupportRegion.ringBandMm { supported[s] += 1 }
        }
        return (0..<SupportRegion.ringSectorCount).map {
            SectorSupport(total: total[$0], supported: supported[$0])
        }
    }

    // Inner-band median signed height PER SECTOR. A sector sitting on the support
    // surface reads ~0; one whose ring crossed onto the table reads the plate's rim
    // height. This is what says whether a low sector fraction is noise or an escape.
    static func sectorMedianMm(samples: SupportRegion.RingSamples,
                               geometry g: SupportRegion.DepthGeometry,
                               normal: Vec3, d: Float) -> [Float] {
        var heights = [[Float]](repeating: [], count: SupportRegion.ringSectorCount)
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            let s = samples.sector[i]
            guard s >= 0 else { continue }
            heights[s].append(normal.dot(g.points[idx]) - d)
        }
        return heights.map { $0.isEmpty ? .nan : $0.sorted()[$0.count / 2] }
    }

    struct NoiseSummary {
        let medianMm: Float
        let robustSigmaMm: Float
        // Robust sigma over the SUPPORT MODE only — samples within `coreWindowMm` of the
        // inner-band median. Sensor noise governs this; scene structure governs the rest.
        let coreSigmaMm: Float
        let coreFraction: Float
        let p10Mm: Float
        let p90Mm: Float
        let withinBandFraction: Float
    }

    // Wide enough to hold the whole support mode at any plausible depth noise, narrow
    // enough to exclude a plate rim (~12-28 mm) or a food sample leaking into the ring.
    static let coreWindowMm: Float = 15

    // Robust because the inner band on a plate capture is not pure support surface —
    // it holds table samples wherever the ring crossed the plate edge, and a plain
    // standard deviation would measure the plate-to-table step rather than the noise.
    // MAD x 1.4826 is the Gaussian-consistent estimator that ignores them.
    static func innerBandNoise(samples: SupportRegion.RingSamples,
                               geometry g: SupportRegion.DepthGeometry,
                               normal: Vec3, d: Float) -> NoiseSummary {
        var heights: [Float] = []
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            heights.append(normal.dot(g.points[idx]) - d)
        }
        guard !heights.isEmpty else {
            return NoiseSummary(medianMm: 0, robustSigmaMm: 0, coreSigmaMm: 0,
                                coreFraction: 0, p10Mm: 0, p90Mm: 0, withinBandFraction: 0)
        }
        let sorted = heights.sorted()
        let median = sorted[sorted.count / 2]
        let mad = heights.map { abs($0 - median) }.sorted()[heights.count / 2]
        let core = heights.filter { abs($0 - median) <= coreWindowMm }
        let coreMedian = core.sorted()[core.count / 2]
        let coreMad = core.map { abs($0 - coreMedian) }.sorted()[core.count / 2]
        let within = heights.reduce(into: 0) { $0 += abs($1) <= SupportRegion.ringBandMm ? 1 : 0 }
        return NoiseSummary(
            medianMm: median,
            robustSigmaMm: 1.4826 * mad,
            coreSigmaMm: 1.4826 * coreMad,
            coreFraction: Float(core.count) / Float(heights.count),
            p10Mm: sorted[Int(0.10 * Float(sorted.count))],
            p90Mm: sorted[min(sorted.count - 1, Int(0.90 * Float(sorted.count)))],
            withinBandFraction: Float(within) / Float(heights.count))
    }

    // Equivalent-disc radius of the food mask, in depth pixels. The `w/f` ratio Req 3.9's
    // guard is stated against needs a single number for "food radius", and the mask is
    // not a disc; equal area is the least arbitrary choice.
    static func foodRadiusPx(_ g: SupportRegion.DepthGeometry) -> Float {
        (Float(g.foodSampleCount) / .pi).squareRoot()
    }
}

private func fmt(_ value: Float) -> String {
    String(format: "%.3f", value)
}
