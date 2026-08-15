import Foundation

/// Grams of carbohydrate covered by one unit of insulin — the clinical
/// carbohydrate ratio, and the direction medreg fits in (Req 1.1). The
/// reciprocal (units per gram) is NEVER stored; `unitsPerTenGrams` is a
/// display derivation only (Req 1.2).
///
/// The developer's phrasing "2 U per 10 g in the morning" IS 5.0 g/U, and
/// "1 U per 10 g" is 10.0 g/U (Decision 13). There is no type called `Ratio`
/// and no field called `ratio` holding a bare number: every column, label and
/// parameter carries `gPerU` / `gramsPerUnit` in its name.
public struct CarbRatio: Sendable, Equatable, Hashable {
    public static let permitted: ClosedRange<Double> = 1.0...60.0  // Req 1.5

    public let gramsPerUnit: Double

    /// nil for a value outside `permitted` or a non-finite value; the caller
    /// keeps whatever was previously in force (Req 1.5).
    public init?(gramsPerUnit: Double) {
        guard gramsPerUnit.isFinite, Self.permitted.contains(gramsPerUnit) else { return nil }
        self.gramsPerUnit = gramsPerUnit
    }

    /// Display only. 5.0 g/U renders "= 2.0 U per 10 g" (Req 1.2).
    public var unitsPerTenGrams: Double { 10.0 / gramsPerUnit }
}

public struct CarbRatioTable: Sendable, Equatable {
    /// Seeds reproducing the developer's stated rule — 2 U per 10 g at
    /// breakfast, 1 U per 10 g otherwise (Req 1.4).
    public static let seed: [DoseBand: CarbRatio] = [
        .overnight: CarbRatio(gramsPerUnit: 10.0)!,
        .breakfast: CarbRatio(gramsPerUnit: 5.0)!,
        .lunch: CarbRatio(gramsPerUnit: 10.0)!,
        .dinner: CarbRatio(gramsPerUnit: 10.0)!
    ]

    private let configured: [DoseBand: CarbRatio]

    public init(configured: [DoseBand: CarbRatio]) {
        self.configured = configured
    }

    /// Falls back to the seed for an unconfigured band and reports which
    /// applied, so the ledger row can record it (Req 1.6, 1.7, 9.4).
    public func ratio(for band: DoseBand) -> (value: CarbRatio, isSeed: Bool) {
        if let value = configured[band] { return (value, false) }
        // `seed` covers every case of DoseBand, so the fallback is
        // unreachable; it exists so this returns a value rather than trapping.
        return (Self.seed[band] ?? CarbRatio(gramsPerUnit: 10.0)!, true)
    }
}

/// The pen's dosable increment (Req 5.1, 5.6).
public struct DosableIncrement: Sendable, Equatable {
    public static let permitted: [Double] = [0.5, 1.0]
    public static let standard = DosableIncrement(units: 1.0)!

    public let units: Double

    public init?(units: Double) {
        guard Self.permitted.contains(units) else { return nil }
        self.units = units
    }
}

/// What the dose sheet's stepper can represent: 1...60 U today.
public struct DoseControlBounds: Sendable, Equatable {
    public static let stepper = DoseControlBounds(minimumUnits: 1, maximumUnits: 60)

    public let minimumUnits: Double
    public let maximumUnits: Double

    public init(minimumUnits: Double, maximumUnits: Double) {
        self.minimumUnits = minimumUnits
        self.maximumUnits = maximumUnits
    }
}
