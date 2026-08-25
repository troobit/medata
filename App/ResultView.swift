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

// `ResultPresentation` is gone (specs/ui/meal-review task 15): the
// `.justCaptured` presentation is superseded by MealReviewView, so ResultView
// now serves only the Records/Graph history read path.

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

// The plate-fraction stops (`PlateFraction`) and the shared serving-row
// controls live in App/ServingRows.swift (specs/ui/shared-meal-components
// Req 1): one implementation renders the amount button, gram editor and step
// buttons here and on MealReviewView. The highlighted stop on THIS surface is
// DERIVED from the rows, so nudging one row off a fraction clears the
// highlight while the other rows stay put.

// Result screen (§6, design-system/pages/result.md, reshaped by the
// serving-adjust PRD; capture-step presentation superseded by
// specs/ui/meal-review — this is the Records/Graph history read path only).
// Hero carb total + four-tier confidence pill, a plate card where each
// per-food row is its own adjustment surface — serving-first amounts
// ("≈ 1½ potatoes") with −/+ steppers in the class's household unit, grams
// one tap away — a plate-fraction quick control for the leftovers case, a
// summary card, and dashed macro placeholders. Keeps the calibration banner,
// liquid flag, and placeholder chip; the very-low retake surface is gated to
// the review path (its retake was already inert from history).
struct ResultView: View {
    let record: MealRecord
    let store: any PersistenceStore
    // Done pops one level; Delete lives in the ⋯ menu (Decision 17).
    var onDone: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var photo: UIImage?
    // Decision 19 / Req 7.3: a correction only adds the `corrected` marker;
    // the record itself is never touched. Re-read on `eventsDidChange` while
    // visible, mirroring MealOverviewView (Decision 18).
    @State private var isCorrected = false
    @State private var correctedTotal: Float?
    // The recorded dose suggestion for this meal (insulin-dosing Req 6.10),
    // loaded once per push; nil for meals that never produced one.
    @State private var suggestion: DoseSuggestionRecord?
    // Capture-born quick-add draft (manual-carb-intake Req 8): set by the
    // ellipsis-menu action, presented as the same edit sheet a hand-authored
    // preset uses (Req 8.2).
    @State private var presetDraft: QuickPreset?
    // Predicted class id → corrected class id from the meal's corrections
    // (meal-review Req 8.7): every surface that names a relabelled food names
    // the corrected one, not the predicted one.
    @State private var correctedClassIds: [String: String] = [:]
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
    // Step increment and per-row mass ceiling: ServingStepLogic
    // (App/ServingRows.swift), shared with MealReviewView.

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
                    displayName: MedataFormat.prettify(correctedClassIds[name] ?? name),
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
                    if isCorrected {
                        CorrectedMarker(palette: .capture, identifier: "result.correctedMarker")
                    }
                    ConfidencePill(sigmaMeal: sigma)
                    if showsPlaceholderChip { placeholderChip }
                    switch calibrationBanner {
                    case .full:      calibrationBannerCard(ResultFormat.uncalibratedBannerCopy)
                    case .softened:  calibrationBannerCard(ResultFormat.softenedBannerCopy)
                    case .suppressed, .none: EmptyView()
                    }
                    if showsLiquidFlag { liquidOverEstimateFlag }
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
        .task { suggestion = try? await store.doseSuggestion(forSourceEventID: record.id) }
        .task {
            loadServings()
            await observeCorrections()
        }
        .sheet(item: $presetDraft) { draft in
            QuickPresetEditSheet(store: store, preset: draft, isNew: true)
        }
    }

    // Hero (§6.1, revised by snaqui Req 1): the carb total the user is eating —
    // scaled live while adjusting, corrected when a correction is recorded,
    // the original estimate otherwise. When the hero diverges from the
    // original, the estimate stays visible on the line beneath, so the
    // full-plate value is never hidden. `g carbs` suffix per the copy inventory.
    private var carbTotal: some View {
        VStack(spacing: 4) {
            CarbAmountText(
                carbs: ResultFormat.carbsGrams(heroCarbsG),
                pointSize: displayPoints,
                palette: .capture,
                animates: Double(heroCarbsG),
                suffixFont: .title3.weight(.semibold),
                spacing: 8
            )
            // Estimated plate mass beside the hero (specs/ui/mass-readout):
            // the kitchen-scales validation number — a scale reads total mass,
            // not carbs, so the mass estimate must be visible without
            // scrolling to the summary card. Tracks pending adjustments the
            // same way the hero carbs do.
            Text("≈ \(Int(pendingTotalMassG.rounded())) g on plate")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.captureChromeText.opacity(0.75))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth, value: pendingTotalMassG)
                .accessibilityIdentifier("result.massLine")
            // History readout (insulin-dosing Req 6.10/6.11): the RECORDED
            // suggestion for this meal, verbatim from its ledger row — never a
            // recomputation, because the band, ratio and insulin-on-board
            // belong to the moment the number was produced. Absent row,
            // absent line; "suggested" labels a past hypothesis
            // (design-direction §6.3) and is not counsel.
            if let line = RecordedSuggestion.line(suggestion) {
                Text(line)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.75))
                    .accessibilityLabel(RecordedSuggestion.spokenLine(suggestion) ?? line)
                    .accessibilityIdentifier("result.doseSuggestion")
            }
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
                PlateFractionButton(
                    fraction: fraction,
                    isActive: activeFraction == fraction,
                    minWidth: 30,
                    height: 26,
                    inactiveBackground: .clear,
                    inactiveTextOpacity: 0.7,
                    idPrefix: "result"
                ) {
                    applyFraction(fraction)
                }
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
                    ServingGramEditor(
                        text: $gramEditText,
                        grams: pendingGramsFor(row),
                        serving: serving(for: row),
                        idPrefix: "result.row.\(row.id)",
                        focus: $gramFieldFocused
                    ) { grams in
                        pendingGrams[row.id] = grams
                    }
                } else {
                    ServingAmountButton(
                        grams: pendingGramsFor(row),
                        serving: serving(for: row),
                        idPrefix: "result.row.\(row.id)"
                    ) {
                        beginGramEdit(row)
                    }
                }
                Spacer(minLength: 8)
                ServingStepButton(
                    symbol: "minus",
                    enabled: pendingGramsFor(row) > 0,
                    idPrefix: "result.row.\(row.id)"
                ) {
                    step(row, direction: -1)
                }
                ServingStepButton(
                    symbol: "plus",
                    enabled: pendingGramsFor(row) < ServingStepLogic.maxRowGrams,
                    idPrefix: "result.row.\(row.id)"
                ) {
                    step(row, direction: 1)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("result.row.\(row.id)")
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

    private func step(_ row: FoodRow, direction: Double) {
        let next = ServingStepLogic.stepped(
            from: pendingGramsFor(row), serving: serving(for: row), direction: direction
        )
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

    // Live total mass for the hero mass line: the per-row pending grams sum,
    // which equals the original estimate until the user adjusts a row.
    private var pendingTotalMassG: Double {
        foodRows.reduce(0) { $0 + pendingGramsFor($1) }
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
        // Dark-on-orange: white caption text on this fill is ~2.8:1, under
        // MASTER.md's >=4.5:1 budget (ui-ux review 2026-08-25); black matches
        // the placeholder chip's dark-on-bright pairing.
        .foregroundStyle(Color.captureBackground)
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
        // Dark-on-orange: white caption text on this fill is ~2.8:1, under
        // MASTER.md's >=4.5:1 budget (ui-ux review 2026-08-25); black matches
        // the placeholder chip's dark-on-bright pairing.
        .foregroundStyle(Color.captureBackground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.confidenceModerate.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.liquidOverEstimateFlag")
    }

    // The very-low retake surface moved to the review path (meal-review task
    // 15): its retake button was already inert from history (`onRetake`
    // defaulted to a no-op), so removing it here makes a dead affordance
    // explicit rather than changing behaviour.

    // §6.6/6.7 revised by the serving-adjust PRD: Done (prominent) + ⋯ menu
    // (Delete only — the fresh-capture Retake lives on the review surface).
    // The Adjust button is retired — the per-food rows above are the
    // adjustment surface.
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
                // Capture-born preset from the history read path
                // (manual-carb-intake Req 8.1): freezes the displayed total —
                // adjustments and corrections included (Req 8.3).
                Button("Save as quick-add") {
                    Task {
                        let presets = (try? await store.quickPresets()) ?? []
                        presetDraft = quickPresetDraft(
                            displayedCarbsG: heroCarbsG,
                            foodNames: foodRows.map(\.displayName),
                            sourceMealID: record.id,
                            existingPresets: presets
                        )
                    }
                }
                .accessibilityIdentifier("result.saveAsQuickAdd")
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
        // Corrected names fold across the history: a later amount-only
        // correction (empty map) must not erase an earlier relabel (Req 8.7).
        correctedClassIds = corrections.reduce(into: [:]) { acc, correction in
            acc.merge(correction.correctedClassIds) { _, newer in newer }
        }
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
