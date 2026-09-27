import Foundation
import Segmentation

// Per-class food height priors (two-view-trust Decision 11). The bundled
// `height_priors.json` is `tools/metafood3d/height_priors.py`'s output over the
// 637 MetaFood3D meshes, seated on their support plane, keyed by palette class
// (`tools/metafood3d/HEIGHT_PRIORS.md`). The two-view carve has no height bound
// on a phone without LiDAR — two silhouette cones at the tilts the aim guide
// allows never close over a low food (Decision 8) — so the grid's vertical
// extent sets the answer, and the shipped 120 mm constant read a bread roll at
// 2.5x. The class cap is the loosest statistic that is still class-specific:
//
//   cap = class max-height P90 + the shipped margin        (n_items >= 4)
//   cap = global max-height P90 + the shipped margin       (otherwise)
//
// P90 of per-item maximum height, not P50: on the mixed-form classes (bread is
// slices, rolls and loaves) a P50 cap clips three of the five audited rolls.
// The cap bounds the no-depth carve; it does not fix it. On the LiDAR path the
// measured extent is `min(measured, cap)` and the cap can never raise it
// (`VoxelGridSizer.verticalBound`).
public struct ClassHeightPriors: Sendable {

    public enum CapSource: String, Sendable, Codable {
        /// The class's own P90 (n_items >= `minItems`).
        case classPrior
        /// The global P90 over all meshes: no items, or fewer than `minItems`.
        case global
    }

    public struct Cap: Sendable, Equatable {
        public let mm: Float
        public let source: CapSource
    }

    /// Fewest measured meshes a class P90 may rest on.
    public static let minItems = 4
    /// The bundled resource's name.
    public static let resourceName = "height_priors"

    public let schema: String
    public let marginMm: Float
    public let globalP90Mm: Float
    /// Palette index -> class max-height P90, mm; only classes with at least
    /// `minItems` meshes. Every other index takes the global P90.
    public let classP90Mm: [Int: Float]
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
        guard file.schema == "height_priors.v1" else {
            throw Error.unexpectedSchema(file.schema)
        }
        var p90: [Int: Float] = [:]
        var names: [Int: String] = [:]
        for (name, entry) in file.classes {
            names[entry.index] = name
            if let v = entry.maxHeightP90Mm, entry.nItems >= Self.minItems {
                p90[entry.index] = v
            }
        }
        self.schema = file.schema
        self.marginMm = marginMm
        self.globalP90Mm = file.global.maxHeightP90Mm
        self.classP90Mm = p90
        self.classNames = names
    }

    /// The cap for one palette index.
    public func cap(forPaletteIndex index: Int) -> Cap {
        if let v = classP90Mm[index] {
            return Cap(mm: v + marginMm, source: .classPrior)
        }
        return Cap(mm: globalP90Mm + marginMm, source: .global)
    }

    public func capMm(forPaletteIndex index: Int) -> Float {
        cap(forPaletteIndex: index).mm
    }

    /// The cap for a set of classes carved together: the loosest of their
    /// caps, so no class present is clipped by another's. nil for no classes.
    public func cap<S: Sequence>(forPaletteIndices indices: S) -> Cap? where S.Element == Int {
        var best: Cap?
        for i in indices {
            let c = cap(forPaletteIndex: i)
            if best == nil || c.mm > best!.mm { best = c }
        }
        return best
    }

    /// The cap for a nadir label map: the loosest cap over the distinct
    /// carvable classes it carries. After `ObjectReconciler` relabels a
    /// single-object view that is one class; a view left as several classes
    /// takes the tallest. `unknown_food` takes the global cap. nil when the
    /// map carries no carvable pixel.
    public func cap(forNadirArgmax argmax: ArgmaxMap, palette: ClassPalette) -> Cap? {
        var present = [Bool](repeating: false, count: palette.totalClasses)
        argmax.pixels.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                let c = Int(byte)
                if c < present.count { present[c] = true }
            }
        }
        let classes = present.indices.filter { present[$0] && palette.isCarvableClass($0) }
        return cap(forPaletteIndices: classes)
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
            enum CodingKeys: String, CodingKey {
                case index
                case nItems = "n_items"
                case maxHeightP90Mm = "max_height_p90_mm"
            }
        }
    }
}
