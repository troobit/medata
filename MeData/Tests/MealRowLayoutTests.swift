import Testing
@testable import MeData

// Task 51 / Req §20.9 / Decision 16. Feed-style layout invariants for
// `MealRow`. The thumbnail target size is the headline regression risk
// (`PHImageManagerMaximumSize` would dominate memory) — assert the 2× row
// width contract directly.
@Suite("MealRow feed-style layout — 4:3 aspect + 2× thumbnail target")
struct MealRowLayoutTests {

    @Test("photo aspect ratio is 4:3 (Req §20.9)")
    func aspect4by3() {
        #expect(MealRowLayout.photoAspectRatio == 4.0 / 3.0)
    }

    @Test("row gap is 24pt (design-system/pages/meals-tab.md)")
    func rowSpacing() {
        #expect(MealRowLayout.rowSpacing == 24)
    }

    @Test("thumbnail target = 2× row width (not PHImageManagerMaximumSize)")
    func thumbnailTargetSizing() {
        let target = MealRowLayout.thumbnailTargetSize(rowWidth: 360)
        #expect(target.width == 720)
        #expect(target.height == 720 * 3.0 / 4.0)
    }

    @Test("zero row width does not divide by zero (defensive)")
    func zeroRowWidth() {
        let target = MealRowLayout.thumbnailTargetSize(rowWidth: 0)
        #expect(target.width > 0)
        #expect(target.height > 0)
    }

    @Test("photo corner radius is 14pt (design-system/pages/meals-tab.md)")
    func cornerRadius() {
        #expect(MealRowLayout.photoCornerRadius == 14)
    }
}
