import CaptureKit
import Confidence
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
                   supportMin: Float = SupportRegion.sectorSupportMin) -> SectorSigns {
            SupportPlaneCorpusMeasurementTests.sectorSigns(
                samples: samples, geometry: geometry, normal: normal, d: planeD,
                count: count, supportMin: supportMin)
        }
    }

    // Every guard, for the four scenes whose committed test requires the whole fit to
    // succeed — passing one guard is not enough when the assertion is `#require(fit)`.
    static let everyGuard: [SupportRegion.CandidateRejection] = [
        .supportFraction, .sectors, .foodEnvelope, .bandStep, .visibility, .escaped,
    ]

    // The eight scenes the committed suites assert on, each at the plane its own test
    // evaluates. Changing a scene changes these bounds, which is the point: they are
    // properties of the committed tests, not of the geometry.
    static func sceneReadings() -> [SceneReading] {
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
        return scenes.compactMap { label, grid, heightMm, requiresPass, requiresFire in
            guard let measured = SPRScene.measure(grid) else { return nil }
            let p = SPRScene.plane(atHeightMm: heightMm)
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
    static func sectorSigns(samples: SupportRegion.RingSamples,
                            geometry g: SupportRegion.DepthGeometry,
                            normal: Vec3, d: Float, count: Int,
                            supportMin: Float = SupportRegion.sectorSupportMin) -> SectorSigns {
        var total = [Int](repeating: 0, count: count)
        var supported = [Int](repeating: 0, count: count)
        var heights = [[Float]](repeating: [], count: count)
        for (i, idx) in samples.ring.enumerated() where samples.band[i] == 0 {
            let s = sectorIndex(x: idx % g.width, y: idx / g.width, geometry: g, count: count)
            let height = normal.dot(g.points[idx]) - d
            total[s] += 1
            heights[s].append(height)
            if abs(height) <= SupportRegion.ringBandMm { supported[s] += 1 }
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
            crossedFailing: failingMedians.filter { $0 > SupportRegion.ringBandMm }.count,
            escapedFailing: failingMedians.filter { $0 < -SupportRegion.ringBandMm }.count,
            crossedAll: medians.filter { $0 > SupportRegion.ringBandMm }.count,
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
