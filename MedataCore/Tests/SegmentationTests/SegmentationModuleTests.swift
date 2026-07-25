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
            version: "v1"
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
            version: "v1"
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
            version: "v1"
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

    func testV1StandardAppendsLiquidsThenSentinels() {
        let palette = ClassPalette.v1Standard
        XCTAssertEqual(palette.foodClasses.count, 24)
        XCTAssertEqual(palette.liquidClasses, [
            "water", "coffee", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ])
        // Sentinels follow the liquids: 24 solids + 8 liquids → 32/33/34.
        XCTAssertEqual(palette.background, 32)
        XCTAssertEqual(palette.unknownFood, 33)
        XCTAssertEqual(palette.unsupportedLiquid, 34)
        XCTAssertEqual(palette.totalClasses,
                       palette.foodClasses.count + palette.liquidClasses.count + 3)
        XCTAssertEqual(palette.totalClasses, 35)
        // Retained as the migration source palette (myfoodrepo-bridge PRD).
        XCTAssertEqual(palette.version, "v1")
    }

    func testV2StandardAppendsCerealThenLiquidsThenSentinels() {
        let palette = ClassPalette.v2Standard
        XCTAssertEqual(palette.foodClasses.count, 25)
        // Carb-priority staple channels (first 8 solids) keep their v1 indices.
        XCTAssertEqual(Array(palette.foodClasses.prefix(8)),
                       Array(ClassPalette.v1Standard.foodClasses.prefix(8)))
        // Cereal appends after the 24 v1 solids — nothing before it moves.
        XCTAssertEqual(Array(palette.foodClasses.prefix(24)),
                       ClassPalette.v1Standard.foodClasses)
        XCTAssertEqual(palette.foodClasses[24], "cereal")
        XCTAssertEqual(palette.liquidClasses, [
            "water", "coffee", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ])
        // Sentinels follow the liquids: 25 solids + 8 liquids → 33/34/35.
        XCTAssertEqual(palette.background, 33)
        XCTAssertEqual(palette.unknownFood, 34)
        XCTAssertEqual(palette.unsupportedLiquid, 35)
        XCTAssertEqual(palette.totalClasses,
                       palette.foodClasses.count + palette.liquidClasses.count + 3)
        XCTAssertEqual(palette.totalClasses, 36)
        XCTAssertEqual(palette.version, "v2")
    }

    func testV2StandardProtoBridgeRoundTripsAll36Channels() {
        let palette = ClassPalette.v2Standard
        let pb = palette.pb
        let recovered = ClassPalette(pb: pb)
        XCTAssertEqual(recovered, palette)
        XCTAssertEqual(recovered.totalClasses, 36)
        XCTAssertEqual(pb.foodClasses.count, 25)
        XCTAssertEqual(pb.liquidClasses.count, 8)
        XCTAssertEqual(pb.background, 33)
        XCTAssertEqual(pb.unknownFood, 34)
        XCTAssertEqual(pb.unsupportedLiquid, 35)
        XCTAssertEqual(pb.version, "v2")
    }

    func testStandardPalettePredicatesOverFullIndexRange() {
        for palette in [ClassPalette.v1Standard, ClassPalette.v2Standard] {
            let version = palette.version
            for classId in 0..<palette.foodClasses.count {
                XCTAssertTrue(palette.isFoodClass(classId), "\(version) solid \(classId)")
                XCTAssertFalse(palette.isLiquidClass(classId), "\(version) solid \(classId)")
            }
            let liquidRange = palette.foodClasses.count
                ..< (palette.foodClasses.count + palette.liquidClasses.count)
            for classId in liquidRange {
                XCTAssertFalse(palette.isFoodClass(classId), "\(version) liquid \(classId)")
                XCTAssertTrue(palette.isLiquidClass(classId), "\(version) liquid \(classId)")
            }
            for classId in [palette.background, palette.unknownFood,
                            palette.unsupportedLiquid, -1, palette.totalClasses] {
                XCTAssertFalse(palette.isFoodClass(classId), "\(version) sentinel/out \(classId)")
                XCTAssertFalse(palette.isLiquidClass(classId), "\(version) sentinel/out \(classId)")
            }
        }
    }
}
