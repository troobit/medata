import XCTest
@testable import Segmentation

final class SegmentationModuleTests: XCTestCase {
    func testModuleNameIsDefined() {
        XCTAssertEqual(SegmentationModule.moduleName, "Segmentation")
    }

    func testClassPaletteRoundTrip() {
        let palette = ClassPalette(
            foodClasses: ["rice", "potato"],
            liquidClasses: ["water", "milk"],
            background: 4, unknownFood: 5, unsupportedLiquid: 6,
            version: "test"
        )
        let pb = palette.pb
        let recovered = ClassPalette(pb: pb)
        XCTAssertEqual(recovered, palette)
        XCTAssertEqual(pb.liquidClasses, ["water", "milk"])
    }

    func testIsFoodClassClassifiesIndicesCorrectly() {
        let palette = ClassPalette(
            foodClasses: ["rice", "potato"],
            liquidClasses: ["water"],
            background: 3, unknownFood: 4, unsupportedLiquid: 5,
            version: "test"
        )
        XCTAssertTrue(palette.isFoodClass(0))
        XCTAssertTrue(palette.isFoodClass(1))
        XCTAssertFalse(palette.isFoodClass(2))   // liquid, not solid food
        XCTAssertFalse(palette.isFoodClass(3))
        XCTAssertFalse(palette.isFoodClass(4))
        XCTAssertFalse(palette.isFoodClass(5))
        XCTAssertFalse(palette.isFoodClass(-1))
        XCTAssertFalse(palette.isFoodClass(6))
    }

    func testIsLiquidClassCoversExactlyTheLiquidRange() {
        let palette = ClassPalette(
            foodClasses: ["rice", "potato"],
            liquidClasses: ["water", "milk"],
            background: 4, unknownFood: 5, unsupportedLiquid: 6,
            version: "test"
        )
        XCTAssertFalse(palette.isLiquidClass(0))
        XCTAssertFalse(palette.isLiquidClass(1))
        XCTAssertTrue(palette.isLiquidClass(2))
        XCTAssertTrue(palette.isLiquidClass(3))
        XCTAssertFalse(palette.isLiquidClass(4))
        XCTAssertFalse(palette.isLiquidClass(5))
        XCTAssertFalse(palette.isLiquidClass(6))
        XCTAssertFalse(palette.isLiquidClass(-1))
        XCTAssertFalse(palette.isLiquidClass(7))
    }

    func testStandardPaletteAppendsLiquidsThenSentinels() {
        let palette = ClassPalette.standard
        XCTAssertEqual(palette.foodClasses.count, 25)
        // Carb-priority staple channels are the first 8 solids.
        XCTAssertEqual(Array(palette.foodClasses.prefix(8)), [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries"
        ])
        // Cereal sits after the original 24 solids (myfoodrepo-bridge PRD).
        XCTAssertEqual(palette.foodClasses[24], "cereal")
        XCTAssertEqual(palette.liquidClasses, [
            "water", "coffee", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ])
        // Sentinels follow the liquids: 25 solids + 8 liquids -> 33/34/35.
        XCTAssertEqual(palette.background, 33)
        XCTAssertEqual(palette.unknownFood, 34)
        XCTAssertEqual(palette.unsupportedLiquid, 35)
        XCTAssertEqual(palette.totalClasses,
                       palette.foodClasses.count + palette.liquidClasses.count + 3)
        XCTAssertEqual(palette.totalClasses, 36)
        // Single pre-release palette (pipeline Decision 50): "v0" until main.
        XCTAssertEqual(palette.version, "v0")
    }

    func testStandardPaletteProtoBridgeRoundTripsAll36Channels() {
        let palette = ClassPalette.standard
        let pb = palette.pb
        let recovered = ClassPalette(pb: pb)
        XCTAssertEqual(recovered, palette)
        XCTAssertEqual(recovered.totalClasses, 36)
        XCTAssertEqual(pb.foodClasses.count, 25)
        XCTAssertEqual(pb.liquidClasses.count, 8)
        XCTAssertEqual(pb.background, 33)
        XCTAssertEqual(pb.unknownFood, 34)
        XCTAssertEqual(pb.unsupportedLiquid, 35)
        XCTAssertEqual(pb.version, "v0")
    }

    func testStandardPalettePredicatesOverFullIndexRange() {
        let palette = ClassPalette.standard
        for classId in 0..<palette.foodClasses.count {
            XCTAssertTrue(palette.isFoodClass(classId), "solid \(classId)")
            XCTAssertFalse(palette.isLiquidClass(classId), "solid \(classId)")
        }
        let liquidRange = palette.foodClasses.count
            ..< (palette.foodClasses.count + palette.liquidClasses.count)
        for classId in liquidRange {
            XCTAssertFalse(palette.isFoodClass(classId), "liquid \(classId)")
            XCTAssertTrue(palette.isLiquidClass(classId), "liquid \(classId)")
        }
        for classId in [palette.background, palette.unknownFood,
                        palette.unsupportedLiquid, -1, palette.totalClasses] {
            XCTAssertFalse(palette.isFoodClass(classId), "sentinel/out \(classId)")
            XCTAssertFalse(palette.isLiquidClass(classId), "sentinel/out \(classId)")
        }
    }
}
