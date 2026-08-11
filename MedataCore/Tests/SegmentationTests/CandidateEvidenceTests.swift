import Foundation
import Testing
@testable import Segmentation

// Alternative-class evidence over synthetic FP16 tensors with known per-channel
// structure. The statistic is the mean over the food's sampled pixels
// (Decision 13); eligibility narrows the channel set before that mean is taken,
// so a sentinel can never occupy a slot.
@Suite("CandidateEvidence")
struct CandidateEvidenceTests {

    // Solids 0…6, liquids 7…8, background 9, unknown_food 10,
    // unsupported_liquid 11 — the shipped palette's shape, small enough to
    // write expected rankings by hand.
    static let palette = ClassPalette(
        foodClasses: ["solid_a", "solid_b", "solid_c", "solid_d", "solid_e", "solid_f", "solid_g"],
        liquidClasses: ["liquid_a", "liquid_b"],
        background: 9, unknownFood: 10, unsupportedLiquid: 11,
        version: "test"
    )
    static let classes = palette.totalClasses          // 12
    static let solidA = 0, solidB = 1, solidC = 2, solidD = 3
    static let liquidA = 7, liquidB = 8
    static let background = 9, unknownFood = 10, unsupportedLiquid = 11

    // MARK: - fixtures

    /// FP16 tensor built from a per-pixel probability vector, encoded through
    /// the same `FP16Bytes.encode` the post-processor uses — so the test reads
    /// exactly the bytes a persisted bundle would carry.
    static func tensor(
        width: Int, height: Int,
        vector: (_ y: Int, _ x: Int) -> [Float]
    ) -> ProbabilityTensor {
        var values = [Float](repeating: 0, count: width * height * classes)
        for y in 0..<height {
            for x in 0..<width {
                let v = vector(y, x)
                precondition(v.count == classes)
                let off = (y * width + x) * classes
                for c in 0..<classes { values[off + c] = v[c] }
            }
        }
        return ProbabilityTensor(
            bytes: FP16Bytes.encode(values),
            height: height, width: width, classes: classes, palette: palette
        )
    }

    static func labels(
        width: Int, height: Int,
        label: (_ y: Int, _ x: Int) -> Int
    ) -> ArgmaxMap {
        var pixels = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width { pixels[y * width + x] = UInt8(label(y, x)) }
        }
        return ArgmaxMap(pixels: pixels, height: height, width: width)
    }

    /// A probability vector with the named channels set and everything else 0.
    static func vec(_ entries: [Int: Float]) -> [Float] {
        var v = [Float](repeating: 0, count: classes)
        for (c, p) in entries { v[c] = p }
        return v
    }

    // MARK: - ranking

    @Test("Ranks eligible channels by mean and quantises to permille")
    func ranksByMean() {
        // 64×64, all one solid: 16×16 = 256 sampled pixels, well clear of the floor.
        let probs = Self.vec([
            Self.solidA: 0.5,      // the food's own channel — excluded
            Self.solidC: 0.2,
            Self.solidB: 0.15,
            Self.solidD: 0.05,
            Self.background: 0.1,  // excluded
        ])
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in probs },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )

        #expect(evidence.keys.sorted() == ["solid_a"])
        #expect(evidence["solid_a"] == [
            CandidateEvidence.Candidate(className: "solid_c", meanPermille: 200),
            CandidateEvidence.Candidate(className: "solid_b", meanPermille: 150),
            CandidateEvidence.Candidate(className: "solid_d", meanPermille: 50),
        ])
    }

    @Test("A class that won no pixel anywhere still ranks (Req 1.2)")
    func neverWinningClassRanks() {
        // solid_c is the argmax nowhere on the plate, yet carries the most
        // eligible mass over solid_a's pixels.
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.solidA: 0.6, Self.solidC: 0.3, Self.solidB: 0.1])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )
        #expect(evidence["solid_a"]?.first?.className == "solid_c")
    }

    @Test("Ties keep channel declaration order")
    func tiesKeepDeclarationOrder() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.solidA: 0.4, Self.solidD: 0.2, Self.solidB: 0.2, Self.solidC: 0.2])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )
        #expect(evidence["solid_a"]?.map(\.className) == ["solid_b", "solid_c", "solid_d"])
    }

    // MARK: - eligibility

    @Test("Excludes self, background, both sentinels and the opposite phase")
    func excludesIneligibleChannels() {
        // Every ineligible channel outweighs the one eligible candidate.
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([
                    Self.solidA: 0.3,
                    Self.background: 0.9,
                    Self.unknownFood: 0.8,
                    Self.unsupportedLiquid: 0.7,
                    Self.liquidA: 0.6,
                    Self.liquidB: 0.5,
                    Self.solidB: 0.01,
                ])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )
        #expect(evidence["solid_a"]?.map(\.className) == ["solid_b"])
    }

    @Test("A liquid food takes liquid candidates only")
    func liquidTakesLiquidCandidates() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.liquidA: 0.4, Self.solidA: 0.4, Self.liquidB: 0.2])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.liquidA },
            palette: Self.palette
        )
        #expect(evidence["liquid_a"]?.map(\.className) == ["liquid_b"])
    }

    @Test("Only strictly positive support is retained")
    func zeroSupportDropped() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.solidA: 0.9, Self.solidB: 0.1])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )
        // solid_c…solid_g carry no mass at all and earn no slot, so the set is
        // shorter than the five-candidate maximum.
        #expect(evidence["solid_a"]?.count == 1)
    }

    @Test("At most five candidates per detected food")
    func capsAtFiveCandidates() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([
                    Self.solidA: 0.28, 1: 0.18, 2: 0.16, 3: 0.14, 4: 0.12, 5: 0.08, 6: 0.04,
                ])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.solidA },
            palette: Self.palette
        )
        #expect(evidence["solid_a"]?.map(\.className)
                == ["solid_b", "solid_c", "solid_d", "solid_e", "solid_f"])
    }

    // MARK: - sampling floor, set cap, stride anchoring

    @Test("The five-set cap keeps the most sampled foods")
    func fiveSetCapKeepsLargestFoods() {
        // Seven horizontal bands, heights descending in steps of 4 so every band
        // clears the 64-sample floor and their sampled counts are strictly
        // ordered: 160, 144, 128, 112, 96, 80, 64 sampled pixels.
        let heights = [40, 36, 32, 28, 24, 20, 16]
        var bandStart = [Int]()
        var acc = 0
        for h in heights { bandStart.append(acc); acc += h }
        let height = acc, width = 64
        func band(_ y: Int) -> Int {
            for (index, start) in bandStart.enumerated().reversed() where y >= start { return index }
            return 0
        }

        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: width, height: height) { y, _ in
                Self.vec([band(y): 0.8, (band(y) + 1) % 7: 0.2])
            },
            labelMap: Self.labels(width: width, height: height) { y, _ in band(y) },
            palette: Self.palette
        )
        #expect(evidence.keys.sorted()
                == ["solid_a", "solid_b", "solid_c", "solid_d", "solid_e"])
    }

    @Test("A food under the 64-sample floor earns no entry")
    func samplingFloorYieldsHonestAbsence() {
        // solid_b occupies rows 0..<4 of a 32-wide frame: 1 sampled row × 8
        // columns = 8 sampled pixels, under the floor. solid_a takes the rest.
        let width = 32, height = 128
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: width, height: height) { _, _ in
                Self.vec([Self.solidA: 0.5, Self.solidB: 0.3, Self.solidC: 0.2])
            },
            labelMap: Self.labels(width: width, height: height) { y, _ in
                y < 4 ? Self.solidB : Self.solidA
            },
            palette: Self.palette
        )
        #expect(evidence.keys.sorted() == ["solid_a"])
    }

    @Test("A food entirely off the stride grid yields no entry")
    func strideAnchoringExcludesOffGridFood() {
        // solid_b owns every pixel whose row is not a multiple of 4 — three
        // quarters of the frame, and not one sampled pixel.
        let width = 64, height = 64
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: width, height: height) { _, _ in
                Self.vec([Self.solidA: 0.5, Self.solidB: 0.3, Self.solidC: 0.2])
            },
            labelMap: Self.labels(width: width, height: height) { y, _ in
                y % 4 == 0 ? Self.solidA : Self.solidB
            },
            palette: Self.palette
        )
        #expect(evidence.keys.sorted() == ["solid_a"])
    }

    @Test("Every pixel background yields no evidence at all")
    func backgroundOnlyPlateYieldsNothing() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.background: 0.9, Self.solidA: 0.1])
            },
            labelMap: Self.labels(width: 64, height: 64) { _, _ in Self.background },
            palette: Self.palette
        )
        #expect(evidence.isEmpty)
    }

    // MARK: - determinism

    @Test("Two runs over the same input are equal")
    func deterministic() {
        let probs = Self.tensor(width: 96, height: 96) { y, x in
            Self.vec([
                Self.solidA: Float((y &* 7 &+ x) % 13) / 13,
                Self.solidB: Float((x &* 5 &+ y) % 11) / 11,
                Self.solidC: Float((y &+ x) % 7) / 7,
                Self.background: 0.05,
            ])
        }
        let map = Self.labels(width: 96, height: 96) { y, _ in
            y < 48 ? Self.solidA : Self.solidB
        }
        let first = CandidateEvidence.compute(
            probabilities: probs, labelMap: map, palette: Self.palette)
        let second = CandidateEvidence.compute(
            probabilities: probs, labelMap: map, palette: Self.palette)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    // MARK: - invariants over arbitrary tensors

    @Test("Seeded random tensors always obey the set invariants")
    func randomisedInvariants() {
        // Deterministic 64-bit LCG — a seeded generator without a new dependency.
        var state: UInt64 = 0x5DEE_CE66_D_ACE1
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }

        for _ in 0..<8 {
            let width = 64, height = 64
            let probs = Self.tensor(width: width, height: height) { _, _ in
                (0..<Self.classes).map { _ in next() }
            }
            let map = Self.labels(width: width, height: height) { _, _ in
                Int(next() * Float(Self.classes)) % Self.classes
            }
            let evidence = CandidateEvidence.compute(
                probabilities: probs, labelMap: map, palette: Self.palette)

            #expect(evidence.count <= CandidateEvidence.maxSets)
            for (key, candidates) in evidence {
                #expect(candidates.count <= CandidateEvidence.maxCandidates)
                #expect(!candidates.contains { $0.className == key })
                #expect(Set(candidates.map(\.className)).count == candidates.count)
                let magnitudes = candidates.map(\.meanPermille)
                #expect(magnitudes == magnitudes.sorted(by: >))
                #expect(magnitudes.allSatisfy { $0 <= 1000 })
                // No sentinel and no cross-phase class ever reaches a slot.
                let ownIsSolid = Self.palette.foodClasses.contains(key)
                for candidate in candidates {
                    #expect(ownIsSolid
                            ? Self.palette.foodClasses.contains(candidate.className)
                            : Self.palette.liquidClasses.contains(candidate.className))
                }
            }
        }
    }

    // MARK: - shape disagreement

    @Test("Mismatched label-map dimensions yield an empty result, not an error")
    func shapeMismatchYieldsEmpty() {
        let evidence = CandidateEvidence.compute(
            probabilities: Self.tensor(width: 64, height: 64) { _, _ in
                Self.vec([Self.solidA: 0.8, Self.solidB: 0.2])
            },
            labelMap: Self.labels(width: 32, height: 32) { _, _ in Self.solidA },
            palette: Self.palette
        )
        #expect(evidence.isEmpty)
    }
}
