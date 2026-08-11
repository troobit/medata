#if HARNESS_ENABLED
import Foundation
import PortableContracts
import Segmentation
import Testing
@testable import HarnessCore

// Replay parity for the retained alternative-class evidence
// (estimation/alternative-class-candidates, Req 6.1/6.2): a fixture's FP16
// tensor plus its persisted argmax through the SHARED
// `CandidateEvidence.compute`, against a golden expected set committed beside
// the fixture that produces it.
//
// What this claims, and what it does not. The harness holds no candidate-evidence
// code of its own — this test is its only caller. It runs no `PostProcessing`,
// writes no meal record and therefore sets no marker, so parity here is
// structural: the device and the replay reach one function with the same bytes.
// The coverage claimed for Req 6.1 is that shared function plus this golden,
// and nothing beyond it.
//
// The golden is a literal rather than a separate file on purpose: the fixture
// that produces it is a few lines above, so a drift shows as one diff with both
// halves visible, and the values below are hand-derivable from the declared
// per-region vectors rather than a recording of whatever the code last did.
@Suite("Candidate-evidence replay parity (Req 6.1/6.2)")
struct CandidateEvidenceReplayParityTests {

    @Test("A fixture replays to the committed golden")
    func replayMatchesGolden() throws {
        // Serialised and read back, because that is what a persisted bundle is —
        // the FP16 bytes must survive the protobuf round trip to reach `compute`
        // unchanged.
        let onDisk = try ReplayFixture.fixture().serializedData()
        let fixture = try PbMealFixture(serializedBytes: onDisk)
        #expect(ReplayFixture.admissible(fixture))

        let replayed = ReplayFixture.replay(fixture)
        #expect(replayed == ReplayFixture.golden)
        // The egg block is sampled at 16 pixels, under the 64-sample floor, so
        // its absence is honest rather than a dropped key.
        #expect(replayed["egg"] == nil)
    }

    // The FP16-decode contract, pinned by a channel that reads differently
    // through the two paths: `pasta` is declared 0.2005, whose FP32 reading
    // quantises to 201 per mille and whose FP16 reading quantises to 200. A
    // ranking taken off the post-processor's intermediate FP32 buffer instead of
    // the bytes a replayed bundle carries would fail here (Decision 9).
    @Test("The ranking reads the FP16 bytes, not an FP32 re-materialisation")
    func fp16BytesAreWhatIsRead() throws {
        let replayed = ReplayFixture.replay(ReplayFixture.fixture())
        let pasta = try #require(replayed["white_rice"]?.first { $0.className == "pasta" })

        let fp32Reading = UInt32((Float(0.2005) * 1000).rounded())
        #expect(fp32Reading == 201, "precondition: the two readings must differ")
        #expect(pasta.meanPermille == 200)
    }

    // Eligibility narrows the channel set BEFORE the statistic (Decision 13).
    // The fixture's ineligible channels deliberately outrank every candidate, so
    // a rank-then-filter reading would surface one of them here.
    @Test("Ineligible channels never occupy a slot after replay")
    func ineligibleChannelsNeverOccupyASlot() {
        let replayed = ReplayFixture.replay(ReplayFixture.fixture())
        let ineligible: Set<String> = ["background", "unknown_food", "unsupported_liquid"]
        for (own, candidates) in replayed {
            for candidate in candidates {
                #expect(!ineligible.contains(candidate.className))
                #expect(candidate.className != own)
            }
        }
        // Phase: a solid's candidates are all solids, a liquid's all liquids.
        #expect(replayed["white_rice"]?.contains { $0.className == "water" } == false)
        #expect(replayed["soup"]?.contains { $0.className == "white_rice" } == false)
    }

    // Req 6.2: replay never empties a populated set. The same bytes yield the
    // same non-empty sets on every run — no reduction order, no map iteration
    // and no clock enters the accumulation.
    @Test("A populated set never replays empty")
    func populatedSetNeverReplaysEmpty() {
        let fixture = ReplayFixture.fixture()
        let first = ReplayFixture.replay(fixture)
        let second = ReplayFixture.replay(fixture)

        #expect(first == second)
        #expect(!first.isEmpty)
        for (own, candidates) in first {
            #expect(!candidates.isEmpty, "\(own) replayed to an empty set")
        }
    }

    // Nutrition5k fixtures carry the GROUND-TRUTH mask in `nadir_argmax`, not a
    // persisted prediction, so evidence computed over truth regions would be a
    // plausible-looking wrong number. They are outside Req 6.1 coverage.
    @Test("A Nutrition5k fixture is inadmissible for parity")
    func nutrition5kFixtureIsInadmissible() {
        #expect(!ReplayFixture.admissible(
            ReplayFixture.fixture(sourceDataset: "nutrition5k@v1/metadata_v1")))
        #expect(ReplayFixture.admissible(ReplayFixture.fixture()))
    }
}

// The synthetic fixture the golden is derived from, in the shape a capture
// bundle records: FP16 [H, W, C] probabilities, a UInt8 [H, W] persisted argmax
// and the intrinsics the replay reads its dimensions from.
//
// Every pixel of a region carries the SAME probability vector, so each
// candidate's mean over that region is the declared value exactly and the golden
// per-mille figures below are arithmetic, not a recording.
enum ReplayFixture {
    // Pre-release there is exactly one palette (pipeline Decision 50), so a
    // fixture resolves to `ClassPalette.standard` — the same resolution
    // `paletteForFixture` performs in HarnessCLI.
    static let palette = ClassPalette.standard
    static let width = 64
    static let height = 64

    // Indices into the shipped palette, named where the golden reads them.
    static let whiteRice = 0, brownRice = 1, pasta = 2, breadWhite = 3
    static let breadWholemeal = 4, chicken = 8, beef = 9, pork = 10, egg = 12
    static let water = 25, coffee = 26, tea = 27, milk = 28, soup = 30
    static let background = 33, unknownFood = 34, unsupportedLiquid = 35

    // Rows 0…31 outside the egg block, 112 sampled pixels. Seven eligible solids
    // so the five-candidate cap bites (beef and pork fall off), and the
    // ineligible channels sit above every candidate that survives.
    static let riceVector: [Int: Float] = [
        whiteRice: 0.30,          // the food's own channel
        background: 0.15,         // would rank 1 under a rank-then-filter reading
        unknownFood: 0.05,        // sentinel
        water: 0.05,              // wrong phase
        pasta: 0.2005, brownRice: 0.125, breadWhite: 0.0625,
        breadWholemeal: 0.03125, chicken: 0.015625, beef: 0.0078125, pork: 0.00390625
    ]

    // Rows 32…63, 128 sampled pixels. A liquid, so the phase split is exercised
    // in both directions.
    static let soupVector: [Int: Float] = [
        soup: 0.45,               // own channel
        background: 0.20,
        whiteRice: 0.15,          // wrong phase, and would rank 1 without the split
        coffee: 0.10, tea: 0.05, milk: 0.03125,
        unsupportedLiquid: 0.01   // sentinel
    ]

    // A 16×16 block, 16 sampled pixels — under the 64-sample floor, so it earns
    // no entry at all (Decision 11).
    static let eggVector: [Int: Float] = [
        egg: 0.60, background: 0.20, pasta: 0.20
    ]

    // THE GOLDEN. Each figure is `round(FP16(declared value) × 1000)`:
    //
    //   pasta            0.2005  → FP16 0.200439…  → 200   (201 read as FP32)
    //   brown_rice       0.125   → exact           → 125
    //   bread_white      0.0625  → exact, 62.5     → 63
    //   bread_wholemeal  0.03125 → exact, 31.25    → 31
    //   chicken          0.015625 → exact, 15.625  → 16
    //   coffee           0.10    → FP16 0.099975…  → 100
    //   tea              0.05    → FP16 0.049987…  → 50
    //   milk             0.03125 → exact, 31.25    → 31
    static let golden: [String: [CandidateEvidence.Candidate]] = [
        "white_rice": [
            .init(className: "pasta", meanPermille: 200),
            .init(className: "brown_rice", meanPermille: 125),
            .init(className: "bread_white", meanPermille: 63),
            .init(className: "bread_wholemeal", meanPermille: 31),
            .init(className: "chicken", meanPermille: 16)
        ],
        "soup": [
            .init(className: "coffee", meanPermille: 100),
            .init(className: "tea", meanPermille: 50),
            .init(className: "milk", meanPermille: 31)
        ]
    ]

    static func region(y: Int, x: Int) -> (label: Int, vector: [Int: Float]) {
        if y < 16 && x < 16 { return (egg, eggVector) }
        return y < 32 ? (whiteRice, riceVector) : (soup, soupVector)
    }

    static func fixture(sourceDataset: String = "") -> PbMealFixture {
        let classes = palette.totalClasses
        var values = [Float](repeating: 0, count: width * height * classes)
        var argmax = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let region = region(y: y, x: x)
                argmax[pixel] = UInt8(region.label)
                let offset = pixel * classes
                for (channel, probability) in region.vector {
                    values[offset + channel] = probability
                }
            }
        }

        var intrinsics = PbCameraIntrinsics()
        intrinsics.fx = 700
        intrinsics.fy = 700
        intrinsics.cx = Float(width) / 2 - 0.5
        intrinsics.cy = Float(height) / 2 - 0.5
        intrinsics.imageWidth = Int32(width)
        intrinsics.imageHeight = Int32(height)

        var fixture = PbMealFixture()
        fixture.fixtureID = "candidate-evidence-parity"
        fixture.fixtureRevision = "rev-1"
        fixture.paletteVersion = palette.version
        fixture.segmenterCheckpointSha256 = String(repeating: "0", count: 64)
        fixture.capturePathCanonical = "single_view_lidar"
        fixture.nadirIntrinsics = intrinsics
        fixture.nadirProbs = FP16Bytes.encode(values)
        fixture.nadirArgmax = Data(argmax)
        fixture.sourceDataset = sourceDataset
        return fixture
    }

    // The replay path: dimensions off the fixture's intrinsics and the resolved
    // palette, exactly as `FixtureRunner` reads them, then the shared function.
    static func replay(_ fixture: PbMealFixture) -> [String: [CandidateEvidence.Candidate]] {
        let w = Int(fixture.nadirIntrinsics.imageWidth)
        let h = Int(fixture.nadirIntrinsics.imageHeight)
        return CandidateEvidence.compute(
            probabilities: ProbabilityTensor(
                bytes: fixture.nadirProbs, height: h, width: w,
                classes: palette.totalClasses, palette: palette),
            labelMap: ArgmaxMap(pixels: fixture.nadirArgmax, height: h, width: w),
            palette: palette)
    }

    // A bundle fixture records the CLEANED prediction (PostProcessing.swift:214),
    // so its argmax IS the persisted mask. A fixture stamped with a source
    // dataset is Nutrition5k-derived and carries ground truth in that field
    // instead — inadmissible for parity, the same refusal
    // `tools/candidate_probe.py` makes.
    static func admissible(_ fixture: PbMealFixture) -> Bool {
        fixture.sourceDataset.isEmpty
    }
}
#endif
