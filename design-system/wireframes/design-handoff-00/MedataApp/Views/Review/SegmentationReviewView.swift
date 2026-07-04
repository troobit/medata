import SwiftUI

/// Pre-result step — user confirms / relabels segmentation regions.
struct SegmentationReviewView: View {
    let meal: Meal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlaceholderImage(label: "nadir capture · masks overlaid")
                    .aspectRatio(4/3, contentMode: .fit)
                    .padding(.horizontal, DS.spacingL)
                    .padding(.top, DS.spacingS)

                Text("Tap a region to confirm or relabel")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, DS.spacingL)
                    .padding(.top, 6)

                SectionHeader(text: "Detected (\(meal.classes.count))")
                    .padding(.horizontal, DS.spacingL)

                ForEach(meal.classes) { c in
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.ink2.opacity(0.6))
                            .frame(width: 10, height: 10)
                        Text(c.name).font(.subheadline)
                        Spacer()
                        ConfidenceChip(
                            confidence: Confidence(scale: c.confidence, segmentation: c.confidence, geometric: c.confidence),
                            compact: true
                        )
                    }
                    .padding(.horizontal, DS.spacingL)
                    .padding(.vertical, 10)
                    .overlay(Divider(), alignment: .bottom)
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unrecognised region.").font(.subheadline.weight(.semibold))
                        Text("A small area didn't match any known food and will be flagged as 'unknown carbs'.")
                            .font(.caption)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.warning)
                }
                .padding(DS.spacingM)
                .background(DS.warningSoft, in: RoundedRectangle(cornerRadius: DS.radiusS))
                .padding(.horizontal, DS.spacingL)
                .padding(.top, DS.spacingM)

                Button {
                    // Push result.
                } label: {
                    Text("Estimate carbs").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, DS.spacingL)
                .padding(.top, DS.spacingM)
                .padding(.bottom, DS.spacingL)
            }
        }
        .navigationTitle("Review foods")
        .navigationBarTitleDisplayMode(.inline)
    }
}
