#if FIELD_LOOP
import ImageIO
import Pipeline
import SwiftUI
import UniformTypeIdentifiers

// Every developer-phase control on one screen, reached from Settings
// (specs/ui/settings-information-architecture). The WHOLE file is `#if
// FIELD_LOOP` — Debug and Release, the field profiles — so the ProductRelease
// build compiles nothing here and Settings shows no Developer row at all.
//
// The seed and clear buttons are `#if DEBUG` INSIDE that, because
// `seedDemoBslEvents` and `deleteAllData` are Debug-only store methods. The
// toggles are not: they exist to be flipped between two captures on the phone,
// and the phone runs a Release build (Debug substitutes the stub segmenter and
// cannot recognise food at all). Getting these two guards the wrong way round
// is what once put the switches in the one build that could not use them.
struct DeveloperSettingsView: View {
    let store: any PersistenceStore

    // Developer-phase capture switches (two-view-trust Req 4.5 and the oblique
    // band measurement, plus the review-photo attempt switch).
    @AppStorage(DeveloperFlags.forceNonLiDARKey) private var forceNonLiDAR = false
    @AppStorage(DeveloperFlags.unlockObliqueTiltKey) private var unlockObliqueTilt = false
    @AppStorage(DeveloperFlags.reviewPhotoFillsWidthKey) private var reviewPhotoFillsWidth = false
    @AppStorage(DeveloperFlags.inlineFoodChipsKey) private var inlineFoodChips = false

    #if DEBUG
    @State private var isSeeding = false
    @State private var isSeedingMeal = false
    @State private var isSeedingReview = false
    @State private var isSeedingWorstCase = false
    @State private var isClearing = false
    @State private var confirmsClear = false
    @State private var demoReview: MealRecord?
    #endif

    var body: some View {
        Form {
            Section("Capture") {
                // Clears depth from every captured frame and reports the phone
                // as having none, so the two-view + ID-1 card path runs on a
                // LiDAR device. Two-view is then forced and the nadir shutter
                // waits for a card.
                Toggle("Capture without depth", isOn: $forceNonLiDAR)
                    .accessibilityIdentifier("settings.forceNonLiDAR")
                // Lets the oblique shutter fire at any tilt. The bubble level,
                // the 25° guidance and the recorded angle are unchanged.
                Toggle("Oblique tilt unlocked", isOn: $unlockObliqueTilt)
                    .accessibilityIdentifier("settings.unlockObliqueTilt")
            }

            Section("Review") {
                // Review photo, attempt 1 versus attempt 2. Both show the photo
                // upright; off is the whole photo with side gutters, on fills
                // the column and crops top and bottom.
                Toggle("Review photo fills width", isOn: $reviewPhotoFillsWidth)
                    .accessibilityIdentifier("settings.reviewPhotoFillsWidth")
                // Swap loop, attempt 1 versus attempt 2 (review-swap-loop):
                // off swaps through the sheet, on adds a one-tap chip line
                // to every row.
                Toggle("Inline food chips", isOn: $inlineFoodChips)
                    .accessibilityIdentifier("settings.inlineFoodChips")
            }

            #if DEBUG
            Section("Demo data") {
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

                Button {
                    reviewWorstCaseMeal()
                } label: {
                    if isSeedingWorstCase {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Text("Review worst-case meal")
                    }
                }
                .disabled(isSeedingWorstCase)
                .accessibilityIdentifier("settings.reviewWorstCaseMeal")
            }

            Section {
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
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
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
            try? await store.save(DeveloperSettingsView.demoMeal(), artefacts: [])
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
            let record = DeveloperSettingsView.demoMeal()
            try? await store.save(record, artefacts: [])
            demoReview = record
        }
    }

    // The meal-review Req 6.6 prerequisite check: the worst case the
    // requirements permit — four detected foods AND every accessory signal at
    // once (calibration banner, liquid over-estimate, unknown region,
    // unsupported liquid). No real capture reaches this state today:
    // `liquidOverEstimate` is never set at runtime (LiquidResolver is not
    // wired into Pipeline) and the unknown/unsupported signals require the
    // segmenter to emit those raster classes. So the record forces the macro
    // flags directly and a synthetic mask artefact carries the sentinel
    // classes — the review surface then renders the signals through the same
    // decode path a real capture would use.
    private func reviewWorstCaseMeal() {
        isSeedingWorstCase = true
        Task {
            defer { isSeedingWorstCase = false }
            let record = DeveloperSettingsView.worstCaseMeal()
            try? await store.save(record, artefacts: [])
            if let png = DeveloperSettingsView.worstCaseMaskPNG() {
                let artefact = MealArtefact(
                    kind: "mask", viewId: "nadir", filename: "mask.png",
                    bytesSize: png.count, sha256Hex: ""
                )
                try? await store.writeArtefact(mealId: record.id, artefact: artefact, data: png)
            }
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

    // Four solids, one of them uncalibrated (pooled β → the full calibration
    // banner) and the result-level liquid over-estimate flag forced on. The
    // unknown-region and unsupported-liquid signals come from the mask below,
    // not from perClass — those classes never carry a macro entry (Req 1.5).
    private static func worstCaseMeal() -> MealRecord {
        // (class, volume cm³, mass g, carbs g, protein g, fat g, status)
        let foods: [(String, Float, Float, Float, Float, Float, PbBetaCalibrationStatus)] = [
            ("white_rice", 150, 180, 50.4, 4.7, 0.5, .calibrated),
            ("pasta", 130, 140, 43.4, 7.3, 1.3, .uncalibratedPooled),
            ("chicken", 110, 120, 0.0, 29.0, 7.6, .calibrated),
            ("broccoli", 110, 80, 5.6, 3.4, 0.7, .calibrated),
            // Food the segmenter could not name (unknown-food-nameable Req 6):
            // volume only, unity β, nothing counted until it is relabelled.
            ("unknown_food", 95, 0, 0.0, 0.0, 0.0, .uncalibratedUnity)
        ]
        var macros = PbMacroResult()
        var volumes = PbVolumeResult()
        for (classId, volume, mass, carbs, protein, fat, status) in foods {
            let beta: Float = classId == ClassPalette.unknownFoodClassId ? 1 : 0.9
            var perClass = PbPerClassMacros()
            perClass.volumeCm3 = volume
            perClass.massG = mass
            perClass.carbsG = carbs
            perClass.proteinG = protein
            perClass.fatG = fat
            perClass.betaUsed = beta
            perClass.betaStatus = status
            macros.perClass[classId] = perClass
            volumes.perClassVolumesCm3[classId] = volume
            volumes.perClassVolumesPreBetaCm3[classId] = volume / beta
        }
        macros.totalCarbsG = foods.reduce(0) { $0 + $1.3 }
        macros.liquidOverEstimate = true

        var confidence = PbConfidenceResult()
        confidence.sigmaMeal = 0.82  // above the very-low gate, so Req 6.6 applies
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
                uniqueKeysWithValues: foods.map { ($0.0, $0.6) }
            )
        )
    }

    // A synthetic label raster matching the worst-case record: one rectangle
    // per food class plus unknown_food and unsupported_liquid, background
    // elsewhere. Encoded exactly as `MaskArtefactWriter.encodeLabelPNG` does —
    // 8-bit DeviceGray, alpha none, raw class indices — so the read side
    // (`MaskOverlayDecoder`) treats it as a real capture's mask.
    private static func worstCaseMaskPNG() -> Data? {
        let width = 400, height = 300  // 4:3, the review photo aspect
        let palette = ClassPalette.standard
        var labels = [UInt8](repeating: UInt8(palette.background), count: width * height)

        func fill(_ classIndex: Int, x: Range<Int>, y: Range<Int>) {
            for row in y {
                for col in x { labels[row * width + col] = UInt8(classIndex) }
            }
        }
        // Class indices per ClassPalette.standard.
        fill(0, x: 20..<140, y: 30..<140)                          // white_rice
        fill(2, x: 160..<280, y: 30..<140)                         // pasta
        fill(8, x: 300..<380, y: 30..<140)                         // chicken
        fill(15, x: 20..<140, y: 160..<270)                        // broccoli
        fill(palette.unknownFood, x: 160..<280, y: 160..<270)
        fill(palette.unsupportedLiquid, x: 300..<380, y: 160..<270)

        guard let provider = CGDataProvider(data: Data(labels) as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil,
                  shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
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
#endif
