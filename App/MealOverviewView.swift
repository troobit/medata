import Pipeline
import SwiftUI
import UIKit

// The Meal overview screen — design-handoff-00 §9, design-system/pages/
// meal-overview.md. A compact recap of one meal: the captured photo with mask
// overlays (photo-only fallback per §6.8), a compact carb total with the
// four-tier confidence pill, a capture-metadata line, and per-class rows with
// mask-colour swatches (no σ — Decision 16). Corrections are re-read on
// `eventsDidChange` while visible (Decision 18) so the `corrected` marker and
// the corrected total stay live.
struct MealOverviewView: View {
    let store: any PersistenceStore
    let record: MealRecord
    var onFullResult: () -> Void = {}
    var onDeleted: () -> Void = {}

    @State private var photo: UIImage?
    @State private var isCorrected = false
    @State private var correctedTotal: Float?
    // Predicted class id → corrected class id (meal-review Req 8.7): a
    // relabelled food is named as corrected on every surface that names it.
    @State private var correctedClassIds: [String: String] = [:]
    @State private var showDeleteConfirm = false

    private var displayTotal: Int {
        Int((correctedTotal ?? record.macros.totalCarbsG).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoCard
                totalRow
                Text(metadataLine)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                foods
                actionRow
            }
            .padding(24)
        }
        .background(Color.surfacePrimary)
        // Deliberately untitled (snaqui Req 4).
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("overview.menu")
            }
        }
        .confirmationDialog("Delete meal?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteMeal() }
            Button("Cancel", role: .cancel) {}
        }
        .task { await loadPhoto() }
        .task { await observeCorrections() }
    }

    // Photo with mask overlays; when the mask artefact is unavailable the loader
    // renders nothing and the photo (or its placeholder) shows through (§6.8).
    private var photoCard: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.surfaceElevated
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityIdentifier("overview.photoFallback")
            }
            MaskOverlayLoader(store: store, mealId: record.id,
                              paletteVersion: record.paletteVersion)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var totalRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(displayTotal)")
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("g carbs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            if isCorrected { correctedMarker }
            Spacer()
            ConfidencePill(sigmaMeal: record.confidence.sigmaMeal)
        }
        .accessibilityIdentifier("overview.total")
    }

    private var correctedMarker: some View {
        Text("corrected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.surfaceElevated, in: Capsule())
            .foregroundStyle(Color.textSecondary)
            .accessibilityIdentifier("overview.correctedMarker")
    }

    // §9.2 per-class rows: mask-colour swatch, name, mass, volume, carbs (no σ).
    private var foods: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Foods (\(perClassRows.count))")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            ForEach(perClassRows, id: \.name) { row in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(swatchColour(for: row.name))
                        .frame(width: 14, height: 14)
                    Text(row.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(row.massG) g · \(row.volumeCm3) cm³ · \(row.carbsG) g carbs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("overview.foods")
    }

    // Pill sizing/background/contentShape live INSIDE the Button label so the
    // whole pill is tappable, not just the centred text (the dead-surface trap
    // fixed for CaptureErrorOverlay in 09aab63 and SegmentationReview here).
    // The Adjust button is retired with ManualCorrectionView (serving-adjust
    // PRD Req 5): Full result opens the screen whose per-food rows adjust.
    private var actionRow: some View {
        Button(action: onFullResult) {
            Text("Full result")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("overview.fullResult")
    }

    private var metadataLine: String {
        let path = record.capturePath == .singleViewLidar ? "1-view · LiDAR" : "2-view"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(path) · \(formatter.string(from: record.createdAt))"
    }

    private struct PerClassRow {
        let name: String
        let displayName: String
        let massG: Int
        let volumeCm3: Int
        let carbsG: Int
    }

    private var perClassRows: [PerClassRow] {
        record.macros.perClass
            .map { name, macro in
                PerClassRow(
                    name: name,
                    displayName: MealOverviewView.prettify(correctedClassIds[name] ?? name),
                    massG: Int(macro.massG.rounded()),
                    volumeCm3: Int(macro.volumeCm3.rounded()),
                    carbsG: Int(macro.carbsG.rounded())
                )
            }
            .sorted { $0.carbsG > $1.carbsG }
    }

    // Deterministic mask-colour swatch (Decision 15). The colour table is keyed
    // by class id, so resolve the name to its palette index; unrecognised names
    // fold to a stable non-negative index so the swatch is still deterministic.
    private func swatchColour(for className: String) -> Color {
        // Single pre-release palette (pipeline Decision 50); the per-record
        // stamp becomes load-bearing again the first time a released palette
        // changes (see app-palette-drift-after-v2-promotion).
        let palette = ClassPalette.standard
        let id: Int
        if let index = palette.foodClasses.firstIndex(of: className) {
            id = index
        } else if let index = palette.liquidClasses.firstIndex(of: className) {
            id = palette.foodClasses.count + index
        } else {
            id = className.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        }
        let colour = ClassColourTable.standard.colour(forClassId: id)
        return Color(red: colour.red, green: colour.green, blue: colour.blue)
    }

    private static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private func loadPhoto() async {
        photo = await MealPhotoLoader.loadImage(assetID: record.photoAssetID)
    }

    private func observeCorrections() async {
        await refreshCorrections()
        for await _ in store.eventsDidChange {
            await refreshCorrections()
        }
    }

    private func refreshCorrections() async {
        let corrections = (try? await store.corrections(for: record.id)) ?? []
        isCorrected = !corrections.isEmpty
        correctedTotal = corrections.last { $0.correctedTotalCarbsGOneof != nil }?.correctedTotalCarbsG
        // Fold in order so a later amount-only correction (empty map) never
        // erases an earlier relabel (meal-review Req 8.7).
        correctedClassIds = corrections.reduce(into: [:]) { acc, correction in
            acc.merge(correction.correctedClassIds) { _, newer in newer }
        }
    }

    private func deleteMeal() {
        Task {
            try? await store.deleteMeal(id: record.id)
            onDeleted()
        }
    }
}
