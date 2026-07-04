import Charts
import Pipeline
import SwiftUI

// The Trends screen — design-handoff-00 §10, design-system/pages/trends.md.
// A single-chart dual-series view: glucose as a line (mmol/L, leading axis) and
// carbs as bars (g, trailing axis relabelled in grams) over a shared y-scale
// (the single-scale workaround), with the 3.9–10.0 mmol/L target band. Week and
// Month aggregate to per-day totals and averages. Reads glucose exclusively from
// `bsl` events (Req 11.1); all bucketing / axis maths is `TrendsMath`.
struct TrendsView: View {
    let store: any PersistenceStore

    @State private var model: TrendsModel
    @State private var path: [MealRoute] = []
    @State private var showOptions = false

    @AppStorage(SettingsKeys.trendsShowCarbs) private var showCarbs = true
    @AppStorage(SettingsKeys.trendsShowGlucose) private var showGlucose = true
    @AppStorage(SettingsKeys.trendsShowTargetBand) private var showTargetBand = true
    @AppStorage(SettingsKeys.trendsScaleFixed) private var scaleFixed = false
    @AppStorage(SettingsKeys.trendsFixedMax) private var fixedMax = 14

    init(store: any PersistenceStore) {
        self.store = store
        _model = State(initialValue: TrendsModel(store: store))
    }

    private var glucoseAxisMax: Double {
        scaleFixed ? Double(fixedMax) : model.autoGlucoseMax
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rangePicker
                    chart
                    metricChips
                    statCards
                    if model.range == .day { dayMeals }
                    footer
                }
                .padding(20)
            }
            .background(Color.surfacePrimary)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Options")
                    .accessibilityIdentifier("trends.options")
                }
            }
            .navigationDestination(for: MealRoute.self) { route in
                mealRouteDestination(route, store: store, path: $path)
            }
        }
        .sheet(isPresented: $showOptions) { TrendsOptionsSheet() }
        .task { await model.start() }
        .onChange(of: model.range) { _, _ in
            Task { await model.reload() }
        }
    }

    private var rangePicker: some View {
        let selection = Binding(get: { model.range }, set: { model.range = $0 })
        return Picker("Range", selection: selection) {
            Text("Day").tag(TrendsRange.day)
            Text("Week").tag(TrendsRange.week)
            Text("Month").tag(TrendsRange.month)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("trends.range")
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            if showTargetBand {
                RectangleMark(
                    yStart: .value("Low", TrendsMath.targetLowMmolL),
                    yEnd: .value("High", TrendsMath.targetHighMmolL)
                )
                .foregroundStyle(Color.bandTarget)
            }
            if showCarbs {
                ForEach(model.carbBars) { bar in
                    BarMark(
                        x: .value("Time", bar.date),
                        y: .value("Carbs", mappedCarb(bar.value))
                    )
                    .foregroundStyle(Color.medataAccent)
                }
            }
            if showGlucose {
                ForEach(model.glucoseLine) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Glucose", point.value)
                    )
                    .foregroundStyle(Color.seriesGlucose)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartYScale(domain: 0...glucoseAxisMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let mmol = value.as(Double.self) {
                        Text(mmol, format: .number.precision(.fractionLength(1)))
                    }
                }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        let grams = TrendsMath.mapAxisToCarbs(
                            axisValue,
                            carbAxisMax: model.carbAxisMax,
                            glucoseAxisMax: glucoseAxisMax
                        )
                        Text("\(Int(grams.rounded()))")
                    }
                }
            }
        }
        .frame(height: 260)
        .overlay(alignment: .topTrailing) {
            if !model.hasGlucose {
                Text("no glucose data")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(6)
                    .accessibilityIdentifier("trends.noGlucose")
            }
        }
    }

    private func mappedCarb(_ carbs: Double) -> Double {
        TrendsMath.mapCarbsToAxis(carbs, carbAxisMax: model.carbAxisMax, glucoseAxisMax: glucoseAxisMax)
    }

    // MARK: - Metric chips (§10.4)

    private var metricChips: some View {
        HStack(spacing: 10) {
            metricChip("Carbs", isOn: showCarbs) { showCarbs.toggle() }
            metricChip("Glucose", isOn: showGlucose) { showGlucose.toggle() }
            disabledChip("Protein · Fat")
            Spacer()
        }
    }

    private func metricChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? Color.medataAccent : Color.surfaceElevated, in: Capsule())
                .foregroundStyle(isOn ? Color.captureBackground : Color.textSecondary)
        }
        .accessibilityIdentifier("trends.chip.\(title.lowercased())")
    }

    private func disabledChip(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.textSecondary.opacity(0.5))
            .overlay(
                Capsule().stroke(
                    Color.textSecondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            )
    }

    // MARK: - Stat cards (§10.5)

    private var statCards: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard("Total carbs", "\(Int(model.totalCarbs.rounded())) g")
            statCard("Avg carbs/day", "\(Int(model.avgCarbsPerDay.rounded())) g")
            statCard("In range", inRangeValue)
            statCard("Avg glucose", avgGlucoseValue)
        }
    }

    private var inRangeValue: String {
        guard let tir = model.timeInRange else { return "—" }
        return "\(Int((tir * 100).rounded()))%"
    }

    private var avgGlucoseValue: String {
        guard let avg = model.averageGlucose else { return "—" }
        return String(format: "%.1f mmol/L", avg)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Day meal list (§10.6)

    private var dayMeals: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meals")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            if model.dayMeals.isEmpty {
                Text("no meals")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(model.dayMeals, id: \.id) { record in
                    NavigationLink(value: MealRoute.overview(record)) {
                        HStack {
                            Text(mealTime(record))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("\(Int(record.macros.totalCarbsG.rounded())) g")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mealTime(_ record: MealRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: record.createdAt)
    }

    // §10.7 safety copy — verbatim, exempt from the minimal-wording rule.
    private var footer: some View {
        Text("Glucose is read-only. Medata never writes to your glucose source.")
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
