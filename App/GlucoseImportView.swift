import Persistence
import PhotosUI
import SwiftUI

// LibreLink screenshot import sheet (specs/data/libre-ingestion Reqs 1.1–1.3,
// 5.4). Presented from Settings; self-contained so it survives the
// design-handoff-00 reskin with a one-line entry-point move (Decision 7).
struct GlucoseImportView: View {
    let store: any PersistenceStore

    @State private var model: GlucoseImportModel?
    @State private var selection: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(
                        selection: $selection,
                        matching: .screenshots,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose screenshots", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(model?.isProcessing ?? false)
                } footer: {
                    Text("Pick FreeStyle LibreLink graph screenshots (8-hour home view or 24-hour daily report). Readings are extracted on this device; nothing leaves it.")
                }

                if let model, model.isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Processing \(model.processedCount + 1) of \(model.totalCount)…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let model, !model.results.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { result in
                            ResultRow(result: result)
                        }
                    }
                }
            }
            .navigationTitle("Import glucose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if model == nil { model = GlucoseImportModel(store: store) }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            model?.process(items: items)
            selection = []
        }
        .onDisappear {
            model?.cancel()
        }
    }
}

private struct ResultRow: View {
    let result: GlucoseImportModel.ImageResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                icon
                Text(result.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(result.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch result.outcome {
        case .stored:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skippedDuplicate:
            Image(systemName: "arrow.uturn.left.circle").foregroundStyle(.secondary)
        case .rejected, .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    // Req 5.4: extracted / stored / skipped counts plus the agreeing and
    // discrepant split for overlaps.
    private var detail: String {
        switch result.outcome {
        case .stored(let summary):
            var parts = ["\(summary.extracted) readings", "\(summary.stored) stored"]
            if summary.skippedExisting > 0 {
                parts.append("\(summary.skippedExisting) already present")
                parts.append("\(summary.agreeing) agreeing")
                if !summary.discrepant.isEmpty {
                    parts.append("\(summary.discrepant.count) differ by more than 0.3 mmol/L")
                }
            }
            return parts.joined(separator: " · ")
        case .skippedDuplicate:
            return "Already imported — skipped"
        case .rejected(let reason):
            return reason
        case .failed(let message):
            return message
        }
    }
}
