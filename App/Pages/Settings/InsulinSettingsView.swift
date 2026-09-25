import Dosing
import SwiftUI

// Insulin preferences, reached from Settings (specs/ui/settings-information-
// architecture): the per-kind product defaults, the time-of-day carbohydrate
// ratios, where the ratios come from, and the recurring dose schedule with its
// reminder cadence (`DoseScheduleSettingsSection.swift`).
struct InsulinSettingsView: View {
    // The recurring dose schedule (specs/data/dose-schedule Req 1.3, 1.4, 3.2,
    // 3.3). Owned by AppRoot so the outstanding set survives the Settings cover
    // being presented and dismissed.
    let doseSchedule: DoseScheduleModel
    // The outstanding-dose gear lands here: when set, the Form scrolls to the
    // dose-schedule section on appear instead of opening at the top.
    var scrollToDoseSchedule: Bool = false

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

    var body: some View {
        ScrollViewReader { proxy in
            insulinForm(proxy: proxy)
        }
    }

    private func insulinForm(proxy: ScrollViewProxy) -> some View {
        Form {
            Section("Product") {
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
            }

            // Carbohydrate ratios in band order (specs/data/insulin-dosing
            // Req 1.2, 6.9). The STORED value is grams per unit and the field is
            // suffixed g/U so the direction is on screen at all times; the
            // reciprocal beneath spells out the developer's own phrasing —
            // "= 2.0 U per 10 g" — so the two conventions are visibly the same
            // number and nobody has to hold the inversion in their head. A field
            // labelled merely "Ratio" is the trap this layout exists to close.
            Section("Carbohydrate ratio") {
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
        }
        .navigationTitle("Insulin")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard scrollToDoseSchedule else { return }
            // Deferred one turn so the List has laid out before the scroll.
            Task { proxy.scrollTo("doseScheduleSection", anchor: .top) }
        }
    }

    // MARK: - Carbohydrate ratio row (specs/data/insulin-dosing Req 1.2, 1.5)

    // Colocated: a one-row view with no other caller.
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
}
