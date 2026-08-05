# Design: Support Plane Reference

## Overview

Replace "largest gravity-aligned plane in the frame" with "the gravity-aligned plane the food is resting on", by bounding the candidate samples to the food's neighbourhood, scoring candidates on the size of their largest connected inlier component rather than raw inlier count, and selecting on measured contact with the food. Rejection routes to today's fit unchanged.

## Architecture

### What changes and what does not

`ransac`'s minimal sampling, the 15° gravity cone, `refine`'s scatter-matrix SVD and the deterministic consensus polish are correct and reused. Three things change: **which samples compete**, **how a candidate is scored**, and **which candidate wins**.

### Bound the candidate set first

Today's candidate set is every non-food pixel in the frame, so floors, hobs, draining boards and a second plate all compete. Restricting to `dilate(foodMask, 2 × foodRadius)` on the depth grid is the highest-leverage change in the design and fixes three problems at once:

- Clutter no longer consumes candidate slots.
- The plate's inlier fraction rises, which is what makes the RANSAC iteration budget tractable (below).
- Point count drops ~4×, which is where the CPU headroom for extra passes comes from.

This is the same scene-dependence objection Decision 9 raised against the next-plane-gap diagnostic; it had re-entered at the extraction stage and is now closed there too.

### Native depth grid, and the intrinsics trap

Sampling moves to the native 256×192 grid (Req 2.4), which removes the ~56× replication that made the wrong fit look confident. Two consequences the implementation must handle explicitly:

**`depth.depthIntrinsics` is unusable on device.** `ARKitCaptureEngine` writes `CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, …)` — only width and height are real, and it has no production readers today. Back-projection must derive depth intrinsics from the colour ones:

```
fx_d = fx_c · W_d/W_c        cx_d = (cx_c + 0.5) · W_d/W_c − 0.5
```

The half-pixel terms are not optional: dropping them offsets the principal point by ~3.75 colour pixels, tilting every fitted plane. Reaching for `depth.depthIntrinsics` instead yields a divide-by-zero and a NaN plane; passing `colourIntrinsics` straight through yields a 7.5× lateral error. This is the most likely implementation bug in the feature.

**Mask downsampling needs a stated rule.** `BinaryMask` is colour-grid; the ring and candidates are depth-grid. A depth pixel is marked food if **any** covered colour pixel is food (conservative — Req 2.1 requires the fitted set to contain no food pixel, so ambiguity must resolve towards exclusion).

`.insideMask` is **not** reused: its branch iterates the colour grid and is the replication being removed. It stays for the harness's existing callers until they are migrated.

### Candidate scoring — CC-RANSAC

Score a candidate by **the size of its largest 8-connected inlier component**, not by total inlier count (Gallo, Manduchi & Rafii 2011). Sequential RANSAC's documented failure is a plane straddling two surfaces separated by a step, because the straddling plane holds more inliers than either surface alone — and a plate rim is exactly that step. Component scoring is what stops it, and it does so *inside* the loop by changing which plane wins, rather than as a post-hoc filter that can only reject.

This subsumes the connected-component adjacency filter Decision 11 staged second: adjacency becomes a property of the score rather than a separate pass with its own constant.

**Extraction loop.** Up to `maxCandidatePlanes` passes; each removes the **polished** inlier set within `2 × inlierBandMm` (a thin shell left at 1× seeds near-duplicate planes on the next pass). Stops early when the residue falls below `minCandidateSamples`.

**Iteration budget.** `maxIterations = 256` was sized to find the *dominant* plane. `P(clean triple) = 1 − (1 − w³)^N` gives 98 % at w = 0.25 but 23 % at w = 0.10 and 3 % at w = 0.05. Bounding the sample set keeps the plate well above 0.25 in the common case, but the budget must not be inherited on faith: each pass uses **adaptive stopping** — recompute the required `N` from the best inlier ratio seen so far and stop when reached, capped at `maxIterationsPerPass`. Deterministic, because the ratio sequence is deterministic.

### Selection and admissibility

**Guards are an admissibility filter applied to every candidate, then the best admissible candidate wins.** Applying them after selection would let a phantom rim-ramp plane win the score, fail a guard, and drop a capture to fallback while an admissible plate plane sat in the candidate set.

| Guard | Rejects | Req |
|---|---|---|
| ring support fraction < `ringSupportMin` | ring not resting on this plane | 3.2 |
| ring MAD > `ringMadMaxMm` | bimodal ring — straddling two surfaces | 2.3, 3.2 |
| plane above > `foodAboveFractionMax` of food samples | vessel rim, or a plane on the food top | 3.4 |
| radial band step > `bandStepMaxMm` rising outward | rim or bowl wall — inner band wins instead | 3.2 |
| support visibility < `supportVisibilityMin` | support surface not observable under the food | 3.2 |
| plane below the lowest admissible candidate | region escaped through a dropout | 3.3 |
| fewer than `minAcceptedExtentPx` inlier bbox extent | badly conditioned normal | 2.3 |

**Score.** Among admissible candidates, maximise the ring support fraction — the share of ring samples within ±`ringBandMm` of the plane. **Not** `|median|` closest to zero, which has a 50 % cliff: a ring half on the plate and half on the table has a median that jumps 26 mm as the mixture crosses half, and just past the cliff the *table* plane reads ≈ 0, passes every guard, and is persisted with a textbook-perfect diagnostic. The support fraction degrades continuously instead, and MAD catches the bimodality directly.

**Ambiguity margin.** If the top two admissible candidates are within `ringSupportMarginMin` of each other, reject to fallback. Two candidates 26 mm apart both scoring near-equally is exactly the straddling-ring case, and a coin flip between them moves the carb number 3×.

### Why there is no separate residual bar

An earlier draft added `restrictedResidualMaxMm = 8`, justified by "a straddling region fits at ~13 mm RMS". That is a property of plain least squares over a fixed region — the flood-fill option Decision 11 rejected. Under RANSAC the residual is computed over `polishedInliers`, each within `inlierBandMm = 5` of the plane, so RMS is **≤ 5 mm by construction** and the bar can never fire. It would also push matte-table captures onto the fallback, since Decision 46 raised the general bar to 20 mm for genuine single-surface depth noise. Ring MAD measures the straddle directly and does fire.

### Fallback ladder (Req 4, Decision 5 ordering)

Restricted fit **first**; on any rejection, the edge-band fit runs and returns byte-identical results (Req 4.3). The edge-band fit is **lazy** — computed only on the rejection path. The below-fallback guard uses the lowest admissible candidate rather than the edge-band plane, so nothing needs it eagerly.

This preserves Decision 5's stated sequence and has a second benefit: `lidar-plane-fit-degenerate-on-clean-capture` widened the bands because the band scan starves on clean captures. The restricted path samples natively and is immune to that failure, so attempting it first recovers captures that would otherwise refuse.

**Cost, stated honestly.** This is *added* work on the success path, not a replacement — the earlier draft's "not slower than today" compared against the harness's deleted path, not the device's. Added: bounded depth-grid collection (~12k samples after bounding), up to 3 adaptive RANSAC passes, ring construction, two medians. Removed on the success path: the full edge-band colour-grid scan. Req 7.6's budget is measured on device, not asserted here.

**Confidence.** `sigmaPlane` gains a third factor, 1.0 on `.foodSupport` and `fallbackPenalty` on `.edgeBand` (Decision 12).

### The rimmed-plate case

Food rests on a plate's **well**; the **rim** sits 10–28 mm above it. If the ring lands on the rim, the rim plane is selected and food height is clipped — a silent under-read, and the inversion Decision 3's harm ordering assumes cannot happen.

**Exposure, measured against ordinary dinnerware.** With the ring at 8–25 mm outside the food boundary, it lands wholly on the rim only once food covers **78–86 % of the well area** — a heaped plate, not a normal serving. Below that the ring is mostly on the well. But when it does hit, the error is large and in the dangerous direction:

| Plate | Rim above well | Food 25 mm tall | Food 40 mm tall |
|---|---|---|---|
| Dinner, wide rim | 18 mm | −72 % | −45 % |
| Dinner, narrow rim | 12 mm | −48 % | −30 % |
| Pasta / deep plate | 28 mm | — | −70 % |

Today's table reference over-reads by +26 mm; a rim reference under-reads by 12–28 mm. Comparable magnitude, opposite sign — so for this case alone the correction could move the error the wrong way.

**Radial ring profile.** The ring is resolved into inner / mid / outer bands rather than reduced to one median. The profile is diagnostic, and it distinguishes the cases a single median conflates:

| Radial profile | Scene |
|---|---|
| flat across bands | plate well, board, or table — one surface |
| **rises outward** | **rimmed plate with the well partly visible** |
| rises steeply outward | bowl wall |
| falls outward | ring has leaked past the plate edge onto the table |

Selection then uses the **inner band** as authoritative — the support surface is by definition the one immediately adjacent to the food — with the outer bands as shape detection. This resolves the partial-fill case *correctly* rather than merely rejecting it: the well plane is already in the candidate set, it was simply not being preferred. It also subsumes the leaked-ring detection, which the earlier single-median design needed MAD to catch.

**Support visibility, for the case that cannot be solved.** When food fills the well, the well surface produces **no depth samples at all** — nothing in the frame touches it. No candidate plane can be fitted to an unobserved surface, and no ring geometry recovers one; this is a sensing limit, not an algorithm choice. It is however detectable: when the visible support region is too thin relative to the food region (`supportVisibilityMin`), the support surface cannot be verified and the fit falls back. That routes the unobservable case to the edge-band over-read, which is the direction a human catches.

This is the `region area ÷ food-mask area` check Decision 9 kept as a secondary guard and an earlier draft dropped. It returns with a job it is suited to — an observability test, not a selection score, which is what it was rejected as.

**Residual risk, stated.** A fully-filled rimmed plate whose food mounds well above the rim can still pass the visibility test with the ring flat on the rim, and will under-read by the rim height. The radial profile is persisted, so the case is identifiable in the accuracy log rather than invisible.

### Stated limits (Req 2.5)

**Minimum resolvable food height ≈ 8 mm.** ARKit depth is fused from a sparse dot pattern and smoothed across ~4 depth pixels, so a step spreads to 4–6 mm/px and a food edge shallower than the smear cannot be separated from its support. The bread capture's implied 10.1 mm slice sits just above this bound — thinner items (a tortilla, sliced ham, sauce) are out of scope for the correction and fall back rather than being silently under-measured.

### Document amendments (Reqs 1.4, 5.2)

Edits, not cross-references: pipeline Req 4.2, pipeline design §6.2, the pipeline glossary, `DECISIONS.md` MD-9 (superseding entry, not a silent rewrite), and — added after review — the `nutrition5k-calibration` transfer contract (Req 5.2), which Req 3.6 of that spec already contradicts.

### Pattern parity audit

| Site | Needs the new path? | Rationale |
|---|---|---|
| `Pipeline.fitSupportPlane` (`Pipeline.swift:638`) | **Yes**, via the fitter | The device path being fixed |
| `HarnessCore/FixtureRunner.run` single-view | **Yes** | Req 5.1 parity; private copy deleted |
| `FixtureRunner` two-view branch | **No** | Silhouette carve, no depth plane (Decision 7) |
| `CardOnlyPlaneFitter` | **No** | No depth map |
| `HarnessCore/CalibrationArtifact` | **Metadata only** | Records the reference (Req 5.3) |
| `VoxelCarveEstimator` | **Consumer, compounding** | Excludes `signedDistance < 0` — a **hard** exclusion, unlike the height field's `max(0, ·)` clamp. Raising the plane 26 mm deletes a slab, and overhanging food (Decision 4) sits inside it, so the effect there is deletion rather than under-measurement. Measured under Req 1.6 |
| `HeightFieldEstimator.integrate` | **Consumer** | Formula unchanged |
| `DiagProbe/main.swift` | **No** | Untracked throwaway; delete |
| `PlateRegionPlaneTests` | **Delete with the code** | Tests the flood fill, which is not being promoted |
| `PlateTopSupportPlaneTests` (`XCTSkip`ped, `99ba8c0`) | **Yes** | Un-skip; it encodes this resolution |

### Deleting `fitPlateRegionPlane` rebases the N5k corpus

Device bundles stamp `estimatorPath = "single_dominant"`, so both device replays and N5k fixtures currently take `fitPlateRegionPlane`. Deleting it changes N5k outputs and therefore every previously recorded `nutrition5k-calibration` result. Those results must be regenerated, and the corpus then spans two references — which is what Req 5.4 exists to handle.

The harness has no food mask at that call site today (`fitPlateRegionPlane` takes only depth, intrinsics, gravity). It derives one from `nadirSeg`'s argmax, the same source the device's segmenter produces, so Req 5.1 parity holds.

## Components and Interfaces

```swift
// MedataCore/Sources/SupportPlane/SupportRegion.swift

public enum SupportPlaneReference: String, Sendable, Codable {
    case foodSupport, edgeBand
}

public struct RingStatistics: Sendable, Equatable {
    public let medianMm: Float        // ≈ 0 on a correct fit; +18…+26 on the table
    public let madMm: Float           // bimodality detector; ~2 mm clean, large when straddling
    public let supportFraction: Float // share within ±ringBandMm, INNER band — the score
    public let bandMedianMm: [Float]  // inner/mid/outer; rises outward on a rimmed plate
    public let supportVisibility: Float // visible support area ÷ food area
    public let sampleCount: Int
}

public enum SupportRegion {
    // Radii in MILLIMETRES, converted per capture from median food depth.
    public static let ringInnerMm: Float = 8   // beyond the ~7 mm depth smear
    public static let ringOuterMm: Float = 25
    public static let ringBandCount = 3        // radial resolution: inner/mid/outer
    public static let bandStepMaxMm: Float = 6 // outward rise above this = rim or bowl
    public static let supportVisibilityMin: Float = 0.15
    public static let ringBandMm: Float = 5
    public static let ringSupportMin: Float = 0.6
    public static let ringSupportMarginMin: Float = 0.15
    public static let ringMadMaxMm: Float = 6
    public static let ringMinSamples = 60
    public static let foodAboveFractionMax: Float = 0.05
    public static let maxCandidatePlanes = 3
    public static let minCandidateSamples = 500
    public static let minAcceptedExtentPx = 24
    public static let maxIterationsPerPass = 2048

    // Depth intrinsics derived from colour (device depthIntrinsics are zeros).
    static func depthIntrinsics(from colour: CameraIntrinsics, depth: DepthMap) -> CameraIntrinsics

    // Depth-grid indices in the annulus, excluding food and low-confidence
    // samples. τ_conf = 0.40 applies here as it does in the band scan, so
    // `lidar-plane-fit-matte-table-confidence` is not bypassed (Req 7.5).
    static func contactRing(foodMask: BinaryMask, depth: DepthMap,
                            intrinsics: CameraIntrinsics) -> [Int]

    static func ringStatistics(ring: [Int], plane: SupportPlane, depth: DepthMap,
                               intrinsics: CameraIntrinsics) -> RingStatistics?

    // nil when no candidate is admissible — the caller then runs the edge-band
    // fit. Never throws: rejection is an expected outcome, not an error.
    public static func fitFoodSupportPlane(
        depth: DepthMap, colourIntrinsics: CameraIntrinsics,
        foodRegionMask: BinaryMask, gravityCamera: Vec3
    ) -> (plane: SupportPlane, ring: RingStatistics, candidateCount: Int)?

    // Req 6.1 requires the ring measure on EVERY depth-derived attempt,
    // including fallbacks — Req 6.2's before/after comparison depends on it.
    public static func ringStatistics(for plane: SupportPlane, depth: DepthMap,
                                      foodMask: BinaryMask,
                                      intrinsics: CameraIntrinsics) -> RingStatistics?
}
```

`contactRing` and `ringStatistics` are internal but directly unit-tested: they carry the geometry that decides the fit.

**Stats semantics.** On a `.foodSupport` row, `candidatePointCount` / `inlierCount` mean *native depth samples*; on `.edgeBand` they mean colour-grid points, as today. The two differ by ~56× and must not be compared across references — the persisted `planeReference` is what disambiguates them.

## Data Models

`EstimationAttemptRecord` gains four optionals, absent (not defaulted) on pre-feature rows so Req 6.3's distinction survives:

| Field | Type | Meaning |
|---|---|---|
| `planeReference` | `String?` | `foodSupport` / `edgeBand` |
| `planeRingMedianMm` | `Float?` | ≈ 0 on a correct fit |
| `planeRingMadMm` | `Float?` | bimodality; large means a straddling ring |
| `planeCandidateCount` | `Int?` | candidates extracted |

Calibration artefacts gain `supportPlaneReference`; absent blocks β_c application (Decision 10). Nothing breaks today because every β is `uncalibrated_unity`.

## Error Handling

No new refusals — every rejection resolves to the fallback, which is pre-feature behaviour.

| Condition | Result |
|---|---|
| Ring has fewer than `ringMinSamples` valid samples | fallback |
| Residue below `minCandidateSamples` before any candidate | fallback |
| No candidate admissible | fallback |
| Top two candidates within `ringSupportMarginMin` | fallback |
| Edge-band fit itself fails | existing refusal (pipeline Req 4.5), unchanged |

## Testing Strategy

**Synthetic unit tests** (`MedataCore/Tests/SupportPlaneTests/`), constructed depth maps:

| Case | Asserts |
|---|---|
| Plate 20 mm above table, table dominant ~9:1 | selects the plate; the case today's fitter fails |
| Ring straddling plate and table ~50/50 | rejected on MAD — the silent-failure case |
| Rimmed plate, well partly visible | inner band selects the well, not the rim |
| Rimmed plate, well fully covered | support visibility fails → fallback, not a rim under-read |
| Bowl, walls above the food | rejected; `reference == .edgeBand` |
| Co-height board elsewhere in frame | component scoring excludes it |
| Overhanging food below the plane | accepted — guards must not fire (Req 1.3) |
| Candidate below the lowest admissible | rejected (Req 3.3) |
| Winning plane below `minAcceptedExtentPx` | rejected |
| Depth grid ≠ 256×192 (N5k identity grid) | mm-based radii transfer (Req 5.1) |
| Food mask at frame edge | short ring → fallback, no crash |
| Same bytes twice | identical plane and reference (Req 7.7) |

**Deliberately no randomised generator.** An earlier draft proposed property tests; both were near-tautologies (fallback totality is guaranteed by the ordering contract; same-process determinism has no failure mode), `swift-testing`'s `arguments:` is parameterised rather than generative and has no shrinking, and CLAUDE.md's MVP gate says not to add test scaffolding unasked. The perturbation-stability property that *would* find counterexamples — ε < 1 mm of noise must not flip the reference — is expressed instead as a fixed parameterised sweep over seeded perturbations of the two real captures, which needs no new harness.

**Regression against real captures.** Reqs 6.2, 7.1–7.3 via `make harness-accuracy`. The 195/204 MB bundles are large because of RGB; a **depth-only slice** (256×192 Float32 depth + food mask ≈ 200 KB) is committed to the repo so Reqs 6.2 and 7.1 are executable by anyone, with the full bundles pulled from the device only for the volume criteria that need imagery.

**Numbers this design owes the requirements** — to be fixed during implementation against the fixture corpus, not asserted now: the Req 4.5 fallback-rate defect threshold, Req 5.1's device/replay plane tolerance and named fixture, Req 7.6's latency and memory budget, and `fallbackPenalty`. Each is a measurement, and stating a value here would be inventing evidence.

**Device-gated:** Req 7.6's budget and Req 7.8's weighed on-device verification.
