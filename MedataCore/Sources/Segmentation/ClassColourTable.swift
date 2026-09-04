import Foundation

// Deterministic id->colour table sitting beside `ClassPalette` (UI Design
// Handoff 00, Decision 15). It is the single source of truth for mask-overlay
// tinting, the §9.2 per-class swatches, and the design-system pages; colours
// are applied at read time only — the stored mask PNG carries raw class
// indices, never colours.
//
// Colours come from a fixed hue wheel indexed by class id: hue advances by the
// golden-angle conjugate per id so neighbouring classes are well separated and
// each id keeps its colour no matter how many classes the palette declares.
// The table is palette-versioned so a future palette can shift the wheel
// without silently repainting existing meals.

// UI-agnostic colour (MedataCore has no SwiftUI). Components are sRGB in 0...1;
// the App wraps this in a `Color`.
public struct PaletteColour: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct ClassColourTable: Sendable, Equatable {
    public let version: String

    public init(version: String) {
        self.version = version
    }

    // The table matching `ClassPalette.standard.version`.
    public static let standard = ClassColourTable(version: "v0")

    // Fixed saturation/brightness give consistently legible swatches; only the
    // hue varies by class id.
    private static let saturation = 0.62
    private static let brightness = 0.90
    // Golden-angle conjugate: the most irrational step around the wheel, so
    // successive ids land far apart.
    private static let hueStep = 0.618_033_988_749_895

    public func colour(forClassId id: Int) -> PaletteColour {
        // `id` is non-negative in practice; guard keeps the maths total.
        let index = Double(max(0, id))
        let hue = (index * Self.hueStep).truncatingRemainder(dividingBy: 1.0)
        return Self.hsbToRGB(hue: hue, saturation: Self.saturation, brightness: Self.brightness)
    }

    // Pure HSB -> sRGB conversion (no platform colour APIs, so it is identical
    // on device and in the test host).
    private static func hsbToRGB(hue: Double, saturation: Double, brightness: Double) -> PaletteColour {
        guard saturation > 0 else {
            return PaletteColour(red: brightness, green: brightness, blue: brightness)
        }
        let h = (hue.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0) * 6.0
        let sector = floor(h)
        let f = h - sector
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch Int(sector) % 6 {
        case 0: return PaletteColour(red: brightness, green: t, blue: p)
        case 1: return PaletteColour(red: q, green: brightness, blue: p)
        case 2: return PaletteColour(red: p, green: brightness, blue: t)
        case 3: return PaletteColour(red: p, green: q, blue: brightness)
        case 4: return PaletteColour(red: t, green: p, blue: brightness)
        default: return PaletteColour(red: brightness, green: p, blue: q)
        }
    }
}

public extension ClassPalette {
    // Convenience: the colour table matching this palette's version.
    var colourTable: ClassColourTable { ClassColourTable(version: version) }
}
