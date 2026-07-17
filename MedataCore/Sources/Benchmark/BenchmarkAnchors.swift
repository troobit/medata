// Published reference figures the report compares against (Req 1.4). Values
// and citations are pinned from docs/agent-notes/snaq-benchmark.md (verified
// 2026-07-16); treat the anchor as an order-of-magnitude bar — all source
// studies are small-N single-site.
public enum BenchmarkAnchors {
    // SNAQ real-world shipping-app performance: per-meal carb MAE
    // 13.1 ± 11.3 g (44.3%). Baumgartner 2024, J Diabetes Sci Technol
    // (53 T1D; 26 meals × 3 portions) — PubMed 39058316.
    public static let snaqMAEGrams = 13.1
    public static let snaqMAPEPercent = 44.3
    public static let snaqCitation =
        "Baumgartner 2024, J Diabetes Sci Technol (PubMed 39058316)"

    // ±10 g clinical-band references: GoCARB 37.0% of meals within ±10 g
    // versus dietitians from photos 35.2%. Vasiloglou 2018, Nutrients
    // (54 meals / 6 dietitians) — PMC6024682.
    public static let goCarbWithin10gPercent = 37.0
    public static let dietitiansWithin10gPercent = 35.2
    public static let within10gCitation =
        "Vasiloglou 2018, Nutrients (PMC6024682)"

    // The clinical band the reference studies report against.
    public static let within10gBandGrams = 10.0
}

// The segmenter staple-floor set (Req 1.6): high-carbohydrate staples that
// dominate the carb number. Mirrors CARB_PRIORITY_CLASSES in
// tools/segmenter/validation.py (authoritative home:
// specs/estimation/segmenter-foundation/decision_log.md) — names and order
// follow ClassPalette.v1Standard indices 0–7.
public enum BenchmarkStaples {
    public static let classIDs = [
        "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
        "potato_boiled", "potato_mashed", "chips_fries"
    ]
}
