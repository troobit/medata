import Foundation
import Segmentation
import XCTest
@testable import Volume

// Tests for MaskMatcher per design §6.11.
// Simple class-equivalence on per-view label maps; no spatial matching.

final class MaskMatcherTests: XCTestCase {

    // MARK: - fixtures

    // palette: food_0=0, food_1=1, bg=2, unknown=3, liquid=4
    let palette = makePalette(numFood: 2)

    func argmax(width: Int = 4, height: Int = 4,
                label: (Int, Int) -> Int) -> ArgmaxMap {
        makeArgmax(width: width, height: height, label: label)
    }

    // MARK: - T33.1 Intersection gives matched_classes

    func testIntersectionGivesMatchedClasses() {
        // View 1: food_0 and food_1 present.
        // View 2: food_1 and (bg only, no food_0).
        // matched = {1}, singleViewOnly = {0}.
        let v1 = argmax { y, x in x < 2 ? 0 : 1 }     // left half = food_0, right = food_1
        let v2 = argmax { _, _ in 1 }                   // all food_1

        let result = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(result.matchedClasses, [1],
            "matched = intersection = {food_1}")
        XCTAssertEqual(result.classesInView1, [0, 1])
        XCTAssertEqual(result.classesInView2, [1])
    }

    // MARK: - T33.2 Symmetric difference gives single_view_only_classes

    func testSymmetricDifferenceGivesSingleViewOnly() {
        // View 1: food_0 only.
        // View 2: food_1 only.
        // matched = {}, singleViewOnly = {0, 1}.
        let v1 = argmax { _, _ in 0 }
        let v2 = argmax { _, _ in 1 }

        let result = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(result.matchedClasses, [],
            "No class appears in both views")
        XCTAssertEqual(result.singleViewOnlyClasses, [0, 1],
            "Both classes are single-view-only")
    }

    // MARK: - T33.3 singleViewOnly(view:) returns the per-view subset

    func testSingleViewOnlyPerViewSubset() {
        // View 1: food_0 only.  View 2: food_1 only.
        let v1 = argmax { _, _ in 0 }
        let v2 = argmax { _, _ in 1 }
        let result = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(result.singleViewOnly(view: 1), [0])
        XCTAssertEqual(result.singleViewOnly(view: 2), [1])
    }

    // MARK: - T33.4 Background and special classes are excluded

    func testSpecialClassesExcluded() {
        let bgId = palette.background            // 2
        let liqId = palette.unsupportedLiquid    // 4
        // All pixels labelled bg or liquid — no food present in either view.
        let v1 = argmax { y, _ in y < 2 ? bgId : liqId }
        let v2 = argmax { _, _ in bgId }

        let result = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(result.matchedClasses, [],
            "Background / liquid classes must not appear in matched set")
        XCTAssertEqual(result.classesInView1, [],
            "classesInView1 should be empty when only special classes present")
        XCTAssertEqual(result.classesInView2, [])
    }

    // MARK: - T33.5 Both views identical → full match, no single-view-only classes

    func testIdenticalViewsFullMatch() {
        let v1 = argmax { y, x in x < 2 ? 0 : 1 }
        let v2 = argmax { y, x in x < 2 ? 0 : 1 }
        let result = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(result.matchedClasses, [0, 1])
        XCTAssertEqual(result.singleViewOnlyClasses, [])
    }

    // MARK: - T33.6 Equatable conformance

    func testEquatable() {
        let v1 = argmax { _, _ in 0 }
        let v2 = argmax { _, _ in 0 }
        let r1 = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        let r2 = MaskMatcher.match(view1: v1, view2: v2, palette: palette)
        XCTAssertEqual(r1, r2)
    }
}
