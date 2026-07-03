import Foods
import PortableContracts
import XCTest
@testable import Macros

// Tests for Macros.compute per design §3.8 / Req 12 / task 37.
//
// Fixed input vectors used throughout (per Req 13.6 / design §3.8 rationale):
//   white_rice:  density=1.05 g/cm³, carbs_mono=32.0 g/100g, protein=2.7, fat=0.3, fibre=0.1, energy=580, beta=0.9 calibrated
//   chicken:     density=0.90 g/cm³, carbs_mono=0.0  g/100g, protein=31.0, fat=3.6, fibre=0.0, energy=736, beta=1.0 uncalibrated_unity

final class MacrosTests: XCTestCase {

    // Stub database with fixed entries, no SQLite required.
    private let db = StubFoodDatabase()

    // MARK: - T37.1 Per-class mass: m_c = V_c · ρ_c (Req 12.1)

    func testPerClassMassFormula() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        // m = 100 cm³ × 1.05 g/cm³ = 105.0 g
        let entry = try! XCTUnwrap(result.perClass["white_rice"])
        XCTAssertEqual(entry.massG, 105.0, accuracy: 1e-3)
    }

    // MARK: - T37.2 Per-class carbs: C_c = m_c · κ_c / 100 (Req 12.2)

    func testPerClassCarbsFormula() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        // C = 105.0 g × 32.0 / 100 = 33.6 g
        let entry = try! XCTUnwrap(result.perClass["white_rice"])
        XCTAssertEqual(entry.carbsG, 33.6, accuracy: 1e-3)
    }

    // MARK: - T37.3 Meal total carbs: C_meal = Σ C_c (Req 12.3)

    func testMealTotalIsSum() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0, "chicken": 80.0],
            database: db,
            edition: "CoFID 2024"
        )
        // rice: 100 × 1.05 × 32 / 100 = 33.6
        // chicken: 80 × 0.90 × 0.0 / 100 = 0.0
        // total = 33.6
        XCTAssertEqual(result.totalCarbsG, 33.6, accuracy: 1e-3)
    }

    // MARK: - T37.4 totalCarbsG persisted at full precision (Req 12.5)

    func testTotalCarbsPersistedFullPrecision() {
        // Use an odd volume that produces a fractional carb value.
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 73.5],
            database: db,
            edition: "CoFID 2024"
        )
        // m = 73.5 × 1.05 = 77.175 g
        // C = 77.175 × 32.0 / 100 = 24.696 g  (not rounded to integer)
        XCTAssertEqual(result.totalCarbsG, 24.696, accuracy: 1e-2)
    }

    // MARK: - T37.5 Clinical macros computed but not in perClass (Req 12.6)

    func testClinicalMacrosPresent() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        // energy = 105.0 × 580 / 100 = 609.0 kJ
        XCTAssertEqual(result.clinicalTotals.energyKJ, 609.0, accuracy: 0.5)
        // protein = 105.0 × 2.7 / 100 = 2.835 g
        XCTAssertEqual(result.clinicalTotals.proteinG, 2.835, accuracy: 1e-3)
        // fat = 105.0 × 0.3 / 100 = 0.315 g
        XCTAssertEqual(result.clinicalTotals.fatG, 0.315, accuracy: 1e-3)
        // fibre = 105.0 × 0.1 / 100 = 0.105 g
        XCTAssertEqual(result.clinicalTotals.fibreG, 0.105, accuracy: 1e-3)
    }

    // MARK: - T37.6 Per-class breakdown carries provenance fields (Req 12.7)

    func testPerClassBreakdownCarriesProvenance() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        let entry = try! XCTUnwrap(result.perClass["white_rice"])
        XCTAssertFalse(entry.densitySource.isEmpty)
        XCTAssertFalse(entry.coefficientSource.isEmpty)
        XCTAssertEqual(entry.betaUsed, 0.9, accuracy: 1e-5)
        XCTAssertEqual(entry.betaStatus, .calibrated)
    }

    // MARK: - T37.7 volumeCm3 stored is the β-corrected input volume

    func testVolumeStoredIsInputVolume() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 123.4],
            database: db,
            edition: "CoFID 2024"
        )
        let entry = try! XCTUnwrap(result.perClass["white_rice"])
        XCTAssertEqual(entry.volumeCm3, 123.4, accuracy: 1e-3)
    }

    // MARK: - T37.8 Zero-carb class contributes 0 to total (chicken has 0 carbs)

    func testZeroCarbClassContributesZero() {
        let result = Macros.compute(
            perClassVolumesCm3: ["chicken": 200.0],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertEqual(result.totalCarbsG, 0.0, accuracy: 1e-6)
        let entry = try! XCTUnwrap(result.perClass["chicken"])
        XCTAssertEqual(entry.carbsG, 0.0, accuracy: 1e-6)
        // But mass is non-zero
        XCTAssertEqual(entry.massG, 200.0 * 0.9, accuracy: 1e-3)
    }

    // MARK: - T37.9 Unknown class (not in DB) is silently skipped

    func testUnknownClassSkipped() {
        let result = Macros.compute(
            perClassVolumesCm3: ["nonexistent_class": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertEqual(result.totalCarbsG, 0.0)
        XCTAssertTrue(result.perClass.isEmpty)
    }

    // MARK: - T37.10 Empty volumes → zero result

    func testEmptyVolumes() {
        let result = Macros.compute(
            perClassVolumesCm3: [:],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertEqual(result.totalCarbsG, 0.0)
        XCTAssertTrue(result.perClass.isEmpty)
        XCTAssertEqual(result.clinicalTotals, ClinicalMacros.zero)
    }

    // MARK: - nutrition5k-calibration Req 10.1: per-class protein/fat from the
    //          same β-corrected mass × DB fraction — no separate fit

    func testPerClassProteinFatFormula() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        // m = 105.0 g; protein = 105.0 × 2.7 / 100 = 2.835; fat = 105.0 × 0.3 / 100 = 0.315
        let entry = try! XCTUnwrap(result.perClass["white_rice"])
        XCTAssertEqual(entry.proteinG, 2.835, accuracy: 1e-3)
        XCTAssertEqual(entry.fatG, 0.315, accuracy: 1e-3)
    }

    // MARK: - Req 10.2: carbs stay primary, protein/fat are additive — the
    //          per-class fields sum to the existing clinical totals and leave
    //          totalCarbsG untouched

    func testProteinFatAdditiveAgainstClinicalTotals() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0, "chicken": 80.0],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertEqual(result.totalCarbsG, 33.6, accuracy: 1e-3)
        let proteinSum = result.perClass.values.reduce(Float(0)) { $0 + $1.proteinG }
        let fatSum     = result.perClass.values.reduce(Float(0)) { $0 + $1.fatG }
        XCTAssertEqual(proteinSum, result.clinicalTotals.proteinG, accuracy: 1e-3)
        XCTAssertEqual(fatSum,     result.clinicalTotals.fatG,     accuracy: 1e-3)
    }

    // MARK: - Req 8.1 banner inputs: deviceVerified and isLiquid copied onto
    //          each PerClassMacros

    func testDeviceVerifiedCopiedFromEntry() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0, "chicken": 80.0],
            database: db,
            edition: "CoFID 2024"
        )
        // Stub injects deviceVerified = true for white_rice only.
        XCTAssertTrue(try! XCTUnwrap(result.perClass["white_rice"]).deviceVerified)
        XCTAssertFalse(try! XCTUnwrap(result.perClass["chicken"]).deviceVerified)
    }

    func testIsLiquidMarkedFromLiquidClassIds() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0, "milk": 200.0],
            database: db,
            edition: "CoFID 2024",
            liquidClassIds: ["milk"]
        )
        XCTAssertTrue(try! XCTUnwrap(result.perClass["milk"]).isLiquid)
        XCTAssertFalse(try! XCTUnwrap(result.perClass["white_rice"]).isLiquid)
    }

    // MARK: - Req 8.2 / 7.3: liquidOverEstimate raised by a depth-integrated
    //          liquid entry or threaded through from the vessel path

    func testLiquidOverEstimateFalseForSolidsOnly() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertFalse(result.liquidOverEstimate)
    }

    func testLiquidOverEstimateRaisedByLiquidEntry() {
        let result = Macros.compute(
            perClassVolumesCm3: ["milk": 200.0],
            database: db,
            edition: "CoFID 2024",
            liquidClassIds: ["milk"]
        )
        XCTAssertTrue(result.liquidOverEstimate)
    }

    func testLiquidOverEstimateThreadedFromVesselPath() {
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0],
            database: db,
            edition: "CoFID 2024",
            liquidOverEstimate: true
        )
        XCTAssertTrue(result.liquidOverEstimate)
    }

    // MARK: - T37.11 Multi-class meal sums all per-class carbs

    func testMultiClassMealSumsCorrectly() {
        // white_rice: 100 cm³ → 33.6 g carbs
        // chicken: 100 cm³ → 0.0 g carbs
        // total: 33.6
        let result = Macros.compute(
            perClassVolumesCm3: ["white_rice": 100.0, "chicken": 100.0],
            database: db,
            edition: "CoFID 2024"
        )
        XCTAssertEqual(result.totalCarbsG, 33.6, accuracy: 1e-3)
        XCTAssertEqual(result.perClass.count, 2)
    }
}

// MARK: - Stub

// In-memory stub for deterministic test vectors.
private final class StubFoodDatabase: FoodDatabase, @unchecked Sendable {
    let version = "CoFID 2024"

    private let entries: [String: FoodEntry] = [
        // deviceVerified injected true — otherwise unreachable within this spec
        // (nutrition5k-calibration Req 8.1 flag injection).
        "white_rice": FoodEntry(
            classId: "white_rice", name: "White rice",
            densityGPerCm3: 1.05, energyKJPer100g: 580.0,
            carbsMonoG: 32.0, proteinG: 2.7, fatG: 0.3, fibreG: 0.1,
            beta: 0.9, calibrationStatus: .calibrated,
            densitySource: "CoFID 2024", compositionSource: "CoFID 2024",
            betaProvenance: "n5k_single_dominant", deviceVerified: true
        ),
        "chicken": FoodEntry(
            classId: "chicken", name: "Chicken breast",
            densityGPerCm3: 0.9, energyKJPer100g: 736.0,
            carbsMonoG: 0.0, proteinG: 31.0, fatG: 3.6, fibreG: 0.0,
            beta: 1.0, calibrationStatus: .uncalibratedUnity,
            densitySource: "FAO_DENS", compositionSource: "CoFID 2024"
        ),
        // Coarse liquid class row (Req 7.1) — β unity, DB-sourced values.
        "milk": FoodEntry(
            classId: "milk", name: "Milk",
            densityGPerCm3: 1.03, energyKJPer100g: 270.0,
            carbsMonoG: 4.7, proteinG: 3.4, fatG: 3.6, fibreG: 0.0,
            beta: 1.0, calibrationStatus: .uncalibratedUnity,
            densitySource: "CoFID 2024", compositionSource: "CoFID 2024"
        )
    ]

    func entry(for classId: String) -> FoodEntry? { entries[classId] }

    func entry(for classId: String, edition: String) -> FoodEntry? { entries[classId] }

    func availableEditions() -> [String] { ["CoFID 2024"] }
}
