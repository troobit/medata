import SwiftUI

/// Shared small bits used across screens.
struct ConfidenceChip: View {
    let confidence: Confidence
    var compact: Bool = false

    var body: some View {
        let lvl = confidence.level
        HStack(spacing: 4) {
            Image(systemName: lvl.sfSymbol)
                .font(.caption2)
            if !compact {
                Text(lvl.displayName)
                    .font(.caption.weight(.medium))
            }
            Text(String(format: "%.2f", confidence.meal))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(lvl.tint.opacity(0.12))
        )
        .overlay(Capsule().stroke(lvl.tint.opacity(0.6), lineWidth: 0.5))
        .foregroundStyle(lvl.tint)
    }
}

struct ClassBreakdownRow: View {
    let foodClass: FoodClass
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: DS.spacingM) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.ink2)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(foodClass.name).font(.subheadline.weight(.medium))
                    Text("\(Int(foodClass.massGrams.rounded())) g · vol \(Int(foodClass.volumeCubicCm.rounded())) cm³")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(carbDisplay)
                        .font(.subheadline.monospacedDigit())
                    Text("σ \(String(format: "%.2f", foodClass.confidence))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var carbDisplay: String {
        if foodClass.unknown { return "unknown" }
        if foodClass.unsupportedLiquid { return "n/a" }
        return "\(Int(foodClass.carbsGrams.rounded())) g"
    }
}

struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.spacingL)
            .padding(.bottom, DS.spacingXS)
    }
}

struct PlaceholderImage: View {
    let label: String
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let stripe: CGFloat = 8
                let count = Int((size.width + size.height) / stripe) + 2
                for i in 0..<count {
                    let x = CGFloat(i) * stripe - size.height
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height + stripe/2, y: size.height))
                    path.addLine(to: CGPoint(x: x + stripe/2, y: 0))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(i.isMultiple(of: 2)
                        ? Color(white: 0.92) : Color(white: 0.85)))
                }
            }
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
    }
}
