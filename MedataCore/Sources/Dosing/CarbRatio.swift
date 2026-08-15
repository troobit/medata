import Foundation

/// Grams of carbohydrate covered by one unit of insulin — the clinical
/// carbohydrate ratio, and the direction medreg fits in
/// (specs/data/insulin-dosing Req 1.1, Decision 13). The reciprocal
/// (units per gram) is NEVER stored; `unitsPerTenGrams` is a display
/// derivation only.
///
/// The developer's phrasing "2 U per 10 g in the morning" IS 5.0 g/U, and
/// "1 U per 10 g" IS 10.0 g/U. A 60 g breakfast at 5.0 g/U is 12 U.
public struct CarbRatio: Sendable, Equatable, Hashable {
    /// Req 1.5 — both endpoints inclusive.
    public static let permitted: ClosedRange<Double> = 1.0...60.0

    public let gramsPerUnit: Double

    /// nil for a value outside `permitted` or a non-finite value; the caller
    /// keeps whatever was previously in force (Req 1.5). No error copy is
    /// rendered anywhere — a rejected entry simply reverts.
    public init?(gramsPerUnit: Double) {
        guard gramsPerUnit.isFinite, Self.permitted.contains(gramsPerUnit) else { return nil }
        self.gramsPerUnit = gramsPerUnit
    }

    /// Display only. 5.0 g/U renders "= 2.0 U per 10 g" (Req 1.2).
    public var unitsPerTenGrams: Double { 10.0 / gramsPerUnit }
}

/// The per-band table. Seeds reproduce the developer's stated rule — 2 U per
/// 10 g at breakfast, 1 U per 10 g otherwise (Req 1.4), expressed in the one
/// canonical direction.
public struct CarbRatioTable: Sendable, Equatable {
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
        return (Self.seed[band]!, true)
    }
}
