import XCTest
@testable import Segmentation

final class PostProcessingTests: XCTestCase {

    // MARK: - helpers

    /// Test palette: 2 food classes + bg(2) + unknownFood(3) + unsupportedLiquid(4) = 5 classes.
    func makeTestPalette(numFoodClasses: Int = 2) -> ClassPalette {
        ClassPalette(
            foodClasses: (0..<numFoodClasses).map { "food_\($0)" },
            background: numFoodClasses,
            unknownFood: numFoodClasses + 1,
            unsupportedLiquid: numFoodClasses + 2,
            version: "test"
        )
    }

    /// Build a one-hot logits buffer (large magnitude → softmax peak ≈ 1.0).
    func makeOneHotLogits(
        targetSize: Int, classes: Int,
        labelAt: (Int, Int) -> Int,
        magnitude: Float = 12
    ) -> [Float] {
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        for y in 0..<targetSize {
            for x in 0..<targetSize {
                let lab = labelAt(y, x)
                logits[(y * targetSize + x) * classes + lab] = magnitude
            }
        }
        return logits
    }

    // MARK: - Resize-back (Step 10 of §6.5)

    func testResizeBackToOriginalDimensions() throws {
        let palette = makeTestPalette()
        let targetSize = 8
        let classes = palette.totalClasses
        // Half-full padded canvas: scaledW=8, scaledH=4 (from a 16×8 original).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, _ in 0 }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: 8, scaledHeight: 4,
            originalWidth: 16, originalHeight: 8,
            palette: palette
        )
        XCTAssertEqual(out.probabilities.height, 8)
        XCTAssertEqual(out.probabilities.width, 16)
        XCTAssertEqual(out.probabilities.classes, classes)
        XCTAssertEqual(out.argmax.height, 8)
        XCTAssertEqual(out.argmax.width, 16)
        XCTAssertEqual(out.probabilities.bytes.count, 8 * 16 * classes * 2)
        // Every pixel argmaxes to class 0.
        out.argmax.pixels.forEach { XCTAssertEqual($0, 0) }
    }

    func testResizeBackPreservesPixelCentreAlignment() throws {
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        // Left half → class 0, right half → class 1 (in padded space).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, x in
            x < 2 ? 0 : 1
        }
        // This test asserts the RAW resize/argmax alignment, so the speckle
        // cleanup is disabled: on a 4×4 map both 8 px halves sit below the
        // standard minimum-region threshold and would be reassigned.
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: 4, scaledHeight: 4,
            originalWidth: 4, originalHeight: 4,
            palette: palette,
            regularisation: .disabled
        )
        // Identity resize: left half labelled 0, right half labelled 1.
        out.argmax.pixels.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self)
            for y in 0..<4 {
                XCTAssertEqual(buf[y * 4 + 0], 0)
                XCTAssertEqual(buf[y * 4 + 1], 0)
                XCTAssertEqual(buf[y * 4 + 2], 1)
                XCTAssertEqual(buf[y * 4 + 3], 1)
            }
        }
    }

    // MARK: - Spatial regularisation (speckle removal)

    func testRegularisationRemovesSpeckleAndPreservesLargeRegion() {
        let width = 64
        let height = 64
        let bg: UInt8 = 2
        var labels = [UInt8](repeating: bg, count: width * height)

        // Large contiguous food region: 20×20 block of class 0 (400 px, far above
        // the 12 px threshold).
        for y in 10..<30 {
            for x in 10..<30 { labels[y * width + x] = 0 }
        }

        // Sub-threshold speckle: isolated single pixels and one 2×2 blob, all
        // well away from the block and from each other (every region < 12 px).
        let specklePixels: [(y: Int, x: Int, cls: UInt8)] = [
            (2, 40, 0), (5, 50, 1), (40, 5, 1), (55, 55, 0),
            (45, 40, 1), (45, 41, 1), (46, 40, 1), (46, 41, 1),   // 2×2 blob
        ]
        for s in specklePixels { labels[s.y * width + s.x] = s.cls }

        let input = Data(labels)
        let palette = makeTestPalette()
        let cleaned = regulariseLabelMap(input, width: width, height: height, palette: palette, config: .standard)
        let out = [UInt8](cleaned)

        // Every speckle region is reassigned to its dominant neighbour (background).
        for s in specklePixels {
            XCTAssertEqual(out[s.y * width + s.x], bg,
                           "speckle at (\(s.y),\(s.x)) should be reassigned to background")
        }

        // The large contiguous food region survives with its area preserved
        // exactly (tolerance: ±0 px of the original 400 px block).
        let foodArea = out.filter { $0 == 0 }.count
        XCTAssertEqual(foodArea, 400, "large contiguous food region must be preserved")
        var blockMismatches = 0
        for y in 10..<30 {
            for x in 10..<30 where out[y * width + x] != 0 { blockMismatches += 1 }
        }
        XCTAssertEqual(blockMismatches, 0, "no pixel inside the food block may change class")

        // Deterministic: identical input → identical output.
        XCTAssertEqual(cleaned, regulariseLabelMap(input, width: width, height: height, palette: palette, config: .standard))

        // Passthrough configuration reproduces the input byte-for-byte.
        XCTAssertEqual(regulariseLabelMap(input, width: width, height: height, palette: palette, config: .disabled), input)

        // Speckle-only configuration (sliver fraction 0) reproduces the
        // pre-sliver pass byte-for-byte: speckle to background, nothing else.
        var speckleOnlyExpected = labels
        for s in specklePixels { speckleOnlyExpected[s.y * width + s.x] = bg }
        XCTAssertEqual(
            regulariseLabelMap(input, width: width, height: height, palette: palette,
                               config: MaskRegularisationConfig(minRegionArea: 12, sliverFraction: 0)),
            Data(speckleOnlyExpected)
        )
    }

    // MARK: - Sliver absorption (unknown-food-nameable Req 10)
    //
    // Test palette: food_0 = 0 (rice), food_1 = 1 (a named class), bg = 2,
    // unknown_food = 3. Every region below is at least 12 px, so the speckle
    // rule never fires and only the sliver rule can change a label.

    /// Speckle rule on, sliver rule at the default 0.10.
    private let sliverConfig = MaskRegularisationConfig(minRegionArea: 12, sliverFraction: 0.10)

    private func fill(_ labels: inout [UInt8], width: Int, x: Range<Int>, y: Range<Int>, _ cls: UInt8) {
        for yy in y { for xx in x { labels[yy * width + xx] = cls } }
    }

    func testSliver_SmallNamedComponentOnLargerUnknownRegionIsAbsorbed() {
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3, named: UInt8 = 1
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 5..<25, y: 5..<25, unknown)   // 400 px block
        fill(&labels, width: width, x: 10..<14, y: 10..<14, named)   // 16 px inset, 4 % of the 400

        let input = Data(labels)
        let out = [UInt8](regulariseLabelMap(input, width: width, height: height,
                                             palette: makeTestPalette(), config: sliverConfig))

        var expected = labels
        fill(&expected, width: width, x: 10..<14, y: 10..<14, unknown)
        XCTAssertEqual(out, expected, "the named inset joins the unknown region it borders")
        XCTAssertEqual(out.filter { $0 == named }.count, 0)
        XCTAssertEqual(out.filter { $0 == unknown }.count, 400)
    }

    func testSliver_SmallUnknownFringeOnRiceJoinsRice() {
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3, rice: UInt8 = 0
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 10..<30, y: 10..<30, rice)      // 400 px block
        // A 3×10 unknown notch on the block's right edge: 30 px, 7.5 % of the
        // 400 food-like pixels. Rice on three sides (16 border px) beats
        // background on the fourth (10), so the fringe joins the rice.
        fill(&labels, width: width, x: 27..<30, y: 15..<25, unknown)

        let input = Data(labels)
        let out = [UInt8](regulariseLabelMap(input, width: width, height: height,
                                             palette: makeTestPalette(), config: sliverConfig))

        var expected = labels
        fill(&expected, width: width, x: 27..<30, y: 15..<25, rice)
        XCTAssertEqual(out, expected, "the unknown fringe joins the rice it mostly borders")
        XCTAssertEqual(out.filter { $0 == rice }.count, 400)
    }

    func testSliver_ClassLargeInTotalButSplitIntoSmallPiecesIsKept() {
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3, peas: UInt8 = 1
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 2..<14, y: 2..<14, unknown)    // 144 px
        // Six separate 4×4 peas clumps (96 px, 40 % of the food-like total).
        // Each clump alone would be under the fraction; the class as a whole is
        // not, so every clump keeps its label.
        for origin in [(18, 2), (24, 2), (18, 8), (24, 8), (18, 14), (24, 14)] {
            fill(&labels, width: width, x: origin.0..<(origin.0 + 4), y: origin.1..<(origin.1 + 4), peas)
        }

        let input = Data(labels)
        let out = regulariseLabelMap(input, width: width, height: height,
                                     palette: makeTestPalette(), config: sliverConfig)
        XCTAssertEqual(out, input, "a class judged per class, not per component, is kept")
    }

    func testSliver_ComponentBorderedOnlyBySliverClassesIsUnchanged() {
        let width = 32, height = 32
        let rice: UInt8 = 0, named: UInt8 = 1, unknown: UInt8 = 3
        var labels = [UInt8](repeating: rice, count: width * height)
        // Rows 0–1: named (64 px); rows 2–3: unknown (64 px); rows 4–31: rice
        // (896 px). Both strips are slivers (6.25 % each). The named strip
        // borders only the unknown sliver (its top is the frame edge) and is
        // left as it is; the unknown strip borders the named sliver and the
        // rice, and the rice — the only non-sliver border — absorbs it.
        fill(&labels, width: width, x: 0..<width, y: 0..<2, named)
        fill(&labels, width: width, x: 0..<width, y: 2..<4, unknown)

        let input = Data(labels)
        let out = [UInt8](regulariseLabelMap(input, width: width, height: height,
                                             palette: makeTestPalette(), config: sliverConfig))

        var expected = labels
        fill(&expected, width: width, x: 0..<width, y: 2..<4, rice)
        XCTAssertEqual(out, expected)
        XCTAssertEqual(out.filter { $0 == named }.count, 64, "a sliver bordered only by slivers is unchanged")
        XCTAssertEqual(out.filter { $0 == unknown }.count, 0)
    }

    func testSliver_BackgroundIsNeverASliverAndAbsorbs() {
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3, named: UInt8 = 1
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 2..<22, y: 2..<22, unknown)   // 400 px
        // Background is outside the food-like histogram, so it is never a
        // sliver, and it is a valid absorber: the 16 px named island (3.8 % of
        // the food-like total) it surrounds joins the background.
        fill(&labels, width: width, x: 26..<30, y: 26..<30, named)

        let input = Data(labels)
        let out = [UInt8](regulariseLabelMap(input, width: width, height: height,
                                             palette: makeTestPalette(), config: sliverConfig))
        var expected = labels
        fill(&expected, width: width, x: 26..<30, y: 26..<30, bg)
        XCTAssertEqual(out, expected)
    }

    func testSliver_OnlyFoodLikeClassIsNeverASliver() {
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 4..<8, y: 4..<8, unknown)   // 16 px, the frame's only food
        let input = Data(labels)
        XCTAssertEqual(
            regulariseLabelMap(input, width: width, height: height,
                               palette: makeTestPalette(), config: sliverConfig),
            input
        )
    }

    func testSliver_FractionZeroIsByteIdenticalPassthrough() {
        // The same maps the rules above change are untouched at fraction 0 —
        // nothing in them is under the speckle threshold, so the speckle-only
        // pass (today's output) is the identity.
        let width = 32, height = 32
        let bg: UInt8 = 2, unknown: UInt8 = 3, named: UInt8 = 1, rice: UInt8 = 0
        var labels = [UInt8](repeating: bg, count: width * height)
        fill(&labels, width: width, x: 5..<25, y: 5..<25, unknown)
        fill(&labels, width: width, x: 10..<14, y: 10..<14, named)
        fill(&labels, width: width, x: 26..<30, y: 2..<6, rice)
        let input = Data(labels)
        let palette = makeTestPalette()

        let zero = MaskRegularisationConfig(minRegionArea: 12, sliverFraction: 0)
        XCTAssertEqual(regulariseLabelMap(input, width: width, height: height, palette: palette, config: zero), input)
        XCTAssertNotEqual(
            regulariseLabelMap(input, width: width, height: height, palette: palette, config: sliverConfig),
            input, "the fraction is what changes the map"
        )
        // `.disabled` stays a full passthrough; `.standard` carries the default.
        XCTAssertTrue(MaskRegularisationConfig.disabled.isPassthrough)
        XCTAssertFalse(zero.isPassthrough)
        XCTAssertEqual(MaskRegularisationConfig.standard.sliverFraction, 0.10)
    }

    // MARK: - σ_seg (Step 12, M8 pin)

    func testSigmaSeg_ExcludesSpecialClasses() throws {
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        // Rows 0–1 → food classes; row 2 → unknown_food; row 3 → unsupported_liquid.
        // All four rows are in silhouette (q[bg] ≈ 0 because softmax peak is on a non-bg class).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { y, _ in
            switch y {
            case 0: return 0
            case 1: return 1
            case 2: return palette.unknownFood
            default: return palette.unsupportedLiquid
            }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // σ_seg averages only the 8 food pixels in rows 0–1.
        XCTAssertEqual(out.sigmaSeg, 0.99999, accuracy: 0.001)
        // Per-class mean covers only the two food classes.
        XCTAssertEqual(out.perClassMeanProb.count, 2)
        XCTAssertNotNil(out.perClassMeanProb["food_0"])
        XCTAssertNotNil(out.perClassMeanProb["food_1"])
    }

    func testSigmaSeg_IsMeanOfTopProbabilityAcrossAllClasses() throws {
        // Build a tensor where the top probability per food pixel is exactly 0.6 so the
        // mean is verifiable.
        let palette = makeTestPalette()
        let targetSize = 2
        let classes = palette.totalClasses
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        // Each pixel: food_0 = 0.6, food_1 = 0.1, bg = 0.1, unknown = 0.1, liq = 0.1.
        // Use log-probs as logits (softmax recovers them).
        let target: [Float] = [0.6, 0.1, 0.1, 0.1, 0.1]
        for pix in 0..<(targetSize * targetSize) {
            for c in 0..<classes { logits[pix * classes + c] = Foundation.log(target[c]) }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // top prob over all classes is 0.6 → σ_seg = 0.6.
        XCTAssertEqual(out.sigmaSeg, 0.6, accuracy: 1e-3)
    }

    // MARK: - Refusal predicate (M8 / edge case 3)

    func testNoFoodPixels_RefusalAlignedWithSilhouetteTest() throws {
        // Pure background (high-magnitude one-hot at bg) → q[bg] ≈ 1 → silhouette empty.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, _ in
            palette.background
        }
        XCTAssertThrowsError(try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )) { error in
            XCTAssertEqual(error as? SegmentationError, .noFoodPixels)
        }
    }

    func testRefusal_NotTriggeredByArgmaxBg_IfSilhouetteSatisfied() throws {
        // Pixel where bg is argmax (q[bg] = 0.45) but silhouette passes (1 − 0.45 = 0.55).
        // Per design §6.5 / §5 refusal table: do NOT throw noFoodPixels — silhouette is non-empty.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let target: [Float] = [0.30, 0.20, 0.45, 0.025, 0.025]   // food_0, food_1, bg, unk, liq
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        for pix in 0..<(targetSize * targetSize) {
            for c in 0..<classes { logits[pix * classes + c] = Foundation.log(target[c]) }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // Every pixel argmaxes to bg → 0 food pixels for σ_seg averaging.
        XCTAssertEqual(out.sigmaSeg, 0, accuracy: 1e-4)
        XCTAssertTrue(out.perClassMeanProb.isEmpty)
        // But no refusal — silhouette pixels exist.
    }

    // MARK: - perClassMeanProb (Step 13)

    func testPerClassMeanProb_OnlyFoodClassesIncluded() throws {
        // Half pixels argmax to food_0, half to food_1. Both food classes appear in perClassMeanProb.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { y, _ in
            y < 2 ? 0 : 1
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        XCTAssertEqual(out.perClassMeanProb.count, 2)
        XCTAssertEqual(out.perClassMeanProb["food_0"]!, 0.99999, accuracy: 1e-3)
        XCTAssertEqual(out.perClassMeanProb["food_1"]!, 0.99999, accuracy: 1e-3)
        XCTAssertNil(out.perClassMeanProb["background"])
    }

    // MARK: - Non-interference of the candidate-evidence pass
    //
    // alternative-class-candidates Req 2.2: the spec adds a retained quantity
    // and corrects none. Every figure the pipeline already reads off this
    // post-processor must be identical whether or not the pass runs, so these
    // comparisons are exact, not approximate.

    /// Two food regions with a known probability structure, large enough that
    /// both clear the pass's 64-sample floor on the stride-4 grid (128 sampled
    /// pixels each) — so the "with" run does real work and the comparison is
    /// not vacuous.
    private func makeTwoRegionLogits(size: Int, classes: Int) -> [Float] {
        // food_0, food_1, food_2, food_3, bg, unknown, unsupported — each row
        // sums to 1, so softmax over the logarithms recovers it exactly.
        let left: [Float] = [0.55, 0.20, 0.10, 0.05, 0.05, 0.025, 0.025]
        let right: [Float] = [0.10, 0.50, 0.25, 0.05, 0.05, 0.025, 0.025]
        var logits = [Float](repeating: 0, count: size * size * classes)
        for y in 0..<size {
            for x in 0..<size {
                let target = x < size / 2 ? left : right
                let off = (y * size + x) * classes
                for c in 0..<classes { logits[off + c] = Foundation.log(target[c]) }
            }
        }
        return logits
    }

    func testCandidateEvidencePassLeavesEveryExistingFigureUnchanged() throws {
        let palette = makeTestPalette(numFoodClasses: 4)
        let size = 64
        let classes = palette.totalClasses
        let logits = makeTwoRegionLogits(size: size, classes: classes)

        func run(retaining: Bool) throws -> PostProcessedOutput {
            try SegmenterPostProcessor.process(
                logitsFP32: logits, targetSize: size, classes: classes,
                scaledWidth: size, scaledHeight: size,
                originalWidth: size, originalHeight: size,
                palette: palette,
                retainCandidateEvidence: retaining
            )
        }

        let with = try run(retaining: true)
        let without = try run(retaining: false)

        // The pass ran and produced something in the "with" arm, and did not run
        // at all in the "without" arm — otherwise the equalities below are empty.
        XCTAssertNil(without.candidateEvidence)
        let evidence = try XCTUnwrap(with.candidateEvidence)
        XCTAssertFalse(evidence.isEmpty, "both regions clear the sample floor")

        XCTAssertEqual(with.argmax.pixels, without.argmax.pixels)
        XCTAssertEqual(with.sigmaSeg, without.sigmaSeg)
        XCTAssertEqual(with.perClassMeanProb, without.perClassMeanProb)
        // The probability tensor feeds the volume stage; it is read-only to the
        // pass for the same reason.
        XCTAssertEqual(with.probabilities.bytes, without.probabilities.bytes)
    }

    func testCandidateEvidencePassLeavesTheRefusalOutcomeUnchanged() throws {
        // Pure background → the silhouette is empty and `process` refuses. The
        // pass must not turn that into a different error, or into a success.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, _ in
            palette.background
        }
        for retaining in [true, false] {
            XCTAssertThrowsError(try SegmenterPostProcessor.process(
                logitsFP32: logits, targetSize: targetSize, classes: classes,
                scaledWidth: targetSize, scaledHeight: targetSize,
                originalWidth: targetSize, originalHeight: targetSize,
                palette: palette,
                retainCandidateEvidence: retaining
            ), "retainCandidateEvidence: \(retaining)") { error in
                XCTAssertEqual(error as? SegmentationError, .noFoodPixels)
            }
        }
    }
}
