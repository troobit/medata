import Persistence
import SwiftUI

// ONE manual-entry surface, three modes.
//
// Logging a dose, logging an activity and logging a carbohydrate amount are
// the same shape of job: name a kind, give a quantity, say when, commit. They
// had two near-identical sheets and were about to get a third. This is that
// third sheet refusing to exist.
//
// The mode selector is the sheet's TITLE — a menu where a static navigation
// title used to be. That is the whole cost of the consolidation in layout
// terms: zero points of added height, no second segmented control stacked
// above the insulin sheet's Bolus/Basal picker, and nothing inserted into any
// happy path. Every entry point names its own mode, so the selector is a way
// out of a wrong turn, never a step on the way in:
//
//   Home "Dose"           → .insulin  → Save            2 taps, unchanged
//   Home "Activity"       → .activity → Save            2 taps
//   medata://insulin/add  → .insulin  → Save            2 taps, unchanged
//   medata://activity/add → .activity → Save            2 taps (Req 3.1, 3.5)
//   Intake "Enter amount" → .carbs                      unchanged
//
// What the consolidation buys: one back-dating control, one commit button,
// one detent, one dismissal contract, one place a fourth event type lands.
// What it costs is written down honestly in the report — chiefly that the
// carbohydrate mode does not fit the grammar as cleanly as the other two.
struct LogSheet: View {
    // Modes are ordered by how often they are logged, which is also the order
    // the menu lists them in.
    enum Mode: String, Identifiable, CaseIterable {
        case insulin
        case activity
        case carbs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .insulin: "Insulin"
            case .activity: "Activity"
            case .carbs: "Carbs"
            }
        }

        var symbol: String {
            switch self {
            case .insulin: "syringe"
            case .activity: "figure.run"
            case .carbs: "carrot"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var insulin: InsulinDoseModel
    @State private var activity: ActivityModel
    @State private var carbs: CarbEntryModel

    private let nextSortOrder: Int
    // The dose-schedule ADJUST path (specs/data/dose-schedule Req 5.1) and the
    // suggestion linkage (insulin-dosing Req 7.5) both reach the insulin mode
    // through the same door as everything else: the schedule seeds the opening
    // amount and each caller is told which event the save wrote and how many
    // units it recorded. No schedule-specific control appears, and no fourth
    // mode.
    private let onInsulinSaved: ((UUID, Int) -> Void)?

    init(
        store: any PersistenceStore,
        mode: Mode = .insulin,
        seedUnits: Int? = nil,
        seedKind: InsulinKind? = nil,
        seed: DoseSeed? = nil,
        nextSortOrder: Int = 0,
        onInsulinSaved: ((UUID, Int) -> Void)? = nil
    ) {
        _mode = State(initialValue: mode)
        let insulinModel = InsulinDoseModel(store: store, seed: seed)
        if let seedUnits {
            insulinModel.seed(units: seedUnits, kind: seedKind ?? insulinModel.kind)
        } else if let seedKind {
            insulinModel.kind = seedKind
        }
        _insulin = State(initialValue: insulinModel)
        _activity = State(initialValue: ActivityModel(store: store))
        _carbs = State(initialValue: CarbEntryModel(store: store))
        self.nextSortOrder = nextSortOrder
        self.onInsulinSaved = onInsulinSaved
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.surfacePrimary)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { modeMenu }
                }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // The insulin and activity modes are fixed-height compositions and sit
    // directly in the sheet; the carbohydrate mode carries a macros
    // disclosure that can grow past the medium detent, so it keeps its own
    // ScrollView. That asymmetry is the first honest seam in the
    // consolidation — see the mode's own comment.
    @ViewBuilder
    private var content: some View {
        switch mode {
        case .insulin:
            InsulinDoseContent(
                model: insulin,
                onSaved: {
                    if let eventID = insulin.savedEventID {
                        onInsulinSaved?(eventID, insulin.units)
                    }
                    dismiss()
                }
            )
        case .activity:
            ActivityContent(model: activity, onSaved: { dismiss() })
        case .carbs:
            CarbEntryContent(
                model: carbs, nextSortOrder: nextSortOrder, onFinished: { dismiss() }
            )
        }
    }

    // A title that is also the switch. The chevron is the only affordance it
    // needs: menus are the one iOS control where a downward chevron beside a
    // label is already understood, so no label explains it and no segmented
    // control competes with the Bolus/Basal picker underneath.
    private var modeMenu: some View {
        Menu {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { candidate in
                    Label(candidate.title, systemImage: candidate.symbol)
                        .tag(candidate)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Entry mode, \(mode.title)")
        .accessibilityIdentifier("log.mode")
    }
}
