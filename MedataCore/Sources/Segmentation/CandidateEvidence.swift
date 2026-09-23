import Foundation

// The retained alternative-class evidence of `estimation/alternative-class-candidates`:
// for each detected food, the top-five other classes the model's own output
// supported over that food's persisted pixels.
//
// The statistic is the MEAN probability of a channel over the food's sampled
// pixels, fixed by Decision 13 from the Decision 11 probe (tools/candidate_probe.py).
// Two things about it are load-bearing and easy to get wrong — see
// docs/agent-notes/candidate-evidence.md before changing anything here:
//
//  1. Eligibility narrows the channel set BEFORE the statistic is taken, never
//     by ranking every channel and filtering afterwards. `background` is the top
//     non-winner at ~100% of food pixels, so a rank-then-filter reading is
//     dominated by a class that can never be a candidate.
//  2. The tensor is read through a strided per-pixel FP16 accessor, never
//     `FP16Bytes.decode` (whole-tensor, ~398 MB of FP32 for a full frame) and
//     never the post-processor's intermediate FP32 buffer, whose low bits differ
//     from the FP16 bytes a replayed bundle carries and could flip a borderline
//     ranking.
//
// Purely additive: reads the tensor and the label map, writes nothing else. σ_seg,
// the refusal predicate, `perClassMeanProb` and every stored figure are untouched.
public enum CandidateEvidence {
    public struct Candidate: Equatable, Sendable {
        /// Palette-independent key (Req 1.7).
        public let className: String
        /// Mean probability over the food's sampled pixels, quantised to permille
        /// (0…1000, Decision 10). Ranking happens pre-quantisation.
        public let meanPermille: UInt32

        public init(className: String, meanPermille: UInt32) {
            self.className = className
            self.meanPermille = meanPermille
        }
    }

    /// Fixed sampling grid: every 4th pixel in both axes, anchored at (0, 0)
    /// (Decision 8). ~6.2 M of the ~99.5 M full-resolution value reads, so the
    /// Req 3.1 budget is met by construction.
    public static let sampleStride = 4
    /// Decision 11: a detected class sampled at fewer pixels than this earns no
    /// entry at all — a top-5 max over a handful of noisy means is selection
    /// bias, not evidence.
    public static let sampleFloor = 64
    /// Req 1.5: candidates retained per detected food.
    public static let maxCandidates = 5
    /// Req 1.8 / Decision 10: detected foods that may carry a set at all, the
    /// persisted-encoding budget bound.
    public static let maxSets = 5

    /// Deterministic: the same `(probabilities, labelMap, palette)` yields the
    /// same result on device and in harness replay (Req 6.1, Decision 9).
    /// Accumulation is a serial raster walk, so the Float sum order is fixed and
    /// parity needs no deterministic-reduction machinery.
    ///
    /// `labelMap` MUST be the REGULARISED map — the pixels the persisted mask
    /// assigns, not a pre-regularisation assignment (Req 2.1, Decision 3).
    ///
    /// Returns an entry per detected food that qualifies; an empty dictionary
    /// where none does. Inputs that disagree on shape yield an empty dictionary
    /// rather than an error — this pass adds no failure mode (Req 3.4).
    public static func compute(
        probabilities: ProbabilityTensor,
        labelMap: ArgmaxMap,
        palette: ClassPalette
    ) -> [String: [Candidate]] {
        let classes = probabilities.classes
        let width = probabilities.width
        let height = probabilities.height
        guard classes == palette.totalClasses, classes > 0,
              width == labelMap.width, height == labelMap.height,
              width > 0, height > 0 else { return [:] }

        let (sampledCount, channelSums) = accumulate(
            probabilities: probabilities, labelMap: labelMap,
            palette: palette, classes: classes, width: width, height: height
        )

        // Detected foods that clear the sampling floor, most sampled pixels
        // first; ties and the Decision 10 cap resolve on declaration order.
        // `sampledCount` is non-zero only for solid and liquid classes, so the
        // floor also excludes background and the two sentinels.
        let retained = (0..<classes)
            .filter { sampledCount[$0] >= sampleFloor }
            .sorted { lhs, rhs in
                sampledCount[lhs] == sampledCount[rhs]
                    ? lhs < rhs
                    : sampledCount[lhs] > sampledCount[rhs]
            }
            .prefix(maxSets)

        var evidence: [String: [Candidate]] = [:]
        for own in retained {
            guard let key = palette.className(at: own) else { continue }
            let sampled = Float(sampledCount[own])
            let sumOffset = own * classes
            let ownIsSolid = palette.isFoodClass(own)

            // Eligibility first (Decision 13): drop the food's own channel,
            // background, both sentinels and the opposite phase, and only then
            // take the statistic over what remains.
            var ranked: [(channel: Int, mean: Float)] = []
            for channel in 0..<classes where channel != own {
                let samePhase = ownIsSolid
                    ? palette.isFoodClass(channel)
                    : palette.isLiquidClass(channel)
                guard samePhase else { continue }
                let mean = channelSums[sumOffset + channel] / sampled
                guard mean > 0 else { continue }          // strictly positive support (Req 1.5)
                ranked.append((channel, mean))
            }
            // Descending by the pre-quantisation mean; ties keep declaration order.
            ranked.sort { $0.mean == $1.mean ? $0.channel < $1.channel : $0.mean > $1.mean }

            evidence[key] = ranked.prefix(maxCandidates).compactMap { entry in
                guard let name = palette.className(at: entry.channel) else { return nil }
                return Candidate(className: name, meanPermille: permille(entry.mean))
            }
        }
        return evidence
    }

    // Serial raster walk of the stride grid. For every sampled pixel the label
    // map assigns to a food, adds that pixel's whole probability vector to the
    // food's running sums. One FP16 decode per sampled value, no whole-tensor
    // materialisation.
    private static func accumulate(
        probabilities: ProbabilityTensor,
        labelMap: ArgmaxMap,
        palette: ClassPalette,
        classes: Int,
        width: Int,
        height: Int
    ) -> (sampledCount: [Int], channelSums: [Float]) {
        var sampledCount = [Int](repeating: 0, count: classes)
        var channelSums = [Float](repeating: 0, count: classes * classes)

        // A class is a candidate key only if the palette treats it as food;
        // resolved once so the inner walk stays a table lookup.
        let isFood = (0..<classes).map { palette.isFoodClass($0) || palette.isLiquidClass($0) }

        sampledCount.withUnsafeMutableBufferPointer { counts in
            channelSums.withUnsafeMutableBufferPointer { sums in
                probabilities.bytes.withUnsafeBytes { rawProbs in
                    let probs = rawProbs.bindMemory(to: Float16.self)
                    labelMap.pixels.withUnsafeBytes { rawLabels in
                        let labels = rawLabels.bindMemory(to: UInt8.self)
                        var y = 0
                        while y < height {
                            let row = y * width
                            var x = 0
                            while x < width {
                                let pixel = row + x
                                let detected = Int(labels[pixel])
                                guard detected < classes, isFood[detected] else {
                                    x += sampleStride
                                    continue
                                }
                                counts[detected] += 1
                                let probOffset = pixel * classes
                                let sumOffset = detected * classes
                                for channel in 0..<classes {
                                    sums[sumOffset + channel] += Float(probs[probOffset + channel])
                                }
                                x += sampleStride
                            }
                            y += sampleStride
                        }
                    }
                }
            }
        }
        return (sampledCount, channelSums)
    }

    // Probabilities are already in 0…1; the clamp guards a tensor whose values
    // are not, so a magnitude can never wrap the persisted uint32.
    private static func permille(_ mean: Float) -> UInt32 {
        let scaled = (mean * 1000).rounded()
        if scaled <= 0 { return 0 }
        if scaled >= 1000 { return 1000 }
        return UInt32(scaled)
    }
}
