import XCTest
@testable import Segmentation

final class SegmentationModuleTests: XCTestCase {
    func testModuleNameIsDefined() {
        XCTAssertEqual(SegmentationModule.moduleName, "Segmentation")
    }

    func testClassPaletteRoundTrip() {
        let palette = ClassPalette(
            foodClasses: ["rice", "potato"],
            background: 2, unknownFood: 3, unsupportedLiquid: 4,
            version: "v1"
        )
        let pb = palette.pb
        let recovered = ClassPalette(pb: pb)
        XCTAssertEqual(recovered, palette)
    }

    func testIsFoodClassClassifiesIndicesCorrectly() {
        let palette = ClassPalette(
            foodClasses: ["rice", "potato"],
            background: 2, unknownFood: 3, unsupportedLiquid: 4,
            version: "v1"
        )
        XCTAssertTrue(palette.isFoodClass(0))
        XCTAssertTrue(palette.isFoodClass(1))
        XCTAssertFalse(palette.isFoodClass(2))
        XCTAssertFalse(palette.isFoodClass(3))
        XCTAssertFalse(palette.isFoodClass(4))
        XCTAssertFalse(palette.isFoodClass(-1))
        XCTAssertFalse(palette.isFoodClass(5))
    }
}
