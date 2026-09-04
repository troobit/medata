import Foods
import PortableContracts
import Volume
import XCTest
@testable import Macros

// β re-derivation equality per specs/ui/meal-review design "Testing
// Strategy" (task 9): a relabel derived through Macros.reDerive must equal
// Macros.compute over the target class's own β-corrected volume — Decision
// 11's stated invariant. A deterministic equality, not a property test: it
// catches a factor inversion.
final class MacroReDerivationTests: XCTestCase {

    private let db = ReDerivationStubDatabase()
    private let edition = "CoFID 2024"

    // MARK: - Relabel equality (Req 3.5, Decisions 11 and 17)

    func testRelabelEqualsDirectComputeOnTargetClass() {
        // Stored prediction: white_rice from a pre-β volume of 120 cm³.
        // The user says couscous. The derivation must be exactly what the
        // pipeline would have computed had the segmenter said couscous.
        let preBetaCm3: Float = 120
        let beta = Macros.betaCorrection(
            for: ["white_rice", "couscous"], database: db, edition: edition
        )

        let relabelled = Macros.reDerive(
            preBetaVolumeCm3: preBetaCm3,
            as: "couscous",
            beta: beta,
            database: db,
            edition: edition
        )

        let direct = Macros.compute(
            perClassVolumesCm3: ["couscous": preBetaCm3 * 0.8],  // β_couscous = 0.8
            database: db,
            edition: edition
        )
        XCTAssertEqual(relabelled, direct)

        // The row carries couscous's own β and calibration status (Req 3.7):
        // the original class's β is fully divided out, never carried across.
        let entry = try! XCTUnwrap(relabelled.perClass["couscous"])
        XCTAssertEqual(entry.betaUsed, 0.8, accuracy: 1e-6)
        XCTAssertEqual(entry.betaStatus, .calibrated)
        XCTAssertEqual(entry.massG, 120 * 0.8 * 1.10, accuracy: 1e-3)
    }

    func testRelabelToUncalibratedClassCarriesItsStatus() {
        // Req 3.7: a target with no fitted β_c derives on the same terms the
        // pipeline uses for an uncalibrated class — β 1.0, status stamped.
        let beta = Macros.betaCorrection(
            for: ["white_rice", "chicken"], database: db, edition: edition
        )
        let result = Macros.reDerive(
            preBetaVolumeCm3: 120, as: "chicken",
            beta: beta, database: db, edition: edition
        )
        let entry = try! XCTUnwrap(result.perClass["chicken"])
        XCTAssertEqual(entry.betaUsed, 1.0, accuracy: 1e-6)
        XCTAssertEqual(entry.betaStatus, .uncalibratedUnity)
    }

    func testLiquidFlagsPassThrough() {
        // A liquid's over-read flag must not be silently dropped.
        let beta = Macros.betaCorrection(for: [], database: db, edition: edition)
        let result = Macros.reDerive(
            preBetaVolumeCm3: 200, as: "milk",
            beta: beta, database: db, edition: edition,
            liquidClassIds: ["milk"], liquidOverEstimate: true
        )
        XCTAssertTrue(result.liquidOverEstimate)
        XCTAssertEqual(result.perClass["milk"]?.isLiquid, true)
    }

    // MARK: - Pre-β fallback (Decision 17; refusal per Decision 14)

    func testPreBetaFallbackDividesOutBeta() {
        let recovered = Macros.preBetaVolume(storedVolumeCm3: 108, betaUsed: 0.9)
        XCTAssertEqual(try XCTUnwrap(recovered), 120, accuracy: 1e-4)
    }

    func testPreBetaFallbackRefusesCorruptBeta() {
        XCTAssertNil(Macros.preBetaVolume(storedVolumeCm3: 108, betaUsed: 0))
        XCTAssertNil(Macros.preBetaVolume(storedVolumeCm3: 108, betaUsed: -0.5))
        XCTAssertNil(Macros.preBetaVolume(storedVolumeCm3: 108, betaUsed: .nan))
        XCTAssertNil(Macros.preBetaVolume(storedVolumeCm3: 108, betaUsed: .infinity))
    }

    // MARK: - Corrected fat and protein (insulin-dosing Req 8.3, 8.8)

    func testCorrectedFatAndProteinFollowTheCorrectedMasses() throws {
        let derived = try XCTUnwrap(
            Macros.correctedFatAndProtein(
                massGByClassID: ["couscous": 150, "chicken": 200],
                database: db, edition: edition))

        // couscous 150 g at 0.2 g fat / 100 g, chicken 200 g at 3.6. The
        // tolerance is Float32's, not the arithmetic's: FoodEntry holds its
        // per-100 g figures as Float, exactly as the pipeline reads them.
        XCTAssertEqual(derived.fatG, 150 * 0.2 / 100 + 200 * 3.6 / 100, accuracy: 1e-5)
        XCTAssertEqual(derived.proteinG, 150 * 3.8 / 100 + 200 * 31.0 / 100, accuracy: 1e-5)
    }

    // The whole point of F1: the figures follow the CORRECTED masses, so a
    // meal scaled down carries fat scaled down with it.
    func testHalvingEveryMassHalvesBothFigures() throws {
        let full = try XCTUnwrap(
            Macros.correctedFatAndProtein(
                massGByClassID: ["couscous": 150, "chicken": 200],
                database: db, edition: edition))
        let half = try XCTUnwrap(
            Macros.correctedFatAndProtein(
                massGByClassID: ["couscous": 75, "chicken": 100],
                database: db, edition: edition))

        XCTAssertEqual(half.fatG, full.fatG / 2, accuracy: 1e-9)
        XCTAssertEqual(half.proteinG, full.proteinG / 2, accuracy: 1e-9)
    }

    // A rejected food contributes zero mass and therefore zero fat, which is
    // not the same fact as a meal whose classes cannot be resolved at all.
    func testAZeroMassMealResolvesToZeroRatherThanAbsent() throws {
        let derived = try XCTUnwrap(
            Macros.correctedFatAndProtein(
                massGByClassID: ["couscous": 0], database: db, edition: edition))

        XCTAssertEqual(derived.fatG, 0)
        XCTAssertEqual(derived.proteinG, 0)
    }

    // Req 8.1's absent-is-not-zero rule: nothing derivable reads as absent.
    func testNoResolvableClassReadsAsAbsentNotFatFree() {
        XCTAssertNil(
            Macros.correctedFatAndProtein(
                massGByClassID: ["not_a_food": 120], database: db, edition: edition))
        XCTAssertNil(
            Macros.correctedFatAndProtein(
                massGByClassID: [:], database: db, edition: edition))
    }

    // A class that fails to resolve inside an otherwise resolvable meal is
    // skipped, matching Macros.compute's own silent skip.
    func testOneUnresolvableClassIsSkippedNotFatal() throws {
        let derived = try XCTUnwrap(
            Macros.correctedFatAndProtein(
                massGByClassID: ["couscous": 150, "not_a_food": 500],
                database: db, edition: edition))

        XCTAssertEqual(derived.fatG, 150 * 0.2 / 100, accuracy: 1e-5)
    }
}

// MARK: - Stub

private final class ReDerivationStubDatabase: FoodDatabase, @unchecked Sendable {
    let version = "CoFID 2024"

    private let entries: [String: FoodEntry] = [
        "white_rice": FoodEntry(
            classId: "white_rice", name: "White rice",
            densityGPerCm3: 1.05, energyKJPer100g: 580.0,
            carbsMonoG: 32.0, proteinG: 2.7, fatG: 0.3, fibreG: 0.1,
            beta: 0.9, calibrationStatus: .calibrated,
            densitySource: "CoFID 2024", compositionSource: "CoFID 2024"
        ),
        "couscous": FoodEntry(
            classId: "couscous", name: "Couscous",
            densityGPerCm3: 1.10, energyKJPer100g: 470.0,
            carbsMonoG: 23.0, proteinG: 3.8, fatG: 0.2, fibreG: 1.4,
            beta: 0.8, calibrationStatus: .calibrated,
            densitySource: "CoFID 2024", compositionSource: "CoFID 2024"
        ),
        "chicken": FoodEntry(
            classId: "chicken", name: "Chicken breast",
            densityGPerCm3: 0.9, energyKJPer100g: 736.0,
            carbsMonoG: 0.0, proteinG: 31.0, fatG: 3.6, fibreG: 0.0,
            beta: 1.0, calibrationStatus: .uncalibratedUnity,
            densitySource: "FAO_DENS", compositionSource: "CoFID 2024"
        ),
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
    func availableEditions() -> [String] { [version] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}
