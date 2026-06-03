import SupportPlane
import Testing
@testable import Pipeline

// Pins the pixel layout of `makeCentreRectangleMask` so future tweaks to the
// rounding convention break loudly. See
// `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` task 2.
@Suite("Centre-rectangle mask helper")
struct CentreRectangleMaskTests {

    @Test("10×10 at fillFraction 0.7 marks the [2,8) × [2,8) inner rectangle as food")
    func tenByTenSeventyPercent() {
        let mask = makeCentreRectangleMask(width: 10, height: 10, fillFraction: 0.7)
        #expect(mask.width == 10)
        #expect(mask.height == 10)
        #expect(mask.pixels.count == 100)
        for y in 0..<10 {
            for x in 0..<10 {
                let isInside = (x >= 2 && x < 8 && y >= 2 && y < 8)
                #expect(mask.isFood(x: x, y: y) == isInside,
                        "pixel (\(x),\(y)) should be \(isInside ? "1" : "0")")
            }
        }
    }

    @Test("pixel buffer length equals width * height for a non-square image")
    func pixelBufferLengthMatchesDimensions() {
        let mask = makeCentreRectangleMask(width: 100, height: 60, fillFraction: 0.7)
        #expect(mask.pixels.count == 100 * 60)
        #expect(mask.width == 100)
        #expect(mask.height == 60)
    }

    @Test("fillFraction = 1.0 fills the entire image")
    func fillFractionOneFillsEverything() {
        let mask = makeCentreRectangleMask(width: 8, height: 8, fillFraction: 1.0)
        for y in 0..<8 {
            for x in 0..<8 {
                #expect(mask.isFood(x: x, y: y), "expected pixel (\(x),\(y)) = 1")
            }
        }
    }

    @Test("small fillFraction shrinks the inner rectangle symmetrically")
    func smallFillFractionShrinksSymmetrically() {
        // fillFraction 0.5 on a 10×10 image → border = 0.25 →
        // xMin = ceil(0.25*10) = 3, xMax = floor(0.75*10) = 7.
        let mask = makeCentreRectangleMask(width: 10, height: 10, fillFraction: 0.5)
        for y in 0..<10 {
            for x in 0..<10 {
                let isInside = (x >= 3 && x < 7 && y >= 3 && y < 7)
                #expect(mask.isFood(x: x, y: y) == isInside,
                        "pixel (\(x),\(y)) should be \(isInside ? "1" : "0")")
            }
        }
    }

    @Test("default fill fraction constant is 0.7 (Decision 1)")
    func defaultFillFractionConstant() {
        #expect(centreRectangleFillFraction == 0.7)
    }
}
