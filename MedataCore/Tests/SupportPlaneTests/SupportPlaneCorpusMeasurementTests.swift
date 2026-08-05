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
// the `.depthslice` fixtures in this target's bundle. A CLI would have to widen the
// module's public surface to reach the same numbers.
//
// The corpus is TWO captures, both flat bread on a white plate, and that bounds what
// can be concluded here. A third slice is committed and NOT admitted — see
// `rejectedCaptures` and `rejectedCaptureIsNotCorpusGrade`, which record the
// measurement that excludes it. Constants this pass can set two-sidedly — a floor from what a
// correct capture achieves, a ceiling from the Decision 18 silent-failure geometry —
// are set. Constants that need a scene the corpus does not contain (a rimmed plate, a
// bowl, food at a small plate's edge) stay `[owed]`, and `decision_log.md` records
// which and why. Fitting a bar to the pass side alone is the circularity Req 3.7
// forbids.
@Suite("Task 26 corpus measurement: the constants the design left unstated")
struct SupportPlaneCorpusMeasurementTests {

    static let captures = ["1785135663727", "1785901032716"]

    // Sliced, committed, and deliberately NOT in `captures`. `1785054950406` is the
    // 208 g mounded-rice bundle from the 2026-07-26 session — on paper the non-flat
    // anchor `prerequisites.md` calls capture 2, and the only bundle in hand that is
    // not flat bread. `tools/fixture_slice.py` cuts it cleanly, so the
    // `FixtureLoader` failure recorded in `field-truth-sessions.md` is not a
    // slice-level one and the capture reaches this pass intact.
    //
    // It is excluded on a measurement, not on the loader's verdict:
    // `rejectedCaptureIsNotCorpusGrade` below records what disqualifies it. The
    // slice is committed anyway because the exclusion has to be reproducible — the
    // capture reads as usable at every level short of the depth confidence map, and
    // admitting it silently flips the sector derivation to a wrong answer (Decision 31).
    static let rejectedCaptures = ["1785054950406"]

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
                      + " residue \(candidate.residueCount),"
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

    // `minCandidateSamples` was one number answering two unrelated questions, and the
    // whole-fit one it was asked at `fitFoodSupportPlane` had an exact answer sitting
    // beside it. `ringStatistics` returns nil unless every radial band clears
    // `ringMinSamples`, and that test reads `samples.band` alone — no plane — so it is
    // knowable before extraction runs. An annulus floor is a proxy for it, and a loose
    // one: 500 admits captures whose ring cannot fill three bands at 200 apiece.
    //
    // This asserts the substitution is exact rather than merely tighter, which is what
    // lets an `[owed]` constant be retired instead of re-guessed (Decision 32).
    @Test("ring-band feasibility subsumes the annulus floor it replaced")
    func ringFeasibilitySubsumesTheAnnulusFloor() throws {
        // The ring is built inside the annulus loop, from the same samples under a
        // narrower radial test, so it is a strict subset by construction. Anything the
        // retired floor rejected, the feasibility test rejects too: with fewer than 500
        // annulus samples the ring holds fewer than 500 across three bands, so some
        // band is under 167 and thus under `ringMinSamples`.
        let retiredFloor = 500
        let weaker = "the retired annulus floor of \(retiredFloor) is no longer weaker"
            + " than ring feasibility — the substitution may not be outcome-preserving"
        #expect(retiredFloor < SupportRegion.ringBandCount * SupportRegion.ringMinSamples,
                "\(weaker)")

        for name in Self.captures {
            let (_, samples) = try #require(Self.prepared(name))
            #expect(samples.ring.count <= samples.annulus.count,
                    "\(name) ring is not a subset of its annulus")
            print("\(name): annulus \(samples.annulus.count), ring \(samples.ring.count),"
                  + " ring share \(Float(samples.ring.count) / Float(samples.annulus.count)),"
                  + " feasible \(SupportRegion.ringBandsAreFeasible(samples: samples))")
            // Both corpus captures clear it, so the substitution is exercised on the
            // admitting side as well as argued on the rejecting one.
            #expect(SupportRegion.ringBandsAreFeasible(samples: samples))
        }
    }

    // `minResidueSamples` is what is left of `minCandidateSamples` once the whole-fit
    // question is asked exactly. The corpus can bound it from above and not from below:
    // it shows which passes a floor would cut, but nothing in it fails for want of
    // residue, so there is no evidence for where the floor belongs (Decision 32).
    @Test("the corpus bounds the residue floor from above only")
    func residueFloorIsBoundedFromAboveOnly() throws {
        var smallestResidue = Int.max
        for name in Self.captures {
            let candidates = try #require(Self.candidates(name))
            let residues = candidates.map(\.residueCount)
            print("\(name): residue per pass \(residues),"
                  + " extents \(candidates.map(\.extentPx))")
            // Every pass the corpus produces must survive the shipped floor, or the
            // constant is silently discarding candidates — and `planeCandidateCount` is
            // persisted, so a cut pass changes the record even when it changes no plane.
            for residue in residues {
                let cut = "\(name) runs a pass on \(residue) samples, below the"
                    + " \(SupportRegion.minResidueSamples) floor — the floor would cut it"
                #expect(residue >= SupportRegion.minResidueSamples, "\(cut)")
            }
            smallestResidue = min(smallestResidue, residues.min() ?? Int.max)
        }
        // The ceiling, stated as a number so a future session can see how little room
        // there is between the shipped floor and the first pass it would cost.
        print("corpus smallest residue \(smallestResidue),"
              + " shipped floor \(SupportRegion.minResidueSamples)")
        #expect(smallestResidue > SupportRegion.minResidueSamples)
    }

    // `minAcceptedExtentPx` rejects a badly conditioned normal (Req 2.3). The corpus
    // supplies one clear sliver and no clear counter-example, so it brackets the
    // constant rather than setting it — and the bracket is narrow above (Decision 32).
    @Test("the corpus brackets minAcceptedExtentPx without setting it")
    func extentFloorIsBracketedNotSet() throws {
        var slivers: [Int] = [], survivors: [Int] = []
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            for candidate in try #require(Self.candidates(name)) {
                guard let ring = SupportRegion.ringStatistics(
                    samples: samples, geometry: g,
                    normal: candidate.normal, d: candidate.d) else { continue }
                let verdict = SupportRegion.admissibility(
                    ring: ring,
                    annulusMedianMm: SupportRegion.medianHeight(
                        indices: samples.annulus, geometry: g,
                        normal: candidate.normal, d: candidate.d),
                    foodEnvelopeMm: SupportRegion.foodEnvelopeMm(
                        geometry: g, normal: candidate.normal, d: candidate.d),
                    extentPx: candidate.extentPx)
                if verdict == .extent {
                    slivers.append(candidate.extentPx)
                } else {
                    survivors.append(candidate.extentPx)
                }
            }
        }
        let sliverMax = try #require(slivers.max())
        let survivorMin = try #require(survivors.min())
        print("extent: slivers \(slivers.sorted()), reaching later guards"
              + " \(survivors.sorted()), bracket \(sliverMax + 1)...\(survivorMin),"
              + " shipped \(SupportRegion.minAcceptedExtentPx)")
        // The shipped value must sit inside what the corpus brackets, or it is either
        // admitting a sliver or rejecting a candidate the corpus judged on other grounds.
        #expect(SupportRegion.minAcceptedExtentPx > sliverMax)
        #expect(SupportRegion.minAcceptedExtentPx <= survivorMin)
        // The margin above is 2 px. Recorded as an assertion so that a capture which
        // narrows it further fails here rather than silently losing a candidate.
        let margin = survivorMin - SupportRegion.minAcceptedExtentPx
        let tightened = "the extent bracket has closed to \(margin) px —"
            + " minAcceptedExtentPx now needs setting rather than bracketing"
        #expect(margin >= 2, "\(tightened)")
    }

    // `ringOuterMm = 25` is `[owed]` against a stated rule: it "must sit inside the
    // smallest measured plate margin". That margin is a property of the capture
    // geometry — how far the plate extends beyond the food — so unlike a noise
    // threshold it does not need a clean correct-fit capture to measure, and the
    // corpus can answer it (the Decision 29 line on what a two-capture corpus settles).
    //
    // The measure is the SUPPORT MARGIN per sector: the distance from the food boundary
    // at which the surface immediately outside the food departs from itself by more than
    // `ringBandMm`. It is denominated in the same window the sector test uses, so it
    // bounds the guard it feeds rather than being a separate quantity.
    //
    // The answer is that the rule cannot be satisfied. Both captures fall off the plate
    // inside `ringInnerMm` in at least one sector, so no `ringOuterMm` — not even one
    // below the ring's inner edge — sits inside the smallest margin. What the corpus
    // shows instead is that the plate GEOMETRY, on its own and before any noise
    // threshold is consulted, caps the supporting-sector count below
    // `minSupportingSectors` on both captures (Decision 33).
    @Test("the corpus measures the plate margin and finds ringOuterMm's rule unsatisfiable")
    func plateMarginCannotSetRingOuter() throws {
        // The ring's inner band — the arc the sector measure actually reads — reaches
        // only this far, so it is the radius the supporting count is decided at.
        let innerBandOuterMm = SupportRegion.ringInnerMm
            + (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm)
            / Float(SupportRegion.ringBandCount)

        for name in Self.captures {
            let margins = try #require(Self.sectorMargins(name))
            let smallest = try #require(margins.map(\.departureMm).min())
            let onPlateAtRingOuter = margins.filter { $0.departureMm >= SupportRegion.ringOuterMm }
            let onPlateAtInnerBand = margins.filter { $0.departureMm >= innerBandOuterMm }
            print("\(name): margins \(margins.map { fmt($0.departureMm) }),"
                  + " steps \(margins.map { fmt($0.stepMm) }),"
                  + " smallest \(fmt(smallest)),"
                  + " sectors reaching ringOuterMm \(onPlateAtRingOuter.count)/\(margins.count),"
                  + " reaching the inner band's \(fmt(innerBandOuterMm)) mm"
                  + " \(onPlateAtInnerBand.count)/\(margins.count)")

            // Every departure in the ring is a FALL — the plate ending and the table
            // beginning — which is what says these margins are a plate edge rather than
            // the far rim of a bowl or a neighbouring object.
            for margin in margins where margin.departureMm <= SupportRegion.ringOuterMm {
                let rise = "\(name) sector \(margin.sector) departs UPWARD by"
                    + " \(margin.stepMm) mm at \(margin.departureMm) mm — the ring meets a"
                    + " raised rim rather than a plate edge, and these margins measure"
                    + " something other than the surface running out"
                #expect(margin.stepMm < 0, "\(rise)")
            }

            // The finding. The rule in `ringOuterMm`'s comment asks for a value inside
            // the smallest margin; the smallest margin is inside `ringInnerMm`, where no
            // ring can be placed at all.
            let satisfiable = "\(name) now has a smallest margin of \(smallest) mm, at or"
                + " outside ringInnerMm \(SupportRegion.ringInnerMm) — ringOuterMm's stated"
                + " rule is satisfiable on this capture and the constant can be set"
            #expect(smallest < SupportRegion.ringInnerMm, "\(satisfiable)")

            // And the consequence for the sector trio. Fewer sectors reach the inner
            // band's outer radius than `minSupportingSectors` demands, so the supporting
            // count is capped by where the plate ends before `sectorSupportMin` is
            // consulted — the trio is being asked to separate surfaces on a ring the
            // scene cannot fill.
            let reachable = "\(name) has \(onPlateAtInnerBand.count) sectors whose plate"
                + " reaches the inner band, at or above minSupportingSectors"
                + " \(SupportRegion.minSupportingSectors) — the supporting count is no"
                + " longer capped by plate geometry and the trio can be set against noise"
            #expect(onPlateAtInnerBand.count < SupportRegion.minSupportingSectors, "\(reachable)")
        }
    }

    // Why the third committed slice is not in `captures`, measured rather than asserted.
    //
    // `1785054950406` is the 208 g mounded-rice capture — the shape the corpus most
    // lacks, since both admitted captures are flat bread. It passes every check that
    // does not read the confidence map: it slices cleanly, fills all three bands well
    // clear of `ringMinSamples`, and its confident food median sits 15.1 mm above its
    // confident surroundings, which is a plate.
    //
    // What disqualifies it is that τ_conf discards the mound. 43 % of its food-mask
    // samples carry ARKit's low confidence against 0 % on both admitted captures, and
    // the discarded samples are the NEAR ones — median 247.9 mm against the surviving
    // 277.8 mm, i.e. the pile itself. What `prepare` is left holding is the flat
    // remnant around the pile, which is why the best candidate reports a food envelope
    // BELOW its own plane: after filtering, the capture no longer contains a mound.
    //
    // Admitting it would not merely add a weak capture, it would produce a wrong
    // answer. Its best candidate scores 3 supporting sectors, outside the 4...7 band
    // Decision 18's geometry produces — so `sectorTrioDoesNotSeparateTheDecision18Case`
    // would report the trio as separable and the constants would be derived from a
    // capture whose food is missing (Decision 31).
    @Test("the rejected capture is disqualified by depth confidence, not by preference")
    func rejectedCaptureIsNotCorpusGrade() throws {
        for name in Self.captures {
            let share = try Self.lowConfidenceFoodShare(name)
            print("\(name) (admitted): low-confidence food share \(share)")
            #expect(share == 0)
        }

        for name in Self.rejectedCaptures {
            let share = try Self.lowConfidenceFoodShare(name)
            let (g, samples) = try #require(Self.prepared(name))
            let best = try #require(Self.bestCandidate(name))
            let envelope = SupportRegion.foodEnvelopeMm(geometry: g, normal: best.normal, d: best.d)
            let sectors = Self.sectorFractions(
                samples: samples, geometry: g, normal: best.normal, d: best.d)
            let meeting = sectors.filter {
                $0.total > 0 && $0.fraction >= SupportRegion.sectorSupportMin
            }.count
            print("\(name) (rejected): low-confidence food share \(share),"
                  + " surviving food samples \(g.foodSampleCount),"
                  + " food envelope \(envelope) mm, supporting sectors \(meeting)")

            // The disqualifier. Both admitted captures read 0; this one loses nearly
            // half the food region before the fit ever sees it.
            let recovered = "\(name) no longer loses a large share of its food region to"
                + " τ_conf (\(share)) — recheck whether it is corpus-grade after all"
            #expect(share > 0.4, "\(recovered)")

            // The consequence, and the reason the share matters rather than being a
            // quality note: the food that survives sits below the plane fitted around
            // it, so there is no mound left to anchor a non-flat criterion against.
            let mounded = "\(name) now presents a positive food envelope"
                + " (\(envelope) mm) — it may be usable as the capture 2 non-flat anchor"
            #expect(envelope < 0, "\(mounded)")

            // The trap. This is what makes the exclusion worth committing a slice for:
            // a count outside the Decision 18 band is the signal the derivation treats
            // as "the corpus can now set the trio", and this capture supplies it
            // spuriously.
            #expect(meeting < 4,
                    "\(name) no longer produces a spurious separable sector count")
        }
    }

    // MARK: - Helpers

    // Share of food-mask samples ARKit marked low-confidence, which `SupportRegion.prepare`
    // drops at τ_conf before any plane is fitted. Confidence bytes are the three ARKit
    // levels scaled to 0/127/255, and `confidenceThreshold` 0.40 admits the upper two.
    static func lowConfidenceFoodShare(_ name: String) throws -> Float {
        let slice = try DepthSlice.load(name)
        let w = slice.depth.width, h = slice.depth.height
        let confidence = slice.depth.confidenceBytes
        guard confidence.count >= w * h else { return 0 }
        var food = 0, low = 0
        for y in 0..<h {
            for x in 0..<w where slice.foodMask.isFood(x: x, y: y) {
                food += 1
                if Float(confidence[y * w + x]) / 255 < LiDARPlaneFitter.confidenceThreshold {
                    low += 1
                }
            }
        }
        return food == 0 ? 0 : Float(low) / Float(food)
    }

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

    // MARK: - The radial support profile

    // How far the surface the food rests on extends outward, per sector, before
    // something else takes over. `ringOuterMm` is `[owed]` against exactly this
    // quantity — "must sit inside the smallest measured plate margin" — and it is a
    // property of the capture geometry rather than of which plane is correct, so a
    // two-capture corpus can measure it (the Decision 29 rationale for what a small
    // corpus can and cannot settle).
    struct SectorMargin {
        let sector: Int
        let referenceMm: Float   // median height over 0…referenceWidthMm: the surface under the food
        let departureMm: Float   // distance at which the surface leaves that reference
        let stepMm: Float        // signed height of the departure: - is a fall, + is a rise
        let censored: Bool       // no departure anywhere inside the annulus
        let samples: Int
    }

    static let profileBinMm: Float = 2
    // A bin under this is read as coverage noise rather than a departure. At corpus
    // range a 2 mm bin spans roughly one depth pixel of width around the whole arc.
    static let profileBinMinSamples = 10
    // The strip the reference is taken over. Narrow, because the question is what the
    // food is resting on and the answer can change within `ringInnerMm` — it does, on
    // one corpus sector — but not narrower than the ~4 px depth smear at corpus range.
    static let referenceWidthMm: Float = 4

    // Reference is taken PER SECTOR over 0…`referenceWidthMm`, the strip immediately
    // outside the food boundary. Whatever the food rests on, that strip is on it. The
    // plane's normal is borrowed only to remove camera tilt — its offset is not used,
    // so a candidate that is the table rather than the plate still yields the right
    // margins.
    static func sectorMargins(_ name: String) -> [SectorMargin]? {
        guard let g = geometry(name), let best = bestCandidate(name) else { return nil }
        let distancePx = SupportRegion.distanceToFoodPx(mask: g.foodMask)
        let outerMm = SupportRegion.annulusOuterMultiple * SupportRegion.ringOuterMm
        let binCount = Int((outerMm / profileBinMm).rounded(.up))
        var heights = [[[Float]]](
            repeating: [[Float]](repeating: [], count: binCount),
            count: SupportRegion.ringSectorCount)

        for y in 0..<g.height {
            for x in 0..<g.width {
                let idx = y * g.width + x
                guard g.valid[idx], !g.foodMask.isFood(x: x, y: y) else { continue }
                let distMm = distancePx[idx] * g.mmPerPx
                guard distMm <= outerMm else { continue }
                let bin = min(binCount - 1, Int(distMm / profileBinMm))
                let sector = SupportRegion.sectorIndex(x: x, y: y, geometry: g)
                heights[sector][bin].append(best.normal.dot(g.points[idx]) - best.d)
            }
        }

        return (0..<SupportRegion.ringSectorCount).map { sector in
            let bins = heights[sector]
            let referenceBins = Int(referenceWidthMm / profileBinMm)
            let near = bins.prefix(referenceBins).flatMap { $0 }
            let total = bins.reduce(0) { $0 + $1.count }
            guard !near.isEmpty else {
                return SectorMargin(sector: sector, referenceMm: .nan, departureMm: .nan,
                                    stepMm: .nan, censored: true, samples: total)
            }
            let reference = near.sorted()[near.count / 2]
            for bin in referenceBins..<binCount where bins[bin].count >= profileBinMinSamples {
                let median = bins[bin].sorted()[bins[bin].count / 2]
                guard abs(median - reference) > SupportRegion.ringBandMm else { continue }
                // The inner edge of the departing bin: the surface is intact up to here.
                return SectorMargin(sector: sector, referenceMm: reference,
                                    departureMm: Float(bin) * profileBinMm,
                                    stepMm: median - reference,
                                    censored: false, samples: total)
            }
            return SectorMargin(sector: sector, referenceMm: reference, departureMm: outerMm,
                                stepMm: 0, censored: true, samples: total)
        }
    }
}

private func fmt(_ value: Float) -> String {
    String(format: "%.3f", value)
}
