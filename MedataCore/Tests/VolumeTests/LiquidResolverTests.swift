import Foundation
import Testing
@testable import Volume

// LiquidResolver (Req 7.4/7.5/7.6, Decisions 12/19/24).
//
// The vessel canonical mapping is a PURE function
// (vessel_label, sub_class, region) → liquid_servings.serving_ml × DB carb
// density — unit-testable from label inputs, independent of the deferred
// vessel/sub-class recognition (Req 7.7). Fixture tables mirror the
// generate.py liquid_servings / liquid_subclasses rows.
//
// Precedence (Req 7.6): recognised standard vessel → canonical-volume
// estimate; else recognised liquid class with usable surface depth →
// depth-integrated estimate; else exclude + flag — never an unbacked carb
// number. BOTH estimate paths raise liquidOverEstimate (Decision 19).

@Suite("LiquidResolver")
struct LiquidResolverTests {

    // Compositions mirror the CoFID rows in generate.py FOOD_DATA.
    static let coarse: [String: LiquidResolver.Composition] = [
        "water": .init(densityGPerCm3: 1.00, carbsMonoPer100g: 0.0),
        "milk": .init(densityGPerCm3: 1.03, carbsMonoPer100g: 4.8),
        "fruit_juice": .init(densityGPerCm3: 1.04, carbsMonoPer100g: 9.1),
        "beer": .init(densityGPerCm3: 1.01, carbsMonoPer100g: 2.3),
        "wine": .init(densityGPerCm3: 0.99, carbsMonoPer100g: 2.6),
    ]

    // liquid_subclasses: beer → lager/stout. Deliberately no assumed
    // lager<stout ordering — the values come from the DB rows alone.
    static let subclasses: [LiquidResolver.SubclassKey: LiquidResolver.Composition] = [
        .init(classId: "beer", subClass: "lager"):
            .init(densityGPerCm3: 1.01, carbsMonoPer100g: 2.2),
        .init(classId: "beer", subClass: "stout"):
            .init(densityGPerCm3: 1.01, carbsMonoPer100g: 4.2),
    ]

    // liquid_servings rows (class, region, vessel) → mL.
    static let servings: [LiquidResolver.ServingKey: Float] = [
        .init(classId: "beer", region: .uk, vessel: .pint): 568,
        .init(classId: "beer", region: .uk, vessel: .halfPint): 284,
        .init(classId: "beer", region: .uk, vessel: .can440): 440,
        .init(classId: "beer", region: .uk, vessel: .can330): 330,
        .init(classId: "beer", region: .us, vessel: .pint): 473,
        .init(classId: "wine", region: .uk, vessel: .glass): 175,
        .init(classId: "wine", region: .us, vessel: .glass): 148,
        .init(classId: "milk", region: .uk, vessel: .glass): 200,
        .init(classId: "fruit_juice", region: .uk, vessel: .glass): 150,
    ]

    let tables = LiquidResolver.Tables(
        servingMl: servings, coarse: coarse, subclasses: subclasses)

    private func expectedCarbsG(servingMl: Float,
                                _ c: LiquidResolver.Composition) -> Float {
        servingMl * c.densityGPerCm3 * c.carbsMonoPer100g / 100
    }

    // --- canonical vessel mapping (Req 7.4) ---

    @Test("canonical mapping = serving_ml × density × carb fraction",
          arguments: [
            ("beer", LiquidResolver.Region.uk, LiquidResolver.Vessel.pint, Float(568)),
            ("beer", .uk, .halfPint, 284),
            ("beer", .uk, .can440, 440),
            ("beer", .uk, .can330, 330),
            ("beer", .us, .pint, 473),
            ("wine", .uk, .glass, 175),
            ("wine", .us, .glass, 148),
            ("milk", .uk, .glass, 200),
            ("fruit_juice", .uk, .glass, 150),
          ] as [(String, LiquidResolver.Region, LiquidResolver.Vessel, Float)])
    func canonicalMapping(classId: String, region: LiquidResolver.Region,
                          vessel: LiquidResolver.Vessel, servingMl: Float) throws {
        let carbs = try LiquidResolver.canonicalCarbsG(
            classId: classId, subClass: nil, vessel: vessel, region: region,
            tables: tables)
        let expected = expectedCarbsG(servingMl: servingMl,
                                      Self.coarse[classId]!)
        #expect(abs(carbs - expected) < 0.001)
    }

    @Test("sub-class densities come from the DB rows",
          arguments: [("lager", Float(2.2)), ("stout", 4.2)])
    func subClassApplied(subClass: String, carbs100: Float) throws {
        let carbs = try LiquidResolver.canonicalCarbsG(
            classId: "beer", subClass: subClass, vessel: .pint, region: .uk,
            tables: tables)
        let expected = expectedCarbsG(
            servingMl: 568, .init(densityGPerCm3: 1.01, carbsMonoPer100g: carbs100))
        #expect(abs(carbs - expected) < 0.001)
    }

    @Test("uncertain or unknown sub-class falls back to the coarse row")
    func subClassFallback() throws {
        let generic = try LiquidResolver.canonicalCarbsG(
            classId: "beer", subClass: nil, vessel: .pint, region: .uk,
            tables: tables)
        // An unrecognised sub-class is best-effort: generic coarse row, not
        // an error and not a guess (Req 7.5).
        let unknown = try LiquidResolver.canonicalCarbsG(
            classId: "beer", subClass: "ipa", vessel: .pint, region: .uk,
            tables: tables)
        let expected = expectedCarbsG(servingMl: 568, Self.coarse["beer"]!)
        #expect(abs(generic - expected) < 0.001)
        #expect(unknown == generic)
    }

    @Test("a serving-table miss is a hard error, never a silent zero")
    func servingLookupMiss() {
        // The vocabulary is closed: water has no pint row.
        #expect(throws: LiquidResolver.ResolverError.self) {
            _ = try LiquidResolver.canonicalCarbsG(
                classId: "water", subClass: nil, vessel: .pint, region: .uk,
                tables: tables)
        }
    }

    @Test("an unknown liquid class is a hard error")
    func unknownClass() {
        #expect(throws: LiquidResolver.ResolverError.self) {
            _ = try LiquidResolver.canonicalCarbsG(
                classId: "petrol", subClass: nil, vessel: .glass, region: .uk,
                tables: tables)
        }
    }

    // --- precedence (Req 7.6) ---

    @Test("recognised vessel wins over usable surface depth")
    func vesselWins() throws {
        let resolution = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "beer", vessel: .pint,
                                     subClass: nil, surfaceVolumeCm3: 100),
            region: .uk, tables: tables)
        guard case .estimate(let estimate) = resolution else {
            Issue.record("expected an estimate, got \(resolution)")
            return
        }
        #expect(estimate.path == .canonicalVessel)
        let expected = expectedCarbsG(servingMl: 568, Self.coarse["beer"]!)
        #expect(abs(estimate.carbsG - expected) < 0.001)
    }

    @Test("no vessel + usable surface depth → depth-integrated estimate")
    func depthIntegrated() throws {
        let resolution = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "fruit_juice", vessel: nil,
                                     subClass: nil, surfaceVolumeCm3: 250),
            region: .uk, tables: tables)
        guard case .estimate(let estimate) = resolution else {
            Issue.record("expected an estimate, got \(resolution)")
            return
        }
        #expect(estimate.path == .depthIntegrated)
        // carb = volume × density × carb fraction (Req 7.3).
        let expected = expectedCarbsG(servingMl: 250, Self.coarse["fruit_juice"]!)
        #expect(abs(estimate.carbsG - expected) < 0.001)
    }

    @Test("no vessel and no usable depth → exclude + flag, never a carb number")
    func excludedAndFlagged() throws {
        let resolution = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "water", vessel: nil,
                                     subClass: nil, surfaceVolumeCm3: nil),
            region: .uk, tables: tables)
        #expect(resolution == .excludedFlagged)
    }

    // --- over-estimate flag (Decision 19) and region default ---

    @Test("both estimate paths raise liquidOverEstimate")
    func bothPathsRaiseFlag() throws {
        let vessel = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "beer", vessel: .pint,
                                     subClass: nil, surfaceVolumeCm3: nil),
            region: .uk, tables: tables)
        let depth = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "beer", vessel: nil,
                                     subClass: nil, surfaceVolumeCm3: 300),
            region: .uk, tables: tables)
        for resolution in [vessel, depth] {
            guard case .estimate(let estimate) = resolution else {
                Issue.record("expected an estimate, got \(resolution)")
                continue
            }
            #expect(estimate.liquidOverEstimate)
        }
    }

    @Test("result-level flag is the OR over resolutions")
    func resultLevelFlag() throws {
        let estimate = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "beer", vessel: .pint,
                                     subClass: nil, surfaceVolumeCm3: nil),
            region: .uk, tables: tables)
        #expect(LiquidResolver.liquidOverEstimate([estimate]))
        #expect(!LiquidResolver.liquidOverEstimate([]))
        #expect(LiquidResolver.liquidOverEstimate([.excludedFlagged]) == false)
    }

    @Test("region defaults to UK (Settings value, default UK)")
    func regionDefaultsToUK() throws {
        let resolution = try LiquidResolver.resolve(
            LiquidResolver.Detection(classId: "beer", vessel: .pint,
                                     subClass: nil, surfaceVolumeCm3: nil),
            tables: tables)
        guard case .estimate(let estimate) = resolution else {
            Issue.record("expected an estimate, got \(resolution)")
            return
        }
        // UK pint 568, not US 473.
        let expected = expectedCarbsG(servingMl: 568, Self.coarse["beer"]!)
        #expect(abs(estimate.carbsG - expected) < 0.001)
    }
}
