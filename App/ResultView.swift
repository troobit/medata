import Foods
import Pipeline
import SwiftUI

// Four-state confidence band keyed off σ_meal per Req §9.2 / Decision 17
// (supersedes Decision 8's three-tier scheme). Boundaries:
//   High        σ ≥ 0.75
//   Moderate    0.50 ≤ σ < 0.75
//   Low         0.20 ≤ σ < 0.50
//   Very Low    σ < 0.20  (also triggers the result-view retake surface §9.3)
enum ConfidenceLevel: Equatable {
    case veryLow
    case low
    case moderate
    case high

    static func forSigma(_ sigma: Float) -> ConfidenceLevel {
        if sigma >= 0.75 { return .high }
        if sigma >= 0.50 { return .moderate }
        if sigma >= 0.20 { return .low }
        return .veryLow
    }

    var label: String {
        switch self {
        case .veryLow: return "Very Low"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var colour: Color {
        switch self {
        case .veryLow: return .confidenceVeryLow
        case .low: return .confidenceLow
        case .moderate: return .confidenceModerate
        case .high: return .confidenceHigh
        }
    }
}

// nutrition5k-calibration Req 8.1 (Decisions 18–19): exactly one of these
// states per result; the liquid over-estimate flag (Req 8.2) is independent
// and additive, never part of this enum.
enum CalibrationBannerState: Equatable {
    case full
    case softened
    case suppressed
    case none       // standalone drink — no solid-food class contributes
}

enum ResultFormat {
    // §9.1: total meal carbohydrates in grams rounded to 1 g.
    static func carbsGrams(_ totalCarbsG: Float) -> Int {
        Int(totalCarbsG.rounded())
    }

    // §9.3 / Decision 17: Very-Low surface gate. Fires only when σ_meal
    // collapses below 0.20 — the prior σ < 0.60 prompt is superseded
    // (Decision 8 → Decision 17). Below this threshold the estimate may be
    // wrong by orders of magnitude and the user is offered Retake / Keep
    // as-is.
    static let veryLowSigmaThreshold: Float = 0.20
    static func showsVeryLowSurface(_ sigma: Float) -> Bool {
        sigma < veryLowSigmaThreshold
    }

    // Decision 42 / Req §23.3: placeholder banner shown only for meals stamped
    // by the Phase 1 dev-stub segmenter. Gated on the persisted record value,
    // NOT on the build flag, so a Phase 1 record viewed under a later Phase 3
    // build still surfaces the banner per design §3.5.
    static let devStubSegmenterSource = "dev_stub"
    static func showsPlaceholderBanner(segmenterSource: String) -> Bool {
        segmenterSource == devStubSegmenterSource
    }

    static let placeholderBannerCopy =
        "Placeholder estimate. The food recogniser is a development stub — the carbohydrate value is not a real measurement."

    // Req §7.2 / §7.3 (model-production) + nutrition5k-calibration Req 8.1
    // (Decision 18): the former showsUncalibratedBanner boolean is now one
    // three-state calibration-confidence signal, evaluated over the result's
    // contributing SOLID-food classes only — liquid classes carry no β and
    // never enter this evaluation. Distinct from the σ-keyed confidence pill
    // and from the `dev_stub` placeholder banner, which marks *fake* numbers.
    //
    //   full       — any solid class pooled/unity, or no per-class data at all
    //                (conservative pre-existing rule for old/degenerate records)
    //   softened   — every solid class calibrated, any not yet device-verified
    //   suppressed — every solid class calibrated AND device-verified
    //                (unreachable within this spec; flag-injection tested)
    //   none       — no solid class contributes (standalone drink): a stated
    //                rule, not the suppressed state reached by vacuous truth
    static func calibrationBanner(
        perClass: [String: PbPerClassMacros]
    ) -> CalibrationBannerState {
        if perClass.isEmpty { return .full }
        let solids = perClass.values.filter { !$0.isLiquid }
        if solids.isEmpty { return .none }
        if solids.contains(where: { $0.betaStatus != .calibrated }) { return .full }
        if solids.contains(where: { !$0.deviceVerified }) { return .softened }
        return .suppressed
    }

    // Req 8.2 (Decision 19): both liquid estimate paths over-read; the flag is
    // result-level, set by the estimation pipeline, and renders additively
    // alongside whichever calibration state 8.1 selected.
    static func showsLiquidOverEstimateFlag(_ macros: PbMacroResult) -> Bool {
        macros.liquidOverEstimate
    }

    static let uncalibratedBannerCopy =
        "Uncalibrated estimate — volume bias is not yet corrected, so this carbohydrate value is more likely too high than too low."

    static let softenedBannerCopy =
        "This estimate is population-calibrated — not yet verified on this device."

    static let liquidOverEstimateFlagCopy =
        "Includes a drink estimate that assumes a full serving, so it is more likely too high than too low."

    // Decision 17 / research Decisions 43–47 (UI side): the Very-Low surface
    // surfaces the per-stage angular error Δθ that contributed to the low
    // confidence. The persisted `PbConfidenceResult` carries
    // `deltaThetaNadirDeg` / `deltaThetaObliqueDeg` (proto fields 5/6, threaded
    // through `PipelineBridges.pbConfidenceResult`), so we report the larger of
    // the two stages. `deltaThetaObliqueDeg` is unset on the single-view path;
    // an unset record defaults to nadir 0 → "0° from target".
    static func maxDeltaThetaDeg(for record: MealRecord) -> Int {
        let confidence = record.confidence
        var maxDelta = confidence.deltaThetaNadirDeg
        if confidence.hasDeltaThetaObliqueDeg {
            maxDelta = max(maxDelta, confidence.deltaThetaObliqueDeg)
        }
        return Int(maxDelta.rounded())
    }
}

// Controls how `ResultView` is presented. Both paths show the pinned Done
// action row; the only difference is the ⋯ menu contents (Retake+Delete on a
// fresh capture, Delete only from history — Decision 17).
enum ResultPresentation: Equatable {
    case justCaptured
    case historyDetail
}

// Legacy portion-note convention (snaqui portion control, superseded by the
// serving rows — serving-adjust PRD). Read-only now: `parse` keeps existing
// `portion N/M` correction notes seeding the rows on history reopen; new
// adjustments write the `ServingNote` stamp instead.
enum PortionFormat {
    static let countRange = 1...24

    static func factor(eaten: Int, of plate: Int) -> Float {
        Float(eaten) / Float(max(1, plate))
    }

    static func parse(note: String) -> (eaten: Int, plate: Int)? {
        guard note.hasPrefix("portion ") else { return nil }
        let counts = note.dropFirst("portion ".count).split(separator: "/")
        guard
            counts.count == 2,
            let eaten = Int(counts[0]), let plate = Int(counts[1]),
            countRange.contains(eaten), countRange.contains(plate)
        else { return nil }
        return (eaten, plate)
    }
}

enum ResultViewLayout {
    // §20.12 Dynamic Type clamp at AX5: maximum display size 88pt to prevent
    // the carb total running off-screen.
    static let displayMinPoints: CGFloat = 56
    static let displayBasePoints: CGFloat = 72
    static let displayMaxPoints: CGFloat = 88

    static func displayPoints(_ sizeCategory: ContentSizeCategory) -> CGFloat {
        switch sizeCategory {
        case .extraSmall, .small, .medium, .large, .extraLarge:
            return displayBasePoints
        case .extraExtraLarge, .extraExtraExtraLarge:
            return min(displayBasePoints * 1.1, displayMaxPoints)
        default:
            return displayMaxPoints
        }
    }
}

// The plate-fraction quick control's stops (serving-adjust PRD, iOS Req 2):
// the leftovers case is one tap. All is the untouched default and writes
// nothing; the highlighted stop is DERIVED from the rows, so nudging one row
// off a fraction clears the highlight while the other rows stay put.
enum PlateFraction: CaseIterable {
    case all, threeQuarters, half, quarter

    var factor: Double {
        switch self {
        case .all: return 1
        case .threeQuarters: return 0.75
        case .half: return 0.5
        case .quarter: return 0.25
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .threeQuarters: return "¾"
        case .half: return "½"
        case .quarter: return "¼"
        }
    }

    var identifier: String {
        switch self {
        case .all: return "all"
        case .threeQuarters: return "threeQuarters"
        case .half: return "half"
        case .quarter: return "quarter"
        }
    }
}

// Result screen (§6, design-system/pages/result.md, reshaped by the
// serving-adjust PRD). Hero carb total + four-tier confidence pill, a plate
// card where each per-food row is its own adjustment surface — serving-first
// amounts ("≈ 1½ potatoes") with −/+ steppers in the class's household unit,
// grams one tap away — a plate-fraction quick control for the leftovers case,
// a summary card, and dashed macro placeholders. Keeps the calibration
// banner, liquid flag, very-low surface, and placeholder chip.
struct ResultView: View {
    let record: MealRecord
    let store: any PersistenceStore
    var mode: ResultPresentation = .justCaptured
    // Done → dismiss (capture) / pop (history); Retake and Delete live in the
    // ⋯ menu (Decision 17). All defaulted so the capture stack and the
    // Records / Trends history stacks both compile.
    var onDone: () -> Void = {}
    var onRetake: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var photo: UIImage?
    // Decision 19 / Req 7.3: a correction only adds the `corrected` marker;
    // the record itself is never touched. Re-read on `eventsDidChange` while
    // visible, mirroring MealOverviewView (Decision 18).
    @State private var isCorrected = false
    @State private var correctedTotal: Float?
    // Decision 17: "Keep as-is" hides the Very-Low surface for the current
    // view session only — navigating away and back re-shows it (no persistent
    // dismissed flag). `@State` is per-instance, so this resets on each push.
    @State private var keepAsIsDismissed = false
    // Serving-row state (serving-adjust PRD). `pendingGrams` holds the rows'
    // pending amounts (absent key = the original estimate); `recordedGrams`
    // mirrors the state the latest persisted correction implies. The log pill
    // shows only while the two diverge. Seeding happens once per push so a
    // store refresh never stomps an adjustment in progress.
    @State private var servings: [String: SolidServing] = [:]
    @State private var pendingGrams: [String: Double] = [:]
    @State private var recordedGrams: [String: Double] = [:]
    @State private var rowsSeeded = false
    // Per-row gram reveal (iOS Req 3): the row whose amount is an editable
    // gram field right now, plus its text (digits-only clamp convention).
    @State private var editingClassId: String?
    @State private var gramEditText = ""
    @FocusState private var gramFieldFocused: Bool

    // Bundled food database, resolved once per process — the result rows only
    // need read-only `solid_servings` lookups (BenchmarkView precedent).
    private static let foodDatabase: (any FoodDatabase)? = try? GRDBFoodDatabase.bundled()

    // Sub-half-gram differences are invisible at whole-gram display rounding,
    // so they neither show the log pill nor count as a divergence.
    private static let gramEpsilon = 0.5
    // Gram-stepper fallback increment for rows without a serving unit.
    private static let fallbackStepGrams = 10.0
    // Per-row MASS ceiling, matching the benchmark grams bound
    // (`BenchmarkMeal.itemGramsRange`). Deliberately not the 999 g carb-entry
    // convention — a 1 L drink already weighs ~1000 g.
    private static let maxRowGrams = 5000.0

    private var sigma: Float { record.confidence.sigmaMeal }
    private var showsPlaceholderChip: Bool { record.segmenterSource == "dev_stub" }
    // dev_stub numbers are fake — the placeholder chip owns that case — so the
    // real-but-over-reading surfaces (calibration banner, liquid flag) are
    // suppressed there to avoid a contradictory "real over-estimate" claim
    // over placeholder figures (design §3.5).
    private var calibrationBanner: CalibrationBannerState {
        showsPlaceholderChip
            ? .none
            : ResultFormat.calibrationBanner(perClass: record.macros.perClass)
    }
    private var showsLiquidFlag: Bool {
        !showsPlaceholderChip
            && ResultFormat.showsLiquidOverEstimateFlag(record.macros)
    }
    private var showsVeryLowSurface: Bool {
        ResultFormat.showsVeryLowSurface(sigma) && !keepAsIsDismissed
    }
    private var displayPoints: CGFloat { ResultViewLayout.displayPoints(sizeCategory) }

    // MARK: - Row model

    // One adjustable per-food row. Scaling ALWAYS derives from the original
    // estimate held here, so repeated adjustments never compound (iOS Req 4).
    private struct FoodRow: Identifiable {
        let id: String          // class id, e.g. "potato_boiled"
        let displayName: String
        let originalGrams: Double
        let originalCarbsG: Double
        let isLiquid: Bool
    }

    // Sorted by carbs descending (name tie-break) for a stable, meaningful order.
    private var foodRows: [FoodRow] {
        record.macros.perClass
            .map { name, macro in
                FoodRow(
                    id: name,
                    displayName: Self.prettify(name),
                    originalGrams: Double(macro.massG),
                    originalCarbsG: Double(macro.carbsG),
                    isLiquid: macro.isLiquid
                )
            }
            .sorted {
                ($0.originalCarbsG, $1.id) > ($1.originalCarbsG, $0.id)
            }
    }

    // A liquid class or one without a solid_servings row falls back to a gram
    // stepper on the same row — never a dead row (iOS Req 1).
    private func serving(for row: FoodRow) -> SolidServing? {
        row.isLiquid ? nil : servings[row.id]
    }

    private func pendingGramsFor(_ row: FoodRow) -> Double {
        pendingGrams[row.id] ?? row.originalGrams
    }

    private func recordedGramsFor(_ row: FoodRow) -> Double {
        recordedGrams[row.id] ?? row.originalGrams
    }

    // Per-row carbs scale linearly with mass off the ORIGINAL estimate. A
    // zero-mass row cannot scale (nothing to derive a ratio from), so its
    // carbs hold still.
    private func pendingCarbs(_ row: FoodRow) -> Double {
        guard row.originalGrams > 0 else { return row.originalCarbsG }
        return row.originalCarbsG * pendingGramsFor(row) / row.originalGrams
    }

    // Any row diverging from the recorded state arms the log pill (iOS Req 4:
    // edit-by-exception — untouched writes nothing).
    private var adjustmentPending: Bool {
        foodRows.contains { abs(pendingGramsFor($0) - recordedGramsFor($0)) > Self.gramEpsilon }
    }

    // Pending total = original total with the per-class delta folded in, so a
    // record whose stored total differs from its per-class sum (rounding, old
    // records) never jumps just by opening the screen.
    private var pendingTotalCarbsG: Float {
        let originalSum = foodRows.reduce(0.0) { $0 + $1.originalCarbsG }
        let pendingSum = foodRows.reduce(0.0) { $0 + pendingCarbs($1) }
        return Float(Double(record.macros.totalCarbsG) - originalSum + pendingSum)
    }

    // The hero total (snaqui Req 1, superseding Decision 19's original-only
    // hero for this screen): the value that matches what the user is eating —
    // a live preview while adjusting, else the corrected total when one is
    // recorded. The original estimate stays visible on the line beneath.
    private var heroCarbsG: Float {
        adjustmentPending ? pendingTotalCarbsG : (correctedTotal ?? record.macros.totalCarbsG)
    }
    private var showsEstimatedLine: Bool {
        ResultFormat.carbsGrams(heroCarbsG) != ResultFormat.carbsGrams(record.macros.totalCarbsG)
    }

    // The highlighted fraction stop is derived, not stored: highlighted iff
    // every row sits exactly at that fraction of the original estimate, so a
    // per-row nudge clears it while the other rows keep the fraction.
    private var activeFraction: PlateFraction? {
        PlateFraction.allCases.first { fraction in
            foodRows.allSatisfy {
                abs(pendingGramsFor($0) - $0.originalGrams * fraction.factor) <= Self.gramEpsilon
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.captureBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    carbTotal
                    if isCorrected { correctedMarker }
                    ConfidencePill(sigmaMeal: sigma)
                    if showsPlaceholderChip { placeholderChip }
                    switch calibrationBanner {
                    case .full:      calibrationBannerCard(ResultFormat.uncalibratedBannerCopy)
                    case .softened:  calibrationBannerCard(ResultFormat.softenedBannerCopy)
                    case .suppressed, .none: EmptyView()
                    }
                    if showsLiquidFlag { liquidOverEstimateFlag }
                    if showsVeryLowSurface { veryLowSurface }
                    plateCard
                    summaryCard
                    macroPlaceholders
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                // Leave room so the pinned action row never overlaps content.
                .padding(.bottom, 96)
            }
            actionRow
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The number pad has no return key; give the gram reveal a way to
            // put the keyboard away.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { gramFieldFocused = false }
            }
        }
        .onChange(of: gramFieldFocused) { _, focused in
            if !focused { editingClassId = nil }
        }
        .task { await loadPhoto() }
        .task {
            loadServings()
            await observeCorrections()
        }
    }

    // `corrected` marker (Req 7.3). Same string and capsule treatment as
    // MealOverviewView's marker, adapted to the Result screen's dark capture
    // palette.
    private var correctedMarker: some View {
        Text("corrected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.captureChromeBG, in: Capsule())
            .foregroundStyle(Color.captureChromeText.opacity(0.7))
            .accessibilityIdentifier("result.correctedMarker")
    }

    // Hero (§6.1, revised by snaqui Req 1): the carb total the user is eating —
    // scaled live while adjusting, corrected when a correction is recorded,
    // the original estimate otherwise. When the hero diverges from the
    // original, the estimate stays visible on the line beneath, so the
    // full-plate value is never hidden. `g carbs` suffix per the copy inventory.
    private var carbTotal: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(ResultFormat.carbsGrams(heroCarbsG))")
                    .font(.system(size: displayPoints, weight: .heavy, design: .default).monospacedDigit())
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth, value: heroCarbsG)
                Text("g carbs")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.captureChromeText.opacity(0.7))
            }
            .foregroundStyle(Color.captureChromeText)
            if showsEstimatedLine {
                Text("estimated \(ResultFormat.carbsGrams(record.macros.totalCarbsG)) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
                    .accessibilityIdentifier("result.estimatedLine")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.carbsTotal")
    }

    // MARK: - Plate card (serving-adjust PRD, iOS Req 1–4)

    // The per-food rows ARE the adjustment surface: each row steps in its own
    // household serving unit, the plate-fraction control covers the leftovers
    // case in one tap, and the log pill appears only when the pending state
    // diverges from what is recorded.
    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PER FOOD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
                Spacer()
                fractionControl
            }
            .padding(.bottom, 6)
            ForEach(foodRows) { row in
                if row.id != foodRows.first?.id {
                    Rectangle()
                        .fill(Color.captureChromeText.opacity(0.08))
                        .frame(height: 1)
                }
                foodRowView(row)
            }
            if adjustmentPending {
                logPill
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .animation(reduceMotion ? nil : .smooth, value: pendingGrams)
        .animation(reduceMotion ? nil : .smooth, value: adjustmentPending)
        .accessibilityIdentifier("result.breakdown")
    }

    // Plate-fraction quick control (iOS Req 2): one tap scales every row from
    // the ORIGINAL estimate. Monochrome selection — the accent stays reserved
    // for the log pill. Each stop is a Button with its shape inside the label
    // (the dead-pill trap, ui-capture-flow.md).
    private var fractionControl: some View {
        HStack(spacing: 2) {
            ForEach(PlateFraction.allCases, id: \.self) { fraction in
                let isActive = activeFraction == fraction
                Button {
                    applyFraction(fraction)
                } label: {
                    Text(fraction.label)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 30)
                        .frame(height: 26)
                        .padding(.horizontal, 4)
                        .background(
                            isActive ? Color.captureChromeText : .clear,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            isActive ? Color.captureBackground : Color.captureChromeText.opacity(0.7)
                        )
                        .contentShape(Capsule())
                }
                .accessibilityIdentifier("result.fraction.\(fraction.identifier)")
            }
        }
        .padding(2)
        .background(Color.captureBackground.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.fractionControl")
    }

    // One adjustable row: name and live carbs on the first line; the tappable
    // amount (serving-first, grams secondary) with its −/+ steppers on the
    // second. Tapping the amount reveals the editable gram field (iOS Req 3).
    private func foodRowView(_ row: FoodRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.captureChromeText)
                Spacer(minLength: 8)
                Text("\(Int(pendingCarbs(row).rounded())) g carbs")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.75))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            HStack(spacing: 8) {
                if editingClassId == row.id {
                    gramEditor(row)
                } else {
                    amountButton(row)
                }
                Spacer(minLength: 8)
                stepButton("minus", row: row, enabled: pendingGramsFor(row) > 0) {
                    step(row, direction: -1)
                }
                stepButton("plus", row: row, enabled: pendingGramsFor(row) < Self.maxRowGrams) {
                    step(row, direction: 1)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("result.row.\(row.id)")
    }

    // The amount, serving-first: "≈ 1½ potatoes · 87 g" for a class with a
    // serving unit, plain "120 g" for the gram fallback. A Button (not the
    // steppers) so tapping it opens the gram reveal; shape inside the label.
    private func amountButton(_ row: FoodRow) -> some View {
        Button {
            beginGramEdit(row)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let serving = serving(for: row) {
                    let count = ServingMath.displayHalfUnits(
                        ServingMath.servings(grams: pendingGramsFor(row), gramsPerUnit: serving.gramsPerUnit)
                    )
                    Text("≈ \(ServingMath.halfUnitText(count)) \(unitLabel(serving, count: count))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.captureChromeText)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("\(Int(pendingGramsFor(row).rounded())) g")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.captureChromeText.opacity(0.6))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                } else {
                    Text("\(Int(pendingGramsFor(row).rounded())) g")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.captureChromeText)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("result.row.\(row.id).amount")
    }

    // The gram reveal (iOS Req 3): an editable gram value, two-way bound with
    // the serving readout — typing grams re-renders the serving equivalence
    // live, and stepping while editing rewrites the field. Digits-only clamp
    // via the mass sanitiser below (NOT the 3-digit carb-entry one).
    private func gramEditor(_ row: FoodRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("0", text: $gramEditText)
                .keyboardType(.numberPad)
                .focused($gramFieldFocused)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.captureChromeText)
                .frame(width: 52)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.captureBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: gramEditText) { _, newValue in
                    let clamped = Self.clampedRowGrams(newValue)
                    if clamped != newValue { gramEditText = clamped }
                    // Empty is a transient typing state — keep the last value.
                    if let grams = Int(clamped) {
                        pendingGrams[row.id] = Double(grams)
                    }
                }
                .accessibilityIdentifier("result.row.\(row.id).gramField")
            Text("g")
                .font(.caption)
                .foregroundStyle(Color.captureChromeText.opacity(0.6))
            if let serving = serving(for: row) {
                let count = ServingMath.displayHalfUnits(
                    ServingMath.servings(grams: pendingGramsFor(row), gramsPerUnit: serving.gramsPerUnit)
                )
                Text("≈ \(ServingMath.halfUnitText(count)) \(unitLabel(serving, count: count))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
    }

    private func unitLabel(_ serving: SolidServing, count: Double) -> String {
        ServingMath.unitLabel(count: count, singular: serving.unitSingular, plural: serving.unitPlural)
    }

    // Compact ± step control. Sizing and `contentShape` live INSIDE each
    // Button label — the dead-surface trap (ui-capture-flow.md).
    private func stepButton(
        _ symbol: String, row: FoodRow, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color.captureBackground.opacity(0.6), in: Circle())
                .foregroundStyle(Color.captureChromeText.opacity(enabled ? 1 : 0.3))
                .contentShape(Circle())
        }
        .disabled(!enabled)
        .accessibilityIdentifier("result.row.\(row.id).\(symbol)")
    }

    // The single confirm action (iOS Req 4): appears only while the pending
    // state diverges from the recorded one and names exactly what it writes.
    private var logPill: some View {
        Button(action: applyAdjustment) {
            Text("Log \(ResultFormat.carbsGrams(pendingTotalCarbsG)) g")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("result.adjust.apply")
    }

    // MARK: - Adjustment behaviour

    // Mass keypad sanitiser (BenchmarkMealEditorSheet.clampedGrams precedent):
    // strips non-digits, caps at 4 digits, clamps at `maxRowGrams`. Idempotent
    // for any whole-gram value within the cap, so the programmatic
    // `gramEditText` writes in `step()` / `applyFraction` survive the
    // onChange round-trip without corrupting `pendingGrams`.
    private static func clampedRowGrams(_ text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(4))
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(maxRowGrams)))
    }

    private func step(_ row: FoodRow, direction: Double) {
        let stepGrams: Double
        if let serving = serving(for: row) {
            stepGrams = serving.step * serving.gramsPerUnit
        } else {
            stepGrams = Self.fallbackStepGrams
        }
        let next = min(Self.maxRowGrams, max(0, pendingGramsFor(row) + direction * stepGrams))
        pendingGrams[row.id] = next
        if editingClassId == row.id {
            gramEditText = String(Int(next.rounded()))
        }
    }

    private func applyFraction(_ fraction: PlateFraction) {
        for row in foodRows {
            pendingGrams[row.id] = row.originalGrams * fraction.factor
        }
        if let editingClassId, let row = foodRows.first(where: { $0.id == editingClassId }) {
            gramEditText = String(Int(pendingGramsFor(row).rounded()))
        }
    }

    private func beginGramEdit(_ row: FoodRow) {
        editingClassId = row.id
        gramEditText = String(Int(pendingGramsFor(row).rounded()))
        gramFieldFocused = true
    }

    // Persist the adjustment (iOS Req 4): ONE appended correction carrying the
    // scaled total, the per-class carbs scaled per row, and the machine-
    // readable serving-count note. Always scales from the ORIGINAL estimate,
    // so repeated adjustments never compound. The store's `eventsDidChange`
    // tick drives `refreshCorrected`, which folds the new recorded state back
    // in and hides the log pill.
    private func applyAdjustment() {
        gramFieldFocused = false
        var correction = PbUserCorrection()
        correction.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        correction.correctedTotalCarbsG = pendingTotalCarbsG
        correction.correctedPerClass = Dictionary(
            uniqueKeysWithValues: foodRows.map { ($0.id, Float(pendingCarbs($0))) }
        )
        correction.note = ServingNote.note(foodRows.map { row -> (classId: String, amount: ServingNote.Amount) in
            if let serving = serving(for: row) {
                return (classId: row.id, amount: .servings(
                    ServingMath.servings(grams: pendingGramsFor(row), gramsPerUnit: serving.gramsPerUnit)
                ))
            }
            return (classId: row.id, amount: .grams(pendingGramsFor(row)))
        })
        Task {
            try? await store.appendCorrection(mealId: record.id, correction: correction)
        }
    }

    // Summary card (§6.3): thumbnail (with §6.8 fallback), foods count, total
    // mass, and the food-database edition.
    private var summaryCard: some View {
        HStack(spacing: 16) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text("\(foodCount) foods")
                    .font(.headline)
                    .foregroundStyle(Color.captureChromeText)
                Text("\(totalMassGrams) g total")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.8))
                Text("CoFID + AFCD")
                    .font(.caption)
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("result.summaryCard")
    }

    // §6.8 fallback: neutral placeholder when the photo asset is unavailable.
    private var thumbnail: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.captureChromeBG
                    Image(systemName: "fork.knife")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.captureChromeText.opacity(0.5))
                }
                .accessibilityIdentifier("result.thumbnailFallback")
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Dashed, disabled macro placeholders that hold layout space (§6.5).
    private var macroPlaceholders: some View {
        HStack(spacing: 12) {
            macroPlaceholder("Protein — soon")
            macroPlaceholder("Fat — soon")
        }
    }

    private func macroPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.captureChromeText.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.captureChromeText.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
    }

    private var foodCount: Int { record.macros.perClass.count }
    private var totalMassGrams: Int {
        Int(record.macros.perClass.values.reduce(Float(0)) { $0 + $1.massG }.rounded())
    }

    // "white_rice" → "White rice".
    private static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private var placeholderChip: some View {
        Text("Placeholder estimate")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.placeholderBG, in: Capsule())
            .foregroundStyle(Color.placeholderFG)
            .accessibilityIdentifier("result.placeholderChip")
    }

    // Req §7.3 + nutrition5k-calibration Req 8.1/8.3: real-but-uncalibrated
    // honesty surface. The softened tier reuses this existing model-production
    // styling with the softened copy — presentation stays model-production-
    // owned. An up-arrow glyph plus the copy convey the upward
    // (over-estimating) volume bias. The orange `confidenceModerate` rounded
    // card is visually distinct from the yellow `dev_stub` placeholder capsule
    // (which marks fake numbers) and from the grey/red Very-Low surface below.
    private func calibrationBannerCard(_ copy: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
            Text(copy)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.confidenceModerate.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.uncalibratedBanner")
    }

    // Req 8.2: additive liquid over-estimate flag — renders alongside whatever
    // calibration state 8.1 selected, and stands alone for a standalone drink.
    // Same card treatment, distinct glyph, so the two surfaces read as siblings.
    private var liquidOverEstimateFlag: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
            Text(ResultFormat.liquidOverEstimateFlagCopy)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.confidenceModerate.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.liquidOverEstimateFlag")
    }

    // Decision 17 / Req §9.3: surfaces below σ_meal < 0.20 with two-line
    // explanation + Retake / Keep as-is. The surface is in-session-only —
    // navigating away and back re-shows it. The meal is already persisted by
    // the capture pipeline, so "Keep as-is" only dismisses the surface; it
    // does not write any "dismissed" flag.
    private var veryLowSurface: some View {
        VStack(spacing: 12) {
            Text("This estimate may be wrong by orders of magnitude.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.captureChromeText)
                .multilineTextAlignment(.center)
            Text("Capture was at \(ResultFormat.maxDeltaThetaDeg(for: record))° from target.")
                .font(.caption)
                .foregroundStyle(Color.captureChromeText.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button(action: onRetake) {
                    Text("Retake")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                        .foregroundStyle(Color.captureChromeText)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("result.veryLow.retake")

                Button { keepAsIsDismissed = true } label: {
                    Text("Keep as-is")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.captureBackground)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("result.veryLow.keepAsIs")
            }
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("result.veryLowSurface")
    }

    // §6.6/6.7 revised by the serving-adjust PRD: Done (prominent) + ⋯ menu
    // (Retake + Delete on a fresh capture, Delete only from history —
    // Decision 17). The Adjust button is retired — the per-food rows above
    // are the adjustment surface.
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.captureBackground)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("result.done")

            Menu {
                if mode == .justCaptured {
                    Button("Retake", action: onRetake)
                }
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.captureChromeText)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("result.menu")
        }
    }

    // MARK: - Loading

    private func loadPhoto() async {
        // Shared with Records / Meal overview via the extracted loader (§6.8).
        self.photo = await MealPhotoLoader.loadImage(assetID: record.photoAssetID)
    }

    // Serving definitions for this record's solid classes, one lookup each —
    // synchronous reads on the shared bundled handle.
    private func loadServings() {
        guard servings.isEmpty, let database = Self.foodDatabase else { return }
        var resolved: [String: SolidServing] = [:]
        for row in foodRows where !row.isLiquid {
            if let serving = database.solidServing(for: row.id) {
                resolved[row.id] = serving
            }
        }
        servings = resolved
    }

    // Mirror of MealOverviewView.observeCorrections (Decision 18): refresh once
    // on appear, then whenever a correction lands while the view is visible.
    private func observeCorrections() async {
        await refreshCorrected()
        for await _ in store.eventsDidChange {
            await refreshCorrected()
        }
    }

    private func refreshCorrected() async {
        let corrections = (try? await store.corrections(for: record.id)) ?? []
        isCorrected = !corrections.isEmpty
        // The corrected total and the row seeds derive from the SAME
        // correction — the latest — so a degenerate history (trailing
        // correction without a total) cannot mix two corrections. When the
        // latest lacks a total, the hero falls back to the original estimate,
        // consistent with `recordedGramsState`'s own fallbacks.
        let latest = corrections.last
        correctedTotal = latest?.correctedTotalCarbsGOneof != nil
            ? latest?.correctedTotalCarbsG
            : nil
        recordedGrams = recordedGramsState(from: latest)
        // Seed the rows once per push (iOS Req 4: history re-entry resumes
        // from the latest correction); later refreshes only update the
        // recorded state so they cannot stomp an adjustment in progress.
        if !rowsSeeded {
            rowsSeeded = true
            pendingGrams = recordedGrams
        }
    }

    // The per-row grams the latest correction implies (empty = the original
    // estimate). Scaling always re-derives from the ORIGINAL, never from a
    // previous correction, so adjustments cannot compound:
    //   1. a `servings` stamp restores the recorded amounts directly;
    //   2. a legacy `portion N/M` stamp still parses and seeds (PRD Req 4);
    //   3. otherwise per-class carb ratios recover row grams (old manual
    //      corrections), with a uniform total ratio as the last resort.
    private func recordedGramsState(from correction: PbUserCorrection?) -> [String: Double] {
        guard let correction else { return [:] }
        if let amounts = ServingNote.parse(correction.note) {
            return Dictionary(uniqueKeysWithValues: foodRows.map { row in
                switch amounts[row.id] {
                case .servings(let count)?:
                    if let serving = servings[row.id] {
                        return (row.id, ServingMath.grams(servings: count, gramsPerUnit: serving.gramsPerUnit))
                    }
                    return (row.id, row.originalGrams)
                case .grams(let grams)?:
                    return (row.id, grams)
                case nil:
                    return (row.id, row.originalGrams)
                }
            })
        }
        if let portion = PortionFormat.parse(note: correction.note) {
            let factor = Double(PortionFormat.factor(eaten: portion.eaten, of: portion.plate))
            return Dictionary(uniqueKeysWithValues: foodRows.map { ($0.id, $0.originalGrams * factor) })
        }
        if !correction.correctedPerClass.isEmpty {
            return Dictionary(uniqueKeysWithValues: foodRows.map { row in
                guard row.originalCarbsG > 0, let corrected = correction.correctedPerClass[row.id] else {
                    return (row.id, row.originalGrams)
                }
                return (row.id, row.originalGrams * Double(corrected) / row.originalCarbsG)
            })
        }
        if case .correctedTotalCarbsG(let total)? = correction.correctedTotalCarbsGOneof,
           record.macros.totalCarbsG > 0 {
            let factor = Double(total / record.macros.totalCarbsG)
            return Dictionary(uniqueKeysWithValues: foodRows.map { ($0.id, $0.originalGrams * factor) })
        }
        return [:]
    }
}
