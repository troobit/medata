import XCTest
@testable import Foods

// Serving⇄gram arithmetic and the machine-readable serving note
// (serving-adjust PRD, iOS Req 1/3/4). The seed data mirrors the shipped
// solid_servings rows: potato_boiled = 58 g/unit step 0.5, spoon-unit
// classes = 27 g/unit step 1.0.
final class ServingMathTests: XCTestCase {

    // MARK: - conversion

    func testGramsForServings() {
        XCTAssertEqual(ServingMath.grams(servings: 1.5, gramsPerUnit: 58), 87, accuracy: 1e-9)
        XCTAssertEqual(ServingMath.grams(servings: 0, gramsPerUnit: 58), 0)
        XCTAssertEqual(ServingMath.grams(servings: -1, gramsPerUnit: 58), 0, "floored at 0")
    }

    func testServingsForGrams() {
        XCTAssertEqual(ServingMath.servings(grams: 87, gramsPerUnit: 58), 1.5, accuracy: 1e-9)
        XCTAssertEqual(ServingMath.servings(grams: 100, gramsPerUnit: 0), 0, "zero unit weight never divides")
        XCTAssertEqual(ServingMath.servings(grams: -5, gramsPerUnit: 58), 0, "floored at 0")
    }

    func testRoundTripIsExactForStepMultiples() {
        let grams = ServingMath.grams(servings: 2.5, gramsPerUnit: 27)
        XCTAssertEqual(ServingMath.servings(grams: grams, gramsPerUnit: 27), 2.5, accuracy: 1e-9)
    }

    // MARK: - display rounding

    func testDisplayHalfUnitsRoundsToNearestHalf() {
        XCTAssertEqual(ServingMath.displayHalfUnits(1.72), 1.5)
        XCTAssertEqual(ServingMath.displayHalfUnits(1.76), 2.0)
        XCTAssertEqual(ServingMath.displayHalfUnits(0.24), 0.0)
        XCTAssertEqual(ServingMath.displayHalfUnits(0.26), 0.5)
        XCTAssertEqual(ServingMath.displayHalfUnits(-0.4), 0.0, "floored at 0")
    }

    func testHalfUnitText() {
        XCTAssertEqual(ServingMath.halfUnitText(0), "0")
        XCTAssertEqual(ServingMath.halfUnitText(0.5), "½")
        XCTAssertEqual(ServingMath.halfUnitText(1), "1")
        XCTAssertEqual(ServingMath.halfUnitText(1.5), "1½")
        XCTAssertEqual(ServingMath.halfUnitText(2), "2")
        XCTAssertEqual(ServingMath.halfUnitText(12.5), "12½")
    }

    func testUnitLabelSingularForHalfAndOne() {
        XCTAssertEqual(ServingMath.unitLabel(count: 0.5, singular: "potato", plural: "potatoes"), "potato")
        XCTAssertEqual(ServingMath.unitLabel(count: 1, singular: "potato", plural: "potatoes"), "potato")
        XCTAssertEqual(ServingMath.unitLabel(count: 0, singular: "potato", plural: "potatoes"), "potatoes")
        XCTAssertEqual(ServingMath.unitLabel(count: 1.5, singular: "potato", plural: "potatoes"), "potatoes")
        XCTAssertEqual(
            ServingMath.unitLabel(count: 3, singular: "heaped tablespoon", plural: "heaped tablespoons"),
            "heaped tablespoons"
        )
    }

    // MARK: - serving note

    func testNoteFormatsServingsAndGrams() {
        let note = ServingNote.note([
            ("potato_boiled", .servings(1.5)),
            ("peas", .servings(3)),
            ("water", .grams(120)),
        ])
        XCTAssertEqual(note, "servings potato_boiled=1.5 peas=3 water=120g")
    }

    func testNoteTrimsToTwoDecimals() {
        XCTAssertEqual(ServingNote.note([("potato_boiled", .servings(1.7241))]),
                       "servings potato_boiled=1.72")
    }

    func testParseRoundTrip() {
        let parsed = ServingNote.parse("servings potato_boiled=1.5 peas=3 water=120g")
        XCTAssertEqual(parsed?["potato_boiled"], .servings(1.5))
        XCTAssertEqual(parsed?["peas"], .servings(3))
        XCTAssertEqual(parsed?["water"], .grams(120))
    }

    func testParseRejectsForeignAndMalformedNotes() {
        XCTAssertNil(ServingNote.parse("portion 2/5"), "legacy portion notes are a different convention")
        XCTAssertNil(ServingNote.parse("a free-text correction note"))
        XCTAssertNil(ServingNote.parse("servings "))
        XCTAssertNil(ServingNote.parse("servings potato=abc"))
        XCTAssertNil(ServingNote.parse("servings potato=1=2"))
        XCTAssertNil(ServingNote.parse("servings potato=-3"))
    }
}
