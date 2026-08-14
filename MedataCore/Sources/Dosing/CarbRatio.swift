// The carbohydrate ratio, in the one direction this repository stores it
// (specs/data/insulin-dosing Req 1, Decision 3).
//
// Foundation only. This target has no dependencies and must acquire none: the
// firewall that keeps dose arithmetic out of the estimation path is the empty
// dependency list in Package.swift, not a graph test (design.md "Module layout
// and the firewall").
import Foundation

/// Grams of carbohydrate covered by one unit of insulin — the clinical
/// carbohydrate ratio, and the direction medreg fits in. The reciprocal
/// (units per gram) is NEVER stored; `unitsPerTenGrams` is a display
/// derivation only (Req 1.1, 1.2).
public struct CarbRatio: Sendable, Equatable, Hashable {

    /// The closed interval a configured value must fall inside (Req 1.5).
    public static let permitted: ClosedRange<Double> = 1.0...60.0

    public let gramsPerUnit: Double

    /// `nil` for a value outside `permitted` or a non-finite value; the caller
    /// keeps whatever was previously in force (Req 1.5). Both endpoints are
    /// accepted — the interval is closed.
    public init?(gramsPerUnit: Double) {
        guard gramsPerUnit.isFinite, Self.permitted.contains(gramsPerUnit) else { return nil }
        self.gramsPerUnit = gramsPerUnit
    }

    /// Display only, never stored (Req 1.1). 5.0 g/U renders as
    /// "= 2.0 U per 10 g", which is the developer's own phrasing of the same
    /// ratio; holding both directions in storage is exactly how the two would
    /// drift apart.
    public var unitsPerTenGrams: Double { 10.0 / gramsPerUnit }
}

/// The four band ratios in force, each falling back to its seed (Req 1.3, 1.6).
public struct CarbRatioTable: Sendable, Equatable {

    /// Seeds reproducing the developer's stated rule — 2 U per 10 g at
    /// breakfast, 1 U per 10 g otherwise (Req 1.4). These are defaults, not
    /// constants: Settings overrides any of them.
    public static let seed: [DoseBand: CarbRatio] = [
        .overnight: CarbRatio(gramsPerUnit: 10.0)!,
        .breakfast: CarbRatio(gramsPerUnit: 5.0)!,
        .lunch: CarbRatio(gramsPerUnit: 10.0)!,
        .dinner: CarbRatio(gramsPerUnit: 10.0)!
    ]

    private let configured: [DoseBand: CarbRatio]

    public init(configured: [DoseBand: CarbRatio] = [:]) {
        self.configured = configured
    }

    /// Falls back to the seed for an unconfigured band and reports which
    /// applied, so the suggestion row can record it (Req 1.6, 1.7, 9.4).
    ///
    /// The seed covers all four bands, so the force-unwrap is total.
    public func ratio(for band: DoseBand) -> (value: CarbRatio, isSeed: Bool) {
        if let value = configured[band] { return (value, false) }
        return (Self.seed[band]!, true)
    }
}
