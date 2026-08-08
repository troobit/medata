# Support-plane implementations: the three competing lines

Three independent implementations of `specs/estimation/support-plane-reference/`
exist as of 2026-08-08. This note records where each lives, how they differ, and
the evidence each produced, so a merge/selection decision can be made without
re-deriving any of it. See [support-region.md](support-region.md) for the research
line's own implementation notes.

## Where they live

| Line | Location | Tasks | State |
|---|---|---|---|
| research | branch `research`, commit `f143a66` | 1–8 of 27 | committed; whole-ring median guard (see below) |
| impl-1 (opus) | branch `orbit-impl-1/support-plane-reference` | 25/27 + deep task 26 | green: 572 XCTest (5 skipped) + 324 swift-testing / 36 suites |
| impl-2 (sonnet) | branch `orbit-impl-2/support-plane-reference` | 25/27 + partial task 26 | green: 572 XCTest (5 skipped) + 213 swift-testing / 27 suites |

The variant branches were produced by an orbit compete run (2026-08-05/06, ~$664
combined) whose worktrees sit under
`specs/estimation/support-plane-reference/.orbit/worktrees/` (gitignored via
`**/.orbit/`). **Do not delete the branches or worktrees without a selection
decision** — they are local-only by design (competing implementations are never
pushed) and the worktrees are the only place orbit's phase logs live. Orbit
recorded both variants as `failed` — that status is spurious: both hit the Claude
weekly usage limit in the final phase ("Calibrate and verify: exit status 1" =
quota, not verification). Both variants' own summaries record 6 phases completed.
impl-1's loose end-of-run measurement work is committed as `0f30ac8` on its branch.

All three fork from `d456028` (which had no `SupportRegion.swift`), and each wrote
the file from scratch, so any git merge across lines is add/add — fully manual.
Selection means choosing a surviving line, not merging diffs.

## Scope difference (the biggest one)

research implemented only the geometry-and-selection phase (tasks 1–8). Both
variants also built tasks 9–25: `LiDARSupportPlaneFitter` dispatch with lazy
edge-band fallback, persisted plane diagnostics on `EstimationAttemptRecord`,
the fallback confidence penalty, device/offline parity (`FixtureRunner`
single-dominant branch on the promoted path), fallback-rate reporting, the
calibration-artefact reference guard, and committed depth-slice regression
fixtures. Continuing the research line means re-implementing all of that;
adopting a variant means inheriting it tested.

## Algorithmic divergences in the core fitter

1. **Ring-median admissibility guard.** research reads the *whole-ring* median
   (`abs(ring.medianMm) <= ringBandMm`). Both variants independently moved this
   to the *inner band* (`bandMedianMm[0]`) — impl-2's Decision 24, impl-1's
   `ringMedianMaxMm` — for the same measured reason: when the ring's outer edge
   reaches past the plate, mid/outer samples legitimately sit on the table and
   drag the whole-ring median off zero, rejecting correct fits. Two independent
   corrections against real captures: treat research's guard as wrong.

2. **Radial banding geometry.** research and impl-1 band by mm-distance from the
   food-mask boundary (the design's reading). impl-2 bands by pixel distance from
   the *ring centroid*, normalised to the ring's own observed near/far spread —
   deliberate and documented, but on a non-circular food mask its "inner band"
   is not everywhere the band nearest the food. Scrutinise before adopting impl-2.

3. **Consensus polish.** Both variants run the full
   `consensusPolishMaxPasses` loop with a gravity gate per re-refine. research
   does a single re-selection after `refine`, so its winner can still depend on
   which minimal RANSAC sample won.

4. **Distance transform.** impl-1 uses the exact Felzenszwalb–Huttenlocher
   squared-EDT; research and impl-2 use the two-pass chamfer approximation
   (adequate at ring scale per both; the exact one costs nothing extra at O(WH)).

5. **Structure.** impl-1 precomputes a `DepthGeometry` (points, validity, scale,
   centroid) once and reuses a generation-stamped `ComponentScratch` for CC
   labelling (O(inliers) per call — written against the 32 GB OOM history on this
   path). Its admissibility returns a typed `CandidateRejection` enum and its
   winner sort is a total order (supportFraction → componentSize → d, Req 7.7).
   impl-1 also adds `SupportPlaneReference.plateRegion` for the N5k calibration
   basis lineage (Req 5.4) — research will need this at task 16 regardless.
   impl-2's `ringStatistics(for:)` overload recomputes the downsample + chamfer
   per call (three times across `contactRing`/`annulusIndices`/stats) — cheap on
   256×192 but the least efficient of the three shapes.

6. **Shared gap in all three** (impl-1 Decisions 52/55): `LiDARPlaneFitter.refine`
   is not gravity-gated, so a polished plane can leave the 15° cone and stay in
   the candidate set (measured at 20.5° on a real capture; rejected downstream
   today). Deliberately unrepaired — repairing it moves the answer, which task 26
   prices.

## Task-26 evidence: two complementary halves

The measurement work is implementation-independent — most findings are statements
about the design's constants, valid for whichever line survives.

**impl-1 (Decisions 27–58, in its `decision_log.md`): exhaustive sweeps on
committed evidence** (2 depth-slice fixtures + 8 synthetic scenes; the sweep suite
runs ~14 min). Highlights: `annulusOuterMm` pinned at 50 mm and identified as the
only owed constant that moves the selected plane (18.8 mm at the food);
`minResidueAreaMm2`/`minAcceptedExtentMm` re-denominated to mm²/mm so Req 5.1's
grid transfer holds; `ransacSuccessProbability` exposed as the live end of the
iteration clamp (seed spread 2.095 → 0.194 mm at 0.99999); the crossed-sector
rule (Decision 40) as the stated fix for `minSupportingSectors`' sign-blindness,
with the corpus determining `maxCrossedSectors = 2`; which joint constant sets
must be fixed together and which brackets must not be interpolated.

**impl-2 (Decisions 34–43, in its `decision_log.md`): real-device external
validity.** Grew the device corpus n=3 → n=11 by pulling every capture bundle off
the phone. Found a `paletteVersion` mislabel silently dropping bundles from
`FixtureLoader` — **a live tooling bug on research, independent of any variant**.
Measured `ringSupportMin`'s clean gap (correct-surface ≥ 0.99 vs wrong-surface
≤ 0.483); swept `ringSectorCount` over {3..32} — separation is a band (3–5, 7–9),
inverts past 13; root-caused a 40 % volume under-read to physically overlapping
bread slices in the ground-truth capture, not code.

Productive disagreement worth keeping: impl-2's n=11 supports lowering
`minSupportingSectors` 6 → 5 on ring geometry but declined on a volume
regression it couldn't explain (its Decision 38); impl-1's Decisions 40/48 supply
the mechanism (sign-blind count; crossed-sector rule) that explains it.

## Open items

- Selection decision: which line survives (record in the spec's decision log).
- Import the task-26 record from both variants' decision logs into the surviving
  line's `decision_log.md`.
- Fix the `paletteVersion` mislabel in the fixture tooling on research regardless
  of selection.
- Task 27 (on-device weighed-food verification) remains human-gated on every line.
