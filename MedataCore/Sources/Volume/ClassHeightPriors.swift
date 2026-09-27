import Foundation
import Segmentation

// Per-class food height priors (two-view-trust Decisions 11 and 12). The
// bundled `height_priors.json` is `tools/metafood3d/height_priors.py`'s output
// over the 637 MetaFood3D meshes, seated on their support plane, keyed by
// palette class (`tools/metafood3d/HEIGHT_PRIORS.md`). The two-view carve has
// no height bound on a phone without LiDAR — two silhouette cones at the tilts
// the aim guide allows never close over a low food (Decision 8) — so the grid's
// vertical extent sets the answer, and the shipped 120 mm constant read a
// bread roll at 2.5x.
//
// Two caps, one per `cap_mode` in the file:
//
//   height mode (Decision 11):
//     cap = class max-height P90 + the shipped margin        (n_items >= 4)
//     cap = global max-height P90 + the shipped margin       (otherwise)
//
//   ratio mode (Decision 12), where the file says the class's height scales
//   with its footprint (a roll and a loaf are one shape at two sizes):
//     cap = r_P90 x sqrt(silhouette footprint mm²) + margin,
//           clamped to [`ratioFloorMm`, the height-mode cap]
//     with r = max height / sqrt(footprint) per mesh. The footprint is the
//     nadir silhouette on the support plane, so the cap follows the object on
//     the plate where the absolute cap can only name the tallest form.
//
// P90, not P50, in both modes: a cap must not clip real food. The cap bounds
// the no-depth carve; it does not fix it. On the LiDAR path the measured
// extent is `min(measured, height-mode cap)` and the cap can never raise it
// (`VoxelGridSizer.verticalBound`); the ratio cap is a prior about form and
// yields to a measurement (`carveCap`).
public struct ClassHeightPriors: Sendable {

    public enum CapSource: String, Sendable, Codable {
        /// The class's footprint-scaled cap (ratio mode, n_items >= `minItems`).
        case classRatio
        /// The class's own P90 (n_items >= `minItems`).
        case classPrior
        /// The global P90 over all meshes: no items, or fewer than `minItems`.
        case global
    }

    public struct Cap: Sendable, Equatable {
        public let mm: Float
        public let source: CapSource

        public init(mm: Float, source: CapSource) {
            self.mm = mm
            self.source = source
        }
    }

    /// Fewest measured meshes a class P90 may rest on.
    public static let minItems = 4
    /// Floor on a ratio-mode cap, mm: a silhouette small enough to put the
    /// cap under this is a fragment, not a form.
    public static let ratioFloorMm: Float = 10
    /// The bundled resource's name.
    public static let resourceName = "height_priors"
    public static let schemaVersion = "height_priors.v2"

    public let schema: String
    public let marginMm: Float
    public let globalP90Mm: Float
    /// Palette index -> class max-height P90, mm; only classes with at least
    /// `minItems` meshes. Every other index takes the global P90.
    public let classP90Mm: [Int: Float]
    /// Palette index -> P90 of max height over sqrt(footprint); only classes
    /// the file puts in ratio mode, with at least `minItems` meshes.
    public let classRatioP90: [Int: Float]
    /// Palette index -> class name as the file records it, every index.
    public let classNames: [Int: String]

    public enum Error: Swift.Error, Equatable {
        case resourceMissing
        case unexpectedSchema(String)
    }

    /// The bundled priors, resolved once. nil only if the resource is missing
    /// or unreadable, in which case callers pass no cap and the sizer keeps
    /// its constant.
    public static let bundled: ClassHeightPriors? = {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ClassHeightPriors(data: data)
    }()

    public init(data: Data, marginMm: Float = VoxelGridSizer.heightMarginMm) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == Self.schemaVersion else {
            throw Error.unexpectedSchema(file.schema)
        }
        var p90: [Int: Float] = [:]
        var ratio: [Int: Float] = [:]
        var names: [Int: String] = [:]
        for (name, entry) in file.classes {
            names[entry.index] = name
            guard entry.nItems >= Self.minItems else { continue }
            if let v = entry.maxHeightP90Mm { p90[entry.index] = v }
            if entry.capMode == "ratio", let r = entry.ratioP90 { ratio[entry.index] = r }
        }
        self.schema = file.schema
        self.marginMm = marginMm
        self.globalP90Mm = file.global.maxHeightP90Mm
        self.classP90Mm = p90
        self.classRatioP90 = ratio
        self.classNames = names
    }

    /// The height-mode cap for one palette index (Decision 11).
    public func cap(forPaletteIndex index: Int) -> Cap {
        if let v = classP90Mm[index] {
            return Cap(mm: v + marginMm, source: .classPrior)
        }
        return Cap(mm: globalP90Mm + marginMm, source: .global)
    }

    public func capMm(forPaletteIndex index: Int) -> Float {
        cap(forPaletteIndex: index).mm
    }

    /// The cap for one palette index given the food's silhouette footprint on
    /// the support plane, mm² (Decision 12). Ratio mode scales the cap with
    /// the footprint and never exceeds the height-mode cap; a class in height
    /// mode, or without enough meshes, takes the height-mode cap unchanged.
    public func cap(forPaletteIndex index: Int, footprintMm2: Float) -> Cap {
        let absolute = cap(forPaletteIndex: index)
        guard let r = classRatioP90[index], footprintMm2 > 0 else { return absolute }
        let scaled = r * footprintMm2.squareRoot() + marginMm
        if scaled >= absolute.mm { return absolute }
        return Cap(mm: max(scaled, Self.ratioFloorMm), source: .classRatio)
    }

    public func capMm(forPaletteIndex index: Int, footprintMm2: Float) -> Float {
        cap(forPaletteIndex: index, footprintMm2: footprintMm2).mm
    }

    /// The cap for a set of classes carved together: the loosest of their
    /// caps, so no class present is clipped by another's. nil for no classes.
    /// With a footprint each class's cap is its footprint-scaled one.
    public func cap<S: Sequence>(
        forPaletteIndices indices: S, footprintMm2: Float? = nil
    ) -> Cap? where S.Element == Int {
        var best: Cap?
        for i in indices {
            let c = footprintMm2.map { cap(forPaletteIndex: i, footprintMm2: $0) }
                ?? cap(forPaletteIndex: i)
            if best == nil || c.mm > best!.mm { best = c }
        }
        return best
    }

    /// The cap for a nadir label map: the loosest cap over the distinct
    /// carvable classes it carries. After `ObjectReconciler` relabels a
    /// single-object view that is one class; a view left as several classes
    /// takes the tallest. `unknown_food` takes the global cap. nil when the
    /// map carries no carvable pixel. `footprintMm2` is the carvable
    /// silhouette's area on the support plane; with it each class's cap is
    /// footprint-scaled where the class is in ratio mode.
    public func cap(
        forNadirArgmax argmax: ArgmaxMap, palette: ClassPalette, footprintMm2: Float? = nil
    ) -> Cap? {
        var present = [Bool](repeating: false, count: palette.totalClasses)
        argmax.pixels.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                let c = Int(byte)
                if c < present.count { present[c] = true }
            }
        }
        let classes = present.indices.filter { present[$0] && palette.isCarvableClass($0) }
        return cap(forPaletteIndices: classes, footprintMm2: footprintMm2)
    }

    /// The cap the carve takes for a nadir map (Decision 12): the
    /// footprint-scaled cap where no height is measured, the height-mode cap
    /// (Decision 11's ceiling) where one is. The ratio cap is a prior about
    /// the food's form; a LiDAR measurement of the food's own height beats
    /// it, so it must never bite a measured extent.
    public func carveCap(
        forNadirArgmax argmax: ArgmaxMap, palette: ClassPalette,
        footprintMm2: Float, heightMeasured: Bool
    ) -> Cap? {
        cap(forNadirArgmax: argmax, palette: palette,
            footprintMm2: heightMeasured ? nil : footprintMm2)
    }

    /// True when every named class sits at its palette index — the file was
    /// generated against this palette. Asserted in tests; a palette change
    /// regenerates the file (`docs/agent-notes/class-palette.md`).
    public func matches(_ palette: ClassPalette) -> Bool {
        for (index, name) in classNames {
            if let expected = palette.volumetricClassName(at: index), expected != name {
                return false
            }
        }
        return true
    }

    // MARK: - file schema

    private struct File: Decodable {
        let schema: String
        let global: Global
        let classes: [String: Entry]

        struct Global: Decodable {
            let maxHeightP90Mm: Float
            enum CodingKeys: String, CodingKey { case maxHeightP90Mm = "max_height_p90_mm" }
        }

        struct Entry: Decodable {
            let index: Int
            let nItems: Int
            let maxHeightP90Mm: Float?
            let ratioP90: Float?
            let capMode: String?
            enum CodingKeys: String, CodingKey {
                case index
                case nItems = "n_items"
                case maxHeightP90Mm = "max_height_p90_mm"
                case ratioP90 = "ratio_p90"
                case capMode = "cap_mode"
            }
        }
    }
}
