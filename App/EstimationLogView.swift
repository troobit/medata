import Benchmark
import Persistence
import SwiftUI

// Wraps the exported log-file URL so it can drive `.sheet(item:)` — the
// ArchiveFile precedent in SettingsView.
private struct LogExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

// Developer-facing browser over the persisted estimation outcome rows
// (snaq-parity Req 2.2/2.3, design lane A "Browser + export"). Deliberately
// OUTSIDE #if DEBUG: Req 2.3 requires outcome recording — and this window on
// it — to operate in Release builds. Pushed inside Settings' NavigationStack,
// so it owns no stack of its own (RecordsView owns one only because it is a
// cover root). Reloads on appear via `.task`; no change-stream subscription —
// reload on appear is enough for a developer log.
struct EstimationLogView: View {
    @State private var model: EstimationLogModel

    init(store: any PersistenceStore, lineage: String) {
        _model = State(initialValue: EstimationLogModel(store: store, lineage: lineage))
    }

    var body: some View {
        List {
            if model.rows.isEmpty {
                Text("No attempts recorded")
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(model.rows) { row in
                NavigationLink {
                    EstimationOutcomeDetailView(outcome: row)
                } label: {
                    OutcomeRow(outcome: row)
                }
            }
            if let exportError = model.exportError {
                Text(exportError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Estimation log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.export() }
                } label: {
                    if model.isExporting {
                        MedataLoadingSymbol(mode: .loop, size: 22)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(model.isExporting)
                .accessibilityLabel("Export")
                .accessibilityIdentifier("estimationLog.export")
            }
        }
        .task { await model.load() }
        .sheet(item: $model.exportFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }
}

// One attempt on the list: outcome icon, failure case for refusals, when and
// under which model lineage, plus a marker for benchmark-tagged rows.
private struct OutcomeRow: View {
    let outcome: EstimationOutcome

    private var refused: Bool {
        outcome.outcome == EstimationOutcomeKind.refused.rawValue
    }

    var body: some View {
        HStack {
            Image(systemName: refused ? "xmark.circle" : "checkmark.circle")
                .foregroundStyle(refused ? Color.confidenceLow : Color.medataAccent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("\(timeString(outcome.timestampMs)) · \(outcome.modelVersion)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if outcome.benchmarkMealID != nil {
                Text("benchmark")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.surfaceElevated, in: Capsule())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityIdentifier("estimationLog.row")
    }

    private var title: String {
        guard refused else { return "Success" }
        return failureCaseName ?? "Refused"
    }

    // Minimal decode of the failure envelope ({domain, case, payload}) for
    // the row title; a row whose JSON does not decode still renders.
    private struct FailureEnvelope: Decodable {
        let domain: String?
        let caseName: String?

        enum CodingKeys: String, CodingKey {
            case domain
            case caseName = "case"
        }
    }

    private var failureCaseName: String? {
        guard
            let json = outcome.failureJSON,
            let envelope = try? JSONDecoder().decode(
                FailureEnvelope.self, from: Data(json.utf8)
            ),
            let caseName = envelope.caseName
        else { return nil }
        if let domain = envelope.domain { return "\(domain): \(caseName)" }
        return caseName
    }
}

// Full record detail: the row's fields plus the stored failure and
// measurements JSON, pretty-printed and selectable so values can be copied
// off-device without an export.
private struct EstimationOutcomeDetailView: View {
    let outcome: EstimationOutcome

    var body: some View {
        List {
            Section {
                LabeledContent("Outcome", value: outcome.outcome)
                LabeledContent("Time", value: timeString(outcome.timestampMs))
                LabeledContent("Model", value: outcome.modelVersion)
                if let mealID = outcome.mealID {
                    LabeledContent("Meal", value: mealID.uuidString)
                }
                if let benchmarkMealID = outcome.benchmarkMealID {
                    LabeledContent("Benchmark meal", value: benchmarkMealID.uuidString)
                }
            }
            .font(.footnote)
            if let failureJSON = outcome.failureJSON {
                Section("Failure") { jsonText(failureJSON) }
            }
            Section("Measurements") { jsonText(outcome.measurementsJSON) }
        }
        .navigationTitle("Attempt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func jsonText(_ raw: String) -> some View {
        Text(Self.prettyJSON(raw))
            .font(.caption.monospaced())
            .foregroundStyle(Color.textPrimary)
            .textSelection(.enabled)
    }

    private static func prettyJSON(_ raw: String) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
            )
        else { return raw }
        return String(decoding: data, as: UTF8.self)
    }
}

// Data source for the log browser and its export. Fetch-on-demand only — no
// `eventsDidChange` subscription exists for outcome rows by design
// (quick_presets convention; the store never notifies for them).
@Observable
@MainActor
final class EstimationLogModel {
    // Effectively-unbounded fetch: both stored populations are bounded (500
    // non-benchmark rows; 10 benchmark attempts per meal per lineage), so
    // this limit returns everything in practice.
    static let fetchLimit = 10_000

    private(set) var rows: [EstimationOutcome] = []
    private(set) var isExporting = false
    private(set) var exportError: String?
    fileprivate var exportFile: LogExportFile?

    private let store: any PersistenceStore
    private let lineage: String

    init(store: any PersistenceStore, lineage: String) {
        self.store = store
        self.lineage = lineage
    }

    func load() async {
        rows = (try? await store.estimationOutcomes(limit: Self.fetchLimit)) ?? []
    }

    // Serialises the outcome rows + benchmark meals (+ the computed report
    // for the current lineage, per design lane B) to a JSON file and hands it
    // to the share sheet — the same seam as Settings' archive export. Export
    // contains record contents only: the stored measurements/failure JSON is
    // embedded structurally, and no raw imagery exists anywhere in it
    // (Req 2.6).
    func export() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let outcomes = try await store.estimationOutcomes(limit: Self.fetchLimit)
            let meals = try await store.benchmarkMeals()
            let data = try LogExport.json(outcomes: outcomes, meals: meals, lineage: lineage)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("estimation-log-\(Self.fileStamp()).json")
            try data.write(to: url, options: .atomic)
            rows = outcomes
            exportFile = LogExportFile(url: url)
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        // en_US_POSIX is the only canonical fixed-format locale (stable HH);
        // this is a machine-format filename, not user copy.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

// Pure JSON assembly for the export file. Built with JSONSerialization
// because the stored `measurements`/`failure` columns are already JSON
// strings — embedding them as parsed objects keeps the export a single
// well-formed document instead of doubly-encoded strings.
enum LogExport {
    static func json(
        outcomes: [EstimationOutcome], meals: [BenchmarkMeal], lineage: String
    ) throws -> Data {
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        let root: [String: Any] = [
            "v": 1,
            "exported_at_ms": Int64(Date().timeIntervalSince1970 * 1000),
            "outcomes": outcomes.map(dict(for:)),
            "benchmark_meals": meals.map(dict(for:)),
            "report": dict(for: report)
        ]
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func dict(for outcome: EstimationOutcome) -> [String: Any] {
        var dict: [String: Any] = [
            "id": outcome.id.uuidString,
            "timestamp_ms": outcome.timestampMs,
            "outcome": outcome.outcome,
            "measurements": embedded(outcome.measurementsJSON),
            "model_version": outcome.modelVersion
        ]
        if let failure = outcome.failureJSON { dict["failure"] = embedded(failure) }
        if let mealID = outcome.mealID { dict["meal_id"] = mealID.uuidString }
        if let benchmarkMealID = outcome.benchmarkMealID {
            dict["benchmark_meal_id"] = benchmarkMealID.uuidString
        }
        return dict
    }

    private static func dict(for meal: BenchmarkMeal) -> [String: Any] {
        [
            "id": meal.id.uuidString,
            "name": meal.name,
            "created_at_ms": meal.createdAtMs,
            "items": meal.items.map { ["class_id": $0.classID, "grams": $0.grams] },
            "truth_carbs_g": meal.truthCarbsG,
            "db_edition": meal.dbEdition,
            "fidelity": meal.fidelity.rawValue
        ]
    }

    private static func dict(for report: Report) -> [String: Any] {
        var dict: [String: Any] = [
            "lineage": report.lineage,
            "meal_count": report.mealCount,
            "completed_meal_count": report.completedMealCount,
            "completion_rate": report.completionRate,
            "total_attempt_count": report.totalAttemptCount,
            "refused_attempt_count": report.refusedAttemptCount,
            "undecodable_attempt_count": report.undecodableAttemptCount,
            "headline_valid": report.headlineValid,
            "missing_staples": report.missingStaples,
            "anchor_verdict": report.anchorVerdict.rawValue,
            "anchors": [
                "snaq_mae_grams": BenchmarkAnchors.snaqMAEGrams,
                "snaq_mape_percent": BenchmarkAnchors.snaqMAPEPercent,
                "gocarb_within_10g_percent": BenchmarkAnchors.goCarbWithin10gPercent,
                "dietitians_within_10g_percent": BenchmarkAnchors.dietitiansWithin10gPercent
            ],
            "rows": report.rows.map(dict(for:))
        ]
        if let mae = report.maeGrams { dict["mae_grams"] = mae }
        if let mape = report.mapePercent { dict["mape_percent"] = mape }
        if let within = report.within10gShare { dict["within_10g_share"] = within }
        if let attempts = report.meanAttemptsPerMeal { dict["mean_attempts_per_meal"] = attempts }
        return dict
    }

    private static func dict(for row: Report.MealRow) -> [String: Any] {
        var dict: [String: Any] = [
            "meal_id": row.mealID.uuidString,
            "name": row.name,
            "truth_carbs_g": row.truthCarbsG,
            "attempt_count": row.attemptCount,
            "completed": row.completed
        ]
        if let estimate = row.estimateCarbsG { dict["estimate_carbs_g"] = estimate }
        if let error = row.absoluteErrorG { dict["absolute_error_g"] = error }
        return dict
    }

    // Embeds a stored JSON string as a structured value; a row whose JSON
    // does not parse exports as the raw string rather than being dropped.
    private static func embedded(_ raw: String) -> Any {
        (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) ?? raw
    }
}

// Shared formatter — allocating a DateFormatter per row render is expensive.
private enum RowTime {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private func timeString(_ timestampMs: Int64) -> String {
    RowTime.formatter.string(from: Date(timeIntervalSince1970: Double(timestampMs) / 1000))
}
