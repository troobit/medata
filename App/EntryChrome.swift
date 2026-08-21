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
        .accessibilityIdentifier(identifier)
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
