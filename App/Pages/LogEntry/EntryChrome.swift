import SwiftUI

// The parts of a manual-entry sheet that are the same job in every mode
// (`LogSheet`). Before this file, the insulin sheet and the carb sheet each
// carried their own byte-identical copy of the back-dating DatePicker and of
// the accent commit button, and a third sheet for activity would have carried
// a third. The unification is here, not in the numeral controls: what differs
// between logging a dose, an activity and a carbohydrate amount is the shape
// of the quantity, and nothing else.

// The compact back-dating control (insulin PRD App 4, manual-carb-intake
// Req 1.2, activity-events Req 3.2). Future instants are forbidden by the
// `...Date()` range; the default stays "now" on every happy path.
struct EntryTimeRow: View {
    @Binding var timestamp: Date
    let identifier: String

    var body: some View {
        DatePicker(
            "Time",
            selection: $timestamp,
            in: ...Date(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .environment(\.locale, Locale(identifier: "en_IE"))
        .accessibilityIdentifier(identifier)
    }
}

// The committing control — the one accent-filled surface on the sheet
// (design-direction §1, "committed" register). Its label always names the
// value it is about to write, which is why no confirmation surface exists
// anywhere in this flow.
struct EntrySaveButton: View {
    let title: String
    let isSaving: Bool
    let isEnabled: Bool
    let identifier: String
    let action: () -> Void

    // Every entry sheet commits through this button, so putting the haptic
    // HERE gives insulin, glucose, activity and carbohydrate entry the same
    // confirmation in the hand for one line of code. `isSaving` falling back
    // to false is the moment the write landed, so the counter it drives is
    // the honest trigger — it cannot fire on a save that failed to start.
    @State private var commits = 0

    var body: some View {
        Button(action: action) {
            if isSaving {
                MedataLoadingSymbol(mode: .loop, size: 22)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.medataAccent)
        .foregroundStyle(Color.captureBackground)
        .disabled(!isEnabled || isSaving)
        .commitFeedback(trigger: commits)
        .onChange(of: isSaving) { wasSaving, nowSaving in
            if wasSaving, !nowSaving { commits += 1 }
        }
        .accessibilityIdentifier(identifier)
    }
}

// The one place a failed write says so (manual-carb-intake Req 2.5, and the
// same shape on glucose, insulin, activity and preset saves). Six sheets
// carried a byte-identical `Text(...).font(.footnote).foregroundStyle(.red)`
// under their save button; the copy is the model's `saveError` string, which
// already names the underlying failure.
//
// It renders NOTHING when there is no error — deliberately a view that takes
// the optional rather than an `if let` at each call site, so a sheet cannot
// forget the treatment and invent its own.
// One treatment for a failed save, so six sheets cannot each invent their own.
//
// Takes a NON-optional message and the call site keeps its `if let`. The
// tempting shape — an optional message and a body that renders nothing when
// nil — makes each call site one line shorter but puts an always-present view
// into a `VStack` that has spacing, and whether a spacing gap appears around a
// view that renders nothing is a question about SwiftUI's layout rather than
// about this code. Two lines at the call site is the price of not having to
// answer it.
struct EntrySaveError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

// A selectable chip among peers. Deliberately NOT accent-coloured: on every
// surface in this app the accent means "this writes a row", and picking a
// kind writes nothing. The treatment is the plate-fraction control's, moved
// to the grouped palette — filled `textPrimary` when active, `surfaceElevated`
// otherwise (MealReviewView.scaleControl).
struct EntryChip: View {
    let title: String
    let isActive: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isActive ? Color.textPrimary : Color.surfaceElevated, in: Capsule()
                )
                .foregroundStyle(isActive ? Color.surfacePrimary : Color.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// Leading-aligned wrapping row (snaqui Req 5): each chip keeps its natural
// size and overflow starts a new line, so nothing ever compresses to an
// ellipsis. Chips are measured with an unspecified proposal (their ideal
// size) both when building lines and when placing them.
//
// Relocated here from `TrendsView` when the activity kind picker needed the
// same behaviour — the Graph's metric chips and the entry sheet's kind chips
// are one layout, not two.
struct ChipFlow: Layout {
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
