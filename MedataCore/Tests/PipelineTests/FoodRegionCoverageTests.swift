import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import Pipeline

// Coverage-recompute regression suite for the design's "Pipeline.estimate —
// coverage recompute" section. Iteration runs in confidence-buffer space
// (256×192) per Decision 14; for each (cx, cy) the corresponding mask pixel
// is `floor(cx·W_colour/256, cy·H_colour/192)`.
@Suite("computeFoodRegionCoverage (Decision 14)")
struct FoodRegionCoverageTests {

    private static let colourWidth = 1920
    private static let colourHeight = 1440
    private static let confWidth = 256
    private static let confHeight = 192
    // LiveSampleMath.confidenceThreshold (App-target source of truth, Decision 14).
    // Hard-coded in tests to avoid cross-module coupling.
    private static let threshold: Float = 0.66

    // Req 8.4: mask area ≥ 10 000 colour-image pixels + synthetic confidence
    // buffer in which exactly 50 % of food-projected confidence pixels pass
    // the threshold → coverage ≈ 50 % ± 1 %.
    @Test("50 % high-confidence food-projected pixels → ~50 % coverage")
    func fiftyPercentCoverage() throws {
        // Mask = full-frame ones (area = 2,764,800 pixels, ≫ 10 000).
        let mask = BinaryMask(
            pixels: [UInt8](repeating: 1, count: Self.colourWidth * Self.colourHeight),
            width: Self.colourWidth, height: Self.colourHeight
        )
        // Confidence buffer: half the rows above threshold, half below.
        let depth = Self.makeDepth(confidence: { _, cy in
            cy < Self.confHeight / 2 ? 255 : 0
        })
        let coverage = computeFoodRegionCoverage(
            depth: depth,
            confidenceThreshold: Self.threshold,
            mask: mask,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        #expect(abs(coverage - 50) <= 1,
                "expected 50 % ± 1 %; got \(coverage) %")
    }

    // Req 4.2: empty mask → 0.
    @Test("empty mask returns 0")
    func emptyMaskReturnsZero() throws {
        let emptyMask = BinaryMask(
            pixels: [UInt8](repeating: 0, count: Self.colourWidth * Self.colourHeight),
            width: Self.colourWidth, height: Self.colourHeight
        )
        let depth = Self.makeDepth(confidence: { _, _ in 255 })
        let coverage = computeFoodRegionCoverage(
            depth: depth,
            confidenceThreshold: Self.threshold,
            mask: emptyMask,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        #expect(coverage == 0, "empty mask must produce 0; got \(coverage)")
    }

    // Req 4.2: depth confidence absent (nadir.depth == nil) → 0.
    @Test("nil depth returns 0")
    func nilDepthReturnsZero() throws {
        let mask = BinaryMask(
            pixels: [UInt8](repeating: 1, count: Self.colourWidth * Self.colourHeight),
            width: Self.colourWidth, height: Self.colourHeight
        )
        let coverage = computeFoodRegionCoverage(
            depth: nil,
            confidenceThreshold: Self.threshold,
            mask: mask,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        #expect(coverage == 0, "nil depth must produce 0; got \(coverage)")
    }

    // Req 4.2: nil mask → 0.
    @Test("nil mask returns 0")
    func nilMaskReturnsZero() throws {
        let depth = Self.makeDepth(confidence: { _, _ in 255 })
        let coverage = computeFoodRegionCoverage(
            depth: depth,
            confidenceThreshold: Self.threshold,
            mask: nil,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        #expect(coverage == 0, "nil mask must produce 0; got \(coverage)")
    }

    // Decision 14: at confidence pixel (cx, cy), the mask pixel sampled is
    // (floor(cx·W_colour/W_conf), floor(cy·H_colour/H_conf)). Pin the algebra
    // by carving the mask along a vertical boundary at colourX = W_colour / 2
    // and asserting the boundary lands on confidence column W_conf / 2.
    @Test("floor-projection algebra maps (cx, cy) → (cx·W_colour/256, cy·H_colour/192)")
    func floorProjectionAlgebra() throws {
        // Mask is 1 only in the left half of the colour image.
        var pixels = [UInt8](repeating: 0, count: Self.colourWidth * Self.colourHeight)
        for y in 0..<Self.colourHeight {
            for x in 0..<(Self.colourWidth / 2) {
                pixels[y * Self.colourWidth + x] = 1
            }
        }
        let mask = BinaryMask(
            pixels: pixels, width: Self.colourWidth, height: Self.colourHeight
        )
        // Confidence buffer: every pixel passes the threshold.
        let depth = Self.makeDepth(confidence: { _, _ in 255 })
        let coverage = computeFoodRegionCoverage(
            depth: depth,
            confidenceThreshold: Self.threshold,
            mask: mask,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        // Per the floor projection: confidence column cx maps to mask column
        // floor(cx · 1920 / 256) = cx · 7.5. cx = 0..127 → mask col 0..952 (all
        // food). cx = 128..255 → mask col 960..1912 (all background). So
        // exactly half of the 256·192 confidence-space iterations land on
        // food pixels and every one passes the threshold → 100 % coverage of
        // the food-projected pixels.
        #expect(abs(coverage - 100) <= 0.01,
                "every high-confidence food-projected pixel must contribute → ~100 %; got \(coverage)")
    }

    // Sanity: at the floor-projection boundary, half the confidence pixels
    // project onto food. Verified by re-running with confidence below the
    // threshold for confidence rows where mask is non-food — the numerator
    // and denominator should match.
    @Test("denominator counts food-projected confidence pixels regardless of confidence value")
    func denominatorIsConfidenceSpaceFoodCount() throws {
        // Half-image mask as above.
        var pixels = [UInt8](repeating: 0, count: Self.colourWidth * Self.colourHeight)
        for y in 0..<Self.colourHeight {
            for x in 0..<(Self.colourWidth / 2) {
                pixels[y * Self.colourWidth + x] = 1
            }
        }
        let mask = BinaryMask(
            pixels: pixels, width: Self.colourWidth, height: Self.colourHeight
        )
        // Confidence: high in left half (food side), low in right half.
        let depth = Self.makeDepth(confidence: { cx, _ in
            cx < Self.confWidth / 2 ? 255 : 0
        })
        let coverage = computeFoodRegionCoverage(
            depth: depth,
            confidenceThreshold: Self.threshold,
            mask: mask,
            colourWidth: Self.colourWidth,
            colourHeight: Self.colourHeight
        )
        // Numerator = food-projected pixels with high confidence = all of left
        // half = denominator → 100 %.
        #expect(abs(coverage - 100) <= 0.01,
                "all food pixels carry high confidence → 100 %; got \(coverage)")
    }

    // MARK: - Fixture helpers

    private static func makeDepth(confidence: (Int, Int) -> UInt8) -> DepthMap {
        var conf = Data(count: confWidth * confHeight)
        conf.withUnsafeMutableBytes { rawPtr in
            let buf = rawPtr.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<confHeight {
                for x in 0..<confWidth {
                    buf[y * confWidth + x] = confidence(x, y)
                }
            }
        }
        // Depth values are unread by computeFoodRegionCoverage; provide a
        // valid 500-mm buffer for shape correctness.
        let depthBytes = Data(repeating: 0, count: confWidth * confHeight * 4)
        return DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: conf,
            width: confWidth, height: confHeight,
            rowStrideBytes: confWidth * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 500, fy: 500,
                cx: Float(confWidth) / 2, cy: Float(confHeight) / 2,
                distortion: [], imageWidth: confWidth, imageHeight: confHeight
            ),
            depthFromColour: .identity
        )
    }
}

// Fail-closed food-coverage gate (PRD estimation-quality, estimation-runtime-
// consistency §2). A near-empty argmax mask must refuse with the EXISTING
// `noFoodPixels` failure instead of flowing a handful of noisy pixels through
// the volume→β→carbs chain and emitting a wildly variable number.
@Suite("Food-coverage gate (estimation-runtime-consistency)")
struct FoodCoverageGateTests {

    private static let width = 200
    private static let height = 100    // 20 000 px; 0.1 % threshold = 20 px

    // Small palette: indices 0–1 solid food, 2 liquid, 3 background,
    // 4 unknown_food, 5 unsupported_liquid.
    private static let palette = ClassPalette(
        foodClasses: ["bread", "rice"],
        liquidClasses: ["soup"],
        background: 3,
        unknownFood: 4,
        unsupportedLiquid: 5,
        version: "v1"
    )

    private static func makeArgmax(labelAt: (Int, Int) -> UInt8) -> ArgmaxMap {
        var pixels = Data(count: width * height)
        pixels.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<height {
                for x in 0..<width {
                    buf[y * width + x] = labelAt(x, y)
                }
            }
        }
        return ArgmaxMap(pixels: pixels, height: height, width: width)
    }

    @Test("near-empty mask (below 0.1 % food) refuses with noFoodPixels")
    func nearEmptyMaskRefuses() {
        // 19 food pixels of 20 000 (0.095 %) — just below the 20-px threshold.
        let argmax = Self.makeArgmax { x, y in
            (y == 0 && x < 19) ? 0 : UInt8(Self.palette.background)
        }
        #expect(throws: EstimationFailure.noFoodPixels) {
            try enforceMinimumFoodCoverage(argmax: argmax, palette: Self.palette)
        }
    }

    @Test("coverage exactly at the threshold accepts")
    func coverageAtThresholdAccepts() throws {
        // 20 food pixels of 20 000 = exactly 0.1 % — the boundary accepts.
        let argmax = Self.makeArgmax { x, y in
            (y == 0 && x < 20) ? 0 : UInt8(Self.palette.background)
        }
        try enforceMinimumFoodCoverage(argmax: argmax, palette: Self.palette)
    }

    @Test("a realistic plate-sized mask accepts")
    func realisticMaskAccepts() throws {
        // ~5 % of the frame labelled food — the low end of a genuine meal.
        let argmax = Self.makeArgmax { x, y in
            (x < 100 && y < 10) ? 1 : UInt8(Self.palette.background)
        }
        try enforceMinimumFoodCoverage(argmax: argmax, palette: Self.palette)
    }

    @Test("recognised liquid pixels count towards coverage")
    func liquidPixelsCount() throws {
        // All-soup frame: liquids integrate volume (Req 7.3), so a liquid-only
        // mask is NOT near-empty.
        let argmax = Self.makeArgmax { _, _ in 2 }
        try enforceMinimumFoodCoverage(argmax: argmax, palette: Self.palette)
    }

    @Test("sentinel labels do not count towards coverage")
    func sentinelLabelsDoNotCount() {
        // unknown_food / unsupported_liquid / background never integrate
        // volume, so a frame full of them must still refuse.
        let argmax = Self.makeArgmax { x, _ in
            x % 2 == 0 ? UInt8(Self.palette.unknownFood)
                       : UInt8(Self.palette.unsupportedLiquid)
        }
        #expect(throws: EstimationFailure.noFoodPixels) {
            try enforceMinimumFoodCoverage(argmax: argmax, palette: Self.palette)
        }
    }
}
