#if HARNESS_ENABLED
import Foundation
import Testing
@testable import HarnessCore

// Property tests for the MixtureBetaCalibrator BVLS solver (spec task 13,
// design §MixtureBetaCalibrator, Decisions 11/14).
//
// Plates are generated from known β and ρ: V_p = Σ_c m_pc/(ρ_c·β_c) plus
// bounded multiplicative noise. The solver fits x_c = 1/β_c bounded to
// [1/1.5, 1/0.05] INSIDE the solve (Decision 11 refinement — a post-hoc clamp
// would re-leak a clamped class's excess volume into co-occurring classes).
@Suite("MixtureBetaCalibrator")
struct MixtureBetaCalibratorTests {

    // Densities (bulk, as the DB carries them).
    static let rho: [String: Float] = [
        "white_rice": 0.73, "chicken": 1.05, "broccoli": 0.35, "potato_boiled": 0.59,
        "pasta": 0.58, "soup": 1.0,
    ]

    // Deterministic plate generator. Each plate mixes 2–3 of the given classes
    // with varying masses; V = Σ m/(ρβ) · (1 + noise), |noise| ≤ noiseAmp.
    static func makePlates(
        classes: [String],
        betaTrue: [String: Float],
        count: Int,
        seed: UInt64,
        noiseAmp: Float = 0.02
    ) -> [MixtureBetaCalibrator.PlateObservation] {
        var rng = SplitMix64(seed: seed)
        func unit() -> Float { Float(rng.next() % 10_000) / 10_000 }
        return (0..<count).map { i in
            // Rotate through class pairs/triples for mixing diversity.
            let n = 2 + Int(rng.next() % 2)
            let start = Int(rng.next() % UInt64(classes.count))
            let chosen = (0..<n).map { classes[(start + $0) % classes.count] }
            var masses: [String: Float] = [:]
            for c in chosen {
                masses[c] = 40 + unit() * 160          // 40–200 g
            }
            var v: Float = 0
            for (c, m) in masses {
                v += m / (rho[c]! * betaTrue[c]!)
            }
            let noise = 1 + (unit() * 2 - 1) * noiseAmp
            return MixtureBetaCalibrator.PlateObservation(
                fixtureID: "dish_\(i)",
                totalHullVolumeCm3: v * noise,
                massByClassG: masses
            )
        }
    }

    // MARK: - Recovery

    @Test("Recovers known β per class within tolerance from noisy mixtures")
    func recoversKnownBetas() {
        let betaTrue: [String: Float] = [
            "white_rice": 0.80, "chicken": 0.95, "broccoli": 0.70, "potato_boiled": 0.85,
        ]
        let plates = Self.makePlates(classes: Array(betaTrue.keys).sorted(),
                                     betaTrue: betaTrue, count: 240, seed: 1)
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)

        for (c, expected) in betaTrue {
            let got = try! #require(result.betaPerClass[c])
            #expect(abs(got - expected) / expected <= 0.03,
                    "\(c): β \(got) not within 3% of \(expected)")
            #expect(result.identifiablePerClass[c] == true)
            #expect(result.effectiveSamplePerClass[c, default: 0] >= MixtureBetaCalibrator.effectiveSampleMin)
        }
        #expect(result.clampedClasses.isEmpty)
        #expect(result.excludedPlates.isEmpty)
        #expect(result.fixedOffsetClasses.isEmpty)
        #expect(result.conditionNumber.isFinite && result.conditionNumber > 0,
                "condition number is a Req 5.5 diagnostic and must be emitted")
    }

    // MARK: - Bounds inside the solve (Decision 11 refinement)

    @Test("A class whose true β exceeds the ceiling rests on the bound and is marked clamped")
    func boundRestingClassIsClamped() {
        // true β = 2.0 → x = 0.5, below the lower x bound 1/1.5. The solve must
        // hold the class at β = 1.5 (bound), flag it clamped (Req 5.6), and NOT
        // leak its excess volume into the co-occurring class.
        let betaTrue: [String: Float] = ["white_rice": 2.0, "chicken": 0.95,
                                         "broccoli": 0.70, "potato_boiled": 0.85]
        let plates = Self.makePlates(classes: Array(betaTrue.keys).sorted(),
                                     betaTrue: betaTrue, count: 240, seed: 2)
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)

        #expect(result.clampedClasses.contains("white_rice"))
        #expect(abs((result.betaPerClass["white_rice"] ?? 0) - 1.5) <= 1e-3,
                "clamped β must rest on the 1.5 ceiling")
        // Co-occurring classes stay near truth — the bound is enforced inside
        // the joint solve, so the least-squares re-attributes the excess.
        for c in ["chicken", "broccoli", "potato_boiled"] {
            let got = result.betaPerClass[c] ?? 0
            #expect(abs(got - betaTrue[c]!) / betaTrue[c]! <= 0.10,
                    "\(c): β \(got) contaminated by the clamped class (true \(betaTrue[c]!))")
        }
    }

    @Test("β bounds are [0.05, 1.5] at both ends")
    func bothBoundsEnforced() {
        // true β = 0.02 → x = 50, above the upper x bound 20 → clamped at 0.05.
        let betaTrue: [String: Float] = ["white_rice": 0.02, "chicken": 1.0,
                                         "broccoli": 0.7, "potato_boiled": 0.85]
        let plates = Self.makePlates(classes: Array(betaTrue.keys).sorted(),
                                     betaTrue: betaTrue, count: 240, seed: 3)
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)
        #expect(abs((result.betaPerClass["white_rice"] ?? 0) - 0.05) <= 1e-4)
        #expect(result.clampedClasses.contains("white_rice"))
    }

    // MARK: - Identifiability (Req 4.5/5.4)

    @Test("A deliberately collinear class pair yields large SE and identifiable = false")
    func collinearClassesUnidentifiable() {
        // pasta mass is always exactly 2× broccoli mass → their design columns
        // are collinear; neither is individually identifiable, and the
        // condition number surfaces it (Req 5.5).
        let betaTrue: [String: Float] = ["white_rice": 0.8, "chicken": 0.95,
                                         "broccoli": 0.7, "pasta": 0.9]
        var plates = Self.makePlates(classes: ["white_rice", "chicken"],
                                     betaTrue: betaTrue, count: 120, seed: 4)
        var rng = SplitMix64(seed: 40)
        for i in 0..<120 {
            let mB = 40 + Float(rng.next() % 10_000) / 10_000 * 100
            let masses = ["broccoli": mB, "pasta": 2 * mB,
                          "white_rice": 60 + Float(rng.next() % 10_000) / 10_000 * 60]
            var v: Float = 0
            for (c, m) in masses { v += m / (Self.rho[c]! * betaTrue[c]!) }
            plates.append(.init(fixtureID: "dish_col_\(i)",
                                totalHullVolumeCm3: v,
                                massByClassG: masses))
        }
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)

        #expect(result.identifiablePerClass["broccoli"] == false)
        #expect(result.identifiablePerClass["pasta"] == false)
        let seB = result.standardErrorPerClass["broccoli"] ?? 0
        #expect(!seB.isFinite || seB / (result.betaPerClass["broccoli"] ?? 1)
                    > MixtureBetaCalibrator.relativeSEBound)
        // Healthy classes stay identifiable.
        #expect(result.identifiablePerClass["white_rice"] == true)
        #expect(result.identifiablePerClass["chicken"] == true)
    }

    // MARK: - Fixed offset (Req 4.6)

    @Test("An under-sampled class is held at β = 1 as a fixed RHS offset, not misattributed")
    func underSampledClassBecomesFixedOffset() {
        let betaTrue: [String: Float] = ["white_rice": 0.8, "chicken": 0.95,
                                         "broccoli": 0.7, "potato_boiled": 1.0]
        // potato appears on only 5 plates (< 30 effective) — generated at
        // β = 1.0 so the fixed offset introduces no bias into the others.
        var plates = Self.makePlates(classes: ["white_rice", "chicken", "broccoli"],
                                     betaTrue: betaTrue, count: 240, seed: 5)
        var rng = SplitMix64(seed: 50)
        for i in 0..<5 {
            let masses = ["potato_boiled": Float(150),
                          "white_rice": 60 + Float(rng.next() % 10_000) / 10_000 * 60]
            var v: Float = 0
            for (c, m) in masses { v += m / (Self.rho[c]! * betaTrue[c]!) }
            plates.append(.init(fixtureID: "dish_pot_\(i)",
                                totalHullVolumeCm3: v, massByClassG: masses))
        }
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)

        #expect(result.fixedOffsetClasses.contains("potato_boiled"))
        #expect(result.betaPerClass["potato_boiled"] == nil,
                "a fixed-offset class receives no fitted β")
        #expect(result.effectiveSamplePerClass["potato_boiled"] == 5)
        for c in ["white_rice", "chicken", "broccoli"] {
            let got = result.betaPerClass[c] ?? 0
            #expect(abs(got - betaTrue[c]!) / betaTrue[c]! <= 0.03,
                    "\(c): fixed offset misattributed volume (β \(got), true \(betaTrue[c]!))")
        }
    }

    @Test("Effective sample counts plates at mass fraction ≥ τ_eff = 0.15, not raw appearances")
    func effectiveSampleUsesMassFraction() {
        let betaTrue: [String: Float] = ["white_rice": 0.8, "chicken": 0.95]
        var plates: [MixtureBetaCalibrator.PlateObservation] = []
        var rng = SplitMix64(seed: 6)
        func unit() -> Float { Float(rng.next() % 10_000) / 10_000 }
        // 40 plates where broccoli is 10% of plate mass (< τ_eff), 5 where it
        // is 30% (≥ τ_eff): effective sample must be 5.
        for i in 0..<45 {
            let frac: Float = i < 40 ? 0.10 : 0.30
            let total = 200 + unit() * 100
            let masses = ["broccoli": total * frac,
                          "white_rice": total * (1 - frac) * 0.6,
                          "chicken": total * (1 - frac) * 0.4]
            var v: Float = 0
            for (c, m) in masses {
                v += m / (Self.rho[c]! * (betaTrue[c] ?? 0.7))
            }
            plates.append(.init(fixtureID: "dish_ef_\(i)",
                                totalHullVolumeCm3: v, massByClassG: masses))
        }
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)
        #expect(result.effectiveSamplePerClass["broccoli"] == 5)
    }

    // MARK: - Plate guards (Req 4.3 / 4.7)

    @Test("Stacking guard: a plate with hull < κ·Σm/ρ is excluded and listed")
    func stackingGuardExcludesPlate() {
        let betaTrue: [String: Float] = ["white_rice": 0.8, "chicken": 0.95,
                                         "broccoli": 0.7, "potato_boiled": 0.85]
        var plates = Self.makePlates(classes: Array(betaTrue.keys).sorted(),
                                     betaTrue: betaTrue, count: 240, seed: 7)
        // Stacked plate: measured hull is 30% of the expected minimum Σm/ρ.
        let masses: [String: Float] = ["white_rice": 100, "chicken": 100]
        let expectedMin = masses.reduce(Float(0)) { $0 + $1.value / Self.rho[$1.key]! }
        plates.append(.init(fixtureID: "dish_stacked",
                            totalHullVolumeCm3: expectedMin * 0.3,
                            massByClassG: masses))
        let result = MixtureBetaCalibrator.fit(plates, densityByClass: Self.rho)

        #expect(result.excludedPlates.contains("dish_stacked"))
        for (c, expected) in betaTrue {
            let got = result.betaPerClass[c] ?? 0
            #expect(abs(got - expected) / expected <= 0.03)
        }
    }

    @Test("Liquid-bearing plate (liquid-mapped mass ≥ 0.05) is excluded entirely and counted")
    func liquidBearingPlateExcluded() {
        let betaTrue: [String: Float] = ["white_rice": 0.8, "chicken": 0.95,
                                         "broccoli": 0.7, "potato_boiled": 0.85]
        var plates = Self.makePlates(classes: Array(betaTrue.keys).sorted(),
                                     betaTrue: betaTrue, count: 240, seed: 8)
        // Soup is 10% of plate mass — vessel-plus-liquid volume would be
        // misattributed to the solids' β (Req 4.7), so the whole plate goes.
        plates.append(.init(fixtureID: "dish_soup",
                            totalHullVolumeCm3: 400,
                            massByClassG: ["soup": 30, "white_rice": 170, "chicken": 100]))
        let result = MixtureBetaCalibrator.fit(
            plates, densityByClass: Self.rho, liquidClasses: ["soup"])

        #expect(result.liquidExcludedPlates.contains("dish_soup"))
        #expect(result.betaPerClass["soup"] == nil,
                "liquid classes never enter the β fit (Decision 9)")
        for (c, expected) in betaTrue {
            let got = result.betaPerClass[c] ?? 0
            #expect(abs(got - expected) / expected <= 0.03)
        }
    }

    @Test("A liquid-mapped mass below the significant fraction keeps the plate, minus the liquid class")
    func insignificantLiquidKeepsPlate() {
        // 2% soup — below the 5% liquid-significant fraction. The plate stays,
        // but soup itself still never receives a β.
        let plates = [
            MixtureBetaCalibrator.PlateObservation(
                fixtureID: "dish_trace_soup",
                totalHullVolumeCm3: 300,
                massByClassG: ["soup": 4, "white_rice": 100, "chicken": 96]),
        ]
        let result = MixtureBetaCalibrator.fit(
            plates, densityByClass: Self.rho, liquidClasses: ["soup"])
        #expect(!result.liquidExcludedPlates.contains("dish_trace_soup"))
        #expect(result.betaPerClass["soup"] == nil)
    }
}
#endif
