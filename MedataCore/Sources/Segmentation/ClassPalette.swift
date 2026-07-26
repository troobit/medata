import Foundation
import PortableContracts

// Swift-ergonomic palette per design §3.5 with bridges to/from the portable Pb*
// generated type. Convention: foodClasses[i] is the class name for solid class
// index i, i ∈ 0..<foodClasses.count; liquidClasses follow at indices
// foodClasses.count..<(foodClasses.count + liquidClasses.count). The three
// special classes (background, unknown_food, unsupported_liquid) occupy the
// remaining indices declared via the dedicated Int fields. Total class count is
// foodClasses.count + liquidClasses.count + 3.
public struct ClassPalette: Sendable, Equatable {
    public let foodClasses: [String]
    public let liquidClasses: [String]
    public let background: Int
    public let unknownFood: Int
    public let unsupportedLiquid: Int
    public let version: String

    public init(foodClasses: [String], liquidClasses: [String] = [],
                background: Int, unknownFood: Int,
                unsupportedLiquid: Int, version: String) {
        self.foodClasses = foodClasses
        self.liquidClasses = liquidClasses
        self.background = background
        self.unknownFood = unknownFood
        self.unsupportedLiquid = unsupportedLiquid
        self.version = version
    }

    public var totalClasses: Int { foodClasses.count + liquidClasses.count + 3 }

    // Solid food classes only — liquid handling is strictly opt-in through
    // isLiquidClass (Decisions 23/24 predicate contract).
    public func isFoodClass(_ classId: Int) -> Bool {
        classId >= 0 && classId < foodClasses.count
    }

    public func isLiquidClass(_ classId: Int) -> Bool {
        classId >= foodClasses.count && classId < foodClasses.count + liquidClasses.count
    }

    public func foodClassName(at classId: Int) -> String? {
        guard isFoodClass(classId) else { return nil }
        return foodClasses[classId]
    }

    public func liquidClassName(at classId: Int) -> String? {
        guard isLiquidClass(classId) else { return nil }
        return liquidClasses[classId - foodClasses.count]
    }

    // Name for any solid or liquid class index; nil for the sentinels.
    public func className(at classId: Int) -> String? {
        foodClassName(at: classId) ?? liquidClassName(at: classId)
    }
}

public extension ClassPalette {
    // The v1 palette (design §3.5, coarse liquid classes per Decisions 23/24),
    // retained for the v1 → v2 persisted-meal migration (PaletteMigrator).
    // Indices 0–23: solid food classes; 24–31: liquid classes; 32: background;
    // 33: unknown_food; 34: unsupported_liquid.
    static let v1Standard = ClassPalette(
        foodClasses: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
            "pork", "fish_white", "egg", "cheese", "salad_leaves",
            "broccoli", "carrot", "peas", "beans_baked", "lentils",
            "apple", "banana", "tomato", "mixed_vegetables"
        ],
        liquidClasses: [
            "water", "coffee", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ],
        background: 32,
        unknownFood: 33,
        unsupportedLiquid: 34,
        version: "v1"
    )

    // The v2 palette matching tools/food_db/generate.py: v1 plus the `cereal`
    // solid class (breakfast cereals — porridge/muesli/granola/cornflakes;
    // myfoodrepo-bridge PRD). Cereal appends after the existing 24 solids so
    // the carb-priority staple channels (first 8 solids) keep their indices.
    // Indices 0–24: solid food classes; 25–32: liquid classes; 33: background;
    // 34: unknown_food; 35: unsupported_liquid.
    static let v2Standard = ClassPalette(
        foodClasses: [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries", "chicken", "beef",
            "pork", "fish_white", "egg", "cheese", "salad_leaves",
            "broccoli", "carrot", "peas", "beans_baked", "lentils",
            "apple", "banana", "tomato", "mixed_vegetables", "cereal"
        ],
        liquidClasses: [
            "water", "coffee", "tea", "milk",
            "fruit_juice", "soup", "beer", "wine"
        ],
        background: 33,
        unknownFood: 34,
        unsupportedLiquid: 35,
        version: "v2"
    )

    // Resolves a persisted `paletteVersion` label to its standard palette —
    // the read-side counterpart of the per-record `paletteVersion` column, so
    // display code renders v1-era meals with v1 indices and v2 meals with v2
    // (bugfix app-palette-drift-after-v2-promotion). Unrecognised labels fall
    // back to v1, preserving pre-resolver behaviour for e.g. "uitest".
    static func standard(for version: String) -> ClassPalette {
        version == "v2" ? .v2Standard : .v1Standard
    }
}

public extension ClassPalette {
    init(pb: PbClassPalette) {
        self.init(
            foodClasses: pb.foodClasses,
            liquidClasses: pb.liquidClasses,
            background: Int(pb.background),
            unknownFood: Int(pb.unknownFood),
            unsupportedLiquid: Int(pb.unsupportedLiquid),
            version: pb.version
        )
    }

    var pb: PbClassPalette {
        var p = PbClassPalette()
        p.foodClasses = foodClasses
        p.liquidClasses = liquidClasses
        p.background = Int32(background)
        p.unknownFood = Int32(unknownFood)
        p.unsupportedLiquid = Int32(unsupportedLiquid)
        p.version = version
        return p
    }
}
