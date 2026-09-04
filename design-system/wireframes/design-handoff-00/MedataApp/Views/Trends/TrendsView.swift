import SwiftUI
import Charts

/// Historical graphs — carbs (bars, right axis, g) and blood glucose
/// (line, left axis, mmol/L) over a shared time axis.
///
/// Swift Charts has a single y-scale per chart, so carbs are mapped into
/// the glucose domain and the trailing axis is labelled in grams manually.
struct TrendsView: View {
    @EnvironmentObject var env: AppEnvironment

    enum Range: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"
        var id: String { rawValue }
    }

    @State private var range: Range = .day
    @State private var options = TrendsGraphOptions()
    @State private var showingOptions = false
    @State private var glucose: [GlucoseReading] = []

    private let week = SampleTrends.lastWeek()

    /// Glucose y-domain. Auto stretches to data; fixed uses the user max.
    private var glucoseMax: Double {
        options.scaleMode == .fixed
            ? options.fixedMaxMmolPerL
            : max(12, (glucose.map(\.mmolPerL).max() ?? 12) + 1)
    }
    /// g-of-carbs represented by the full chart height.
    private let carbAxisMax: Double = 80

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingM) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)

                switch range {
                case .day:   dayChart
                case .week:  weekChart
                case .month: weekChart   // wireframe reuses the rollup shape
                }

                metricChips
                summaryStats

                if range == .day { mealsList }

                Label("Glucose data imported from CGM — read-only. Medata never writes to your glucose device.",
                      systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.spacingS)
            }
            .padding(.horizontal, DS.spacingL)
            .padding(.bottom, DS.spacingXL)
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingOptions = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            TrendsOptionsSheet(options: $options)
                .presentationDetents([.medium, .large])
        }
        .task {
            let cal = Calendar.current
            let start = cal.startOfDay(for: .now)
            let interval = DateInterval(start: start.addingTimeInterval(6 * 3600),
                                        end: start.addingTimeInterval(22 * 3600))
            glucose = (try? await MockGlucoseSource().readings(in: interval)) ?? []
        }
    }

    // MARK: - Day chart (dual series)

    private var dayChart: some View {
        Chart {
            if options.showTargetBand && options.showGlucose {
                RectangleMark(yStart: .value("Low", 3.9), yEnd: .value("High", 10.0))
                    .foregroundStyle(DS.success.opacity(0.10))
            }
            if options.showCarbs {
                ForEach(env.mealStore.meals) { meal in
                    BarMark(
                        x: .value("Time", meal.capturedAt),
                        y: .value("Carbs", meal.totalCarbs / carbAxisMax * glucoseMax),
                        width: 14
                    )
                    .foregroundStyle(DS.ink.opacity(0.35))
                }
            }
            if options.showGlucose {
                ForEach(glucose) { r in
                    LineMark(
                        x: .value("Time", r.takenAt),
                        y: .value("Glucose", r.mmolPerL)
                    )
                    .foregroundStyle(DS.warning)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartYScale(domain: 0...glucoseMax)
        .chartYAxis {
            // Leading axis: glucose in mmol/L.
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2).foregroundStyle(DS.warning)
                    }
                }
            }
            // Trailing axis: same positions relabelled in grams.
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v / glucoseMax * carbAxisMax))g")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 220)
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }

    // MARK: - Week chart (daily rollup)

    private var weekChart: some View {
        Chart {
            if options.showCarbs {
                ForEach(week) { d in
                    BarMark(
                        x: .value("Day", d.day, unit: .day),
                        y: .value("Carbs", d.totalCarbsGrams / 200 * glucoseMax)
                    )
                    .foregroundStyle(DS.ink.opacity(0.35))
                }
            }
            if options.showGlucose {
                ForEach(week) { d in
                    LineMark(
                        x: .value("Day", d.day, unit: .day),
                        y: .value("Avg glucose", d.avgGlucoseMmolPerL)
                    )
                    .foregroundStyle(DS.warning)
                    .symbol(.circle)
                }
            }
        }
        .chartYScale(domain: 0...glucoseMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2).foregroundStyle(DS.warning)
                    }
                }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v / glucoseMax * 200))g")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 220)
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }

    // MARK: - Chrome

    private var metricChips: some View {
        HStack(spacing: DS.spacingS) {
            MetricChip(label: "Carbs", active: options.showCarbs, tint: DS.ink) {
                options.showCarbs.toggle()
            }
            MetricChip(label: "Glucose", active: options.showGlucose, tint: DS.warning) {
                options.showGlucose.toggle()
            }
            MetricChip(label: "Protein", active: false, tint: DS.ink3, enabled: false) {}
            MetricChip(label: "Fat", active: false, tint: DS.ink3, enabled: false) {}
        }
    }

    private var summaryStats: some View {
        HStack(spacing: DS.spacingS) {
            StatCard(label: range == .day ? "Total carbs" : "Avg carbs/day",
                     value: range == .day ? "149 g" : "143 g")
            StatCard(label: "Time in range", value: range == .day ? "78%" : "74%")
            StatCard(label: "Avg glucose", value: "6.8")
        }
    }

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Meals this day")
            ForEach(env.mealStore.meals) { meal in
                NavigationLink(value: Route.result(meal)) {
                    HStack {
                        PlaceholderImage(label: "")
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meal.title).font(.subheadline)
                            Text(meal.capturedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(meal.displayCarbs) g")
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .overlay(Divider(), alignment: .bottom)
            }
        }
    }
}

// MARK: - bits

struct MetricChip: View {
    let label: String
    let active: Bool
    let tint: Color
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if active { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(enabled ? (active ? tint : .secondary) : Color(.tertiaryLabel))
            .background(
                Capsule().strokeBorder(
                    enabled ? (active ? tint : Color(.separator)) : Color(.separator),
                    style: StrokeStyle(lineWidth: 1, dash: enabled ? [] : [3, 3])
                )
            )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }
}
