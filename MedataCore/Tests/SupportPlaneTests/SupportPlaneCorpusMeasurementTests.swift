import CaptureKit
import Confidence
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing
import Volume

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
                      + " extent \(candidate.extentPx) px = \(fmt(candidate.extentMm)) mm,"
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
                    extentMm: candidate.extentMm)
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
            let annulusWidthPx = (SupportRegion.annulusOuterMm)
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

    // The support-surface depth-noise distribution, and the pipeline Decision 46 tension.
    // `ringSupportMin = 0.6` over a +/-`ringBandMm` band is a statement about noise: a
    // plane truly on the support surface passes only if a 0.6 share of inner-band
    // samples lands within +/-5 mm, which implies sigma_z <~ 5.9 mm. Pipeline Decision 46's
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
        // difference, not a range one, which is exactly what pipeline Decision 46's matte-table
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

    // Decision 30 recorded, as a PROPOSAL, that the sector count takes `|height|` and so
    // reads the same 5 of 8 for two opposite scenes. It left the proposal unresolved on
    // one ground: a rule that rejects on signed sectors "needs a threshold, and that
    // threshold has the same evidence problem as every other `[owed]` constant".
    //
    // That ground is what this measures, and it does not hold. The threshold the rule
    // needs on the MAGNITUDE axis is `ringBandMm`, which is `[inherited]` from
    // `LiDARPlaneFitter.inlierBandMm` and already defines "supported" for the very
    // sectors being classified — so the signed rule adds no new millimetre constant. What
    // it does add is a COUNT, and that count the corpus brackets rather than sets.
    //
    // Restricting the sign test to sectors that already FAIL `sectorSupportMin` is what
    // makes the bar inherited rather than fitted: across all sectors the separating bar
    // has to sit in a 2 mm window, and across failing sectors it has a 23 mm one that
    // contains both `ringBandMm` and zero. Both readings are recorded below.
    @Test("the sign of a failing sector separates the two scenes its count cannot")
    func failingSectorSignSeparatesWhatTheCountCannot() throws {
        var byCapture: [String: SectorSigns] = [:]

        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            let candidates = try #require(Self.candidates(name))
            let best = try #require(Self.bestCandidate(name))
            // Every candidate, not just the intended one: six planes of known character
            // is the widest reading a two-capture corpus supports, and a rule that only
            // works on the two rows it was written from is not a rule.
            for (i, candidate) in candidates.enumerated() {
                let signs = Self.sectorSigns(
                    samples: samples, geometry: g, normal: candidate.normal, d: candidate.d)
                print("\(name) candidate \(i): supporting \(signs.supporting)/"
                      + "\(SupportRegion.ringSectorCount), failing \(signs.failing),"
                      + " failing medians \(signs.failingMedians.map { fmt($0) }),"
                      + " crossed(failing) \(signs.crossedFailing),"
                      + " escaped(failing) \(signs.escapedFailing),"
                      + " crossed(all) \(signs.crossedAll)")
                if candidate.normal == best.normal, candidate.d == best.d {
                    byCapture[name] = signs
                }
            }
        }

        let plate = try #require(byCapture["1785135663727"])   // ring median −0.93 mm
        let table = try #require(byCapture["1785901032716"])   // ring median +3.04 mm

        // The premise. Decision 30's two rows agree exactly in the statistic the guard
        // reads, which is why no `minSupportingSectors` separates them.
        let premise = "the two intended candidates no longer score the same supporting count"
            + " (\(plate.supporting) vs \(table.supporting)) — Decision 30's premise has moved"
            + " and the signed rule has to be re-derived"
        #expect(plate.supporting == table.supporting, "\(premise)")

        // The finding. The failing sectors of a candidate that IS the support surface all
        // read below it — the ring ran off the plate onto the table. The failing sectors
        // of a candidate that is the SURROUNDING surface all read above it — part of the
        // ring is still on the plate. Neither capture mixes the two signs.
        let escape = "1785135663727's failing sectors are no longer uniformly below its"
            + " plane (\(plate.failingMedians.map { fmt($0) })) — the escape reading is not clean"
        #expect(plate.crossedFailing == 0 && plate.escapedFailing == plate.failing.count,
                "\(escape)")
        let crossing = "1785901032716's failing sectors are no longer uniformly above its"
            + " plane (\(table.failingMedians.map { fmt($0) })) — the crossing reading is not clean"
        #expect(table.escapedFailing == 0 && table.crossedFailing == table.failing.count,
                "\(crossing)")

        // The magnitude bar is inherited, not owed. Any bar strictly between the two
        // captures' extreme failing medians separates them, and `ringBandMm` is inside
        // that window with room on both sides.
        let plateWorst = try #require(plate.failingMedians.max())
        let tableBest = try #require(table.failingMedians.min())
        print("failing-sector window \(fmt(plateWorst))…\(fmt(tableBest)) mm,"
              + " width \(fmt(tableBest - plateWorst)) mm,"
              + " ringBandMm \(SupportRegion.ringBandMm) sits"
              + " \(fmt(SupportRegion.ringBandMm - plateWorst)) mm above the floor and"
              + " \(fmt(tableBest - SupportRegion.ringBandMm)) mm below the ceiling")
        let window = "ringBandMm = \(SupportRegion.ringBandMm) no longer lies between the"
            + " captures' extreme failing medians (\(fmt(plateWorst))…\(fmt(tableBest))) — the"
            + " signed rule would need a bar of its own after all"
        #expect(plateWorst < SupportRegion.ringBandMm
                && SupportRegion.ringBandMm < tableBest, "\(window)")

        // Why the rule is stated over FAILING sectors. Applied to every sector, the
        // separating window is the plate's highest median against the table's lowest
        // CROSSED one, and that collapses to a fraction of the width above. `ringBandMm`
        // survives inside it, but by about a millimetre — a bar with that much headroom
        // is being fitted to the corpus rather than inherited, which Req 3.7 forbids.
        let plateHighest = try #require(plate.medians.max())
        let tableCrossedLowest = try #require(
            table.medians.filter { $0 > SupportRegion.ringBandMm }.min())
        print("all-sector window \(fmt(plateHighest))…\(fmt(tableCrossedLowest)) mm,"
              + " width \(fmt(tableCrossedLowest - plateHighest)) mm;"
              + " crossed(all) plate \(plate.crossedAll), table \(table.crossedAll)")
        let allSector = "the all-sector window is no longer the narrower of the two — the"
            + " rule need not be restricted to failing sectors"
        #expect(tableCrossedLowest - plateHighest < tableBest - plateWorst, "\(allSector)")

        // The COUNT is what stays owed. The rule fires when more than `maxCrossedSectors`
        // failing sectors read above the plane; the corpus says that ceiling is at least 0
        // and at most one below the table candidate's count, and says nothing inside.
        // Prerequisites capture 6 — food filling a small plate — is what sets it.
        let ceilingHigh = table.crossedFailing - 1
        print("maxCrossedSectors bracketed \(plate.crossedFailing)…\(ceilingHigh)"
              + " (\(ceilingHigh - plate.crossedFailing + 1) admissible values)")
        let bracket = "the corpus no longer brackets maxCrossedSectors — plate reads"
            + " \(plate.crossedFailing) crossed and table reads \(table.crossedFailing),"
            + " so there is no ceiling admitting one and rejecting the other"
        #expect(plate.crossedFailing <= ceilingHigh, "\(bracket)")
        // Bracketed, NOT set: more than one value survives, so this is not a derivation.
        let collapsed = "the bracket has collapsed to a single value — maxCrossedSectors"
            + " would be measured rather than owed, and the design must be updated to say so"
        #expect(ceilingHigh - plate.crossedFailing >= 1, "\(collapsed)")
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

    // The residue floor is what is left of `minCandidateSamples` once the whole-fit
    // question is asked exactly. The corpus can bound it from above and not from below:
    // it shows which passes a floor would cut, but nothing in it fails for want of
    // residue, so there is no evidence for where the floor belongs (Decision 32).
    //
    // Measured in MILLIMETRES² since Decision 38, for the same reason the extent bar is
    // (Decision 37): a sample count is a property of the grid, and this one decided how
    // many extraction passes ran.
    @Test("the corpus bounds the residue floor from above only")
    func residueFloorIsBoundedFromAboveOnly() throws {
        var smallestResidueMm2 = Float.greatestFiniteMagnitude
        for name in Self.captures {
            let g = try #require(Self.geometry(name))
            let candidates = try #require(Self.candidates(name))
            let pixelAreaMm2 = g.mmPerPx * g.mmPerPx
            let residues = candidates.map(\.residueCount)
            let residueAreas = residues.map { Float($0) * pixelAreaMm2 }
            print("\(name): residue per pass \(residues) samples"
                  + " = \(residueAreas.map { fmt($0) }) mm², floor"
                  + " \(SupportRegion.minResidueAreaMm2) mm²"
                  + " = \(SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)) samples here,"
                  + " extents \(candidates.map { fmt($0.extentMm) }) mm")
            // Every pass the corpus produces must survive the shipped floor, or the
            // constant is silently discarding candidates — and `planeCandidateCount` is
            // persisted, so a cut pass changes the record even when it changes no plane.
            for area in residueAreas {
                let cut = "\(name) runs a pass on \(area) mm² of residue, below the"
                    + " \(SupportRegion.minResidueAreaMm2) mm² floor — the floor would cut it"
                #expect(area >= SupportRegion.minResidueAreaMm2, "\(cut)")
            }
            // The re-denomination holds the value: at corpus resolution the area floor
            // is the 500 samples the count floor was, or fewer, so nothing it used to
            // admit is now rejected.
            #expect(SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx) <= 500)
            smallestResidueMm2 = min(smallestResidueMm2, residueAreas.min() ?? .greatestFiniteMagnitude)
        }
        // The ceiling, stated as a number so a future session can see how little room
        // there is between the shipped floor and the first pass it would cost.
        print("corpus smallest residue \(fmt(smallestResidueMm2)) mm²,"
              + " shipped floor \(SupportRegion.minResidueAreaMm2) mm²")
        #expect(smallestResidueMm2 > SupportRegion.minResidueAreaMm2)
    }

    // `minAcceptedExtentMm` rejects a badly conditioned normal (Req 2.3). The corpus
    // supplies one clear sliver and no clear counter-example, so it brackets the
    // constant rather than setting it — and the bracket is narrow above (Decision 32).
    //
    // The bracket is in MILLIMETRES since Decision 37. In pixels it was 13…26, but that
    // was a 256×192 bracket: the same two numbers meant different physical sizes on the
    // two captures, whose `mmPerPx` differ, and meant nothing at all on another grid.
    @Test("the corpus brackets minAcceptedExtentMm without setting it")
    func extentFloorIsBracketedNotSet() throws {
        var slivers: [Float] = [], survivors: [Float] = []
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
                    extentMm: candidate.extentMm)
                if verdict == .extent {
                    slivers.append(candidate.extentMm)
                } else {
                    survivors.append(candidate.extentMm)
                }
            }
        }
        let sliverMax = try #require(slivers.max())
        let survivorMin = try #require(survivors.min())
        print("extent: slivers \(slivers.sorted().map(fmt)), reaching later guards"
              + " \(survivors.sorted().map(fmt)), bracket \(fmt(sliverMax))...\(fmt(survivorMin)) mm,"
              + " shipped \(SupportRegion.minAcceptedExtentMm) mm")
        // The shipped value must sit inside what the corpus brackets, or it is either
        // admitting a sliver or rejecting a candidate the corpus judged on other grounds.
        #expect(SupportRegion.minAcceptedExtentMm > sliverMax)
        #expect(SupportRegion.minAcceptedExtentMm <= survivorMin)
        // The margin above is 3.8 mm — the same 2 px of Decision 32, now stated in the
        // units the guard reads. Recorded as an assertion so that a capture which
        // narrows it further fails here rather than silently losing a candidate.
        let margin = survivorMin - SupportRegion.minAcceptedExtentMm
        let tightened = "the extent bracket has closed to \(margin) mm —"
            + " minAcceptedExtentMm now needs setting rather than bracketing"
        #expect(margin >= 3.5, "\(tightened)")
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

    // Which guards the corpus actually exercises. `admissibility` short-circuits at the
    // first rejection, so the reason it returns says which guard came first, not which
    // guards would have fired. The order has no observable effect — the reason is not
    // persisted, and a rejected candidate is rejected — but it does decide what a
    // measurement pass can see, and a constant behind a guard that is never reached is
    // not merely unset: nothing in the corpus says it is even correctly oriented.
    //
    // This evaluates every guard independently. Under the shipped order only THREE
    // reasons ever fire on the corpus; evaluated independently a fourth does, and five
    // never fire at all — among them four of the `[owed]` constants (Decision 34).
    @Test("five of the nine rejection reasons never fire on the corpus")
    func laterGuardsAreUnexercisedOnTheCorpus() throws {
        var shipped: Set<SupportRegion.CandidateRejection> = []
        var independent: Set<SupportRegion.CandidateRejection> = []

        for name in Self.captures {
            for m in try #require(Self.measurements(name)) {
                let all = Self.allRejections(m)
                let verdict = SupportRegion.admissibility(
                    ring: m.ring, annulusMedianMm: m.annulusMedianMm,
                    foodEnvelopeMm: m.envelopeMm, extentMm: m.candidate.extentMm)
                print("\(name): candidate at \(fmt(m.ring.medianMm)) mm — shipped verdict"
                      + " \(verdict?.rawValue ?? "ADMITTED"), all guards \(all.map(\.rawValue))")
                // Pins the duplication: `allRejections` restates the shipped conditions,
                // so its first entry must be exactly what `admissibility` returns, or the
                // two have drifted and every count below is measuring the wrong thing.
                #expect(all.first == verdict,
                        "\(name) guard restatement has drifted from `admissibility`")
                if let verdict { shipped.insert(verdict) }
                independent.formUnion(all)
            }
        }

        // No candidate reaches the ring-unavailable path either — `bandsClearTheSampleFloor`
        // is why — so the unexercised set is these five.
        let unexercised: Set<SupportRegion.CandidateRejection> =
            [.ringUnavailable, .foodEnvelope, .bandStep, .visibility, .escaped]
        print("corpus fires \(shipped.map(\.rawValue).sorted()) under the shipped order,"
              + " \(independent.map(\.rawValue).sorted()) with every guard evaluated")

        for reason in unexercised {
            let fired = "\(reason.rawValue) now fires somewhere in the corpus — the guard"
                + " behind it is exercised and its constant can be measured rather than"
                + " merely bounded"
            #expect(!independent.contains(reason), "\(fired)")
        }
        // And the converse, so a capture that stops exercising a guard is caught too.
        #expect(independent == [.extent, .supportFraction, .sectors, .ringMedian])
        #expect(shipped == [.extent, .supportFraction, .sectors])
    }

    // `foodEnvelopeMinMm = 0` is the Decision 22 replacement for `foodAboveFractionMax`,
    // which rejected this feature's own acceptance capture. The corpus bounds it from
    // ABOVE — above the envelope of the candidate the design intends to select, the guard
    // rejects the fit this feature exists to produce — and not from below, because the
    // negative-envelope cases it is written for (a bowl, a plane on the food top) are
    // scenes the corpus does not contain.
    @Test("the corpus bounds foodEnvelopeMinMm from above only")
    func foodEnvelopeFloorIsBoundedFromAboveOnly() throws {
        var ceiling = Float.greatestFiniteMagnitude
        for name in Self.captures {
            let measurements = try #require(Self.measurements(name))
            let best = try #require(Self.bestCandidate(name))
            let intended = try #require(measurements.first { $0.candidate.d == best.d })
            print("\(name): envelopes \(measurements.map { fmt($0.envelopeMm) }),"
                  + " intended candidate \(fmt(intended.envelopeMm)) mm,"
                  + " shipped floor \(SupportRegion.foodEnvelopeMinMm) mm")
            // Every envelope in the corpus is positive, so nothing here approaches the
            // guard from the side it is written to catch.
            for m in measurements {
                let bounded = "\(name) now produces a negative food envelope"
                    + " (\(m.envelopeMm) mm) — the corpus can bound foodEnvelopeMinMm from below"
                #expect(m.envelopeMm > 0, "\(bounded)")
            }
            ceiling = min(ceiling, intended.envelopeMm)
        }
        print("corpus ceiling on foodEnvelopeMinMm \(fmt(ceiling)) mm,"
              + " shipped \(SupportRegion.foodEnvelopeMinMm) mm")
        #expect(SupportRegion.foodEnvelopeMinMm < ceiling)
    }

    // `bandStepMaxMm = 6` fires on an outward RISE across the inner→mid step (Decision 21):
    // a rim beginning inside the ring, or a bowl wall. Every step the corpus produces is a
    // FALL — the plate ending and the table beginning — so the corpus supplies no floor for
    // the constant, and its ceiling ("below the smallest measured rim step") is owed to the
    // ruler measurement `prerequisites.md` still carries.
    @Test("no candidate on the corpus produces the outward rise bandStepMaxMm reads")
    func bandStepIsUnapproachedOnTheCorpus() throws {
        var largestRise = -Float.greatestFiniteMagnitude
        for name in Self.captures {
            let measurements = try #require(Self.measurements(name))
            let steps = measurements.map { $0.ring.bandMedianMm[1] - $0.ring.bandMedianMm[0] }
            print("\(name): inner→mid steps \(steps.map { fmt($0) }) mm,"
                  + " shipped bar \(SupportRegion.bandStepMaxMm) mm")
            for step in steps {
                let rise = "\(name) now steps UP by \(step) mm across inner→mid — the corpus"
                    + " contains a rise and bandStepMaxMm can be bounded against it"
                #expect(step < 0, "\(rise)")
            }
            largestRise = max(largestRise, steps.max() ?? largestRise)
        }
        print("corpus largest inner→mid step \(fmt(largestRise)) mm,"
              + " \(fmt(SupportRegion.bandStepMaxMm - largestRise)) mm below the bar")
        #expect(largestRise < SupportRegion.bandStepMaxMm)
    }

    // Req 3.3 rejects a plane lying BELOW the surrounding surface, so the comparator is
    // correctly one-sided: a plane the surroundings sit above reads a POSITIVE annulus
    // median. The corpus confirms the orientation and nothing else — its largest positive
    // annulus median is a fifth of the bar, and its largest magnitude is on the other sign
    // entirely, where Req 3.3 makes no claim and `ringMedianMaxMm` is the guard that fires.
    @Test("escapeBandMm is oriented for Req 3.3 and unapproached by the corpus")
    func escapeBandIsOrientedAndUnapproached() throws {
        var highest = -Float.greatestFiniteMagnitude, lowest = Float.greatestFiniteMagnitude
        for name in Self.captures {
            let measurements = try #require(Self.measurements(name))
            let medians = measurements.map(\.annulusMedianMm)
            print("\(name): annulus medians \(medians.map { fmt($0) }) mm,"
                  + " shipped bar \(SupportRegion.escapeBandMm) mm")
            for m in measurements {
                // The sign check that says the orientation is right: the one candidate far
                // from its surroundings is far ABOVE them (−36.6 mm), which is a plane on
                // the food top, not an escape, and it is `ringMedian` that rejects it.
                if m.annulusMedianMm < -SupportRegion.escapeBandMm {
                    let unguarded = "\(name) has a candidate \(m.annulusMedianMm) mm above"
                        + " its surroundings that ringMedian does not reject — the escape"
                        + " guard's one-sidedness now leaves a candidate unguarded"
                    #expect(abs(m.ring.bandMedianMm[0]) > SupportRegion.ringMedianMaxMm,
                            "\(unguarded)")
                }
            }
            highest = max(highest, medians.max() ?? highest)
            lowest = min(lowest, medians.min() ?? lowest)
        }
        print("corpus annulus medians span \(fmt(lowest))…\(fmt(highest)) mm"
              + " against escapeBandMm \(SupportRegion.escapeBandMm) mm")
        let approached = "the corpus now reaches \(fmt(highest)) mm, within reach of"
            + " escapeBandMm \(SupportRegion.escapeBandMm) — the constant can be bounded"
        #expect(highest < SupportRegion.escapeBandMm / 2, "\(approached)")
    }

    // The ambiguity margin cannot fire on this corpus: it compares the top TWO admissible
    // candidates and neither capture produces one. What the corpus can show is where the
    // constant sits relative to the gaps real candidates open — and 0.15 falls BETWEEN the
    // two captures' gaps, so it would call one pair distinct and the other ambiguous while
    // neither capture supplies a known-correct winner to say which verdict is right.
    @Test("ringSupportMarginMin falls between the corpus's two candidate gaps")
    func ambiguityMarginFallsBetweenTheCorpusGaps() throws {
        var gaps: [Float] = []
        for name in Self.captures {
            let measurements = try #require(Self.measurements(name))
            let admissible = measurements.filter { Self.allRejections($0).isEmpty }
            let fractions = measurements.map(\.ring.supportFraction).sorted(by: >)
            let gap = fractions[0] - fractions[1]
            print("\(name): support fractions \(fractions.map { fmt($0) }),"
                  + " top-two gap \(fmt(gap)), admissible \(admissible.count),"
                  + " shipped margin \(SupportRegion.ringSupportMarginMin)")
            // The guard needs two admissible candidates. Both captures produce none, so
            // it has never run on real data — this is the assertion that says so.
            let reachable = "\(name) now produces \(admissible.count) admissible candidates"
                + " — ringSupportMarginMin is reachable and can be measured"
            #expect(admissible.count < 2, "\(reachable)")
            gaps.append(gap)
        }
        let low = try #require(gaps.min()), high = try #require(gaps.max())
        print("corpus top-two gaps span \(fmt(low))…\(fmt(high))"
              + " around ringSupportMarginMin \(SupportRegion.ringSupportMarginMin)")
        // Straddled, in the same shape as `ringBandMm` and the noise figures (Decision 29):
        // a constant a corpus brackets from both sides at once is a constant the corpus
        // cannot set.
        let settled = "the corpus no longer straddles ringSupportMarginMin"
            + " (\(fmt(low))…\(fmt(high))) — the margin can be derived"
        #expect(low < SupportRegion.ringSupportMarginMin
                && high > SupportRegion.ringSupportMarginMin, "\(settled)")
    }

    // MARK: - Req 5.1: the device/replay tolerance

    // Req 5.1 asks for support-plane coefficients "equal within a documented tolerance,
    // verified on a named fixture", and the tolerance is one of the numbers design.md
    // records as owed. Since task 16 there is ONE implementation behind both paths, so
    // the arithmetic half of the question is already answered exactly: identical bytes
    // give an identical plane (`fitIsDeterministic`, Req 7.7), and a tolerance over that
    // would be measuring nothing.
    //
    // What legitimately differs between a device capture and its replay is the DEPTH
    // GRID — design.md's own transfer table names the N5k identity grid — and until now
    // that claim was tested only on a synthetic scene built to satisfy it
    // (`fitTransfersAcrossDepthGrids`), where the geometry is exact by construction.
    // This measures it on the committed captures instead: decimate the depth grid 2x,
    // refit, and compare where the plane lands at the food.
    //
    // The comparison point is the food-mask centroid RAY of the native grid, evaluated
    // against both planes. That is the quantity volume is integrated against — a plane
    // that moves 1 mm there adds 1 mm to every food pixel — so it is the tolerance the
    // requirement is about, rather than a coefficient difference in arbitrary units.
    @Test("the plane transfers across a depth-grid halving within the documented tolerance")
    func planeTransfersAcrossADepthGridHalving() throws {
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let native = try #require(Self.gridFit(slice, decimation: 1))
            let halved = try #require(Self.gridFit(slice, decimation: 2))
            let ray = try #require(Self.foodCentroidRay(slice))
            let a = try #require(native.best), b = try #require(halved.best)

            let depthA = Self.planeDepthMm(normal: a.candidate.normal, d: a.candidate.d, ray: ray)
            let depthB = Self.planeDepthMm(normal: b.candidate.normal, d: b.candidate.d, ray: ray)
            let moveMm = abs(depthA - depthB)
            let tiltDeg = Self.angleDeg(a.candidate.normal, b.candidate.normal)
            print("\(name): \(native.widthPx)px -> \(halved.widthPx)px,"
                  + " plane depth at food \(fmt(depthA)) -> \(fmt(depthB)) mm"
                  + " (move \(fmt(moveMm)) mm, tilt \(fmt(tiltDeg))°),"
                  + " ring median \(fmt(a.ring.medianMm)) -> \(fmt(b.ring.medianMm)) mm,"
                  + " support \(fmt(a.ring.supportFraction)) -> \(fmt(b.ring.supportFraction)),"
                  + " candidates \(native.candidates.count) -> \(halved.candidates.count)")

            let outside = "\(name) plane moves \(moveMm) mm across the halving, outside"
                + " the \(Self.gridTransferToleranceMm) mm tolerance"
            #expect(moveMm <= Self.gridTransferToleranceMm, "\(outside)")
            // Same surface, not merely a nearby number: a flip from the plate to the
            // table would move the ring measure by the plate height, not by a millimetre.
            #expect(abs(a.ring.medianMm - b.ring.medianMm) <= Self.gridTransferToleranceMm,
                    "\(name) ring median moves \(a.ring.medianMm) -> \(b.ring.medianMm) mm")
            #expect(tiltDeg < 1.5, "\(name) normal tilts \(tiltDeg)° across the halving")

            // `planeCandidateCount` is persisted (Req 6.1, task 12) and used to be the
            // second thing here that did not transfer: the coarser grid ran fewer
            // extraction passes, because the residue floor was a raw SAMPLE count and
            // the residue quarters under a 2x halving. Decision 38 denominated the floor
            // in millimetres² instead, and the count now follows the scene.
            let drifted = "\(name) extracts \(halved.candidates.count) candidates on the"
                + " halved grid against \(native.candidates.count) native —"
                + " planeCandidateCount is grid-dependent again"
            #expect(halved.candidates.count == native.candidates.count, "\(drifted)")
        }
    }

    // The measurement behind Decision 38, and the reason the floor could be re-denominated
    // without inventing a value: the residue's AREA is what the grid leaves alone. The
    // sample count quarters under a 2x halving because a depth pixel covers 4x the
    // surface, and the two cancel.
    @Test("the residue a pass draws from is an area, and the area survives a grid halving")
    func residueAreaTransfersAcrossAGridHalving() throws {
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let native = try #require(Self.gridFit(slice, decimation: 1))
            let halved = try #require(Self.gridFit(slice, decimation: 2))
            let nativeArea = native.mmPerPx * native.mmPerPx
            let halvedArea = halved.mmPerPx * halved.mmPerPx
            let nativeResidues = native.candidates.map { Float($0.candidate.residueCount) * nativeArea }
            let halvedResidues = halved.candidates.map { Float($0.candidate.residueCount) * halvedArea }
            print("\(name): residue per pass \(native.candidates.map(\.candidate.residueCount))"
                  + " -> \(halved.candidates.map(\.candidate.residueCount)) samples,"
                  + " \(nativeResidues.map { fmt($0) }) -> \(halvedResidues.map { fmt($0) }) mm²;"
                  + " floor \(SupportRegion.minResidueSamples(mmPerPx: native.mmPerPx))"
                  + " -> \(SupportRegion.minResidueSamples(mmPerPx: halved.mmPerPx)) samples")

            #expect(nativeResidues.count == halvedResidues.count)
            // Pass 1 draws from the annulus itself, which nothing has removed from yet,
            // so this is the grid acting on a fixed set of surface: 0.3 % and 1.2 %.
            let annulusDrift = abs(nativeResidues[0] - halvedResidues[0]) / nativeResidues[0]
            #expect(annulusDrift < 0.02,
                    "\(name) annulus area \(nativeResidues[0]) -> \(halvedResidues[0]) mm²")
            for (i, (a, b)) in zip(nativeResidues, halvedResidues).enumerated() {
                // Later passes drift further — up to 22.7 % on pass 3 — because each
                // pass removes its OWN inliers within a mm band and that removal is
                // resolved on the grid, so the coarser run removes a slightly different
                // set. The bar is 25 %: what matters is that the drift stays an order
                // below the 4x the sample count moves by, not that it vanishes.
                let drift = abs(a - b) / max(a, b)
                #expect(drift < 0.25,
                        "\(name) pass \(i + 1) residue \(a) -> \(b) mm², \(drift * 100) % apart")
            }
            // The sample count is what moves: each pass draws from roughly a quarter of
            // the samples on the halved grid, which is why a floor denominated in them
            // decided how many passes ran.
            for (a, b) in zip(native.candidates, halved.candidates) {
                #expect(b.candidate.residueCount < a.candidate.residueCount / 2)
            }
            // The pass the old floor cut. Its residue clears the area floor on both
            // grids while its halved-grid SAMPLE count is below the 500 the floor used
            // to be — which is the whole of Decision 38 in one comparison.
            let last = try #require(halved.candidates.last)
            #expect(last.candidate.residueCount < 500)
            #expect(Float(last.candidate.residueCount) * halvedArea >= SupportRegion.minResidueAreaMm2)
        }
    }

    // The transfer claim's floor. Halving again refuses the fit outright, and the guard
    // that refuses it is `ringBandsAreFeasible` — the ring, not the plane. Both bounds
    // that decide it are the same quantity, `mmPerPx`: coarsening the grid divides f_d
    // exactly as increasing the range multiplies z, so this is Decision 29's ~365 mm
    // range envelope reached from the other direction.
    @Test("the grid transfer has a resolution floor and it is the ring's sample floor")
    func gridTransferRefusesBelowTheRingSampleFloor() throws {
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let halved = try #require(Self.gridFit(slice, decimation: 2))
            let quartered = try #require(Self.gridFit(slice, decimation: 4))
            print("\(name): \(halved.widthPx)px bands \(halved.bandCounts)"
                  + " mmPerPx \(fmt(halved.mmPerPx)) smear \(fmt(4 * halved.mmPerPx)) mm"
                  + " feasible \(halved.feasible); \(quartered.widthPx)px bands"
                  + " \(quartered.bandCounts) mmPerPx \(fmt(quartered.mmPerPx))"
                  + " smear \(fmt(4 * quartered.mmPerPx)) mm feasible \(quartered.feasible)")

            #expect(halved.feasible)
            let survives = "\(name) still fills three ring bands at \(quartered.widthPx) px"
                + " — the transfer envelope is wider than 2x and can be measured further down"
            #expect(!quartered.feasible, "\(survives)")
            // The inner band is what runs out first: it is the narrowest in millimetres,
            // so it is the first to fall below one pixel of width.
            #expect(quartered.bandCounts[0] < SupportRegion.ringMinSamples)
            #expect(quartered.bandCounts[0] < quartered.bandCounts[1])
            // And the smear bound of Decision 29 is already violated one step ABOVE the
            // floor — at half resolution the 4 px smear is ~15 mm against ringInnerMm 8 —
            // while the plane still transfers within a millimetre. The smear governs how
            // clean the ring measure is, not where the plane lands.
            #expect(4 * halved.mmPerPx > SupportRegion.ringInnerMm)
        }
    }

    // The last standing "must" on a `[measured]` constant, measured before it is obeyed.
    //
    // `ringInnerMm = 8` stands for the ~4 px depth smear, and a smear is a PIXEL
    // quantity, so what it spans in millimetres scales with range: `smear_mm = 4z/f_d`.
    // Decision 29 measured the envelope at ≈365 mm and both the constant's own comment
    // and `prerequisites.md` conclude that the radius "must become
    // `max(ringInnerMm, 4 × mmPerPx)`" before any capture beyond it is trusted.
    //
    // It must not. `mmPerPx` is `z/f_d` and carries BOTH quantities — coarsening the grid
    // divides f_d exactly as increasing the range multiplies z — but only one of them
    // moves the smear. Decimation subsamples a map ARKit has ALREADY smoothed, so the
    // physical smear stays where it was while `4 × mmPerPx` doubles, and the proposed
    // radius chases a smear the grid does not have. This measures what obeying it costs.
    @Test("the smear-tracking inner radius chases a smear a coarser grid does not have")
    func smearTrackingInnerRadiusCollapsesTheRing() throws {
        var halvedFeasible: [String: Bool] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let native = try #require(Self.geometry(slice, decimation: 1))
            let halved = try #require(Self.geometry(slice, decimation: 2))

            for g in [native, halved] {
                let proposed = max(SupportRegion.ringInnerMm, 4 * g.mmPerPx)
                let shipped = Self.bandCounts(geometry: g, innerMm: SupportRegion.ringInnerMm)
                let dynamic = Self.bandCounts(geometry: g, innerMm: proposed)
                let bandWidthMm = (SupportRegion.ringOuterMm - proposed)
                    / Float(SupportRegion.ringBandCount)
                print("\(name): \(g.width)px mmPerPx \(fmt(g.mmPerPx)) — inner radius"
                      + " \(fmt(SupportRegion.ringInnerMm)) -> \(fmt(proposed)) mm,"
                      + " band width \(fmt(bandWidthMm)) mm against one pixel of"
                      + " \(fmt(g.mmPerPx)) mm, bands \(shipped) -> \(dynamic)")

                if g.width == native.width {
                    // At corpus range the repair is a no-op: `max` picks the constant,
                    // because the smear is 7.45 and 7.36 mm against 8. Whatever is
                    // decided here, nothing on this corpus moves.
                    #expect(proposed == SupportRegion.ringInnerMm)
                    #expect(dynamic == shipped)
                } else {
                    #expect(proposed > SupportRegion.ringInnerMm)
                    // The robust half of the finding, and it holds on both captures: the
                    // radius eats 6.9 mm of a 17 mm ring, so the three bands it leaves are
                    // each NARROWER THAN ONE DEPTH PIXEL. Three sub-pixel bands are not
                    // three radial samples of the surface whatever their counts total —
                    // Decision 14 resolved the ring radially to tell the surface next to
                    // the food from the one beyond it, and a band the grid cannot resolve
                    // cannot make that distinction.
                    #expect(bandWidthMm < g.mmPerPx)
                    #expect(shipped.allSatisfy { $0 >= SupportRegion.ringMinSamples })
                    halvedFeasible[name] = dynamic
                        .allSatisfy { $0 >= SupportRegion.ringMinSamples }
                }
            }
        }

        // And the fragile half, which is the reason this is a rejection rather than a
        // trade-off. Under the shipped radius BOTH captures clear the sample floor at
        // 128 px, which is what Req 5.1's documented 2× transfer envelope rests on. Under
        // the smear-tracking radius one of them stops clearing it and the other clears it
        // by nothing at all — the inner band reads 166 against a 200 floor on
        // `1785135663727` and exactly 200 on `1785901032716`. Two captures of the same
        // scene type, one plate apart, landing either side of the bar is what a
        // sub-pixel band produces: the counts are quantisation, not support.
        let survivors = halvedFeasible.filter(\.value).keys.sorted()
        print("smear-tracking radius at 128 px: \(halvedFeasible.count - survivors.count)"
              + " of \(halvedFeasible.count) captures lose ring feasibility;"
              + " survivors \(survivors)")
        let free = "every capture keeps ring feasibility at 128 px under a smear-tracking"
            + " inner radius — the repair costs nothing measurable and Decision 39's"
            + " rejection no longer has evidence behind it"
        #expect(survivors.count < halvedFeasible.count, "\(free)")
    }

    // What is left once the repair is refused: a RANGE envelope on a constant that has
    // no range term. `ringInnerMm` covers the smear out to `ringInnerMm × f_d / 4`, and
    // f_d is the one quantity here the capture session cannot vary by accident — it is
    // the sensor's. So the envelope is a property of the device, computed once from the
    // corpus, and the session's job is to stay inside it and record where it stood.
    //
    // The margin is the finding: the corpus does not sit comfortably inside this bound.
    @Test("the smear envelope is a range bound derived from f_d, and the corpus nearly reaches it")
    func smearEnvelopeIsARangeBoundTheCorpusNearlyReaches() throws {
        for name in Self.captures {
            let g = try #require(Self.geometry(name))
            // `mmPerPx` is `median(foodDepths) / f_d`, so this recovers the range the
            // smear was measured at without the pass having to carry it separately.
            let rangeMm = g.mmPerPx * g.intrinsics.fx
            let envelopeMm = SupportRegion.ringInnerMm * g.intrinsics.fx / 4
            let usedFraction = rangeMm / envelopeMm
            print("\(name): f_d \(fmt(g.intrinsics.fx)) px, range \(fmt(rangeMm)) mm,"
                  + " smear \(fmt(4 * g.mmPerPx)) mm against ringInnerMm"
                  + " \(fmt(SupportRegion.ringInnerMm)) mm — envelope \(fmt(envelopeMm)) mm,"
                  + " corpus at \(fmt(usedFraction * 100)) % of it")

            #expect(rangeMm < envelopeMm)
            // Under 8 % of headroom, on both captures, on the flattest possible framing.
            // A session that shoots one plate from a little further back leaves the
            // envelope without anything in the record saying so — which is why the range
            // is now a thing `prerequisites.md` asks to be written down per capture.
            let roomier = "\(name) sits at \(usedFraction * 100) % of the envelope — the corpus"
                + " has more headroom than Decision 29 measured and the warning can relax"
            #expect(usedFraction > 0.9, "\(roomier)")
        }
    }

    // Decision 35 found the one constant that could not transfer: the extent bar was
    // denominated in PIXELS while every other bar in `admissibility` is a millimetre or
    // a dimensionless fraction, which is what Req 5.1's transfer rests on. It halved
    // with the grid and its verdict halved with it.
    //
    // Decision 37 re-denominated it, and this test now measures the repair rather than
    // the defect. Both quantities are taken across the same halving: the PIXEL extent
    // still halves — that was never in doubt and is a property of the component scan —
    // while the MILLIMETRE extent holds, because `mmPerPx` doubles by exactly the same
    // factor. The verdict follows the millimetres, so no surface changes its answer.
    @Test("the extent guard's verdict survives a grid halving once denominated in mm")
    func extentGuardTransfersAcrossAGridHalving() throws {
        var pairs = 0, flipped = 0
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let native = try #require(Self.gridFit(slice, decimation: 1))
            let halved = try #require(Self.gridFit(slice, decimation: 2))
            let ray = try #require(Self.foodCentroidRay(slice))

            for a in native.candidates {
                // Pair candidates across grids by where they cut the food centroid ray:
                // the same physical surface, found twice.
                let depthA = Self.planeDepthMm(normal: a.candidate.normal, d: a.candidate.d, ray: ray)
                guard let b = halved.candidates.min(by: {
                    abs(Self.planeDepthMm(normal: $0.candidate.normal, d: $0.candidate.d, ray: ray) - depthA)
                    < abs(Self.planeDepthMm(normal: $1.candidate.normal, d: $1.candidate.d, ray: ray) - depthA)
                }) else { continue }
                let depthB = Self.planeDepthMm(normal: b.candidate.normal, d: b.candidate.d, ray: ray)
                guard abs(depthA - depthB) <= Self.gridTransferToleranceMm else { continue }
                pairs += 1
                let driftMm = abs(a.candidate.extentMm - b.candidate.extentMm)
                print("\(name): surface at \(fmt(depthA)) mm — extent"
                      + " \(a.candidate.extentPx) px / \(fmt(a.candidate.extentMm)) mm native,"
                      + " \(b.candidate.extentPx) px / \(fmt(b.candidate.extentMm)) mm halved"
                      + " (drift \(fmt(driftMm)) mm), bar \(SupportRegion.minAcceptedExtentMm) mm")
                // The pixel extent is a count on the winning inlier component, so it
                // scales with the grid rather than with the surface. Unchanged by
                // Decision 37 — this is why the bar could not stay denominated in it.
                #expect(b.candidate.extentPx < a.candidate.extentPx)
                // The millimetre extent is the same physical span measured twice. One
                // depth pixel of the halved grid is ~3.7 mm, so the quantisation floor
                // is that, not zero.
                #expect(driftMm <= 2 * halved.mmPerPx)
                if (a.candidate.extentMm >= SupportRegion.minAcceptedExtentMm)
                    != (b.candidate.extentMm >= SupportRegion.minAcceptedExtentMm) {
                    flipped += 1
                }
            }
        }
        // The finding, inverted from Decision 35: no surface the guard admits natively
        // is rejected as a sliver at half resolution, and none is admitted that was not.
        #expect(pairs >= 2, "too few paired surfaces to conclude anything about transfer")
        let regressed = "\(flipped) of \(pairs) paired surfaces change their extent verdict"
            + " across the halving — the mm denomination of Decision 37 is not transferring"
        #expect(flipped == 0, "\(regressed)")

        // And the grid it did not transfer to is not hypothetical. The N5k corpus runs
        // the same fitter over RealSense frames whose depth is registered to the colour
        // grid — `tools/nutrition5k/ingest.py` pins f = 617 px against the device's
        // measured f_d — so at equal range the same physical sliver spans over three
        // times as many pixels there. A 24 px bar would have been stricter on the device
        // than on N5k by that ratio; 44 mm is the same bar on both, which is the point of
        // Decision 37 and why it did not wait for model-production Bucket C to be paid
        // for. Bucket C is when N5k fixtures first carry a food mask and reach this guard
        // at all, and the ratio below is what the pixel denomination would have cost then.
        let deviceFx = try #require(Self.geometry(Self.captures[0])).intrinsics.fx
        let ratio = Self.n5kPinnedFxPx / deviceFx
        print("extent denomination: device f_d \(fmt(deviceFx)) px against N5k's pinned"
              + " \(fmt(Self.n5kPinnedFxPx)) px — the same physical extent spans"
              + " \(fmt(ratio))x more pixels on the N5k grid")
        #expect(ratio > 3)
    }

    // `tools/nutrition5k/ingest.py`'s `PINNED_INTRINSICS`, RealSense D435 factory nominal
    // at 640x480. Depth is registered to the colour grid there, so this is f_d as well.
    static let n5kPinnedFxPx: Float = 617

    // MEASURED (Decision 35): the plane moves 0.835 mm on `1785135663727` and 0.037 mm
    // on `1785901032716` across a 2x grid halving. 1 mm is that rounded up — a bar the
    // corpus meets on both captures with the wider one at 84 % of it, not a round number
    // chosen for comfort. The named fixture Req 5.1 asks for is `1785135663727`, the
    // wider of the two and already the fixture named by Reqs 6.2 and 7.1.
    //
    // It bounds a REPLAY-side quantity. The device leg of Req 5.1 is task 27's, and
    // decimation models a coarser grid rather than a different sensor: it subsamples one
    // sensor's output, so it carries that sensor's smoothing with it.
    static let gridTransferToleranceMm: Float = 1

    // Depth grid decimated by `factor` in each axis: sample (factor·x, factor·y). No
    // interpolation — a subsample is what a coarser sensor grid gives, and an
    // interpolated one would smooth the very discontinuities the ring reads.
    static func decimated(_ slice: DepthSlice, by factor: Int) -> DepthSlice {
        guard factor > 1 else { return slice }
        let w = slice.depth.width, h = slice.depth.height
        let nw = w / factor, nh = h / factor
        let depths: [Float] = slice.depth.depthBytesMm.withUnsafeBytes { raw in
            let source = raw.bindMemory(to: Float.self)
            var out = [Float](repeating: 0, count: nw * nh)
            for y in 0..<nh {
                for x in 0..<nw { out[y * nw + x] = source[(y * factor) * w + x * factor] }
            }
            return out
        }
        var confidence = [UInt8](repeating: 255, count: nw * nh)
        let sourceConfidence = [UInt8](slice.depth.confidenceBytes)
        if sourceConfidence.count >= w * h {
            for y in 0..<nh {
                for x in 0..<nw {
                    confidence[y * nw + x] = sourceConfidence[(y * factor) * w + x * factor]
                }
            }
        }
        return DepthSlice(
            name: slice.name,
            depth: DepthMap(
                depthBytesMm: depths.withUnsafeBufferPointer { Data(buffer: $0) },
                confidenceBytes: Data(confidence),
                width: nw, height: nh, rowStrideBytes: nw * 4,
                depthIntrinsics: CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, distortion: [],
                                                  imageWidth: nw, imageHeight: nh),
                depthFromColour: .identity),
            colourIntrinsics: slice.colourIntrinsics,
            gravity: slice.gravity,
            // Left on the ORIGINAL grid: the mask arrives at colour resolution on both
            // paths, and `downsampleFoodMask` is what puts it on whatever depth grid
            // the sensor produced. Decimating it here would bypass the step under test.
            foodMask: slice.foodMask)
    }

    // The whole pass at one grid resolution: what the ring can support, and every
    // candidate that produced ring statistics there.
    struct GridFit {
        let widthPx: Int
        let mmPerPx: Float
        let bandCounts: [Int]
        let feasible: Bool
        let candidates: [(candidate: SupportRegion.PlaneCandidate, ring: RingStatistics)]

        // Highest inner-band support, as everywhere else in this pass: the candidate the
        // design intends to select, taken before admissibility.
        var best: (candidate: SupportRegion.PlaneCandidate, ring: RingStatistics)? {
            candidates.max { $0.ring.supportFraction < $1.ring.supportFraction }
        }
    }

    static func gridFit(_ slice: DepthSlice, decimation: Int) -> GridFit? {
        let scaled = decimated(slice, by: decimation)
        guard let g = SupportRegion.prepare(depth: scaled.depth,
                                            colourIntrinsics: scaled.colourIntrinsics,
                                            foodRegionMask: scaled.foodMask) else { return nil }
        let samples = SupportRegion.ringSamples(geometry: g)
        var counts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
        for band in samples.band { counts[band] += 1 }
        let feasible = SupportRegion.ringBandsAreFeasible(samples: samples)
        guard feasible else {
            return GridFit(widthPx: g.width, mmPerPx: g.mmPerPx, bandCounts: counts,
                           feasible: false, candidates: [])
        }
        var rng = SplitMix64(seed: Fnv1a64.hash(scaled.depth.depthBytesMm))
        let candidates = SupportRegion.extractCandidates(
            annulus: samples.annulus, geometry: g,
            gravity: scaled.gravity.normalised(), rng: &rng)
        return GridFit(
            widthPx: g.width, mmPerPx: g.mmPerPx, bandCounts: counts, feasible: true,
            candidates: candidates.compactMap { candidate in
                guard let ring = SupportRegion.ringStatistics(
                    samples: samples, geometry: g,
                    normal: candidate.normal, d: candidate.d) else { return nil }
                return (candidate, ring)
            })
    }

    // The unnormalised camera ray through the NATIVE grid's food-mask centroid, in the
    // convention `prepare` back-projects with (z negated). Taken once, from the native
    // grid, so both planes are compared at the same physical direction rather than each
    // at its own grid's centroid.
    static func foodCentroidRay(_ slice: DepthSlice) -> Vec3? {
        guard let g = SupportRegion.prepare(depth: slice.depth,
                                            colourIntrinsics: slice.colourIntrinsics,
                                            foodRegionMask: slice.foodMask) else { return nil }
        return Vec3((g.centroidX - g.intrinsics.cx) / g.intrinsics.fx,
                    (g.centroidY - g.intrinsics.cy) / g.intrinsics.fy,
                    -1)
    }

    // Where the plane cuts that ray, in millimetres of range. Volume is integrated
    // per-pixel above the plane, so a difference here is a difference added to every
    // food pixel — the units Req 5.1's tolerance has to be in to mean anything.
    static func planeDepthMm(normal: Vec3, d: Float, ray: Vec3) -> Float {
        let denominator = normal.dot(ray)
        return denominator == 0 ? .nan : d / denominator
    }

    static func angleDeg(_ a: Vec3, _ b: Vec3) -> Float {
        acos(SupportRegion.clampedCosine(a.normalised().dot(b.normalised()))) * 180 / .pi
    }

    // MARK: - Req 4.6: what the fallback costs

    // `Confidence.supportPlaneFallbackPenalty = 0.9` is the last `[owed]` figure no
    // derivation has touched, and it is not a bar a guard fires on — it is a price. Req
    // 4.6 asks only that the fallback report "no higher than a restricted fit of equal
    // residual", and every value in (0, 1) satisfies that, so compliance says nothing
    // about the number.
    //
    // The number's denomination comes from the curve it multiplies. `sigmaPlane` is
    // exp(−r/5) with r in millimetres, so a penalty p asserts that the fallback carries
    // −5·ln(p) mm of extra plane error, and 0.9 prices it at 0.53 mm. That is a
    // measurable quantity: it is the height the edge-band plane adds to a food pixel
    // against the plane the design intends to select.
    //
    // Not every capture can price it. The offset is only a fallback ERROR where the
    // candidate it is measured against is the raised support; where the best-support
    // candidate is the surrounding surface itself (Decision 30 measured that on
    // `1785901032716`), the same subtraction compares two fits of ONE surface and says
    // nothing about what falling back costs. The two are told apart by the sign Decision
    // 30 proposed the sector measure should carry: failing sectors read negative when the
    // candidate is the raised support and the ring escaped downward, positive when the
    // candidate is what the ring escaped ONTO.
    @Test("the corpus prices the fallback far above the shipped penalty, on the one capture that can")
    func fallbackPenaltyIsBoundedAboveByTheMeasuredPlaneError() throws {
        let shippedEquivalentMm = -5 * Foundation.log(Confidence.supportPlaneFallbackPenalty)
        var pricedByCapture: [(name: String, offsetMm: Float, implied: Float)] = []
        var sameSurface: [(name: String, offsetMm: Float)] = []

        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let (g, samples) = try #require(Self.prepared(name))
            let fallback = try #require(Self.fallbackPlane(slice))
            let intended = try #require(Self.bestCandidate(name))
            let ray = try #require(Self.foodCentroidRay(slice))

            let offsets = Self.foodOffsetsMm(
                fallback: fallback, intended: intended, geometry: g)
            let offsetMm = offsets.reduce(0, +) / Float(offsets.count)
            let sortedOffsets = offsets.sorted()
            let p10Mm = sortedOffsets[Int(0.10 * Float(sortedOffsets.count))]
            let p90Mm = sortedOffsets[min(sortedOffsets.count - 1,
                                          Int(0.90 * Float(sortedOffsets.count)))]
            let implied = Foundation.exp(-offsetMm / 5)
            let rayOffsetMm = Self.planeDepthMm(
                normal: fallback.normal, d: fallback.distanceMm, ray: ray)
                - Self.planeDepthMm(normal: intended.normal, d: intended.d, ray: ray)

            // What the two paths report for the same capture, penalty included.
            let sigmaFallback = Foundation.exp(-fallback.residualMm / 5)
                * Confidence.supportPlaneFallbackPenalty
            let sigmaIntended = Foundation.exp(-intended.residualMm / 5)

            // Decision 30's sign, used as an analysis tool rather than a guard: the median
            // signed inner-band height of the sectors that fail `sectorSupportMin`.
            let fractions = Self.sectorFractions(
                samples: samples, geometry: g, normal: intended.normal, d: intended.d)
            let medians = Self.sectorMedianMm(
                samples: samples, geometry: g, normal: intended.normal, d: intended.d)
            let failing = zip(fractions, medians)
                .filter { $0.0.total > 0 && $0.0.fraction < SupportRegion.sectorSupportMin }
                .map(\.1).sorted()
            let failingMedianMm = try #require(failing.isEmpty ? nil : failing[failing.count / 2])
            let isRaisedSupport = failingMedianMm < 0

            let tiltDeg = Self.angleDeg(fallback.normal, intended.normal)

            print("\(name): fallback adds \(fmt(offsetMm)) mm to the mean food pixel"
                  + " (p10 \(fmt(p10Mm)), p90 \(fmt(p90Mm)), tilt \(fmt(tiltDeg))°,"
                  + " centroid ray \(fmt(rayOffsetMm)) mm);"
                  + " failing-sector median \(fmt(failingMedianMm)) mm ->"
                  + " \(isRaisedSupport ? "raised support" : "surrounding surface");"
                  + " residuals \(fmt(fallback.residualMm)) vs \(fmt(intended.residualMm)) mm;"
                  + " sigmaPlane \(fmt(sigmaFallback)) vs \(fmt(sigmaIntended));"
                  + " implied penalty \(fmt(implied)) against shipped"
                  + " \(fmt(Confidence.supportPlaneFallbackPenalty))"
                  + " (\(fmt(shippedEquivalentMm)) mm)")

            // The edge-band plane lies below the best candidate across the food, not merely
            // on average — p10 is the assertion, so a tilt that put a tenth of the food on
            // the other side would fail here rather than average away.
            let reversed = "\(name) fallback plane sits nearer the camera than the best"
                + " candidate over part of the food (p10 \(p10Mm) mm) — Req 3.3's premise"
                + " fails on the fallback side"
            #expect(p10Mm > 0, "\(reversed)")

            // The residual channel does not carry the error; it works the other way. The
            // edge-band plane is a GOOD fit to the wrong surface, so its residual is
            // lower than the restricted fit's, and exp(−r/5) rewards it for that. This is
            // why Decision 12 made the penalty a separate factor — and it means the
            // penalty must first cancel a residual advantage before it prices anything.
            let advantageMm = intended.residualMm - fallback.residualMm
            let carried = "\(name) fallback residual \(fallback.residualMm) mm now exceeds"
                + " the restricted fit's \(intended.residualMm) mm — the residual channel"
                + " has started carrying part of the fallback's error"
            #expect(advantageMm >= 0, "\(carried)")
            let spent = "\(name) residual advantage \(advantageMm) mm is now under half the"
                + " \(shippedEquivalentMm) mm the penalty prices — the penalty is no longer"
                + " mostly spent cancelling it"
            #expect(advantageMm > shippedEquivalentMm / 2, "\(spent)")
            // Req 4.6's practical form does hold, and by very little: the fallback reports
            // lower confidence than the restricted fit on the SAME capture, by 3 %.
            #expect(sigmaFallback < sigmaIntended,
                    "\(name) fallback reports \(sigmaFallback) against \(sigmaIntended)")
            #expect(sigmaFallback / sigmaIntended > 0.95,
                    "\(name) net confidence reduction is \(1 - sigmaFallback / sigmaIntended)")

            if isRaisedSupport {
                pricedByCapture.append((name, offsetMm, implied))
            } else {
                sameSurface.append((name, offsetMm))
            }
        }

        // The corpus's shape, asserted so a capture that changes it is noticed: one
        // capture whose best candidate is the plate top and can price the fallback, one
        // whose best candidate is the table and cannot.
        let shape = "the corpus no longer splits one raised-support capture against one"
            + " surrounding-surface capture (\(pricedByCapture.count) and"
            + " \(sameSurface.count)) — the ceiling below rests on a different sample"
        #expect(pricedByCapture.count == 1 && sameSurface.count == 1, "\(shape)")

        // What the capture that cannot price it does say: two independent fitters, one
        // colour-grid and one depth-grid, land within `ringBandMm` of each other on the
        // same surface. That is a Req 4.3 agreement figure, not a fallback cost.
        for entry in sameSurface {
            let apart = "\(entry.name) best candidate and edge-band plane are"
                + " \(entry.offsetMm) mm apart on what the sign says is one surface —"
                + " further than ringBandMm, so they are no longer the same surface"
            #expect(entry.offsetMm < SupportRegion.ringBandMm, "\(apart)")
        }

        // The finding. On the one capture that can price it, the fallback carries an
        // order of magnitude more plane error than the shipped penalty charges for.
        let priced = try #require(pricedByCapture.first)
        print("corpus ceiling on supportPlaneFallbackPenalty \(fmt(priced.implied)) from"
              + " \(priced.name)'s \(fmt(priced.offsetMm)) mm, shipped"
              + " \(fmt(Confidence.supportPlaneFallbackPenalty)) (\(fmt(shippedEquivalentMm)) mm),"
              + " over-report \(fmt(Confidence.supportPlaneFallbackPenalty / priced.implied))x")
        let inside = "the shipped penalty \(Confidence.supportPlaneFallbackPenalty) now sits"
            + " inside the measured ceiling \(priced.implied) — the over-report is closed"
            + " and the constant can be set rather than bounded"
        #expect(Confidence.supportPlaneFallbackPenalty > priced.implied, "\(inside)")
        #expect(Confidence.supportPlaneFallbackPenalty / priced.implied > 5)
    }

    // The obvious substitute for a constant, measured and rejected before anyone builds
    // it. The fallback path already persists a ring measure (Req 6.1, task 12), so a
    // penalty priced per capture from it looks free — read the ring median, charge for it.
    //
    // It does not track the quantity it would have to. The ring sits 8–25 mm out from the
    // food and Decision 33 measured the plate ending inside it in five of eight
    // directions, so the median averages support and surroundings rather than reading
    // either. On the corpus it lands 4.3x LOW where the offset is real and 2.4x HIGH where
    // the two planes are the same surface — wrong in both directions, which is worse than
    // wrong in one, because no single scale factor repairs it.
    @Test("the fallback's persisted ring median does not track its offset at the food")
    func fallbackRingMedianDoesNotTrackTheOffsetAtTheFood() throws {
        var ratios: [Float] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let fallback = try #require(Self.fallbackPlane(slice))
            let intended = try #require(Self.bestCandidate(name))
            let ring = try #require(SupportRegion.ringStatistics(
                for: fallback, depth: slice.depth,
                foodMask: slice.foodMask, intrinsics: slice.colourIntrinsics))

            let offsets = Self.foodOffsetsMm(
                fallback: fallback, intended: intended, geometry: g)
            let offsetMm = offsets.reduce(0, +) / Float(offsets.count)
            print("\(name): fallback ring median \(fmt(ring.medianMm)) mm against an offset"
                  + " at the food of \(fmt(offsetMm)) mm"
                  + " — ratio \(fmt(ring.medianMm / offsetMm))")

            // The sign is right on both — the ring lies above the fallback plane, which is
            // the Req 3.1 signature of a plane on the surrounding surface. It is the size
            // that does not carry.
            #expect(ring.medianMm > 0, "\(name) fallback ring median \(ring.medianMm) mm")
            ratios.append(ring.medianMm / offsetMm)
        }

        let low = try #require(ratios.min()), high = try #require(ratios.max())
        print("fallback ring median / offset at the food spans \(fmt(low))…\(fmt(high))")
        let tracks = "the fallback ring median now tracks the offset at the food across the"
            + " corpus (\(low)…\(high)) — the persisted measure may price the fallback per"
            + " capture after all, and Decision 36's rejection of it should be rechecked"
        #expect(low < 0.5 && high > 2, "\(tracks)")
    }

    // The height the edge-band plane adds to each food pixel against the plane the design
    // intends to select — per sample, because the two planes are up to 7° apart and a
    // single ray would stand for nothing. Volume is integrated per-pixel above the plane,
    // so this is the quantity the fallback's error is denominated in, and its mean is what
    // the confidence curve's millimetres refer to. (Req 5.1's tolerance can use one ray,
    // Decision 35, because there the two fits are of the SAME surface.)
    static func foodOffsetsMm(fallback: SupportPlane,
                              intended: SupportRegion.PlaneCandidate,
                              geometry g: SupportRegion.DepthGeometry) -> [Float] {
        g.foodIndices.map { index in
            let p = g.points[index]
            return (fallback.normal.dot(p) - fallback.distanceMm)
                - (intended.normal.dot(p) - intended.d)
        }
    }

    // The edge-band plane — what Req 4.3 says the fallback returns unmodified. It runs
    // over the colour grid rather than the depth one, so it is the expensive half of this
    // pass; only the Req 4.6 derivation needs it.
    static func fallbackPlane(_ slice: DepthSlice) -> SupportPlane? {
        LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
            depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
            foodRegionMask: slice.colourFoodMask, gravityCamera: slice.gravity)).plane
    }

    // MARK: - What the committed suite leaves the session room to set

    // `prerequisites.md` still carries one open item that is NOT a hardware gate — "set the
    // guard constants before task 8 hard-codes them", flagged because task 8 bakes every
    // threshold into code and tests before anything measures it. Task 8 shipped, so the
    // question is no longer whether to reorder: it is how much room the committed tests
    // leave the capture session.
    //
    // Every test reference to an `[owed]` constant is SYMBOLIC — `SupportRegion.ringSupportMin`,
    // never a literal — but symbolic is not the same as insulated. Two shapes hide behind it.
    // A test that expresses its INPUT in terms of the constant (`extentMm: minAcceptedExtentMm - 1`)
    // tracks it wherever it goes. A test that fixes a synthetic scene and asserts the scene's
    // MEASURED value against the constant flips as soon as the constant crosses that value,
    // and the scene is what pins it. `SupportRegionSelectionTests` says as much in prose —
    // "the window in which the aggregate passes and the sectors fail is therefore narrow, and
    // this scene sits inside it by construction" — without measuring how narrow.
    //
    // This measures it: per constant, the interval over which every committed assertion keeps
    // its verdict, against the bracket Decisions 29-40 measured on the corpus.
    struct SceneReading {
        let label: String
        // Which guards this scene's COMMITTED assertions require to pass, and which to
        // fire. Not "which guards the scene happens to satisfy": the bowl fails almost
        // every guard, but the only assertion made about it is on the inner→mid step, so
        // it bounds `bandStepMaxMm` and nothing else. A scene bounds a constant only where
        // a committed test would change verdict.
        let requiresPass: [SupportRegion.CandidateRejection]
        let requiresFire: [SupportRegion.CandidateRejection]
        let supportFraction: Float
        let supportingSectors: Int
        let bandStepMm: Float
        let visibility: Float
        let envelopeMm: Float
        let annulusMedianMm: Float
        // The same ring read the way Decision 40's rule reads it. Carried here so the
        // suite can be measured against the REPLACEMENT sector guard on exactly the
        // scenes it is measured against the shipped one.
        let signs: SectorSigns
        // The ring and the plane the reading was taken at, kept so the scene can be
        // re-sectored at a count other than the shipped one without rebuilding it.
        let samples: SupportRegion.RingSamples
        let geometry: SupportRegion.DepthGeometry
        let normal: Vec3
        let planeD: Float

        func signs(at count: Int,
                   supportMin: Float = SupportRegion.sectorSupportMin,
                   bandMm: Float = SupportRegion.ringBandMm) -> SectorSigns {
            SupportPlaneCorpusMeasurementTests.sectorSigns(
                samples: samples, geometry: geometry, normal: normal, d: planeD,
                count: count, supportMin: supportMin, bandMm: bandMm)
        }

        // The inner-band support share at a band other than the shipped one. The scene's
        // own plane and ring, so only the tolerance moves.
        func supportFraction(bandMm: Float) -> Float {
            SupportPlaneCorpusMeasurementTests.innerSupportFraction(
                samples: samples, geometry: geometry, normal: normal, d: planeD,
                bandMm: bandMm)
        }

        // `|bandMedianMm[0]|`, the quantity `ringMedianMaxMm` is compared against. Band
        // medians do not move with the tolerance — only the bar they are read against
        // does — so this is taken once and re-read at every band.
        var innerBandMedianMm: Float {
            SupportPlaneCorpusMeasurementTests.bandMediansMm(
                samples: samples, geometry: geometry, normal: normal, d: planeD,
                bandCount: SupportRegion.ringBandCount)[0]
        }
    }

    // Every guard, for the four scenes whose committed test requires the whole fit to
    // succeed — passing one guard is not enough when the assertion is `#require(fit)`.
    static let everyGuard: [SupportRegion.CandidateRejection] = [
        .supportFraction, .sectors, .foodEnvelope, .bandStep, .visibility, .escaped,
    ]

    // A committed scene as the suite states it: the grid, the plane its own test
    // evaluates at, and which guards that test requires to pass and to fire. Held apart
    // from `SceneReading` because a reading is taken at ONE ring geometry and the
    // sweeps re-take it at others.
    struct SceneSpec {
        let label: String
        let grid: SPRScene.Grid
        let planeHeightMm: Float
        let requiresPass: [SupportRegion.CandidateRejection]
        let requiresFire: [SupportRegion.CandidateRejection]
    }

    // The eight scenes the committed suites assert on, each at the plane its own test
    // evaluates. Changing a scene changes these bounds, which is the point: they are
    // properties of the committed tests, not of the geometry.
    static func sceneSpecs() -> [SceneSpec] {
        let all = everyGuard
        let scenes: [(String, SPRScene.Grid, Float,
                      [SupportRegion.CandidateRejection], [SupportRegion.CandidateRejection])] = [
            // `#require(SPRScene.fit(...))` — every guard must pass.
            ("plate above table", SPRScene.plateAboveTable(), 20, all, []),
            ("flat surface", SPRScene.plateAboveTable(plateHeightMm: 0), 0, all, []),
            ("rim in the outer band", SPRScene.rimmedPlate(rimStartPx: 24), 20, all, []),
            ("overhanging food", SPRScene.overhangingFood(lobeHalfAngleDeg: 8), 20, all, []),
            // The silent-failure case: every guard asserted healthy one by one, then the
            // verdict pinned to `.sectors`.
            ("food across the plate edge", SPRScene.foodAcrossPlateEdge(edgeOffsetPx: -10), 0,
             all.filter { $0 != .sectors }, [.sectors]),
            // `admissibility(...) == .bandStep` with the guards BEFORE bandStep in the
            // shipped order required to pass. `annulusMedianMm` and `foodEnvelopeMm` are
            // passed as literals there, and `visibility`/`escaped` come after, so this
            // scene bounds neither.
            ("rim in the mid band", SPRScene.rimmedPlate(rimStartPx: 19), 20,
             [.supportFraction, .sectors], [.bandStep]),
            // One assertion only: the step exceeds the bar.
            ("bowl", SPRScene.bowl(), 20, [], [.bandStep]),
            // One assertion only: the envelope is below the floor.
            ("fully covered well", SPRScene.rimmedPlate(foodRadiusPx: 20, rimStartPx: 20), 35,
             [], [.foodEnvelope]),
        ]
        return scenes.map {
            SceneSpec(label: $0.0, grid: $0.1, planeHeightMm: $0.2,
                      requiresPass: $0.3, requiresFire: $0.4)
        }
    }

    static func sceneReadings() -> [SceneReading] {
        return sceneSpecs().compactMap { spec in
            let (label, grid) = (spec.label, spec.grid)
            let (requiresPass, requiresFire) = (spec.requiresPass, spec.requiresFire)
            guard let measured = SPRScene.measure(grid) else { return nil }
            let p = SPRScene.plane(atHeightMm: spec.planeHeightMm)
            guard let ring = SupportRegion.ringStatistics(
                samples: measured.samples, geometry: measured.geometry,
                normal: p.normal, d: p.d) else { return nil }
            return SceneReading(
                label: label, requiresPass: requiresPass, requiresFire: requiresFire,
                supportFraction: ring.supportFraction,
                supportingSectors: ring.supportingSectors,
                bandStepMm: ring.bandMedianMm[1] - ring.bandMedianMm[0],
                visibility: ring.supportVisibility,
                envelopeMm: SupportRegion.foodEnvelopeMm(
                    geometry: measured.geometry, normal: p.normal, d: p.d),
                annulusMedianMm: SupportRegion.medianHeight(
                    indices: measured.samples.annulus, geometry: measured.geometry,
                    normal: p.normal, d: p.d),
                signs: sectorSigns(samples: measured.samples, geometry: measured.geometry,
                                   normal: p.normal, d: p.d),
                samples: measured.samples, geometry: measured.geometry,
                normal: p.normal, planeD: p.d)
        }
    }

    @Test("the committed scenes bound six owed constants, and the sector floor is the tight one")
    func committedScenesBoundTheOwedConstants() throws {
        let readings = Self.sceneReadings()
        #expect(readings.count == 8, "a scene stopped producing ring statistics")
        // A guard's bound comes from the scenes whose committed assertions require it to
        // pass, and from those that require it to fire — in opposite directions.
        func passing(_ guardKind: SupportRegion.CandidateRejection) -> [SceneReading] {
            readings.filter { $0.requiresPass.contains(guardKind) }
        }
        func firing(_ guardKind: SupportRegion.CandidateRejection) -> [SceneReading] {
            readings.filter { $0.requiresFire.contains(guardKind) }
        }

        for r in readings {
            print("\(r.label): fraction \(fmt(r.supportFraction)), sectors \(r.supportingSectors),"
                  + " inner→mid \(fmt(r.bandStepMm)) mm, visibility \(fmt(r.visibility)),"
                  + " envelope \(fmt(r.envelopeMm)) mm, annulus \(fmt(r.annulusMedianMm)) mm"
                  + " [pass \(r.requiresPass.map(\.rawValue).joined(separator: "/"))"
                  + " fire \(r.requiresFire.map(\.rawValue).joined(separator: "/"))]")
        }

        // Ceilings: raise the bar past the smallest value a scene that must pass produces,
        // and that scene starts failing.
        let supportCeiling = passing(.supportFraction).map(\.supportFraction).min() ?? 0
        let visibilityCeiling = passing(.visibility).map(\.visibility).min() ?? 0
        let envelopeCeiling = passing(.foodEnvelope).map(\.envelopeMm).min() ?? 0
        let sectorCeiling = passing(.sectors).map(\.supportingSectors).min() ?? 0
        // Floors: the opposite direction, from the scenes each guard exists to reject.
        let sectorFloor = (firing(.sectors).map(\.supportingSectors).max() ?? 0) + 1
        let envelopeFloor = firing(.foodEnvelope).map(\.envelopeMm).max() ?? 0
        // `bandStepMaxMm` and `escapeBandMm` read the other way round — a value BELOW the
        // bar passes — so their passing scenes floor them and their firing scenes cap them.
        let stepFloor = passing(.bandStep).map(\.bandStepMm).max() ?? 0
        let stepCeiling = firing(.bandStep).map(\.bandStepMm).min() ?? 0
        let escapeFloor = passing(.escaped).map(\.annulusMedianMm).max() ?? 0

        print("suite intervals: ringSupportMin ≤ \(fmt(supportCeiling)),"
              + " minSupportingSectors \(sectorFloor)…\(sectorCeiling),"
              + " bandStepMaxMm \(fmt(stepFloor))…\(fmt(stepCeiling)) mm,"
              + " supportVisibilityMin ≤ \(fmt(visibilityCeiling)),"
              + " foodEnvelopeMinMm \(fmt(envelopeFloor))…\(fmt(envelopeCeiling)) mm,"
              + " escapeBandMm ≥ \(fmt(escapeFloor)) mm")

        // Every shipped value sits inside its own interval, or the suite would be red today.
        #expect(SupportRegion.ringSupportMin <= supportCeiling)
        #expect(SupportRegion.supportVisibilityMin <= visibilityCeiling)
        #expect(SupportRegion.foodEnvelopeMinMm > envelopeFloor)
        #expect(SupportRegion.foodEnvelopeMinMm <= envelopeCeiling)
        #expect(SupportRegion.bandStepMaxMm >= stepFloor)
        #expect(SupportRegion.bandStepMaxMm < stepCeiling)
        #expect(SupportRegion.escapeBandMm >= escapeFloor)
        #expect(SupportRegion.minSupportingSectors >= sectorFloor)
        #expect(SupportRegion.minSupportingSectors <= sectorCeiling)

        // Now the same three constants against what the CORPUS says, computed the way the
        // sibling derivations compute them rather than quoted from them.
        var corpusIntendedSectors = Int.max
        var corpusEnvelopeCeiling = Float.greatestFiniteMagnitude
        var corpusHighestAnnulus = -Float.greatestFiniteMagnitude
        for name in Self.captures {
            let measurements = try #require(Self.measurements(name))
            let best = try #require(Self.bestCandidate(name))
            let intended = try #require(measurements.first { $0.candidate.d == best.d })
            corpusIntendedSectors = min(corpusIntendedSectors, intended.ring.supportingSectors)
            corpusEnvelopeCeiling = min(corpusEnvelopeCeiling, intended.envelopeMm)
            corpusHighestAnnulus = max(corpusHighestAnnulus,
                                       measurements.map(\.annulusMedianMm).max() ?? corpusHighestAnnulus)
        }
        print("corpus: minSupportingSectors ≤ \(corpusIntendedSectors),"
              + " foodEnvelopeMinMm ≤ \(fmt(corpusEnvelopeCeiling)) mm,"
              + " escapeBandMm reached \(fmt(corpusHighestAnnulus)) mm")

        // On two constants the SUITE is the binding constraint, not the corpus — so a
        // session setting them against captures alone would land inside the corpus's
        // bracket and outside the suite's.
        let envelopeTighter = "the corpus now bounds foodEnvelopeMinMm below the suite"
            + " (\(fmt(corpusEnvelopeCeiling)) vs \(fmt(envelopeCeiling)) mm) — the scenes"
            + " have stopped being the binding constraint on it"
        #expect(envelopeCeiling < corpusEnvelopeCeiling, "\(envelopeTighter)")
        let escapeTighter = "the corpus now reaches an annulus median above the suite's"
            + " floor on escapeBandMm (\(fmt(corpusHighestAnnulus)) vs \(fmt(escapeFloor)) mm)"
        #expect(escapeFloor > corpusHighestAnnulus, "\(escapeTighter)")

        // And on one they CONTRADICT. Decision 33 measured that the plate ends inside the
        // ring in five of eight directions on both captures, so a real intended candidate
        // scores 5 of 8 and `minSupportingSectors` has to come down to admit it. The suite's
        // floor is 6, because the silent-failure scene it must reject scores 5 as well. The
        // session cannot satisfy both: the scene has to move with the constant, and this
        // assertion is what says so until it does.
        print("collision: suite floor \(sectorFloor) > corpus ceiling \(corpusIntendedSectors),"
              + " shipped \(SupportRegion.minSupportingSectors)")
        let resolved = "the suite's floor on minSupportingSectors (\(sectorFloor)) no longer"
            + " exceeds what the corpus's intended candidate scores (\(corpusIntendedSectors)):"
            + " the collision this test records is resolved and it can be retired"
        #expect(sectorFloor > corpusIntendedSectors, "\(resolved)")
    }

    // MARK: - The replacement sector guard against both constraint sets

    // Decision 41 left one thing unresolved and named it: the suite and the corpus
    // CONTRADICT on `minSupportingSectors` — floor 6 against ceiling 5 — so "the scene
    // has to move with the constant", a dependency Decision 40 did not anticipate.
    // Decision 42 then measured that the only thing holding the wrong plane out of a
    // 0 % fallback rate is `ringMedianMaxMm` clearing it by 0.338 mm, and called that an
    // argument for the crossed-sector rule "that does not need capture 6".
    //
    // Both point at the same question and neither asks it: does the REPLACEMENT guard
    // have the collision too? The contradiction is a property of the unsigned count, not
    // of the scenes, and the scenes are unchanged — so the rule can be measured against
    // exactly the two constraint sets that broke the count, on the same eight scenes and
    // the same six corpus candidates, before capture 6 exists.
    //
    // `maxCrossedSectors` is bracketed 0…2 by the corpus (Decision 40). This asks what
    // the committed suite brackets it to, whether the two intervals intersect where the
    // count's did not, and whether anything in hand distinguishes the values inside.
    @Test("the crossed-sector rule is bracketed by the suite too, and the two agree")
    func crossedSectorRuleIsBracketedByBothConstraintSets() throws {
        let readings = Self.sceneReadings()
        #expect(readings.count == 8, "a scene stopped producing ring statistics")

        for r in readings {
            print("\(r.label): supporting \(r.signs.supporting)/\(SupportRegion.ringSectorCount),"
                  + " failing \(r.signs.failing.count)"
                  + " \(r.signs.failingMedians.map { fmt($0) }),"
                  + " crossed \(r.signs.crossedFailing), escaped \(r.signs.escapedFailing)")
        }

        // The scenes whose committed assertions run through the sector guard. Every
        // other scene bounds this constant no more than it bounds the shipped count.
        let mustPass = readings.filter { $0.requiresPass.contains(.sectors) }
        let mustFire = readings.filter { $0.requiresFire.contains(.sectors) }
        #expect(mustPass.count == 5, "the set of scenes requiring the sector guard to pass moved")
        #expect(mustFire.count == 1, "the set of scenes requiring the sector guard to fire moved")

        // A ceiling on crossed sectors reads the opposite way round to a floor on
        // supporting ones: a scene that must be ADMITTED floors the ceiling, and the
        // scene the guard exists to REJECT caps it one below its own count.
        let suiteFloor = mustPass.map(\.signs.crossedFailing).max() ?? 0
        let suiteCeiling = (mustFire.map(\.signs.crossedFailing).min() ?? 0) - 1
        print("suite brackets maxCrossedSectors \(suiteFloor)…\(suiteCeiling)")

        // The corpus side, recomputed rather than quoted from Decision 40 — the two
        // constraint sets have to be comparable on one run.
        var byCapture: [String: SectorSigns] = [:]
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            let best = try #require(Self.bestCandidate(name))
            byCapture[name] = Self.sectorSigns(
                samples: samples, geometry: g, normal: best.normal, d: best.d)
        }
        // `1785135663727` selects its plate top — the plane a correct fit must ADMIT.
        // `1785901032716` selects the TABLE — Decision 18's silent failure, and the
        // plane the guard exists to reject.
        let plate = try #require(byCapture["1785135663727"])
        let table = try #require(byCapture["1785901032716"])
        let corpusFloor = plate.crossedFailing
        let corpusCeiling = table.crossedFailing - 1
        print("corpus brackets maxCrossedSectors \(corpusFloor)…\(corpusCeiling)")

        // THE FINDING. On the shipped count the two sets have no common value; on the
        // rule that replaces it they do, and no scene had to move to get it.
        let jointFloor = max(suiteFloor, corpusFloor)
        let jointCeiling = min(suiteCeiling, corpusCeiling)
        print("joint interval \(jointFloor)…\(jointCeiling)"
              + " (\(max(0, jointCeiling - jointFloor + 1)) admissible values)")
        let collided = "the suite and the corpus now contradict on maxCrossedSectors as"
            + " well (\(suiteFloor)…\(suiteCeiling) against \(corpusFloor)…\(corpusCeiling)) —"
            + " the crossed-sector rule inherits Decision 41's collision and a committed"
            + " scene has to move after all"
        #expect(jointFloor <= jointCeiling, "\(collided)")

        // Same two sources, same eight scenes, the OTHER formulation of the same guard:
        // the unsigned count's joint interval is empty. This is the comparison, and it
        // is the whole reason the rule is worth having before capture 6.
        let countFloor = (mustFire.map(\.supportingSectors).max() ?? 0) + 1
        let countCeiling = min(mustPass.map(\.supportingSectors).min() ?? 0,
                               plate.supporting)
        print("for comparison, minSupportingSectors joint interval"
              + " \(countFloor)…\(countCeiling) — empty")
        let countFeasible = "the unsigned sector count now has a feasible joint interval"
            + " (\(countFloor)…\(countCeiling)) — Decision 41's collision has resolved by"
            + " some other route and this comparison no longer says anything"
        #expect(countFloor > countCeiling, "\(countFeasible)")

        // And nothing in hand distinguishes the values inside the joint interval: every
        // committed scene and every corpus candidate returns the same verdict at each of
        // them. So the interval is not narrowable by more measurement of what exists —
        // it is owed to capture 6 in the strict sense, and the rule's verdicts today do
        // not depend on which value is eventually chosen.
        for value in jointFloor...jointCeiling {
            for r in mustPass {
                #expect(r.signs.crossedFailing <= value,
                        "\(r.label) is rejected by the crossed rule at maxCrossedSectors \(value)")
            }
            for r in mustFire {
                #expect(r.signs.crossedFailing > value,
                        "\(r.label) is admitted by the crossed rule at maxCrossedSectors \(value)")
            }
            #expect(plate.crossedFailing <= value,
                    "1785135663727's plate top is rejected at maxCrossedSectors \(value)")
            #expect(table.crossedFailing > value,
                    "1785901032716's table plane is admitted at maxCrossedSectors \(value)")
        }
        let indistinguishable = "the joint interval has collapsed to one value —"
            + " maxCrossedSectors would be measured rather than owed"
        #expect(jointCeiling > jointFloor, "\(indistinguishable)")

        // The margin the rule replaces. Decision 42 measured `ringMedianMaxMm` clearing
        // the table candidate by 0.338 mm on a 5 mm bar; the rule clears it by whole
        // sectors, and by the SAME distance at every value in the joint interval.
        print("the table candidate is rejected by \(table.crossedFailing) crossed sectors"
              + " against a ceiling of at most \(jointCeiling) — margin"
              + " \(table.crossedFailing - jointCeiling) sectors, where ringMedianMaxMm's"
              + " margin on the same candidate is 0.338 mm on a"
              + " \(SupportRegion.ringMedianMaxMm) mm bar")
    }

    // MARK: - The sector count, and what it is the unit of

    // Every bracket this feature has recorded for the sector measure — Decision 40's
    // 0…2 on `maxCrossedSectors`, Decision 41's 6…7 and Decision 43's empty 6…5 on
    // `minSupportingSectors` — is a COUNT OF SECTORS, read at `ringSectorCount = 8`. So
    // is `ringMinSamples`, whose whole derivation is `ringSectorCount × 25`. The three
    // sector constants have been treated as peers of one another and of the count; they
    // are not. The count is the unit the other three are denominated in, and Req 3.7
    // leaves it `[owed]` alongside them.
    //
    // What that means for the capture session is the question here, and it is answerable
    // without a capture: re-cut the same rings into N equal arcs and read what moves.
    // 10 and 11 are in the sweep so the ceiling below is exercised rather than
    // interpolated — 11 is the last count the Req 5.1 grid halving supports.
    static let sectorCountSweep = [4, 6, 8, 10, 11, 12, 16, 24, 32]

    // The derivation `ringMinSamples` carries: 25 inner-band samples per sector, so a
    // 0.5 support bar has binomial σ ≈ 0.10 (Decision 20). Applied per RADIAL band.
    static let samplesPerSectorTarget = 25

    @Test("the sector count is the unit the other three sector constants are denominated in")
    func sectorCountIsTheUnitOfTheSectorTrio() throws {
        // The two corpus candidates Decisions 40 and 43 are read from: the plate top a
        // correct fit must admit, and the table plane the guard exists to reject.
        var rings: [String: (SupportRegion.DepthGeometry, SupportRegion.RingSamples,
                             SupportRegion.PlaneCandidate)] = [:]
        var nativeBandCounts: [String: [Int]] = [:]
        var halvedBandCounts: [String: [Int]] = [:]
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            rings[name] = (g, samples, try #require(Self.bestCandidate(name)))
            var counts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
            for band in samples.band { counts[band] += 1 }
            nativeBandCounts[name] = counts
            let slice = try DepthSlice.load(name)
            halvedBandCounts[name] = try #require(Self.gridFit(slice, decimation: 2)).bandCounts
        }
        let readings = Self.sceneReadings()
        #expect(readings.count == 8, "a scene stopped producing ring statistics")
        let mustPass = readings.filter { $0.requiresPass.contains(.sectors) }
        let mustFire = readings.filter { $0.requiresFire.contains(.sectors) }

        struct Sweep {
            let count: Int
            let plate: SectorSigns
            let table: SectorSigns
            let corpusFloor: Int
            let corpusCeiling: Int
            let suiteFloor: Int
            let suiteCeiling: Int
            var jointFloor: Int { max(corpusFloor, suiteFloor) }
            var jointCeiling: Int { min(corpusCeiling, suiteCeiling) }
            var jointFeasible: Bool { jointFloor <= jointCeiling }
            let minSectorSamples: Int
            let occupied: [Int]
            // `ringMinSamples` at this count, and whether the corpus's radial bands
            // clear it — natively, and across the Req 5.1 grid halving.
            let impliedRingMinSamples: Int
            let nativeFeasible: Bool
            let halvedFeasible: Bool
        }

        var sweeps: [Sweep] = []
        for count in Self.sectorCountSweep {
            var signs: [String: SectorSigns] = [:]
            for (name, r) in rings {
                signs[name] = Self.sectorSigns(samples: r.1, geometry: r.0,
                                               normal: r.2.normal, d: r.2.d, count: count)
            }
            let plate = try #require(signs["1785135663727"])
            let table = try #require(signs["1785901032716"])
            let passCrossed = mustPass.map { $0.signs(at: count).crossedFailing }
            let fireCrossed = mustFire.map { $0.signs(at: count).crossedFailing }
            let implied = count * Self.samplesPerSectorTarget
            sweeps.append(Sweep(
                count: count, plate: plate, table: table,
                corpusFloor: plate.crossedFailing,
                corpusCeiling: table.crossedFailing - 1,
                suiteFloor: passCrossed.max() ?? 0,
                suiteCeiling: (fireCrossed.min() ?? 0) - 1,
                minSectorSamples: [plate, table]
                    .flatMap(\.sectorSampleCounts).filter { $0 > 0 }.min() ?? 0,
                occupied: [plate, table].map { $0.sectorSampleCounts.filter { $0 > 0 }.count },
                impliedRingMinSamples: implied,
                nativeFeasible: nativeBandCounts.values.allSatisfy {
                    $0.allSatisfy { $0 >= implied }
                },
                halvedFeasible: halvedBandCounts.values.allSatisfy {
                    $0.allSatisfy { $0 >= implied }
                }))
        }

        for s in sweeps {
            print("N=\(s.count): occupied \(s.occupied), min sector samples \(s.minSectorSamples)"
                  + " (target \(Self.samplesPerSectorTarget));"
                  + " plate supporting \(s.plate.supporting) crossed \(s.plate.crossedFailing),"
                  + " table supporting \(s.table.supporting) crossed \(s.table.crossedFailing);"
                  + " maxCrossedSectors corpus \(s.corpusFloor)…\(s.corpusCeiling),"
                  + " suite \(s.suiteFloor)…\(s.suiteCeiling),"
                  + " joint \(s.jointFloor)…\(s.jointCeiling)"
                  + " (\(max(0, s.jointCeiling - s.jointFloor + 1)) values);"
                  + " ringMinSamples \(s.impliedRingMinSamples)"
                  + " native \(s.nativeFeasible ? "feasible" : "REFUSED")"
                  + " halved \(s.halvedFeasible ? "feasible" : "REFUSED")")
        }
        print("native band counts \(nativeBandCounts), halved \(halvedBandCounts)")

        let shipped = try #require(sweeps.first { $0.count == SupportRegion.ringSectorCount })

        // Anchor. At the shipped count this reproduces Decisions 40 and 43 exactly — if
        // it does not, the re-sectoring arithmetic has diverged from `sectorIndex` and
        // nothing below is a measurement of the count.
        let anchor = "re-sectoring at ringSectorCount no longer reproduces the recorded"
            + " reading (plate crossed \(shipped.plate.crossedFailing),"
            + " table crossed \(shipped.table.crossedFailing), joint"
            + " \(shipped.jointFloor)…\(shipped.jointCeiling)) — the sweep is not measuring"
            + " the same rule Decision 43 measured"
        #expect(shipped.plate.crossedFailing == 0 && shipped.table.crossedFailing == 3
                && shipped.jointFloor == 0 && shipped.jointCeiling == 2, "\(anchor)")

        // THE FINDING. The bracket both constraint sets agree on is not a property of the
        // rule; it is a property of the rule AT EIGHT SECTORS. Recorded as 0…2 it reads
        // like a number the session may pick from, and it is not — pick a different count
        // and it is a different interval.
        let brackets = Set(sweeps.map { "\($0.jointFloor)…\($0.jointCeiling)" })
        print("joint brackets over the sweep: \(brackets.sorted())")
        let invariant = "maxCrossedSectors reads the same bracket at every sector count"
            + " (\(brackets.sorted())) — it is not denominated in ringSectorCount after all"
        #expect(brackets.count > 1, "\(invariant)")

        // THE CEILING, and it is not the one the corpus's own sample margin suggests.
        // `ringMinSamples = ringSectorCount × 25` rises WITH the count, so raising the
        // count tightens the very floor the ring has to clear. The native corpus clears
        // it far past any plausible count; the Req 5.1 grid halving does not, so the
        // transfer claim is what binds — and the exact ceiling is the halved grid's
        // thinnest radial band divided by the 25 the derivation targets.
        let nativeCeiling = sweeps.filter(\.nativeFeasible).map(\.count).max() ?? 0
        let halvedCeiling = sweeps.filter(\.halvedFeasible).map(\.count).max() ?? 0
        let thinnestHalvedBand = halvedBandCounts.values.flatMap { $0 }.min() ?? 0
        let exactCeiling = thinnestHalvedBand / Self.samplesPerSectorTarget
        print("sample-floor ceiling on ringSectorCount: native \(nativeCeiling),"
              + " across the Req 5.1 halving \(halvedCeiling);"
              + " exact halved ceiling \(thinnestHalvedBand)/\(Self.samplesPerSectorTarget)"
              + " = \(exactCeiling), shipped \(SupportRegion.ringSectorCount)")
        let binding = "the grid halving no longer binds ringSectorCount before the native"
            + " grid does (native \(nativeCeiling), halved \(halvedCeiling)) — Req 5.1's"
            + " transfer floor has stopped being the tighter constraint"
        #expect(halvedCeiling < nativeCeiling, "\(binding)")
        let exact = "the swept halved ceiling \(halvedCeiling) no longer agrees with the"
            + " arithmetic one \(exactCeiling) — the sweep has stopped bracketing it"
        #expect(halvedCeiling == exactCeiling, "\(exact)")
        let shippedTransfers = "the shipped ringSectorCount no longer survives the Req 5.1"
            + " halving — ringMinSamples \(shipped.impliedRingMinSamples) against halved"
            + " band counts \(halvedBandCounts)"
        #expect(shipped.halvedFeasible, "\(shippedTransfers)")

        // And NO floor, which is the negative worth recording. Decision 40's rule works by
        // finding an arc of the ring above the candidate plane while the rest supports it,
        // so a coarse cut might have averaged the crossing away inside one sector. It does
        // not: the corpus separates its two candidates at every count in the sweep. The
        // rule's SEPARATION is robust to the count; only its bracket is not.
        let separating = sweeps.filter { $0.corpusFloor <= $0.corpusCeiling }.map(\.count)
        print("counts at which the corpus still separates the two candidates: \(separating)")
        let floorAppeared = "the crossed-sector rule has stopped separating the corpus at"
            + " some count (separating at \(separating) of \(Self.sectorCountSweep)) — the"
            + " count now has a floor from the rule as well as a ceiling from Req 5.1"
        #expect(separating == Self.sectorCountSweep, "\(floorAppeared)")

        // What the count buys, over the range Req 5.1 leaves open. It runs the opposite way
        // to intuition: a COARSER cut leaves LESS freedom in the constant it denominates.
        // At the smallest count the joint bracket is a single value, so `maxCrossedSectors`
        // would be determined by what is already committed rather than owed to capture 6 —
        // and the shipped count is where the freedom is WIDEST. Decision 43's "nothing in
        // hand narrows 0…2" is therefore partly a consequence of the count.
        let feasible = sweeps.filter { $0.count <= exactCeiling }
        let widths = feasible.map { (count: $0.count, width: $0.jointCeiling - $0.jointFloor + 1) }
        print("joint bracket width over the Req 5.1-feasible range:"
              + " \(widths.map { "\($0.count):\($0.width)" })")
        let smallest = try #require(widths.first)
        let determined = "the smallest count in the sweep no longer determines"
            + " maxCrossedSectors (width \(smallest.width)) — choosing the count no longer"
            + " discharges the constant and capture 6 is its only source at every count"
        #expect(smallest.width == 1, "\(determined)")
        let widest = try #require(widths.max { $0.width < $1.width })
        let peak = "the shipped count is no longer where maxCrossedSectors is least"
            + " determined (\(widest.count) is, at width \(widest.width)) — Decision 43's"
            + " bracket width has stopped being a property of the shipped count"
        #expect(widest.count == SupportRegion.ringSectorCount, "\(peak)")

        // The other side of the trade, and why a finer cut is not free either: the plane a
        // correct fit must ADMIT starts reading a crossed sector of its own once the arcs
        // are narrow enough to resolve where its ring left the plate onto the table. So the
        // shipped 8 is the LARGEST count at which the rule's floor is still zero, inside the
        // Req 5.1 ceiling above — bracketing the count 4…8 rather than setting it.
        let cleanFloor = sweeps.filter { $0.plate.crossedFailing == 0 }.map(\.count)
        print("counts at which the intended plate candidate reads no crossed sector:"
              + " \(cleanFloor) — ringSectorCount bracketed \(cleanFloor.min() ?? 0)…"
              + "\(cleanFloor.max() ?? 0) against a Req 5.1 ceiling of \(exactCeiling)")
        let eroded = "the intended candidate's crossed count no longer separates the sweep"
            + " at the shipped value (clean at \(cleanFloor)) — the pass-side erosion this"
            + " records has moved"
        #expect(cleanFloor.allSatisfy { $0 <= SupportRegion.ringSectorCount }
                && cleanFloor.contains(SupportRegion.ringSectorCount), "\(eroded)")
        // Bracketed, not set: more than one count survives both sides, so this is not a
        // derivation either.
        let collapsed = "the count bracket has collapsed to a single value — ringSectorCount"
            + " would be measured rather than owed, and the design must be updated to say so"
        #expect(cleanFloor.count > 1, "\(collapsed)")
    }

    // MARK: - The support bar, and what it is the bar OF

    // The third member of Req 3.7's trio and the one nothing has ever varied. Decision 44
    // measured the count and deferred this in as many words: "the support bar is a
    // fraction of a sector's samples, not a count of sectors, so it is not re-denominated
    // by this finding and its measurement is a separate one".
    //
    // It is not a peer of the other two either, and Decision 40 is where that shows.
    // The crossed-sector rule reads the SIGN of sectors that FAIL this bar, so
    // `sectorSupportMin` selects the population the rule is computed over. Decision 40's
    // central claim — that the rule's magnitude bar is `[inherited]` rather than fitted,
    // because failing sectors separate over 23.397 mm where all sectors separate over
    // 2.128 mm — is a statement about that population. And "all sectors" is precisely this
    // constant at 1.0, so the 2.128 mm figure Decision 40 quotes as a contrast is its own
    // sweep's other end. The claim is a reading at 0.5 of a quantity that moves with the
    // bar, and nothing records what it does in between.
    static let supportBarSweep: [Float] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    // The counts Req 5.1's ceiling leaves open (Decision 44: 4…11 by the sample floor,
    // 4…8 by the pass side), for the two-dimensional half of the sweep.
    static let feasibleCountSweep = [4, 6, 8, 10, 11]

    @Test("the support bar selects the population Decision 40's rule reads, and brackets itself")
    func supportBarSelectsThePopulationTheRuleReads() throws {
        var rings: [String: (SupportRegion.DepthGeometry, SupportRegion.RingSamples,
                             SupportRegion.PlaneCandidate)] = [:]
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            rings[name] = (g, samples, try #require(Self.bestCandidate(name)))
        }
        let readings = Self.sceneReadings()
        #expect(readings.count == 8, "a scene stopped producing ring statistics")
        let mustPass = readings.filter { $0.requiresPass.contains(.sectors) }
        let mustFire = readings.filter { $0.requiresFire.contains(.sectors) }

        // One reading of both constraint sets at one (count, bar) pair.
        struct Bar {
            let supportMin: Float
            let count: Int
            let plate: SectorSigns
            let table: SectorSigns
            let corpusFloor: Int
            let corpusCeiling: Int
            let suiteFloor: Int
            let suiteCeiling: Int
            var jointFloor: Int { max(corpusFloor, suiteFloor) }
            var jointCeiling: Int { min(corpusCeiling, suiteCeiling) }
            var jointFeasible: Bool { jointFloor <= jointCeiling }
            // Decision 40's window, recomputed at this bar. It is a VERDICT-INVARIANCE
            // interval, not a population separation: how far `ringBandMm` may move before
            // one of the two candidates changes its crossed count. The lower edge is the
            // highest failing median of the plane a correct fit must ADMIT — below it the
            // plate gains a crossed sector — and the upper edge is the lowest CROSSED
            // median of the plane the rule must reject, above which the table loses one.
            let invarianceLowMm: Float
            let invarianceHighMm: Float
            var invarianceMm: Float { invarianceHighMm - invarianceLowMm }
            var barInside: Bool {
                invarianceLowMm < SupportRegion.ringBandMm
                    && SupportRegion.ringBandMm < invarianceHighMm
            }
            // The harsher reading of the same two populations: the plate's highest failing
            // median against the table's lowest failing median, with no conditioning on the
            // bar's current value. Positive means the two sets of failing sectors are
            // separated outright; negative means they interleave and only the bar's
            // position keeps the verdicts apart.
            let separationLowMm: Float
            let separationHighMm: Float
            var separationMm: Float { separationHighMm - separationLowMm }
            // Whether the rule can fire at all: a rule reading a population the wrong
            // plane contributes nothing to cannot reject it.
            var fires: Bool { table.crossedFailing > 0 }
        }

        func read(count: Int, supportMin: Float) throws -> Bar {
            var signs: [String: SectorSigns] = [:]
            for (name, r) in rings {
                signs[name] = Self.sectorSigns(samples: r.1, geometry: r.0,
                                               normal: r.2.normal, d: r.2.d,
                                               count: count, supportMin: supportMin)
            }
            let plate = try #require(signs["1785135663727"])
            let table = try #require(signs["1785901032716"])
            let passCrossed = mustPass.map { $0.signs(at: count, supportMin: supportMin).crossedFailing }
            let fireCrossed = mustFire.map { $0.signs(at: count, supportMin: supportMin).crossedFailing }
            return Bar(
                supportMin: supportMin, count: count, plate: plate, table: table,
                corpusFloor: plate.crossedFailing,
                corpusCeiling: table.crossedFailing - 1,
                suiteFloor: passCrossed.max() ?? 0,
                suiteCeiling: (fireCrossed.min() ?? 0) - 1,
                invarianceLowMm: plate.failingMedians.max() ?? -.infinity,
                invarianceHighMm: table.failingMedians
                    .filter { $0 > SupportRegion.ringBandMm }.min() ?? .infinity,
                separationLowMm: plate.failingMedians.max() ?? -.infinity,
                separationHighMm: table.failingMedians.min() ?? .infinity)
        }

        // MARK: the bar swept at the shipped count
        let bars = try Self.supportBarSweep.map {
            try read(count: SupportRegion.ringSectorCount, supportMin: $0)
        }
        for b in bars {
            print("supportMin \(fmt(b.supportMin)):"
                  + " plate supporting \(b.plate.supporting) failing \(b.plate.failing.count)"
                  + " crossed \(b.plate.crossedFailing) escaped \(b.plate.escapedFailing);"
                  + " table supporting \(b.table.supporting) failing \(b.table.failing.count)"
                  + " crossed \(b.table.crossedFailing);"
                  + " invariance \(fmt(b.invarianceLowMm))…\(fmt(b.invarianceHighMm)) mm"
                  + " (\(fmt(b.invarianceMm)) wide, ringBandMm inside: \(b.barInside));"
                  + " separation \(fmt(b.separationLowMm))…\(fmt(b.separationHighMm)) mm"
                  + " (\(fmt(b.separationMm)));"
                  + " maxCrossedSectors corpus \(b.corpusFloor)…\(b.corpusCeiling),"
                  + " suite \(b.suiteFloor)…\(b.suiteCeiling),"
                  + " joint \(b.jointFloor)…\(b.jointCeiling)"
                  + " \(b.jointFeasible ? "" : "EMPTY")")
        }

        let shipped = try #require(bars.first { $0.supportMin == SupportRegion.sectorSupportMin })

        // Anchor. At the shipped bar this reproduces Decisions 40, 43 and 44 exactly — the
        // window they quote, the crossed counts, and the joint bracket. If it does not, the
        // parameterised classification has diverged from `ringStatistics` and nothing below
        // is a measurement of the bar.
        let anchor = "re-classifying at sectorSupportMin no longer reproduces the recorded"
            + " reading (plate crossed \(shipped.plate.crossedFailing), table crossed"
            + " \(shipped.table.crossedFailing), window \(fmt(shipped.invarianceLowMm))…"
            + "\(fmt(shipped.invarianceHighMm)) mm, joint \(shipped.jointFloor)…\(shipped.jointCeiling))"
        #expect(shipped.plate.crossedFailing == 0 && shipped.table.crossedFailing == 3
                && shipped.jointFloor == 0 && shipped.jointCeiling == 2
                && abs(shipped.invarianceLowMm - -6.794) < 0.01
                && abs(shipped.invarianceHighMm - 16.603) < 0.01, "\(anchor)")

        // THE FLOOR, and it is the rule's own rather than the unsigned count's. Set the bar
        // low enough and no sector fails on the wrong plane, so the population Decision 40's
        // rule reads is EMPTY — and a rule with nothing to read admits the plane Decision 18
        // exists to reject. At the shipped count only 0 is silent; the grid below shows the
        // floor rising with a coarser cut, which is the first half of the coupling.
        let firing = bars.filter(\.fires).map(\.supportMin)
        let silent = bars.filter { !$0.fires }.map(\.supportMin)
        print("bars at which the rule fires on the table candidate: \(firing.map { fmt($0) });"
              + " silent at \(silent.map { fmt($0) })")
        let noFloor = "the crossed-sector rule fires at every bar in the sweep"
            + " (\(bars.map { fmt($0.supportMin) })) — sectorSupportMin has no floor from"
            + " the rule and this finding has moved"
        #expect(!silent.isEmpty, "\(noFloor)")

        // THE CEILING, and Decision 40 quoted it without recognising it as one. Both edges
        // of the window converge on the bar as `sectorSupportMin` rises, from opposite
        // sides: sectors that sit ON the plate candidate's plane but are noisy start
        // FAILING, and they read near zero, so the lower edge climbs; sectors that hold the
        // table candidate's plane at a small positive offset fail too and become crossed, so
        // the upper edge falls. At 1.0 every sector fails and the window is Decision 40's
        // "over all sectors" figure exactly — that contrast is this sweep's endpoint.
        let allSectors = try #require(bars.last)
        print("invariance window over the sweep:"
              + " \(bars.map { "\(fmt($0.supportMin)):\(fmt($0.invarianceMm))" })")
        let degenerate = "the bar at 1.0 no longer reproduces Decision 40's all-sector"
            + " window (+3.846…+5.974 mm, 2.128 wide) — the contrast it draws is not this"
            + " sweep's endpoint after all"
        #expect(abs(allSectors.invarianceLowMm - 3.846) < 0.01
                && abs(allSectors.invarianceHighMm - 5.974) < 0.01, "\(degenerate)")

        // And the same endpoint read without conditioning on where `ringBandMm` currently
        // sits: over ALL sectors the two candidates' failing medians INTERLEAVE — the
        // table's lowest is below the plate's highest — so the 2.128 mm Decision 40 quotes
        // is the room the bar has at its own value, not a gap between the populations.
        // The contrast it draws understates its own case.
        print("all-sector separation \(fmt(allSectors.separationLowMm))…"
              + "\(fmt(allSectors.separationHighMm)) mm (\(fmt(allSectors.separationMm)))"
              + " against the failing-sector separation at the shipped bar"
              + " \(fmt(shipped.separationLowMm))…\(fmt(shipped.separationHighMm)) mm"
              + " (\(fmt(shipped.separationMm)))")
        let stillSeparated = "the all-sector populations no longer interleave"
            + " (\(fmt(allSectors.separationMm)) mm) — Decision 40's 2.128 mm contrast is a"
            + " genuine gap and the harsher reading has stopped saying anything extra"
        #expect(allSectors.separationMm < 0 && shipped.separationMm > 0, "\(stillSeparated)")

        // `ringBandMm` sits inside the invariance window at every firing bar, because the
        // window's edges are DEFINED by the crossed counts either side of it — so
        // "inherited or fitted" is not a yes/no, it is the window's WIDTH, and Decision 40
        // supplies the criterion: 2.128 mm is "being fitted to the corpus", 23.397 mm is
        // "being inherited". Applied to the sweep, that criterion needs no threshold of its
        // own, because the collapse is a cliff rather than a slope — one notch of the bar.
        let byConstruction = "ringBandMm has left the invariance window at some firing bar —"
            + " the window's edges no longer bracket it by construction"
        #expect(bars.allSatisfy { !$0.fires || $0.barInside }, "\(byConstruction)")
        let firingBars = bars.filter(\.fires)
        let widths = firingBars.map { (bar: $0.supportMin, mm: $0.invarianceMm) }
        let cliff = try #require(zip(widths, widths.dropFirst()).max {
            ($0.0.mm / $0.1.mm) < ($1.0.mm / $1.1.mm)
        })
        print("the largest single-notch collapse is \(fmt(cliff.0.bar)) → \(fmt(cliff.1.bar)):"
              + " \(fmt(cliff.0.mm)) → \(fmt(cliff.1.mm)) mm, a factor of"
              + " \(fmt(cliff.0.mm / cliff.1.mm)); shipped bar \(fmt(SupportRegion.sectorSupportMin))")
        let onTheCliff = "the invariance window's collapse is no longer a cliff at the"
            + " shipped bar (largest step \(fmt(cliff.0.bar))→\(fmt(cliff.1.bar)), factor"
            + " \(fmt(cliff.0.mm / cliff.1.mm))) — sectorSupportMin's ceiling stops being"
            + " self-selecting and needs a threshold of its own"
        #expect(cliff.0.bar == SupportRegion.sectorSupportMin
                && cliff.0.mm / cliff.1.mm > 5, "\(onTheCliff)")

        // So the bar is bracketed by Decision 40's own argument, and the shipped value is
        // AT the ceiling rather than inside it: every bar above the cliff leaves
        // `ringBandMm` the ~2 mm of room Decision 40 rejected the all-sector formulation for.
        let wide = firingBars.filter { $0.invarianceMm > 10 }.map(\.supportMin)
        print("bars leaving ringBandMm more than 10 mm of room: \(wide.map { fmt($0) });"
              + " sectorSupportMin bracketed \(fmt(wide.min() ?? 0))…\(fmt(wide.max() ?? 0))"
              + " at ringSectorCount \(SupportRegion.ringSectorCount)")
        let atTheCeiling = "the shipped sectorSupportMin is no longer the largest bar leaving"
            + " ringBandMm inherited (\(wide.map { fmt($0) })) — it has stopped sitting on"
            + " the edge of its own bracket"
        #expect(wide.max() == SupportRegion.sectorSupportMin, "\(atTheCeiling)")
        let determined = "the support bar's bracket has collapsed to one value —"
            + " sectorSupportMin would be measured rather than owed"
        #expect(wide.count > 1, "\(determined)")

        // MARK: the two constants together
        // Decision 44 says fix the count FIRST, then read `maxCrossedSectors` in the unit
        // it fixed. That ordering assumes the count's own reading does not depend on the
        // bar. Both constants are owed, so the assumption is measurable: read the joint
        // bracket over the whole grid and ask whether the count's bracket moves with it.
        print("joint bracket on maxCrossedSectors over (count × supportMin):")
        var cleanCountsByBar: [Float: [Int]] = [:]
        var collisions: [String] = []
        for supportMin in Self.supportBarSweep {
            var row: [String] = []
            var clean: [Int] = []
            for count in Self.feasibleCountSweep {
                let b = try read(count: count, supportMin: supportMin)
                if !b.jointFeasible && b.fires {
                    collisions.append("\(count)×\(fmt(supportMin))")
                }
                // An empty joint bracket has two causes and they are not the same finding:
                // the rule may be SILENT (nothing crossed on the plane it must reject, so
                // no ceiling exists) or the two constraint sets may CONTRADICT, which is
                // Decision 41's collision reappearing on the rule Decision 43 said escaped it.
                let cell: String
                if b.jointFeasible {
                    cell = "\(b.jointFloor)…\(b.jointCeiling)"
                } else {
                    cell = b.fires ? "COLLIDES" : "silent"
                }
                row.append("\(count):\(cell)")
                if b.plate.crossedFailing == 0 && b.fires { clean.append(count) }
            }
            cleanCountsByBar[supportMin] = clean
            print("  supportMin \(fmt(supportMin)): \(row.joined(separator: "  "))"
                  + " | counts with a clean pass side and a firing rule: \(clean)")
        }

        // Decision 43's headline survives the whole grid: wherever the rule fires at all,
        // the suite and the corpus still admit a common `maxCrossedSectors`. The collision
        // that broke the unsigned count belongs to the count, not to the (count, bar) pair —
        // which is a stronger statement than Decision 43 could make at one pair.
        let collided = "the crossed-sector rule now inherits Decision 41's collision at some"
            + " (count × supportMin) pair (\(collisions)) — Decision 43's finding is a"
            + " property of the shipped pair rather than of the rule"
        #expect(collisions.isEmpty, "\(collided)")

        // Decision 44 bracketed `ringSectorCount` 4…8 on the pass side, read at the shipped
        // bar. If the bar moves that bracket, the two constants are not separable and the
        // stated ordering is not enough — the session has to fix them together.
        let atShipped = try #require(cleanCountsByBar[SupportRegion.sectorSupportMin])
        let barsMovingTheCount = Self.supportBarSweep.filter {
            (cleanCountsByBar[$0] ?? []) != atShipped && !(cleanCountsByBar[$0] ?? []).isEmpty
        }
        print("Decision 44's count bracket at the shipped bar: \(atShipped);"
              + " bars that move it: \(barsMovingTheCount.map { fmt($0) })")
        let separable = "the count's pass-side bracket reads the same at every bar that"
            + " admits one — ringSectorCount and sectorSupportMin are separable and"
            + " Decision 44's ordering is sufficient"
        #expect(!barsMovingTheCount.isEmpty, "\(separable)")
    }

    // MARK: - The ring radius, and what it is the radius OF

    // `ringOuterMm` is `[owed]` with no derivation at all. Decision 33 measured its
    // stated rule — "inside the smallest measured plate margin" — and found it
    // unsatisfiable, since the tightest margin is 4 mm and `ringInnerMm` is 8, and
    // nothing has replaced it. Meanwhile Decisions 44 and 45 measured the sector
    // measure's other two free constants and concluded they must be fixed jointly.
    //
    // This is the third, and it is upstream of both. The sector rule reads the INNER
    // BAND, whose outer edge is `ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount`
    // = 13.667 mm at the shipped value — so Decision 33's "only 4 of 8 sectors reach the
    // inner band" and Decision 43's rimmed-plate blind spot ("their rims never reach the
    // inner band the sector median is computed over") are both readings of this constant.
    // And unlike the count and the bar, it moved the ANNULUS with it — the bound was
    // `2 × ringOuterMm` when this sweep was written — so it changed which planes compete
    // rather than only how a fixed set is read. Decision 49 severed that; this sweep passes
    // the coupled bound explicitly and remains a measurement of the coupling.
    // Coarse outside the bracket, 1 mm inside it: the floor and the ceiling below are
    // read off this grid, so a spacing of 5 mm there would report a precision the sweep
    // does not have.
    static let ringOuterSweep: [Float] = [
        13, 15, 17, 20, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 35, 40,
    ]

    @Test("the ring radius is the radial unit of the sector rule, and it re-selects the candidates")
    func ringRadiusIsTheRadialUnitOfTheSectorRule() throws {
        let specs = Self.sceneSpecs()
        #expect(specs.count == 8, "a scene stopped producing a spec")
        let mustPass = specs.filter { $0.requiresPass.contains(.sectors) }
        let mustFire = specs.filter { $0.requiresFire.contains(.sectors) }

        struct Corpus {
            let name: String
            let signs: SectorSigns
            let supportFraction: Float
            let ringMedianMm: Float
            let bandCounts: [Int]
            let candidateCount: Int
            let ringSampleCount: Int
            let annulusSampleCount: Int
            // Where the SELECTED plane cuts the food-centroid ray, in millimetres of
            // range. Taken from the native grid's centroid so every radius is compared at
            // one physical direction — the same instrument Decision 35 measures Req 5.1's
            // 1 mm transfer tolerance with, and the units volume is integrated in.
            let planeAtFoodMm: Float
            let normal: Vec3
            var feasible: Bool {
                bandCounts.allSatisfy { $0 >= SupportRegion.ringMinSamples }
            }
            var occupied: Int { signs.sectorSampleCounts.filter { $0 > 0 }.count }
        }

        struct Radius {
            let outerMm: Float
            let innerBandOuterMm: Float
            let corpus: [Corpus]
            // `maxCrossedSectors`, Decision 43's two constraint sets at this radius.
            let corpusFloor: Int, corpusCeiling: Int
            let suiteFloor: Int, suiteCeiling: Int
            // `minSupportingSectors`, the unsigned count Decision 41 found contradictory.
            let countCorpusCeiling: Int
            let countSuiteFloor: Int, countSuiteCeiling: Int
            // Req 5.1's 2× depth-grid halving, the same transfer Decision 44 read the
            // count's ceiling off. A narrower ring holds fewer samples and the halving
            // quarters them, so this is where the radius acquires a FLOOR.
            let halvedBandCounts: [String: [Int]]
            var halvedFeasible: Bool {
                halvedBandCounts.values.allSatisfy {
                    $0.allSatisfy { $0 >= SupportRegion.ringMinSamples }
                }
            }
            var jointFloor: Int { max(corpusFloor, suiteFloor) }
            var jointCeiling: Int { min(corpusCeiling, suiteCeiling) }
            var jointFeasible: Bool { jointFloor <= jointCeiling }
            var countJointFloor: Int { countSuiteFloor }
            var countJointCeiling: Int { min(countCorpusCeiling, countSuiteCeiling) }
            var countJointFeasible: Bool { countJointFloor <= countJointCeiling }
            var feasible: Bool { corpus.allSatisfy(\.feasible) }
        }

        // The halved geometry is a property of the capture, not of the radius, so it is
        // prepared once and re-ringed inside the sweep.
        var halvedGeometry: [String: SupportRegion.DepthGeometry] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            halvedGeometry[name] = try #require(Self.geometry(slice, decimation: 2))
        }

        var radii: [Radius] = []
        for outerMm in Self.ringOuterSweep {
            var corpus: [Corpus] = []
            var halvedBands: [String: [Int]] = [:]
            for name in Self.captures {
                let slice = try DepthSlice.load(name)
                let g = try #require(Self.geometry(name))
                let halved = Self.ringSamples(
                    geometry: try #require(halvedGeometry[name]), outerMm: outerMm)
                var halvedCounts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
                for band in halved.band { halvedCounts[band] += 1 }
                halvedBands[name] = halvedCounts
                let samples = Self.ringSamples(geometry: g, outerMm: outerMm,
                                               annulusOuterMm: Self.coupledBoundMm(outerMm))
                // Re-extracted, not re-read: under the coupling this sweep measures, the
                // annulus is `2 × outerMm`, so the candidate set is a function of the
                // radius too. Decision 49 severed that; the coupled bound is passed
                // explicitly here so this stays the measurement Decision 46 recorded.
                var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
                let candidates = SupportRegion.extractCandidates(
                    annulus: samples.annulus, geometry: g,
                    gravity: slice.gravity.normalised(), rng: &rng)
                let best = try #require(candidates.max {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: $0.normal, d: $0.d)
                    < Self.innerSupportFraction(samples: samples, geometry: g,
                                                normal: $1.normal, d: $1.d)
                }, "no candidate survives extraction at ringOuterMm = \(fmt(outerMm))")
                var counts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
                for band in samples.band { counts[band] += 1 }
                corpus.append(Corpus(
                    name: name,
                    signs: Self.sectorSigns(samples: samples, geometry: g,
                                            normal: best.normal, d: best.d,
                                            count: SupportRegion.ringSectorCount),
                    supportFraction: Self.innerSupportFraction(
                        samples: samples, geometry: g, normal: best.normal, d: best.d),
                    ringMedianMm: SupportRegion.medianHeight(
                        indices: samples.ring, geometry: g, normal: best.normal, d: best.d),
                    bandCounts: counts,
                    candidateCount: candidates.count,
                    ringSampleCount: samples.ring.count,
                    annulusSampleCount: samples.annulus.count,
                    planeAtFoodMm: Self.planeDepthMm(
                        normal: best.normal, d: best.d,
                        ray: try #require(Self.foodCentroidRay(slice))),
                    normal: best.normal))
            }
            let plate = try #require(corpus.first { $0.name == "1785135663727" })
            let table = try #require(corpus.first { $0.name == "1785901032716" })
            let passSigns = try mustPass.map { try #require(Self.sceneSigns($0, outerMm: outerMm)) }
            let fireSigns = try mustFire.map { try #require(Self.sceneSigns($0, outerMm: outerMm)) }
            radii.append(Radius(
                outerMm: outerMm,
                innerBandOuterMm: SupportRegion.ringInnerMm
                    + (outerMm - SupportRegion.ringInnerMm) / Float(SupportRegion.ringBandCount),
                corpus: corpus,
                corpusFloor: plate.signs.crossedFailing,
                corpusCeiling: table.signs.crossedFailing - 1,
                suiteFloor: passSigns.map(\.crossedFailing).max() ?? 0,
                suiteCeiling: (fireSigns.map(\.crossedFailing).min() ?? 0) - 1,
                countCorpusCeiling: plate.signs.supporting,
                countSuiteFloor: (fireSigns.map(\.supporting).max() ?? 0) + 1,
                countSuiteCeiling: passSigns.map(\.supporting).min() ?? 0,
                halvedBandCounts: halvedBands))
        }

        // The plane the SHIPPED radius selects, per capture — the reference every other
        // radius's selection is compared against.
        let shippedRadius = try #require(radii.first { $0.outerMm == SupportRegion.ringOuterMm })
        var shippedPlaneAtFood: [String: Float] = [:]
        var shippedNormal: [String: Vec3] = [:]
        for c in shippedRadius.corpus {
            shippedPlaneAtFood[c.name] = c.planeAtFoodMm
            shippedNormal[c.name] = c.normal
        }

        for r in radii {
            print("ringOuterMm=\(fmt(r.outerMm)) (inner band ends \(fmt(r.innerBandOuterMm)) mm,"
                  + " annulus \(fmt(2 * r.outerMm)) mm):")
            for c in r.corpus {
                print("  \(c.name): candidates \(c.candidateCount), ring \(c.ringSampleCount),"
                      + " annulus \(c.annulusSampleCount), bands \(c.bandCounts)"
                      + " \(c.feasible ? "feasible" : "REFUSED");"
                      + " best support \(fmt(c.supportFraction)), ring median"
                      + " \(fmt(c.ringMedianMm)) mm, PLANE AT FOOD \(fmt(c.planeAtFoodMm)) mm"
                      + " (\(fmt(c.planeAtFoodMm - (shippedPlaneAtFood[c.name] ?? c.planeAtFoodMm)))"
                      + " vs shipped, tilt"
                      + " \(fmt(Self.angleDeg(c.normal, shippedNormal[c.name] ?? c.normal)))°),"
                      + " occupied \(c.occupied)/8,"
                      + " supporting \(c.signs.supporting), failing \(c.signs.failing.count),"
                      + " crossed \(c.signs.crossedFailing), escaped \(c.signs.escapedFailing)")
            }
            print("  maxCrossedSectors corpus \(r.corpusFloor)…\(r.corpusCeiling),"
                  + " suite \(r.suiteFloor)…\(r.suiteCeiling),"
                  + " joint \(r.jointFloor)…\(r.jointCeiling)"
                  + " \(r.jointFeasible ? "" : "EMPTY");"
                  + " minSupportingSectors corpus ≤ \(r.countCorpusCeiling),"
                  + " suite \(r.countSuiteFloor)…\(r.countSuiteCeiling),"
                  + " joint \(r.countJointFloor)…\(r.countJointCeiling)"
                  + " \(r.countJointFeasible ? "" : "EMPTY")")
            print("  Req 5.1 halved bands \(r.halvedBandCounts)"
                  + " \(r.halvedFeasible ? "feasible" : "REFUSED")")
        }

        // Anchor. At the shipped radius this must reproduce Decisions 41, 43 and 45
        // exactly — plate 0 crossed, table 3, joint `maxCrossedSectors` 0…2, and the
        // unsigned count's empty 6…5 — or the re-ringing has diverged from
        // `SupportRegion.ringSamples` and nothing below is a measurement of the radius.
        let shipped = shippedRadius
        let anchor = "re-ringing at ringOuterMm no longer reproduces the recorded reading"
            + " (crossed joint \(shipped.jointFloor)…\(shipped.jointCeiling), count joint"
            + " \(shipped.countJointFloor)…\(shipped.countJointCeiling)) — the sweep is not"
            + " measuring the same ring Decisions 43 and 45 measured"
        #expect(shipped.jointFloor == 0 && shipped.jointCeiling == 2
                && shipped.countSuiteFloor == 6 && shipped.countCorpusCeiling == 5,
                "\(anchor)")

        // THE FINDING, and it is not the one Decisions 44 and 45 make. Those two swept a
        // constant and closed with "no value moves": the count and the bar re-READ a fixed
        // candidate set, so they can only move a bracket. This one moves the ANSWER. The
        // annulus was `2 × ringOuterMm` when this was measured, so extraction runs on a
        // different sample set at every radius and the plane it selects lands somewhere else
        // at the food. Decision 49 shows the movement is the annulus's alone.
        //
        // The units are Decision 35's — millimetres of range along the food-centroid ray,
        // added to every food pixel — so the span is directly comparable with Req 5.1's
        // 1 mm transfer tolerance.
        var spanByCapture: [String: (lo: Float, hi: Float)] = [:]
        for r in radii {
            for c in r.corpus {
                let existing = spanByCapture[c.name] ?? (c.planeAtFoodMm, c.planeAtFoodMm)
                spanByCapture[c.name] = (min(existing.lo, c.planeAtFoodMm),
                                         max(existing.hi, c.planeAtFoodMm))
            }
        }
        let spans = spanByCapture.mapValues { $0.hi - $0.lo }
        let widestSpan = spans.values.max() ?? 0
        print("plane movement at the food over the radius sweep:"
              + " \(spans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm transfer tolerance")
        let inert = "ringOuterMm no longer moves the selected plane at the food beyond Req"
            + " 5.1's own transfer tolerance (\(fmt(widestSpan)) mm against"
            + " \(fmt(Self.gridTransferToleranceMm)) mm) — it is a bracket-only constant"
            + " like ringSectorCount and sectorSupportMin, and this finding can be retired"
        #expect(widestSpan > Self.gridTransferToleranceMm, "\(inert)")

        // And the movement is not drift around one surface. On the capture whose
        // best-support candidate Decision 30 identified as the TABLE, the selection
        // bifurcates: the narrow radii pick a plane roughly a plate's height nearer the
        // camera, reading a NEGATIVE ring median where the shipped radius reads positive.
        // Which surface this capture selects is therefore a function of an owed constant.
        let table = radii.compactMap { r in
            r.corpus.first { $0.name == "1785901032716" }.map { (r.outerMm, $0) }
        }
        let low = table.filter { $0.1.ringMedianMm < 0 }.map(\.0)
        let high = table.filter { $0.1.ringMedianMm > 0 }.map(\.0)
        print("1785901032716 selects a negative-ring-median plane at \(low.map { fmt($0) })"
              + " and a positive one at \(high.map { fmt($0) }) —"
              + " separation \((table.filter { $0.1.ringMedianMm > 0 }.map(\.1.planeAtFoodMm).min() ?? 0) - (table.filter { $0.1.ringMedianMm < 0 }.map(\.1.planeAtFoodMm).max() ?? 0)) mm at the food")
        let oneSurface = "the second capture's selection no longer changes sign with the"
            + " radius (low \(low.map { fmt($0) }), high \(high.map { fmt($0) })) — the"
            + " bifurcation this records has gone"
        #expect(!low.isEmpty && !high.isEmpty, "\(oneSurface)")

        // The CEILING, and it comes from the committed suite exactly as Decision 41 warned
        // it would: the scenes place their features at fixed pixel radii, so a wide enough
        // ring reaches the rim a scene put outside it. Both suite intervals go empty
        // together — every sector of a scene that must PASS reads crossed.
        let suiteHolds = radii.filter { $0.suiteFloor <= $0.suiteCeiling }.map(\.outerMm)
        let suiteCeiling = suiteHolds.max() ?? 0
        print("radii at which the committed suite still admits a maxCrossedSectors:"
              + " \(suiteHolds.map { fmt($0) }) — ceiling \(fmt(suiteCeiling)) mm")
        let unbounded = "the committed suite now admits every radius in the sweep — it has"
            + " stopped capping ringOuterMm and the ceiling this records is gone"
        #expect(suiteCeiling < Self.ringOuterSweep.max() ?? 0, "\(unbounded)")

        // The FLOOR, and it is Req 5.1's — the mirror of Decision 44's ceiling on the
        // count. A narrower ring holds fewer samples per band and the 2× halving quarters
        // them, so below some radius `ringBandsAreFeasible` refuses on a grid where the
        // plane still transfers within a millimetre.
        let transfers = radii.filter(\.halvedFeasible).map(\.outerMm)
        let floor = transfers.min() ?? 0
        print("radii at which the ring survives the Req 5.1 halving: \(transfers.map { fmt($0) })"
              + " — floor \(fmt(floor)) mm; ringOuterMm bracketed \(fmt(floor))…\(fmt(suiteCeiling)) mm")
        let noFloor = "the Req 5.1 halving no longer refuses any radius in the sweep — the"
            + " floor this records is gone and ringOuterMm is capped only from above"
        #expect(floor > Self.ringOuterSweep.min() ?? 0, "\(noFloor)")
        let shippedInside = "the shipped ringOuterMm has left the bracket its own"
            + " constraints produce (\(fmt(floor))…\(fmt(suiteCeiling)) mm)"
        #expect(SupportRegion.ringOuterMm >= floor
                && SupportRegion.ringOuterMm <= suiteCeiling, "\(shippedInside)")

        // And the bracket cannot be read the way the other two were. The count and the bar
        // both erode monotonically, so Decisions 44 and 45 could name an end and say what
        // lies past it. The radius does not: the plate candidate — the one plane a correct
        // fit must admit — reads no crossed sector at every radius in the sweep EXCEPT one
        // in the middle of it, where re-extraction hands it a different plane. A value
        // between two clean radii is therefore not implied by either.
        let cleanPassSide = radii.filter { $0.corpusFloor == 0 }.map(\.outerMm)
        let dirty = Self.ringOuterSweep.filter { !cleanPassSide.contains($0) }
        print("radii at which the intended plate candidate reads no crossed sector:"
              + " \(cleanPassSide.map { fmt($0) }); interior exceptions \(dirty.map { fmt($0) })")
        let monotonic = "the radius's pass side now erodes monotonically like the count's"
            + " (clean at \(cleanPassSide.map { fmt($0) })) — ringOuterMm can be bracketed"
            + " by interpolation after all"
        #expect(dirty.contains { $0 > (cleanPassSide.min() ?? 0)
                                 && $0 < (cleanPassSide.max() ?? 0) }, "\(monotonic)")

        // Which makes `maxCrossedSectors` denominated in a THIRD owed constant. Decision 44
        // recorded it as a count of sectors, Decision 45 as a count read at a bar; it is
        // also a count read at a radius, and the radius reorders it rather than scaling it.
        let brackets = radii.filter(\.jointFeasible).map { "\($0.jointFloor)…\($0.jointCeiling)" }
        print("joint maxCrossedSectors brackets over the radius sweep: \(brackets)")
        let radiusInvariant = "maxCrossedSectors reads one bracket at every radius"
            + " (\(Set(brackets).sorted())) — it is not denominated in ringOuterMm and the"
            + " session may fix the count and the bar without it"
        #expect(Set(brackets).count > 1, "\(radiusInvariant)")
    }

    // The control the sweep above needs. Its pass side alternates between clean and dirty
    // at 1 mm steps of the radius, which admits two readings: either the radius genuinely
    // reorders the candidates, or extraction is unstable and moving the annulus merely
    // re-rolls it. The two are told apart by holding the radius FIXED at the shipped value
    // and varying only the RANSAC seed — the one input the sweep above holds constant,
    // since `Fnv1a64.hash(depthBytesMm)` is a property of the capture.
    //
    // If the spread under seeds alone matches the spread under radii, the sweep is
    // measuring extraction variance and `ringOuterMm` is not the constant carrying it.
    @Test("candidate selection at the shipped radius is unstable under the RANSAC seed alone")
    func candidateSelectionIsSeedUnstableAtTheShippedRadius() throws {
        struct Roll {
            let seed: UInt64
            let planeAtFoodMm: Float
            let crossed: Int
            let supporting: Int
            let supportFraction: Float
            let ringMedianMm: Float
            let candidateCount: Int
        }

        var spreadByCapture: [String: Float] = [:]
        var seedVerdicts: [String: (crossed: Set<Int>, supporting: Set<Int>)] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let ray = try #require(Self.foodCentroidRay(slice))
            let shippedSeed = Fnv1a64.hash(slice.depth.depthBytesMm)

            var rolls: [Roll] = []
            for i in 0..<Self.seedRolls {
                // The shipped seed first, so the roll the corpus actually reads is in the
                // set rather than compared against it.
                let seed = i == 0 ? shippedSeed : shippedSeed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
                var rng = SplitMix64(seed: seed)
                let candidates = SupportRegion.extractCandidates(
                    annulus: samples.annulus, geometry: g,
                    gravity: slice.gravity.normalised(), rng: &rng)
                guard let best = candidates.max(by: {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: $0.normal, d: $0.d)
                    < Self.innerSupportFraction(samples: samples, geometry: g,
                                                normal: $1.normal, d: $1.d)
                }) else { continue }
                let signs = Self.sectorSigns(samples: samples, geometry: g,
                                             normal: best.normal, d: best.d,
                                             count: SupportRegion.ringSectorCount)
                rolls.append(Roll(
                    seed: seed,
                    planeAtFoodMm: Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray),
                    crossed: signs.crossedFailing,
                    supporting: signs.supporting,
                    supportFraction: Self.innerSupportFraction(
                        samples: samples, geometry: g, normal: best.normal, d: best.d),
                    ringMedianMm: SupportRegion.medianHeight(
                        indices: samples.ring, geometry: g, normal: best.normal, d: best.d),
                    candidateCount: candidates.count))
            }
            #expect(rolls.count == Self.seedRolls, "extraction failed on some seed")

            let planes = rolls.map(\.planeAtFoodMm)
            let spread = (planes.max() ?? 0) - (planes.min() ?? 0)
            spreadByCapture[name] = spread
            seedVerdicts[name] = (crossed: Set(rolls.map(\.crossed)),
                                  supporting: Set(rolls.map(\.supporting)))
            print("\(name) at ringOuterMm=\(fmt(SupportRegion.ringOuterMm)),"
                  + " \(Self.seedRolls) seeds:")
            for r in rolls {
                print("  plane at food \(fmt(r.planeAtFoodMm)) mm, support \(fmt(r.supportFraction)),"
                      + " ring median \(fmt(r.ringMedianMm)) mm, supporting \(r.supporting),"
                      + " crossed \(r.crossed), candidates \(r.candidateCount)")
            }
            print("  spread at the food \(fmt(spread)) mm;"
                  + " crossed counts \(Set(rolls.map(\.crossed)).sorted());"
                  + " supporting counts \(Set(rolls.map(\.supporting)).sorted())")
        }

        // The caveat. The shipped radius's reading is ONE draw, and a different draw of the
        // same capture puts the plane elsewhere — further than the 1 mm Decision 35 measures
        // the grid transfer at. This is NOT a Req 5.1 failure: the seed is
        // `Fnv1a64.hash(depthBytesMm)`, so identical bytes draw identically and replay
        // reproduces device exactly, which is what the requirement asks. What it bounds is
        // how much of any plane-at-the-food figure this feature quotes is the capture and
        // how much is the draw.
        let widest = spreadByCapture.values.max() ?? 0
        print("selection spread under the seed alone:"
              + " \(spreadByCapture.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against the \(fmt(Self.gridTransferToleranceMm)) mm Decision 35 measures"
              + " the Req 5.1 grid transfer at")
        let stable = "candidate selection no longer moves the plane at the food under the"
            + " RANSAC seed alone (\(fmt(widest)) mm) — the caveat this records is gone and"
            + " the corpus's plane figures are properties of the captures outright"
        #expect(widest > Self.gridTransferToleranceMm, "\(stable)")

        // And the reassurance, which is what licenses every bracket the feature has read
        // off one draw. The plane moves; the SECTOR VERDICT does not. Across eight draws
        // per capture the supporting and crossed counts are single-valued, so Decisions 40
        // to 45 are reading a property of the captures even though the plane behind it is
        // a draw. It is also what separates this control from the radius sweep, where the
        // intended candidate's crossed count alternates 0 and 2 at 1 mm steps: the radius
        // reorders the candidates, it does not merely re-roll them.
        let verdictsStable = seedVerdicts.allSatisfy { $0.value.crossed.count == 1
                                                       && $0.value.supporting.count == 1 }
        print("sector verdicts under the seed:"
              + " \(seedVerdicts.map { "\($0.key) crossed \($0.value.crossed.sorted()) supporting \($0.value.supporting.sorted())" }.sorted().joined(separator: ", "))")
        let verdictMoved = "the sector verdict now moves with the RANSAC seed"
            + " (\(seedVerdicts)) — the brackets Decisions 40-45 read off one draw per"
            + " capture are properties of that draw and must be re-read across seeds"
        #expect(verdictsStable, "\(verdictMoved)")
    }

    static let seedRolls = 8

    // One committed scene re-ringed at a radius other than the shipped one. The plane is
    // the scene's own, so only the ring geometry moves.
    static func sceneSigns(_ spec: SceneSpec, outerMm: Float) -> SectorSigns? {
        guard let g = SupportRegion.prepare(
            depth: SPRScene.makeDepth(spec.grid),
            colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: SPRScene.makeColourMask(spec.grid)) else { return nil }
        let p = SPRScene.plane(atHeightMm: spec.planeHeightMm)
        return sectorSigns(samples: ringSamples(geometry: g, outerMm: outerMm),
                           geometry: g, normal: p.normal, d: p.d,
                           count: SupportRegion.ringSectorCount)
    }

    // MARK: - The band count, and what it divides

    // `ringBandCount` is the only constant in the ring geometry carrying NO provenance
    // marker at all. Every neighbour is `[measured]`, `[inherited]`, `[derived]` or
    // `[owed]`; this one says "Structural: inner / mid / outer", which is an assertion
    // wearing a different word. It has never been varied.
    //
    // Decision 46 is what makes that a gap rather than a tidiness complaint. It found the
    // radius upstream of the count and the bar because the sector rule reads the INNER
    // BAND, whose outer edge is `ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount`
    // — and then swept only the numerator. The divisor sets the same edge. Worse, it
    // divides in two places at once: the inner band the sector rule reads, and the band
    // partition `ringMinSamples` is floored PER member of, so raising it narrows the arcs
    // and starves them in the same move.
    //
    // Three properties distinguish it from the other three. It does NOT move the annulus,
    // so unlike the radius the candidate SET is fixed. It does move which candidate is
    // SELECTED, since `bestCandidate` ranks on inner-band support and the inner band is
    // what this divides — so unlike the count and the bar it is not purely a re-reading.
    // And it is the only one of the four that a guard's existence bounds from below:
    // `admissibility` reads `bandMedianMm[1] − bandMedianMm[0]` behind a `count > 1` test,
    // so at one band the `bandStep` guard does not fire and does not report that it did not.
    //
    // 1 is included to measure that floor rather than assume it. Above 8 the bands are
    // narrower than 2.2 mm at the shipped radius, roughly half a depth pixel at corpus
    // range, so the sweep stops where the partition stops meaning anything.
    static let ringBandCountSweep = [1, 2, 3, 4, 5, 6, 7, 8, 10]

    @Test("the band count is the radial divisor of the sector rule, and it was never structural")
    func theBandCountIsTheRadialDivisorOfTheSectorRule() throws {
        let specs = Self.sceneSpecs()
        #expect(specs.count == 8, "a scene stopped producing a spec")
        let mustPass = specs.filter { $0.requiresPass.contains(.sectors) }
        let mustFire = specs.filter { $0.requiresFire.contains(.sectors) }
        let stepPass = specs.filter { $0.requiresPass.contains(.bandStep) }
        let stepFire = specs.filter { $0.requiresFire.contains(.bandStep) }

        struct Corpus {
            let name: String
            let signs: SectorSigns
            let bandCounts: [Int]
            let bandMediansMm: [Float]
            let planeAtFoodMm: Float
            let normal: Vec3
            let candidateD: Float
            var feasible: Bool {
                bandCounts.allSatisfy { $0 >= SupportRegion.ringMinSamples }
            }
            // The quantity `bandStepMaxMm` is read against. Undefined at one band, which
            // is the point of measuring there.
            var stepMm: Float? {
                bandMediansMm.count > 1 ? bandMediansMm[1] - bandMediansMm[0] : nil
            }
        }

        struct Bands {
            let count: Int
            let innerBandOuterMm: Float
            let bandWidthMm: Float
            let corpus: [Corpus]
            // `maxCrossedSectors`, Decision 43's two constraint sets at this band count.
            let corpusFloor: Int, corpusCeiling: Int
            let suiteFloor: Int, suiteCeiling: Int
            // `minSupportingSectors`, the unsigned count Decision 41 found contradictory.
            let countCorpusCeiling: Int
            let countSuiteFloor: Int, countSuiteCeiling: Int
            // `bandStepMaxMm`'s suite interval, which is a difference between two of the
            // bands this constant creates and so is denominated in it.
            let stepFloorMm: Float?, stepCeilingMm: Float?
            // Req 5.1's 2× depth-grid halving, the bound Decision 44 read the count's
            // ceiling off and Decision 46 the radius's floor.
            let halvedBandCounts: [String: [Int]]
            var halvedFeasible: Bool {
                halvedBandCounts.values.allSatisfy {
                    $0.allSatisfy { $0 >= SupportRegion.ringMinSamples }
                }
            }
            var jointFloor: Int { max(corpusFloor, suiteFloor) }
            var jointCeiling: Int { min(corpusCeiling, suiteCeiling) }
            var jointFeasible: Bool { jointFloor <= jointCeiling }
            var countJointFloor: Int { countSuiteFloor }
            var countJointCeiling: Int { min(countCorpusCeiling, countSuiteCeiling) }
            var feasible: Bool { corpus.allSatisfy(\.feasible) }
            // Whether the `bandStep` guard can run at all here.
            var stepGuardRuns: Bool { count > 1 }
        }

        var halvedGeometry: [String: SupportRegion.DepthGeometry] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            halvedGeometry[name] = Self.geometry(slice, decimation: 2)
        }

        var swept: [Bands] = []
        for count in Self.ringBandCountSweep {
            var corpus: [Corpus] = []
            var halvedBands: [String: [Int]] = [:]
            for name in Self.captures {
                let slice = try DepthSlice.load(name)
                let g = try #require(Self.geometry(name))
                halvedBands[name] = Self.bandSampleCounts(
                    Self.ringSamples(geometry: try #require(halvedGeometry[name]),
                                     bandCount: count),
                    bandCount: count)
                let samples = Self.ringSamples(geometry: g, bandCount: count)
                // Re-read, not re-extracted. The annulus is `annulusOuterMm` and does
                // not move with the band count, so the candidate set is the shipped
                // one — but selection ranks on inner-band support, and that is what
                // this constant divides.
                var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
                let candidates = SupportRegion.extractCandidates(
                    annulus: samples.annulus, geometry: g,
                    gravity: slice.gravity.normalised(), rng: &rng)
                let best = try #require(candidates.max {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: $0.normal, d: $0.d)
                    < Self.innerSupportFraction(samples: samples, geometry: g,
                                                normal: $1.normal, d: $1.d)
                }, "no candidate survives at ringBandCount = \(count)")
                corpus.append(Corpus(
                    name: name,
                    signs: Self.sectorSigns(samples: samples, geometry: g,
                                            normal: best.normal, d: best.d,
                                            count: SupportRegion.ringSectorCount),
                    bandCounts: Self.bandSampleCounts(samples, bandCount: count),
                    bandMediansMm: Self.bandMediansMm(samples: samples, geometry: g,
                                                      normal: best.normal, d: best.d,
                                                      bandCount: count),
                    planeAtFoodMm: Self.planeDepthMm(
                        normal: best.normal, d: best.d,
                        ray: try #require(Self.foodCentroidRay(slice))),
                    normal: best.normal,
                    candidateD: best.d))
            }
            let plate = try #require(corpus.first { $0.name == "1785135663727" })
            let table = try #require(corpus.first { $0.name == "1785901032716" })
            let passSigns = try mustPass.map { try #require(Self.sceneSigns($0, bandCount: count)) }
            let fireSigns = try mustFire.map { try #require(Self.sceneSigns($0, bandCount: count)) }
            let passSteps = try stepPass.compactMap { try Self.sceneStepMm($0, bandCount: count) }
            let fireSteps = try stepFire.compactMap { try Self.sceneStepMm($0, bandCount: count) }
            swept.append(Bands(
                count: count,
                innerBandOuterMm: SupportRegion.ringInnerMm
                    + (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / Float(count),
                bandWidthMm: (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / Float(count),
                corpus: corpus,
                corpusFloor: plate.signs.crossedFailing,
                corpusCeiling: table.signs.crossedFailing - 1,
                suiteFloor: passSigns.map(\.crossedFailing).max() ?? 0,
                suiteCeiling: (fireSigns.map(\.crossedFailing).min() ?? 0) - 1,
                countCorpusCeiling: plate.signs.supporting,
                countSuiteFloor: (fireSigns.map(\.supporting).max() ?? 0) + 1,
                countSuiteCeiling: passSigns.map(\.supporting).min() ?? 0,
                stepFloorMm: passSteps.max(),
                stepCeilingMm: fireSteps.min(),
                halvedBandCounts: halvedBands))
        }

        let shippedBands = try #require(swept.first { $0.count == SupportRegion.ringBandCount })
        var shippedPlaneAtFood: [String: Float] = [:]
        for c in shippedBands.corpus { shippedPlaneAtFood[c.name] = c.planeAtFoodMm }

        for b in swept {
            print("ringBandCount=\(b.count) (bands \(fmt(b.bandWidthMm)) mm wide,"
                  + " inner band ends \(fmt(b.innerBandOuterMm)) mm,"
                  + " bandStep guard \(b.stepGuardRuns ? "runs" : "SILENT")):")
            for c in b.corpus {
                print("  \(c.name): bands \(c.bandCounts)"
                      + " \(c.feasible ? "feasible" : "REFUSED"),"
                      + " medians \(c.bandMediansMm.map { fmt($0) }),"
                      + " inner→mid \(c.stepMm.map { fmt($0) } ?? "n/a") mm,"
                      + " PLANE AT FOOD \(fmt(c.planeAtFoodMm)) mm"
                      + " (\(fmt(c.planeAtFoodMm - (shippedPlaneAtFood[c.name] ?? c.planeAtFoodMm)))"
                      + " vs shipped),"
                      + " supporting \(c.signs.supporting), failing \(c.signs.failing.count),"
                      + " crossed \(c.signs.crossedFailing), escaped \(c.signs.escapedFailing)")
            }
            print("  maxCrossedSectors corpus \(b.corpusFloor)…\(b.corpusCeiling),"
                  + " suite \(b.suiteFloor)…\(b.suiteCeiling),"
                  + " joint \(b.jointFloor)…\(b.jointCeiling)"
                  + " \(b.jointFeasible ? "" : "EMPTY");"
                  + " minSupportingSectors corpus ≤ \(b.countCorpusCeiling),"
                  + " suite \(b.countSuiteFloor)…\(b.countSuiteCeiling)")
            print("  bandStepMaxMm suite \(b.stepFloorMm.map { fmt($0) } ?? "n/a")…"
                  + "\(b.stepCeilingMm.map { fmt($0) } ?? "n/a") mm;"
                  + " Req 5.1 halved bands \(b.halvedBandCounts)"
                  + " \(b.halvedFeasible ? "feasible" : "REFUSED")")
        }

        // Anchor. At three bands this must reproduce Decisions 41, 43 and 45 exactly, or
        // the re-banding has diverged from `SupportRegion.ringSamples` and nothing below
        // is a measurement of the band count.
        let anchor = "re-banding at ringBandCount no longer reproduces the recorded reading"
            + " (crossed joint \(shippedBands.jointFloor)…\(shippedBands.jointCeiling), count"
            + " suite floor \(shippedBands.countSuiteFloor), corpus ceiling"
            + " \(shippedBands.countCorpusCeiling), bandStep suite"
            + " \(shippedBands.stepFloorMm.map { fmt($0) } ?? "n/a")…"
            + "\(shippedBands.stepCeilingMm.map { fmt($0) } ?? "n/a") mm) — the sweep is not"
            + " measuring the same ring Decisions 41, 43 and 45 measured"
        #expect(shippedBands.jointFloor == 0 && shippedBands.jointCeiling == 2
                && shippedBands.countSuiteFloor == 6
                && shippedBands.countCorpusCeiling == 5
                && abs((shippedBands.stepCeilingMm ?? 0) - 9.288) < 0.01, "\(anchor)")

        // THE NEGATIVE FIRST, because it is what places this constant among the other
        // three. Decision 46 found the radius moves the SELECTED plane, 18.719 mm at the
        // food, and attributed it to the annulus moving with it. That attribution is now
        // tested rather than argued: the band count leaves the annulus at annulusOuterMm,
        // so the candidate SET is fixed — but selection ranks on inner-band support and
        // this constant is what divides the inner band, so the ranking could still have
        // moved. It does not, anywhere in the sweep, on either capture. Decision 46's
        // "moves the answer" is a property of the annulus specifically, not of radial
        // geometry generally.
        var planeSpan: [String: Float] = [:]
        for b in swept {
            for c in b.corpus {
                let shipped = shippedPlaneAtFood[c.name] ?? c.planeAtFoodMm
                planeSpan[c.name] = max(planeSpan[c.name] ?? 0, abs(c.planeAtFoodMm - shipped))
            }
        }
        let widestPlane = planeSpan.values.max() ?? 0
        print("plane movement at the food over the band-count sweep:"
              + " \(planeSpan.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm and Decision"
              + " 46's 18.719 mm on the radius")
        let moves = "the band count now moves the selected plane at the food"
            + " (\(fmt(widestPlane)) mm) — it has joined ringOuterMm as a constant that"
            + " moves the ANSWER, and the session must fix it before any plane figure is"
            + " quoted rather than only before the brackets are read"
        #expect(widestPlane <= Self.gridTransferToleranceMm, "\(moves)")

        // THE FLOOR, and it is unlike any other bound in this feature: it comes from a
        // guard's EXISTENCE rather than from a measurement. At one band there is no mid
        // band, `admissibility` skips the `bandStep` test on a `bandMedianMm.count > 1`
        // guard, and the two scenes the suite commits to rejecting on that guard are
        // admitted in silence — the shape of failure Decision 18 exists to prevent,
        // arriving through a constant nobody was watching.
        let silent = swept.filter { !$0.stepGuardRuns }.map(\.count)
        print("band counts at which the bandStep guard cannot run: \(silent);"
              + " scenes asserting on it: \(stepFire.map(\.label))")
        let stepAlwaysRuns = "the bandStep guard now runs at every band count in the sweep"
            + " — the structural floor of 2 this records is gone"
        #expect(!silent.isEmpty && !stepFire.isEmpty, "\(stepAlwaysRuns)")

        // The same floor arrives a SECOND way, and this one is Decision 41's prediction on
        // a third constant. At one band the inner band IS the whole 8…25 mm ring, so the
        // rims the rimmed-plate scenes place at fixed pixel radii fall inside it and a
        // scene that must PASS reads every sector crossed. Both suite intervals go empty
        // together, exactly as they do at the radius's ceiling (Decision 46).
        let oneBand = try #require(swept.first { $0.count == 1 })
        print("at one band: maxCrossedSectors suite \(oneBand.suiteFloor)…\(oneBand.suiteCeiling)"
              + " \(oneBand.jointFeasible ? "" : "EMPTY"),"
              + " minSupportingSectors suite \(oneBand.countSuiteFloor)…\(oneBand.countSuiteCeiling)")
        let oneBandAdmissible = "the committed suite now admits a single band — the second,"
            + " independent floor this records is gone and only the bandStep guard's"
            + " existence keeps ringBandCount above 1"
        #expect(!oneBand.jointFeasible
                && oneBand.countSuiteFloor > oneBand.countSuiteCeiling, "\(oneBandAdmissible)")

        // THE CEILING, and it is Req 5.1's for the third time. Decision 44 read it on the
        // sector count, Decision 46 on the radius; the same 2× halving reads it here,
        // because `ringMinSamples` is floored PER band and this constant is how many bands
        // there are. One partition, three constants dividing it, one bound — and this is
        // the constant that divides it most directly, so the ceiling lands hardest: the
        // halving refuses four bands outright.
        let transfers = swept.filter(\.halvedFeasible).map(\.count)
        let ceiling = transfers.max() ?? 0
        print("band counts at which the ring survives the Req 5.1 halving: \(transfers)"
              + " — ceiling \(ceiling); ringBandCount bracketed 2…\(ceiling)")
        let noCeiling = "the Req 5.1 halving no longer refuses any band count in the sweep"
            + " — the ceiling this records is gone and ringBandCount is bounded only from"
            + " below"
        #expect(ceiling < Self.ringBandCountSweep.max() ?? 0, "\(noCeiling)")
        // Which leaves a bracket of TWO VALUES, the tightest any owed constant in this
        // feature has, with the shipped value on its ceiling — the position Decision 45
        // found `sectorSupportMin` in.
        let shippedInside = "the shipped ringBandCount has left the bracket its own"
            + " constraints produce (2…\(ceiling))"
        #expect(SupportRegion.ringBandCount >= 2
                && SupportRegion.ringBandCount <= ceiling, "\(shippedInside)")
        let wide = "ringBandCount's bracket (2…\(ceiling)) has stopped being a two-value"
            + " choice — the claim that it is the tightest bracket in the feature no"
            + " longer holds"
        #expect(ceiling - 2 == 1, "\(wide)")

        // And it denominates `bandStepMaxMm`, the constant it most obviously owns: the step
        // is a difference between two bands this constant creates, so narrowing them moves
        // the quantity the bar is read against. The suite interval does not merely shift —
        // it COLLAPSES and then INVERTS, because a rim spanning a fixed radial distance
        // stops being a step between adjacent bands once the bands are narrower than it.
        // Decision 41's 0.024…9.288 mm is a reading at three bands and says so nowhere.
        let stepIntervals = swept.compactMap { b -> String? in
            guard let lo = b.stepFloorMm, let hi = b.stepCeilingMm else { return nil }
            return "\(b.count): \(fmt(lo))…\(fmt(hi))"
        }
        let stepEmpty = swept.filter {
            guard let lo = $0.stepFloorMm, let hi = $0.stepCeilingMm else { return false }
            return lo > hi
        }.map(\.count)
        print("bandStepMaxMm suite intervals over the band-count sweep: \(stepIntervals);"
              + " empty at \(stepEmpty)")
        let stepInvariant = "bandStepMaxMm's suite interval no longer goes empty anywhere in"
            + " the band-count sweep — it is not denominated in ringBandCount and Decision"
            + " 41's interval can be quoted without one"
        #expect(!stepEmpty.isEmpty, "\(stepInvariant)")
        // The two shipped values are consistent, but only just, and by a margin nothing
        // records: `bandStepMaxMm = 6` is admissible at 2, 3 and 4 bands and above the
        // suite's ceiling from 5 up. That is inside the Req 5.1 bracket, so the pair does
        // not collide — the coupling is real and currently harmless.
        let stepAdmits = swept.filter {
            guard let lo = $0.stepFloorMm, let hi = $0.stepCeilingMm else { return false }
            return SupportRegion.bandStepMaxMm >= lo && SupportRegion.bandStepMaxMm < hi
        }.map(\.count)
        print("band counts at which the shipped bandStepMaxMm"
              + " (\(fmt(SupportRegion.bandStepMaxMm)) mm) stays inside the suite:"
              + " \(stepAdmits) — against the Req 5.1 bracket 2…\(ceiling)")
        let collides = "the shipped bandStepMaxMm no longer survives every band count Req"
            + " 5.1 permits (\(stepAdmits) against 2…\(ceiling)) — the two constants now"
            + " collide and the pair must be set together"
        #expect((2...ceiling).allSatisfy { stepAdmits.contains($0) }, "\(collides)")

        // And it denominates `maxCrossedSectors` too, which makes a FOURTH. Decision 44
        // recorded that constant as a count of sectors, Decision 45 as a count read at a
        // bar, Decision 46 as a count read at a radius; it is also a count read at a band
        // count. The joint bracket is 1…2 at two bands and 0…2 at three — so Decision 43's
        // headline, that 0 is admissible and nothing in hand narrows 0…2, is a reading at
        // three bands. What moves it is Decision 43's own recorded blind spot: the
        // rimmed-plate rims "never reach the inner band" at three bands, and at two the
        // inner band ends at 16.5 mm instead of 13.667 and one of them does.
        let jointBrackets = swept.filter(\.jointFeasible).map {
            "\($0.count): \($0.jointFloor)…\($0.jointCeiling)"
        }
        print("joint maxCrossedSectors brackets over the band-count sweep: \(jointBrackets)")
        let bandInvariant = "maxCrossedSectors reads one bracket at every band count the"
            + " suite admits (\(jointBrackets)) — it is not denominated in ringBandCount"
            + " and Decision 43's 0…2 can be quoted without one"
        #expect(Set(swept.filter(\.jointFeasible).map { "\($0.jointFloor)…\($0.jointCeiling)" })
                    .count > 1, "\(bandInvariant)")

        // The reassurance, and it is the same one Decision 44 found for the sector count.
        // Whatever the divisor, the rule still tells the two corpus candidates apart: the
        // plate-top candidate a correct fit must admit reads no crossed sector at every
        // band count, and the table candidate reads at least three at all of them. The
        // brackets move; the separation does not.
        let separated = swept.allSatisfy { b in
            guard let plate = b.corpus.first(where: { $0.name == "1785135663727" }),
                  let table = b.corpus.first(where: { $0.name == "1785901032716" })
            else { return false }
            return plate.signs.crossedFailing < table.signs.crossedFailing
        }
        print("crossed counts per band count — plate"
              + " \(swept.map { $0.corpus.first { $0.name == "1785135663727" }?.signs.crossedFailing ?? -1 }),"
              + " table"
              + " \(swept.map { $0.corpus.first { $0.name == "1785901032716" }?.signs.crossedFailing ?? -1 })")
        let averaged = "the crossed-sector rule no longer separates the two corpus"
            + " candidates at every band count — the divisor can average the crossing away"
            + " and Decision 40's rule is a property of the shipped partition"
        #expect(separated, "\(averaged)")
    }

    // `ringSamples`'s radial banding with the BAND COUNT as a parameter. Everything else —
    // the distance transform, `ringInnerMm`, `ringOuterMm`, `annulusOuterMm`, the
    // validity and food-mask exclusions, the sector bucketing — is the shipped path's, so
    // at `ringBandCount` it reproduces `ringSamples` exactly.
    //
    // Note what does NOT move with it. The annulus is `annulusOuterMm`, so the candidate
    // set is untouched: this constant divides the ring it is given rather than resizing it.
    // What does move is the inner band, `ringInnerMm …  ringInnerMm + (ringOuterMm −
    // ringInnerMm) / bandCount`, which is both what the sector rule reads and what
    // selection ranks on.
    static func ringSamples(geometry g: SupportRegion.DepthGeometry,
                            bandCount: Int) -> SupportRegion.RingSamples {
        let distancePx = SupportRegion.distanceToFoodPx(mask: g.foodMask)
        let bandWidthMm = (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / Float(bandCount)
        let annulusOuterMm = SupportRegion.annulusOuterMm
        var ring: [Int] = [], band: [Int] = [], sector: [Int] = [], annulus: [Int] = []
        guard bandWidthMm > 0 else {
            return SupportRegion.RingSamples(ring: ring, band: band, sector: sector,
                                             annulus: annulus)
        }
        for y in 0..<g.height {
            for x in 0..<g.width {
                let idx = y * g.width + x
                guard g.valid[idx], !g.foodMask.isFood(x: x, y: y) else { continue }
                let distMm = distancePx[idx] * g.mmPerPx
                guard distMm <= annulusOuterMm else { continue }
                annulus.append(idx)
                guard distMm >= SupportRegion.ringInnerMm,
                      distMm <= SupportRegion.ringOuterMm else { continue }
                let b = min(bandCount - 1,
                            Int((distMm - SupportRegion.ringInnerMm) / bandWidthMm))
                ring.append(idx)
                band.append(b)
                sector.append(b == 0 ? SupportRegion.sectorIndex(x: x, y: y, geometry: g) : -1)
            }
        }
        return SupportRegion.RingSamples(ring: ring, band: band, sector: sector,
                                         annulus: annulus)
    }

    static func bandSampleCounts(_ samples: SupportRegion.RingSamples,
                                 bandCount: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: bandCount)
        for band in samples.band { counts[band] += 1 }
        return counts
    }

    // `ringStatistics`'s `bandMedianMm` at a band count other than the shipped one, and
    // without its `ringMinSamples` guard, so a partition the floor refuses can still be
    // read. `SupportRegion.median` rather than a middle element, since it averages the two
    // central values on an even count and the step is a difference of two of these — using
    // anything else moves Decision 41's ceiling by 8 µm and the anchor below would not
    // reproduce. An empty band reads NaN rather than being dropped, since dropping it
    // would renumber the bands the step is taken between.
    static func bandMediansMm(samples: SupportRegion.RingSamples,
                              geometry g: SupportRegion.DepthGeometry,
                              normal: Vec3, d: Float, bandCount: Int) -> [Float] {
        var heights = [[Float]](repeating: [], count: bandCount)
        for (i, idx) in samples.ring.enumerated() {
            heights[samples.band[i]].append(normal.dot(g.points[idx]) - d)
        }
        return heights.map { $0.isEmpty ? .nan : SupportRegion.median($0) }
    }

    // One committed scene re-banded at a band count other than the shipped one. The plane
    // is the scene's own, so only the radial partition moves.
    static func sceneSigns(_ spec: SceneSpec, bandCount: Int) -> SectorSigns? {
        guard let g = SupportRegion.prepare(
            depth: SPRScene.makeDepth(spec.grid),
            colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: SPRScene.makeColourMask(spec.grid)) else { return nil }
        let p = SPRScene.plane(atHeightMm: spec.planeHeightMm)
        return sectorSigns(samples: ringSamples(geometry: g, bandCount: bandCount),
                           geometry: g, normal: p.normal, d: p.d,
                           count: SupportRegion.ringSectorCount)
    }

    // The inner→mid step a committed scene reads at a given band count — the quantity
    // `bandStepMaxMm` is asserted against. nil at one band, where there is no mid band
    // and the guard cannot run.
    static func sceneStepMm(_ spec: SceneSpec, bandCount: Int) throws -> Float? {
        guard bandCount > 1 else { return nil }
        guard let g = SupportRegion.prepare(
            depth: SPRScene.makeDepth(spec.grid),
            colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: SPRScene.makeColourMask(spec.grid)) else { return nil }
        let p = SPRScene.plane(atHeightMm: spec.planeHeightMm)
        let medians = bandMediansMm(samples: ringSamples(geometry: g, bandCount: bandCount),
                                    geometry: g, normal: p.normal, d: p.d,
                                    bandCount: bandCount)
        guard medians.count > 1, !medians[0].isNaN, !medians[1].isNaN else { return nil }
        return medians[1] - medians[0]
    }

    // MARK: - The pass cap, and what it is the cap ON

    // Decision 47 closed the ring geometry: every constant the sector measure reads now
    // carries a provenance marker. `maxCandidatePlanes` is outside it, in extraction, and
    // it carries the same kind of comment the band count did — "Structural: table,
    // support, one more" — with no marker at all. It has never been varied either.
    //
    // Decision 46 is what makes it worth varying. That decision found the radius moves the
    // selected plane BECAUSE it moves the annulus, and Decision 47 confirmed the
    // attribution by moving radial geometry without moving the annulus and watching the
    // plane stand still. The annulus is the sample set extraction draws from; this
    // constant is how many times it may draw. It is the second constant that changes
    // which planes COMPETE, and the only one that can add a candidate rather than
    // reshuffle the set.
    //
    // 8 is above anything the corpus can plausibly use and is there to find where
    // extraction stops on its own. 1 is there because a cap of 1 is the pre-feature
    // single-plane fit, which is the floor a sequential design has to beat.
    static let maxCandidatePlanesSweep = [1, 2, 3, 4, 5, 6, 8]

    // `SupportRegion.extractCandidates` with the pass cap as an argument. Every other
    // line is the shipped path's — the same `ccRansac`, the same consensus polish, the
    // same `minResidueSamples` floor, the same inlier removal — so at
    // `maxCandidatePlanes` it reproduces the shipped call exactly, which the anchor below
    // checks candidate by candidate.
    //
    // The passes are a PREFIX chain: pass n reads only the residue pass n−1 left and the
    // rng state it left, so a run at a higher cap contains a run at a lower one verbatim.
    // That is why one run at the sweep's top measures every cap below it, and why a cap
    // can only ever truncate — it can never change a candidate the shorter run produced.
    //
    // The removal multiple is an argument too, since Decision 50. It is the only shipped
    // constant that acts BETWEEN passes, so a sweep of it needs the same chain replayed at
    // a different shell width; at `SupportRegion.inlierRemovalMultiple` this reproduces the
    // shipped call exactly, which both anchors below check candidate by candidate.
    static func extractCandidates(
        annulus: [Int], geometry g: SupportRegion.DepthGeometry,
        gravity: Vec3, rng: inout SplitMix64,
        maxPasses: Int,
        removalMultiple: Float = SupportRegion.inlierRemovalMultiple
    ) -> [SupportRegion.PlaneCandidate] {
        var residue = annulus
        var candidates: [SupportRegion.PlaneCandidate] = []
        let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)
        let residueFloor = SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)

        for _ in 0..<maxPasses {
            guard residue.count >= residueFloor else { break }
            guard let hypothesis = SupportRegion.ccRansac(
                indices: residue, geometry: g, gravity: gravity,
                rng: &rng, scratch: scratch) else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1

            for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue
                where abs(normal.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers || next.count < LiDARPlaneFitter.minPoints { break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { break }
                if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity)))
                    > LiDARPlaneFitter.gravityAngleMaxRad {
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
            }

            let component = scratch.largestComponent(of: inliers)
            candidates.append(SupportRegion.PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count))

            let removalBandMm = removalMultiple * LiDARPlaneFitter.inlierBandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return candidates
    }

    @Test("the pass cap is what stops extraction on the corpus, and it is not marked")
    func thePassCapIsWhatStopsExtractionOnTheCorpus() throws {
        struct Pass {
            let index: Int
            let residueCount: Int
            let residueAreaMm2: Float
            let planeAtFoodMm: Float
            let innerSupport: Float
            let extentMm: Float
            let componentSize: Int
            let residualMm: Float
            let signs: SectorSigns
            let envelopeMm: Float
            let annulusMedianMm: Float
            // Req 3.1's own quantity: the ring's median signed height above the plane. The
            // candidate a correct fit must select is the one nearest zero, which is how
            // Decisions 42 and 46 identify it, and it is NOT always the highest-support one.
            let ringMedianMm: Float
            let rejections: [SupportRegion.CandidateRejection]
            var admissible: Bool { rejections.isEmpty }
            // The guards that are not `[owed]`. Decision 42 sweeps the owed bars and holds
            // these fixed; the same split is what makes a selection here readable.
            var rejectedByInherited: Bool {
                rejections.contains(.ringMedian) || rejections.contains(.escaped)
            }
        }
        struct Capture {
            let name: String
            let residueFloor: Int
            let pixelAreaMm2: Float
            let passes: [Pass]
            let halvedPassCount: Int
            // What is left in the annulus after the last pass took its inliers. This is
            // what says whether extraction stopped because it ran out of surface or
            // because the cap said so.
            let residueAfterLastPass: Int
            var naturalDepth: Int { passes.count }
            var starved: Bool { residueAfterLastPass < residueFloor }
        }

        let sweepTop = try #require(Self.maxCandidatePlanesSweep.max())
        var captures: [Capture] = []

        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let ray = try #require(Self.foodCentroidRay(slice))
            let gravity = slice.gravity.normalised()

            var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
            let deep = Self.extractCandidates(annulus: samples.annulus, geometry: g,
                                              gravity: gravity, rng: &rng,
                                              maxPasses: sweepTop)

            // The anchor. A prefix of the deep run must BE the shipped run, or the sweep
            // is measuring a different extraction and nothing below says anything about
            // `maxCandidatePlanes`.
            let shipped = try #require(Self.candidates(name))
            let drift = "\(name): the parameterised extraction no longer reproduces"
                + " SupportRegion.extractCandidates at maxCandidatePlanes"
                + " (\(shipped.count) shipped, \(deep.prefix(SupportRegion.maxCandidatePlanes).count)"
                + " in the prefix) — the pass cap sweep is not measuring the shipped path"
            #expect(shipped.count == deep.prefix(SupportRegion.maxCandidatePlanes).count, "\(drift)")
            for (a, b) in zip(shipped, deep) {
                #expect(a.d == b.d && a.normal == b.normal
                        && a.componentSize == b.componentSize
                        && a.residueCount == b.residueCount, "\(drift)")
            }

            let pixelAreaMm2 = g.mmPerPx * g.mmPerPx
            var passes: [Pass] = []
            for (i, c) in deep.enumerated() {
                let annulusMedianMm = SupportRegion.medianHeight(
                    indices: samples.annulus, geometry: g, normal: c.normal, d: c.d)
                let envelopeMm = SupportRegion.foodEnvelopeMm(
                    geometry: g, normal: c.normal, d: c.d)
                var rejections: [SupportRegion.CandidateRejection] = []
                var ringMedianMm = Float.nan
                if let ring = SupportRegion.ringStatistics(samples: samples, geometry: g,
                                                           normal: c.normal, d: c.d) {
                    rejections = Self.allRejections(CandidateMeasurement(
                        candidate: c, ring: ring, annulusMedianMm: annulusMedianMm,
                        envelopeMm: envelopeMm))
                    ringMedianMm = ring.medianMm
                }
                passes.append(Pass(
                    index: i,
                    residueCount: c.residueCount,
                    residueAreaMm2: Float(c.residueCount) * pixelAreaMm2,
                    planeAtFoodMm: Self.planeDepthMm(normal: c.normal, d: c.d, ray: ray),
                    innerSupport: Self.innerSupportFraction(samples: samples, geometry: g,
                                                            normal: c.normal, d: c.d),
                    extentMm: c.extentMm,
                    componentSize: c.componentSize,
                    residualMm: c.residualMm,
                    signs: Self.sectorSigns(samples: samples, geometry: g,
                                            normal: c.normal, d: c.d),
                    envelopeMm: envelopeMm,
                    annulusMedianMm: annulusMedianMm,
                    ringMedianMm: ringMedianMm,
                    rejections: rejections))
            }

            // Req 5.1's 2× halving, the bound that has now capped three constants. The
            // question here is not whether the ring survives — Decision 38 settled that —
            // but whether the two grids stop at the same DEPTH once the cap is lifted.
            let halvedG = try #require(Self.geometry(slice, decimation: 2))
            let halvedSlice = Self.decimated(slice, by: 2)
            let halvedSamples = SupportRegion.ringSamples(geometry: halvedG)
            var halvedRng = SplitMix64(seed: Fnv1a64.hash(halvedSlice.depth.depthBytesMm))
            let halvedDeep = Self.extractCandidates(
                annulus: halvedSamples.annulus, geometry: halvedG,
                gravity: halvedSlice.gravity.normalised(), rng: &halvedRng,
                maxPasses: sweepTop)

            // The removal chain replayed, so the residue the pass AFTER the last one would
            // have drawn from is a number rather than an inference. Removal is
            // order-dependent and each pass filters what the previous left, which is
            // exactly what this reproduces.
            let removalBandMm = SupportRegion.inlierRemovalMultiple * LiDARPlaneFitter.inlierBandMm
            var residue = samples.annulus
            for c in deep {
                residue = residue.filter { abs(c.normal.dot(g.points[$0]) - c.d) >= removalBandMm }
            }

            captures.append(Capture(
                name: name,
                residueFloor: SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx),
                pixelAreaMm2: pixelAreaMm2,
                passes: passes,
                halvedPassCount: halvedDeep.count,
                residueAfterLastPass: residue.count))
        }

        for c in captures {
            print("=== \(c.name): natural depth \(c.naturalDepth) passes"
                  + " (cap \(SupportRegion.maxCandidatePlanes)),"
                  + " residue floor \(c.residueFloor) samples"
                  + " = \(fmt(SupportRegion.minResidueAreaMm2)) mm²,"
                  + " residue left after the last pass \(c.residueAfterLastPass) samples"
                  + " = \(fmt(Float(c.residueAfterLastPass) * c.pixelAreaMm2)) mm²"
                  + " \(c.starved ? "BELOW the floor — starved" : "ABOVE the floor — the cap stopped it"),"
                  + " halved-grid natural depth \(c.halvedPassCount)")
            for p in c.passes {
                print("  pass \(p.index + 1): residue \(p.residueCount) samples"
                      + " = \(fmt(p.residueAreaMm2)) mm²"
                      + " (\(fmt(p.residueAreaMm2 / SupportRegion.minResidueAreaMm2))× the floor),"
                      + " PLANE AT FOOD \(fmt(p.planeAtFoodMm)) mm,"
                      + " inner support \(fmt(p.innerSupport)),"
                      + " extent \(fmt(p.extentMm)) mm,"
                      + " component \(p.componentSize),"
                      + " residual \(fmt(p.residualMm)) mm,"
                      + " supporting \(p.signs.supporting), crossed \(p.signs.crossedFailing),"
                      + " escaped \(p.signs.escapedFailing),"
                      + " RING MEDIAN \(fmt(p.ringMedianMm)) mm,"
                      + " food envelope \(fmt(p.envelopeMm)) mm,"
                      + " annulus median \(fmt(p.annulusMedianMm)) mm,"
                      + " \(p.admissible ? "ADMISSIBLE" : p.rejections.map(\.rawValue).joined(separator: "+"))")
            }
            for cap in Self.maxCandidatePlanesSweep {
                let prefix = c.passes.prefix(cap)
                guard let best = prefix.max(by: { $0.innerSupport < $1.innerSupport }) else {
                    print("  cap \(cap): no candidate")
                    continue
                }
                // Selection under Decision 40's rule, at every value of `maxCrossedSectors`
                // the two constraint sets leave open (Decision 43's 0…2). The rule rejects
                // first and the shipped ranking picks from what survives, which is the
                // order `fitFoodSupportPlane` applies today with `admissibility` in place
                // of the rule.
                let underRule = (0...2).map { ceiling -> String in
                    let surviving = prefix.filter { $0.signs.crossedFailing <= ceiling }
                    guard let pick = surviving.max(by: { $0.innerSupport < $1.innerSupport })
                    else { return "\(ceiling): FALLBACK" }
                    return "\(ceiling): pass \(pick.index + 1) @ \(fmt(pick.planeAtFoodMm)) mm"
                }
                print("  cap \(cap): \(prefix.count) candidates,"
                      + " selected pass \(best.index + 1) at \(fmt(best.planeAtFoodMm)) mm,"
                      + " inner support \(fmt(best.innerSupport)),"
                      + " crossed \(best.signs.crossedFailing),"
                      + " admissible \(prefix.filter(\.admissible).count)"
                      + " | under Decision 40's rule at maxCrossedSectors"
                      + " [\(underRule.joined(separator: ", "))]")
            }
            // The candidate a correct fit must select, by Req 3.1's own quantity rather
            // than by the ranking — the identification Decisions 42 and 46 make and
            // Decision 43's bracket does not use.
            if let intended = c.passes.min(by: { abs($0.ringMedianMm) < abs($1.ringMedianMm) }) {
                print("  intended by ring median: pass \(intended.index + 1)"
                      + " (ring median \(fmt(intended.ringMedianMm)) mm,"
                      + " crossed \(intended.signs.crossedFailing),"
                      + " inner support \(fmt(intended.innerSupport)),"
                      + " envelope \(fmt(intended.envelopeMm)) mm)"
                      + " — the highest-support candidate is pass"
                      + " \((c.passes.max { $0.innerSupport < $1.innerSupport }?.index ?? 0) + 1)")
            }
        }

        // `maxCrossedSectors` read at FULL pass depth, with the intended candidate
        // identified by Req 3.1's ring median rather than by the ranking. Decision 43 took
        // the floor from the highest-support candidate on each capture, which on
        // `1785901032716` is the table — the plane the guard exists to reject — so its
        // floor was never read off a plane the feature must admit there.
        var crossedFloor = 0, crossedCeiling = Int.max
        for c in captures {
            guard let intended = c.passes.min(by: { abs($0.ringMedianMm) < abs($1.ringMedianMm) })
            else { continue }
            crossedFloor = max(crossedFloor, intended.signs.crossedFailing)
            // Every candidate the feature must NOT select, taken as Decision 43 takes it:
            // the ranking's winner where that is not the intended plane.
            if let ranked = c.passes.max(by: { $0.innerSupport < $1.innerSupport }),
               ranked.index != intended.index {
                crossedCeiling = min(crossedCeiling, ranked.signs.crossedFailing - 1)
            }
        }
        print("maxCrossedSectors at full pass depth: corpus \(crossedFloor)…\(crossedCeiling)"
              + " — against Decision 43's 0…2, whose floor is the highest-support candidate's")

        // THE NEGATIVE FIRST, and it is the opposite of Decision 46's. The cap never
        // truncates: at eight passes both captures still stop at three, and both stop
        // STARVED — the residue left after the last pass is below `minResidueAreaMm2`, so
        // it is the residue floor that ends extraction and the cap has never been reached.
        // Every claim about the value above 3 is therefore unfalsifiable on this corpus.
        for c in captures {
            let binds = "\(c.name) now runs \(c.naturalDepth) passes with the cap lifted to"
                + " \(sweepTop) and \(c.starved ? "starves" : "does NOT starve") — if the cap"
                + " is what stops extraction then maxCandidatePlanes is truncating the"
                + " candidate set and everything Decisions 42-47 read off that set is read"
                + " off a truncation"
            #expect(c.naturalDepth == SupportRegion.maxCandidatePlanes && c.starved, "\(binds)")
        }

        // Which makes Decision 38's repair unconditional. That decision restored the
        // native/halved candidate counts to 3 → 3 by re-denominating the residue floor in
        // mm², and both numbers were AT the cap — so the agreement could have been the cap
        // truncating both. It is not: lift the cap and the two grids still agree.
        for c in captures {
            let truncated = "\(c.name)'s native and halved grids stop at \(c.naturalDepth)"
                + " and \(c.halvedPassCount) passes with the cap lifted — Decision 38's"
                + " 3 → 3 agreement was the cap truncating both, not the area invariance it"
                + " is recorded as"
            #expect(c.halvedPassCount == c.naturalDepth, "\(truncated)")
        }

        // THE FLOOR, and it is the corpus's, not the suite's. On `1785901032716` the plane
        // a correct fit must select is pass 2 — nearest Req 3.1's zero at −2.658 mm — while
        // the RANKING's winner is pass 1, the table, at +3.039 mm. So the intended plane is
        // not in the candidate set at all below a cap of 2, and no setting of any owed
        // constant recovers it: the capture falls back by construction. Decision 18's
        // silent-failure case, arriving one level above the guard that exists to catch it.
        let rankingDisagrees = captures.compactMap { c -> String? in
            guard let intended = c.passes.min(by: { abs($0.ringMedianMm) < abs($1.ringMedianMm) }),
                  let ranked = c.passes.max(by: { $0.innerSupport < $1.innerSupport }),
                  intended.index != ranked.index else { return nil }
            return "\(c.name): intended pass \(intended.index + 1), ranked pass \(ranked.index + 1)"
        }
        print("captures where the ranking's winner is NOT the intended plane:"
              + " \(rankingDisagrees.isEmpty ? ["none"] : rankingDisagrees)")
        let rankingSuffices = "the ranking now picks the intended plane on every corpus"
            + " capture — the pass cap's floor of 2 was read off a disagreement that is gone,"
            + " and sequential extraction is no longer load-bearing on this corpus"
        #expect(!rankingDisagrees.isEmpty, "\(rankingSuffices)")

        // And NO ceiling. Every cap from the natural depth upward produces the same
        // candidates, the same selection and the same verdicts, so the corpus cannot tell
        // 3 from 8. What holds the ceiling open is `minResidueAreaMm2` — itself `[owed]`
        // and bounded from above only (Decision 32) — because it is what stops extraction
        // first. The headroom is the coupling: lower the residue floor below what the
        // corpus leaves after its last pass and the cap starts to bind.
        let headroom = captures.map { c in
            (name: c.name,
             leftMm2: Float(c.residueAfterLastPass) * c.pixelAreaMm2,
             share: Float(c.residueAfterLastPass) * c.pixelAreaMm2 / SupportRegion.minResidueAreaMm2)
        }
        print("residue left after the last pass, against the shipped floor:"
              + " \(headroom.map { "\($0.name) \(fmt($0.leftMm2)) mm² = \(fmt($0.share))× the floor" })"
              + " — a floor below \(fmt(headroom.map(\.leftMm2).max() ?? 0)) mm² gives the"
              + " corpus a fourth pass and the cap something to truncate")
        let noCoupling = "every corpus capture now leaves less than half the residue floor"
            + " after its last pass — the pass cap and minResidueAreaMm2 have stopped being"
            + " coupled and the cap can be given a ceiling without setting the floor first"
        #expect((headroom.map(\.share).max() ?? 0) > 0.5, "\(noCoupling)")

        // THE CONSEQUENCE, and it belongs to another constant. Read at full pass depth with
        // the intended plane identified by Req 3.1's ring median rather than by the ranking,
        // the corpus DETERMINES `maxCrossedSectors` at 2: the intended plane on
        // `1785901032716` carries 2 crossed sectors and the table it must beat carries 3.
        // Decision 43's floor of 0 came from the highest-support candidate on each capture,
        // which on that capture is the table — a plane the guard exists to reject — so its
        // 0…2 was never read off a plane the feature must admit there. This is the first
        // thing in hand that narrows that bracket, and it is a slice at the shipped
        // (radius, count, bar, band count), like every reading since Decision 44.
        let determined = "the corpus no longer determines maxCrossedSectors at full pass"
            + " depth (\(crossedFloor)…\(crossedCeiling)) — Decision 43's 0…2 stands and the"
            + " narrowing this records is gone"
        #expect(crossedFloor == crossedCeiling && crossedFloor == 2, "\(determined)")

        // One side finding, and it is a correction to Decision 34. That decision recorded
        // `foodEnvelopeMinMm` as having no floor because the scenes the guard is written
        // for — a bowl, a plane on the food top — are "negative-envelope cases the corpus
        // does not contain". The corpus does contain one: `1785901032716`'s pass 3 sits
        // 9.736 mm ABOVE the plate, reads 6 escaped sectors, and its envelope is POSITIVE
        // at 7.154 mm. So the guard's own case is reachable with a positive envelope, and
        // the corpus supplies a floor candidate rather than none.
        for c in captures {
            guard let intended = c.passes.min(by: { abs($0.ringMedianMm) < abs($1.ringMedianMm) })
            else { continue }
            let above = c.passes.filter { $0.index != intended.index && $0.ringMedianMm < 0 }
            guard let highest = above.min(by: { $0.envelopeMm < $1.envelopeMm }) else { continue }
            print("\(c.name): a plane above the support surface (pass \(highest.index + 1),"
                  + " ring median \(fmt(highest.ringMedianMm)) mm) has envelope"
                  + " \(fmt(highest.envelopeMm)) mm against the intended plane's"
                  + " \(fmt(intended.envelopeMm)) mm — a foodEnvelopeMinMm floor candidate,"
                  + " where Decision 34 recorded none")
            let noFloor = "\(c.name)'s above-surface candidate now has an envelope at or"
                + " above the intended plane's — the foodEnvelopeMinMm floor candidate this"
                + " records is gone and Decision 34's \"no floor\" stands unqualified"
            #expect(highest.envelopeMm < intended.envelopeMm, "\(noFloor)")
        }
    }

    // MARK: - The candidate bound, and what it is the bound OF

    // The candidate bound is the last constant in this file that decides which planes
    // COMPETE, and the only one of the three that had never been varied. Decision 46 found
    // the radius moves the selected plane 18.719 mm at the food and concluded the movement
    // belongs to the annulus; Decision 47 supported that by moving radial geometry without
    // moving the annulus and watching the plane stand still; Decision 48 varied how many
    // times the annulus may be drawn from. None of the three could vary the annulus ITSELF,
    // because it was written as `annulusOuterMultiple × ringOuterMm` and the radius carried
    // it: the ring and the bound moved together at every value.
    //
    // The sweep is that former multiple's range in millimetres. 25 mm is the degenerate end
    // — the candidate set collapses onto the ring — and 100 mm is wide enough to reach a
    // second surface on a table capture. The shipped 50 mm sits in the middle.
    static let annulusOuterSweep: [Float] = [25, 31.25, 37.5, 43.75, 50, 62.5, 75, 100]

    @Test("the candidate bound is a constant of its own, and it carries the radius's movement")
    func theCandidateBoundIsAConstantOfItsOwn() throws {
        struct Reading {
            let name: String
            let annulusOuterMm: Float
            let annulusSampleCount: Int
            let candidateCount: Int
            let planeAtFoodMm: Float
            let normal: Vec3
            let ringMedianMm: Float
            let supportFraction: Float
            let signs: SectorSigns
            // The candidate a correct fit must select, by Req 3.1's own quantity — the
            // identification Decisions 42, 46 and 48 make.
            let intendedIndex: Int
            let intendedRingMedianMm: Float
            let intendedCrossed: Int
            let selectedIndex: Int
        }

        // Everything a candidate set is read for, at one ring geometry and one bound.
        func read(name: String, slice: DepthSlice, g: SupportRegion.DepthGeometry,
                  ray: Vec3, outerMm: Float, annulusOuterMm: Float) throws -> Reading {
            let samples = Self.ringSamples(geometry: g, outerMm: outerMm,
                                           annulusOuterMm: annulusOuterMm)
            var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
            let candidates = SupportRegion.extractCandidates(
                annulus: samples.annulus, geometry: g,
                gravity: slice.gravity.normalised(), rng: &rng)
            let ringMedians = candidates.map {
                SupportRegion.medianHeight(indices: samples.ring, geometry: g,
                                           normal: $0.normal, d: $0.d)
            }
            let supports = candidates.map {
                Self.innerSupportFraction(samples: samples, geometry: g,
                                          normal: $0.normal, d: $0.d)
            }
            let selected = try #require(
                (0..<candidates.count).max { supports[$0] < supports[$1] },
                "no candidate survives extraction at an annulus of \(fmt(annulusOuterMm)) mm")
            let intended = try #require(
                (0..<candidates.count).min { abs(ringMedians[$0]) < abs(ringMedians[$1]) })
            let best = candidates[selected]
            return Reading(
                name: name,
                annulusOuterMm: annulusOuterMm,
                annulusSampleCount: samples.annulus.count,
                candidateCount: candidates.count,
                planeAtFoodMm: Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray),
                normal: best.normal,
                ringMedianMm: ringMedians[selected],
                supportFraction: supports[selected],
                signs: Self.sectorSigns(samples: samples, geometry: g,
                                        normal: best.normal, d: best.d),
                intendedIndex: intended,
                intendedRingMedianMm: ringMedians[intended],
                intendedCrossed: Self.sectorSigns(
                    samples: samples, geometry: g,
                    normal: candidates[intended].normal,
                    d: candidates[intended].d).crossedFailing,
                selectedIndex: selected)
        }

        struct Capture {
            let name: String
            let slice: DepthSlice
            let g: SupportRegion.DepthGeometry
            let ray: Vec3
        }
        var corpus: [Capture] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            corpus.append(Capture(name: name, slice: slice,
                                  g: try #require(Self.geometry(name)),
                                  ray: try #require(Self.foodCentroidRay(slice))))
        }

        // MARK: the bound swept at the shipped ring

        var byBound: [Float: [Reading]] = [:]
        for boundMm in Self.annulusOuterSweep {
            var readings: [Reading] = []
            for c in corpus {
                readings.append(try read(name: c.name, slice: c.slice, g: c.g, ray: c.ray,
                                         outerMm: SupportRegion.ringOuterMm,
                                         annulusOuterMm: boundMm))
            }
            byBound[boundMm] = readings
        }

        // The anchor. At the shipped bound this must BE the shipped extraction — candidate
        // for candidate — or the sweep is measuring a different annulus and nothing below
        // says anything about `annulusOuterMm`.
        for c in corpus {
            let shipped = try #require(Self.candidates(c.name))
            let samples = Self.ringSamples(geometry: c.g,
                                           outerMm: SupportRegion.ringOuterMm,
                                           annulusOuterMm: SupportRegion.annulusOuterMm)
            var rng = SplitMix64(seed: Fnv1a64.hash(c.slice.depth.depthBytesMm))
            let reproduced = SupportRegion.extractCandidates(
                annulus: samples.annulus, geometry: c.g,
                gravity: c.slice.gravity.normalised(), rng: &rng)
            let drift = "\(c.name): re-ringing with the bound as an argument no longer"
                + " reproduces SupportRegion.ringSamples at annulusOuterMm"
                + " (\(shipped.count) shipped candidates, \(reproduced.count) reproduced)"
                + " — the bound sweep is not measuring the shipped path"
            #expect(shipped.count == reproduced.count, "\(drift)")
            for (a, b) in zip(shipped, reproduced) {
                #expect(a.d == b.d && a.normal == b.normal
                        && a.componentSize == b.componentSize
                        && a.residueCount == b.residueCount, "\(drift)")
            }
        }

        for boundMm in Self.annulusOuterSweep {
            let readings = byBound[boundMm] ?? []
            print("annulusOuterMm=\(fmt(boundMm))"
                  + " (ring fixed at \(fmt(SupportRegion.ringOuterMm)) mm):")
            for r in readings {
                let shippedPlane = byBound[SupportRegion.annulusOuterMm]?
                    .first { $0.name == r.name }
                print("  \(r.name): annulus \(r.annulusSampleCount) samples,"
                      + " candidates \(r.candidateCount),"
                      + " selected pass \(r.selectedIndex + 1),"
                      + " PLANE AT FOOD \(fmt(r.planeAtFoodMm)) mm"
                      + " (\(fmt(r.planeAtFoodMm - (shippedPlane?.planeAtFoodMm ?? r.planeAtFoodMm)))"
                      + " vs shipped, tilt"
                      + " \(fmt(Self.angleDeg(r.normal, shippedPlane?.normal ?? r.normal)))°),"
                      + " ring median \(fmt(r.ringMedianMm)) mm,"
                      + " support \(fmt(r.supportFraction)),"
                      + " supporting \(r.signs.supporting), crossed \(r.signs.crossedFailing),"
                      + " escaped \(r.signs.escapedFailing);"
                      + " intended pass \(r.intendedIndex + 1)"
                      + " (ring median \(fmt(r.intendedRingMedianMm)) mm,"
                      + " crossed \(r.intendedCrossed))")
            }
        }

        // What the bound does to the plane, in Decision 35's units — millimetres of range
        // along the food-centroid ray, the quantity Req 5.1's 1 mm transfer tolerance is
        // stated in and the one volume is integrated in.
        var boundSpan: [String: (lo: Float, hi: Float)] = [:]
        for readings in byBound.values {
            for r in readings {
                let existing = boundSpan[r.name] ?? (r.planeAtFoodMm, r.planeAtFoodMm)
                boundSpan[r.name] = (min(existing.lo, r.planeAtFoodMm),
                                     max(existing.hi, r.planeAtFoodMm))
            }
        }
        let boundSpans = boundSpan.mapValues { $0.hi - $0.lo }
        print("plane movement at the food over the BOUND sweep, ring held fixed:"
              + " \(boundSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm transfer tolerance")

        // `maxCrossedSectors` per bound, read as Decision 48 reads it — the floor off the
        // plane a correct fit must ADMIT (nearest Req 3.1's zero), the ceiling off the
        // ranking's winner where that is a different plane. Decision 48 determined it at 2;
        // this says at which bound.
        var crossedByBound: [Float: (floor: Int, ceiling: Int)] = [:]
        for boundMm in Self.annulusOuterSweep {
            let readings = byBound[boundMm] ?? []
            var floor = 0, ceiling = Int.max
            for r in readings {
                floor = max(floor, r.intendedCrossed)
                if r.selectedIndex != r.intendedIndex {
                    ceiling = min(ceiling, r.signs.crossedFailing - 1)
                }
            }
            crossedByBound[boundMm] = (floor, ceiling)
            print("  bound \(fmt(boundMm)) mm:"
                  + " maxCrossedSectors corpus \(floor)…"
                  + " \(ceiling == Int.max ? "unbounded" : "\(ceiling)")"
                  + " \(floor <= ceiling ? "" : "EMPTY")")
        }

        // The committed suite's leg. The scenes never run extraction — each asserts against
        // a plane its own test states — so the bound reaches them through exactly two
        // guards, `visibility` and `escaped`, both of which read the ANNULUS. That is where
        // a suite bound on this constant can come from, and the only place.
        struct SceneBound {
            let label: String
            let boundMm: Float
            let visibility: Float
            let annulusMedianMm: Float
            let requiresVisibilityPass: Bool
            let requiresEscapePass: Bool
            var holds: Bool {
                (!requiresVisibilityPass || visibility >= SupportRegion.supportVisibilityMin)
                    && (!requiresEscapePass || annulusMedianMm <= SupportRegion.escapeBandMm)
            }
        }
        var sceneBounds: [SceneBound] = []
        for spec in Self.sceneSpecs() {
            guard spec.requiresPass.contains(.visibility)
                    || spec.requiresPass.contains(.escaped) else { continue }
            guard let measured = SPRScene.measure(spec.grid) else { continue }
            let p = SPRScene.plane(atHeightMm: spec.planeHeightMm)
            for boundMm in Self.annulusOuterSweep {
                let samples = Self.ringSamples(geometry: measured.geometry,
                                               outerMm: SupportRegion.ringOuterMm,
                                               annulusOuterMm: boundMm)
                var visible = 0
                for idx in samples.annulus
                where abs(p.normal.dot(measured.geometry.points[idx]) - p.d)
                    <= LiDARPlaneFitter.inlierBandMm {
                    visible += 1
                }
                sceneBounds.append(SceneBound(
                    label: spec.label,
                    boundMm: boundMm,
                    visibility: Float(visible)
                        / Float(max(1, measured.geometry.foodSampleCount)),
                    annulusMedianMm: SupportRegion.medianHeight(
                        indices: samples.annulus, geometry: measured.geometry,
                        normal: p.normal, d: p.d),
                    requiresVisibilityPass: spec.requiresPass.contains(.visibility),
                    requiresEscapePass: spec.requiresPass.contains(.escaped)))
            }
        }
        let suiteHolds = Self.annulusOuterSweep.filter { boundMm in
            sceneBounds.filter { $0.boundMm == boundMm }.allSatisfy(\.holds)
        }
        for boundMm in Self.annulusOuterSweep {
            let atBound = sceneBounds.filter { $0.boundMm == boundMm }
            print("  suite at bound \(fmt(boundMm)) mm:"
                  + " \(atBound.map { "\($0.label) visibility \(fmt($0.visibility))," + " annulus median \(fmt($0.annulusMedianMm)) mm\($0.holds ? "" : " FAILS")" })")
        }
        print("bounds at which every committed scene keeps its verdict:"
              + " \(suiteHolds.map { fmt($0) }) mm")

        // And what the suite's silence costs another owed constant. `escapeBandMm`'s suite
        // floor is the largest annulus median any must-pass scene reads (Decision 41's
        // ≥ 14.868 mm) — an annulus median, so it is a reading at the shipped bound.
        for boundMm in Self.annulusOuterSweep {
            let floor = sceneBounds.filter { $0.boundMm == boundMm && $0.requiresEscapePass }
                .map(\.annulusMedianMm).max() ?? 0
            print("  escapeBandMm suite floor at bound \(fmt(boundMm)) mm: \(fmt(floor)) mm")
        }

        // MARK: the radius swept with the bound PINNED

        // The decomposition. Decision 46 swept `ringOuterMm` and the annulus moved with it,
        // so its 18.719 mm is the two together. Re-running the same sweep twice — once
        // coupled as the shipped path couples them, once with the bound pinned at the
        // shipped 50 mm — splits that movement into the ring's share and the bound's.
        struct RadiusPair {
            let outerMm: Float
            let coupled: [Reading]
            let pinned: [Reading]
        }
        let pinnedAnnulusMm = SupportRegion.annulusOuterMm
        var pairs: [RadiusPair] = []
        for outerMm in Self.ringOuterSweep {
            var coupled: [Reading] = [], pinned: [Reading] = []
            for c in corpus {
                coupled.append(try read(name: c.name, slice: c.slice, g: c.g, ray: c.ray,
                                        outerMm: outerMm,
                                        annulusOuterMm: Self.coupledBoundMm(outerMm)))
                pinned.append(try read(name: c.name, slice: c.slice, g: c.g, ray: c.ray,
                                       outerMm: outerMm, annulusOuterMm: pinnedAnnulusMm))
            }
            pairs.append(RadiusPair(outerMm: outerMm, coupled: coupled, pinned: pinned))
        }

        for p in pairs {
            print("ringOuterMm=\(fmt(p.outerMm)):")
            for c in corpus {
                guard let coupled = p.coupled.first(where: { $0.name == c.name }),
                      let pinned = p.pinned.first(where: { $0.name == c.name }) else { continue }
                print("  \(c.name): coupled (annulus \(fmt(coupled.annulusOuterMm)) mm)"
                      + " plane \(fmt(coupled.planeAtFoodMm)) mm,"
                      + " candidates \(coupled.candidateCount),"
                      + " selected pass \(coupled.selectedIndex + 1),"
                      + " crossed \(coupled.signs.crossedFailing),"
                      + " intended pass \(coupled.intendedIndex + 1) crossed \(coupled.intendedCrossed)"
                      + " | pinned (annulus \(fmt(pinnedAnnulusMm)) mm)"
                      + " plane \(fmt(pinned.planeAtFoodMm)) mm,"
                      + " candidates \(pinned.candidateCount),"
                      + " selected pass \(pinned.selectedIndex + 1),"
                      + " crossed \(pinned.signs.crossedFailing),"
                      + " intended pass \(pinned.intendedIndex + 1) crossed \(pinned.intendedCrossed)")
            }
        }

        func span(_ readings: [[Reading]]) -> [String: Float] {
            var byName: [String: (lo: Float, hi: Float)] = [:]
            for group in readings {
                for r in group {
                    let existing = byName[r.name] ?? (r.planeAtFoodMm, r.planeAtFoodMm)
                    byName[r.name] = (min(existing.lo, r.planeAtFoodMm),
                                      max(existing.hi, r.planeAtFoodMm))
                }
            }
            return byName.mapValues { $0.hi - $0.lo }
        }
        let coupledSpans = span(pairs.map(\.coupled))
        let pinnedSpans = span(pairs.map(\.pinned))
        print("plane movement over the RADIUS sweep — coupled"
              + " \(coupledSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " | bound pinned"
              + " \(pinnedSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))")

        // Decision 46's other finding: the pass side ALTERNATES at 1 mm steps, which is why
        // that decision forbids interpolating inside the bracket. If the alternation is the
        // annulus re-selecting the candidates, pinning the bound removes it.
        var coupledDirty: [Float] = [], pinnedDirty: [Float] = []
        for p in pairs {
            if p.coupled.contains(where: { $0.name == "1785135663727" && $0.intendedCrossed > 0 }) {
                coupledDirty.append(p.outerMm)
            }
            if p.pinned.contains(where: { $0.name == "1785135663727" && $0.intendedCrossed > 0 }) {
                pinnedDirty.append(p.outerMm)
            }
        }
        print("radii at which the intended plate candidate reads a crossed sector —"
              + " coupled \(coupledDirty.map { fmt($0) }),"
              + " bound pinned \(pinnedDirty.map { fmt($0) })")

        // MARK: what the two legs say

        // The anchor for the coupled leg: it must reproduce Decision 46 — plane movement
        // beyond Req 5.1's tolerance on both captures and an alternating pass side — or the
        // comparison below is against something other than what that decision measured.
        let coupledAnchor = "the coupled radius sweep no longer reproduces Decision 46"
            + " (movement \(coupledSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted()),"
            + " dirty radii \(coupledDirty.map { fmt($0) })) — the decomposition below is"
            + " not a decomposition of that decision's finding"
        #expect(coupledSpans.values.allSatisfy { $0 > Self.gridTransferToleranceMm }
                && !coupledDirty.isEmpty, "\(coupledAnchor)")

        // THE FINDING. Pin the bound and the radius stops moving the plane — not within a
        // tolerance, exactly. Extraction reads the annulus and nothing else, so a pinned
        // bound hands every radius the same candidates; the ring still changes, so the
        // RANKING could still pick a different one, and it does not. Decision 46's 18.719 mm
        // is the annulus's, and `ringOuterMm` is a bracket-only constant like the count and
        // the bar after all.
        print("the radius's own share of Decision 46's movement:"
              + " \(pinnedSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))")
        let radiusCarriesIt = "the radius still moves the selected plane with the candidate"
            + " bound pinned (\(pinnedSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted()))"
            + " — the movement is not the annulus's alone and decoupling the bound does not"
            + " make ringOuterMm interpolable"
        #expect(pinnedSpans.values.allSatisfy { $0 == 0 }, "\(radiusCarriesIt)")

        // And the alternation goes with it. Decision 46 forbids interpolating inside
        // 22…32 mm because the intended plate candidate reads crossed sectors at 24, 27, 30,
        // 32 and 35 mm; with the bound pinned it reads none at any radius in the sweep, so
        // the alternation was the annulus re-selecting the candidates, not the ring.
        let alternationRemains = "the intended plate candidate still alternates with the"
            + " radius under a pinned bound (\(pinnedDirty.map { fmt($0) })) — Decision 46's"
            + " DO NOT INTERPOLATE stands and the bound is not what carries it"
        #expect(pinnedDirty.isEmpty, "\(alternationRemains)")

        // The bound's own movement, at a fixed ring — the same quantity, and it is
        // Decision 46's number rather than a fraction of it.
        let inertBound = "the candidate bound no longer moves the selected plane beyond Req"
            + " 5.1's transfer tolerance (\(boundSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted()))"
            + " — it is a bracket-only constant and this decision's headline is gone"
        #expect(boundSpans.values.contains { $0 > Self.gridTransferToleranceMm }, "\(inertBound)")

        // The corpus's bracket, and the shipped bound is the only value in the sweep that
        // DETERMINES `maxCrossedSectors`. Below it the floor rises to 3 or the interval goes
        // empty — the plane a correct fit must admit is itself crossed — and above it the
        // ceiling opens to 4 before the whole interval collapses at 100 mm. So Decision 48's
        // "determined at 2" is a slice at this constant as much as at the other four.
        let shippedBracket = try #require(crossedByBound[SupportRegion.annulusOuterMm])
        let determinedAt = Self.annulusOuterSweep.filter {
            (crossedByBound[$0]?.floor ?? 0) == 2 && (crossedByBound[$0]?.ceiling ?? 0) == 2
        }
        let feasibleAt = Self.annulusOuterSweep.filter {
            (crossedByBound[$0].map { $0.floor <= $0.ceiling }) == true
        }
        print("bounds at which the corpus determines maxCrossedSectors at 2:"
              + " \(determinedAt.map { fmt($0) }) mm;"
              + " feasible at \(feasibleAt.map { fmt($0) }) mm")
        let boundInvariant = "the corpus reads the same maxCrossedSectors bracket at every"
            + " candidate bound — Decision 48's determination is not denominated in this"
            + " constant and the sitting may set the two independently"
        #expect(shippedBracket.floor == 2 && shippedBracket.ceiling == 2
                && determinedAt.count == 1, "\(boundInvariant)")

        // The suite's leg, and it is the first constant since Decision 41 the committed
        // scenes cannot bound at all. They never run extraction, so the bound reaches them
        // only through `visibility` and `escaped` — which are two of the five guards
        // Decision 34 found never fire. Every scene keeps its verdict at 25 mm and at
        // 100 mm alike, so the ceiling and the floor are the corpus's alone.
        let suiteBinds = "the committed suite now changes verdict somewhere in the bound"
            + " sweep (holds at \(suiteHolds.map { fmt($0) }) of"
            + " \(Self.annulusOuterSweep.count) values) — it bounds annulusOuterMm after"
            + " all, and this decision's \"the corpus alone\" is wrong"
        #expect(suiteHolds.count == Self.annulusOuterSweep.count, "\(suiteBinds)")

        // One side finding, and it belongs to `escapeBandMm`. Decision 41 read that
        // constant's suite floor as ≥ 14.868 mm — an ANNULUS median, so a reading at the
        // shipped bound. Over the sweep the same scenes read 0.131 mm to 14.868 mm, because
        // a wider annulus reaches past the plate a scene sits on and the median goes
        // negative. So an owed constant that never fires is denominated in one that moves
        // the answer.
        let escapeFloors = Self.annulusOuterSweep.map { boundMm -> Float in
            sceneBounds.filter { $0.boundMm == boundMm && $0.requiresEscapePass }
                .map(\.annulusMedianMm).max() ?? 0
        }
        let escapeSpan = (escapeFloors.max() ?? 0) - (escapeFloors.min() ?? 0)
        print("escapeBandMm's suite floor over the bound sweep:"
              + " \(escapeFloors.map { fmt($0) }) mm — span \(fmt(escapeSpan)) mm")
        let escapeIndependent = "escapeBandMm's suite floor no longer moves with the"
            + " candidate bound (span \(fmt(escapeSpan)) mm) — Decision 41's ≥ 14.868 mm is"
            + " not a reading at the shipped bound and this side finding can be retired"
        #expect(escapeSpan > SupportRegion.ringBandMm, "\(escapeIndependent)")
    }

    // MARK: - The removal band, and what one pass hands the next

    // The fourth constant that decides which planes COMPETE, and the only one that acts
    // BETWEEN passes. `annulusOuterMm` fixes the sample set extraction draws from
    // (Decision 49); `maxCandidatePlanes` fixes how many times it may draw (Decision 48);
    // `ringOuterMm` re-rings a set already chosen (Decisions 46, 49). This one decides what
    // each draw LEAVES for the next, and it is the last unmarked constant in the file.
    //
    // Its comment is not a provenance marker but a claim: "a pass removes its polished
    // inliers within 2 × inlierBandMm; a 1× shell seeds near-duplicate planes on the next
    // pass". That is a statement about what happens at 1×, and like `ringOuterMm`'s
    // "inside the smallest measured plate margin" (Decision 33) and `ringBandCount`'s
    // "structural" (Decision 47) it has never been measured. It is measured here.
    //
    // The sweep runs from the structural floor to well past the shipped value. 1× is the
    // narrowest shell that can remove a pass's own inliers at all — the pass selected them
    // within `inlierBandMm`, so below 1× a pass leaves samples it just consumed and the
    // next pass can re-find the same plane exactly. 6× is 30 mm, wide enough to reach a
    // plate from a table.
    static let inlierRemovalSweep: [Float] = [1, 1.25, 1.5, 2, 2.5, 3, 4, 6]

    @Test("the removal band is what one pass hands the next, and its stated rule is measurable")
    func theRemovalBandIsWhatOnePassHandsTheNext() throws {
        struct Pass {
            let index: Int
            let normal: Vec3
            let d: Float
            let residueCount: Int
            let planeAtFoodMm: Float
            let ringMedianMm: Float
            let innerSupport: Float
            let extentMm: Float
            let signs: SectorSigns
        }
        struct Reading {
            let name: String
            let multiple: Float
            let removalBandMm: Float
            let pixelAreaMm2: Float
            let residueFloor: Int
            // The run with the cap LIFTED, so the depth extraction reaches on its own is
            // readable beside the depth it ships at. Decision 48 read this at the shipped
            // multiple alone.
            let natural: [Pass]
            let residueAfterNatural: Int
            // The shipped depth: a prefix of the same chain, since a pass reads only what
            // the previous left (Decision 48's prefix property).
            let shipped: [Pass]
            let selectedIndex: Int
            let intendedIndex: Int
            var starved: Bool { residueAfterNatural < residueFloor }
            var selected: Pass { shipped[selectedIndex] }
            var intended: Pass { shipped[intendedIndex] }
        }

        struct Capture {
            let name: String
            let slice: DepthSlice
            let g: SupportRegion.DepthGeometry
            let samples: SupportRegion.RingSamples
            let ray: Vec3
        }
        var corpus: [Capture] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            corpus.append(Capture(name: name, slice: slice, g: g,
                                  samples: SupportRegion.ringSamples(geometry: g),
                                  ray: try #require(Self.foodCentroidRay(slice))))
        }

        let sweepTop = try #require(Self.maxCandidatePlanesSweep.max())

        func pass(_ index: Int, _ c: SupportRegion.PlaneCandidate,
                  capture: Capture) -> Pass {
            Pass(index: index, normal: c.normal, d: c.d,
                 residueCount: c.residueCount,
                 planeAtFoodMm: Self.planeDepthMm(normal: c.normal, d: c.d, ray: capture.ray),
                 ringMedianMm: SupportRegion.medianHeight(
                    indices: capture.samples.ring, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 innerSupport: Self.innerSupportFraction(
                    samples: capture.samples, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 extentMm: c.extentMm,
                 signs: Self.sectorSigns(samples: capture.samples, geometry: capture.g,
                                         normal: c.normal, d: c.d))
        }

        func read(_ capture: Capture, multiple: Float) throws -> Reading {
            var rng = SplitMix64(seed: Fnv1a64.hash(capture.slice.depth.depthBytesMm))
            let deep = Self.extractCandidates(
                annulus: capture.samples.annulus, geometry: capture.g,
                gravity: capture.slice.gravity.normalised(), rng: &rng,
                maxPasses: sweepTop, removalMultiple: multiple)
            let natural = deep.enumerated().map { pass($0.offset, $0.element, capture: capture) }
            let shipped = Array(natural.prefix(SupportRegion.maxCandidatePlanes))

            // The removal chain replayed to the end, so what the pass AFTER the last one
            // would have drawn from is a number rather than an inference — Decision 48's
            // reading, at this multiple.
            let removalBandMm = multiple * LiDARPlaneFitter.inlierBandMm
            var residue = capture.samples.annulus
            for p in natural {
                residue = residue.filter {
                    abs(p.normal.dot(capture.g.points[$0]) - p.d) >= removalBandMm
                }
            }

            let empty = "\(capture.name): no candidate survives extraction at a removal band"
                + " of \(fmt(removalBandMm)) mm"
            let selected = try #require(
                (0..<shipped.count).max { shipped[$0].innerSupport < shipped[$1].innerSupport },
                "\(empty)")
            let intended = try #require(
                (0..<shipped.count).min { abs(shipped[$0].ringMedianMm) < abs(shipped[$1].ringMedianMm) })

            return Reading(
                name: capture.name, multiple: multiple, removalBandMm: removalBandMm,
                pixelAreaMm2: capture.g.mmPerPx * capture.g.mmPerPx,
                residueFloor: SupportRegion.minResidueSamples(mmPerPx: capture.g.mmPerPx),
                natural: natural, residueAfterNatural: residue.count,
                shipped: shipped, selectedIndex: selected, intendedIndex: intended)
        }

        var byMultiple: [Float: [Reading]] = [:]
        for multiple in Self.inlierRemovalSweep {
            byMultiple[multiple] = try corpus.map { try read($0, multiple: multiple) }
        }

        // The anchor. At the shipped multiple the parameterised chain must BE the shipped
        // extraction — candidate for candidate — or the sweep is measuring a different
        // removal and nothing below says anything about `inlierRemovalMultiple`.
        for c in corpus {
            let shipped = try #require(Self.candidates(c.name))
            let reading = try #require(
                byMultiple[SupportRegion.inlierRemovalMultiple]?.first { $0.name == c.name })
            let drift = "\(c.name): the parameterised removal chain no longer reproduces"
                + " SupportRegion.extractCandidates at inlierRemovalMultiple"
                + " (\(shipped.count) shipped candidates, \(reading.shipped.count) reproduced)"
                + " — the removal sweep is not measuring the shipped path"
            #expect(shipped.count == reading.shipped.count, "\(drift)")
            for (a, b) in zip(shipped, reading.shipped) {
                #expect(a.d == b.d && a.normal == b.normal
                        && a.residueCount == b.residueCount, "\(drift)")
            }
        }

        for multiple in Self.inlierRemovalSweep {
            let readings = byMultiple[multiple] ?? []
            print("inlierRemovalMultiple=\(fmt(multiple))"
                  + " (removal band \(fmt(multiple * LiDARPlaneFitter.inlierBandMm)) mm):")
            for r in readings {
                let shippedPlane = byMultiple[SupportRegion.inlierRemovalMultiple]?
                    .first { $0.name == r.name }
                print("  \(r.name): natural depth \(r.natural.count) passes"
                      + " (cap \(SupportRegion.maxCandidatePlanes)),"
                      + " residue after the last \(r.residueAfterNatural) samples"
                      + " = \(fmt(Float(r.residueAfterNatural) * r.pixelAreaMm2)) mm²"
                      + " \(r.starved ? "STARVED" : "the CAP stopped it"),"
                      + " selected pass \(r.selectedIndex + 1),"
                      + " PLANE AT FOOD \(fmt(r.selected.planeAtFoodMm)) mm"
                      + " (\(fmt(r.selected.planeAtFoodMm - (shippedPlane?.selected.planeAtFoodMm ?? r.selected.planeAtFoodMm)))"
                      + " vs shipped, tilt"
                      + " \(fmt(Self.angleDeg(r.selected.normal, shippedPlane?.selected.normal ?? r.selected.normal)))°),"
                      + " ring median \(fmt(r.selected.ringMedianMm)) mm,"
                      + " support \(fmt(r.selected.innerSupport)),"
                      + " crossed \(r.selected.signs.crossedFailing),"
                      + " escaped \(r.selected.signs.escapedFailing);"
                      + " intended pass \(r.intendedIndex + 1)"
                      + " (ring median \(fmt(r.intended.ringMedianMm)) mm,"
                      + " crossed \(r.intended.signs.crossedFailing),"
                      + " plane \(fmt(r.intended.planeAtFoodMm)) mm)")
                for p in r.natural {
                    print("    pass \(p.index + 1): residue \(p.residueCount) samples"
                          + " = \(fmt(Float(p.residueCount) * r.pixelAreaMm2)) mm²,"
                          + " plane \(fmt(p.planeAtFoodMm)) mm,"
                          + " ring median \(fmt(p.ringMedianMm)) mm,"
                          + " support \(fmt(p.innerSupport)),"
                          + " extent \(fmt(p.extentMm)) mm")
                }
            }
        }

        // MARK: the one stated rule

        // "A 1× shell seeds near-duplicate planes on the next pass." The bar for
        // "near-duplicate" is `inlierBandMm` itself, not a number chosen here: two planes
        // are near-duplicates when no sample in the candidate set can tell them apart —
        // when the largest gap between their signed heights, taken over the whole annulus,
        // is under one inlier band. That is exactly the condition under which the second
        // plane's inliers would have been the first's, so the claim is read in the units
        // the removal itself is written in.
        struct Adjacent {
            let name: String
            let multiple: Float
            let from: Int
            let separationMm: Float
            let tiltDeg: Float
            let maxDivergenceMm: Float
            var duplicate: Bool { maxDivergenceMm < LiDARPlaneFitter.inlierBandMm }
        }
        func divergenceMm(_ a: Pass, _ b: Pass, capture: Capture) -> Float {
            var worst: Float = 0
            for idx in capture.samples.annulus {
                let p = capture.g.points[idx]
                worst = max(worst, abs((a.normal.dot(p) - a.d) - (b.normal.dot(p) - b.d)))
            }
            return worst
        }
        var adjacents: [Adjacent] = []
        for multiple in Self.inlierRemovalSweep {
            for r in byMultiple[multiple] ?? [] {
                guard let capture = corpus.first(where: { $0.name == r.name }) else { continue }
                for (a, b) in zip(r.natural, r.natural.dropFirst()) {
                    adjacents.append(Adjacent(
                        name: r.name, multiple: multiple, from: a.index,
                        separationMm: abs(a.planeAtFoodMm - b.planeAtFoodMm),
                        tiltDeg: Self.angleDeg(a.normal, b.normal),
                        maxDivergenceMm: divergenceMm(a, b, capture: capture)))
                }
            }
        }
        for multiple in Self.inlierRemovalSweep {
            let atMultiple = adjacents.filter { $0.multiple == multiple }
            print("adjacent-pass separation at \(fmt(multiple))×:"
                  + " \(atMultiple.map { "\($0.name) pass \($0.from + 1)→\($0.from + 2)" + " \(fmt($0.separationMm)) mm at the food / \(fmt($0.tiltDeg))° / divergence \(fmt($0.maxDivergenceMm)) mm\($0.duplicate ? " DUPLICATE" : "")" })")
        }
        let duplicatesAtOne = adjacents.filter { $0.multiple == 1 && $0.duplicate }
        let duplicatesAbove = adjacents.filter { $0.multiple > 1 && $0.duplicate }
        print("near-duplicate adjacent passes: \(duplicatesAtOne.count) at 1×,"
              + " \(duplicatesAbove.count) above 1×,"
              + " of \(adjacents.count) adjacent pairs in the sweep")

        // MARK: what the removal band does to the answer

        var spanByName: [String: (lo: Float, hi: Float)] = [:]
        for readings in byMultiple.values {
            for r in readings {
                let existing = spanByName[r.name] ?? (r.selected.planeAtFoodMm, r.selected.planeAtFoodMm)
                spanByName[r.name] = (min(existing.lo, r.selected.planeAtFoodMm),
                                      max(existing.hi, r.selected.planeAtFoodMm))
            }
        }
        let spans = spanByName.mapValues { $0.hi - $0.lo }
        print("plane movement at the food over the REMOVAL sweep:"
              + " \(spans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm transfer tolerance")

        // And what it does to the plane a correct fit must SELECT, which on `1785901032716`
        // is pass 2 and not the ranking's winner (Decision 48). If a wide shell removes the
        // plate along with the table, that plane leaves the candidate set entirely — the
        // failure mode Decision 48 measured at a cap below 2, arriving by another route.
        for multiple in Self.inlierRemovalSweep {
            let readings = byMultiple[multiple] ?? []
            print("  at \(fmt(multiple))×: intended ring medians"
                  + " \(readings.map { "\($0.name) \(fmt($0.intended.ringMedianMm)) mm" }.sorted())")
        }

        // `maxCrossedSectors` per multiple, read exactly as Decisions 48 and 49 read it:
        // the floor off the plane a correct fit must ADMIT, the ceiling off the ranking's
        // winner where that is a different plane.
        var crossedByMultiple: [Float: (floor: Int, ceiling: Int)] = [:]
        for multiple in Self.inlierRemovalSweep {
            var floor = 0, ceiling = Int.max
            for r in byMultiple[multiple] ?? [] {
                floor = max(floor, r.intended.signs.crossedFailing)
                if r.selectedIndex != r.intendedIndex {
                    ceiling = min(ceiling, r.selected.signs.crossedFailing - 1)
                }
            }
            crossedByMultiple[multiple] = (floor, ceiling)
            print("  multiple \(fmt(multiple))×: maxCrossedSectors corpus \(floor)…"
                  + "\(ceiling == Int.max ? "unbounded" : "\(ceiling)")"
                  + " \(floor <= ceiling ? "" : "EMPTY")")
        }

        // MARK: what the sweep says

        // THE FIRST FINDING, and it is the claim in the comment. "A 1× shell seeds
        // near-duplicate planes on the next pass" is false on this corpus, and not
        // marginally: the closest adjacent pair anywhere in the sweep diverges by 23.973 mm
        // across the annulus, nearly five inlier bands, and the closest at 1× by 30.807 mm.
        // CC-RANSAC is why — a pass keeps the largest CONNECTED component, so the samples a
        // 1× shell leaves behind sit in a thin ring around a surface already taken and do
        // not form one. So the shipped value has no derivation at all, as `ringOuterMm` had
        // none once Decision 33 measured its stated rule. The floor cannot come from here.
        let closestAtOne = adjacents.filter { $0.multiple == 1 }.map(\.maxDivergenceMm).min() ?? 0
        let closestAnywhere = adjacents.map(\.maxDivergenceMm).min() ?? 0
        print("closest adjacent pass pair: \(fmt(closestAtOne)) mm at 1×,"
              + " \(fmt(closestAnywhere)) mm over the whole sweep"
              + " — against an inlier band of \(fmt(LiDARPlaneFitter.inlierBandMm)) mm")
        let ruleHolds = "a 1× shell does seed near-duplicate planes after all"
            + " (\(duplicatesAtOne.count) of \(adjacents.filter { $0.multiple == 1 }.count)"
            + " adjacent pairs, closest \(fmt(closestAtOne)) mm) — the comment's stated"
            + " reason for 2× is a derivation and this constant is not unmarked"
        #expect(duplicatesAtOne.isEmpty && duplicatesAbove.isEmpty, "\(ruleHolds)")

        // THE SECOND FINDING: the shell decides whether the pass cap is a cap at all.
        // Decision 48 lifted `maxCandidatePlanes` to 8 and found extraction stopping at
        // three passes on both captures, starved — so no value at or above 3 was
        // distinguishable and the cap's ceiling was open. That reading is at 2×. A narrower
        // shell hands the next pass more residue, extraction runs deeper, and the cap starts
        // truncating: the shipped 2× is the SMALLEST multiple in the sweep at which it does
        // not. Decision 48's headline is a slice at this constant, and the ordering it
        // states — residue floor before pass cap — gains a member before both.
        let naturalDepths = Self.inlierRemovalSweep.map { multiple in
            (multiple, (byMultiple[multiple] ?? []).map(\.natural.count))
        }
        let truncatedAt = Self.inlierRemovalSweep.filter { multiple in
            (byMultiple[multiple] ?? []).contains { $0.natural.count > SupportRegion.maxCandidatePlanes }
        }
        print("natural extraction depth per multiple:"
              + " \(naturalDepths.map { "\(fmt($0.0))× \($0.1)" });"
              + " the cap truncates at \(truncatedAt.map { fmt($0) })×")
        let capIsIdleThroughout = "the pass cap truncates at no removal multiple in the sweep"
            + " (natural depths \(naturalDepths.map { "\(fmt($0.0))× \($0.1)" })) — Decision"
            + " 48's \"the cap never fires\" is not denominated in this constant after all"
        #expect(!truncatedAt.isEmpty
                && !truncatedAt.contains(SupportRegion.inlierRemovalMultiple),
                "\(capIsIdleThroughout)")

        // THE THIRD FINDING: it does NOT move the answer, exactly. This is the constant that
        // decides what each pass hands the next, and the selected plane is unchanged to
        // 0.000 mm at every multiple on both captures — because removal happens AFTER a pass
        // and pass 1 is therefore drawn from an annulus this constant has never touched, and
        // because the ranking picks pass 1 on both captures at every multiple. So it joins
        // the count, the bar, the band count and (since Decision 49) the radius as
        // bracket-only, and `annulusOuterMm` remains the only owed constant that moves the
        // plane.
        let widest = spans.values.max() ?? 0
        let rankedFirstAlways = byMultiple.values.flatMap { $0 }.allSatisfy { $0.selectedIndex == 0 }
        print("the removal band's own share of the movement: \(fmt(widest)) mm;"
              + " the ranking picks pass 1 everywhere: \(rankedFirstAlways)")
        let removalMovesThePlane = "the removal band moves the selected plane"
            + " (\(spans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted())) — it is a second"
            + " owed constant that moves the answer and not a bracket-only one"
        #expect(widest == 0 && rankedFirstAlways, "\(removalMovesThePlane)")

        // THE BRACKET, and it is the corpus's alone. The committed suite cannot see this
        // constant at all, and here that is STRUCTURAL rather than measured: Decision 49's
        // bound reached the scenes through `visibility` and `escaped` and was found silent
        // by measurement, but no scene runs extraction — each asserts against a plane its
        // own test states — and the removal chain exists nowhere else. So no suite reading
        // is even definable, which no other owed constant can say.
        //
        // The CEILING is where a shell wide enough to take the table takes the plate with
        // it. On `1785901032716` the plane a correct fit must select is pass 2 (Decision 48),
        // and its ring median degrades −2.203, −2.309, −2.377, −2.658, −3.011 mm over
        // 1…2.5× before the candidate stops existing: at 3× the nearest-to-zero candidate is
        // pass 1, the TABLE at +3.039 mm with 3 crossed sectors of its own, so
        // `maxCrossedSectors` reads 3…unbounded — the guard would have to admit the plane
        // Decision 18 exists to reject. That is Decision 49's floor argument arriving on a
        // second constant. The FLOOR is structural at 1× and the corpus does not raise it:
        // at 1× the intended candidate is still admissible and still separable.
        let shippedBracket = try #require(crossedByMultiple[SupportRegion.inlierRemovalMultiple])
        let determinedAt = Self.inlierRemovalSweep.filter {
            (crossedByMultiple[$0]?.floor ?? 0) == 2 && (crossedByMultiple[$0]?.ceiling ?? 0) == 2
        }
        let brokenAt = Self.inlierRemovalSweep.filter {
            (crossedByMultiple[$0]?.floor ?? 0) > 2
        }
        print("multiples at which the corpus determines maxCrossedSectors at 2:"
              + " \(determinedAt.map { fmt($0) })×;"
              + " multiples at which the intended plane is gone: \(brokenAt.map { fmt($0) })×")
        let noCeiling = "the intended candidate survives at every removal multiple in the"
            + " sweep (maxCrossedSectors determined at 2 at \(determinedAt.map { fmt($0) }))"
            + " — the corpus does not bracket this constant from above and the ceiling is open"
        #expect(shippedBracket.floor == 2 && shippedBracket.ceiling == 2
                && !brokenAt.isEmpty
                && determinedAt.allSatisfy { $0 < (brokenAt.min() ?? 0) }, "\(noCeiling)")

        // And what the bracket says about Decision 48's determination. Unlike the candidate
        // bound — where only 50 mm of eight values read 2…2 (Decision 49) — this constant
        // reads 2…2 at EVERY value its own bracket admits. So `maxCrossedSectors` is not
        // denominated in it, and the sitting sets the two independently: the first time
        // since Decision 43 that two sources of a bracket agree throughout rather than at a
        // point.
        let agreesThroughout = determinedAt.count
            == Self.inlierRemovalSweep.filter { $0 <= (determinedAt.max() ?? 0) }.count
        print("maxCrossedSectors reads 2…2 at every admissible multiple: \(agreesThroughout)")
        let determinationIsASlice = "the corpus determines maxCrossedSectors at 2 at only"
            + " some of the removal multiples its own bracket admits"
            + " (\(determinedAt.map { fmt($0) })) — Decision 48's determination is a slice at"
            + " this constant too and the sitting must fix the removal band first"
        #expect(agreesThroughout, "\(determinationIsASlice)")
    }

    // MARK: - The iteration budget, and the probability that is supposed to set it

    // What one pass actually spent, which the shipped `ccRansac` computes and discards.
    struct RansacSpend {
        let iterations: Int        // iterations actually run before the loop exited
        let bestRatio: Float       // largest component ÷ residue count, the adaptive input
        let requiredAtBest: Double // requiredIterations at that ratio, UNCLAMPED
        let stoppedEarly: Bool     // the target probability ended the pass, not the cap
    }

    // `SupportRegion.requiredIterations` with the target probability as an argument and
    // WITHOUT the cap clamped on, so the two ends of the clamp can be read apart. The
    // shipped function is `min(maxIterationsPerPass, this)`, which is exactly what hides
    // which end binds.
    static func requiredIterations(inlierRatio w: Float, successProbability p: Double) -> Double {
        guard w > 0 else { return .infinity }
        let clean = pow(Double(min(0.999, w)), 3)
        guard clean < 1 else { return 1 }
        let n = log(1 - p) / log(1 - clean)
        return n.isFinite ? Swift.max(1, n.rounded(.up)) : .infinity
    }

    // `SupportRegion.ccRansac` with the budget pair as arguments and the spend reported.
    // Every other line is the shipped path's — the same unconditional three draws, the
    // same gravity gate, the same amortised component labelling — so at
    // (`maxIterationsPerPass`, `ransacSuccessProbability`) it reproduces the shipped
    // hypothesis exactly, which the anchor below checks candidate by candidate.
    static func ccRansac(indices: [Int], geometry g: SupportRegion.DepthGeometry,
                         gravity: Vec3, rng: inout SplitMix64,
                         scratch: SupportRegion.ComponentScratch,
                         maxIterations: Int, successProbability: Double)
    -> (hypothesis: SupportRegion.RansacHypothesis?, spend: RansacSpend) {
        let n = indices.count
        let empty = RansacSpend(iterations: 0, bestRatio: 0,
                                requiredAtBest: .infinity, stoppedEarly: false)
        guard n >= LiDARPlaneFitter.minPoints else { return (nil, empty) }
        var best: SupportRegion.RansacHypothesis?
        var bestComponent = 0
        var required = maxIterations
        var iteration = 0

        while iteration < required && iteration < maxIterations {
            iteration += 1
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = g.points[indices[i]], p2 = g.points[indices[j]], p3 = g.points[indices[k]]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            if acos(SupportRegion.clampedCosine(nHat.dot(gravity)))
                > LiDARPlaneFitter.gravityAngleMaxRad { continue }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in indices where abs(nHat.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                inliers.append(idx)
            }
            if inliers.count <= bestComponent { continue }

            let component = scratch.largestComponent(of: inliers)
            guard component.size > bestComponent else { continue }
            bestComponent = component.size
            best = SupportRegion.RansacHypothesis(normal: nHat, d: d, members: component.members)
            let w = Float(bestComponent) / Float(n)
            required = Swift.max(1, Swift.min(maxIterations,
                                              Int(requiredIterations(inlierRatio: w,
                                                                     successProbability: successProbability)
                                                  .rounded(.up))))
        }

        let ratio = Float(bestComponent) / Float(n)
        let unclamped = requiredIterations(inlierRatio: ratio, successProbability: successProbability)
        return (best, RansacSpend(iterations: iteration, bestRatio: ratio,
                                  requiredAtBest: unclamped,
                                  stoppedEarly: iteration < maxIterations))
    }

    // The pass chain with the budget parameterised and the spend of every pass kept.
    static func extractCandidates(
        annulus: [Int], geometry g: SupportRegion.DepthGeometry,
        gravity: Vec3, rng: inout SplitMix64,
        maxIterations: Int,
        successProbability: Double = SupportRegion.ransacSuccessProbability
    ) -> (candidates: [SupportRegion.PlaneCandidate], spends: [RansacSpend]) {
        var residue = annulus
        var candidates: [SupportRegion.PlaneCandidate] = []
        var spends: [RansacSpend] = []
        let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)
        let residueFloor = SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)

        for _ in 0..<SupportRegion.maxCandidatePlanes {
            guard residue.count >= residueFloor else { break }
            let drawn = Self.ccRansac(indices: residue, geometry: g, gravity: gravity,
                                      rng: &rng, scratch: scratch,
                                      maxIterations: maxIterations,
                                      successProbability: successProbability)
            spends.append(drawn.spend)
            guard let hypothesis = drawn.hypothesis else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1

            for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue
                where abs(normal.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers || next.count < LiDARPlaneFitter.minPoints { break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { break }
                if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity)))
                    > LiDARPlaneFitter.gravityAngleMaxRad {
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
            }

            let component = scratch.largestComponent(of: inliers)
            candidates.append(SupportRegion.PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count))

            let removalBandMm = SupportRegion.inlierRemovalMultiple * LiDARPlaneFitter.inlierBandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return (candidates, spends)
    }

    // Below the shipped cap in halvings, and two above it. 16 is there because the
    // pre-feature fitter's budget was 256 and the design's own comment measures this
    // constant against it; 8192 is far enough above that a cap which binds at 2048 has
    // room to stop binding.
    static let ransacBudgetSweep = [16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192]

    // The seed control is the expensive half, so it runs at four budgets rather than ten:
    // one far below the shipped cap, one below, the shipped one, and one above.
    static let ransacBudgetSeedSweep = [64, 256, 2048, 8192]

    // Every value `ransacSuccessProbability` could plausibly take. 0.5 is included as the
    // degenerate end — if even a coin-flip target reads the same as 0.99, the constant is
    // not merely loosely set, it is inert.
    static let ransacProbabilitySweep = [0.5, 0.9, 0.95, 0.99, 0.999, 0.99999]

    @Test("the iteration budget is what the seed spread is denominated in, and its target probability never binds")
    func theIterationBudgetIsWhatTheSeedSpreadIsDenominatedIn() throws {
        struct Reading {
            let budget: Int
            let planeAtFoodMm: Float
            let crossed: Int
            let supporting: Int
            let ringMedianMm: Float
            let candidateCount: Int
            let spends: [RansacSpend]
        }

        var byCapture: [String: [Reading]] = [:]
        var spreadByCaptureAndBudget: [String: [Int: Float]] = [:]
        var everStoppedEarly = false
        var pass1Ratios: [String: Float] = [:]

        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let ray = try #require(Self.foodCentroidRay(slice))
            let shippedSeed = Fnv1a64.hash(slice.depth.depthBytesMm)

            // The anchor. At the shipped pair this mirror must reproduce the shipped call
            // candidate for candidate, or nothing below is a reading on the shipped path.
            var anchorRng = SplitMix64(seed: shippedSeed)
            let anchor = Self.extractCandidates(
                annulus: samples.annulus, geometry: g, gravity: slice.gravity.normalised(),
                rng: &anchorRng, maxIterations: SupportRegion.maxIterationsPerPass)
            var shippedRng = SplitMix64(seed: shippedSeed)
            let shipped = SupportRegion.extractCandidates(
                annulus: samples.annulus, geometry: g,
                gravity: slice.gravity.normalised(), rng: &shippedRng)
            #expect(anchor.candidates.count == shipped.count,
                    "the budget mirror stopped reproducing the shipped pass count")
            for (a, s) in zip(anchor.candidates, shipped) {
                let samePlane: Bool = a.d == s.d
                let sameComponent: Bool = a.componentSize == s.componentSize
                #expect(samePlane && sameComponent,
                        "the budget mirror diverged from SupportRegion.extractCandidates")
            }
            pass1Ratios[name] = anchor.spends.first?.bestRatio ?? 0

            var readings: [Reading] = []
            for budget in Self.ransacBudgetSweep {
                var rng = SplitMix64(seed: shippedSeed)
                let run = Self.extractCandidates(
                    annulus: samples.annulus, geometry: g,
                    gravity: slice.gravity.normalised(), rng: &rng, maxIterations: budget)
                guard let best = run.candidates.max(by: {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: $0.normal, d: $0.d)
                    < Self.innerSupportFraction(samples: samples, geometry: g,
                                                normal: $1.normal, d: $1.d)
                }) else { continue }
                let signs = Self.sectorSigns(samples: samples, geometry: g,
                                             normal: best.normal, d: best.d)
                if run.spends.contains(where: \.stoppedEarly) { everStoppedEarly = true }
                readings.append(Reading(
                    budget: budget,
                    planeAtFoodMm: Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray),
                    crossed: signs.crossedFailing,
                    supporting: signs.supporting,
                    ringMedianMm: SupportRegion.medianHeight(
                        indices: samples.ring, geometry: g, normal: best.normal, d: best.d),
                    candidateCount: run.candidates.count,
                    spends: run.spends))
            }
            byCapture[name] = readings

            print("\(name): the budget swept at the shipped seed")
            for r in readings {
                let spend = r.spends.map {
                    "\($0.iterations)@w=\(fmt($0.bestRatio))"
                        + ($0.requiredAtBest.isFinite
                           ? "(needs \(Int($0.requiredAtBest)))" : "(needs ∞)")
                }
                print("  cap \(r.budget): plane at food \(fmt(r.planeAtFoodMm)) mm,"
                      + " ring median \(fmt(r.ringMedianMm)) mm, supporting \(r.supporting),"
                      + " crossed \(r.crossed), candidates \(r.candidateCount),"
                      + " spend \(spend.joined(separator: " | "))")
            }

            // The seed control, re-run at four budgets. Decision 46 measured 2.095 mm of
            // draw dependence on this capture at the shipped cap and recorded it as a
            // caveat on every plane figure the feature quotes; what it could not say is
            // which constant the caveat is denominated in.
            var spreads: [Int: Float] = [:]
            for budget in Self.ransacBudgetSeedSweep {
                var planes: [Float] = []
                for i in 0..<Self.seedRolls {
                    let seed = i == 0 ? shippedSeed
                        : shippedSeed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
                    var rng = SplitMix64(seed: seed)
                    let run = Self.extractCandidates(
                        annulus: samples.annulus, geometry: g,
                        gravity: slice.gravity.normalised(), rng: &rng, maxIterations: budget)
                    guard let best = run.candidates.max(by: {
                        Self.innerSupportFraction(samples: samples, geometry: g,
                                                  normal: $0.normal, d: $0.d)
                        < Self.innerSupportFraction(samples: samples, geometry: g,
                                                    normal: $1.normal, d: $1.d)
                    }) else { continue }
                    planes.append(Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray))
                }
                spreads[budget] = (planes.max() ?? 0) - (planes.min() ?? 0)
            }
            spreadByCaptureAndBudget[name] = spreads
            print("  seed spread at the food by cap:"
                  + " \(Self.ransacBudgetSeedSweep.map { "\($0) → \(fmt(spreads[$0] ?? 0)) mm" }.joined(separator: ", "))")
        }

        // FINDING 1. The clamp has two ends and the shipped one is not the end that binds.
        // `requiredIterations` is `min(cap, target)`, and on every pass of both captures
        // the TARGET is smaller: the passes spend 72, 11, 250 and 12, 41, 5 against a cap
        // of 2048. So `maxIterationsPerPass` NEVER FIRES at the shipped value — the third
        // constant in this file of which that is true, after Decision 48's pass cap and
        // Decision 34's five unexercised guards — and the constant that actually sets
        // every pass's budget is `ransacSuccessProbability`.
        //
        // That is the inversion. The cap carries a `[derived]` marker and a paragraph of
        // sufficiency argument; the target carries NO provenance marker at all, the last
        // constant in the file of which that is true after Decision 47's band count and
        // Decision 48's pass cap. The feature has been documenting the inert half of a
        // two-constant clamp and leaving the live half unmarked.
        let spendsAtShipped = Self.captures.flatMap {
            byCapture[$0]?.first { $0.budget == SupportRegion.maxIterationsPerPass }?.spends ?? []
        }
        let capFired = spendsAtShipped.contains { $0.iterations >= SupportRegion.maxIterationsPerPass }
        print("passes at the shipped cap: "
              + spendsAtShipped.map { "\($0.iterations)/\(SupportRegion.maxIterationsPerPass)" }
                .joined(separator: ", ")
              + "; every pass stopped on the target: \(everStoppedEarly && !capFired)")
        let capBinds = "a pass at the shipped budget ran the cap out"
            + " (\(spendsAtShipped.map(\.iterations))) — maxIterationsPerPass fires after"
            + " all and the two ends of the clamp are not separable this way"
        #expect(everStoppedEarly && !capFired, "\(capBinds)")

        // FINDING 2. And the cap's `[derived]` argument is refuted by its own quantity.
        // It prices pass 1 at a ~6 % inlier ratio — the figure the whole "the budget is
        // sufficient because extraction is SEQUENTIAL" paragraph rests on. Measured, the
        // pass-1 ratio is 0.402 and 0.698, six to twelve times that, and at those ratios
        // a 0.99 target is met in 69 and 12 iterations. The budget is not sufficient
        // because extraction is sequential; it is sufficient because the dominant plane
        // is easy, and the cap is 30x larger than the largest draw the corpus ever needs.
        let quotedPass1Ratio: Float = 0.06
        for (name, w) in pass1Ratios.sorted(by: { $0.key < $1.key }) {
            let needed = Self.requiredIterations(inlierRatio: w, successProbability:
                                                    SupportRegion.ransacSuccessProbability)
            print("\(name) pass 1: w = \(fmt(w)) against the quoted"
                  + " \(fmt(quotedPass1Ratio)); a 0.99 target needs \(Int(needed)) iterations"
                  + " against a cap of \(SupportRegion.maxIterationsPerPass)")
            let quoteHolds = "pass 1 on \(name) reads w = \(fmt(w)), which is the ~6 % the"
                + " design quotes — the sufficiency argument on maxIterationsPerPass stands"
                + " as written"
            #expect(w > 4 * quotedPass1Ratio, "\(quoteHolds)")
        }

        // FINDING 3. The target is the live constant, and it moves the plane past the bar
        // Req 5.1 is measured at. Swept from a coin flip to five nines at the shipped cap,
        // the selected plane at the food moves 3.704 mm on `1785135663727` — against the
        // 1 mm Decision 35 measures the grid transfer at, and larger than the 2.095 mm of
        // draw dependence Decision 46 recorded as a caveat on the whole feature.
        //
        // So this is not a constant being retired. It is an owed constant the feature did
        // not know it had: unmarked, unvaried, unbracketed, and moving the answer by more
        // than every constant Decisions 44 to 48 swept except the candidate bound.
        var probabilityPlanes: [String: [Double: Float]] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let seed = Fnv1a64.hash(slice.depth.depthBytesMm)
            let ray = try #require(Self.foodCentroidRay(slice))
            var planes: [Double: Float] = [:]
            for p in Self.ransacProbabilitySweep {
                var rng = SplitMix64(seed: seed)
                let run = Self.extractCandidates(
                    annulus: samples.annulus, geometry: g,
                    gravity: slice.gravity.normalised(), rng: &rng,
                    maxIterations: SupportRegion.maxIterationsPerPass, successProbability: p)
                guard let best = run.candidates.max(by: {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: $0.normal, d: $0.d)
                    < Self.innerSupportFraction(samples: samples, geometry: g,
                                                normal: $1.normal, d: $1.d)
                }) else { continue }
                planes[p] = Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray)
            }
            probabilityPlanes[name] = planes
            let values = Self.ransacProbabilitySweep.compactMap { planes[$0] }
            let spread = (values.max() ?? 0) - (values.min() ?? 0)
            print("\(name) over ransacSuccessProbability:"
                  + " \(Self.ransacProbabilitySweep.map { "\($0) → \(fmt(planes[$0] ?? 0))" }.joined(separator: ", "))"
                  + " — spread \(fmt(spread)) mm")
        }
        let widestOverP = Self.captures.map { name -> Float in
            let v = Self.ransacProbabilitySweep.compactMap { probabilityPlanes[name]?[$0] }
            return (v.max() ?? 0) - (v.min() ?? 0)
        }.max() ?? 0
        let targetIsInert = "ransacSuccessProbability moves the selected plane by at most"
            + " \(fmt(widestOverP)) mm across a coin flip to five nines — it cannot change"
            + " an output and leaves task 26 by being retired rather than bracketed"
        #expect(widestOverP > Self.gridTransferToleranceMm, "\(targetIsInert)")

        // FINDING 4. Which is what Decision 46's caveat is denominated in, and it is not
        // the cap. Re-run the eight-seed control at four budgets and the spread does not
        // move at all — 1.992 mm at 64 and 2.095 mm at 256, 2048 and 8192 — because the
        // cap is not what ends a pass. Draw dependence is not bought off by a larger
        // budget; it is bought off by a stricter target, and no amount of the constant
        // that carries the argument buys any of it.
        for name in Self.captures {
            let spreads = try #require(spreadByCaptureAndBudget[name])
            print("\(name) seed spread against the cap:"
                  + " \(Self.ransacBudgetSeedSweep.map { "\($0) → \(fmt(spreads[$0] ?? 0)) mm" }.joined(separator: ", "))")
        }
        let spreadAtShipped = Self.captures.compactMap {
            spreadByCaptureAndBudget[$0]?[SupportRegion.maxIterationsPerPass]
        }.max() ?? 0
        let spreadAtTop = Self.captures.compactMap {
            spreadByCaptureAndBudget[$0]?[Self.ransacBudgetSeedSweep.last ?? 0]
        }.max() ?? 0
        print("widest seed spread at the shipped cap \(fmt(spreadAtShipped)) mm,"
              + " at \(Self.ransacBudgetSeedSweep.last ?? 0) \(fmt(spreadAtTop)) mm")
        let capBuysStability = "raising maxIterationsPerPass from"
            + " \(SupportRegion.maxIterationsPerPass) to \(Self.ransacBudgetSeedSweep.last ?? 0)"
            + " narrows the seed spread (\(fmt(spreadAtShipped)) → \(fmt(spreadAtTop)) mm)"
            + " — the cap does buy draw stability and Decision 46's caveat is denominated"
            + " in it after all"
        #expect(spreadAtTop == spreadAtShipped, "\(capBuysStability)")

        // And the other half of that, measured rather than argued. Saying the spread is
        // denominated in the target only because it is not denominated in the cap would be
        // an inference, so the eight-seed control runs against the target as well. This is
        // what a sitting would actually be choosing between: the cap is free and buys
        // nothing, the target costs iterations and is the only thing that can buy the
        // draw stability every bracket in Decisions 40 to 50 is quoted at.
        var spreadByProbability: [String: [Double: Float]] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let ray = try #require(Self.foodCentroidRay(slice))
            let shippedSeed = Fnv1a64.hash(slice.depth.depthBytesMm)
            var spreads: [Double: Float] = [:]
            for p in Self.ransacProbabilitySweep {
                var planes: [Float] = []
                for i in 0..<Self.seedRolls {
                    let seed = i == 0 ? shippedSeed
                        : shippedSeed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
                    var rng = SplitMix64(seed: seed)
                    let run = Self.extractCandidates(
                        annulus: samples.annulus, geometry: g,
                        gravity: slice.gravity.normalised(), rng: &rng,
                        maxIterations: SupportRegion.maxIterationsPerPass,
                        successProbability: p)
                    guard let best = run.candidates.max(by: {
                        Self.innerSupportFraction(samples: samples, geometry: g,
                                                  normal: $0.normal, d: $0.d)
                        < Self.innerSupportFraction(samples: samples, geometry: g,
                                                    normal: $1.normal, d: $1.d)
                    }) else { continue }
                    planes.append(Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray))
                }
                spreads[p] = (planes.max() ?? 0) - (planes.min() ?? 0)
            }
            spreadByProbability[name] = spreads
            print("\(name) seed spread against the target:"
                  + " \(Self.ransacProbabilitySweep.map { "\($0) → \(fmt(spreads[$0] ?? 0)) mm" }.joined(separator: ", "))")
        }
        let atShippedP = Self.captures.compactMap {
            spreadByProbability[$0]?[SupportRegion.ransacSuccessProbability]
        }.max() ?? 0
        let atStrictestP = Self.captures.compactMap {
            spreadByProbability[$0]?[Self.ransacProbabilitySweep.last ?? 0]
        }.max() ?? 0
        print("widest seed spread at the shipped target \(fmt(atShippedP)) mm,"
              + " at \(Self.ransacProbabilitySweep.last ?? 0) \(fmt(atStrictestP)) mm")
        let targetBuysNothingEither = "tightening ransacSuccessProbability from"
            + " \(SupportRegion.ransacSuccessProbability) to"
            + " \(Self.ransacProbabilitySweep.last ?? 0) does not narrow the seed spread"
            + " (\(fmt(atShippedP)) → \(fmt(atStrictestP)) mm) — neither end of the clamp"
            + " buys draw stability and Decision 46's caveat is denominated in neither"
        #expect(atStrictestP < atShippedP, "\(targetBuysNothingEither)")

        // FINDING 5. The cap is still bracketed from BELOW, so it is not retired either.
        // It stops truncating any pass at 256 — the largest draw the corpus needs is 250 —
        // but the answer locks earlier and lower than that: at 128 the plane is the shipped
        // one, and at 64 the sector verdict FLIPS from 5 supporting / 0 crossed to 3 / 2,
        // which is the guard Decisions 40 to 50 read every one of their brackets from.
        // Bracketed 128…unbounded, the shipped 2048 far inside it, and the ceiling is open
        // for the same reason Decision 48's was: nothing above the point where it stops
        // firing is distinguishable.
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let atShipped = try #require(
                readings.first { $0.budget == SupportRegion.maxIterationsPerPass })
            let moved = readings.filter {
                abs($0.planeAtFoodMm - atShipped.planeAtFoodMm) > Self.gridTransferToleranceMm
            }.map(\.budget)
            let flipped = readings.filter {
                $0.supporting != atShipped.supporting || $0.crossed != atShipped.crossed
            }.map(\.budget)
            print("\(name): caps whose plane differs from the shipped cap's by more than"
                  + " \(fmt(Self.gridTransferToleranceMm)) mm: \(moved);"
                  + " caps whose sector verdict differs: \(flipped)")
            let noFloor = "no cap in \(Self.ransacBudgetSweep) moves the plane or the sector"
                + " verdict on \(name) — the corpus gives maxIterationsPerPass no floor and"
                + " the constant is unbracketed in both directions"
            if name == "1785135663727" {
                #expect(!moved.isEmpty && !flipped.isEmpty, "\(noFloor)")
                #expect(moved.allSatisfy { $0 < 128 } && flipped.allSatisfy { $0 < 128 },
                        "the cap floor moved off 128 — the bracket needs re-reading")
            }
        }
    }

    // MARK: - The inlier band, and the four markers that terminate in it

    // `SupportRegion.ccRansac` with the inlier band as an argument. Every other line is
    // the shipped path's — the same unconditional three draws, the same gravity gate, the
    // same amortised component labelling, the same adaptive stopping — so at
    // `LiDARPlaneFitter.inlierBandMm` it reproduces the shipped hypothesis exactly, which
    // the anchor below checks candidate by candidate.
    static func ccRansac(indices: [Int], geometry g: SupportRegion.DepthGeometry,
                         gravity: Vec3, rng: inout SplitMix64,
                         scratch: SupportRegion.ComponentScratch,
                         bandMm: Float) -> SupportRegion.RansacHypothesis? {
        let n = indices.count
        guard n >= LiDARPlaneFitter.minPoints else { return nil }
        var best: SupportRegion.RansacHypothesis?
        var bestComponent = 0
        var required = SupportRegion.maxIterationsPerPass
        var iteration = 0

        while iteration < required && iteration < SupportRegion.maxIterationsPerPass {
            iteration += 1
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = g.points[indices[i]], p2 = g.points[indices[j]], p3 = g.points[indices[k]]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            if acos(SupportRegion.clampedCosine(nHat.dot(gravity)))
                > LiDARPlaneFitter.gravityAngleMaxRad { continue }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in indices where abs(nHat.dot(g.points[idx]) - d) < bandMm {
                inliers.append(idx)
            }
            if inliers.count <= bestComponent { continue }

            let component = scratch.largestComponent(of: inliers)
            guard component.size > bestComponent else { continue }
            bestComponent = component.size
            best = SupportRegion.RansacHypothesis(normal: nHat, d: d, members: component.members)
            required = SupportRegion.requiredIterations(
                inlierRatio: Float(bestComponent) / Float(n))
        }
        return best
    }

    // The pass chain with the band parameterised. It reaches THREE places at once, which
    // is the point: the RANSAC inlier test above, the consensus polish's re-selection, and
    // the removal band `inlierRemovalMultiple` is a multiple OF. Decision 50 swept the
    // multiple at a fixed band; this sweeps the band the multiple is denominated in.
    static func extractCandidates(
        annulus: [Int], geometry g: SupportRegion.DepthGeometry,
        gravity: Vec3, rng: inout SplitMix64, bandMm: Float
    ) -> [SupportRegion.PlaneCandidate] {
        var residue = annulus
        var candidates: [SupportRegion.PlaneCandidate] = []
        let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)
        let residueFloor = SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)

        for _ in 0..<SupportRegion.maxCandidatePlanes {
            guard residue.count >= residueFloor else { break }
            guard let hypothesis = Self.ccRansac(indices: residue, geometry: g,
                                                 gravity: gravity, rng: &rng,
                                                 scratch: scratch, bandMm: bandMm) else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1

            for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue where abs(normal.dot(g.points[idx]) - d) < bandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers || next.count < LiDARPlaneFitter.minPoints { break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { break }
                if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity)))
                    > LiDARPlaneFitter.gravityAngleMaxRad {
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
            }

            let component = scratch.largestComponent(of: inliers)
            candidates.append(SupportRegion.PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count))

            let removalBandMm = SupportRegion.inlierRemovalMultiple * bandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return candidates
    }

    // Whether a plane's inlier component spans more than one of the scene's SURFACES —
    // Gallo et al.'s straddler, in the paper's own terms. The surfaces are the shipped
    // extraction's own planes, read once per capture at the shipped band, so this is a
    // measurement against the scene rather than against the sweep.
    //
    // A member is assigned to the reference plane it lies nearest, and only if it lies
    // within one shipped band of it; the plate and the table are ~26 mm apart, so the
    // assignment is unambiguous wherever it is made at all. A component holding at least
    // `bridgeMinShare` of its members on each of two references has BRIDGED them.
    struct BridgeReading {
        let componentSize: Int
        let shares: [Float]        // share of the component on each reference surface
        let unassigned: Float
        let tiltDeg: Float
        var span: Int { shares.filter { $0 >= bridgeMinShare }.count }
        var spanned: [Int] {
            shares.enumerated().filter { $0.element >= bridgeMinShare }.map(\.offset)
        }
    }

    // The step between two reference surfaces, in the units Gallo et al.'s envelope is
    // stated in: `h` is the separation of the two planes over the annulus, and the
    // envelope is `epsilon / h`. Taken as the median absolute height difference so a
    // relative tilt between the two does not read as a single number it is not.
    static func separationMm(_ a: (normal: Vec3, d: Float), _ b: (normal: Vec3, d: Float),
                             geometry g: SupportRegion.DepthGeometry,
                             annulus: [Int]) -> Float {
        SupportRegion.median(annulus.map {
            abs((a.normal.dot(g.points[$0]) - a.d) - (b.normal.dot(g.points[$0]) - b.d))
        })
    }

    // A tenth of the component. Small enough that a genuine bridge — the paper's "large
    // number of connected inliers" across the step — is caught, large enough that a
    // handful of samples straying over a reference plane's own noise is not.
    static let bridgeMinShare: Float = 0.10

    static func bridgeReading(normal: Vec3, d: Float, bandMm: Float,
                              geometry g: SupportRegion.DepthGeometry,
                              annulus: [Int], gravity: Vec3,
                              references: [(normal: Vec3, d: Float)],
                              scratch: SupportRegion.ComponentScratch) -> BridgeReading {
        var inliers: [Int] = []
        inliers.reserveCapacity(annulus.count)
        for idx in annulus where abs(normal.dot(g.points[idx]) - d) < bandMm {
            inliers.append(idx)
        }
        let component = scratch.largestComponent(of: inliers)
        var counts = [Int](repeating: 0, count: references.count)
        var unassigned = 0
        for idx in component.members {
            let p = g.points[idx]
            var bestIndex = -1
            var bestDistance = LiDARPlaneFitter.inlierBandMm
            for (i, reference) in references.enumerated() {
                let distance = abs(reference.normal.dot(p) - reference.d)
                if distance < bestDistance { bestDistance = distance; bestIndex = i }
            }
            if bestIndex >= 0 { counts[bestIndex] += 1 } else { unassigned += 1 }
        }
        let total = Float(max(1, component.size))
        return BridgeReading(
            componentSize: component.size,
            shares: counts.map { Float($0) / total },
            unassigned: Float(unassigned) / total,
            tiltDeg: acos(SupportRegion.clampedCosine(normal.dot(gravity))) * 180 / .pi)
    }

    // Halvings and doublings around the shipped 5 mm, with the ends set by what the
    // measurement has to be able to see. 1 mm is below the 3.44 mm per-sample sigma
    // Decision 29 measured, where the paper's own warning — CC-RANSAC is WORSE than plain
    // RANSAC at very small epsilon, because components stop being large enough to support
    // the correct plane — should bite. 12.5 mm is half the 26 mm plate step, an
    // epsilon/h of 0.48 and well outside the 0.25-0.35 envelope design.md quotes, where
    // the straddler is supposed to appear.
    static let inlierBandSweep: [Float] = [1, 2, 3, 4, 5, 6, 8, 10, 12.5]

    @Test("the inlier band is the unit four provenance markers terminate in, and it moves the plane")
    func theInlierBandIsWhatTheInheritedMarkersTerminateIn() throws {
        // The chain, asserted rather than described. Three constants are one number, and
        // the number is `LiDARPlaneFitter.inlierBandMm` — which is where every `[inherited]`
        // marker in `SupportRegion` ends and where the provenance ends with it.
        #expect(SupportRegion.ringBandMm == LiDARPlaneFitter.inlierBandMm,
                "ringBandMm stopped being inherited from inlierBandMm")
        #expect(SupportRegion.ringMedianMaxMm == SupportRegion.ringBandMm,
                "ringMedianMaxMm stopped being inherited from ringBandMm")

        struct Reading {
            let bandMm: Float
            let candidateCount: Int
            // The ranked winner with the ring read at the SHIPPED band: the extraction
            // half of the constant alone.
            let planeAtFoodMm: Float
            // The ranked winner with the ring read at the SWEPT band: the inheritance
            // honoured, which is what actually happens if the root moves.
            let coupledPlaneAtFoodMm: Float
            // The candidate nearest Req 3.1's zero — Decision 48's identification of the
            // plane a correct fit must select, which is not always the ranking's winner.
            let intendedRingMedianMm: Float
            let intendedCrossed: Int
            let intendedSupporting: Int
            let intendedSupportFraction: Float
            let intendedInnerBandMedianMm: Float
            let ringMedianGuardFires: Bool
            let maxSpan: Int
            let maxTiltDeg: Float
            let ringFeasible: Bool
        }

        var byCapture: [String: [Reading]] = [:]
        // The step between the two surfaces the plate capture's competition is between,
        // which is `h` in design.md's envelope table, and the widest tilt the SHIPPED run
        // produces against the fitter's stated gravity cone.
        var stepBetweenCompetingSurfacesMm: [String: Float] = [:]
        var shippedMaxTiltDeg: [String: Float] = [:]

        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            let samples = SupportRegion.ringSamples(geometry: g)
            let ray = try #require(Self.foodCentroidRay(slice))
            let gravity = slice.gravity.normalised()
            let seed = Fnv1a64.hash(slice.depth.depthBytesMm)
            let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)

            // The anchor. At the shipped band this mirror must reproduce the shipped call
            // candidate for candidate, or nothing below is a reading on the shipped path.
            var anchorRng = SplitMix64(seed: seed)
            let anchor = Self.extractCandidates(annulus: samples.annulus, geometry: g,
                                                gravity: gravity, rng: &anchorRng,
                                                bandMm: LiDARPlaneFitter.inlierBandMm)
            var shippedRng = SplitMix64(seed: seed)
            let shipped = SupportRegion.extractCandidates(annulus: samples.annulus, geometry: g,
                                                          gravity: gravity, rng: &shippedRng)
            #expect(anchor.count == shipped.count,
                    "the band mirror stopped reproducing the shipped pass count")
            for (a, s) in zip(anchor, shipped) {
                #expect(a.d == s.d && a.componentSize == s.componentSize,
                        "the band mirror diverged from SupportRegion.extractCandidates")
            }

            // The scene's surfaces, taken once at the shipped band from the shipped run.
            let references = shipped.map { (normal: $0.normal, d: $0.d) }

            // Which surface is which, and how far apart they sit — `h` in the envelope
            // design.md quotes. The shipped candidates' own tilts come from the shipped
            // call, not the mirror, so the cone reading below is a reading on shipped code.
            print("=== \(name): the scene's surfaces, from the shipped run ===")
            for (i, candidate) in shipped.enumerated() {
                let tilt = acos(SupportRegion.clampedCosine(candidate.normal.dot(gravity)))
                    * 180 / .pi
                print("  surface \(i + 1): ring median"
                      + " \(fmt(SupportRegion.medianHeight(indices: samples.ring, geometry: g, normal: candidate.normal, d: candidate.d))) mm,"
                      + " annulus median"
                      + " \(fmt(SupportRegion.medianHeight(indices: samples.annulus, geometry: g, normal: candidate.normal, d: candidate.d))) mm,"
                      + " tilt \(fmt(tilt))° against a"
                      + " \(fmt(LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi))° cone"
                      + (tilt > LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi
                         ? " — OUTSIDE THE CONE" : ""))
            }
            shippedMaxTiltDeg[name] = shipped.map {
                acos(SupportRegion.clampedCosine($0.normal.dot(gravity))) * 180 / .pi
            }.max() ?? 0
            var steps: [Float] = []
            for i in shipped.indices {
                for j in shipped.indices where j > i {
                    let h = Self.separationMm(references[i], references[j],
                                              geometry: g, annulus: samples.annulus)
                    steps.append(h)
                    print("  surfaces \(i + 1)/\(j + 1): h = \(fmt(h)) mm,"
                          + " shipped ε/h = \(fmt(LiDARPlaneFitter.inlierBandMm / max(h, 1e-6)))")
                }
            }
            // The competition design.md's first table row prices — the two surfaces the
            // ranking actually chooses between — is the CLOSEST pair, since that is the
            // step CC-RANSAC has the least room to resolve.
            stepBetweenCompetingSurfacesMm[name] = steps.min() ?? 0

            var readings: [Reading] = []
            for bandMm in Self.inlierBandSweep {
                var rng = SplitMix64(seed: seed)
                let candidates = Self.extractCandidates(annulus: samples.annulus, geometry: g,
                                                        gravity: gravity, rng: &rng,
                                                        bandMm: bandMm)
                guard !candidates.isEmpty else {
                    print("\(name) at band \(fmt(bandMm)) mm: extraction produced NO candidate")
                    continue
                }
                func rank(_ c: SupportRegion.PlaneCandidate, at band: Float) -> Float {
                    Self.innerSupportFraction(samples: samples, geometry: g,
                                              normal: c.normal, d: c.d, bandMm: band)
                }
                let winner = try #require(candidates.max {
                    rank($0, at: LiDARPlaneFitter.inlierBandMm)
                    < rank($1, at: LiDARPlaneFitter.inlierBandMm)
                })
                let coupledWinner = try #require(candidates.max {
                    rank($0, at: bandMm) < rank($1, at: bandMm)
                })
                let intended = try #require(candidates.min {
                    abs(SupportRegion.medianHeight(indices: samples.ring, geometry: g,
                                                   normal: $0.normal, d: $0.d))
                    < abs(SupportRegion.medianHeight(indices: samples.ring, geometry: g,
                                                     normal: $1.normal, d: $1.d))
                })
                let signs = Self.sectorSigns(samples: samples, geometry: g,
                                             normal: intended.normal, d: intended.d,
                                             count: SupportRegion.ringSectorCount,
                                             bandMm: bandMm)
                let innerMedian = Self.bandMediansMm(samples: samples, geometry: g,
                                                     normal: intended.normal, d: intended.d,
                                                     bandCount: SupportRegion.ringBandCount)[0]
                let bridges = candidates.map {
                    Self.bridgeReading(normal: $0.normal, d: $0.d, bandMm: bandMm,
                                       geometry: g, annulus: samples.annulus, gravity: gravity,
                                       references: references, scratch: scratch)
                }
                readings.append(Reading(
                    bandMm: bandMm,
                    candidateCount: candidates.count,
                    planeAtFoodMm: Self.planeDepthMm(normal: winner.normal, d: winner.d, ray: ray),
                    coupledPlaneAtFoodMm: Self.planeDepthMm(normal: coupledWinner.normal,
                                                            d: coupledWinner.d, ray: ray),
                    intendedRingMedianMm: SupportRegion.medianHeight(
                        indices: samples.ring, geometry: g,
                        normal: intended.normal, d: intended.d),
                    intendedCrossed: signs.crossedFailing,
                    intendedSupporting: signs.supporting,
                    intendedSupportFraction: rank(intended, at: bandMm),
                    intendedInnerBandMedianMm: innerMedian,
                    ringMedianGuardFires: abs(innerMedian) > bandMm,
                    maxSpan: bridges.map(\.span).max() ?? 0,
                    maxTiltDeg: bridges.map(\.tiltDeg).max() ?? 0,
                    ringFeasible: SupportRegion.ringBandsAreFeasible(samples: samples)))

                print("\(name) band \(fmt(bandMm)) mm: candidates \(candidates.count),"
                      + " plane at food \(fmt(readings[readings.count - 1].planeAtFoodMm))"
                      + " (coupled \(fmt(readings[readings.count - 1].coupledPlaneAtFoodMm))),"
                      + " intended ring median \(fmt(readings[readings.count - 1].intendedRingMedianMm)) mm,"
                      + " support \(fmt(readings[readings.count - 1].intendedSupportFraction)),"
                      + " supporting \(signs.supporting), crossed \(signs.crossedFailing),"
                      + " inner band median \(fmt(innerMedian)) mm"
                      + " (ringMedian guard fires: \(abs(innerMedian) > bandMm)),"
                      + " widest span \(bridges.map(\.span).max() ?? 0),"
                      + " max tilt \(fmt(bridges.map(\.tiltDeg).max() ?? 0))°")
                for (i, bridge) in bridges.enumerated() {
                    var envelope = ""
                    if bridge.span > 1 {
                        let pairs = bridge.spanned.flatMap { a in
                            bridge.spanned.filter { $0 > a }.map { b -> String in
                                let h = Self.separationMm(references[a], references[b],
                                                          geometry: g, annulus: samples.annulus)
                                return "\(a + 1)/\(b + 1) h = \(fmt(h)) mm,"
                                    + " ε/h = \(fmt(bandMm / max(h, 1e-6)))"
                            }
                        }
                        envelope = " — BRIDGES \(pairs.joined(separator: "; "))"
                    }
                    print("    pass \(i + 1): component \(bridge.componentSize),"
                          + " shares \(bridge.shares.map { fmt($0) }),"
                          + " unassigned \(fmt(bridge.unassigned)),"
                          + " tilt \(fmt(bridge.tiltDeg))°, span \(bridge.span)\(envelope)")
                }
            }
            byCapture[name] = readings
        }

        // FINDING 1. It moves the answer, and by more than any constant swept so far. Both
        // captures move ~18-19 mm at the food against the 1 mm Decision 35 measures Req 5.1's
        // transfer at — where `annulusOuterMm`, the only other owed constant that moves the
        // plane, moves 18.843 mm on one capture and 1.978 mm on the other (Decision 49), and
        // `ransacSuccessProbability` moves 3.704 mm on one (Decision 51). This is the first
        // to move BOTH by more than the grid transfer's whole budget, which is what a
        // constant that decides what an INLIER IS should be expected to do.
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let extraction = readings.map(\.planeAtFoodMm)
            let coupled = readings.map(\.coupledPlaneAtFoodMm)
            print("\(name): plane at the food over the band sweep —"
                  + " extraction only \(fmt((extraction.max() ?? 0) - (extraction.min() ?? 0))) mm,"
                  + " coupled \(fmt((coupled.max() ?? 0) - (coupled.min() ?? 0))) mm")
        }
        let narrowestMovement = Self.captures.map { name -> Float in
            let v = byCapture[name]?.map(\.planeAtFoodMm) ?? []
            return (v.max() ?? 0) - (v.min() ?? 0)
        }.min() ?? 0
        print("smallest movement of the selected plane over the band sweep,"
              + " across both captures: \(fmt(narrowestMovement)) mm")
        let bandIsInert = "the inlier band moves the selected plane by at most"
            + " \(fmt(narrowestMovement)) mm on some capture — it is bracket-only like the"
            + " count, the bar, the band count and the removal band, not a constant that"
            + " moves the answer"
        #expect(narrowestMovement > Self.gridTransferToleranceMm, "\(bandIsInert)")

        // FINDING 2. design.md's envelope table is measured, and the row it rests on is
        // outside the envelope. The table prices "plate above table" at h = 26 mm and
        // ε/h = 0.19, "inside the validated envelope", and concludes component scoring is
        // validated for the defect this feature fixes. The 26 mm is pipeline Decision 6's
        // plane ERROR at the food, not the step between the two surfaces over the annulus.
        // Measured, the closest competing pair is 19.464 mm and 11.706 mm, so the shipped
        // ε/h is 0.257 and 0.427 — the second outside Gallo's 0.25…0.35 envelope entirely
        // and in the same band as the table's own two "outside" rows (0.42 and 0.50).
        let quotedStepMm: Float = 26
        var worstRatio: Float = 0
        for name in Self.captures {
            let h = try #require(stepBetweenCompetingSurfacesMm[name])
            let ratio = LiDARPlaneFitter.inlierBandMm / h
            worstRatio = Swift.max(worstRatio, ratio)
            print("\(name): closest competing surfaces are \(fmt(h)) mm apart against the"
                  + " \(fmt(quotedStepMm)) mm design.md prices the row at — shipped ε/h ="
                  + " \(fmt(ratio)) against the envelope's 0.25…0.35")
        }
        let envelopeHolds = "every competing pair on the corpus is at least"
            + " \(fmt(LiDARPlaneFitter.inlierBandMm / worstRatio)) mm apart, so the shipped"
            + " ε/h stays at \(fmt(worstRatio)) and design.md's table row is measured as"
            + " written"
        #expect(worstRatio > 0.35, "\(envelopeHolds)")

        // FINDING 3. So the straddler is REAL, and design.md's open question — "whether the
        // smeared ramp bridges the two inlier sets is contested and unresolved… task 26
        // settles it by measurement; neither reading may be assumed" — resolves for the
        // first reading. At the SHIPPED band a candidate's largest connected component
        // holds at least a tenth of its members on each of two surfaces, on BOTH captures.
        //
        // Neither review predicted the mechanism. It is not that the ramp is crossable
        // (the first reading) and the cone does not prevent it (the second): the step is
        // less than half what the design priced, so the envelope was never satisfied.
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let spanning = readings.filter { $0.maxSpan > 1 }.map(\.bandMm)
            print("\(name): bands at which a candidate's component spans two surfaces:"
                  + " \(spanning.map { fmt($0) })")
            let shippedReading = try #require(
                readings.first { $0.bandMm == LiDARPlaneFitter.inlierBandMm })
            let noBridge = "no candidate on \(name) bridges two surfaces at the shipped"
                + " band — design.md's second reading holds and component scoring is not"
                + " straddling on this corpus"
            #expect(shippedReading.maxSpan > 1, "\(noBridge)")
        }

        // FINDING 4. And the cone the second reading's refutation rests on is not enforced.
        // That refutation is "the ramp's own slope is ~73°, a 15°-capped plane rises only
        // ~2.1 mm across its whole width, so the plane cannot TRACK the ramp". Measured, the
        // shipped candidate set on `1785135663727` contains a plane at 20.512° — and at a
        // 4 mm band the same slot reads 25.422°, against a stated cone of 15°.
        //
        // `extractCandidates` gates gravity on the RANSAC hypothesis and on every consensus
        // polish iteration, but NOT on the first refinement between them: `refine` is called
        // on the hypothesis's members and its result is assigned unchecked, and a polish that
        // reaches its fixed point on the first iteration leaves that plane standing. The cone
        // is an invariant of the hypotheses, not of the candidate set.
        //
        // Nothing shipped changes today — that candidate is rejected downstream on `extent`
        // and `supportFraction` — but it is one of the two surfaces the bridging above
        // happens across, so the two findings are the same finding. Repairing the gate would
        // remove a candidate and therefore MOVE the answer, which is a change this pass
        // measures rather than makes.
        let coneDeg = LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi
        for name in Self.captures {
            let tilt = try #require(shippedMaxTiltDeg[name])
            print("\(name): widest shipped candidate tilt \(fmt(tilt))°"
                  + " against a \(fmt(coneDeg))° cone")
        }
        let widestTilt = Self.captures.compactMap { shippedMaxTiltDeg[$0] }.max() ?? 0
        let coneIsAnInvariant = "every shipped candidate sits inside the \(fmt(coneDeg))°"
            + " gravity cone (widest \(fmt(widestTilt))°) — the first refinement's missing"
            + " gate is unreachable on this corpus and the cone is an invariant of the"
            + " candidate set after all"
        #expect(widestTilt > coneDeg, "\(coneIsAnInvariant)")

        // FINDING 5. The corpus interval is EMPTY at the shipped bars, and the two that
        // empty it are both owed and both denominated in this constant.
        //
        // Three constraints bound the band, all read on the plane a correct fit must select
        // (Decision 48's identification, the candidate nearest Req 3.1's zero). `ringMedian`
        // is a bar that IS the band, so below 4 mm the intended candidate fails it on both
        // captures (inner-band medians 6.117 and 4.685). `maxCrossedSectors` caps it from
        // above: at 6 mm the intended candidate on `1785901032716` reads 3 crossed against
        // the 2 Decision 48 determines. And `ringSupportMin` floors it: the intended
        // candidate's inner-band support rises with the band, since the band is the
        // tolerance the share is counted within.
        //
        // On `1785901032716` those last two are DISJOINT. Support reaches 0.6 only at 10 mm
        // and above; the crossed count stays at or below 2 only at 5 mm and below. No band
        // satisfies both, so the corpus interval is empty — Decision 41's "one constant
        // contradicts" and Decision 30's straddle, arriving on a constant one file over.
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let admissible = readings.filter {
                $0.intendedSupportFraction >= SupportRegion.ringSupportMin
                && !$0.ringMedianGuardFires
            }.map(\.bandMm)
            let withinCrossed = readings.filter { $0.intendedCrossed <= 2 }.map(\.bandMm)
            print("\(name): bands at which the intended candidate clears ringSupportMin and"
                  + " ringMedian: \(admissible.map { fmt($0) }); bands at which it reads at"
                  + " most 2 crossed sectors: \(withinCrossed.map { fmt($0) });"
                  + " candidate counts \(readings.map { "\(fmt($0.bandMm)):\($0.candidateCount)" })")
        }
        func feasibleBands(supportMin: Float) -> [Float] {
            Self.inlierBandSweep.filter { band in
                Self.captures.allSatisfy { name in
                    guard let r = byCapture[name]?.first(where: { $0.bandMm == band }) else {
                        return false
                    }
                    return r.intendedSupportFraction >= supportMin
                        && !r.ringMedianGuardFires && r.intendedCrossed <= 2
                }
            }
        }
        let atShippedBar = feasibleBands(supportMin: SupportRegion.ringSupportMin)
        print("bands satisfying every corpus constraint at the shipped ringSupportMin"
              + " (\(fmt(SupportRegion.ringSupportMin))): \(atShippedBar.map { fmt($0) })")
        let barsHaveARoom = "the corpus admits \(atShippedBar.map { fmt($0) }) at the shipped"
            + " ringSupportMin — the band has a non-empty interval and the two owed bars do"
            + " not collide on it"
        #expect(atShippedBar.isEmpty, "\(barsHaveARoom)")

        // What it takes to make it non-empty, which hands `ringSupportMin` a bound this pass
        // did not set out to measure. The largest support the intended candidate reaches at
        // ANY band the sector rule still admits is 0.362, at 5 mm — so `ringSupportMin` must
        // be at or below 0.362 for the corpus to admit any band at all, and at that bar the
        // interval is exactly the shipped 5 mm. Decision 42 measured 0.362 as the value at
        // the shipped band; over the whole sweep it is the CEILING, and the corpus's only
        // ceiling on a constant Decision 29 recorded as having none.
        let barSweep: [Float] = [0.2, 0.25, 0.281, 0.3, 0.362, 0.4, 0.5, 0.6]
        for bar in barSweep {
            print("  ringSupportMin \(fmt(bar)) → bands \(feasibleBands(supportMin: bar).map { fmt($0) })")
        }
        let ceiling = Self.captures.compactMap { name -> Float? in
            byCapture[name]?.filter { $0.intendedCrossed <= 2 && !$0.ringMedianGuardFires }
                .map(\.intendedSupportFraction).max()
        }.min() ?? 0
        print("largest inner-band support the intended candidate reaches at any band the"
              + " sector rule admits, on the tightest capture: \(fmt(ceiling))")
        let noNewCeiling = "the intended candidate reaches \(fmt(ceiling)) support at some"
            + " admissible band on every capture — the shipped ringSupportMin of"
            + " \(fmt(SupportRegion.ringSupportMin)) is reachable and this pass sets no"
            + " ceiling on it"
        #expect(ceiling < SupportRegion.ringSupportMin, "\(noNewCeiling)")
        #expect(feasibleBands(supportMin: ceiling) == [LiDARPlaneFitter.inlierBandMm],
                "the band the corpus admits at its own ringSupportMin ceiling moved off 5 mm")

        // And the readings WANDER rather than climb, so like Decision 46's radius and
        // Decision 51's target — and unlike Decision 50's removal band — the bracket must
        // not be interpolated. The support share would rise monotonically at a FIXED plane,
        // since a wider tolerance can only admit more samples; it does not, because
        // extraction re-runs at every band and the candidate is re-selected under it
        // (0.312 at 3 mm falling to 0.281 at 4 mm on `1785901032716`).
        var wanders = false
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            print("\(name): intended candidate's inner-band support against the band:"
                  + " \(readings.map { "\(fmt($0.bandMm)) → \(fmt($0.intendedSupportFraction))" }.joined(separator: ", "))")
            let fractions = readings.map(\.intendedSupportFraction)
            let climbs = zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 + 1e-6 }
            print("  monotone in the band: \(climbs)")
            if !climbs { wanders = true }
        }
        let readingsClimb = "the intended candidate's support climbs monotonically with the"
            + " band on both captures — the plane is not re-selected under the sweep and the"
            + " bracket may be interpolated"
        #expect(wanders, "\(readingsClimb)")
    }

    // The committed suite's silence on this constant is a THIRD kind. Decision 49's bound
    // reached the scenes through two guards and was found silent by measurement; Decision
    // 50's removal band could not be read at all, because no scene runs extraction. This
    // constant DOES reach the scenes — as `ringBandMm` it is the tolerance every sector is
    // classified within and the magnitude bar Decision 40's rule inherits — and the suite
    // still reads the same verdict at every band from 1 to 12.5 mm.
    //
    // The reason is measurable rather than structural: `SPRScene.makeDepth` adds ±0.3 mm of
    // synthetic sensor noise, so every scene sample sits within a third of a millimetre of
    // its own surface and any tolerance across the whole sweep classifies it identically.
    // The scenes validate the LOGIC of every guard and no tolerance in any of them.
    @Test("the committed suite reads the inherited half of the inlier band and is silent on the other")
    func theCommittedSuiteReadsOnlyTheInheritedHalfOfTheBand() throws {
        let readings = Self.sceneReadings()
        #expect(readings.count == 8, "a scene stopped producing ring statistics")

        var intervals: Set<String> = []
        for bandMm in Self.inlierBandSweep {
            // `supportFraction` at the swept band, against the scenes whose committed
            // assertions require that guard to pass or to fire.
            let supportBroken = readings.filter { reading in
                let fraction = reading.supportFraction(bandMm: bandMm)
                if reading.requiresPass.contains(.supportFraction) {
                    return fraction < SupportRegion.ringSupportMin
                }
                if reading.requiresFire.contains(.supportFraction) {
                    return fraction >= SupportRegion.ringSupportMin
                }
                return false
            }.map(\.label)

            // `ringMedianMaxMm` moves with the band, so the scenes that must pass every
            // guard must keep clearing it.
            let medianBroken = readings.filter { reading in
                reading.requiresPass.contains(.supportFraction)
                && abs(reading.innerBandMedianMm) > bandMm
            }.map(\.label)

            // Decision 40's rule at the swept band: the magnitude bar IS `ringBandMm`.
            let mustPass = readings.filter { $0.requiresPass.contains(.sectors) }
            let mustFire = readings.filter { $0.requiresFire.contains(.sectors) }
            let crossedFloor = mustPass.map {
                $0.signs(at: SupportRegion.ringSectorCount, bandMm: bandMm).crossedFailing
            }.max() ?? 0
            let crossedCeiling = mustFire.map {
                $0.signs(at: SupportRegion.ringSectorCount, bandMm: bandMm).crossedFailing - 1
            }.min() ?? Int.max
            let supportingFloor = mustFire.map {
                $0.signs(at: SupportRegion.ringSectorCount, bandMm: bandMm).supporting + 1
            }.max() ?? 0
            let supportingCeiling = mustPass.map {
                $0.signs(at: SupportRegion.ringSectorCount, bandMm: bandMm).supporting
            }.min() ?? Int.max

            print("band \(fmt(bandMm)) mm: maxCrossedSectors \(crossedFloor)…\(crossedCeiling),"
                  + " minSupportingSectors \(supportingFloor)…\(supportingCeiling),"
                  + " supportFraction verdicts broken on \(supportBroken),"
                  + " ringMedian verdicts broken on \(medianBroken)")
            intervals.insert("\(crossedFloor)…\(crossedCeiling)/"
                             + "\(supportingFloor)…\(supportingCeiling)/"
                             + "\(supportBroken.count)/\(medianBroken.count)")
        }

        // One reading across an order of magnitude of tolerance. The suite gives this
        // constant no floor and no ceiling, so the corpus is its only source — as it was
        // `annulusOuterMm`'s (Decision 49) and `inlierRemovalMultiple`'s (Decision 50).
        print("distinct suite readings across the whole band sweep: \(intervals.count)")
        let suiteBoundsTheBand = "the committed suite reads \(intervals.count) different"
            + " verdict sets across the band sweep — it does bound this constant and the"
            + " sitting has a second source to track"
        #expect(intervals.count == 1, "\(suiteBoundsTheBand)")

        // And the reason, asserted where it lives: the scenes' noise is an order of
        // magnitude below the smallest band swept, so the tolerance is never the binding
        // quantity in any of them.
        let sceneNoiseMm: Float = 0.3
        #expect(sceneNoiseMm * 3 < Self.inlierBandSweep.min() ?? 0,
                "SPRScene's noise reached the band sweep — the suite's silence needs re-reading")
    }

    // MARK: - τ_conf: the constant upstream of the one Decision 52 found

    // Decision 52 followed four `[inherited]` markers out of `SupportRegion` and into
    // `LiDARPlaneFitter.inlierBandMm`, "the most upstream constant, because it decides what
    // an INLIER is". There is one further step up the same file: `confidenceThreshold`
    // decides what a SAMPLE is, and every sample the inlier test is applied to has already
    // passed it. `SupportRegion.prepare` reads it directly, so it governs the promoted path
    // and the legacy band scan alike.
    //
    // It differs from every constant swept so far in KIND, and the difference is the finding:
    // its domain is not an interval. ARKit reports three confidence LEVELS, scaled to bytes
    // 0/127/255, so τ_conf has exactly three behaviours over the whole of [0, 1] — accept
    // LOW and up, accept MEDIUM and up, accept HIGH only. A twelve-value sweep therefore
    // enumerates the domain EXHAUSTIVELY rather than sampling it, which no other bracket in
    // Decisions 29-52 does.
    @Test("the confidence bar has three states, not a bracket, and it moves the plane")
    func theConfidenceBarHasThreeStatesRatherThanABracket() throws {
        // The premise. Three levels is an ARKit fact; that these slices contain nothing else
        // is a measurement, and it is what makes the three states exhaustive.
        for name in Self.captures + Self.rejectedCaptures {
            let slice = try DepthSlice.load(name)
            var histogram: [UInt8: Int] = [:]
            for byte in slice.depth.confidenceBytes { histogram[byte, default: 0] += 1 }
            print("\(name): confidence bytes"
                  + " \(histogram.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" })")
            let unexpected = Set(histogram.keys).subtracting(Self.arkitConfidenceBytes)
            let notQuantised = "\(name) carries confidence bytes \(unexpected.sorted()) outside"
                + " the three ARKit levels — τ_conf has more than three states and this whole"
                + " derivation has to be re-read as a continuous sweep"
            #expect(unexpected.isEmpty, "\(notQuantised)")
        }

        // The anchor on the mechanism. At the shipped bar the rewritten map must admit exactly
        // the samples the untouched one does, or the sweep is measuring a different corpus.
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let shipped = try #require(Self.geometry(name))
            let rewritten = Self.reconfidenced(slice, tauConf: LiDARPlaneFitter.confidenceThreshold)
            let mirrored = try #require(SupportRegion.prepare(
                depth: rewritten.depth, colourIntrinsics: rewritten.colourIntrinsics,
                foodRegionMask: rewritten.foodMask))
            let drifted = "\(name): the rewritten confidence map does not reproduce the shipped"
                + " validity set at the shipped bar"
            #expect(mirrored.valid == shipped.valid, "\(drifted)")
            #expect(mirrored.foodIndices == shipped.foodIndices,
                    "\(name): the rewritten confidence map moves the food sample set")
        }

        var byCapture: [String: [TauReading]] = [:]
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            var readings: [TauReading] = []
            for tau in Self.tauConfSweep {
                guard let reading = Self.tauReading(slice, tauConf: tau) else {
                    print("\(name) at τ_conf \(fmt(tau)): NO plane — the fit is starved")
                    continue
                }
                readings.append(reading)
                print("\(name) τ_conf \(fmt(tau)): valid \(reading.validCount),"
                      + " food \(reading.foodSampleCount), annulus \(reading.annulusCount),"
                      + " ring \(reading.ringCount) (feasible \(reading.ringFeasible)),"
                      + " passes \(reading.passCount), plane at food \(fmt(reading.planeAtFoodMm)) mm,"
                      + " intended pass \(reading.intendedPass),"
                      + " ring median \(fmt(reading.intendedRingMedianMm)) mm,"
                      + " support \(fmt(reading.intendedSupportFraction)),"
                      + " supporting \(reading.intendedSupporting),"
                      + " crossed \(reading.intendedCrossed),"
                      + " envelope \(fmt(reading.intendedEnvelopeMm)) mm")
            }
            #expect(readings.count == Self.tauConfSweep.count,
                    "\(name): some τ_conf in the sweep produced no plane at all")
            byCapture[name] = readings
        }

        // FINDING 1. Twelve values, three readings. The state boundaries are exactly 0 and
        // the MEDIUM level, so "do not interpolate" — the rider Decisions 46, 51 and 52 all
        // carry — does not apply here: there is nothing between the states to interpolate to.
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let states = Set(readings.map(\.validCount))
            print("\(name): \(Self.tauConfSweep.count) values swept →"
                  + " \(states.count) distinct sample sets \(states.sorted())")
            let tooFine = "\(name) resolves \(states.count) sample sets across the sweep —"
                + " τ_conf is finer-grained than the three ARKit levels"
            #expect(states.count <= 3, "\(tooFine)")
            for reading in readings {
                let expectedState = reading.tauConf <= 0 ? 0
                    : (reading.tauConf <= Self.mediumConfidence ? 1 : 2)
                let sameState = readings.filter {
                    ($0.tauConf <= 0 ? 0 : ($0.tauConf <= Self.mediumConfidence ? 1 : 2))
                        == expectedState
                }
                let strayed = "\(name): τ_conf \(fmt(reading.tauConf)) does not agree with the"
                    + " rest of its state — the boundaries are not at 0 and"
                    + " \(fmt(Self.mediumConfidence))"
                #expect(sameState.allSatisfy { $0.validCount == reading.validCount },
                        "\(strayed)")
            }
        }

        // FINDING 2. It moves the answer. `annulusOuterMm` (Decision 49),
        // `ransacSuccessProbability` (51) and `inlierBandMm` (52) are the only other owed
        // constants that do, and this one moves the selected plane past the 1 mm Decision 35
        // measures Req 5.1's transfer at on one of the two captures. It also moves the PASS
        // COUNT, which couples it to Decision 48's cap and Decision 50's ordering.
        var largestMovement: Float = 0
        for name in Self.captures {
            let readings = try #require(byCapture[name])
            let planes = readings.map(\.planeAtFoodMm)
            let movement = (planes.max() ?? 0) - (planes.min() ?? 0)
            largestMovement = max(largestMovement, movement)
            print("\(name): plane at the food over the three states"
                  + " \(Set(planes.map { fmt($0) }).sorted()) — \(fmt(movement)) mm;"
                  + " pass counts \(Set(readings.map(\.passCount)).sorted())")
        }
        let planeToleranceMm: Float = 1
        let barIsInert = "τ_conf moves the selected plane by at most \(fmt(largestMovement)) mm"
            + " on every capture — it is bracket-only like the sector count and the band count,"
            + " not a constant that moves the answer"
        #expect(largestMovement > planeToleranceMm, "\(barIsInert)")

        // FINDING 3. The FLOOR is measured and it is strictly above zero — on ONE capture.
        // Admitting LOW moves the plane 2.003 mm on `1785135663727` and pushes the intended
        // candidate's inner-band median away from the zero Req 3.1 wants, so the accept-all
        // state is ruled out and the choice is between the upper two. The other capture cannot
        // price it: 36 of its 49,152 pixels are LOW, 0.07 %, and admitting all of them moves
        // nothing to three decimal places. So this floor rests on a single capture, which is
        // the same one-capture footing Decision 36 recorded for `fallbackPenalty`.
        var canPriceTheFloor: [String] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let readings = try #require(byCapture[name])
            let acceptAll = try #require(readings.first { $0.tauConf <= 0 })
            let shipped = try #require(readings.first {
                $0.tauConf == LiDARPlaneFitter.confidenceThreshold
            })
            let lowShare = Float(acceptAll.validCount - shipped.validCount)
                / Float(slice.depth.width * slice.depth.height)
            print("\(name): accepting LOW adds"
                  + " \(acceptAll.validCount - shipped.validCount) samples (\(fmt(lowShare)) of"
                  + " the grid) and moves the plane"
                  + " \(fmt(abs(acceptAll.planeAtFoodMm - shipped.planeAtFoodMm))) mm;"
                  + " intended inner median \(fmt(shipped.intendedInnerMedianMm)) →"
                  + " \(fmt(acceptAll.intendedInnerMedianMm)) mm")
            guard lowShare >= Self.materialLowShare else { continue }
            canPriceTheFloor.append(name)
            let lowIsHarmless = "\(name): accepting LOW samples no longer degrades the intended"
                + " candidate's inner-band median — τ_conf's floor of 0 is not measured any more"
            #expect(abs(acceptAll.intendedInnerMedianMm) > abs(shipped.intendedInnerMedianMm),
                    "\(lowIsHarmless)")
        }
        print("captures carrying a material LOW population: \(canPriceTheFloor)")
        let floorIsBroadlyBased = "more than one capture now carries a material LOW population —"
            + " τ_conf's floor is no longer resting on \(canPriceTheFloor.first ?? "one capture")"
            + " alone"
        #expect(canPriceTheFloor.count == 1, "\(floorIsBroadlyBased)")

        // FINDING 4. The corpus cannot reproduce the bug that set the shipped value, and on
        // the captures it does contain the state the shipped value REJECTS reads better.
        // `lidar-plane-fit-matte-table-confidence` lowered the bar from 0.66 to 0.40 because
        // HIGH-only starved the fit into `noLidarPoints`; at HIGH-only both committed captures
        // still fit, on the promoted path and on the fitter's own band scan, and the intended
        // candidate's inner-band support RISES on both. The floor argument the shipped value
        // rests on is evidence outside this corpus, so the corpus must not re-set the constant
        // in either direction — a matte-table capture is a requirement of the sitting.
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let readings = try #require(byCapture[name])
            let shipped = try #require(readings.first {
                $0.tauConf == LiDARPlaneFitter.confidenceThreshold
            })
            let highOnly = try #require(readings.first { $0.tauConf > Self.mediumConfidence })
            let starved = Self.fallbackPlane(
                Self.reconfidenced(slice, tauConf: HeightFieldEstimator.tauConfidence)) == nil
            print("\(name) at HIGH only: \(highOnly.validCount) of \(shipped.validCount) samples"
                  + " survive, ring feasible \(highOnly.ringFeasible),"
                  + " passes \(shipped.passCount) → \(highOnly.passCount),"
                  + " intended support \(fmt(shipped.intendedSupportFraction)) →"
                  + " \(fmt(highOnly.intendedSupportFraction)), supporting"
                  + " \(shipped.intendedSupporting) → \(highOnly.intendedSupporting),"
                  + " band-scan fit starved: \(starved)")
            let ringStarves = "\(name): the ring stops clearing ringMinSamples at HIGH only —"
                + " the corpus now reproduces the matte-table starvation and τ_conf has a"
                + " corpus floor"
            #expect(highOnly.ringFeasible, "\(ringStarves)")
            let scanStarves = "\(name): the fitter's band scan refuses at HIGH only — the corpus"
                + " now reproduces lidar-plane-fit-matte-table-confidence"
            #expect(!starved, "\(scanStarves)")
            let noImprovement = "\(name): the intended candidate's support no longer improves at"
                + " HIGH only — the corpus's mild argument against the shipped state has gone"
            #expect(highOnly.intendedSupportFraction > shipped.intendedSupportFraction,
                    "\(noImprovement)")
            let sectorsStill = "\(name): the supporting-sector count no longer rises by exactly"
                + " one at HIGH only — Decision 41's interval reading needs re-checking"
            #expect(highOnly.intendedSupporting == shipped.intendedSupporting + 1,
                    "\(sectorsStill)")
        }

        // FINDING 5. Decision 41's one genuinely EMPTY joint interval is denominated here. On
        // `1785135663727` the intended candidate reads 5 supporting sectors at the shipped bar
        // — "so minSupportingSectors must fall to 5 or below", against a suite floor of 6 that
        // no value could satisfy — and 6 at HIGH only, where 6…6 is non-empty. It does not
        // RESOLVE the collision: `1785901032716`'s tighter reading rises 2 → 3 and stays far
        // below the floor. What it establishes is that the contradiction is a reading at a
        // constant this task owes, on the capture it was recorded on.
        let collisionCapture = "1785135663727"
        let collisionReadings = try #require(byCapture[collisionCapture])
        let atShipped = try #require(collisionReadings.first {
            $0.tauConf == LiDARPlaneFitter.confidenceThreshold
        })
        let atHighOnly = try #require(collisionReadings.first { $0.tauConf > Self.mediumConfidence })
        print("\(collisionCapture): minSupportingSectors' corpus ceiling"
              + " \(atShipped.intendedSupporting) → \(atHighOnly.intendedSupporting)"
              + " against the committed suite's floor of 6")
        let collisionStands = "the supporting count no longer crosses the suite's floor of 6"
            + " between the two states — Decision 41's collision is not denominated in τ_conf"
            + " after all"
        #expect(atShipped.intendedSupporting < 6 && atHighOnly.intendedSupporting >= 6,
                "\(collisionStands)")

        // FINDING 6, and the reason this constant is upstream rather than beside: BOTH of
        // Decision 52's determinations move. That decision measured the corpus interval for
        // the inlier band to be empty at the shipped bars, non-empty only once `ringSupportMin`
        // falls to 0.362 or below, and there exactly the shipped 5 mm — handing `ringSupportMin`
        // its first corpus ceiling. Re-read at HIGH only, the ceiling is 0.497 and the band the
        // corpus points at is 6 mm. So Decision 52's three-way joint set is FOUR-way, with
        // τ_conf at its head: it decides what a sample is, before the band decides which
        // samples are inliers.
        var gridByState: [Float: [String: [TauReading]]] = [:]
        for tau in [Float(0), LiDARPlaneFitter.confidenceThreshold, 1] {
            var byName: [String: [TauReading]] = [:]
            for name in Self.captures {
                let slice = try DepthSlice.load(name)
                byName[name] = Self.inlierBandSweep.compactMap {
                    Self.tauReading(slice, tauConf: tau, bandMm: $0)
                }
            }
            gridByState[tau] = byName
        }
        func determination(_ byName: [String: [TauReading]]) -> (ceiling: Float, bands: [Float]) {
            let ceiling = Self.captures.compactMap { name -> Float? in
                byName[name]?.filter { $0.intendedCrossed <= 2 && !$0.ringMedianGuardFires }
                    .map(\.intendedSupportFraction).max()
            }.min() ?? 0
            let bands = Self.inlierBandSweep.filter { band in
                Self.captures.allSatisfy { name in
                    guard let r = byName[name]?.first(where: { $0.bandMm == band }) else {
                        return false
                    }
                    return r.intendedSupportFraction >= ceiling
                        && !r.ringMedianGuardFires && r.intendedCrossed <= 2
                }
            }
            return (ceiling, bands)
        }
        for tau in gridByState.keys.sorted() {
            let read = determination(try #require(gridByState[tau]))
            print("τ_conf \(fmt(tau)): ringSupportMin's corpus ceiling \(fmt(read.ceiling)),"
                  + " inlier bands the corpus admits there \(read.bands.map { fmt($0) })")
        }
        let shippedState = determination(try #require(gridByState[LiDARPlaneFitter.confidenceThreshold]))
        let highOnlyState = determination(try #require(gridByState[1]))
        let bandMoved = "the band the corpus admits at its own ringSupportMin ceiling is no"
            + " longer the shipped 5 mm at the shipped bar — Decision 52's reading has moved"
        #expect(shippedState.bands == [LiDARPlaneFitter.inlierBandMm], "\(bandMoved)")
        let ceilingIsFixed = "ringSupportMin's corpus ceiling no longer rises at HIGH only —"
            + " Decision 52's first ceiling for it is not denominated in τ_conf after all"
        #expect(highOnlyState.ceiling > shippedState.ceiling, "\(ceilingIsFixed)")
        let bandIsFixed = "the inlier band the corpus determines no longer moves with τ_conf —"
            + " Decision 52's conditional determination is not a slice at this bar after all"
        #expect(highOnlyState.bands != shippedState.bands, "\(bandIsFixed)")

        // FINDING 7, the one positive: `maxCrossedSectors` reads the same in all three states
        // at the shipped band, so Decision 48's determination at 2 survives τ_conf DIRECTLY.
        // It survives only there — at HIGH only the band the corpus points at is 6 mm, where
        // the intended candidate reads fewer crossed sectors — so it remains a reading at the
        // shipped band, which is what Decision 48 already says it is.
        let crossedCapture = "1785901032716"
        let crossedAtShippedBand = Set((byCapture[crossedCapture] ?? []).map(\.intendedCrossed))
        print("\(crossedCapture): crossed sectors at the shipped band across all three states"
              + " \(crossedAtShippedBand.sorted())")
        let crossedMoves = "\(crossedCapture)'s crossed count moves with τ_conf at the shipped"
            + " band — Decision 48's determination of maxCrossedSectors at 2 is a slice at this"
            + " bar too"
        #expect(crossedAtShippedBand == [2], "\(crossedMoves)")
    }

    // τ_conf is TWO constants under one name, which is Decision 32's `minCandidateSamples`
    // shape a second time — and this time the two values fall on OPPOSITE sides of the only
    // boundary in the domain. `LiDARPlaneFitter.confidenceThreshold` = 0.40 admits MEDIUM;
    // `HeightFieldEstimator.tauConfidence` = 0.66, the value the fitter's bar was lowered
    // FROM, admits HIGH only. One pipeline reads one confidence surface at two levels, so the
    // support plane is fitted to MEDIUM and HIGH samples while the food volume above it is
    // integrated over HIGH alone.
    //
    // Not repaired here. Aligning them adds or removes samples on every capture and moves the
    // answer, which is the same discipline Decision 52 applied to the unenforced gravity gate.
    // What is recorded is the consequence for the corpus's own composition, because Decision
    // 31 excluded a capture on a number read at the support plane's bar.
    @Test("the confidence bar is two constants, and they straddle the MEDIUM level")
    func theConfidenceBarIsTwoConstantsStraddlingTheMediumLevel() throws {
        print("support plane τ_conf \(fmt(LiDARPlaneFitter.confidenceThreshold)),"
              + " height field τ_conf \(fmt(HeightFieldEstimator.tauConfidence)),"
              + " MEDIUM level \(fmt(Self.mediumConfidence))")
        let aligned = "the two τ_conf values no longer straddle the MEDIUM level — the support"
            + " plane and the height field now read the same confidence states and this"
            + " divergence is closed"
        #expect(LiDARPlaneFitter.confidenceThreshold < Self.mediumConfidence
                && HeightFieldEstimator.tauConfidence > Self.mediumConfidence, "\(aligned)")

        // Decision 31's disqualifying number, read at both bars. "43.2 % of its food mask is
        // ARKit-low against 0.0 % on both admitted captures" is the SUPPORT PLANE's reading;
        // at the bar that actually consumes the food samples neither admitted capture reads 0.
        for name in Self.captures + Self.rejectedCaptures {
            let slice = try DepthSlice.load(name)
            let atFitter = Self.lowConfidenceFoodShare(slice, tauConf: LiDARPlaneFitter.confidenceThreshold)
            let atHeightField = Self.lowConfidenceFoodShare(slice, tauConf: HeightFieldEstimator.tauConfidence)
            print("\(name): food discarded at the support plane's bar \(fmt(atFitter)),"
                  + " at the height field's \(fmt(atHeightField))")
            if Self.captures.contains(name) {
                #expect(atFitter == 0, "\(name) stopped reading 0 at the support plane's bar")
                let agrees = "\(name) now reads 0 at the height field's bar too — Decision 31's"
                    + " zero on both admitted captures holds at both bars after all"
                #expect(atHeightField > 0, "\(agrees)")
            }
        }

        // And the exclusion itself, which is CIRCULAR in this constant. Decision 31 rejected
        // `1785054950406` because τ_conf removes its mound and the surviving food then sits
        // BELOW the plane fitted around it, "so there is no mound left to anchor a non-flat
        // criterion against". At τ_conf = 0 the same slice reads a POSITIVE food envelope: the
        // mound is in the data, and the second ground is a restatement of the first.
        //
        // The exclusion still holds, on a grounds Decision 31 did not state: the samples the
        // mound is made of are the ones ARKit marks unreliable, and admitting them wrecks the
        // ring fit the capture would have to anchor — its intended candidate's ring median goes
        // from a near-exact −0.018 mm to −4.589 mm. The third ground REVERSES: the spurious
        // separable sector count Decision 31 committed the slice to prevent does not appear in
        // either state below the MEDIUM level, and does appear at HIGH only.
        for name in Self.rejectedCaptures {
            let slice = try DepthSlice.load(name)
            let acceptAll = try #require(Self.tauReading(slice, tauConf: 0))
            let shipped = try #require(Self.tauReading(
                slice, tauConf: LiDARPlaneFitter.confidenceThreshold))
            let highOnly = try #require(Self.tauReading(slice, tauConf: 1))
            for reading in [acceptAll, shipped, highOnly] {
                print("\(name) at τ_conf \(fmt(reading.tauConf)): food"
                      + " \(reading.foodSampleCount), envelope \(fmt(reading.intendedEnvelopeMm)) mm,"
                      + " ring median \(fmt(reading.intendedRingMedianMm)) mm,"
                      + " supporting \(reading.intendedSupporting)")
            }
            let noMound = "\(name)'s food envelope no longer changes sign between accepting LOW"
                + " and the shipped bar — Decision 31's second ground is not circular in τ_conf"
            #expect(acceptAll.intendedEnvelopeMm > 0 && shipped.intendedEnvelopeMm < 0,
                    "\(noMound)")
            let lowIsClean = "\(name)'s ring fit no longer degrades when LOW samples are"
                + " admitted — the ground the exclusion actually stands on has gone"
            #expect(abs(acceptAll.intendedRingMedianMm) > abs(shipped.intendedRingMedianMm),
                    "\(lowIsClean)")
            let trapMoved = "\(name)'s spurious separable sector count no longer appears at HIGH"
                + " only alone — Decision 31's third ground needs re-reading"
            #expect(acceptAll.intendedSupporting < 4 && shipped.intendedSupporting < 4
                    && highOnly.intendedSupporting >= 4, "\(trapMoved)")
        }
    }

    // MARK: - The consensus polish, and the loop the gravity gate is missing from

    // Why the loop stopped. Reported per pass, because the constant is a CAP and a cap that
    // never binds is not what sets the answer — the same shape as `maxIterationsPerPass`
    // (Decision 51), one loop further in.
    enum PolishStop: String {
        case fixedPoint          // the consensus set stopped changing — the stated exit
        case underpopulated      // the re-selection fell below `minPoints`
        case degenerate          // `refine` refused the re-selected set
        case gravity             // the loop's OWN gate rejected the re-refined plane
        case cap                 // `consensusPolishMaxPasses` truncated it
    }

    struct PolishTrace {
        let passIndex: Int
        let iterations: Int            // polish iterations actually APPLIED
        let stop: PolishStop
        // The ungated plane the loop starts from: `ccRansac`'s winner refined once. Decision
        // 52's measured gap lives exactly here.
        let refinementTiltDeg: Float
        let finalTiltDeg: Float
        var refinementOutsideCone: Bool {
            refinementTiltDeg > LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi
        }
        var finalOutsideCone: Bool {
            finalTiltDeg > LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi
        }
    }

    // `SupportRegion.extractCandidates` with the polish cap as an argument, and with the
    // loop instrumented. Every other line is the shipped path's — the same `ccRansac`, the
    // same ungated first refinement, the same component-based re-selection, the same gate on
    // the re-refined plane, the same removal — so at `consensusPolishMaxPasses` it
    // reproduces the shipped call exactly, which the anchor below checks candidate by
    // candidate.
    //
    // The polish is NOT a prefix chain the way the pass cap is (Decision 48). A shallower
    // polish leaves a different plane, so it removes a different shell, so the next pass
    // draws from a different residue and `uniformInt` reads a different n — the RNG stream
    // diverges after pass 1. One run per depth, therefore, not one run at the top.
    static func extractCandidates(
        annulus: [Int], geometry g: SupportRegion.DepthGeometry,
        gravity: Vec3, rng: inout SplitMix64, polishPasses: Int,
        trace: inout [PolishTrace]
    ) -> [SupportRegion.PlaneCandidate] {
        var residue = annulus
        var candidates: [SupportRegion.PlaneCandidate] = []
        let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)
        let residueFloor = SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)

        func tiltDeg(_ n: Vec3) -> Float {
            acos(SupportRegion.clampedCosine(n.dot(gravity))) * 180 / .pi
        }

        for passIndex in 0..<SupportRegion.maxCandidatePlanes {
            guard residue.count >= residueFloor else { break }
            guard let hypothesis = SupportRegion.ccRansac(
                indices: residue, geometry: g, gravity: gravity,
                rng: &rng, scratch: scratch) else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1
            let refinementTilt = tiltDeg(normal)

            var applied = 0
            var stop = PolishStop.cap
            for _ in 0..<polishPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue
                where abs(normal.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers { stop = .fixedPoint; break }
                if next.count < LiDARPlaneFitter.minPoints { stop = .underpopulated; break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { stop = .degenerate; break }
                if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity)))
                    > LiDARPlaneFitter.gravityAngleMaxRad {
                    stop = .gravity
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
                applied += 1
            }
            trace.append(PolishTrace(passIndex: passIndex, iterations: applied, stop: stop,
                                     refinementTiltDeg: refinementTilt,
                                     finalTiltDeg: tiltDeg(normal)))

            let component = scratch.largestComponent(of: inliers)
            candidates.append(SupportRegion.PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count))

            let removalBandMm = SupportRegion.inlierRemovalMultiple * LiDARPlaneFitter.inlierBandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return candidates
    }

    // The OTHER call site. `LiDARPlaneFitter.fitOutcome` runs the same loop over the same
    // constant, on a different sample set (colour-grid edge bands rather than the depth
    // annulus) and with a plain inlier re-selection rather than a connected one. This is the
    // plane Req 4.3 pins byte-identical and Req 4.6 prices, so a sweep of the constant has to
    // report both legs or it is measuring half of it.
    struct FallbackReading {
        let planeAtFoodMm: Float
        let tiltDeg: Float
        let residualMm: Float
        let inlierCount: Int
        let iterations: Int
        let stop: PolishStop
    }

    static func fallbackReading(_ slice: DepthSlice, polishPasses: Int,
                                ray: Vec3) -> FallbackReading? {
        let inputs = LiDARPlaneFitter.Inputs(
            depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
            foodRegionMask: slice.colourFoodMask, gravityCamera: slice.gravity)
        var stats = SupportPlaneFitStats()
        let points = LiDARPlaneFitter.collectCandidatePoints(inputs, stats: &stats)
        guard points.count >= LiDARPlaneFitter.minPoints else { return nil }

        var rng = SplitMix64(seed: Fnv1a64.hash(inputs.depth.depthBytesMm))
        let gravity = inputs.gravityCamera.normalised()
        let (bestNormal, _, bestInliers) = LiDARPlaneFitter.ransac(
            points: points, gravity: gravity, rng: &rng)
        guard bestInliers.count >= LiDARPlaneFitter.minPoints else { return nil }
        guard let refined = try? LiDARPlaneFitter.refine(
            inliers: bestInliers.map { points[$0] }, seedNormal: bestNormal) else { return nil }

        var normal = refined.0
        var d = refined.1
        var polishedInliers = bestInliers
        var applied = 0
        var stop = PolishStop.cap
        for _ in 0..<polishPasses {
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(normal.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                reselected.append(idx)
            }
            if reselected == polishedInliers { stop = .fixedPoint; break }
            if reselected.count < LiDARPlaneFitter.minPoints { stop = .underpopulated; break }
            guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                inliers: reselected.map { points[$0] }, seedNormal: normal
            ) else { stop = .degenerate; break }
            if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity)))
                > LiDARPlaneFitter.gravityAngleMaxRad { stop = .gravity; break }
            polishedInliers = reselected
            normal = nextNormal
            d = nextD
            applied += 1
        }

        return FallbackReading(
            planeAtFoodMm: Self.planeDepthMm(normal: normal, d: d, ray: ray),
            tiltDeg: acos(SupportRegion.clampedCosine(normal.dot(gravity))) * 180 / .pi,
            residualMm: LiDARPlaneFitter.computeResidual(
                points: polishedInliers.map { points[$0] }, normal: normal, d: d),
            inlierCount: polishedInliers.count,
            iterations: applied, stop: stop)
    }

    // 0 is the floor with a meaning: the pre-polish plane, which is `ccRansac`'s winner
    // refined once and is exactly what `estimation-runtime-consistency` added the loop to
    // replace. The top has to be wherever the loop actually reaches its stated fixed point,
    // which the comment says is below 3 and which the corpus puts above 16.
    static let polishPassSweep = [0, 1, 2, 3, 4, 6, 8, 16, 32, 64]

    @Test("the polish cap is a cap on a loop that reaches its own fixed point, and both fitters read it")
    func thePolishCapIsACapOnALoopThatFixedPointsFirst() throws {
        struct Pass {
            let index: Int
            let normal: Vec3
            let d: Float
            let planeAtFoodMm: Float
            let ringMedianMm: Float
            let innerSupport: Float
            let extentMm: Float
            let tiltDeg: Float
            let signs: SectorSigns
        }
        struct Reading {
            let name: String
            let passes: Int
            let candidates: [Pass]
            let trace: [PolishTrace]
            let fallback: FallbackReading?
            let selectedIndex: Int
            let intendedIndex: Int
            var selected: Pass { candidates[selectedIndex] }
            var intended: Pass { candidates[intendedIndex] }
        }
        struct Capture {
            let name: String
            let slice: DepthSlice
            let g: SupportRegion.DepthGeometry
            let samples: SupportRegion.RingSamples
            let ray: Vec3
        }

        var corpus: [Capture] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            corpus.append(Capture(name: name, slice: slice, g: g,
                                  samples: SupportRegion.ringSamples(geometry: g),
                                  ray: try #require(Self.foodCentroidRay(slice))))
        }

        func pass(_ index: Int, _ c: SupportRegion.PlaneCandidate,
                  capture: Capture) -> Pass {
            Pass(index: index, normal: c.normal, d: c.d,
                 planeAtFoodMm: Self.planeDepthMm(normal: c.normal, d: c.d, ray: capture.ray),
                 ringMedianMm: SupportRegion.medianHeight(
                    indices: capture.samples.ring, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 innerSupport: Self.innerSupportFraction(
                    samples: capture.samples, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 extentMm: c.extentMm,
                 tiltDeg: Self.angleDeg(c.normal, capture.slice.gravity.normalised()),
                 signs: Self.sectorSigns(samples: capture.samples, geometry: capture.g,
                                         normal: c.normal, d: c.d))
        }

        func read(_ capture: Capture, passes: Int) throws -> Reading {
            var rng = SplitMix64(seed: Fnv1a64.hash(capture.slice.depth.depthBytesMm))
            var trace: [PolishTrace] = []
            let extracted = Self.extractCandidates(
                annulus: capture.samples.annulus, geometry: capture.g,
                gravity: capture.slice.gravity.normalised(), rng: &rng,
                polishPasses: passes, trace: &trace)
            let candidates = extracted.enumerated().map {
                pass($0.offset, $0.element, capture: capture)
            }
            let empty = "\(capture.name): no candidate survives extraction at"
                + " \(passes) polish passes"
            let selected = try #require(
                (0..<candidates.count).max { candidates[$0].innerSupport < candidates[$1].innerSupport },
                "\(empty)")
            let intended = try #require(
                (0..<candidates.count).min { abs(candidates[$0].ringMedianMm) < abs(candidates[$1].ringMedianMm) })
            return Reading(name: capture.name, passes: passes, candidates: candidates,
                           trace: trace,
                           fallback: Self.fallbackReading(capture.slice, polishPasses: passes,
                                                          ray: capture.ray),
                           selectedIndex: selected, intendedIndex: intended)
        }

        var byPasses: [Int: [Reading]] = [:]
        for passes in Self.polishPassSweep {
            byPasses[passes] = try corpus.map { try read($0, passes: passes) }
        }

        // The anchor, both legs. At the shipped cap the instrumented chain must BE the
        // shipped extraction, candidate for candidate, and the instrumented fallback must be
        // the shipped `fitOutcome` plane — or the sweep is measuring a different polish and
        // nothing below says anything about `consensusPolishMaxPasses`.
        for c in corpus {
            let shipped = try #require(Self.candidates(c.name))
            let reading = try #require(
                byPasses[LiDARPlaneFitter.consensusPolishMaxPasses]?.first { $0.name == c.name })
            let drift = "\(c.name): the instrumented polish chain no longer reproduces"
                + " SupportRegion.extractCandidates at consensusPolishMaxPasses"
                + " (\(shipped.count) shipped candidates, \(reading.candidates.count) reproduced)"
            #expect(shipped.count == reading.candidates.count, "\(drift)")
            for (a, b) in zip(shipped, reading.candidates) {
                #expect(a.d == b.d && a.normal == b.normal, "\(drift)")
            }
            let shippedFallback = try #require(Self.fallbackPlane(c.slice))
            let reproduced = try #require(reading.fallback)
            let fallbackDrift = "\(c.name): the instrumented polish chain no longer reproduces"
                + " LiDARPlaneFitter.fitOutcome at consensusPolishMaxPasses"
            #expect(reproduced.planeAtFoodMm
                    == Self.planeDepthMm(normal: shippedFallback.normal,
                                         d: shippedFallback.distanceMm, ray: c.ray),
                    "\(fallbackDrift)")
        }

        for passes in Self.polishPassSweep {
            print("consensusPolishMaxPasses=\(passes):")
            for r in byPasses[passes] ?? [] {
                let shippedRun = byPasses[LiDARPlaneFitter.consensusPolishMaxPasses]?
                    .first { $0.name == r.name }
                print("  \(r.name): \(r.candidates.count) candidates,"
                      + " selected pass \(r.selectedIndex + 1),"
                      + " PLANE AT FOOD \(fmt(r.selected.planeAtFoodMm)) mm"
                      + " (\(fmt(r.selected.planeAtFoodMm - (shippedRun?.selected.planeAtFoodMm ?? r.selected.planeAtFoodMm))) vs shipped),"
                      + " ring median \(fmt(r.selected.ringMedianMm)) mm,"
                      + " support \(fmt(r.selected.innerSupport)),"
                      + " crossed \(r.selected.signs.crossedFailing);"
                      + " intended pass \(r.intendedIndex + 1)"
                      + " (ring median \(fmt(r.intended.ringMedianMm)) mm,"
                      + " support \(fmt(r.intended.innerSupport)),"
                      + " crossed \(r.intended.signs.crossedFailing),"
                      + " plane \(fmt(r.intended.planeAtFoodMm)) mm)")
                for (t, p) in zip(r.trace, r.candidates) {
                    print("    pass \(t.passIndex + 1): polish \(t.iterations)/\(passes)"
                          + " stopped on \(t.stop.rawValue),"
                          + " refinement tilt \(fmt(t.refinementTiltDeg))°"
                          + "\(t.refinementOutsideCone ? " OUTSIDE THE CONE" : "")"
                          + " → final \(fmt(t.finalTiltDeg))°"
                          + "\(t.finalOutsideCone ? " OUTSIDE THE CONE" : ""),"
                          + " plane \(fmt(p.planeAtFoodMm)) mm,"
                          + " ring median \(fmt(p.ringMedianMm)) mm,"
                          + " support \(fmt(p.innerSupport)),"
                          + " extent \(fmt(p.extentMm)) mm")
                }
                if let f = r.fallback {
                    print("    FALLBACK: polish \(f.iterations)/\(passes)"
                          + " stopped on \(f.stop.rawValue),"
                          + " plane \(fmt(f.planeAtFoodMm)) mm"
                          + " (\(fmt(f.planeAtFoodMm - (shippedRun?.fallback?.planeAtFoodMm ?? f.planeAtFoodMm))) vs shipped),"
                          + " tilt \(fmt(f.tiltDeg))°,"
                          + " residual \(fmt(f.residualMm)) mm,"
                          + " inliers \(f.inlierCount)")
                }
            }
        }

        // MARK: does the cap ever bind?

        var truncatedAt: [Int] = []
        for passes in Self.polishPassSweep {
            let readings = byPasses[passes] ?? []
            let capped = readings.flatMap(\.trace).filter { $0.stop == .cap }
            let fallbackCapped = readings.compactMap(\.fallback).filter { $0.stop == .cap }
            if !capped.isEmpty || !fallbackCapped.isEmpty { truncatedAt.append(passes) }
            print("  at \(passes) passes: extraction stops"
                  + " \(readings.flatMap(\.trace).map { "\($0.stop.rawValue)@\($0.iterations)" }),"
                  + " fallback stops"
                  + " \(readings.compactMap(\.fallback).map { "\($0.stop.rawValue)@\($0.iterations)" })")
        }
        let deepest = (byPasses[Self.polishPassSweep.max() ?? 16] ?? [])
            .flatMap(\.trace).map(\.iterations).max() ?? 0
        let deepestFallback = (byPasses[Self.polishPassSweep.max() ?? 16] ?? [])
            .compactMap(\.fallback).map(\.iterations).max() ?? 0
        print("polish iterations the corpus actually needs: \(deepest) in extraction,"
              + " \(deepestFallback) in the fallback, against a cap of"
              + " \(LiDARPlaneFitter.consensusPolishMaxPasses);"
              + " the cap truncates at \(truncatedAt) passes")

        // MARK: what it does to the answer

        var spanByName: [String: (lo: Float, hi: Float)] = [:]
        var fallbackSpanByName: [String: (lo: Float, hi: Float)] = [:]
        for readings in byPasses.values {
            for r in readings {
                let existing = spanByName[r.name] ?? (r.selected.planeAtFoodMm, r.selected.planeAtFoodMm)
                spanByName[r.name] = (min(existing.lo, r.selected.planeAtFoodMm),
                                      max(existing.hi, r.selected.planeAtFoodMm))
                if let f = r.fallback {
                    let e = fallbackSpanByName[r.name] ?? (f.planeAtFoodMm, f.planeAtFoodMm)
                    fallbackSpanByName[r.name] = (min(e.lo, f.planeAtFoodMm),
                                                  max(e.hi, f.planeAtFoodMm))
                }
            }
        }
        let spans = spanByName.mapValues { $0.hi - $0.lo }
        let fallbackSpans = fallbackSpanByName.mapValues { $0.hi - $0.lo }
        print("plane movement at the food over the POLISH sweep:"
              + " \(spans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + "; fallback leg"
              + " \(fallbackSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm transfer tolerance")

        // MARK: the cone the loop is supposed to hold

        for passes in Self.polishPassSweep {
            let traces = (byPasses[passes] ?? []).flatMap(\.trace)
            print("  at \(passes) passes: refinements outside the cone"
                  + " \(traces.filter(\.refinementOutsideCone).count)/\(traces.count)"
                  + " (worst \(fmt(traces.map(\.refinementTiltDeg).max() ?? 0))°),"
                  + " CANDIDATES outside the cone"
                  + " \(traces.filter(\.finalOutsideCone).count)/\(traces.count)"
                  + " (worst \(fmt(traces.map(\.finalTiltDeg).max() ?? 0))°)")
        }

        // MARK: the bracket

        var crossedByPasses: [Int: (floor: Int, ceiling: Int)] = [:]
        for passes in Self.polishPassSweep {
            var floor = 0, ceiling = Int.max
            for r in byPasses[passes] ?? [] {
                floor = max(floor, r.intended.signs.crossedFailing)
                if r.selectedIndex != r.intendedIndex {
                    ceiling = min(ceiling, r.selected.signs.crossedFailing - 1)
                }
            }
            crossedByPasses[passes] = (floor, ceiling)
            print("  \(passes) passes: maxCrossedSectors corpus \(floor)…"
                  + "\(ceiling == Int.max ? "unbounded" : "\(ceiling)")"
                  + " \(floor <= ceiling ? "" : "EMPTY")")
        }

        // MARK: what the sweep says

        // THE FIRST FINDING, and it is the claim in the comment. "The loop usually exits
        // earlier because the inlier set reaches a fixed point" is false on this corpus, and
        // it is false on BOTH legs. At the shipped cap extraction is truncated on 4 of its 6
        // passes and the fallback on both captures, and the depth the corpus actually needs
        // to reach the stated fixed point is 17 in extraction and 11 in the fallback — five
        // and nearly four times the cap. So the plane the pipeline ships is a truncated
        // iterate of the polish, not the fixed point every argument for the guard is stated
        // about. This is the mirror of Decision 51's `maxIterationsPerPass`, which never
        // fires: that cap is idle, this one always binds.
        let shippedTraces = (byPasses[LiDARPlaneFitter.consensusPolishMaxPasses] ?? [])
        let shippedCapped = shippedTraces.flatMap(\.trace).filter { $0.stop == .cap }
        let shippedFallbackCapped = shippedTraces.compactMap(\.fallback).filter { $0.stop == .cap }
        let capIsIdle = "the polish loop reaches its fixed point inside"
            + " consensusPolishMaxPasses on this corpus (deepest \(deepest) in extraction,"
            + " \(deepestFallback) in the fallback) — the comment's \"the loop usually exits"
            + " earlier\" holds and this constant is a bound rather than the thing that stops it"
        #expect(!shippedCapped.isEmpty && !shippedFallbackCapped.isEmpty
                && deepest > LiDARPlaneFitter.consensusPolishMaxPasses
                && deepestFallback > LiDARPlaneFitter.consensusPolishMaxPasses, "\(capIsIdle)")

        // THE SECOND FINDING: it decides which planes COMPETE, and it can ADD one. Extraction
        // stops at the pass cap or at the residue floor, and a shallower polish leaves a
        // different plane, hence a different removal shell, hence a different residue —
        // `1785135663727` yields TWO candidates at 0 and 1 passes and THREE from 2 up, its
        // third pass appearing only once the polish has run deep enough to leave it something
        // to draw from. That puts this constant with `annulusOuterMm` (Decision 49) and
        // `maxCandidatePlanes` (Decision 48) rather than with the bracket-only ones, and makes
        // the persisted `planeCandidateCount` (Req 6.1) denominated in it as well.
        func candidateCounts(_ passes: Int) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: (byPasses[passes] ?? []).map {
                ($0.name, $0.candidates.count)
            })
        }
        let shallow = candidateCounts(0)
        let shippedCounts = candidateCounts(LiDARPlaneFitter.consensusPolishMaxPasses)
        print("candidate counts: 0 passes \(shallow.sorted { $0.key < $1.key }),"
              + " shipped \(shippedCounts.sorted { $0.key < $1.key })")
        let setIsFixed = "the polish depth no longer changes the candidate SET"
            + " (\(shallow.sorted { $0.key < $1.key }) at 0 passes against"
            + " \(shippedCounts.sorted { $0.key < $1.key }) shipped) — it is a bracket-only"
            + " constant after all and does not belong with the ones that decide which"
            + " planes compete"
        #expect(shallow != shippedCounts, "\(setIsFixed)")

        // THE THIRD FINDING, and it sharpens Decision 52's. That decision recorded the gravity
        // cone as un-enforced on the first refinement, and the corpus holding a candidate at
        // 20.512° as a result. Traced through the loop, the gate is worse than absent: on that
        // candidate it FIRES on the very first re-selection, and its rejection path is `break`,
        // which keeps the previous plane — the ungated refinement, itself outside the cone. So
        // the "conservative fallback" `estimation-runtime-consistency.md` documents (a
        // re-selection outside the cone keeps the previous pass's plane, so the polish can
        // never fail a fit that previously succeeded) is exactly what preserves the plane the
        // cone exists to exclude. It reads `gravity` at 0 applied iterations at EVERY depth
        // from 2 up, and the tilt it leaves standing moves with the cap — 26.573° at 2 passes,
        // Decision 52's 20.512° at the shipped 3, 18.609° from 16 — so that figure is a
        // reading at this constant too.
        let gateFirings = shippedTraces.flatMap(\.trace).filter { $0.stop == .gravity }
        print("polish passes stopped by the gravity gate at the shipped cap:"
              + " \(gateFirings.count), of which"
              + " \(gateFirings.filter(\.finalOutsideCone).count) keep a plane OUTSIDE the cone"
              + " (\(gateFirings.map { fmt($0.finalTiltDeg) })°)")
        let gateRemoves = "the polish loop's gravity gate no longer keeps an out-of-cone plane"
            + " on this corpus — Decision 52's unenforced cone is enforced after all and the"
            + " note at the call site can go"
        #expect(gateFirings.contains { $0.finalOutsideCone && $0.iterations == 0 },
                "\(gateRemoves)")

        // THE FOURTH FINDING: the two legs move by different amounts and only one of them
        // stays inside Req 5.1's tolerance. The promoted plane moves 0.490 and 0.106 mm over
        // the sweep; the FALLBACK plane moves 0.158 and 1.719 mm, past the 1 mm Decision 35
        // measures the transfer at. Req 4.3 makes the fallback identical to what
        // `LiDARPlaneFitter` produces for the same capture, and it does at every value here
        // because one constant moves both — but the plane both of them name moves, and it is
        // the plane Decision 36 prices `fallbackPenalty` against and the one that feeds
        // `lidarMmPerPx = |d| / f` on the legacy path. First owed constant whose fallback leg
        // moves further than its promoted one.
        let promoted = spans.values.max() ?? 0
        let fallbackWidest = fallbackSpans.values.max() ?? 0
        let legsAgree = "the fallback leg no longer moves further than the promoted one"
            + " (promoted \(fmt(promoted)) mm, fallback \(fmt(fallbackWidest)) mm) — this"
            + " constant can be read off the feature's own path alone"
        #expect(fallbackWidest > Self.gridTransferToleranceMm
                && promoted < Self.gridTransferToleranceMm, "\(legsAgree)")

        // THE BRACKET. The FLOOR is 1 and it is the corpus's: at 0 the loop does not exist, the
        // candidate set is short a plane on one capture, and `maxCrossedSectors` reads 2…3
        // rather than the 2…2 Decision 48 determined — so the polish is what makes that
        // determination tight, and turning it off costs the corpus its one determined constant.
        // From 1 up the reading is 2…2 at every depth, so like Decision 50's removal band this
        // constant does not otherwise denominate it. There is no CEILING: the readings are
        // monotone in the sense that matters (each depth is one more iteration of the same
        // map) and the corpus points ABOVE the shipped value rather than at it, because the
        // constant's own derivation — reach the fixed point — is met only at 17. What stops
        // that being a proposal is Req 7.6: the polish is the innermost loop in extraction and
        // raising it to 17 quintuples it, on the path that has already produced an OOM.
        let atZero = try #require(crossedByPasses[0])
        let aboveZero = Self.polishPassSweep.filter { $0 > 0 }
        let tightEverywhere = aboveZero.allSatisfy {
            crossedByPasses[$0]?.floor == 2 && crossedByPasses[$0]?.ceiling == 2
        }
        print("maxCrossedSectors: \(atZero.floor)…\(atZero.ceiling) with no polish,"
              + " 2…2 at every depth from 1 up: \(tightEverywhere)")
        let floorIsNotThePolish = "the corpus reads maxCrossedSectors identically with the"
            + " polish off (\(atZero.floor)…\(atZero.ceiling)) and on — the floor of 1 is not"
            + " the corpus's and this constant has no bracket from below"
        #expect(atZero.ceiling > 2 && tightEverywhere, "\(floorIsNotThePolish)")
    }

    // The polish loop was added for ONE stated reason: the RANSAC winner's inlier band is
    // anchored to a 3-point candidate plane, so the refined plane depends on which minimal
    // sample won, and re-selecting against the refined plane "converges to a fixed point that
    // no longer depends on which minimal sample won". Decision 46 measured that dependence at
    // the shipped settings — 2.095 mm at the food over eight seeds — and Decision 51 found it
    // removable, by tightening `ransacSuccessProbability` rather than by anything the polish
    // does. So the guard's own purpose has a number attached to it and has never been read
    // against the constant that bounds the guard. Three depths: none, shipped, and past where
    // the corpus's slowest pass reaches its fixed point.
    static let polishSeedDepths = [0, 3, 64]

    @Test("the polish is what the seed spread was added to remove, and depth alone does not remove it")
    func thePolishDoesNotRemoveTheSeedSpreadItWasAddedFor() throws {
        struct Roll {
            let planeAtFoodMm: Float
            let crossed: Int
            let supporting: Int
            let candidateCount: Int
        }

        var spreadByDepth: [Int: [String: Float]] = [:]
        for depth in Self.polishSeedDepths {
            var spreads: [String: Float] = [:]
            for name in Self.captures {
                let slice = try DepthSlice.load(name)
                let g = try #require(Self.geometry(name))
                let samples = SupportRegion.ringSamples(geometry: g)
                let ray = try #require(Self.foodCentroidRay(slice))
                let shippedSeed = Fnv1a64.hash(slice.depth.depthBytesMm)

                var rolls: [Roll] = []
                for i in 0..<Self.seedRolls {
                    let seed = i == 0
                        ? shippedSeed
                        : shippedSeed &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
                    var rng = SplitMix64(seed: seed)
                    var trace: [PolishTrace] = []
                    let candidates = Self.extractCandidates(
                        annulus: samples.annulus, geometry: g,
                        gravity: slice.gravity.normalised(), rng: &rng,
                        polishPasses: depth, trace: &trace)
                    guard let best = candidates.max(by: {
                        Self.innerSupportFraction(samples: samples, geometry: g,
                                                  normal: $0.normal, d: $0.d)
                        < Self.innerSupportFraction(samples: samples, geometry: g,
                                                    normal: $1.normal, d: $1.d)
                    }) else { continue }
                    let signs = Self.sectorSigns(samples: samples, geometry: g,
                                                 normal: best.normal, d: best.d)
                    rolls.append(Roll(
                        planeAtFoodMm: Self.planeDepthMm(normal: best.normal, d: best.d, ray: ray),
                        crossed: signs.crossedFailing, supporting: signs.supporting,
                        candidateCount: candidates.count))
                }
                #expect(rolls.count == Self.seedRolls,
                        "extraction failed on some seed at \(depth) polish passes")
                let planes = rolls.map(\.planeAtFoodMm)
                let spread = (planes.max() ?? 0) - (planes.min() ?? 0)
                spreads[name] = spread
                print("\(name) at \(depth) polish passes, \(Self.seedRolls) seeds:"
                      + " spread \(fmt(spread)) mm,"
                      + " planes \(planes.map { fmt($0) }.sorted()),"
                      + " crossed \(Set(rolls.map(\.crossed)).sorted()),"
                      + " supporting \(Set(rolls.map(\.supporting)).sorted()),"
                      + " candidates \(Set(rolls.map(\.candidateCount)).sorted())")
            }
            spreadByDepth[depth] = spreads
            print("  seed spread at \(depth) polish passes:"
                  + " \(spreads.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))")
        }

        let shipped = spreadByDepth[LiDARPlaneFitter.consensusPolishMaxPasses] ?? [:]
        let deep = spreadByDepth[Self.polishSeedDepths.max() ?? 64] ?? [:]
        let none = spreadByDepth[0] ?? [:]
        print("seed spread against polish depth:"
              + " none \(none.map { "\($0.key) \(fmt($0.value))" }.sorted()),"
              + " shipped \(shipped.map { "\($0.key) \(fmt($0.value))" }.sorted()),"
              + " deep \(deep.map { "\($0.key) \(fmt($0.value))" }.sorted())"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm")

        // The guard does its job on one capture and not on the other, and the one it fails on
        // is the one carrying the corpus's only intended-correct fit. On `1785901032716` the
        // spread collapses 0.096 → 0.001 mm; on `1785135663727` it reads 2.123, 2.095 and
        // 2.067 mm at none, shipped and convergence — a 2.6 % reduction for the shipped cap
        // and 2.9 % for running the loop to its own fixed point. So the constant's DEPTH is
        // not what removes the dependence the loop was added to remove: what does is
        // `ransacSuccessProbability`, which Decision 51 measured taking the same 2.095 mm to
        // 0.194 mm. The residual spread is a SELECTION difference the polish cannot reach —
        // the seeds disagree about which candidate wins, not about where one plane lies.
        let stubborn = Self.captures.filter { name in
            let n = none[name] ?? 0, d = deep[name] ?? 0
            return n > Self.gridTransferToleranceMm && d > 0.9 * n
        }
        print("captures whose seed spread survives the polish at any depth: \(stubborn)")
        let polishFixesIt = "the polish now removes the seed spread it was added for on every"
            + " capture (none \(none.map { "\($0.key) \(fmt($0.value))" }.sorted()), deep"
            + " \(deep.map { "\($0.key) \(fmt($0.value))" }.sorted())) — the guard's stated"
            + " purpose is met by its own depth and Decision 51's finding is not the only route"
        #expect(!stubborn.isEmpty
                && (shipped["1785135663727"] ?? 0) > 0.9 * (none["1785135663727"] ?? 0),
                "\(polishFixesIt)")
    }

    // MARK: - The gravity cone, the bar four gates read and two enforce

    // What the cone did on one extraction pass. THREE tilts, because the constant is read at
    // three points in a single pass and only the first of them turns anything away: the
    // hypothesis `ccRansac` admits, the UNGATED refinement of that hypothesis, and the plane
    // that finally reaches `admissibility`. Decision 52 measured the gap between the second
    // and the shipped bar; Decision 54 traced it through the polish and found the gate's
    // `break` preserving it. Neither varied the bar itself, which is what this does.
    struct ConeTrace {
        let passIndex: Int
        let hypothesisTiltDeg: Float
        let hypothesisRejected: Int    // draws the ONE enforced gate turned away
        let hypothesisDraws: Int
        let refinementTiltDeg: Float
        let finalTiltDeg: Float
        let polishIterations: Int
        let stop: PolishStop
        func outside(_ coneDeg: Float) -> Bool { finalTiltDeg > coneDeg }
    }

    // `SupportRegion.ccRansac` with the cone as an argument and its rejections counted.
    // Every other line is the shipped path's — the same unconditional three draws, the same
    // orientation onto gravity's half-space, the same inlier band, the same amortised
    // component labelling, the same adaptive stopping — so at `gravityAngleMaxRad` it
    // reproduces the shipped hypothesis exactly, which the anchor below checks candidate by
    // candidate.
    static func ccRansac(indices: [Int], geometry g: SupportRegion.DepthGeometry,
                         gravity: Vec3, rng: inout SplitMix64,
                         scratch: SupportRegion.ComponentScratch,
                         coneRad: Float, rejected: inout Int,
                         draws: inout Int) -> SupportRegion.RansacHypothesis? {
        let n = indices.count
        guard n >= LiDARPlaneFitter.minPoints else { return nil }
        var best: SupportRegion.RansacHypothesis?
        var bestComponent = 0
        var required = SupportRegion.maxIterationsPerPass
        var iteration = 0

        while iteration < required && iteration < SupportRegion.maxIterationsPerPass {
            iteration += 1
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = g.points[indices[i]], p2 = g.points[indices[j]], p3 = g.points[indices[k]]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            draws += 1
            if acos(SupportRegion.clampedCosine(nHat.dot(gravity))) > coneRad {
                rejected += 1
                continue
            }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in indices
            where abs(nHat.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                inliers.append(idx)
            }
            if inliers.count <= bestComponent { continue }

            let component = scratch.largestComponent(of: inliers)
            guard component.size > bestComponent else { continue }
            bestComponent = component.size
            best = SupportRegion.RansacHypothesis(normal: nHat, d: d, members: component.members)
            required = SupportRegion.requiredIterations(
                inlierRatio: Float(bestComponent) / Float(n))
        }
        return best
    }

    // The pass chain with the cone parameterised at BOTH of the places extraction reads it,
    // and with the ungated refinement between them left ungated — because that is the shipped
    // path and the question here is what the bar does to it, not what a repaired gate would.
    static func extractCandidates(
        annulus: [Int], geometry g: SupportRegion.DepthGeometry,
        gravity: Vec3, rng: inout SplitMix64, coneRad: Float,
        trace: inout [ConeTrace]
    ) -> [SupportRegion.PlaneCandidate] {
        var residue = annulus
        var candidates: [SupportRegion.PlaneCandidate] = []
        let scratch = SupportRegion.ComponentScratch(width: g.width, height: g.height)
        let residueFloor = SupportRegion.minResidueSamples(mmPerPx: g.mmPerPx)

        func tiltDeg(_ n: Vec3) -> Float {
            acos(SupportRegion.clampedCosine(n.dot(gravity))) * 180 / .pi
        }

        for passIndex in 0..<SupportRegion.maxCandidatePlanes {
            guard residue.count >= residueFloor else { break }
            var rejected = 0
            var draws = 0
            guard let hypothesis = Self.ccRansac(
                indices: residue, geometry: g, gravity: gravity, rng: &rng,
                scratch: scratch, coneRad: coneRad,
                rejected: &rejected, draws: &draws) else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1
            let refinementTilt = tiltDeg(normal)

            var applied = 0
            var stop = PolishStop.cap
            for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue
                where abs(normal.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers { stop = .fixedPoint; break }
                if next.count < LiDARPlaneFitter.minPoints { stop = .underpopulated; break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { stop = .degenerate; break }
                if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity))) > coneRad {
                    stop = .gravity
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
                applied += 1
            }
            trace.append(ConeTrace(
                passIndex: passIndex,
                hypothesisTiltDeg: tiltDeg(hypothesis.normal),
                hypothesisRejected: rejected, hypothesisDraws: draws,
                refinementTiltDeg: refinementTilt, finalTiltDeg: tiltDeg(normal),
                polishIterations: applied, stop: stop))

            let component = scratch.largestComponent(of: inliers)
            candidates.append(SupportRegion.PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count))

            let removalBandMm = SupportRegion.inlierRemovalMultiple * LiDARPlaneFitter.inlierBandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return candidates
    }

    // The OTHER leg's hypothesis gate. `LiDARPlaneFitter.ransac` reads the same constant on
    // a fixed 256-iteration budget over the colour-grid edge bands, with no connected
    // component and no adaptive stopping — so the cone is the only thing the two hypothesis
    // stages share, and a sweep that reports one of them is measuring half the constant.
    static func fallbackRansac(points: [Vec3], gravity: Vec3, rng: inout SplitMix64,
                               coneRad: Float,
                               rejected: inout Int, draws: inout Int)
        -> (normal: Vec3, d: Float, inliers: [Int]) {
        var bestScore = 0
        var bestInliers: [Int] = []
        var bestNormal = gravity
        var bestD: Float = 0
        let n = points.count

        for _ in 0..<LiDARPlaneFitter.maxIterations {
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = points[i], p2 = points[j], p3 = points[k]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            draws += 1
            if acos(SupportRegion.clampedCosine(nHat.dot(gravity))) > coneRad {
                rejected += 1
                continue
            }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in 0..<n where abs(nHat.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                inliers.append(idx)
            }
            if inliers.count > bestScore {
                bestScore = inliers.count
                bestInliers = inliers
                bestNormal = nHat
                bestD = d
            }
        }
        return (bestNormal, bestD, bestInliers)
    }

    struct ConeFallbackReading {
        let planeAtFoodMm: Float
        let hypothesisTiltDeg: Float
        let refinementTiltDeg: Float
        let tiltDeg: Float
        let residualMm: Float
        let inlierCount: Int
        let hypothesisRejected: Int
        let hypothesisDraws: Int
        let iterations: Int
        let stop: PolishStop
    }

    // `LiDARPlaneFitter.fitOutcome` with the cone parameterised at both of ITS gates. This is
    // the plane Req 4.3 pins byte-identical to the legacy fitter and Req 4.6 prices, so it is
    // reported alongside the promoted one at every value.
    static func fallbackReading(_ slice: DepthSlice, coneRad: Float,
                                ray: Vec3) -> ConeFallbackReading? {
        let inputs = LiDARPlaneFitter.Inputs(
            depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
            foodRegionMask: slice.colourFoodMask, gravityCamera: slice.gravity)
        var stats = SupportPlaneFitStats()
        let points = LiDARPlaneFitter.collectCandidatePoints(inputs, stats: &stats)
        guard points.count >= LiDARPlaneFitter.minPoints else { return nil }

        var rng = SplitMix64(seed: Fnv1a64.hash(inputs.depth.depthBytesMm))
        let gravity = inputs.gravityCamera.normalised()
        var rejected = 0
        var draws = 0
        let (bestNormal, _, bestInliers) = Self.fallbackRansac(
            points: points, gravity: gravity, rng: &rng, coneRad: coneRad,
            rejected: &rejected, draws: &draws)
        guard bestInliers.count >= LiDARPlaneFitter.minPoints else { return nil }
        guard let refined = try? LiDARPlaneFitter.refine(
            inliers: bestInliers.map { points[$0] }, seedNormal: bestNormal) else { return nil }

        func tiltDeg(_ n: Vec3) -> Float {
            acos(SupportRegion.clampedCosine(n.dot(gravity))) * 180 / .pi
        }
        var normal = refined.0
        var d = refined.1
        let refinementTilt = tiltDeg(normal)
        var polishedInliers = bestInliers
        var applied = 0
        var stop = PolishStop.cap
        for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(normal.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                reselected.append(idx)
            }
            if reselected == polishedInliers { stop = .fixedPoint; break }
            if reselected.count < LiDARPlaneFitter.minPoints { stop = .underpopulated; break }
            guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                inliers: reselected.map { points[$0] }, seedNormal: normal
            ) else { stop = .degenerate; break }
            if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity))) > coneRad {
                stop = .gravity
                break
            }
            polishedInliers = reselected
            normal = nextNormal
            d = nextD
            applied += 1
        }

        return ConeFallbackReading(
            planeAtFoodMm: Self.planeDepthMm(normal: normal, d: d, ray: ray),
            hypothesisTiltDeg: tiltDeg(bestNormal),
            refinementTiltDeg: refinementTilt,
            tiltDeg: tiltDeg(normal),
            residualMm: LiDARPlaneFitter.computeResidual(
                points: polishedInliers.map { points[$0] }, normal: normal, d: d),
            inlierCount: polishedInliers.count,
            hypothesisRejected: rejected, hypothesisDraws: draws,
            iterations: applied, stop: stop)
    }

    // Degrees. The ends are set by what the measurement has to be able to see. 1° is below
    // any plausible hand-held tilt, where the hypothesis gate should starve outright; 90° is
    // the gate OFF, because both fitters orient every hypothesis onto gravity's half-space
    // before measuring the angle and nothing can exceed a right angle after that. The shipped
    // 15° sits mid-sweep, and 20° and 25° bracket the 20.512° candidate Decision 52 found
    // surviving it.
    static let gravityConeSweep: [Float] = [1, 2, 3, 5, 8, 10, 12, 15, 18, 20, 25, 30, 45, 90]

    @Test("the gravity cone is read at four gates, and what it leaves standing is not monotone in the bar")
    func theGravityConeIsTheBarFourGatesReadAndTwoEnforce() throws {
        struct Pass {
            let index: Int
            let normal: Vec3
            let d: Float
            let planeAtFoodMm: Float
            let ringMedianMm: Float
            let innerSupport: Float
            let extentMm: Float
            let tiltDeg: Float
            let signs: SectorSigns
        }
        struct Reading {
            let name: String
            let coneDeg: Float
            let candidates: [Pass]
            let trace: [ConeTrace]
            let fallback: ConeFallbackReading?
            let selectedIndex: Int?
            let intendedIndex: Int?
            var selected: Pass? { selectedIndex.map { candidates[$0] } }
            var intended: Pass? { intendedIndex.map { candidates[$0] } }
        }
        struct Capture {
            let name: String
            let slice: DepthSlice
            let g: SupportRegion.DepthGeometry
            let samples: SupportRegion.RingSamples
            let ray: Vec3
        }

        var corpus: [Capture] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let g = try #require(Self.geometry(name))
            corpus.append(Capture(name: name, slice: slice, g: g,
                                  samples: SupportRegion.ringSamples(geometry: g),
                                  ray: try #require(Self.foodCentroidRay(slice))))
        }

        func pass(_ index: Int, _ c: SupportRegion.PlaneCandidate,
                  capture: Capture) -> Pass {
            Pass(index: index, normal: c.normal, d: c.d,
                 planeAtFoodMm: Self.planeDepthMm(normal: c.normal, d: c.d, ray: capture.ray),
                 ringMedianMm: SupportRegion.medianHeight(
                    indices: capture.samples.ring, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 innerSupport: Self.innerSupportFraction(
                    samples: capture.samples, geometry: capture.g,
                    normal: c.normal, d: c.d),
                 extentMm: c.extentMm,
                 tiltDeg: Self.angleDeg(c.normal, capture.slice.gravity.normalised()),
                 signs: Self.sectorSigns(samples: capture.samples, geometry: capture.g,
                                         normal: c.normal, d: c.d))
        }

        func read(_ capture: Capture, coneDeg: Float) -> Reading {
            let coneRad = coneDeg * .pi / 180
            var rng = SplitMix64(seed: Fnv1a64.hash(capture.slice.depth.depthBytesMm))
            var trace: [ConeTrace] = []
            let extracted = Self.extractCandidates(
                annulus: capture.samples.annulus, geometry: capture.g,
                gravity: capture.slice.gravity.normalised(), rng: &rng,
                coneRad: coneRad, trace: &trace)
            let candidates = extracted.enumerated().map {
                pass($0.offset, $0.element, capture: capture)
            }
            return Reading(
                name: capture.name, coneDeg: coneDeg, candidates: candidates, trace: trace,
                fallback: Self.fallbackReading(capture.slice, coneRad: coneRad, ray: capture.ray),
                selectedIndex: (0..<candidates.count).max {
                    candidates[$0].innerSupport < candidates[$1].innerSupport
                },
                intendedIndex: (0..<candidates.count).min {
                    abs(candidates[$0].ringMedianMm) < abs(candidates[$1].ringMedianMm)
                })
        }

        var byCone: [Float: [Reading]] = [:]
        for coneDeg in Self.gravityConeSweep {
            byCone[coneDeg] = corpus.map { read($0, coneDeg: coneDeg) }
        }

        // The anchor, both legs. At the shipped cone the instrumented chain must BE the
        // shipped extraction, candidate for candidate, and the instrumented fallback must be
        // the shipped `fitOutcome` plane — or the sweep is measuring a different cone and
        // nothing below says anything about `gravityAngleMaxRad`.
        // The sweep's own member, not `gravityAngleMaxRad × 180/π` recomputed — the round trip
        // through radians does not land on a Float dictionary key.
        let shippedDeg = try #require(Self.gravityConeSweep.first {
            abs($0 - LiDARPlaneFitter.gravityAngleMaxRad * 180 / .pi) < 1e-3
        }, "the cone sweep no longer contains the shipped gravityAngleMaxRad")
        for c in corpus {
            let shipped = try #require(Self.candidates(c.name))
            let reading = try #require(byCone[shippedDeg]?.first { $0.name == c.name })
            let drift = "\(c.name): the instrumented cone chain no longer reproduces"
                + " SupportRegion.extractCandidates at gravityAngleMaxRad"
                + " (\(shipped.count) shipped candidates, \(reading.candidates.count) reproduced)"
            #expect(shipped.count == reading.candidates.count, "\(drift)")
            for (a, b) in zip(shipped, reading.candidates) {
                #expect(a.d == b.d && a.normal == b.normal, "\(drift)")
            }
            let shippedFallback = try #require(Self.fallbackPlane(c.slice))
            let reproduced = try #require(reading.fallback)
            let fallbackDrift = "\(c.name): the instrumented cone chain no longer reproduces"
                + " LiDARPlaneFitter.fitOutcome at gravityAngleMaxRad"
            #expect(reproduced.planeAtFoodMm
                    == Self.planeDepthMm(normal: shippedFallback.normal,
                                         d: shippedFallback.distanceMm, ray: c.ray),
                    "\(fallbackDrift)")
        }

        for coneDeg in Self.gravityConeSweep {
            print("gravityAngleMaxRad=\(fmt(coneDeg))°:")
            for r in byCone[coneDeg] ?? [] {
                let shippedRun = byCone[shippedDeg]?.first { $0.name == r.name }
                if let s = r.selected, let i = r.intended {
                    print("  \(r.name): \(r.candidates.count) candidates,"
                          + " selected pass \((r.selectedIndex ?? 0) + 1),"
                          + " PLANE AT FOOD \(fmt(s.planeAtFoodMm)) mm"
                          + " (\(fmt(s.planeAtFoodMm - (shippedRun?.selected?.planeAtFoodMm ?? s.planeAtFoodMm))) vs shipped),"
                          + " tilt \(fmt(s.tiltDeg))°,"
                          + " ring median \(fmt(s.ringMedianMm)) mm,"
                          + " support \(fmt(s.innerSupport)),"
                          + " crossed \(s.signs.crossedFailing);"
                          + " intended pass \((r.intendedIndex ?? 0) + 1)"
                          + " (tilt \(fmt(i.tiltDeg))°,"
                          + " ring median \(fmt(i.ringMedianMm)) mm,"
                          + " support \(fmt(i.innerSupport)),"
                          + " crossed \(i.signs.crossedFailing),"
                          + " plane \(fmt(i.planeAtFoodMm)) mm)")
                } else {
                    print("  \(r.name): NO CANDIDATE — extraction starved at \(fmt(coneDeg))°")
                }
                for (t, p) in zip(r.trace, r.candidates) {
                    print("    pass \(t.passIndex + 1):"
                          + " hypothesis \(fmt(t.hypothesisTiltDeg))°"
                          + " (\(t.hypothesisRejected)/\(t.hypothesisDraws) draws rejected by the cone),"
                          + " ungated refinement \(fmt(t.refinementTiltDeg))°"
                          + "\(t.refinementTiltDeg > coneDeg ? " OUTSIDE" : "")"
                          + " → final \(fmt(t.finalTiltDeg))°"
                          + "\(t.outside(coneDeg) ? " OUTSIDE" : ""),"
                          + " polish \(t.polishIterations) stopped on \(t.stop.rawValue),"
                          + " plane \(fmt(p.planeAtFoodMm)) mm,"
                          + " ring median \(fmt(p.ringMedianMm)) mm,"
                          + " support \(fmt(p.innerSupport)),"
                          + " extent \(fmt(p.extentMm)) mm")
                }
                if let f = r.fallback {
                    print("    FALLBACK: hypothesis \(fmt(f.hypothesisTiltDeg))°"
                          + " (\(f.hypothesisRejected)/\(f.hypothesisDraws) draws rejected),"
                          + " ungated refinement \(fmt(f.refinementTiltDeg))°"
                          + " → final \(fmt(f.tiltDeg))°"
                          + "\(f.tiltDeg > coneDeg ? " OUTSIDE" : ""),"
                          + " polish \(f.iterations) stopped on \(f.stop.rawValue),"
                          + " plane \(fmt(f.planeAtFoodMm)) mm"
                          + " (\(fmt(f.planeAtFoodMm - (shippedRun?.fallback?.planeAtFoodMm ?? f.planeAtFoodMm))) vs shipped),"
                          + " residual \(fmt(f.residualMm)) mm, inliers \(f.inlierCount)")
                }
            }
        }

        // MARK: what the bar moves

        var spanByName: [String: (lo: Float, hi: Float)] = [:]
        var fallbackSpanByName: [String: (lo: Float, hi: Float)] = [:]
        for readings in byCone.values {
            for r in readings {
                if let s = r.selected {
                    let e = spanByName[r.name] ?? (s.planeAtFoodMm, s.planeAtFoodMm)
                    spanByName[r.name] = (min(e.lo, s.planeAtFoodMm), max(e.hi, s.planeAtFoodMm))
                }
                if let f = r.fallback {
                    let e = fallbackSpanByName[r.name] ?? (f.planeAtFoodMm, f.planeAtFoodMm)
                    fallbackSpanByName[r.name] = (min(e.lo, f.planeAtFoodMm),
                                                  max(e.hi, f.planeAtFoodMm))
                }
            }
        }
        let spans = spanByName.mapValues { $0.hi - $0.lo }
        let fallbackSpans = fallbackSpanByName.mapValues { $0.hi - $0.lo }
        print("plane movement at the food over the CONE sweep:"
              + " \(spans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + "; fallback leg"
              + " \(fallbackSpans.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", "))"
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm transfer tolerance")

        // MARK: what it leaves standing

        for coneDeg in Self.gravityConeSweep {
            let traces = (byCone[coneDeg] ?? []).flatMap(\.trace)
            let fallbacks = (byCone[coneDeg] ?? []).compactMap(\.fallback)
            print("  at \(fmt(coneDeg))°: candidates outside the cone"
                  + " \(traces.filter { $0.outside(coneDeg) }.count)/\(traces.count)"
                  + " (worst \(fmt(traces.map(\.finalTiltDeg).max() ?? 0))°),"
                  + " ungated refinements outside"
                  + " \(traces.filter { $0.refinementTiltDeg > coneDeg }.count)/\(traces.count),"
                  + " hypothesis rejections"
                  + " \(traces.map(\.hypothesisRejected).reduce(0, +))/\(traces.map(\.hypothesisDraws).reduce(0, +))"
                  + " extraction and"
                  + " \(fallbacks.map(\.hypothesisRejected).reduce(0, +))/\(fallbacks.map(\.hypothesisDraws).reduce(0, +))"
                  + " fallback")
        }

        // MARK: the bracket

        var crossedByCone: [Float: (floor: Int, ceiling: Int)] = [:]
        for coneDeg in Self.gravityConeSweep {
            var floor = 0, ceiling = Int.max
            var complete = true
            for r in byCone[coneDeg] ?? [] {
                guard let intended = r.intended, let selected = r.selected else {
                    complete = false
                    continue
                }
                floor = max(floor, intended.signs.crossedFailing)
                if r.selectedIndex != r.intendedIndex {
                    ceiling = min(ceiling, selected.signs.crossedFailing - 1)
                }
            }
            crossedByCone[coneDeg] = (floor, ceiling)
            print("  \(fmt(coneDeg))°: maxCrossedSectors corpus \(floor)…"
                  + "\(ceiling == Int.max ? "unbounded" : "\(ceiling)")"
                  + "\(complete ? "" : " (a capture starved)")"
                  + " \(floor <= ceiling ? "" : "EMPTY")")
        }

        // MARK: what the sweep says

        func outsideTheCone(_ coneDeg: Float) -> (outside: Int, total: Int) {
            let traces = (byCone[coneDeg] ?? []).flatMap(\.trace)
            return (traces.filter { $0.outside(coneDeg) }.count, traces.count)
        }

        // THE FIRST FINDING, and it is what the constant is FOR. The cone is read at four
        // gates — the hypothesis test and the polish gate, on each of the two legs — and only
        // the hypothesis tests turn anything away. The polish gates' rejection path is
        // `break`, which KEEPS the plane that failed the check's predecessor, and the
        // refinement between the two stages is not gated at all (Decisions 52, 54). Vary the
        // bar and the consequence is not that the violation shrinks: at 1° the cone admits
        // hypotheses within 1° and EVERY candidate extraction produces is outside 1° — 4 of 4,
        // each one `gravity` at 0 applied iterations. At 2° it is 5 of 6, the worst at 18.955°,
        // NINE TIMES its own bar, against 20.512° at 1.37× the shipped 15°. The bar is not a
        // bound on the candidate set at any value in the sweep that admits one.
        let atOne = outsideTheCone(1)
        print("candidates outside their own cone: 1° \(atOne.outside)/\(atOne.total),"
              + " 2° \(outsideTheCone(2).outside)/\(outsideTheCone(2).total),"
              + " shipped \(outsideTheCone(shippedDeg).outside)/\(outsideTheCone(shippedDeg).total)")
        let coneBoundsTheSet = "the cone now bounds the candidate set at its tightest value"
            + " (\(atOne.outside)/\(atOne.total) outside a 1° cone) — the polish gate's `break`"
            + " no longer preserves the plane it rejected and Decisions 52 and 54's finding has"
            + " been repaired somewhere upstream"
        #expect(atOne.total > 0 && atOne.outside == atOne.total, "\(coneBoundsTheSet)")

        // And it is not monotone in the bar. 8° leaves NOTHING outside itself while the
        // shipped 15° leaves one candidate at 20.512°, so tightening the guard by seven
        // degrees moves the worst plane in the set FURTHER out. A guard whose violation does
        // not fall as its bar falls is not measuring what it names.
        let atEight = outsideTheCone(8)
        let atShipped = outsideTheCone(shippedDeg)
        let monotone = "the cone's violations are monotone in the bar after all"
            + " (8° \(atEight.outside)/\(atEight.total), shipped"
            + " \(atShipped.outside)/\(atShipped.total)) — tightening it now tightens the set"
        #expect(atEight.outside == 0 && atShipped.outside > 0, "\(monotone)")

        // THE SECOND FINDING: it moves the answer, and every millimetre of that movement is
        // BELOW the floor. 3.758 mm and 14.584 mm at the food over the sweep, both past Req
        // 5.1's 1 mm — but from 10° to 90° the selected plane is unchanged to 0.000 mm on both
        // captures, gate fully off included. So unlike `inlierBandMm` (Decision 52) or
        // `ransacSuccessProbability` (Decision 51), which wander across their whole range, this
        // constant is a FLOOR rather than a knob: it either admits the hypothesis that produces
        // the correct fit or it does not, and above that there is nothing to tune.
        let aboveFloor = Self.gravityConeSweep.filter { $0 >= 10 }
        var stationary = true
        for c in corpus {
            let reference = byCone[shippedDeg]?.first { $0.name == c.name }?.selected?.planeAtFoodMm
            for coneDeg in aboveFloor {
                let here = byCone[coneDeg]?.first { $0.name == c.name }?.selected?.planeAtFoodMm
                if here != reference { stationary = false }
            }
        }
        let eightMoves = corpus.compactMap { c -> Float? in
            guard let a = byCone[8]?.first(where: { $0.name == c.name })?.selected?.planeAtFoodMm,
                  let b = byCone[shippedDeg]?.first(where: { $0.name == c.name })?.selected?.planeAtFoodMm
            else { return nil }
            return abs(a - b)
        }.max() ?? 0
        print("selected plane stationary from 10° to 90°: \(stationary);"
              + " 8° moves it \(fmt(eightMoves)) mm")
        let floorMoved = "the corpus no longer floors the cone at 10° — the selected plane"
            + " \(stationary ? "still" : "no longer") holds to 0.000 mm from 10° up and 8°"
            + " moves it \(fmt(eightMoves)) mm against Req 5.1's"
            + " \(fmt(Self.gridTransferToleranceMm)) mm"
        #expect(stationary && eightMoves > Self.gridTransferToleranceMm, "\(floorMoved)")

        // THE THIRD FINDING, and it is the exact reverse of Decision 54's. That constant moved
        // the FALLBACK plane further than the promoted one; this one barely touches the
        // fallback — 0.226 mm and 0.074 mm over the whole sweep, inside Req 5.1 even at a 1°
        // cone — while moving the promoted plane 3.758 mm and 14.584 mm. The reason is in the
        // tilts, and it is the floor's derivation: the fallback fits the TABLE over the
        // colour-grid edge bands and lands at 1.742° and 0.579°, so a 15° cone has thirteen
        // degrees of headroom there and nothing to do. The promoted fit on `1785135663727` is
        // the PLATE TOP, at 8.309°, from a hypothesis at 8.900° — 6.3° off the table candidate
        // in its own capture. One constant gates two surfaces that differ by six degrees in the
        // same frame, and only the promoted one is anywhere near it.
        let promoted = spans.values.max() ?? 0
        let fallbackWidest = fallbackSpans.values.max() ?? 0
        let hypothesisTilts = (byCone[shippedDeg] ?? []).compactMap { r -> Float? in
            guard let i = r.intendedIndex, i < r.trace.count else { return nil }
            return r.trace[i].hypothesisTiltDeg
        }
        let worstHypothesis = hypothesisTilts.max() ?? 0
        print("margin over the hypothesis that produces the intended fit:"
              + " \(fmt(shippedDeg - worstHypothesis))° at the shipped \(fmt(shippedDeg))°"
              + " (worst intended hypothesis \(fmt(worstHypothesis))°);"
              + " promoted leg moves \(fmt(promoted)) mm, fallback leg \(fmt(fallbackWidest)) mm")
        let legsAgree = "the fallback leg now moves with the cone as well"
            + " (promoted \(fmt(promoted)) mm, fallback \(fmt(fallbackWidest)) mm) — the"
            + " asymmetry Decision 54 found running the other way has gone"
        #expect(promoted > Self.gridTransferToleranceMm
                && fallbackWidest < Self.gridTransferToleranceMm, "\(legsAgree)")
        let marginMoved = "the intended fit's own hypothesis no longer sits between 8° and the"
            + " shipped cone (\(fmt(worstHypothesis))°) — the floor of 10° is not this"
            + " measurement's and the bracket needs re-reading"
        #expect(worstHypothesis > 8 && worstHypothesis < shippedDeg, "\(marginMoved)")

        // THE BRACKET: 10…unbounded, with the shipped 15° strictly inside it — the second owed
        // constant in this feature not sitting on an edge, after Decision 50's removal band.
        // The FLOOR is the corpus's twice over: below 8° the joint `maxCrossedSectors` interval
        // is EMPTY, and at 8° the plane moves 1.802 mm. There is NO CEILING at all — at 90° the
        // gate cannot reject anything (both fitters orient onto gravity's half-space first) and
        // the corpus reads 2…2 and the same selected plane anyway. What a cone above 45° does
        // buy is one absurd candidate: `1785135663727`'s third pass finds a 79.809° surface
        // 1305.187 mm away with support 0.000, which `extent` rejects regardless. So on this
        // corpus the guard could be removed entirely without changing a single answer, and the
        // value cannot be set from it.
        let tightEverywhere = aboveFloor.allSatisfy {
            crossedByCone[$0]?.floor == 2 && crossedByCone[$0]?.ceiling == 2
        }
        let belowIsEmpty = Self.gravityConeSweep.filter { $0 < 8 }.allSatisfy {
            guard let r = crossedByCone[$0] else { return false }
            return r.floor > r.ceiling
        }
        print("maxCrossedSectors: EMPTY below 8° \(belowIsEmpty), 2…2 from 10° up"
              + " \(tightEverywhere), gate fully off \(crossedByCone[90].map { "\($0.floor)…\($0.ceiling)" } ?? "—")")
        let noCeiling = "the corpus now bounds the cone from above — turning the gate off at"
            + " 90° changes a reading it did not before, and this constant has a two-sided"
            + " bracket for the first time"
        #expect(tightEverywhere && belowIsEmpty
                && crossedByCone[90]?.floor == 2 && crossedByCone[90]?.ceiling == 2,
                "\(noCeiling)")
    }

    // MARK: - The envelope percentile, and what the envelope bar is denominated in

    // `SupportRegion.foodEnvelopeMm` with the percentile as an argument. Everything else is
    // the shipped path's — the food indices `prepare` admitted at τ_conf, the signed height
    // against the candidate plane, `SupportRegion.percentile`'s own nearest-rank rule — so
    // at `foodEnvelopePercentile` it reproduces the shipped reading exactly.
    static func foodEnvelopeMm(geometry g: SupportRegion.DepthGeometry,
                               normal: Vec3, d: Float, percentile p: Float) -> Float {
        SupportRegion.percentile(g.foodIndices.map { normal.dot(g.points[$0]) - d }, p)
    }

    // The whole domain, [0, 1], because a percentile has one, and dense at BOTH ends
    // because that is where the two constraint sets close on it. 0.5 is in the sweep for a
    // reason beyond spacing: `SupportRegion.percentile` special-cases it, averaging the two
    // middle samples where every other value takes a nearest-rank index, so the sweep
    // crosses a BRANCH there and not only a value.
    static let envelopePercentileSweep: [Float] =
        [0, 0.02, 0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.8, 0.85, 0.9, 0.92, 0.95, 0.99, 1]

    @Test("the envelope percentile is the unit the envelope bar is denominated in")
    func theEnvelopePercentileIsTheUnitTheEnvelopeBarIsDenominatedIn() throws {
        struct Pass {
            let index: Int
            let ringMedianMm: Float
            let innerSupport: Float
            let envelopeByP: [Float: Float]
            // Whether the ENVELOPE guard is the one that has to reject this plane, which is
            // Decision 34's rule for the suite — "a scene bounds a constant only where a
            // committed test would change verdict" — read on the corpus. A candidate
            // `supportFraction` already rejects floors nothing here, and THAT depends on
            // `ringSupportMin`, which is itself `[owed]`.
            func floorsTheEnvelopeBar(supportBar: Float) -> Bool { innerSupport >= supportBar }
        }
        struct Capture {
            let name: String
            let foodSamples: Int
            let passes: [Pass]
            var intended: Pass? { passes.min { abs($0.ringMedianMm) < abs($1.ringMedianMm) } }
        }

        var corpus: [Capture] = []
        for name in Self.captures {
            let (g, samples) = try #require(Self.prepared(name))
            let candidates = try #require(Self.candidates(name))
            let passes = candidates.enumerated().map { index, c -> Pass in
                var byP: [Float: Float] = [:]
                for p in Self.envelopePercentileSweep {
                    byP[p] = Self.foodEnvelopeMm(geometry: g, normal: c.normal, d: c.d,
                                                 percentile: p)
                }
                return Pass(index: index,
                            ringMedianMm: SupportRegion.medianHeight(
                                indices: samples.ring, geometry: g, normal: c.normal, d: c.d),
                            innerSupport: Self.innerSupportFraction(
                                samples: samples, geometry: g, normal: c.normal, d: c.d),
                            envelopeByP: byP)
            }
            corpus.append(Capture(name: name, foodSamples: g.foodSampleCount, passes: passes))
        }

        // The suite's own reading of the same guard, re-taken at every percentile. The
        // scenes carry their geometry and their plane, so only the percentile moves.
        struct Scene {
            let label: String
            let requiresPass: Bool
            let requiresFire: Bool
            let foodSamples: Int
            let envelopeByP: [Float: Float]
        }
        let scenes = Self.sceneReadings().map { r -> Scene in
            var byP: [Float: Float] = [:]
            for p in Self.envelopePercentileSweep {
                byP[p] = Self.foodEnvelopeMm(geometry: r.geometry, normal: r.normal,
                                             d: r.planeD, percentile: p)
            }
            return Scene(label: r.label,
                         requiresPass: r.requiresPass.contains(.foodEnvelope),
                         requiresFire: r.requiresFire.contains(.foodEnvelope),
                         foodSamples: r.geometry.foodSampleCount,
                         envelopeByP: byP)
        }
        #expect(scenes.count == 8, "a scene stopped producing ring statistics")

        // THE ANCHOR. At the shipped percentile the parameterised reading must BE
        // `SupportRegion.foodEnvelopeMm`, on every corpus candidate and every scene, or the
        // sweep is measuring a different quantity.
        let shippedP = try #require(Self.envelopePercentileSweep.first {
            $0 == SupportRegion.foodEnvelopePercentile
        }, "the percentile sweep no longer contains the shipped foodEnvelopePercentile")
        for name in Self.captures {
            let measured = try #require(Self.measurements(name))
            let here = try #require(corpus.first { $0.name == name })
            #expect(measured.count == here.passes.count)
            let drift = "\(name): the parameterised envelope no longer reproduces"
                + " SupportRegion.foodEnvelopeMm at foodEnvelopePercentile"
            for (a, b) in zip(measured, here.passes) {
                #expect(a.envelopeMm == b.envelopeByP[shippedP], "\(drift)")
            }
        }
        for (r, s) in zip(Self.sceneReadings(), scenes) {
            let sceneDrift = "\(s.label): the parameterised envelope no longer reproduces"
                + " the scene's own reading at foodEnvelopePercentile"
            #expect(r.envelopeMm == s.envelopeByP[shippedP], "\(sceneDrift)")
        }

        print("food samples the percentile is taken over:"
              + " \(corpus.map { "\($0.name) \($0.foodSamples)" }.joined(separator: ", "))"
              + "; scenes \(scenes.map { "\($0.label) \($0.foodSamples)" }.joined(separator: ", "))")

        // MARK: the two brackets, re-denominated

        struct Bracket {
            let corpusFloor: Float
            let corpusCeiling: Float
            let suiteFloor: Float
            let suiteCeiling: Float
            var jointFloor: Float { max(corpusFloor, suiteFloor) }
            var jointCeiling: Float { min(corpusCeiling, suiteCeiling) }
            var jointWidth: Float { jointCeiling - jointFloor }
            var empty: Bool { jointFloor >= jointCeiling }
            var hasCorpusFloor: Bool { corpusFloor > -Float.greatestFiniteMagnitude }
        }

        // The above-surface candidates' inner-band support, which is what decides whether
        // each of them reaches the envelope guard at all. It does NOT move with the
        // percentile, so these are fixed regime boundaries rather than a second sweep — and
        // every one of them sits inside `ringSupportMin`'s own bracket of (0, 0.362]
        // (Decision 52), so all three regimes are settings the session may still choose.
        let aboveSurfaceSupports = corpus.flatMap { c -> [Float] in
            guard let intended = c.intended else { return [] }
            return c.passes.filter { $0.index != intended.index && $0.ringMedianMm < 0 }
                .map(\.innerSupport)
        }.sorted()
        print("above-surface candidates' inner support:"
              + " \(aboveSurfaceSupports.map { fmt($0) }.joined(separator: ", "))"
              + " — against ringSupportMin's corpus ceiling of 0.362 (Decision 52)")
        // One bar per regime: below every above-surface support, between the two, above both.
        let supportBars: [Float] = [0.15, 0.25, 0.35]

        func bracket(at p: Float, supportBar: Float) -> Bracket {
            // Decision 48's rule, re-read at this percentile. The CEILING is the intended
            // candidate's own envelope — above it the guard rejects the fit this feature
            // exists to produce. The FLOOR is the highest above-surface candidate's, the
            // plane the guard is written to reject, counting only the ones that reach it.
            var corpusCeiling = Float.greatestFiniteMagnitude
            var corpusFloor = -Float.greatestFiniteMagnitude
            for c in corpus {
                guard let intended = c.intended, let ceiling = intended.envelopeByP[p] else { continue }
                corpusCeiling = min(corpusCeiling, ceiling)
                let above = c.passes.filter {
                    $0.index != intended.index && $0.ringMedianMm < 0
                        && $0.floorsTheEnvelopeBar(supportBar: supportBar)
                }
                if let floor = above.compactMap({ $0.envelopeByP[p] }).min() {
                    corpusFloor = max(corpusFloor, floor)
                }
            }
            let suiteCeiling = scenes.filter(\.requiresPass)
                .compactMap { $0.envelopeByP[p] }.min() ?? Float.greatestFiniteMagnitude
            let suiteFloor = scenes.filter(\.requiresFire)
                .compactMap { $0.envelopeByP[p] }.max() ?? -Float.greatestFiniteMagnitude
            return Bracket(corpusFloor: corpusFloor, corpusCeiling: corpusCeiling,
                           suiteFloor: suiteFloor, suiteCeiling: suiteCeiling)
        }

        var brackets: [Float: [Float: Bracket]] = [:]
        for p in Self.envelopePercentileSweep {
            var row: [Float: Bracket] = [:]
            for bar in supportBars { row[bar] = bracket(at: p, supportBar: bar) }
            brackets[p] = row
        }
        // Decision 48's own reading is the middle regime: `ringSupportMin` above the first
        // above-surface candidate's support and below the second's.
        let decision48Bar: Float = 0.25

        for p in Self.envelopePercentileSweep {
            let b = try #require(brackets[p]?[decision48Bar])
            print("p=\(fmt(p)):")
            for c in corpus {
                let intendedIndex = c.intended?.index
                print("  \(c.name): "
                      + c.passes.map {
                          "pass \($0.index + 1)"
                          + ($0.index == intendedIndex ? " INTENDED" : "")
                          + " \(fmt($0.envelopeByP[p] ?? 0)) mm"
                          + " (ring median \(fmt($0.ringMedianMm)) mm,"
                          + " support \(fmt($0.innerSupport)))"
                      }.joined(separator: ", "))
            }
            print("  scenes: " + scenes.map {
                "\($0.label) \(fmt($0.envelopeByP[p] ?? 0)) mm"
                + ($0.requiresPass ? " [pass]" : "") + ($0.requiresFire ? " [fire]" : "")
            }.joined(separator: ", "))
            print("  foodEnvelopeMinMm at ringSupportMin \(fmt(decision48Bar)):"
                  + " corpus \(b.hasCorpusFloor ? fmt(b.corpusFloor) : "no floor")"
                  + "…\(fmt(b.corpusCeiling)) mm,"
                  + " suite \(fmt(b.suiteFloor))…\(fmt(b.suiteCeiling)) mm,"
                  + " JOINT \(fmt(b.jointFloor))…\(fmt(b.jointCeiling)) mm"
                  + " = \(fmt(b.jointWidth)) mm\(b.empty ? " EMPTY" : "")")
            for bar in supportBars {
                let r = try #require(brackets[p]?[bar])
                print("    ringSupportMin \(fmt(bar)):"
                      + " corpus floor \(r.hasCorpusFloor ? fmt(r.corpusFloor) : "none"),"
                      + " joint \(fmt(r.jointWidth)) mm\(r.empty ? " EMPTY" : "")")
            }
        }

        // MARK: what the percentile moves

        // It cannot move the plane by moving the candidate SET — extraction never reads it —
        // so the only route is `admissibility`, and at the shipped `foodEnvelopeMinMm = 0`
        // that needs an envelope to cross zero. Report which candidates and scenes do.
        let crossers = corpus.flatMap { c in
            c.passes.compactMap { p -> String? in
                let values = Self.envelopePercentileSweep.compactMap { p.envelopeByP[$0] }
                guard let lo = values.min(), let hi = values.max(), lo < 0, hi >= 0 else { return nil }
                return "\(c.name) pass \(p.index + 1) (\(fmt(lo))…\(fmt(hi)) mm)"
            }
        }
        print("corpus candidates whose envelope crosses the shipped foodEnvelopeMinMm of"
              + " \(fmt(SupportRegion.foodEnvelopeMinMm)) mm over the sweep:"
              + " \(crossers.isEmpty ? ["none"] : crossers)")

        let sceneCrossers = scenes.compactMap { s -> String? in
            let values = Self.envelopePercentileSweep.compactMap { s.envelopeByP[$0] }
            guard let lo = values.min(), let hi = values.max(), lo < 0, hi >= 0 else { return nil }
            return "\(s.label) (\(fmt(lo))…\(fmt(hi)) mm)"
        }
        print("committed scenes whose envelope crosses it: "
              + "\(sceneCrossers.isEmpty ? ["none"] : sceneCrossers)")

        // The suite's reading of THIS constant at the SHIPPED bar, which is the one bound
        // here that involves no owed value at all: a scene whose committed assertion
        // requires the envelope guard to pass and whose envelope goes negative turns the
        // suite red at `foodEnvelopeMinMm = 0`, whatever the session later sets.
        func suiteRedAt(_ p: Float) -> [String] {
            scenes.compactMap { s -> String? in
                guard let e = s.envelopeByP[p] else { return nil }
                let fires = e < SupportRegion.foodEnvelopeMinMm
                if s.requiresPass && fires { return "\(s.label) fires (\(fmt(e)) mm)" }
                if s.requiresFire && !fires { return "\(s.label) passes (\(fmt(e)) mm)" }
                return nil
            }
        }
        let suiteFloorP = Self.envelopePercentileSweep.filter { suiteRedAt($0).isEmpty }.min()
        print("committed suite at the shipped foodEnvelopeMinMm of"
              + " \(fmt(SupportRegion.foodEnvelopeMinMm)) mm:"
              + Self.envelopePercentileSweep.map {
                  let red = suiteRedAt($0)
                  return " \(fmt($0)) \(red.isEmpty ? "green" : "RED — \(red.joined(separator: "; "))")"
              }.joined(separator: ","))
        print("suite-only floor on the percentile: \(fmt(suiteFloorP ?? 0))")

        // MARK: the bracket on the percentile itself

        // Monotone BY CONSTRUCTION — a percentile of a fixed multiset cannot fall as the
        // percentile rises — which is what makes this bracket interpolable where Decision
        // 46's radius and Decisions 51 and 52's wandering readings are not. Asserted rather
        // than assumed, because `SupportRegion.percentile`'s 0.5 branch is a different
        // function from the nearest-rank one either side of it.
        var monotone = true
        for c in corpus {
            for pass in c.passes {
                let values = Self.envelopePercentileSweep.compactMap { pass.envelopeByP[$0] }
                for (a, b) in zip(values, values.dropFirst()) where b < a { monotone = false }
            }
        }
        for s in scenes {
            let values = Self.envelopePercentileSweep.compactMap { s.envelopeByP[$0] }
            for (a, b) in zip(values, values.dropFirst()) where b < a { monotone = false }
        }
        print("every reading monotone in the percentile: \(monotone)")
        let notMonotone = "the envelope readings are no longer monotone in the percentile —"
            + " the bracket below may not be interpolated"
        #expect(monotone, "\(notMonotone)")

        func width(_ p: Float, _ bar: Float) -> Float { brackets[p]?[bar]?.jointWidth ?? 0 }
        func empty(_ p: Float, _ bar: Float) -> Bool { brackets[p]?[bar]?.empty ?? true }

        for bar in supportBars {
            let live = Self.envelopePercentileSweep.filter { !empty($0, bar) }
            let widest = live.max { width($0, bar) < width($1, bar) }
            print("at ringSupportMin \(fmt(bar)), joint window by percentile: "
                  + Self.envelopePercentileSweep.map {
                      "\(fmt($0)) → \(fmt(width($0, bar))) mm" + (empty($0, bar) ? " EMPTY" : "")
                  }.joined(separator: ", ")
                  + "; NON-EMPTY over \(fmt(live.min() ?? 0))…\(fmt(live.max() ?? 0)),"
                  + " widest \(fmt(width(widest ?? 0, bar))) mm at \(fmt(widest ?? 0)),"
                  + " shipped \(fmt(shippedP)) \(empty(shippedP, bar) ? "OUTSIDE" : "inside")")
        }

        // MARK: what the sweep says

        // THE ANCHOR ON THE FINDING, not just on the code. At the shipped percentile, in the
        // `ringSupportMin` regime Decision 48 read it in, the corpus bracket is that
        // decision's 7.154…21.041 mm and the joint window against the suite is its 1.079 mm.
        // Everything below is a statement about how far that reading travels.
        let shipped48 = try #require(brackets[shippedP]?[decision48Bar])
        print("Decision 48 reproduced: corpus \(fmt(shipped48.corpusFloor))…"
              + "\(fmt(shipped48.corpusCeiling)) mm, joint \(fmt(shipped48.jointWidth)) mm")
        let reproduced = "Decision 48's foodEnvelopeMinMm bracket no longer reads"
            + " 7.154…21.041 mm with a 1.079 mm joint window at the shipped percentile"
            + " (\(fmt(shipped48.corpusFloor))…\(fmt(shipped48.corpusCeiling)),"
            + " \(fmt(shipped48.jointWidth)) mm)"
        #expect(abs(shipped48.corpusFloor - 7.154) < 0.01
                && abs(shipped48.corpusCeiling - 21.041) < 0.01
                && abs(shipped48.jointWidth - 1.079) < 0.01, "\(reproduced)")

        // THE FIRST FINDING: the percentile is a UNIT and not a peer, and it re-denominates
        // every bound ever quoted on `foodEnvelopeMinMm`. The corpus ceiling — the intended
        // candidate's own envelope, the number Decisions 34 and 48 both bound the constant
        // above by — runs from −19.415 mm at p = 0 to +26.038 mm at p = 1, so the constant's
        // whole two-sided bracket moves 45 mm across a constant that was never varied.
        let ceilings = Self.envelopePercentileSweep.compactMap {
            brackets[$0]?[decision48Bar]?.corpusCeiling
        }
        let ceilingSpan = (ceilings.max() ?? 0) - (ceilings.min() ?? 0)
        print("corpus ceiling on foodEnvelopeMinMm over the percentile:"
              + " \(fmt(ceilings.min() ?? 0))…\(fmt(ceilings.max() ?? 0)) mm"
              + " = \(fmt(ceilingSpan)) mm of movement")
        let unitMoved = "the envelope bar's corpus ceiling no longer moves with the"
            + " percentile (\(fmt(ceilingSpan)) mm) — it is not the unit this records"
        #expect(ceilingSpan > 40, "\(unitMoved)")

        // THE SECOND FINDING, and it is where the shipped value sits. In Decision 48's own
        // regime the joint window is non-empty over 0.02…0.92 and the shipped 0.90 is the
        // second-narrowest reading in it — 1.079 mm against 8.779 mm at p = 0.5, an 8.1×
        // collapse, with only 0.92's 0.075 mm below it. So "the narrowest joint window in
        // the feature" is a property of the DENOMINATOR and not of the constant it bounds,
        // and the shipped percentile is very nearly the value that makes it narrowest
        // without making it empty.
        let widestWidth = Self.envelopePercentileSweep.filter { !empty($0, decision48Bar) }
            .map { width($0, decision48Bar) }.max() ?? 0
        print("joint window at the shipped percentile \(fmt(width(shippedP, decision48Bar))) mm"
              + " against \(fmt(widestWidth)) mm at its widest"
              + " — \(fmt(widestWidth / max(width(shippedP, decision48Bar), 1e-6)))×")
        let notNarrow = "the shipped percentile no longer sits at a near-minimal joint"
            + " window (\(fmt(width(shippedP, decision48Bar))) mm against"
            + " \(fmt(widestWidth)) mm) — Decision 48's 1.079 mm is not the denominator's doing"
        #expect(widestWidth > 4 * width(shippedP, decision48Bar), "\(notNarrow)")

        // THE THIRD FINDING, and it is the one that moves another decision. Whether the
        // corpus floors `foodEnvelopeMinMm` AT ALL depends on `ringSupportMin`, which
        // Decision 48 never named: the two above-surface candidates carry 0.183 and 0.304
        // inner-band support, both inside that constant's (0, 0.362] bracket. Below 0.183
        // both reach the envelope guard and the floor is 8.958 mm — ABOVE the suite's
        // ceiling, so the joint window is EMPTY at the shipped percentile. Between them the
        // floor is Decision 48's 7.154 mm. Above 0.304 neither reaches it and there is NO
        // floor, which is Decision 34's original reading restored. One constant, three
        // regimes, all three admissible today.
        let regimes = supportBars.map { bar -> String in
            let b = brackets[shippedP]?[bar]
            return "\(fmt(bar)) → \(b?.hasCorpusFloor == true ? "\(fmt(b?.corpusFloor ?? 0)) mm" : "no floor")"
                + ", joint \(fmt(width(shippedP, bar))) mm\(empty(shippedP, bar) ? " EMPTY" : "")"
        }
        print("corpus floor at the shipped percentile by ringSupportMin: "
              + regimes.joined(separator: "; "))
        let conditional = "the corpus floor on foodEnvelopeMinMm no longer depends on"
            + " ringSupportMin — Decision 48's floor is unconditional after all and this"
            + " finding can be retired"
        #expect(empty(shippedP, 0.15) && !empty(shippedP, 0.25)
                && brackets[shippedP]?[0.35]?.hasCorpusFloor == false, "\(conditional)")

        // THE FOURTH FINDING, and it is the only bound on this constant that needs nothing
        // owed. At the SHIPPED `foodEnvelopeMinMm = 0` the committed suite is RED below
        // p = 0.1: `overhangingFood` requires the envelope guard to pass and its envelope is
        // negative at 0.05 and below, because a percentile that low reads the overhanging
        // lobe rather than the loaf. That is a floor stated in no owed value at all — the
        // fifth distinct way the suite has spoken to a constant here, after Decision 41's
        // brackets, Decision 49's measured silence, Decision 50's structural silence and
        // Decision 52's noise-limited identity.
        let suiteFloorOnP = try #require(suiteFloorP)
        let suiteFloorMoved = "the committed suite is no longer red below p = 0.1 at the"
            + " shipped foodEnvelopeMinMm (floor \(fmt(suiteFloorOnP))) — the one bound on"
            + " this constant that needs no owed value has moved"
        #expect(suiteFloorOnP == 0.1, "\(suiteFloorMoved)")
    }

    // MARK: - The fallback's fixed budget, and the argument the promoted leg made against it

    // One improvement to `LiDARPlaneFitter.ransac`'s running best, and the iteration it
    // landed on. The shipped loop keeps no record of these — it returns only the winner —
    // and they are the whole reading, because they are the only iterations at which the
    // budget can matter.
    struct BudgetImprovement {
        let iteration: Int       // 1-based, the iteration that raised the best score
        let normal: Vec3
        let d: Float
        let inliers: [Int]
        let drawsSoFar: Int      // triples that reached the cone test
        let rejectedSoFar: Int   // triples the cone turned away
    }

    // `LiDARPlaneFitter.ransac` with the budget as the loop bound, the cone as an argument
    // (Decision 55 measured what it takes OUT of the budget and this is where that is paid)
    // and every improvement recorded. Every other line is the shipped path's — the same
    // unconditional three draws, the same degenerate-triple test, the same orientation onto
    // gravity's half-space, the same plain inlier count with no connected component — so at
    // (`maxIterations`, `gravityAngleMaxRad`) it reproduces the shipped winner exactly.
    //
    // ONE run at the top of the sweep is exact for every value below it, and that is a
    // property of the shipped loop rather than a shortcut. `uniformInt` consumes exactly one
    // `next()`, the loop draws i, j and k unconditionally before any `continue`, and nothing
    // else touches the RNG — so iteration t is the SAME triple whatever the budget is, and a
    // budget-B run is a strict prefix of a budget-B′ run for B < B′. The winner at budget B
    // is therefore the last improvement at or before B.
    // `theFallbackBudgetTruncatesASearchThatNeverFinishes` checks that against independent
    // short runs rather than assuming it.
    static func fallbackRansacTrace(points: [Vec3], gravity: Vec3, rng: inout SplitMix64,
                                    budget: Int, coneRad: Float) -> [BudgetImprovement] {
        var improvements: [BudgetImprovement] = []
        var bestScore = 0
        var draws = 0
        var rejected = 0
        let n = points.count
        guard budget >= 1, n >= LiDARPlaneFitter.minPoints else { return improvements }

        for iteration in 1...budget {
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = points[i], p2 = points[j], p3 = points[k]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            draws += 1
            if acos(SupportRegion.clampedCosine(nHat.dot(gravity))) > coneRad {
                rejected += 1
                continue
            }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in 0..<n where abs(nHat.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                inliers.append(idx)
            }
            guard inliers.count > bestScore else { continue }
            bestScore = inliers.count
            improvements.append(BudgetImprovement(
                iteration: iteration, normal: nHat, d: d, inliers: inliers,
                drawsSoFar: draws, rejectedSoFar: rejected))
        }
        return improvements
    }

    // What the fallback SHIPS at one budget: the winner refined, polished and passed through
    // the residual gate, exactly as `fitOutcome` does it. The refusal is carried rather than
    // collapsed to nil because a budget that starves the fit is a different reading from one
    // that produces a wrong plane, and Req 4.5's rate counts them the same way.
    struct BudgetReading {
        let budget: Int
        let winnerIteration: Int   // 0 when no draw ever improved on nothing
        let planeAtFoodMm: Float
        let normal: Vec3
        let d: Float
        let tiltDeg: Float
        let residualMm: Float
        let inlierCount: Int
        let hypothesisRatio: Float // the winner's raw inlier share, the adaptive input
        let refusal: String?
        let polishIterations: Int
        let polishStop: PolishStop
    }

    static func fallbackBudgetReading(points: [Vec3], gravity: Vec3, ray: Vec3,
                                      budget: Int, coneRad: Float,
                                      improvements: [BudgetImprovement]) -> BudgetReading {
        func starved(_ why: String) -> BudgetReading {
            BudgetReading(budget: budget, winnerIteration: 0, planeAtFoodMm: .nan,
                          normal: gravity, d: 0, tiltDeg: .nan, residualMm: .nan,
                          inlierCount: 0, hypothesisRatio: 0, refusal: why,
                          polishIterations: 0, polishStop: .cap)
        }
        guard let winner = improvements.last(where: { $0.iteration <= budget }),
              winner.inliers.count >= LiDARPlaneFitter.minPoints else {
            return starved("\(SupportPlaneError.noLidarPoints)")
        }
        guard let refined = try? LiDARPlaneFitter.refine(
            inliers: winner.inliers.map { points[$0] }, seedNormal: winner.normal) else {
            return starved("\(SupportPlaneError.lidarFitDegenerate)")
        }

        var normal = refined.0
        var d = refined.1
        var polishedInliers = winner.inliers
        var applied = 0
        var stop = PolishStop.cap
        for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(normal.dot(points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                reselected.append(idx)
            }
            if reselected == polishedInliers { stop = .fixedPoint; break }
            if reselected.count < LiDARPlaneFitter.minPoints { stop = .underpopulated; break }
            guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                inliers: reselected.map { points[$0] }, seedNormal: normal
            ) else { stop = .degenerate; break }
            if acos(SupportRegion.clampedCosine(nextNormal.dot(gravity))) > coneRad {
                stop = .gravity
                break
            }
            polishedInliers = reselected
            normal = nextNormal
            d = nextD
            applied += 1
        }

        let residual = LiDARPlaneFitter.computeResidual(
            points: polishedInliers.map { points[$0] }, normal: normal, d: d)
        return BudgetReading(
            budget: budget, winnerIteration: winner.iteration,
            planeAtFoodMm: Self.planeDepthMm(normal: normal, d: d, ray: ray),
            normal: normal, d: d,
            tiltDeg: acos(SupportRegion.clampedCosine(normal.dot(gravity))) * 180 / .pi,
            residualMm: residual, inlierCount: polishedInliers.count,
            hypothesisRatio: Float(winner.inliers.count) / Float(points.count),
            refusal: residual > LiDARPlaneFitter.residualMaxMm
                ? "\(SupportPlaneError.lidarFitResidualTooHigh)" : nil,
            polishIterations: applied, polishStop: stop)
    }

    // The promoted leg's stopping rule replayed over the fallback's OWN improvement trace.
    // `SupportRegion.ccRansac` recomputes `requiredIterations` from the best ratio every time
    // the best improves and leaves the loop once the iteration count reaches it; this loop
    // has no such exit. The replay is exact and free — the trace already carries every ratio
    // and the iteration it was reached on — and it is the counterfactual the comment in
    // `ccRansac` is an argument for. One difference is inherent and stated rather than
    // hidden: the promoted rule reads the largest CONNECTED component's share, and the
    // fallback has no component step, so the ratio here is the raw inlier share. That makes
    // the replay optimistic about the fallback, which is the safe direction for a claim that
    // the budget is too large.
    static func adaptiveStop(_ trace: [BudgetImprovement], pointCount: Int, cap: Int)
        -> (iterations: Int, winner: BudgetImprovement?) {
        var required = cap
        var winner: BudgetImprovement?
        var iteration = 0
        while iteration < required && iteration < cap {
            iteration += 1
            guard let improvement = trace.first(where: { $0.iteration == iteration }) else {
                continue
            }
            winner = improvement
            let ratio = Float(improvement.inliers.count) / Float(pointCount)
            required = Swift.max(1, Swift.min(cap, Int(Self.requiredIterations(
                inlierRatio: ratio,
                successProbability: SupportRegion.ransacSuccessProbability).rounded(.up))))
        }
        return (iteration, winner)
    }

    // What `SupportPlaneRegressionSliceTests` asserts about the plane THIS constant produces.
    // Every other suite reading in this pass has been on `SPRScene` scenes, which run neither
    // extraction nor the fallback fit (Decisions 50, 54) — the fallback leg's committed
    // constraints live in the regression file instead, measured against the same two slices.
    // Restated here rather than referenced because that file computes them from the SHIPPED
    // budget; the point is to run them at every other value.
    struct FallbackSuiteBand {
        let ringMedianMinMm: Float
        let ringMedianMaxMm: Float
        let supportFractionMax: Float   // `.infinity` where the file asserts nothing
        let volumeCm3: Float
        let volumeTolerance: Float
    }

    static let fallbackSuiteBands: [String: FallbackSuiteBand] = [
        // `ringMeasureSeparatesTheTwoReferences` and `correctingThePlaneRemovesVolume`.
        "1785135663727": FallbackSuiteBand(ringMedianMinMm: 2, ringMedianMaxMm: 8,
                                           supportFractionMax: 0.5,
                                           volumeCm3: 682.96, volumeTolerance: 0.05),
        // `ringMeasureSeparatesTheTwoReferencesOnTheWeighedCapture` and
        // `theWeighedCapturesFoodMaskIsTooLarge`.
        "1785901032716": FallbackSuiteBand(ringMedianMinMm: 4, ringMedianMaxMm: .infinity,
                                           supportFractionMax: .infinity,
                                           volumeCm3: 714.84, volumeTolerance: 0.05),
    ]

    // `SupportPlaneRegressionSliceTests.volumeCm3`, restated so a plane the regression file
    // cannot produce can still be priced through it. Same per-pixel integration above the
    // plane, same oblique-pixel area term.
    static func foodVolumeCm3(geometry g: SupportRegion.DepthGeometry,
                              normal: Vec3, d: Float) -> Float {
        let k = g.intrinsics
        let fMean = (k.fx + k.fy) / 2
        var mm3: Float = 0
        for index in g.foodIndices {
            let point = g.points[index]
            let height = normal.dot(point) - d
            guard height > 0 else { continue }
            let x = index % k.imageWidth, y = index / k.imageWidth
            let du = Float(x) - k.cx, dv = Float(y) - k.cy
            let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
            let z = -point.z
            mm3 += height * (z * z) / (k.fx * k.fy * cosTheta * cosTheta * cosTheta)
        }
        return mm3 / 1000
    }

    // Halvings down to a single draw, and two doublings above the shipped 256 — the same
    // shape Decision 51 swept `maxIterationsPerPass` on. 1 is the floor with a meaning: one
    // triple, refined and polished, which is what the loop degenerates to and what a budget
    // has to buy something over.
    static let fallbackBudgetSweep = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]

    // The budget is spent on DRAWS and the cone rejects some of them before they cost an
    // inlier scan, so the two are coupled and Decision 55 measured one half of it. Read at
    // the shipped budget: three cones, its own tightest, the corpus floor that decision
    // found, and the shipped bar.
    static let fallbackBudgetConeSweep: [Float] = [1, 8, 15]

    @Test("the fallback's iteration budget truncates a search that never finishes, and the suite bounds it where Req 4.3 does not")
    func theFallbackBudgetTruncatesASearchThatNeverFinishes() throws {
        struct Capture {
            let name: String
            let slice: DepthSlice
            let points: [Vec3]
            let gravity: Vec3
            let ray: Vec3
        }

        var corpus: [Capture] = []
        for name in Self.captures {
            let slice = try DepthSlice.load(name)
            let inputs = LiDARPlaneFitter.Inputs(
                depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
                foodRegionMask: slice.colourFoodMask, gravityCamera: slice.gravity)
            var stats = SupportPlaneFitStats()
            let points = LiDARPlaneFitter.collectCandidatePoints(inputs, stats: &stats)
            corpus.append(Capture(name: name, slice: slice, points: points,
                                  gravity: slice.gravity.normalised(),
                                  ray: try #require(Self.foodCentroidRay(slice))))
        }

        let shippedCone = LiDARPlaneFitter.gravityAngleMaxRad
        let top = try #require(Self.fallbackBudgetSweep.max())

        // One traced run per capture at the top of the sweep, at the shipped cone.
        var traceByName: [String: [BudgetImprovement]] = [:]
        var readingsByName: [String: [BudgetReading]] = [:]
        for c in corpus {
            var rng = SplitMix64(seed: Fnv1a64.hash(c.slice.depth.depthBytesMm))
            let trace = Self.fallbackRansacTrace(
                points: c.points, gravity: c.gravity, rng: &rng,
                budget: top, coneRad: shippedCone)
            traceByName[c.name] = trace
            readingsByName[c.name] = Self.fallbackBudgetSweep.map {
                Self.fallbackBudgetReading(points: c.points, gravity: c.gravity, ray: c.ray,
                                           budget: $0, coneRad: shippedCone,
                                           improvements: trace)
            }
        }

        // THE ANCHOR, in two halves. At the shipped budget the instrumented chain must BE
        // `LiDARPlaneFitter.fitOutcome` — the same plane, not a plane within a tolerance —
        // or nothing below is a reading on the shipped path. And the prefix claim the single
        // traced run rests on is checked against short runs drawn independently from the
        // same seed, because if it were false every value below the top would be fiction.
        for c in corpus {
            let shipped = try #require(Self.fallbackPlane(c.slice))
            let reading = try #require(readingsByName[c.name]?
                .first { $0.budget == LiDARPlaneFitter.maxIterations })
            let drift = "\(c.name): the instrumented budget chain no longer reproduces"
                + " LiDARPlaneFitter.fitOutcome at maxIterations"
            #expect(reading.normal == shipped.normal && reading.d == shipped.distanceMm,
                    "\(drift)")

            for budget in [4, 64, LiDARPlaneFitter.maxIterations] {
                var rng = SplitMix64(seed: Fnv1a64.hash(c.slice.depth.depthBytesMm))
                let direct = Self.fallbackRansacTrace(
                    points: c.points, gravity: c.gravity, rng: &rng,
                    budget: budget, coneRad: shippedCone)
                let derived = (traceByName[c.name] ?? []).filter { $0.iteration <= budget }
                let notAPrefix = "\(c.name): a budget-\(budget) run is no longer a prefix of"
                    + " the budget-\(top) run (\(direct.count) improvements direct,"
                    + " \(derived.count) derived) — the loop's RNG consumption has stopped"
                    + " being fixed per iteration and the sweep below is sampled, not exact"
                #expect(direct.count == derived.count, "\(notAPrefix)")
                for (a, b) in zip(direct, derived) {
                    #expect(a.iteration == b.iteration && a.normal == b.normal && a.d == b.d,
                            "\(notAPrefix)")
                }
            }
        }

        for c in corpus {
            let trace = traceByName[c.name] ?? []
            print("=== \(c.name) === \(c.points.count) colour-grid candidate points")
            print("  improvements over \(top) iterations:"
                  + " \(trace.map { "#\($0.iteration) → \($0.inliers.count)" }.joined(separator: ", "))")
            for r in readingsByName[c.name] ?? [] {
                let shippedPlane = readingsByName[c.name]?
                    .first { $0.budget == LiDARPlaneFitter.maxIterations }?.planeAtFoodMm
                print("  budget \(r.budget): winner from iteration \(r.winnerIteration),"
                      + " plane \(fmt(r.planeAtFoodMm)) mm"
                      + " (\(fmt(r.planeAtFoodMm - (shippedPlane ?? r.planeAtFoodMm))) vs shipped),"
                      + " tilt \(fmt(r.tiltDeg))°, residual \(fmt(r.residualMm)) mm,"
                      + " inliers \(r.inlierCount), hypothesis ratio \(fmt(r.hypothesisRatio)),"
                      + " polish \(r.polishIterations) stopped on \(r.polishStop.rawValue)"
                      + "\(r.refusal.map { ", REFUSED \($0)" } ?? "")")
            }
        }

        // MARK: what the budget buys

        // THE FIRST FINDING, and it is the mirror of Decision 51's. That decision measured
        // `SupportRegion.maxIterationsPerPass` and found it NEVER FIRES: the promoted leg's
        // pass stops adaptively at 72, 11, 250 and 12, 41, 5 draws against a cap of 2048, so
        // the cap truncates nothing it wanted. This loop has NO adaptive stopping at all — a
        // bare `for _ in 0..<maxIterations` — so it spends every iteration it is given, and
        // the search it truncates NEVER FINISHES: RANSAC's running best is monotone in the
        // draws and nothing here stops it, so doubling the budget to 1024 finds a better
        // hypothesis on BOTH captures (improvements at #689 and #1005, against the #76 and
        // #210 that 256 stops at). There is no value at which the search is done, and the
        // shipped 256 is a truncation rather than a convergence point. Two caps on two legs
        // of one feature, both `[owed]`: one never binds, the other cannot stop binding.
        var lastImprovement: [String: Int] = [:]
        for c in corpus {
            lastImprovement[c.name] = (traceByName[c.name] ?? []).last?.iteration ?? 0
        }
        print("last improvement over \(top) iterations: "
              + lastImprovement.map { "\($0.key) #\($0.value)" }.sorted().joined(separator: ", ")
              + " — the shipped budget is \(LiDARPlaneFitter.maxIterations)")
        let converges = "the fallback's search now converges inside the shipped budget"
            + " (last improvements \(lastImprovement.sorted { $0.key < $1.key }.map(\.value))"
            + " of \(top)) — the budget has stopped being an arbitrary truncation and can be"
            + " read as a value the corpus reaches"
        #expect(lastImprovement.values.allSatisfy { $0 > LiDARPlaneFitter.maxIterations },
                "\(converges)")

        // THE SECOND FINDING, and it is a FOURTH kind of provenance failure. The constant
        // carries no marker and no comment — a bare `static let` — which is Decisions 47, 48
        // and 51's shape. But a derivation for it does exist, it is CORRECT, and it is a
        // REFUTATION: `SupportRegion.ccRansac` and `SupportRegionCandidateTests` both carry
        // "maxIterations = 256 was sized to find the DOMINANT plane and must not be inherited
        // on faith — P(clean triple) is 98 % at w = 0.25 but 3 % at w = 0.05". The promoted
        // leg ACTED on that and built adaptive stopping; the fallback leg still runs on the
        // number the argument rejects, and the argument is filed on the leg that abandoned
        // it. After Decision 56's marker that reads correctly and covers a different
        // quantity, this is a derivation that reads correctly and argues against its own
        // constant, recorded where it cannot be found from the constant.
        //
        // Replayed rather than argued: the promoted leg's own stopping rule, run over the
        // fallback's own improvement trace, exits at a small fraction of the budget and
        // lands INSIDE Req 5.1's 1 mm of the plane the 256 draws produce. The winning
        // hypothesis holds a far larger share than either ratio the paragraph prices — the
        // fallback fits the table over the colour-grid edge bands, which is the easiest fit
        // in the feature — so the budget is generous because the surface is easy, exactly
        // the shape Decision 51 found on the other leg.
        var adaptiveByName: [String: (iterations: Int, deltaMm: Float, ratio: Float)] = [:]
        for c in corpus {
            let trace = traceByName[c.name] ?? []
            let stop = Self.adaptiveStop(trace, pointCount: c.points.count,
                                         cap: LiDARPlaneFitter.maxIterations)
            let reading = Self.fallbackBudgetReading(
                points: c.points, gravity: c.gravity, ray: c.ray,
                budget: stop.iterations, coneRad: shippedCone, improvements: trace)
            let shipped = try #require(readingsByName[c.name]?
                .first { $0.budget == LiDARPlaneFitter.maxIterations })
            adaptiveByName[c.name] = (stop.iterations,
                                      abs(reading.planeAtFoodMm - shipped.planeAtFoodMm),
                                      shipped.hypothesisRatio)
        }
        print("the promoted leg's stopping rule replayed on the fallback: "
              + adaptiveByName.map {
                  "\($0.key) stops at \($0.value.iterations) draws"
                  + " (\(fmt(Float(LiDARPlaneFitter.maxIterations) / Float($0.value.iterations)))×"
                  + " cheaper), plane \(fmt($0.value.deltaMm)) mm off the shipped one,"
                  + " measured ratio \(fmt($0.value.ratio))"
              }.sorted().joined(separator: "; ")
              + " — at p = \(SupportRegion.ransacSuccessProbability)")
        let ruleAgrees = "the promoted leg's stopping rule no longer disagrees with the"
            + " fallback's budget (\(adaptiveByName.sorted { $0.key < $1.key }.map(\.value.iterations))"
            + " draws, planes \(adaptiveByName.sorted { $0.key < $1.key }.map { fmt($0.value.deltaMm) }) mm off)"
            + " — the refutation filed in ccRansac has stopped applying to this constant"
        #expect(adaptiveByName.values.allSatisfy {
            $0.iterations < LiDARPlaneFitter.maxIterations
                && $0.deltaMm < Self.gridTransferToleranceMm
        }, "\(ruleAgrees)")

        // THE THIRD FINDING: it is a FLOOR, not a knob, and the floor is EIGHT DRAWS. The
        // plane spans 23.474 mm and 0.152 mm at the food over the sweep, and every millimetre
        // of the wide one is below a budget of 8 — from 8 up the two captures hold to 0.027
        // and 0.152 mm, both inside Req 5.1's 1 mm, while a budget of 2 sits 23.466 mm out at
        // a 9.504° tilt. Second owed constant with this shape after Decision 55's gravity
        // cone, and for the same reason: below the floor the loop has not yet drawn a triple
        // on the table, and above it every further draw is refining a plane it already has.
        // One-capture footing, Decision 36's again: only `1785135663727` moves past Req 5.1
        // at all, because `1785901032716`'s table holds 0.857 of the points on the FIRST draw
        // and every budget in the sweep sits within 0.152 mm of the shipped plane there.
        var spanByName: [String: Float] = [:]
        var spanAboveFloorByName: [String: Float] = [:]
        let answerFloor = 8
        for c in corpus {
            let readings = (readingsByName[c.name] ?? []).filter { !$0.planeAtFoodMm.isNaN }
            let planes = readings.map(\.planeAtFoodMm)
            spanByName[c.name] = (planes.max() ?? 0) - (planes.min() ?? 0)
            let above = readings.filter { $0.budget >= answerFloor }.map(\.planeAtFoodMm)
            spanAboveFloorByName[c.name] = (above.max() ?? 0) - (above.min() ?? 0)
        }
        print("plane movement at the food over the BUDGET sweep: "
              + spanByName.map { "\($0.key) \(fmt($0.value)) mm" }.sorted().joined(separator: ", ")
              + "; from a budget of \(answerFloor) up: "
              + spanAboveFloorByName.map { "\($0.key) \(fmt($0.value)) mm" }.sorted()
                .joined(separator: ", ")
              + " — against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm")
        let inert = "the budget is inert on the corpus after all — no value in the sweep moves"
            + " the fallback plane past Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm"
            + " (spans \(spanByName.sorted { $0.key < $1.key }.map { fmt($0.value) }))"
        #expect(spanByName.values.contains { $0 > Self.gridTransferToleranceMm }, "\(inert)")
        let floorMoved = "the corpus no longer floors the budget at \(answerFloor) draws —"
            + " above it the plane moves"
            + " \(spanAboveFloorByName.sorted { $0.key < $1.key }.map { fmt($0.value) }) mm"
            + " against Req 5.1's \(fmt(Self.gridTransferToleranceMm)) mm"
        #expect(spanAboveFloorByName.values
            .allSatisfy { $0 < Self.gridTransferToleranceMm }, "\(floorMoved)")

        // THE FOURTH FINDING, and it settles which document actually constrains this
        // constant. Req 4.3 does NOT: it requires the plane USED when the fallback fires to
        // equal the one the edge-band fit PRODUCES for that capture, and both sides of that
        // identity move together when the budget moves — Decision 54's reading of the same
        // requirement, restated on a constant only one leg reads. The byte-identity is an
        // internal consistency, not a freeze, and the shipped bits are reproduced by
        // {256, 512} alone precisely because the search never converges: below 256 an
        // earlier improvement wins, at 1024 a later one does.
        //
        // What DOES bound it is the committed SUITE, and this is the SIXTH distinct way the
        // suite has spoken here — after Decision 41's brackets, Decision 49's measured
        // silence, Decision 50's structural silence, Decision 52's noise-limited identity
        // and Decision 56's floor at the shipped bar — and the FIRST through the FALLBACK
        // leg. `SupportPlaneRegressionSliceTests` measures the pre-feature plane on these
        // same two slices: its ring median in 2…8 mm and support fraction below 0.5 on
        // `1785135663727`, its ring median above 4 mm on `1785901032716`, and its food
        // volume within 5 % of 682.96 and 714.84 cm³. Those are assertions about the plane
        // this constant produces, so they bracket it, and they bracket it from BELOW: a
        // budget of 1 or 2 turns the parity capture's ring median NEGATIVE (−4.309 mm, the
        // sign the whole regression criterion is about), its support to 0.594 against a 0.5
        // bar and its volume to 200.885 cm³ against 682.96, so all three assertions go red at
        // once and the suite floors the budget at 4.
        //
        // And the suite is the LOOSER of the two sources, which no earlier decision has seen.
        // Decision 41 found the committed suite binding TIGHTER than the corpus on two
        // constants and warned that a value set from captures alone could land inside the
        // corpus bracket and outside the suite's; here the corpus floors at 8 and the suite at
        // 4, so a budget of 4 passes every committed assertion while sitting 2.231 mm from
        // the shipped plane — past Req 5.1's 1 mm. The regression bands are volume and
        // ring-median bands, not transfer bands, and on this constant that gap is 4 draws.
        var shippedByName: [String: BudgetReading] = [:]
        for c in corpus {
            shippedByName[c.name] = try #require(readingsByName[c.name]?
                .first { $0.budget == LiDARPlaneFitter.maxIterations })
        }
        let byteIdenticalBudgets = Self.fallbackBudgetSweep.filter { budget in
            corpus.allSatisfy { c in
                guard let shipped = shippedByName[c.name],
                      let here = (readingsByName[c.name] ?? [])
                          .first(where: { $0.budget == budget }) else { return false }
                return here.normal == shipped.normal && here.d == shipped.d
            }
        }
        print("budgets returning the shipped bits on the whole corpus:"
              + " \(byteIdenticalBudgets) of \(Self.fallbackBudgetSweep)")
        let converged = "the shipped bits are now reproduced outside {256, 512}"
            + " (\(byteIdenticalBudgets)) — the search has started converging and finding one"
            + " needs re-reading"
        #expect(byteIdenticalBudgets == [LiDARPlaneFitter.maxIterations, 512], "\(converged)")

        struct SuiteVerdict {
            let budget: Int
            let failures: [String]
        }
        var suiteByName: [String: [SuiteVerdict]] = [:]
        for c in corpus {
            let g = try #require(Self.geometry(c.name))
            let band = try #require(Self.fallbackSuiteBands[c.name])
            suiteByName[c.name] = (readingsByName[c.name] ?? []).map { r in
                var failures: [String] = []
                guard !r.planeAtFoodMm.isNaN else {
                    return SuiteVerdict(budget: r.budget, failures: ["no plane"])
                }
                let plane = SupportPlane(normal: r.normal, distanceMm: r.d,
                                         residualMm: r.residualMm, convergedIterations: nil)
                if let ring = SupportRegion.ringStatistics(
                    for: plane, depth: c.slice.depth, foodMask: c.slice.foodMask,
                    intrinsics: c.slice.colourIntrinsics) {
                    if ring.medianMm <= band.ringMedianMinMm || ring.medianMm >= band.ringMedianMaxMm {
                        failures.append("ring median \(fmt(ring.medianMm)) mm")
                    }
                    if ring.supportFraction >= band.supportFractionMax {
                        failures.append("support \(fmt(ring.supportFraction))")
                    }
                } else {
                    failures.append("no ring")
                }
                let volume = Self.foodVolumeCm3(geometry: g, normal: r.normal, d: r.d)
                if abs(volume - band.volumeCm3) / band.volumeCm3 >= band.volumeTolerance {
                    failures.append("volume \(fmt(volume)) cm³")
                }
                return SuiteVerdict(budget: r.budget, failures: failures)
            }
        }
        for c in corpus {
            print("  \(c.name) against its committed regression bands: "
                  + (suiteByName[c.name] ?? []).map {
                      "\($0.budget)\($0.failures.isEmpty ? " ok" : " RED on \($0.failures.joined(separator: ", "))")"
                  }.joined(separator: "; "))
        }
        let suiteFloor = Self.fallbackBudgetSweep.first { budget in
            Self.fallbackBudgetSweep.filter { $0 >= budget }.allSatisfy { above in
                corpus.allSatisfy { c in
                    suiteByName[c.name]?.first { $0.budget == above }?.failures.isEmpty == true
                }
            }
        }
        print("committed suite floor on the budget: \(suiteFloor.map(String.init) ?? "none")")
        let suiteSilent = "the committed regression bands no longer floor the budget"
            + " (floor \(suiteFloor.map(String.init) ?? "none")) — the fallback leg's one"
            + " committed source has gone silent on this constant"
        #expect(suiteFloor != nil && suiteFloor! > 1
                && suiteFloor! < LiDARPlaneFitter.maxIterations, "\(suiteSilent)")

        // MARK: what it costs

        // THE FIFTH FINDING: what the spend is denominated in. Every iteration is a full O(n)
        // inlier scan over the COLOUR grid — this loop is the one place in the feature that
        // runs at 1920×1440 rather than over the depth annulus — so the budget multiplies a
        // point count two orders of magnitude larger than the promoted leg's 10,469 and
        // 12,551 annulus samples (Decision 51). Req 7.6's latency and the 32 GB allocation
        // failure `refine` was rewritten for both live here. Decision 55 recorded Req 7.6
        // pulling one owed constant TIGHTER and noted no other does; this is the second, and
        // the first where the corpus does not pull against it — everything above the 8-draw
        // floor is measured to change nothing, rather than being insurance the captures
        // cannot price. Decision 54's polish cap is the contrast: there the corpus pointed
        // ABOVE the shipped value while Req 7.6 pointed below it.
        for c in corpus {
            let total = c.points.count * LiDARPlaneFitter.maxIterations
            let past = c.points.count * (LiDARPlaneFitter.maxIterations - answerFloor)
            print("  \(c.name): \(c.points.count) points ×"
                  + " \(LiDARPlaneFitter.maxIterations) = \(total) distance tests,"
                  + " \(fmt(100 * Float(past) / Float(total))) % of them past the"
                  + " \(answerFloor)-draw floor the answer settles at")
        }

        // MARK: the cone the budget is spent against

        // THE SIXTH FINDING: every reading above is a SLICE at `gravityAngleMaxRad`. A
        // rejected triple costs an iteration and buys nothing, so the cone decides how much
        // of the budget is reachable — Decision 55 measured 137 and 10 of 256 draws rejected
        // at the shipped bar and 252 and 207 at 1°, and this is where that spend is paid for.
        // Re-traced at the shipped budget under three cones, the last improvement moves with
        // the bar (#76 → #46 and #210 → #236 at 1°, where 45 of 46 and 192 of 236 draws are
        // rejected by then), so neither the floor nor Req 4.3's admissible set can be quoted
        // without naming the cone it was read at.
        var byCone: [Float: [String: (last: Int, rejected: Int, draws: Int, plane: Float)]] = [:]
        for coneDeg in Self.fallbackBudgetConeSweep {
            let coneRad = coneDeg * .pi / 180
            var row: [String: (last: Int, rejected: Int, draws: Int, plane: Float)] = [:]
            for c in corpus {
                var rng = SplitMix64(seed: Fnv1a64.hash(c.slice.depth.depthBytesMm))
                let trace = Self.fallbackRansacTrace(
                    points: c.points, gravity: c.gravity, rng: &rng,
                    budget: LiDARPlaneFitter.maxIterations, coneRad: coneRad)
                let reading = Self.fallbackBudgetReading(
                    points: c.points, gravity: c.gravity, ray: c.ray,
                    budget: LiDARPlaneFitter.maxIterations, coneRad: coneRad,
                    improvements: trace)
                row[c.name] = (trace.last?.iteration ?? 0,
                               trace.last?.rejectedSoFar ?? 0,
                               trace.last?.drawsSoFar ?? 0,
                               reading.planeAtFoodMm)
            }
            byCone[coneDeg] = row
            print("  cone \(fmt(coneDeg))°: "
                  + row.map {
                      "\($0.key) last improvement iteration \($0.value.last),"
                      + " \($0.value.rejected)/\($0.value.draws) draws rejected by then,"
                      + " plane \(fmt($0.value.plane)) mm"
                  }.sorted().joined(separator: "; "))
        }
        let coneFree = "the last improvement no longer moves with the gravity cone — the"
            + " budget's floor is not a reading at gravityAngleMaxRad after all and"
            + " Decision 55's rejection counts no longer cost anything"
        #expect(Self.fallbackBudgetConeSweep.contains { coneDeg in
            guard let tight = byCone[coneDeg], let shipped = byCone[15] else { return false }
            return corpus.contains { tight[$0.name]?.last != shipped[$0.name]?.last }
        }, "\(coneFree)")
    }

    // MARK: - Req 4.5: what the fallback rate is a function of

    // Every `[owed]` bar `admissibility` applies, so the rate can be measured as a
    // function of them. The bars NOT here are the ones that are not owed:
    // `ringMedianMaxMm` is `[inherited]` from `ringBandMm`, and `ringMinSamples` is
    // `[measured]`. Keeping them fixed is the whole point of the sweep — it asks what
    // the corpus does when everything still to be set is set as permissively as it can be.
    struct OwedBars {
        var sectors: Int
        var supportMin: Float
        var extentMm: Float
        var envelopeMinMm: Float
        var stepMaxMm: Float
        var visibilityMin: Float
        var escapeMm: Float
        var marginMin: Float

        static let shipped = OwedBars(
            sectors: SupportRegion.minSupportingSectors,
            supportMin: SupportRegion.ringSupportMin,
            extentMm: SupportRegion.minAcceptedExtentMm,
            envelopeMinMm: SupportRegion.foodEnvelopeMinMm,
            stepMaxMm: SupportRegion.bandStepMaxMm,
            visibilityMin: SupportRegion.supportVisibilityMin,
            escapeMm: SupportRegion.escapeBandMm,
            marginMin: SupportRegion.ringSupportMarginMin)

        // Every owed bar at the most permissive value it could ever be given. Not a
        // proposal — the point of evaluating here is that no setting of the owed
        // constants can admit more than this does.
        static let loosest = OwedBars(
            sectors: 0, supportMin: 0, extentMm: 0,
            envelopeMinMm: -.greatestFiniteMagnitude,
            stepMaxMm: .greatestFiniteMagnitude,
            visibilityMin: 0, escapeMm: .greatestFiniteMagnitude,
            marginMin: 0)

        func with(sectors: Int? = nil, supportMin: Float? = nil) -> OwedBars {
            var copy = self
            if let sectors { copy.sectors = sectors }
            if let supportMin { copy.supportMin = supportMin }
            return copy
        }
    }

    // `SupportRegion.admissibility` with the owed bars parameterised. Pinned against the
    // shipped function inside the test below, so this restatement cannot drift from it.
    static func admissible(_ m: CandidateMeasurement, bars: OwedBars) -> Bool {
        if m.candidate.extentMm < bars.extentMm { return false }
        if m.ring.supportFraction < bars.supportMin { return false }
        if m.ring.supportingSectors < bars.sectors { return false }
        if m.envelopeMm < bars.envelopeMinMm { return false }
        if abs(m.ring.bandMedianMm[0]) > SupportRegion.ringMedianMaxMm { return false }
        if m.ring.bandMedianMm.count > 1,
           m.ring.bandMedianMm[1] - m.ring.bandMedianMm[0] > bars.stepMaxMm { return false }
        if m.ring.supportVisibility < bars.visibilityMin { return false }
        if m.annulusMedianMm > bars.escapeMm { return false }
        return true
    }

    // `fitFoodSupportPlane`'s whole selection, including the ambiguity margin that can
    // send a capture back to the fallback even when two candidates were admitted. nil
    // means this capture falls back.
    static func selection(_ measurements: [CandidateMeasurement],
                          bars: OwedBars) -> CandidateMeasurement? {
        let admitted = measurements.filter { admissible($0, bars: bars) }
            .sorted { $0.ring.supportFraction > $1.ring.supportFraction }
        guard let best = admitted.first else { return nil }
        if admitted.count >= 2,
           best.ring.supportFraction - admitted[1].ring.supportFraction < bars.marginMin {
            return nil
        }
        return best
    }

    // Req 4.5 wants a fallback rate above which the feature is a defect, and
    // `prerequisites.md` has been treating the open question as WHICH corpus to measure
    // it on. On the corpus that exists there is a prior question: the rate is a function
    // of the `[owed]` constants and of nothing else, so a threshold stated now would
    // grade the placeholders rather than the algorithm — the circularity Req 3.7 forbids
    // for the sector trio, arriving at Req 4.5 by another route.
    //
    // `SupportPlaneRegressionSliceTests` already records that both captures fall back.
    // What is measured here is the SHAPE of that: where the rate moves as the owed bars
    // move, which plane each capture lands on when it stops falling back, and what holds
    // the wrong planes out once every owed bar is as permissive as it could ever be.
    @Test("the corpus fallback rate spans 100 %…0 % on the owed constants alone")
    func fallbackRateIsAFunctionOfTheOwedConstantsAlone() throws {
        var byCapture: [String: [CandidateMeasurement]] = [:]
        for name in Self.captures {
            byCapture[name] = Self.measurements(name)
            #expect(byCapture[name]?.isEmpty == false, "\(name) produced no candidates")
        }

        // The restatement above is `admissibility` with the owed bars pulled out. At the
        // shipped bars it must agree with the shipped function on every candidate, or the
        // sweep below is measuring a different guard set.
        for (name, measurements) in byCapture {
            for (i, m) in measurements.enumerated() {
                let shipped = SupportRegion.admissibility(
                    ring: m.ring, annulusMedianMm: m.annulusMedianMm,
                    foodEnvelopeMm: m.envelopeMm, extentMm: m.candidate.extentMm) == nil
                let drifted = "\(name) candidate \(i): the parameterised guards disagree"
                    + " with SupportRegion.admissibility at the shipped bars"
                #expect(Self.admissible(m, bars: .shipped) == shipped, "\(drifted)")
            }
        }

        func rate(_ bars: OwedBars) -> Float {
            let fallbacks = Self.captures.filter {
                Self.selection(byCapture[$0] ?? [], bars: bars) == nil
            }.count
            return Float(fallbacks) / Float(Self.captures.count)
        }

        // The rate the shipped placeholders produce. Req 4.5's own words for this state
        // are "delivering nothing".
        let shippedRate = rate(.shipped)
        print("shipped fallback rate \(fmt(shippedRate)) over \(Self.captures.count) captures")
        let moved = "the corpus no longer falls back on every capture at the shipped bars —"
            + " Req 4.5's rate has a real reading now and this derivation must be redone"
        #expect(shippedRate == 1, "\(moved)")

        // One owed bar, swept alone. `minSupportingSectors` is the guard the shipped
        // short-circuit returns on the parity capture's intended candidate.
        var curve: [(Int, Float)] = []
        for sectors in stride(from: SupportRegion.ringSectorCount, through: 0, by: -1) {
            curve.append((sectors, rate(OwedBars.shipped.with(sectors: sectors))))
        }
        print("rate vs minSupportingSectors: "
              + curve.map { "\($0.0)→\(fmt($0.1))" }.joined(separator: " "))
        // Above the corpus's intended score the rate is total; at or below it, one capture
        // is recovered and the other is not, because a second owed bar is in front of it.
        for (sectors, r) in curve {
            let step = "the rate at minSupportingSectors = \(sectors) is \(fmt(r)),"
                + " not what the corpus measured when this was derived"
            #expect(r == (sectors > 5 ? 1 : 0.5), "\(step)")
        }

        // Every owed bar at once, as permissive as each could ever be set. No setting of
        // the owed constants admits more than this, so whatever is still rejected here is
        // rejected by something that is NOT owed.
        let loosestRate = rate(.loosest)
        print("loosest-owed fallback rate \(fmt(loosestRate))")
        let stuck = "the corpus still falls back somewhere with every owed bar at its most"
            + " permissive value — something not owed is now refusing the fit, and Req 4.5's"
            + " rate is no longer a function of the owed constants alone"
        #expect(loosestRate == 0, "\(stuck)")

        // And the plane each capture lands on there is the one Req 3.1 names: inner-band
        // median nearest zero. The rate reaching 0 is therefore not bought by admitting a
        // wrong plane — which is the claim a rate threshold would otherwise be guarding.
        for name in Self.captures {
            let measurements = try #require(byCapture[name])
            let selected = try #require(Self.selection(measurements, bars: .loosest))
            let nearestZero = try #require(
                measurements.min { abs($0.ring.bandMedianMm[0]) < abs($1.ring.bandMedianMm[0]) })
            print("\(name) at the loosest owed bars: inner band"
                  + " \(fmt(selected.ring.bandMedianMm[0])) mm,"
                  + " support \(fmt(selected.ring.supportFraction)),"
                  + " sectors \(selected.ring.supportingSectors)")
            let wrong = "\(name) selects a plane whose inner band is"
                + " \(fmt(selected.ring.bandMedianMm[0])) mm while a candidate at"
                + " \(fmt(nearestZero.ring.bandMedianMm[0])) mm exists — driving the rate to"
                + " zero now costs a wrong plane, which changes what Req 4.5's threshold is for"
            #expect(selected.candidate.d == nearestZero.candidate.d, "\(wrong)")
        }

        // What rejects the rest. `ringMedianMaxMm` is `[inherited]` from `ringBandMm`, so
        // the separation that survives the loosest owed setting is not owed to the capture
        // session at all — and the margin it holds it by is worth knowing.
        var closestMarginMm = Float.greatestFiniteMagnitude
        for name in Self.captures {
            let measurements = try #require(byCapture[name])
            let selected = try #require(Self.selection(measurements, bars: .loosest))
            for m in measurements where m.candidate.d != selected.candidate.d {
                let excess = abs(m.ring.bandMedianMm[0]) - SupportRegion.ringMedianMaxMm
                let held = "\(name) has a candidate at inner band"
                    + " \(fmt(m.ring.bandMedianMm[0])) mm that the inherited ringMedianMaxMm"
                    + " does not reject, so it survives the loosest owed setting on the owed"
                    + " bars alone"
                #expect(excess > 0, "\(held)")
                closestMarginMm = min(closestMarginMm, excess)
            }
        }
        print("closest rejected candidate clears ringMedianMaxMm"
              + " (\(SupportRegion.ringMedianMaxMm) mm) by \(fmt(closestMarginMm)) mm")
        // Stated as a bound rather than an equality so a third capture narrowing it fails
        // here rather than silently: this is the whole margin the corpus's wrong planes are
        // held out by once the owed bars stop contributing.
        let widened = "the inherited ring-median bar now clears every rejected candidate"
            + " by \(fmt(closestMarginMm)) mm — the sub-millimetre margin Decision 42"
            + " records has widened and the finding should be restated"
        #expect(closestMarginMm < 1, "\(widened)")
    }

    // MARK: - Helpers

    // Everything `admissibility` reads, per candidate, computed once.
    struct CandidateMeasurement {
        let candidate: SupportRegion.PlaneCandidate
        let ring: RingStatistics
        let annulusMedianMm: Float
        let envelopeMm: Float
    }

    static func measurements(_ name: String) -> [CandidateMeasurement]? {
        guard let (g, samples) = prepared(name), let candidates = candidates(name) else {
            return nil
        }
        return candidates.compactMap { candidate -> CandidateMeasurement? in
            guard let ring = SupportRegion.ringStatistics(
                samples: samples, geometry: g,
                normal: candidate.normal, d: candidate.d) else { return nil }
            return CandidateMeasurement(
                candidate: candidate, ring: ring,
                annulusMedianMm: SupportRegion.medianHeight(
                    indices: samples.annulus, geometry: g,
                    normal: candidate.normal, d: candidate.d),
                envelopeMm: SupportRegion.foodEnvelopeMm(
                    geometry: g, normal: candidate.normal, d: candidate.d))
        }
    }

    // Every guard `admissibility` applies, evaluated independently and returned in the
    // shipped order rather than short-circuited. `laterGuardsAreUnexercisedOnTheCorpus`
    // pins `first` against `admissibility` so this restatement cannot drift from it.
    static func allRejections(_ m: CandidateMeasurement) -> [SupportRegion.CandidateRejection] {
        var fired: [SupportRegion.CandidateRejection] = []
        if m.candidate.extentMm < SupportRegion.minAcceptedExtentMm { fired.append(.extent) }
        if m.ring.supportFraction < SupportRegion.ringSupportMin { fired.append(.supportFraction) }
        if m.ring.supportingSectors < SupportRegion.minSupportingSectors { fired.append(.sectors) }
        if m.envelopeMm < SupportRegion.foodEnvelopeMinMm { fired.append(.foodEnvelope) }
        if abs(m.ring.bandMedianMm[0]) > SupportRegion.ringMedianMaxMm { fired.append(.ringMedian) }
        if m.ring.bandMedianMm.count > 1,
           m.ring.bandMedianMm[1] - m.ring.bandMedianMm[0] > SupportRegion.bandStepMaxMm {
            fired.append(.bandStep)
        }
        if m.ring.supportVisibility < SupportRegion.supportVisibilityMin { fired.append(.visibility) }
        if m.annulusMedianMm > SupportRegion.escapeBandMm { fired.append(.escaped) }
        return fired
    }

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

    static func geometry(_ slice: DepthSlice, decimation: Int) -> SupportRegion.DepthGeometry? {
        let scaled = decimated(slice, by: decimation)
        return SupportRegion.prepare(depth: scaled.depth,
                                     colourIntrinsics: scaled.colourIntrinsics,
                                     foodRegionMask: scaled.foodMask)
    }

    // `ringSamples`'s radial banding with the inner radius as a parameter, so a proposed
    // radius can be measured before it is shipped. Everything else — the distance
    // transform, `ringOuterMm`, `ringBandCount`, the validity and food-mask exclusions —
    // is the shipped path's.
    static func bandCounts(geometry g: SupportRegion.DepthGeometry, innerMm: Float) -> [Int] {
        var counts = [Int](repeating: 0, count: SupportRegion.ringBandCount)
        let bandWidthMm = (SupportRegion.ringOuterMm - innerMm) / Float(SupportRegion.ringBandCount)
        guard bandWidthMm > 0 else { return counts }
        let distancePx = SupportRegion.distanceToFoodPx(mask: g.foodMask)
        for y in 0..<g.height {
            for x in 0..<g.width {
                let idx = y * g.width + x
                guard g.valid[idx], !g.foodMask.isFood(x: x, y: y) else { continue }
                let distMm = distancePx[idx] * g.mmPerPx
                guard distMm >= innerMm, distMm <= SupportRegion.ringOuterMm else { continue }
                counts[min(SupportRegion.ringBandCount - 1,
                           Int((distMm - innerMm) / bandWidthMm))] += 1
            }
        }
        return counts
    }

    // `SupportRegion.ringSamples` with the OUTER radius as a parameter. Everything else —
    // the distance transform, `ringInnerMm`, `ringBandCount`, `annulusOuterMm`, the
    // validity and food-mask exclusions, the sector bucketing — is the shipped path's, so
    // at `ringOuterMm` it reproduces `ringSamples` exactly and the sweep below is
    // measuring the radius alone.
    //
    // Note what moves with it and what does not. The inner edge is `ringInnerMm`, fixed
    // by the depth smear (Decision 39), so the radius sets the ring's WIDTH; the band
    // width is that width over `ringBandCount`, so the inner band the sector rule reads
    // ends at `ringInnerMm + (outerMm − ringInnerMm) / 3`. The candidate bound does NOT
    // move with it — `annulusOuterMm` is a constant of its own since Decision 49 — so this
    // re-rings a fixed candidate set.
    static func ringSamples(geometry g: SupportRegion.DepthGeometry,
                            outerMm: Float) -> SupportRegion.RingSamples {
        ringSamples(geometry: g, outerMm: outerMm,
                    annulusOuterMm: SupportRegion.annulusOuterMm)
    }

    // The bound as `annulusOuterMultiple × ringOuterMm` expressed it, which is how every
    // reading of the radius between Decisions 46 and 49 took it. Kept because Decision 46's
    // sweep is a measurement OF that coupling and Decision 49's decomposition compares
    // against it; it is not the shipped path any more.
    static func coupledBoundMm(_ outerMm: Float) -> Float { 2 * outerMm }

    // The same re-ringing with the CANDIDATE BOUND as a second argument. The two were tied
    // until Decision 49 — the annulus was `annulusOuterMultiple × ringOuterMm`, so every
    // reading of the radius moved the ring and the candidate set together. Separating them
    // is what said which of the two the movement belonged to.
    static func ringSamples(geometry g: SupportRegion.DepthGeometry,
                            outerMm: Float,
                            annulusOuterMm: Float) -> SupportRegion.RingSamples {
        let distancePx = SupportRegion.distanceToFoodPx(mask: g.foodMask)
        let bandWidthMm = (outerMm - SupportRegion.ringInnerMm) / Float(SupportRegion.ringBandCount)
        var ring: [Int] = [], band: [Int] = [], sector: [Int] = [], annulus: [Int] = []
        guard bandWidthMm > 0 else {
            return SupportRegion.RingSamples(ring: ring, band: band, sector: sector,
                                             annulus: annulus)
        }
        for y in 0..<g.height {
            for x in 0..<g.width {
                let idx = y * g.width + x
                guard g.valid[idx], !g.foodMask.isFood(x: x, y: y) else { continue }
                let distMm = distancePx[idx] * g.mmPerPx
                guard distMm <= annulusOuterMm else { continue }
                annulus.append(idx)
                guard distMm >= SupportRegion.ringInnerMm, distMm <= outerMm else { continue }
                let b = min(SupportRegion.ringBandCount - 1,
                            Int((distMm - SupportRegion.ringInnerMm) / bandWidthMm))
                ring.append(idx)
                band.append(b)
                sector.append(b == 0 ? SupportRegion.sectorIndex(x: x, y: y, geometry: g) : -1)
            }
        }
        return SupportRegion.RingSamples(ring: ring, band: band, sector: sector,
                                         annulus: annulus)
    }

    // The inner-band share within ±`ringBandMm`, computed without `ringStatistics`'s
    // `ringMinSamples` guard so a radius that refuses the floor can still be read. This
    // is the quantity `bestCandidate` ranks on.
    // `bandMm` is an argument because `ringBandMm` is `[inherited]` from
    // `LiDARPlaneFitter.inlierBandMm` and Decision 52 sweeps the constant it inherits
    // from; at the shipped value this is the shipped quantity.
    static func innerSupportFraction(samples: SupportRegion.RingSamples,
                                     geometry g: SupportRegion.DepthGeometry,
                                     normal: Vec3, d: Float,
                                     bandMm: Float = SupportRegion.ringBandMm) -> Float {
        var total = 0, supported = 0
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            total += 1
            if abs(normal.dot(g.points[idx]) - d) <= bandMm { supported += 1 }
        }
        return total == 0 ? 0 : Float(supported) / Float(total)
    }

    static func prepared(_ name: String) -> (SupportRegion.DepthGeometry, SupportRegion.RingSamples)? {
        guard let g = geometry(name) else { return nil }
        return (g, SupportRegion.ringSamples(geometry: g))
    }

    // MARK: - The confidence bar, and what it decides a SAMPLE is

    // ARKit's three confidence levels as `DepthMap` bytes (§6.0): LOW → 0, MEDIUM → 127,
    // HIGH → 255. τ_conf is compared against `byte / 255`, so the constant's whole domain
    // is THREE states rather than a continuum. The measurement below asserts the corpus
    // carries no other byte value, because that is what makes three exhaustive.
    static let arkitConfidenceBytes: Set<UInt8> = [0, 127, 255]

    // The MEDIUM level normalised, and the only boundary inside τ_conf's domain that the
    // sweep can cross: at or below it MEDIUM survives, above it only HIGH does. The shipped
    // `LiDARPlaneFitter.confidenceThreshold` sits below, and `HeightFieldEstimator.tauConfidence`
    // — the 0.66 the fitter's bar was lowered FROM — sits above.
    static let mediumConfidence = Float(127) / 255

    // Twelve values across the whole domain, deliberately dense either side of
    // `mediumConfidence`. Twelve rather than three because the collapse to three distinct
    // readings is a FINDING and not an assumption: a corpus carrying a byte the ARKit levels
    // do not produce would separate 0.45 from 0.49, and this sweep would say so.
    static let tauConfSweep: [Float] = [0, 0.1, 0.2, 0.3, 0.4, 0.45, 0.49, 0.5, 0.6, 0.66, 0.8, 1.0]

    // A LOW population large enough for the accept-all state to be readable at all. One percent
    // of the depth grid is ~491 samples on the corpus grid, above `ringMinSamples`; below it a
    // capture cannot say whether admitting LOW would cost anything.
    static let materialLowShare: Float = 0.01

    // τ_conf re-denominated as a rewritten confidence map, which is what lets this sweep run
    // the SHIPPED path end to end. `SupportRegion.prepare` drops a sample when
    // `confidence / 255 < LiDARPlaneFitter.confidenceThreshold`; rewriting every byte to 255
    // when it clears `tauConf` and to 0 otherwise makes the shipped bar admit exactly the set
    // `tauConf` admits. Unlike every other sweep in this file — the count, the bar, the radius,
    // the band count, the removal band, the iteration budget, the inlier band — there is no
    // restatement of shipped code here that could drift from it, and the anchor below checks
    // the identity at the shipped value.
    //
    // The depth bytes are untouched, so `Fnv1a64.hash(depthBytesMm)` is identical at every
    // value and the RANSAC SEED is held across the sweep. The draw is not: `uniformInt(n)`
    // reads the residue size, which moves with the sample set.
    static func reconfidenced(_ slice: DepthSlice, tauConf: Float) -> DepthSlice {
        let rewritten = [UInt8](slice.depth.confidenceBytes).map { byte -> UInt8 in
            Float(byte) / 255 >= tauConf ? 255 : 0
        }
        return DepthSlice(
            name: slice.name,
            depth: DepthMap(
                depthBytesMm: slice.depth.depthBytesMm,
                confidenceBytes: Data(rewritten),
                width: slice.depth.width, height: slice.depth.height,
                rowStrideBytes: slice.depth.rowStrideBytes,
                depthIntrinsics: slice.depth.depthIntrinsics,
                depthFromColour: slice.depth.depthFromColour),
            colourIntrinsics: slice.colourIntrinsics,
            gravity: slice.gravity,
            foodMask: slice.foodMask)
    }

    // One capture read at one confidence bar and one inlier band. Both are arguments because
    // the band is what τ_conf turns out to be upstream OF (Decision 52's constant), and the
    // grid of the two is the only way to see that.
    struct TauReading {
        let tauConf: Float
        let bandMm: Float
        let validCount: Int
        let foodSampleCount: Int
        let annulusCount: Int
        let ringCount: Int
        let ringFeasible: Bool
        let passCount: Int
        // The plane the ranking selects, where it cuts the food-centroid ray. The ray is
        // taken from the UNTOUCHED slice — the mask centroid does not depend on validity —
        // so the millimetres compare across the sweep.
        let planeAtFoodMm: Float
        let intendedPass: Int
        let intendedRingMedianMm: Float
        let intendedInnerMedianMm: Float
        let intendedSupportFraction: Float
        let intendedSupporting: Int
        let intendedCrossed: Int
        let intendedEnvelopeMm: Float
        var ringMedianGuardFires: Bool { abs(intendedInnerMedianMm) > bandMm }
    }

    static func tauReading(_ slice: DepthSlice, tauConf: Float,
                           bandMm: Float = LiDARPlaneFitter.inlierBandMm) -> TauReading? {
        let rewritten = reconfidenced(slice, tauConf: tauConf)
        guard let g = SupportRegion.prepare(depth: rewritten.depth,
                                            colourIntrinsics: rewritten.colourIntrinsics,
                                            foodRegionMask: rewritten.foodMask),
              let ray = foodCentroidRay(slice) else { return nil }
        let samples = SupportRegion.ringSamples(geometry: g)
        var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
        let candidates = extractCandidates(annulus: samples.annulus, geometry: g,
                                           gravity: rewritten.gravity.normalised(),
                                           rng: &rng, bandMm: bandMm)
        guard !candidates.isEmpty else { return nil }

        func ringMedian(_ c: SupportRegion.PlaneCandidate) -> Float {
            SupportRegion.medianHeight(indices: samples.ring, geometry: g,
                                       normal: c.normal, d: c.d)
        }
        // The ranking's winner, read at the SHIPPED band so the sweep does not move the
        // ranking as well as the sample set, and the plane a correct fit must select —
        // Decision 48's identification, the candidate nearest Req 3.1's zero.
        let winner = candidates.max {
            innerSupportFraction(samples: samples, geometry: g, normal: $0.normal, d: $0.d,
                                 bandMm: LiDARPlaneFitter.inlierBandMm)
            < innerSupportFraction(samples: samples, geometry: g, normal: $1.normal, d: $1.d,
                                   bandMm: LiDARPlaneFitter.inlierBandMm)
        }
        guard let winner,
              let intendedIndex = (0..<candidates.count).min(by: {
                  abs(ringMedian(candidates[$0])) < abs(ringMedian(candidates[$1]))
              }) else { return nil }
        let intended = candidates[intendedIndex]
        let signs = sectorSigns(samples: samples, geometry: g,
                                normal: intended.normal, d: intended.d,
                                count: SupportRegion.ringSectorCount,
                                supportMin: SupportRegion.sectorSupportMin, bandMm: bandMm)

        return TauReading(
            tauConf: tauConf,
            bandMm: bandMm,
            validCount: g.valid.filter { $0 }.count,
            foodSampleCount: g.foodSampleCount,
            annulusCount: samples.annulus.count,
            ringCount: samples.ring.count,
            ringFeasible: SupportRegion.ringBandsAreFeasible(samples: samples),
            passCount: candidates.count,
            planeAtFoodMm: planeDepthMm(normal: winner.normal, d: winner.d, ray: ray),
            intendedPass: intendedIndex + 1,
            intendedRingMedianMm: ringMedian(intended),
            intendedInnerMedianMm: bandMediansMm(samples: samples, geometry: g,
                                                 normal: intended.normal, d: intended.d,
                                                 bandCount: SupportRegion.ringBandCount)[0],
            intendedSupportFraction: innerSupportFraction(samples: samples, geometry: g,
                                                          normal: intended.normal, d: intended.d,
                                                          bandMm: bandMm),
            intendedSupporting: signs.supporting,
            intendedCrossed: signs.crossedFailing,
            intendedEnvelopeMm: SupportRegion.foodEnvelopeMm(geometry: g, normal: intended.normal,
                                                             d: intended.d))
    }

    // Share of food-mask samples a given bar discards. `lowConfidenceFoodShare` is this at
    // the fitter's own bar; the bar is a parameter here because there are TWO of them.
    static func lowConfidenceFoodShare(_ slice: DepthSlice, tauConf: Float) -> Float {
        let w = slice.depth.width, h = slice.depth.height
        let confidence = slice.depth.confidenceBytes
        guard confidence.count >= w * h else { return 0 }
        var food = 0, low = 0
        for y in 0..<h {
            for x in 0..<w where slice.foodMask.isFood(x: x, y: y) {
                food += 1
                if Float(confidence[y * w + x]) / 255 < tauConf { low += 1 }
            }
        }
        return food == 0 ? 0 : Float(low) / Float(food)
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

    // The sector measure with its sign put back (Decision 30's proposal). `supporting` is
    // exactly what `ringStatistics` computes today; everything else is what the absolute
    // value discards. A failing sector reading BELOW the plane means the ring left the
    // support surface — the plate ended. One reading ABOVE it means the support surface
    // is still there and the plane is not on it.
    struct SectorSigns {
        let supporting: Int          // the shipped unsigned count
        let medians: [Float]         // signed inner-band median per sector
        let failing: [Int]           // sector indices below `sectorSupportMin`
        let failingMedians: [Float]
        let crossedFailing: Int      // failing sectors reading above +ringBandMm
        let escapedFailing: Int      // failing sectors reading below −ringBandMm
        let crossedAll: Int          // any sector reading above +ringBandMm
        // Inner-band samples per sector. The sector measure's statistical footing, and
        // the quantity `ringMinSamples = ringSectorCount × 25` exists to floor.
        let sectorSampleCounts: [Int]
    }

    static func sectorSigns(samples: SupportRegion.RingSamples,
                            geometry g: SupportRegion.DepthGeometry,
                            normal: Vec3, d: Float) -> SectorSigns {
        sectorSigns(samples: samples, geometry: g, normal: normal, d: d,
                    count: SupportRegion.ringSectorCount)
    }

    // `SupportRegion.sectorIndex` with the count as an argument rather than read from the
    // shipped constant. Same arithmetic — equal arcs about the food-mask centroid — so at
    // `ringSectorCount` it reproduces `samples.sector` exactly, which is what lets the
    // reading above delegate here and the sweep below re-sector the same ring.
    static func sectorIndex(x: Int, y: Int, geometry g: SupportRegion.DepthGeometry,
                            count: Int) -> Int {
        let angle = atan2(Float(y) - g.centroidY, Float(x) - g.centroidX)
        let normalised = (angle + .pi) / (2 * .pi)
        return min(count - 1, max(0, Int(normalised * Float(count))))
    }

    // The inner band re-cut into `count` equal arcs, classified at `supportMin`. Both are
    // `[owed]` constants, so both are arguments here: the count says how the ring is cut
    // and the bar says which of the resulting sectors Decision 40's rule may read.
    // `samples.sector` is only ever populated for band 0, so the band test is what selects
    // the inner band here too.
    //
    // `bandMm` is a third argument for the same reason (Decision 52): it is BOTH the
    // tolerance a sector is supported within and — as `ringBandMm` — the magnitude bar
    // Decision 40's rule inherits, so a sweep of `LiDARPlaneFitter.inlierBandMm` moves the
    // classification and the crossing bar together. At the shipped value it reproduces
    // the shipped reading.
    static func sectorSigns(samples: SupportRegion.RingSamples,
                            geometry g: SupportRegion.DepthGeometry,
                            normal: Vec3, d: Float, count: Int,
                            supportMin: Float = SupportRegion.sectorSupportMin,
                            bandMm: Float = SupportRegion.ringBandMm) -> SectorSigns {
        var total = [Int](repeating: 0, count: count)
        var supported = [Int](repeating: 0, count: count)
        var heights = [[Float]](repeating: [], count: count)
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            let s = sectorIndex(x: idx % g.width, y: idx / g.width, geometry: g, count: count)
            let height = normal.dot(g.points[idx]) - d
            total[s] += 1
            heights[s].append(height)
            if abs(height) <= bandMm { supported[s] += 1 }
        }
        let medians = heights.map { $0.isEmpty ? Float.nan : $0.sorted()[$0.count / 2] }
        func fraction(_ s: Int) -> Float {
            total[s] == 0 ? 0 : Float(supported[s]) / Float(total[s])
        }
        // Empty sectors count as neither supporting nor failing, as in `ringStatistics`.
        let failing = (0..<count).filter {
            total[$0] > 0 && fraction($0) < supportMin
        }
        let failingMedians = failing.map { medians[$0] }
        return SectorSigns(
            supporting: (0..<count).filter {
                total[$0] > 0 && fraction($0) >= supportMin
            }.count,
            medians: medians,
            failing: failing,
            failingMedians: failingMedians,
            crossedFailing: failingMedians.filter { $0 > bandMm }.count,
            escapedFailing: failingMedians.filter { $0 < -bandMm }.count,
            crossedAll: medians.filter { $0 > bandMm }.count,
            sectorSampleCounts: total)
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
        let outerMm = SupportRegion.annulusOuterMm
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
