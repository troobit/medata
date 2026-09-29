import Foundation

// Clears a convex image quadrilateral to background in a segmentation result
// (two-view-trust Req 4.6). The ID-1 card is an out-of-palette object the
// segmenter labels as food (a bank card integrated as 43.7 g of cheese on
// 2026-08-11); its pose is solved from four corners, so the pixels it covers
// are known before the volume stage runs. Both the probability tensor and the
// label map are rewritten: the height field and the carve take the silhouette
// from the background probability and the class from the labels.
extension SegmentationResult {
    /// The same result with every pixel inside `quad` (image px, any winding)
    /// set to background, and the number of pixels that changed label.
    public func excluding(quad: [SIMD2<Float>]) -> (result: SegmentationResult, clearedPixels: Int) {
        guard quad.count == 4 else { return (self, 0) }
        let w = probabilities.width, h = probabilities.height, k = probabilities.classes
        let bg = probabilities.palette.background
        let yLo = max(0, Int(quad.map(\.y).min()!.rounded(.down)))
        let yHi = min(h - 1, Int(quad.map(\.y).max()!.rounded(.up)))
        guard yLo <= yHi else { return (self, 0) }

        var probs = probabilities.bytes
        var labels = argmax.pixels
        var cleared = 0
        probs.withUnsafeMutableBytes { p in
            let q = p.bindMemory(to: Float16.self).baseAddress!
            labels.withUnsafeMutableBytes { l in
                let lab = l.bindMemory(to: UInt8.self).baseAddress!
                for y in yLo...yHi {
                    for x in 0..<w where Self.contains(quad, x: Float(x) + 0.5, y: Float(y) + 0.5) {
                        let i = y * w + x
                        if lab[i] != UInt8(bg) { cleared += 1; lab[i] = UInt8(bg) }
                        for c in 0..<k { q[i * k + c] = c == bg ? 1 : 0 }
                    }
                }
            }
        }
        let result = SegmentationResult(
            probabilities: ProbabilityTensor(bytes: probs, height: h, width: w, classes: k,
                                             palette: probabilities.palette),
            argmax: ArgmaxMap(pixels: labels, height: h, width: w),
            perClassMeanProb: perClassMeanProb, sigmaSeg: sigmaSeg, timings: timings,
            foodCoveragePercent: foodCoveragePercent, candidateEvidence: candidateEvidence)
        return (result, cleared)
    }

    /// Even-odd crossing test of a pixel centre against the quad's edges.
    private static func contains(_ quad: [SIMD2<Float>], x: Float, y: Float) -> Bool {
        var inside = false
        for i in 0..<4 {
            let a = quad[i], b = quad[(i + 1) % 4]
            guard (a.y <= y) != (b.y <= y) else { continue }
            if x < a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x) { inside.toggle() }
        }
        return inside
    }
}
