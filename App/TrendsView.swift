import Charts
import Pipeline
import SwiftUI

// The Graph screen (renamed from Trends — Decision 21) — design-handoff-00 §10,
// design-system/pages/trends.md. Visualisation only (home-router Req 2): it
// presents as a full-screen cover from the home page, carrying the standard
// close control; the Capture / Data / Settings / Insulin entry points moved to
// the home page and the insulin dose sheet relocated to AppRoot (Decision 10).
// A single-chart dual-series view: glucose as a line (mmol/L, leading axis)
// and carbs as bars (g, trailing axis relabelled in grams) over a shared
// y-scale (the single-scale workaround), with the 3.9–10.0 mmol/L target band.
// Week and Month aggregate to per-day totals and averages. Reads glucose
// exclusively from `bsl` events (Req 11.1); all bucketing / axis maths is
// `TrendsMath`.
struct TrendsView: View {
    let store: any PersistenceStore

    @Environment(\.dismiss) private var dismiss
    @State private var model: TrendsModel
    @State private var path: [MealRoute] = []
    @State private var showOptions = false

    @AppStorage(SettingsKeys.trendsShowCarbs) private var showCarbs = true
    @AppStorage(SettingsKeys.trendsShowGlucose) private var showGlucose = true
    @AppStorage(SettingsKeys.trendsShowInsulin) private var showInsulin = true
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
                    if model.range == .day {
                        dayMeals
                        dayInsulin
                    }
                }
                .padding(20)
            }
            .background(Color.surfacePrimary)
            // Deliberately untitled (snaqui Req 4): full-screen pages carry no
            // navigation title — the band goes to content.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Graph is a cover now (Req 1.4): the standard close control
                // top-leading, chart options top-trailing. The navigation
                // entry points (Capture / Data / Settings / Insulin) moved to
                // the home page (Req 2.3).
                ToolbarItem(placement: .topBarLeading) {
                    CloseCoverButton { dismiss() }
                }
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
                        y: .value("Carbs", mappedCarb(bar.value)),
                        width: carbBarWidth
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
            // Insulin band (App 6): small glyphs pinned just above the x-axis
            // — the established CGM-app pattern — clear of the glucose plot
            // band (3.9+ mmol/L). Day: one glyph per dose, bolus (teal circle)
            // and basal (purple square) distinct. Week/Month: per-day total
            // units, diamond. Unit counts sit above each glyph.
            if showInsulin {
                ForEach(model.insulinMarkers) { marker in
                    PointMark(
                        x: .value("Time", marker.date),
                        y: .value("Insulin", insulinBandY)
                    )
                    .symbol(insulinSymbol(for: marker.kind))
                    .symbolSize(60)
                    .foregroundStyle(
                        marker.kind == .basal
                            ? Color.seriesInsulinBasal : Color.seriesInsulinBolus
                    )
                    .annotation(position: .top, spacing: 1) {
                        Text("\(Int(marker.units.rounded()))")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        // Pin the x-domain to the whole selected range. Without this the
        // domain shrinks to the data extent — with a single meal the day chart
        // degenerated to a huge centred bar (see task 6 findings).
        .chartXScale(domain: model.interval.start...model.interval.end)
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

    // Day bars sit on a continuous time axis where the automatic width is
    // plot-width ÷ mark-count — a lone meal rendered as an obstructive slab at
    // its timestamp (task 6). A fixed narrow width keeps every meal a slim
    // bar; Week/Month keep the automatic per-day width.
    private var carbBarWidth: MarkDimension {
        model.range == .day ? .fixed(6) : .automatic
    }

    // The insulin band's y-position: a whisker above the axis line, well below
    // the glucose trace's plot band whichever y-scale is active.
    private var insulinBandY: Double { glucoseAxisMax * 0.04 }

    private func insulinSymbol(for kind: InsulinKind?) -> BasicChartSymbolShape {
        switch kind {
        case .bolus: return .circle
        case .basal: return .square
        case nil: return .diamond  // per-day aggregate (Week/Month)
        }
    }

    // MARK: - Metric chips (§10.4, reshaped by snaqui Req 5)

    // The chips are the chart's legend as much as its switches: an active chip
    // fills with the colour of the series it toggles (carbs green, glucose
    // orange, insulin bolus-teal — the week/month aggregate colour), so the
    // chip↔series mapping reads at a glance. `ChipFlow` wraps the row onto a
    // second line rather than letting a fixed HStack compress the labels to
    // ellipsis in portrait.
    private var metricChips: some View {
        ChipFlow(spacing: 10, lineSpacing: 8) {
            metricChip("Carbs", series: .medataAccent, isOn: showCarbs) { showCarbs.toggle() }
            metricChip("Glucose", series: .seriesGlucose, isOn: showGlucose) { showGlucose.toggle() }
            metricChip("Insulin", series: .seriesInsulinBolus, isOn: showInsulin) { showInsulin.toggle() }
            disabledChip("Protein · Fat")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricChip(
        _ title: String, series: Color, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? series : Color.surfaceElevated, in: Capsule())
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
            statCard("Total insulin", "\(Int(model.totalInsulinUnits.rounded())) U")
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
                            Text("\(model.displayCarbs(for: record)) g")
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
        timeLabel(record.createdAt)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Day insulin list (App 8)

    // The day's doses beside the Meals list, read-only (Req 2.4 — deletion
    // lives on the Records surface). The List is height-pinned and
    // scroll-disabled so it reads as a plain section of the ScrollView.
    private let doseRowHeight: CGFloat = 44

    private var dayInsulin: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insulin")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            if model.dayDoses.isEmpty {
                Text("no doses")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            } else {
                List {
                    ForEach(model.dayDoses) { dose in
                        doseRow(dose)
                            .listRowBackground(Color.surfacePrimary)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .environment(\.defaultMinListRowHeight, doseRowHeight)
                .frame(height: CGFloat(model.dayDoses.count) * doseRowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doseRow(_ dose: InsulinEntry) -> some View {
        HStack {
            Text(timeLabel(dose.timestamp))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Text(dose.kind == .bolus ? "Bolus" : "Basal")
                .font(.subheadline)
                .foregroundStyle(
                    dose.kind == .basal ? Color.seriesInsulinBasal : Color.seriesInsulinBolus
                )
            Spacer()
            Text("\(Int(dose.units.rounded())) U")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityIdentifier("graph.dose.\(dose.id.uuidString)")
    }
}

// Leading-aligned wrapping row for the metric chips (snaqui Req 5): each chip
// keeps its natural size and overflow starts a new line, so nothing ever
// compresses to an ellipsis. Chips are measured with an unspecified proposal
// (their ideal size) both when building lines and when placing them.
private struct ChipFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(fitting: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, lines.count - 1))
        let width = proposal.width ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for line in lines(fitting: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(fitting maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let gap = current.indices.isEmpty ? 0 : spacing
            if !current.indices.isEmpty, current.width + gap + size.width > maxWidth {
                lines.append(current)
                current = Line()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
