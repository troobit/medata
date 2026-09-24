# Bugfix Report: Two-View Unknown Carve

**Date:** 2026-09-24
**Status:** Fixed

## Description of the Issue

Two-view captures recorded a large `unknown_food` row from a nadir label map that had no unknown pixels at all. On the 2026-09-24 sesame-roll sitting, outcome `FE37458C` (bundle `1790223844719-success`) carried bread_white 286 cm³ plus unknown_food 1148 cm³, and outcome `1790232615202` carried bread_wholemeal 383 cm³ plus unknown_food 317 cm³; both nadir argmaxes are bread plus background only. The developer saw the phantom row on the review screen as "2 unknown food" and filed it as BACKLOG 24.

**Reproduction steps:**
1. Two-view capture of a plate where the oblique frame labels some pixels `unknown_food` (a wall, the plate rim, a shadow) and the nadir frame does not.
2. Estimate succeeds; open the record.
3. An Unknown food row with hundreds of cm³ appears beside the named rows.

**Impact:** Every two-view estimate (the path non-LiDAR phones use, and the path a LiDAR phone takes when the user chooses two-view) can carry a fabricated unknown row whose volume is the oblique silhouette's footprint at a 30 mm prior height. The row has 0 g carbohydrate, so totals are unaffected until the user names it, at which point a phantom mass becomes a phantom carb figure.

## Investigation Summary

- **Symptoms examined:** the two outcome rows above (`estimation_outcomes.measurements`), the bundles' nadir argmax class histograms (`bundle_view.py`), and the oblique segmentation measurements (`foodCoveragePercent` 2).
- **Code inspected:** `MaskMatcher.match` (label-only class matching, symmetric difference as single-view-only), `VoxelCarveEstimator.carve` fallback block, `singleViewExtrudedVolumeMm3`, `ClassPalette.isCarvableClass` (food or unknown), unknown-food-nameable task 4 (unknown integrates as its own class in both estimators).
- **Hypotheses tested:** a mismatch between the carve's class filter and the matcher — ruled out, both use the carvable predicate; the carve grid or matched-class path — ruled out, matched classes need both views. The single-view-only fallback from the oblique view is the only path that can emit a class absent from the nadir.

## Discovered Root Cause

`VoxelCarveEstimator.carve` runs the §6.6 single-view-only fallback for every carvable class present in exactly one view, from whichever view has it. `unknown_food` became carvable in unknown-food-nameable task 4 so that an unknown region seen in both views (or in the nadir) is measured. That also enrolled it in the oblique-only fallback, where an unknown region the model produces in the oblique frame alone — with nothing corresponding from above — is extruded to the plane at 30 mm and reported as food.

**Defect type:** Missing exclusion; a sentinel class treated as a named class in a fallback designed for named classes.

**Why it occurred:** Task 4 made the unknown class volumetric by widening `isCarvableClass`, and the fallback filter reads that predicate. No test covered an unknown class present in only one view.

**Contributing factors:** The oblique frame is more prone to `unknown_food` than the nadir (walls, rims, shadows in view), and the fallback's fixed 30 mm prior turns any silhouette into a large volume.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/Volume/VoxelCarveEstimator.swift` (fallback block) - `unknown_food` is filtered out of the view-2 (oblique) single-view-only fallback. Named classes keep the fallback from either view; an unknown region the nadir sees alone still carries.

**Approach rationale:** The nadir is the primary silhouette on both capture paths (the coverage gate in `Pipeline.estimate` reads it), so an unknown region only the oblique view labels has no support from the view that defines the plate. Excluding the sentinel from that one fallback is the smallest change that removes the fabrication without touching named-class behaviour or the matched-class carve.

**Alternatives considered:**
- Drop the oblique-only fallback for every class - Removes a §6.6 behaviour for named classes on a hunch; not evidenced by this bug.
- Require unknown to be matched in both views to carry at all - Would drop the nadir-only unknown row, which is the unknown-food-nameable case the user names in review.
- Spatial matching between views - The design defers it (label-only matching in v1); out of scope for a bugfix.

## Regression Test

**Test file:** `MedataCore/Tests/VolumeTests/VoxelCarveObliqueOnlyUnknownTests.swift`
**Test name:** `obliqueOnlyUnknownIsNotFabricated` (and `nadirOnlyUnknownStillCarries` guards the kept behaviour)

**What it verifies:** with the nadir all food_0 and the oblique half unknown_food, the carve reports no `unknown_food` volume and a positive food_0 volume; with the views swapped, the unknown row is still produced.

**Run command:** `swift test --filter VoxelCarveObliqueOnlyUnknown`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Volume/VoxelCarveEstimator.swift` | Exclude `unknown_food` from the oblique-only fallback |
| `MedataCore/Tests/VolumeTests/VoxelCarveObliqueOnlyUnknownTests.swift` | Regression tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass (`make spell`)

**Manual verification:**
- Replay of the two 2026-09-24 two-view bundles is not possible offline (the harness two-view path takes a nominal plane and the bundles' oblique tensors are stored; a device capture is the check). Next two-view sitting: the record must carry no unknown row unless the nadir shows one.

## Prevention

**Recommendations to avoid similar bugs:**
- When a sentinel class gains a capability through a shared predicate (`isCarvableClass`, `isVolumetricClass`), grep every consumer of that predicate and decide per site whether the sentinel belongs; write the one-view test at the same time.
- Fallbacks that manufacture geometry from a prior (the 30 mm extrusion) should be limited to the primary view.
