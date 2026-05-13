import Foundation
import PortableContracts

// Swift-ergonomic palette per design §3.5 with bridges to/from the portable Pb*
// generated type. Convention: foodClasses[i] is the class name for class index i,
// where i ∈ 0..<foodClasses.count. The three special classes (background,
// unknown_food, unsupported_liquid) occupy the remaining indices declared via the
// dedicated Int fields. Total class count is foodClasses.count + 3.
public struct ClassPalette: Sendable, Equatable {
    public let foodClasses: [String]
    public let background: Int
    public let unknownFood: Int
    public let unsupportedLiquid: Int
    public let version: String

    public init(foodClasses: [String], background: Int, unknownFood: Int,
                unsupportedLiquid: Int, version: String) {
        self.foodClasses = foodClasses
        self.background = background
        self.unknownFood = unknownFood
        self.unsupportedLiquid = unsupportedLiquid
        self.version = version
    }

    public var totalClasses: Int { foodClasses.count + 3 }

    public func isFoodClass(_ classId: Int) -> Bool {
        guard classId >= 0, classId < totalClasses else { return false }
        return classId != background && classId != unknownFood && classId != unsupportedLiquid
    }

    public func foodClassName(at classId: Int) -> String? {
        guard isFoodClass(classId), classId < foodClasses.count else { return nil }
        return foodClasses[classId]
    }
}

public extension ClassPalette {
    // The 24-food-class v1 palette matching tools/food_db/generate.py and design §3.5.
    // Indices 0–23: food classes; 24: background; 25: unknown_food; 26: unsupported_liquid.
    static let v1Standard = ClassPalette(
        foodClasses: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
            "pork", "fish_white", "egg", "cheese", "salad_leaves",
            "broccoli", "carrot", "peas", "beans_baked", "lentils",
            "apple", "banana", "tomato", "mixed_vegetables"
        ],
        background: 24,
        unknownFood: 25,
        unsupportedLiquid: 26,
        version: "v1"
    )
}

public extension ClassPalette {
    init(pb: PbClassPalette) {
        self.init(
            foodClasses: pb.foodClasses,
            background: Int(pb.background),
            unknownFood: Int(pb.unknownFood),
            unsupportedLiquid: Int(pb.unsupportedLiquid),
            version: pb.version
        )
    }

    var pb: PbClassPalette {
        var p = PbClassPalette()
        p.foodClasses = foodClasses
        p.background = Int32(background)
        p.unknownFood = Int32(unknownFood)
        p.unsupportedLiquid = Int32(unsupportedLiquid)
        p.version = version
        return p
    }
}
