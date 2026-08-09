import Persistence
import PortableContracts
import SwiftUI
import Testing
@testable import MeData

// Task 50 / Req §20.8 / §20.11 / §20.12 / Decision 16. Layout invariants for
// the restyled ResultView — Dynamic Type clamp at AX5, action row visibility
// per presentation mode, placeholder chip presence per `segmenterSource`.
@Suite("ResultView layout — Dynamic Type clamp, placeholder chip, action row")
struct ResultViewLayoutTests {

    @Test("display points clamp at 88pt for AX5 (Req §20.12)")
    func displayClampAX5() {
        let ax5Points = ResultViewLayout.displayPoints(.accessibilityExtraExtraExtraLarge)
        #expect(ax5Points == ResultViewLayout.displayMaxPoints)
        #expect(ax5Points == 88)
    }

    @Test("base display points = 72pt at standard size (Req §20.8)")
    func displayBasePoints() {
        let points = ResultViewLayout.displayPoints(.large)
        #expect(points == 72)
    }

    @Test("display points never exceed max")
    func displayNeverExceedsMax() {
        for size in dynamicTypeSizes() {
            #expect(ResultViewLayout.displayPoints(size) <= ResultViewLayout.displayMaxPoints)
        }
    }

    // The presentation-mode contract is superseded: `ResultPresentation` was
    // removed by specs/ui/meal-review task 15 — ResultView now serves only
    // the Records/Graph history read path, and the capture-step surface is
    // MealReviewView.
}

private func dynamicTypeSizes() -> [ContentSizeCategory] {
    [
        .extraSmall, .small, .medium, .large, .extraLarge,
        .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge,
        .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge
    ]
}
