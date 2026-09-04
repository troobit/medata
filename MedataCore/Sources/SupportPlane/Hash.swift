import Foundation

// Deterministic 64-bit seed derived from a byte buffer per §6.0 ("rng_seed :=
// xxh64(depth.bytes)"). xxh64 is the canonical algorithm in the design but any
// deterministic stable hash satisfies the cross-run reproducibility requirement
// — we use FNV-1a 64 here to keep the file small and dependency-free; the test
// asserts that two runs on identical input produce identical inliers.
enum Fnv1a64 {
    private static let offset: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    static func hash(_ bytes: Data) -> UInt64 {
        var h = offset
        for b in bytes {
            h ^= UInt64(b)
            h = h &* prime
        }
        return h
    }
}

// splitmix64-based RNG so the same seed always generates the same sequence. Used by
// the RANSAC loop in §6.2 to draw 3-point subsamples deterministically.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed != 0 ? seed : 0xDEAD_BEEF_C0DE_F00D
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniformInt(_ upperExclusive: Int) -> Int {
        precondition(upperExclusive > 0)
        return Int(next() % UInt64(upperExclusive))
    }
}
