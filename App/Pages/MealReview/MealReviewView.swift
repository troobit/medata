import Foods
import Pipeline
import SwiftUI
import UIKit

// The single review surface (specs/ui/meal-review Req 1): the captured photo
// with its detected areas outlined, the meal total, one editable row per
// detected food, and the primary action — one screen replacing
// SegmentationReviewView + ResultView(.justCaptured). Behaviour lives in
// MealReviewModel; this is composition only.
//
// Layout order (design "Surface composition"): photo + outlines ~40% fixed,
// total + confidence pill + corrected marker, primary action, scale control —
// all above the scroll boundary (Req 6.6). Accessory signals collapse to one
// expandable line below the boundary, then the food rows. When σ < 0.20 the
// very-low surface owns the fold and suspends the Req 6.6 guarantee: a retake
// decision precedes any adjustment.
//
// No reassurance, disclaimer or data-preservation copy (Req 10.7).
struct MealReviewView: View {
    let record: MealRecord
    let store: any PersistenceStore
    var onRecord: () -> Void = {}
    var onRetake: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var model: MealReviewModel
    @State private var photo: UIImage?
    @State private var contours: MaskContourSet?
    // "Keep as-is" hides the very-low surface for this session only
    // (ResultView precedent); @State resets per push.
    @State private var veryLowDecided = false
    @State private var accessoryExpanded = false
    // Per-row gram reveal (Req 6.1/6.7, serving-adjust item 3).
    @State private var editingClassId: String?
    @State private var gramEditText = ""
    @FocusState private var gramFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The dose readout is computed HERE, on appearance and on every correction
    // (specs/data/insulin-dosing Decision 19): no shared readout state, so this
    // surface cannot show another surface's leftovers.
    @State private var doseReadout: DoseReadout?
    @State private var showingWorking = false
    // Optional: this surface is also reachable from history routes, and the
    // seed holder is only injected on the live capture path (it is owned by
    // AppRoot). Absent, nothing is armed.
    @Environment(DoseSeedHolder.self) private var doseSeeds: DoseSeedHolder?
    // Capture-born quick-add draft (manual-carb-intake Req 8): set by the
    // menu action, presented as the same edit sheet a hand-authored preset
    // uses (Req 8.2).
    @State private var presetDraft: QuickPreset?
    @State private var presetName = ""

    // Bundled food database, resolved once per process (ResultView precedent).
    private static let foodDatabase: (any FoodDatabase)? = try? GRDBFoodDatabase.bundled()

    // Step increment and per-row mass ceiling: ServingStepLogic
    // (App/ServingRows.swift), shared with ResultView.

    init(
        record: MealRecord,
        store: any PersistenceStore,
        onRecord: @escaping () -> Void = {},
        onRetake: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.record = record
        self.store = store
        self.onRecord = onRecord
        self.onRetake = onRetake
        self.onDelete = onDelete
        _model = State(initialValue: MealReviewModel(
            record: record, store: store, database: Self.foodDatabase
        ))
    }

    private var sigma: Float { record.confidence.sigmaMeal }
    private var showsVeryLowSurface: Bool {
        ResultFormat.showsVeryLowSurface(sigma) && !veryLowDecided
    }

    // The input shape the suggester takes (specs/data/insulin-dosing design.md,
    // `DoseSubject`): the carbohydrate total, the meal's own instant, and the
    // meal's own event id — which the offset query needs so this meal never
    // offsets its own pre-bolus (Req 4.8). No fat, protein or confidence term
    // travels: nothing is recorded and none of them enters the arithmetic
    // (Req 3.8, Decision 18).
    private var doseSubject: DoseSubject {
        DoseSubject(
            carbsG: model.pendingTotalCarbsG,
            instant: record.createdAt,
            sourceEventID: record.id
        )
    }

    // Computed where it renders (Decision 19). The suggestion is derived from
    // the total the user will actually record (Req 3.2), so it re-derives with
    // every correction — tapping 1/2 on the plate scale rolls the carb total,
    // the plate mass and the dose figure together, which teaches the divisor
    // better than a caption could.
    private func refreshDose() async {
        doseReadout = await DoseComputation.readout(for: doseSubject, store: store)
    }

    #if FIELD_LOOP
    private var fieldEstimateSnapshot: EstimateSnapshot {
        EstimateSnapshot(
            foods: model.activeFoods.map { food in
                EstimateSnapshotFood(
                    classID: food.currentClassId,
                    displayName: MealReviewModel.prettify(food.currentClassId),
                    massG: food.currentMassG,
                    carbsG: food.currentCarbsG
                )
            },
            displayedTotalCarbsG: model.pendingTotalCarbsG,
            displayedTotalMassG: model.pendingTotalMassG
        )
    }
    #endif

    private var palette: ClassPalette { .standard }
    private var colourTable: ClassColourTable { ClassColourTable(version: record.paletteVersion) }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                photoSection(maxHeight: proxy.size.height * 0.40)
                totalRow
                primaryAction
                if showsVeryLowSurface {
                    veryLowSurface
                } else {
                    scaleControl
                }
                // No rule here: Intake separates its groups with space alone,
                // and the register already changes at this line from fixed
                // head to scrolling rows (Req 10.1, UI review 2026-09-04).
                ScrollView {
                    VStack(spacing: 10) {
                        accessoryLine
                        ForEach(model.activeFoods) { food in
                            foodRow(food)
                        }
                        ForEach(model.rejectedFoods) { food in
                            rejectedRow(food)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.captureBackground.ignoresSafeArea())
        #if FIELD_LOOP
        // Meal-linked note context (ml-feedback-loop Req 2.1 / 2.4). The
        // snapshot is the CURRENT displayed state — post-relabel, post-scale,
        // post-gram-edit — recomputed on every body pass, so a note saved after
        // three corrections records the three corrections and not the raw
        // prediction. The meal id is the join key; the outcome row carries it,
        // so the Mac side reaches the bundle stem from here without this
        // surface having to know an attempt timestamp it was never given.
        .fieldScreen(
            "meal.review",
            meal: FieldNoteMealLink(mealID: record.id),
            estimate: fieldEstimateSnapshot
        )
        #endif
        // On appearance and on every correction — see `refreshDose()`.
        .task { await refreshDose() }
        .onChange(of: model.pendingTotalCarbsG) {
            Task { await refreshDose() }
        }
        .quickAddNamePrompt(
            draft: $presetDraft,
            name: $presetName,
            store: store,
            identifier: "review.quickAdd.name"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Retake and delete (Req 1.3): both discard the recorded meal and
            // set capture_abandoned on every row before the delete lands.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Capture-born preset (manual-carb-intake Req 8.1): the
                    // draft freezes the DISPLAYED total at the moment of the
                    // tap (Req 8.3); no confidence, calibration or dev_stub
                    // gate (Req 8.5, Decision 12).
                    Button("Save as quick-add") {
                        Task {
                            let presets = (try? await store.quickPresets()) ?? []
                            let draft = quickPresetDraft(
                                displayedCarbsG: Float(model.pendingTotalCarbsG),
                                foodNames: model.activeFoods.map {
                                    MealReviewModel.prettify($0.currentClassId)
                                },
                                sourceMealID: record.id,
                                existingPresets: presets
                            )
                            // Name seeded before the prompt is armed: setting
                            // the draft is what presents it (Decision 13).
                            presetName = draft.name
                            presetDraft = draft
                        }
                    }
                    .accessibilityIdentifier("review.saveAsQuickAdd")
                    Button("Retake") { discard(then: onRetake) }
                    Button("Delete", role: .destructive) { discard(then: onDelete) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("review.menu")
            }
            // The number pad has no return key (ResultView precedent).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { gramFieldFocused = false }
            }
        }
        .onChange(of: gramFieldFocused) { _, focused in
            if !focused { editingClassId = nil }
        }
        .sheet(isPresented: alternativesPresented) {
            if let classId = model.alternativesFor {
                RelabelSheet(model: model, classId: classId)
            }
        }
        .task { await model.start() }
        .task { photo = await MealPhotoLoader.loadImage(assetID: record.photoAssetID) }
        .task { await loadContours() }
    }

    private func discard(then completion: @escaping () -> Void) {
        Task {
            await model.discard()
            completion()
        }
    }

    private var alternativesPresented: Binding<Bool> {
        Binding(
            get: { model.alternativesFor != nil },
            set: { presented in
                if !presented { Task { await model.dismissAlternatives() } }
            }
        )
    }

    // MARK: - Photo + outlines (Req 2)

    // The photo area keeps the mask's 4:3 aspect so contour unit coordinates
    // map linearly onto the frame; capped at ~40% of the surface height.
    private func photoSection(maxHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * 4 / 3)
            let size = CGSize(width: width, height: width * 3 / 4)
            ZStack {
                photoLayer
                if let contours {
                    overlayLayer(contours: contours, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: maxHeight)
        .accessibilityIdentifier("review.photo")
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            // Req 1.6: rows and total render without the photo; never an error.
            ZStack {
                Color.captureChromeBG
                Image(systemName: "fork.knife")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.captureChromeText.opacity(0.5))
            }
            .accessibilityIdentifier("review.photoFallback")
        }
    }

    // Foods that have contours in the decoded set, in badge order.
    private func contouredFoods(_ set: MaskContourSet) -> [(food: ReviewFood, loops: [MaskContour])] {
        model.foods.compactMap { food in
            guard let index = model.classIndex(for: food.classId),
                  let loops = set.contoursByClassId[index], !loops.isEmpty else { return nil }
            return (food, loops)
        }
    }

    private func overlayLayer(contours set: MaskContourSet, size: CGSize) -> some View {
        let items = contouredFoods(set)
        return ZStack {
            // Selection dims outside the selected class via an even-odd path
            // (Req 2.5) — the selected areas stay the highest-contrast content.
            if let selected = model.selected,
               let selectedLoops = items.first(where: { $0.food.classId == selected })?.loops {
                DimOutsideShape(loops: selectedLoops)
                    .fill(Color.captureScrim, style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
            }
            ForEach(items, id: \.food.classId) { item in
                let rejected = item.food.flags.rejected
                MaskContourShape(loops: item.loops)
                    .stroke(
                        strokeColour(for: item.food),
                        lineWidth: rejected ? 1 : 2  // reduced weight when rejected (Req 4.2)
                    )
                    .opacity(rejected ? 0.5 : 1)
                    .allowsHitTesting(false)
                if let badge = model.badgeNumber(for: item.food.classId),
                   let largest = item.loops.max(by: { $0.area < $1.area }) {
                    contourBadge(number: badge, food: item.food)
                        .position(
                            x: largest.centroid.x * size.width,
                            y: largest.centroid.y * size.height
                        )
                }
            }
            // VoiceOver shadow layer (Req 2.6): one element per detected food,
            // focus ring following the contour rather than a bounding box.
            accessibilityShadow(items: items)
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                handlePhotoTap(at: value.location, items: items, size: size)
            }
        )
    }

    private func strokeColour(for food: ReviewFood) -> Color {
        guard let index = model.classIndex(for: food.classId) else {
            return Color.captureChromeText
        }
        let colour = colourTable.colour(forClassId: index)
        return Color(red: colour.red, green: colour.green, blue: colour.blue)
    }

    // Numbered badge at the largest contour's centroid — the non-colour
    // identity channel between photo and row (Req 2.2, 2.3). A rejected
    // food's badge is struck through (Req 4.2).
    private func contourBadge(number: Int, food: ReviewFood) -> some View {
        Text("\(number)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .strikethrough(food.flags.rejected)
            .foregroundStyle(Color.captureChromeText)
            .frame(width: 22, height: 22)
            .background(Color.captureScrim, in: Circle())
            .overlay(Circle().stroke(strokeColour(for: food), lineWidth: 1.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func accessibilityShadow(
        items: [(food: ReviewFood, loops: [MaskContour])]
    ) -> some View {
        ZStack {
            ForEach(items, id: \.food.classId) { item in
                Color.clear
                    .contentShape(.accessibility, MaskContourShape(loops: item.loops))
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityName(for: item.food))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        model.select(classId: item.food.classId)
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private func accessibilityName(for food: ReviewFood) -> String {
        let predicted = MealReviewModel.prettify(food.predicted.classID)
        if food.flags.rejected { return "\(predicted), rejected" }
        if food.flags.classCorrected, let corrected = food.corrected?.classID, !corrected.isEmpty {
            return "\(predicted), corrected to \(MealReviewModel.prettify(corrected))"
        }
        return predicted
    }

    // Tap on a marked area selects that food and its row (Req 2.4); where a
    // class's largest contour is under 44 pt its row is the hit target, so a
    // miss here simply deselects.
    private func handlePhotoTap(
        at location: CGPoint,
        items: [(food: ReviewFood, loops: [MaskContour])],
        size: CGSize
    ) {
        let rect = CGRect(origin: .zero, size: size)
        for item in items {
            let path = MaskContourShape(loops: item.loops).path(in: rect)
            if path.contains(location, eoFill: true) {
                model.select(classId: item.food.classId)
                return
            }
        }
        model.select(classId: nil)
    }

    private func loadContours() async {
        // Emit contours only for classes present in macros.perClass (Req 2.8);
        // presentClassIds still reports every raster class for the banners.
        let included = Set(model.foods.compactMap { model.classIndex(for: $0.classId) })
        contours = await MaskContourCache.shared.contours(
            store: store,
            mealId: record.id,
            paletteVersion: record.paletteVersion,
            includedClassIds: included
        )
    }

    // MARK: - Total row (Req 1.4, 8.6)

    private var totalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                CarbAmountText(
                    carbs: Int(model.pendingTotalCarbsG.rounded()),
                    pointSize: 44,
                    palette: .capture,
                    animates: Double(model.pendingTotalCarbsG),
                    suffixFont: .title3.weight(.semibold),
                    spacing: 10
                )
                if model.hasActualCorrections {
                    CorrectedMarker(palette: .capture, identifier: "review.correctedMarker")
                }
                Spacer()
                // The dose takes the pill; confidence is its colour, and is
                // named in words in the working (Req 6.12). Tapping opens the
                // same sheet the line used to open — the pill IS the
                // affordance, which is why the dotted underline went.
                if let doseReadout {
                    DosePill(
                        unitsLabel: doseReadout.unitsLabel,
                        sigmaMeal: sigma,
                        animates: Double(doseReadout.units)
                    )
                    .onTapGesture { showingWorking = true }
                    .accessibilityAction(named: "Show working") { showingWorking = true }
                }
            }
            // Field validation reads a kitchen scale, and a scale reads mass
            // not carbs — the total must be visible at the moment of capture
            // (mass-readout smolspec; same treatment as result.massLine).
            // The dose suggestion appends to this line rather than taking a
            // row of its own, so nothing above the scroll boundary moves
            // (specs/ui/meal-review Req 6.6) and the plate control stays
            // visible without scrolling.
            // Mass only. The dose left this line for the pill above, so the
            // measured quantity and the quantity derived from it are no
            // longer rendered as two peers on one line.
            MealTotalSecondLine(massG: model.pendingTotalMassG)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.total")
        // Presented from the row rather than from `body`, so the surface's
        // two sheets (this and the quick-add draft) never share one modifier
        // site.
        .sheet(isPresented: $showingWorking) {
            if let doseReadout {
                DoseWorkingSheet(readout: doseReadout, sigmaMeal: sigma)
            }
        }
    }


    // MARK: - Primary action (Req 7.1–7.3)

    // One tap records the meal as displayed and dismisses — the meal is
    // already persisted and every correction applied live, so this only
    // flushes and leaves (design: record() dismisses only). Shape inside the
    // label (the dead-pill trap, ui-capture-flow.md).
    private var primaryAction: some View {
        Button {
            Task {
                await model.record()
                // Arms the seed the dose sheet reads when it next opens
                // through the existing route (Req 6.4). Nothing is presented
                // from here: a dose stays a separate, deliberate act, and the
                // capture path is still shutter -> Record. A `0 U` result arms
                // nothing — `DoseReadout.seed` is nil below 1 U (Req 3.4).
                await refreshDose()
                if let seed = doseReadout?.seed { doseSeeds?.arm(seed) }
                onRecord()
            }
        } label: {
            Text("Record \(Int(model.pendingTotalCarbsG.rounded())) g")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("review.record")
    }

    // MARK: - Whole-meal scale (Req 6.3–6.6)

    private var scaleControl: some View {
        // Unlabelled: all-caps is the capture CHROME register in this app
        // (the mode and telemetry capsules), and no content surface uses it.
        // The stops sit directly under a photograph of a plate, so the label
        // was naming what the picture already says, at the cost of the row's
        // leading width (Req 10.1/10.4, UI review 2026-09-04).
        HStack(spacing: 8) {
            Spacer()
            ForEach(PlateFraction.allCases, id: \.self) { fraction in
                PlateFractionButton(
                    fraction: fraction,
                    isActive: model.scale == fraction,
                    minWidth: 44,
                    height: 34,
                    inactiveBackground: Color.captureChromeBG,
                    inactiveTextOpacity: 0.8,
                    idPrefix: "review"
                ) {
                    Task { await model.setScale(fraction) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plate")
        .accessibilityIdentifier("review.scaleControl")
    }

    // MARK: - Very-low surface (Req 1.4; design: owns the fold)

    private var veryLowSurface: some View {
        VStack(spacing: 10) {
            Text("This estimate may be wrong by orders of magnitude.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.captureChromeText)
                .multilineTextAlignment(.center)
            Text("Capture was at \(ResultFormat.maxDeltaThetaDeg(for: record))° from target.")
                .font(.caption)
                .foregroundStyle(Color.captureChromeText.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button {
                    discard(then: onRetake)
                } label: {
                    Text("Retake")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                        .foregroundStyle(Color.captureChromeText)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("review.veryLow.retake")

                Button { veryLowDecided = true } label: {
                    Text("Keep as-is")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.captureChromeText)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("review.veryLow.keepAsIs")
            }
        }
        .accessibilityIdentifier("review.veryLowSurface")
    }

    // MARK: - Accessory line (Req 1.4, 1.5)

    private struct AccessorySignal: Identifiable {
        let id: String
        let symbol: String
        let shortLabel: String
        let copy: String
    }

    private var accessorySignals: [AccessorySignal] {
        var out: [AccessorySignal] = []
        switch ResultFormat.calibrationBanner(perClass: record.macros.perClass) {
        case .full:
            out.append(AccessorySignal(
                id: "calibration", symbol: "arrow.up.circle.fill",
                shortLabel: "Uncalibrated", copy: ResultFormat.uncalibratedBannerCopy
            ))
        case .softened:
            out.append(AccessorySignal(
                id: "calibration", symbol: "arrow.up.circle.fill",
                shortLabel: "Population-calibrated", copy: ResultFormat.softenedBannerCopy
            ))
        case .suppressed, .none:
            break
        }
        if ResultFormat.showsLiquidOverEstimateFlag(record.macros) {
            out.append(AccessorySignal(
                id: "liquid", symbol: "cup.and.saucer.fill",
                shortLabel: "Drink over-estimate", copy: ResultFormat.liquidOverEstimateFlagCopy
            ))
        }
        let present = contours?.presentClassIds ?? []
        if present.contains(palette.unknownFood) {
            out.append(AccessorySignal(
                id: "unknown", symbol: "questionmark.circle.fill",
                shortLabel: "Unknown region", copy: "Unknown region · counted as unknown carbs"
            ))
        }
        if present.contains(palette.unsupportedLiquid) {
            out.append(AccessorySignal(
                id: "unsupportedLiquid", symbol: "drop.fill",
                shortLabel: "Liquid not estimated", copy: "Liquid · not estimated"
            ))
        }
        return out
    }

    // One expandable line so a meal carrying every signal cannot push the
    // scale control off-screen (design layout note). Icon + text, never
    // colour alone (Req 1.5).
    @ViewBuilder
    private var accessoryLine: some View {
        let signals = accessorySignals
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth) { accessoryExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: signals.count == 1
                            ? signals[0].symbol : "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.confidenceModerate)
                        Text(signals.map(\.shortLabel).joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: accessoryExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    // Intake's card grammar, with the SYMBOL carrying the
                    // colour instead of the plate. Two things this fixes at
                    // once: a second saturated fill was competing with
                    // `Record N g` for the one-prominent-action role Req 10.1
                    // names, and white caption text on the orange fill
                    // measured ~2.8:1 against MASTER.md's >=4.5:1 budget
                    // (ui-ux review 2026-08-25, closed 2026-09-04). White on
                    // captureChromeBG composites to ~18:1. Still icon AND
                    // text, so Req 1.5 (never colour alone) is untouched.
                    .foregroundStyle(Color.captureChromeText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("review.accessoryLine")
                if accessoryExpanded {
                    ForEach(signals) { signal in
                        HStack(spacing: 8) {
                            Image(systemName: signal.symbol)
                            Text(signal.copy)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.captureChromeText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - Food rows (Req 3.10, 6.1, 10.1)

    // IntakeView's grouped-row metrics restated on the capture palette
    // (Req 10.1/10.2): 12 pt corner radius on an elevated surface, 12 pt
    // vertical padding, .headline over .caption.monospacedDigit().
    private func foodRow(_ food: ReviewFood) -> some View {
        let isSelected = model.selected == food.classId
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                rowBadge(food)
                nameLine(food)
                Spacer(minLength: 8)
                Text("\(Int(food.currentCarbsG.rounded())) g carbs")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.75))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
            HStack(spacing: 8) {
                if editingClassId == food.classId {
                    ServingGramEditor(
                        text: $gramEditText,
                        grams: food.currentMassG,
                        serving: model.solidServing(for: food.classId),
                        idPrefix: "review.row.\(food.classId)",
                        focus: $gramFieldFocused
                    ) { grams in
                        model.setAmount(classId: food.classId, grams: grams)
                    }
                } else {
                    ServingAmountButton(
                        grams: food.currentMassG,
                        serving: model.solidServing(for: food.classId),
                        idPrefix: "review.row.\(food.classId)"
                    ) {
                        editingClassId = food.classId
                        gramEditText = String(Int(food.currentMassG.rounded()))
                        gramFieldFocused = true
                    }
                }
                Spacer(minLength: 8)
                ServingStepButton(
                    symbol: "minus",
                    enabled: food.currentMassG > 0,
                    idPrefix: "review.row.\(food.classId)"
                ) {
                    step(food, direction: -1)
                }
                ServingStepButton(
                    symbol: "plus",
                    enabled: food.currentMassG < ServingStepLogic.maxRowGrams,
                    idPrefix: "review.row.\(food.classId)"
                ) {
                    step(food, direction: 1)
                }
                relabelButton(food)
                rejectButton(food)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? strokeColour(for: food) : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.select(classId: food.classId) }  // Req 2.4
        .animation(reduceMotion ? nil : .smooth, value: food.currentMassG)
        .accessibilityIdentifier("review.row.\(food.classId)")
    }

    // De-emphasised remnant for a rejected food: predicted name struck
    // through, contribution gone, restore affordance (Req 4.2, 4.3).
    private func rejectedRow(_ food: ReviewFood) -> some View {
        HStack(spacing: 10) {
            rowBadge(food)
            Text(MealReviewModel.prettify(food.predicted.classID))
                .font(.headline)
                .strikethrough()
                .foregroundStyle(Color.captureChromeText)
            Spacer(minLength: 8)
            Button {
                Task { await model.reverseReject(classId: food.classId) }
            } label: {
                Text("Restore")
                    .font(.caption.weight(.semibold))
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.captureChromeText)
            .accessibilityIdentifier("review.row.\(food.classId).restore")
        }
        // foodRow's metrics exactly, de-emphasised the way Intake
        // de-emphasises a tile — opacity on the whole row, not a different
        // fill and a different padding (UI review 2026-09-04). Rejecting a
        // food now leaves the list rhythm intact instead of reflowing it.
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
        .opacity(0.55)
        .accessibilityIdentifier("review.rejectedRow.\(food.classId)")
    }

    private func rowBadge(_ food: ReviewFood) -> some View {
        Group {
            if let number = model.badgeNumber(for: food.classId) {
                Text("\(number)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .strikethrough(food.flags.rejected)
                    .foregroundStyle(Color.captureChromeText)
                    .frame(width: 22, height: 22)
                    .background(Color.captureBackground.opacity(0.6), in: Circle())
                    .overlay(Circle().stroke(strokeColour(for: food), lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }

    // Predicted beside corrected, on the row (Req 3.10; Decision 9 — the
    // correction is shown, not only the corrected state).
    @ViewBuilder
    private func nameLine(_ food: ReviewFood) -> some View {
        let predicted = MealReviewModel.prettify(food.predicted.classID)
        if food.flags.classCorrected, let corrected = food.corrected?.classID, !corrected.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(predicted)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(Color.captureChromeText.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Color.captureChromeText.opacity(0.5))
                }
                Text(MealReviewModel.prettify(corrected))
                    .font(.headline)
                    .foregroundStyle(Color.captureChromeText)
            }
        } else if food.flags.absent {
            VStack(alignment: .leading, spacing: 2) {
                Text(predicted)
                    .font(.headline)
                    .foregroundStyle(Color.captureChromeText)
                Text("not in the database")
                    .font(.caption)
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
            }
        } else {
            Text(predicted)
                .font(.headline)
                .foregroundStyle(Color.captureChromeText)
        }
    }

    // Opens the relabel alternatives (Req 3.1); selection alone never does
    // (Req 2.7).
    private func relabelButton(_ food: ReviewFood) -> some View {
        Button {
            Task { await model.openAlternatives(for: food.classId) }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.captureBackground.opacity(0.6), in: Circle())
                .foregroundStyle(Color.captureChromeText)
                .contentShape(Circle())
        }
        .accessibilityLabel("Change food")
        .accessibilityIdentifier("review.row.\(food.classId).relabel")
    }

    private func rejectButton(_ food: ReviewFood) -> some View {
        Button {
            Task { await model.reject(classId: food.classId) }
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.captureBackground.opacity(0.6), in: Circle())
                .foregroundStyle(Color.captureChromeText.opacity(0.8))
                .contentShape(Circle())
        }
        .accessibilityLabel("Reject")
        .accessibilityIdentifier("review.row.\(food.classId).reject")
    }

    // MARK: - Amounts (Req 6.1, 6.7 — serving-adjust items 1 and 3 unchanged)
    //
    // The amount button, gram editor and step buttons are the shared
    // serving-row controls (App/ServingRows.swift, shared-meal-components
    // Req 1); this surface routes their callbacks to MealReviewModel.

    // Serving-unit step where one exists; the shipped gram fallback otherwise
    // (Req 6.1, 6.2). Not capped at the measured volume (Req 6.5).
    private func step(_ food: ReviewFood, direction: Double) {
        let next = ServingStepLogic.stepped(
            from: food.currentMassG,
            serving: model.solidServing(for: food.classId),
            direction: direction
        )
        model.setAmount(classId: food.classId, grams: next)
        if editingClassId == food.classId {
            gramEditText = String(Int(next.rounded()))
        }
    }
}

// MARK: - Relabel sheet (Req 3, 5)

// The shortlist (at most five, recency-ordered, no scores — Req 3.2), the
// prominent not-in-the-database action (Req 5.1; the common case on a
// 25-class palette), and the full eligible list behind a plain text filter
// (Req 3.4).
private struct RelabelSheet: View {
    @Bindable var model: MealReviewModel
    let classId: String

    @State private var filterText = ""
    @Environment(\.dismiss) private var dismiss

    private var food: ReviewFood? { model.food(classId) }
    private var canRelabel: Bool { model.canRelabel(classId) }

    private var filteredEligible: [FoodCandidate] {
        let all = model.eligibleFoods(for: classId)
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                // The absent action is prominent, not tucked under a search:
                // nearly every real food is outside the palette (Req 5.1).
                Section {
                    Button {
                        Task {
                            await model.markAbsent(classId: classId, query: filterText)
                            dismiss()
                        }
                    } label: {
                        Label("Not in the database", systemImage: "questionmark.square.dashed")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("relabel.absent")
                }
                if !model.shortlist.isEmpty {
                    Section("Recent") {
                        ForEach(Array(model.shortlist.enumerated()), id: \.element.id) { rank, candidate in
                            candidateRow(candidate, shortlistRank: rank + 1)
                        }
                    }
                }
                Section("All foods") {
                    TextField("Filter", text: $filterText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("relabel.filter")
                    ForEach(filteredEligible) { candidate in
                        // Chosen from the full list: shortlist_rank 0 records
                        // that the alternatives did not contain it (Req 9.7).
                        candidateRow(candidate, shortlistRank: 0)
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sheetTitle: String {
        guard let food else { return "Change food" }
        return MealReviewModel.prettify(food.predicted.classID)
    }

    private func candidateRow(_ candidate: FoodCandidate, shortlistRank: Int) -> some View {
        Button {
            Task {
                await model.relabel(
                    classId: classId, to: candidate, shortlistRank: shortlistRank
                )
                dismiss()
            }
        } label: {
            Text(candidate.displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        // A record whose β is unrecoverable cannot be relabelled (Decision 14
        // fallback); reject, absent and amount stay available.
        .disabled(!canRelabel)
        .accessibilityIdentifier("relabel.candidate.\(candidate.classId)")
    }
}

// MARK: - Contour shapes

// All of a class's boundary loops as one path; even-odd fill reproduces the
// region (holes wind opposite), which is what the dimming and
// Path.contains(_:eoFill:) hit-testing need.
struct MaskContourShape: Shape {
    let loops: [MaskContour]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for loop in loops {
            guard let first = loop.points.first else { continue }
            path.move(to: scaled(first, rect))
            for point in loop.points.dropFirst() {
                path.addLine(to: scaled(point, rect))
            }
            path.closeSubpath()
        }
        return path
    }

    private func scaled(_ point: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

// The full frame plus the selected class's loops: even-odd fill dims
// everything outside the selected areas (Req 2.5).
private struct DimOutsideShape: Shape {
    let loops: [MaskContour]

    func path(in rect: CGRect) -> Path {
        var path = MaskContourShape(loops: loops).path(in: rect)
        path.addRect(rect)
        return path
    }
}
