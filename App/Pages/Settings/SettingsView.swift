import Dosing
import GlucoseWidgetShared
import Pipeline
import SwiftUI

// Wraps the exported archive URL so it can drive `.sheet(item:)`.
private struct ArchiveFile: Identifiable {
    let id = UUID()
    let url: URL
}

// The Settings screen — design-handoff-00 §12, design-system/pages/settings.md.
// A disabled Account row, the bundled food-database editions (CoFID + AFCD, not
// IFCDB — Decision 4), capture defaults (default path + always-include-card),
// data export, and an About link. No photo-retention controls (Req 12.3).
// Attribution now lives in About (§13), not inline here. A DEBUG-only row seeds
// demo glucose so Trends is verifiable before an importer ships (Decision 13).
struct SettingsView: View {
    let store: any PersistenceStore
    // The recurring dose schedule (specs/data/dose-schedule Req 1.3, 1.4, 3.2,
    // 3.3). Owned by AppRoot so the outstanding set survives this cover being
    // presented and dismissed.
    let doseSchedule: DoseScheduleModel
    // Fresh-install default forks on device capability (Req 16.2 / Decision 9):
    // 1-view on LiDAR devices, 2-view otherwise. Passed from AppRoot so the
    // Picker resolves an unset key the same way `CaptureFlowView.effectiveMode`
    // and `defaultCaptureModeReader` do, instead of hard-defaulting to `.double`.
    let hasLiDAR: Bool
    // Live glucose-source connections (cgm-connect Req 6), owned by MedataApp
    // and threaded through AppRoot.
    let glucoseConnections: GlucoseConnectionsModel
    // Current segmenter lineage tag (snaq-parity): scopes the benchmark
    // report and labels the log. AppRoot passes `captureModel.segmenterSource`.
    let captureLineage: String
    // Benchmark capture launch (snaq-parity lane B). Settings cannot present
    // the Capture cover itself — Capture and Settings are mutually-exclusive
    // covers on AppRoot — so this closure hands the meal id up to AppRoot,
    // which tags `CaptureFlowModel.benchmarkMealID` and sequences
    // dismiss-Settings → present-Capture through its deep-link machinery.
    let onBenchmarkCapture: (UUID) -> Void
    // The outstanding-dose gear lands here: when set, the Form scrolls to the
    // dose-schedule section on appear instead of opening at the top.
    var scrollToDoseSchedule: Bool = false

    @Environment(\.dismiss) private var dismiss
    // Empty string means the capture-mode key is unset — `captureModeBinding`
    // then resolves the effective default from `hasLiDAR`. Writing persists the
    // raw value back under the same `SettingsKeys.captureMode` key.
    @AppStorage(SettingsKeys.captureMode) private var captureModeRaw: String = ""
    @AppStorage(SettingsKeys.alwaysIncludeCard) private var alwaysIncludeCard = false
    // Per-kind insulin product defaults (PRD regression-suggestion-integration
    // App 5). The dose sheet fills `insulin_type` from these at save time and
    // never asks for the product itself.
    @AppStorage(SettingsKeys.insulinTypeBolus)
    private var bolusInsulinType = SettingsKeys.insulinTypeBolusDefault
    @AppStorage(SettingsKeys.insulinTypeBasal)
    private var basalInsulinType = SettingsKeys.insulinTypeBasalDefault
    @AppStorage(SettingsKeys.ratioSource)
    private var ratioSource = "manual"
    @AppStorage(SettingsKeys.ratioFitRef)
    private var ratioFitRef = ""
    // How long a blood reading outranks a newer sensor reading
    // (specs/data/fingerprick-glucose Req 3.2). Seconds on disk, minutes in the
    // control. App-private and deliberately not App Group state: what crosses
    // to the widget is the resolved absolute `holdsUntil`, never this
    // (Decision 8).
    @AppStorage(SettingsKeys.glucoseHoldWindowSeconds)
    private var glucoseHoldWindowSeconds: Double = GlucoseHoldWindow.defaultSeconds

    private var captureModeBinding: Binding<CaptureMode> {
        Binding(
            get: { CaptureMode(rawValue: captureModeRaw) ?? (hasLiDAR ? .single : .double) },
            set: { captureModeRaw = $0.rawValue }
        )
    }

    @State private var archiveFile: ArchiveFile?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showsGlucoseImport = false
    @State private var showsGlucoseSources = false
    @State private var isSeeding = false
    #if DEBUG
    @State private var isClearing = false
    @State private var confirmsClear = false
    @State private var isSeedingMeal = false
    @State private var isSeedingReview = false
    @State private var demoReview: MealRecord?
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            settingsForm(proxy: proxy)
        }
    }

    private func settingsForm(proxy: ScrollViewProxy) -> some View {
        Form {
            Section {
                Button("Account") {}
                    .disabled(true)
                    .accessibilityIdentifier("settings.account")
            }

            Section("Food database") {
                Text("CoFID")
                Text("AFCD")
            }
            Section("Glucose data") {
                Button {
                    showsGlucoseSources = true
                } label: {
                    Label("Glucose sources", systemImage: "sensor.tag.radiowaves.forward")
                }
                .accessibilityIdentifier("settings.glucoseSources")
                Button {
                    showsGlucoseImport = true
                } label: {
                    Label("Import LibreLink screenshots", systemImage: "waveform.path.ecg")
                }
                Stepper(value: $glucoseHoldWindowSeconds,
                        in: GlucoseHoldWindow.rangeSeconds,
                        step: 300) {
                    LabeledContent(
                        "Blood hold", value: Self.minutesLabel(glucoseHoldWindowSeconds))
                }
                .accessibilityIdentifier("settings.glucoseHoldWindow")
                // The one thing a longer window silently changes: the staleness
                // ladder measures a reading's age from its own instant and knows
                // nothing of the hold (Decision 3), so past this point a held
                // reading renders as stale while still holding. Stated as the
                // number it is, and only where the two diverge — a fact about
                // the render, not a warning about the setting.
                if glucoseHoldWindowSeconds > GlucoseTimeline.staleAge {
                    LabeledContent(
                        "Renders stale after",
                        value: Self.minutesLabel(GlucoseTimeline.staleAge))
                }
                // Explainer footnote removed under the developer-phase copy rule
                // (Req 14.5 / Decision 21).
            }

            Section("Capture") {
                Picker("Default path", selection: captureModeBinding) {
                    Text("1-view").tag(CaptureMode.single)
                    Text("2-view").tag(CaptureMode.double)
                }
                Toggle("Always include card", isOn: $alwaysIncludeCard)
            }

            Section("Insulin") {
                LabeledContent("Bolus") {
                    TextField(SettingsKeys.insulinTypeBolusDefault, text: $bolusInsulinType)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.insulinBolus")
                }
                LabeledContent("Basal") {
                    TextField(SettingsKeys.insulinTypeBasalDefault, text: $basalInsulinType)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.insulinBasal")
                }
                // Carbohydrate ratios in band order (specs/data/insulin-dosing
                // Req 1.2, 6.9). The STORED value is grams per unit and the
                // field is suffixed g/U so the direction is on screen at all
                // times; the reciprocal beneath spells out the developer's own
                // phrasing — "= 2.0 U per 10 g" — so the two conventions are
                // visibly the same number and nobody has to hold the inversion
                // in their head. A field labelled merely "Ratio" is the trap
                // this layout exists to close.
                ForEach(DoseBand.allCases, id: \.self) { band in
                    CarbRatioRow(band: band)
                }
                // No increment row: the dosable increment is fixed at 1 U
                // (Req 5.1, 6.9, Decision 17), so there is nothing to choose.
                Picker("Ratio source", selection: $ratioSource) {
                    Text("Chosen").tag("manual")
                    Text("medreg").tag("medreg")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.ratioSource")
                LabeledContent("medreg fit") {
                    TextField("", text: $ratioFitRef)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.ratioFitRef")
                }
            }

            doseScheduleSection

            Section {
                Button {
                    exportArchive()
                } label: {
                    if isExporting {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                .accessibilityIdentifier("settings.export")
                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                // Outside #if DEBUG deliberately: Req 2.3 requires the
                // estimation log (and the benchmark that reads it) to
                // operate in Release builds.
                NavigationLink("Estimation log") {
                    EstimationLogView(store: store, lineage: captureLineage)
                }
                .accessibilityIdentifier("settings.estimationLog")
                NavigationLink("Benchmark") {
                    BenchmarkView(
                        store: store,
                        lineage: captureLineage,
                        onCapture: onBenchmarkCapture
                    )
                }
                .accessibilityIdentifier("settings.benchmark")
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }

            #if DEBUG
            Section {
                Button {
                    seedDemoGlucose()
                } label: {
                    if isSeeding {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Text("Seed demo glucose")
                    }
                }
                .disabled(isSeeding)
                .accessibilityIdentifier("settings.seedGlucose")

                Button {
                    seedDemoMeal()
                } label: {
                    if isSeedingMeal {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Text("Seed demo meal")
                    }
                }
                .disabled(isSeedingMeal)
                .accessibilityIdentifier("settings.seedMeal")

                Button {
                    reviewDemoMeal()
                } label: {
                    if isSeedingReview {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Text("Review demo meal")
                    }
                }
                .disabled(isSeedingReview)
                .accessibilityIdentifier("settings.reviewDemoMeal")

                Button(role: .destructive) {
                    confirmsClear = true
                } label: {
                    if isClearing {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Text("Clear all data")
                    }
                }
                .disabled(isClearing)
                .accessibilityIdentifier("settings.clearAllData")
            }
            #endif
        }
        // Deliberately untitled (snaqui Req 4); inline mode so no large-title
        // band is reserved.
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard scrollToDoseSchedule else { return }
            // Deferred one turn so the List has laid out before the scroll.
            Task { proxy.scrollTo("doseScheduleSection", anchor: .top) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CloseCoverButton { dismiss() }
            }
        }
        .sheet(item: $archiveFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showsGlucoseImport) {
            GlucoseImportView(store: store)
        }
        .sheet(isPresented: $showsGlucoseSources) {
            GlucoseConnectionsView(model: glucoseConnections)
        }
        #if DEBUG
        .navigationDestination(item: $demoReview) { record in
            MealReviewView(
                record: record,
                store: store,
                onRecord: { demoReview = nil },
                onRetake: { discardDemoReview(record) },
                onDelete: { discardDemoReview(record) }
            )
        }
        .confirmationDialog(
            "Delete all meals, glucose and insulin data?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear all data", role: .destructive) { clearAllData() }
        }
        #endif
    }

    private func exportArchive() {
        isExporting = true
        exportError = nil
        Task {
            defer { isExporting = false }
            do {
                let path = try await store.exportArchive()
                archiveFile = ArchiveFile(url: URL(fileURLWithPath: path))
            } catch {
                exportError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Carbohydrate ratio row (specs/data/insulin-dosing Req 1.2, 1.5)

    // Colocated to avoid a project.pbxproj entry for a one-row view.
    //
    // Validation is `CarbRatio.init?`: a rejected entry leaves the stored
    // value in force and the field reverts on commit. No error copy, no
    // validation message — the value in force is always the value on screen.
    private struct CarbRatioRow: View {
        let band: DoseBand

        @State private var text = ""
        @FocusState private var focused: Bool

        private var storedRatio: CarbRatio {
            let raw = UserDefaults.standard.double(forKey: SettingsKeys.ratioKey(for: band))
            return CarbRatio(gramsPerUnit: raw)
                ?? CarbRatioTable.seed[band]
                ?? CarbRatio(gramsPerUnit: 10.0)!
        }

        private static func fieldText(_ ratio: CarbRatio) -> String {
            String(format: "%.1f", ratio.gramsPerUnit)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent {
                    HStack(spacing: 4) {
                        TextField("", text: $text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .focused($focused)
                            .accessibilityIdentifier("settings.ratio.\(band.rawValue)")
                        Text("g/U")
                            .foregroundStyle(Color.textSecondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(band.label)
                            .foregroundStyle(Color.textPrimary)
                        // Which meals the row governs, made concrete without
                        // a sentence.
                        Text(band.windowLabel)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Text(reciprocalLabel)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("settings.ratioReciprocal.\(band.rawValue)")
            }
            .onAppear { text = Self.fieldText(storedRatio) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
        }

        // Rendered, never stored (Req 1.1).
        private var reciprocalLabel: String {
            String(format: "= %.1f U per 10 g", storedRatio.unitsPerTenGrams)
        }

        private func commit() {
            if let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                let ratio = CarbRatio(gramsPerUnit: value) {
                UserDefaults.standard.set(
                    ratio.gramsPerUnit, forKey: SettingsKeys.ratioKey(for: band)
                )
            }
            text = Self.fieldText(storedRatio)
        }
    }

    // Seconds on disk, minutes on screen — the key is named in seconds so the
    // reader hands a `TimeInterval` straight to the derivation with no unit
    // conversion in between, and this is the one place that converts.
    private static func minutesLabel(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }

    #if DEBUG
    private func seedDemoGlucose() {
        guard let grdb = store as? GRDBPersistenceStore else { return }
        isSeeding = true
        Task {
            defer { isSeeding = false }
            try? await grdb.seedDemoBslEvents()
        }
    }

    // Writes one fixed meal so the surfaces that only exist after a capture —
    // the review screen above all — can be judged without a camera, and judged
    // against the SAME numbers on every build. 56.0 g of carbohydrate: 11 U on
    // the breakfast seed ratio (5 g/U), 6 U on the other three (10 g/U), so the
    // rounding is visible either way. Segmenter source `demo_seed` keeps these
    // rows separable from real captures in the correction corpus.
    private func seedDemoMeal() {
        isSeedingMeal = true
        Task {
            defer { isSeedingMeal = false }
            try? await store.save(SettingsView.demoMeal(), artefacts: [])
        }
    }

    // The only non-capture path onto `MealReviewView`, which is otherwise
    // built in exactly one place (CaptureFlowView's `.result` route). It saves
    // the same fixed record `seedDemoMeal` writes and then pushes the review
    // surface on it, so the capture-review line can be judged on a build whose
    // estimation is refusing or drifting.
    //
    // Saved first, and against the real store, because the surface persists
    // every correction against the meal id the moment it is made (meal-review
    // Req 9.9) — an unsaved record would strand those rows. `artefacts: []`
    // means no photo and no outlines, so the surface shows the fallback it is
    // specified to show without one (Req 1.6); everything below the photo —
    // rows, totals, corrected markers, serving and scale controls — renders
    // exactly as it does after a real capture.
    private func reviewDemoMeal() {
        isSeedingReview = true
        Task {
            defer { isSeedingReview = false }
            let record = SettingsView.demoMeal()
            try? await store.save(record, artefacts: [])
            demoReview = record
        }
    }

    // Retake and Delete discard the demo meal the same way they discard a
    // just-captured one (`CaptureFlowModel.deleteAndDismiss`). The correction
    // rows survive that delete (Req 9.10), which is what leaves the
    // persistence half of the check readable afterwards.
    private func discardDemoReview(_ record: MealRecord) {
        demoReview = nil
        Task { try? await store.deleteMeal(id: record.id) }
    }

    private static func demoMeal() -> MealRecord {
        // (class, volume cm³, mass g, carbs g, protein g, fat g)
        let foods: [(String, Float, Float, Float, Float, Float)] = [
            ("white_rice", 150, 180, 50.4, 4.7, 0.5),
            ("chicken", 110, 120, 0.0, 29.0, 7.6),
            ("broccoli", 110, 80, 5.6, 3.4, 0.7)
        ]
        let beta: Float = 0.9
        var macros = PbMacroResult()
        var volumes = PbVolumeResult()
        for (classId, volume, mass, carbs, protein, fat) in foods {
            var perClass = PbPerClassMacros()
            perClass.volumeCm3 = volume
            perClass.massG = mass
            perClass.carbsG = carbs
            perClass.proteinG = protein
            perClass.fatG = fat
            perClass.betaUsed = beta
            perClass.betaStatus = .calibrated
            macros.perClass[classId] = perClass
            volumes.perClassVolumesCm3[classId] = volume
            // Relabel refuses without a pre-β volume (meal-review Decision 14),
            // so the demo meal carries one.
            volumes.perClassVolumesPreBetaCm3[classId] = volume / beta
        }
        macros.totalCarbsG = foods.reduce(0) { $0 + $1.3 }

        var confidence = PbConfidenceResult()
        confidence.sigmaMeal = 0.82
        confidence.sigmaScale = 0.90
        confidence.sigmaSeg = 0.85

        return MealRecord(
            capturePath: .singleViewLidar,
            databaseEdition: "CoFID 2024 + AFCD 2024",
            paletteVersion: ClassPalette.standard.version,
            segmenterSource: "demo_seed",
            calibration: PbCameraIntrinsics(),
            supportPlane: PbSupportPlane(),
            scale: PbMetricScale(),
            volumes: volumes,
            macros: macros,
            confidence: confidence,
            perClassCalibration: Dictionary(
                uniqueKeysWithValues: foods.map { ($0.0, PbBetaCalibrationStatus.calibrated) }
            )
        )
    }

    private func clearAllData() {
        guard let grdb = store as? GRDBPersistenceStore else { return }
        isClearing = true
        Task {
            defer { isClearing = false }
            try? await grdb.deleteAllData()
        }
    }
    #endif
}
