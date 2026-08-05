---
references:
    - specs/estimation/support-plane-reference/requirements.md
    - specs/estimation/support-plane-reference/design.md
    - specs/estimation/support-plane-reference/decision_log.md
---
# Support Plane Reference

## Geometry and selection

- [x] 1. Write failing tests for depth-intrinsics derivation and colour-to-depth mask downsampling <!-- id:284ca52 -->
  - Assert fx_d = fx_c*W_d/W_c and cx_d = (cx_c+0.5)*W_d/W_c-0.5 — the half-pixel terms are the point of the test; dropping them shifts the principal point ~3.75 colour pixels
  - Assert a depth pixel is food when ANY covered colour pixel is food, so ambiguity resolves towards exclusion (Req 2.1)
  - MedataCore/Tests/SupportPlaneTests/
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4)

- [x] 2. Implement depthIntrinsics(from:depth:) and the mask downsample in SupportRegion.swift <!-- id:284ca53 -->
  - New file MedataCore/Sources/SupportPlane/SupportRegion.swift
  - Do NOT read depth.depthIntrinsics — ARKitCaptureEngine writes it as all zeros, which yields a NaN plane
  - Blocked-by: 284ca52 (Write failing tests for depth-intrinsics derivation and colour-to-depth mask downsampling)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4)

- [x] 3. Write failing tests for contactRing and ringStatistics <!-- id:284ca54 -->
  - Ring excludes food pixels and samples below tau_conf 0.40; radii converted from mm per capture using median food depth
  - ringStatistics returns whole-ring median (persisted, not used for selection), per-band medians, inner-band support fraction, supporting-sector count, support visibility, per-band sample counts. There is NO MAD statistic: the MAD bar cannot fire on an admissible candidate and is deleted (Decision 19)
  - ringMinSamples = 200 holds per band, derived as ringSectorCount x 25 so sector fractions are measurement rather than noise (Decision 20); assert a thinner inner band returns nil
  - supportVisibility = annulus samples within inlierBandMm of the plane, divided by food sample count; both native depth samples. Assert it is grid-independent
  - Sector support (Req 3.6): divide the inner band into ringSectorCount equal arcs by atan2 about the food-mask centroid, count sectors meeting sectorSupportMin; empty sectors count as neither supporting nor failing (Decision 20). Assert a ring 65% on table over a contiguous arc yields few supporting sectors while its AGGREGATE support fraction reads a healthy 0.65
  - Cover: flat surface (bands equal), rim (rises outward), bowl (rises steeply), leaked-to-table (falls outward)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9)

- [x] 4. Implement contactRing and ringStatistics <!-- id:284ca55 -->
  - ringMinSamples = 200 must hold PER BAND, not just overall — radial banding divides the samples (Decision 14), and sectoring divides the inner band again, which is where the 200 floor comes from (Decision 20)
  - Blocked-by: 284ca54 (Write failing tests for contactRing and ringStatistics)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9)

- [x] 5. Write failing tests for bounded candidate sampling and CC-RANSAC extraction <!-- id:284ca56 -->
  - Candidate set bounded to an ANNULUS of 2x ringOuterMm around the food mask on the depth grid; assert clutter outside that neighbourhood cannot become a candidate
  - NOT dilate(foodMask, 2x foodRadius): that is ~8.3s^2 against today's four-band ~4s^2, i.e. looser than the code it replaces (Decision 15)
  - Assert scoring uses largest 8-connected inlier component, not total inlier count: a plane straddling two surfaces separated by a step must lose to either surface alone
  - Assert adaptive iteration stopping derives N from the observed inlier ratio rather than the inherited 256
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

- [x] 6. Implement bounded sampling and sequential CC-RANSAC with adaptive iterations <!-- id:284ca57 -->
  - Remove the polished inlier set within 2x inlierBandMm per pass — a 1x shell seeds near-duplicate planes on the next pass
  - Thread one depth-hash-seeded generator through all passes; ransac draws 3 uniformInt per iteration unconditionally, so the sequence stays pass-count-independent
  - Amortise CC labelling: label only hypotheses whose raw inlier count is within a constant factor of the running best. Unamortised it is up to maxIterationsPerPass x maxCandidatePlanes labellings, order 1e8 ops, on the path that already produced a 32 GB allocation failure (Decision 15)
  - Report the per-pass residue inlier ratio: the budget is sufficient because pass 1 removes the table, not because the pass-1 ratio is high (it is ~6%, where 2048 iterations reach only ~36%)
  - Blocked-by: 284ca53 (Implement depthIntrinsicsfrom:depth: and the mask downsample in SupportRegion.swift), 284ca56 (Write failing tests for bounded candidate sampling and CC-RANSAC extraction)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

- [x] 7. Write failing tests for admissibility guards, selection and determinism <!-- id:284ca58 -->
  - Guards filter ALL candidates for admissibility, then the best admissible wins — assert a phantom candidate failing a guard does not discard an admissible plate plane
  - Scene cases: plate 20mm above table with table dominant 9:1; ring straddling 50/50 (rejected on sectors, Decision 19); rimmed plate well partly visible with the rim in the outer band (inner band wins — the step guard reads inner-to-mid only, Decision 21); rimmed plate with the rim step inside the mid band (rejected to fallback); rimmed plate well fully covered (visibility fails); bowl; co-height board; overhanging food below the plane must NOT trigger guards; candidate below the lowest admissible; winner below minAcceptedExtentMm; food mask at frame edge
  - Overhang case (Decision 22): the weighed bread capture has ~11% of food samples below the plate plane. Assert the envelope guard ACCEPTS it — a count-fraction bar at 0.05 rejects it and fails Req 7.2
  - THE SILENT-FAILURE CASE (Decision 18): food to within 10mm of a flat plate's edge, ring 65% on table. The table plane scores 0.65 aggregate, clears the ambiguity margin, has a FLAT band profile and median ~0 — every guard except sectors passes. Assert it is rejected on sectors and never recorded as .foodSupport
  - Determinism: same bytes twice gives identical plane and identical reference
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9), [7.7](requirements.md#7.7)

- [x] 8. Implement fitFoodSupportPlane <!-- id:284ca59 -->
  - Returns nil rather than throwing — rejection is an expected outcome on the fallback path
  - Score on inner-band support fraction, not |median| (50% cliff); reject when the top two admissible candidates are within ringSupportMarginMin
  - There is NO MAD guard: the sector guard is the Req 2.3 dispersion bar (Decision 19). The band-step guard reads the inner-to-mid step only, or it rejects the partly-visible well Decision 14 rescues (Decision 21)
  - foodEnvelope guard REPLACES foodAboveFractionMax (Decision 22): reject when the food's p90 signed height above the plane is below foodEnvelopeMinMm. The fraction rejected this feature's own acceptance capture — ~11% of bread samples overhang below the plate plane against a 5% bar, failing Req 7.2
  - Req 3.3 comparator is the ANNULUS MEDIAN height with escapeBandMm, not "below the lowest admissible candidate", which compares a set minimum against itself and cannot fire (Decision 22)
  - Restore the SIGNED |median| admission guard (Req 3.2): the support fraction is unsigned and cannot separate a plane above the ring from one below it
  - Sector guard: reject when supporting sectors < minSupportingSectors. Without it, food near a plate edge selects the TABLE plane and persists median ~0, the value the spec treats as proof of correctness (Decision 18)
  - Blocked-by: 284ca55 (Implement contactRing and ringStatistics), 284ca57 (Implement bounded sampling and sequential CC-RANSAC with adaptive iterations), 284ca58 (Write failing tests for admissibility guards, selection and determinism)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9), [7.7](requirements.md#7.7)

## Wiring and persistence

- [x] 9. Write failing tests for fitter dispatch and the lazy fallback <!-- id:284ca5a -->
  - Restricted fit attempted FIRST (Decision 5 ordering); edge-band fit computed only on the rejection path
  - Assert the fallback plane is byte-identical to today's edge-band result, and that the refusal conditions of pipeline Req 4.5 are unchanged
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [x] 10. Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats <!-- id:284ca5b -->
  - Stats gain reference, ring statistics and candidate count
  - candidatePointCount/inlierCount now mean NATIVE DEPTH SAMPLES on a .foodSupport row and colour-grid points on .edgeBand — they differ ~56x and must never be compared across references
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane), 284ca5a (Write failing tests for fitter dispatch and the lazy fallback)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 11. Write failing tests for the persisted diagnostic fields <!-- id:284ca5c -->
  - Pre-feature rows decode with the fields absent — assert no default is supplied, since a default destroys the distinction the fields exist to provide
  - Ring statistics are computed and persisted on the FALLBACK path too; Req 6.2's before/after comparison is unexecutable otherwise
  - Assert the sector count is persisted on both paths (Req 6.4), and the band medians with it — the radial profile is what identifies a rim-borne ring after the fact (Decision 14)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 12. Add the EstimationAttemptRecord fields and persist from both paths <!-- id:284ca5d -->
  - planeReference, planeRingMedianMm, planeRingBandMediansMm, planeCandidateCount, planeSupportingSectors — all optional, no default. No planeRingMadMm: the MAD statistic is deleted with its guard (Decision 19)
  - Req 3.5 needs no new field: foodRegionCoveragePercent already persists on EstimationAttemptRecord (PipelineDiagnostics.swift:200)
  - planeSupportingSectors is what makes Req 6.4 executable: a ring median of ~0 alone cannot distinguish a correct fit from a ring that crossed the plate edge onto the table
  - No migration and no backfill: stored meals are left exactly as recorded (Decision 6)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5c (Write failing tests for the persisted diagnostic fields)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.9](requirements.md#7.9)

- [x] 13. Write a failing test for the fallback confidence penalty <!-- id:284ca5e -->
  - sigmaPlane = exp(-r/5) * iter_penalty * fallbackPenalty; assert the persisted residual is unchanged by the penalty
  - Stream: 1
  - Requirements: [4.6](requirements.md#4.6)

- [x] 14. Implement fallbackPenalty on sigmaPlane <!-- id:284ca5f -->
  - Multiplicative and separate so planeResidualMm stays the measured residual (Decision 12)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5e (Write a failing test for the fallback confidence penalty)
  - Stream: 1
  - Requirements: [4.6](requirements.md#4.6)

## Harness parity and reporting

- [x] 15. Write a failing test that device and offline derive the same support plane <!-- id:284ca5g -->
  - One shared implementation is what makes this structural rather than a convention — the test guards the deletion in the next task
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1)

- [x] 16. Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path <!-- id:284ca5h -->
  - HarnessCore already depends on SupportPlane, so the promotion moves in the allowed direction and no shipped code gains a HARNESS_ENABLED dependency
  - FixtureRunner has no food mask at that call site today — derive it from nadirSeg's argmax, the same source the device segmenter produces
  - Do NOT delete plateRegionMask/fitPlateRegionPlane: CalibrationArtifact.mixtureObservation:157 is a live caller (reached from HarnessCLI/main.swift:397 and :542) and mixture fixtures carry neither probs nor argmax, so no food mask can be derived there (Decision 17)
  - Report the skip counts at both mixture call sites — they wrap mixtureObservation in try?/catch, so a broken fitter empties the corpus while the run still reports success
  - Removes the estimatorPath branch from FixtureRunner.run only
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane), 284ca5g (Write a failing test that device and offline derive the same support plane)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [2.2](requirements.md#2.2)

- [x] 17. Regenerate the N5k calibration results against the promoted path <!-- id:284ca5i -->
  - SUPERSEDED premise: "moving the single-dominant branch off fitPlateRegionPlane changes those N5k outputs". It does not, on this corpus. Pre-checkpoint ingestion stamps every plate mixture (run_summary estimator_paths: mixture 3485, single_dominant 0), so FixtureRunner.fitSupportPlane is reached zero times and the promoted path has NO N5k coverage until Bucket C lands and ingestion re-runs with --checkpoint
  - Mixture fixtures do NOT move (Decision 17), so the corpus spans two references permanently, not just in transition — Req 5.4's within-reference rule is a standing constraint
  - This restores validity of existing artefacts against the corrected geometry; it is NOT new beta_c gravimetric calibration, which stays a Non-Goal
  - DONE 2026-08-05. Both artefacts regenerated, same flags and seed 42. The real deliverable is the support_plane_reference stamp: without it the Req 5.3 fail-closed guard aborts the bake, so until this ran the N5k corpus contributed no beta at all
  - MEASURED movement, attributable to the food DB v2 rebake (c855042, bcbe9bd) and NOT to the support plane — the stacking guard divides mapped mass by densityByClass from the bundled DB. Qualifying plates 181 -> 179, stacking excluded 56 -> 58, broccoli beta 0.516 (eff 35) -> 0.495 (eff 34). Split/unmapped/liquid/plane-fit-skip counts all unchanged
  - Calibration no longer beats baseline on carbs: MAPE 66.7 baseline -> 67.5 calibrated, where it was 105.8 -> 81.9. The DB v2 composition tables moved the baseline far more than one class at beta 0.495 can recover. Protein and fat still improve
  - The bake bakes nothing: broccoli is plateRegion, Req 5.4 skips it, every beta stays uncalibrated_unity (Decision 10 holds). generate.py was re-run to prove the Req 5.3 guard now admits the artefact; it only writes calibration lineage into the sqlite meta, which the DB v2 rebake had dropped
  - Compute cost was ~4 minutes total, not the segmenter pass prerequisites.md assumed — that cost applies to --checkpoint ingestion only, which this corpus does not use. prerequisites.md corrected
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

- [x] 18. Write a failing test for fallback-rate aggregation in the accuracy report <!-- id:284ca5j -->
  - Decision 11's decisive argument for this architecture rests on the fallback rate being measurable, so an unreported rate makes that argument unfalsifiable
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 19. Implement fallback-rate reporting in the accuracy report <!-- id:284ca5k -->
  - Aggregate across the fixture corpus, segmented by reference
  - Blocked-by: 284ca5d (Add the EstimationAttemptRecord fields and persist from both paths), 284ca5j (Write a failing test for fallback-rate aggregation in the accuracy report)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 20. Write failing tests for the calibration-artefact reference guard <!-- id:284ca5l -->
  - Absent reference MUST block application, not permit it — every artefact produced before this feature records none, and those are the ones calibrated on the old basis
  - Assert beta_c is fitted on the subset sharing the reference it will be applied under
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

- [x] 21. Add supportPlaneReference to the calibration artefact and enforce it fail-closed <!-- id:284ca5m -->
  - Nothing breaks today because every beta is uncalibrated_unity (Decision 10)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5l (Write failing tests for the calibration-artefact reference guard)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

## Regression fixtures and cleanup

- [x] 22. Commit depth-only fixture slices and add the regression criteria <!-- id:284ca5n -->
  - The 195/204 MB bundles are large because of RGB; a 256x192 Float32 depth map plus the food mask is ~200 KB, so committing a slice makes Reqs 6.2 and 7.1 executable by anyone
  - Done: tools/fixture_slice.py cuts a 290 KB slice per bundle (199 MB of the 204 is the probability tensor, which the fit never reads); both slices committed under MedataCore/Tests/SupportPlaneTests/Fixtures/
  - 7.1 parity: capture 1785135663727 within 5% of 235.96 cm3 (a parity check against a known implementation — that capture has no weighed truth)
  - 7.2: capture 1785901032716 volume within 20% of 200 cm3, class pinned as a precondition since mass depends on class and density this feature does not control
  - 6.2: ring measure +18..+26 mm under the pre-feature fit, ~0 under the corrected fit
  - MEASURED, and three of those figures do not hold (Decision 28): pre-feature ring +4.2 mm not +18..+26; corrected volume 306.8 cm3 not 235.96; and no candidate reaches 200 cm3 on 1785901032716 because the mask covers ~298 cm2 where the bread is ~200 cm2 — a segmentation bound, not a plane one. The two PRE-feature volumes reproduce within 5% and 3%, which is what says the slices are faithful. Reductions and separations are asserted in place of the superseded absolutes
  - 7.3 and 7.4 stay BLOCKED on captures that do not exist, not on code: 7.3 needs a weighed non-flat capture (the 208 g rice bundle loads zero meals) and 7.4 a bowl with in-palette food (the 2026-08-05 bowl was prawns, which refused at segmentation). See prerequisites.md captures 2 and 5
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

- [x] 23. Un-skip PlateTopSupportPlaneTests and delete the superseded code <!-- id:284ca5o -->
  - PlateTopSupportPlaneTests (MedataCore/Tests/VolumeTests/, XCTSkip at :55) encodes exactly this resolution and was skipped pending it
  - KEEP PlateRegionPlaneTests — the flood fill it tests survives for the mixture path (Decision 17). Delete only the untracked DiagProbe/ probe
  - Confirm the three prior plane-fit bugfixes still hold: no allocation failure at 1920x1440, no degenerate fit on a clean capture, no matte-table confidence regression
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [7.5](requirements.md#7.5)

- [x] 24. Measure and state the voxel-carve excluded-voxel change <!-- id:284ca5p -->
  - VoxelCarveEstimator excludes signedDistanceToPlane < 0 — a HARD exclusion, unlike the height field's max(0, .) clamp
  - Raising the plane 26 mm deletes a slab, and overhanging food (Decision 4) sits inside it, so the effect there is deletion rather than under-measurement and compounds with the accepted 11% bracket
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6)

## Documents

- [x] 25. Amend every document that names the old support-plane reference <!-- id:284ca5q -->
  - Edits, not cross-references: pipeline Req 4.2, pipeline design section 6.2, the pipeline glossary, and DECISIONS.md MD-9 (superseding entry, not a silent rewrite)
  - Add the support-plane reference to the nutrition5k-calibration transfer contract alongside masking (Req 5.2), which its own Req 3.6 already contradicts
  - State the two-view + ID-1-card path as unaffected: it derives no depth-derived plane, so the definitional change applies but no behaviour changes
  - State the resolvable-food limits as the design does (section "Stated limits"): minimum food WIDTH ~8 mm at 350 mm range (scaling with distance), minimum food HEIGHT ~2-4 mm bounded by depth noise, NOT an 8 mm height floor — the smear widens transitions, it does not attenuate plateaus wider than its kernel. Carry the capture-distance envelope, and state that items below the width floor fall back rather than being silently under-measured
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.5](requirements.md#2.5), [5.2](requirements.md#5.2)

## Calibrate and verify

- [ ] 26. Determine the constants the design deliberately left unstated <!-- id:284ca5r -->
  - Each is a measurement against the fixture corpus, not a value to invent: the fallback-rate defect threshold (4.5), the device/replay plane tolerance and its named fixture (5.1), and fallbackPenalty (4.6)
  - Req 3.7 adds the sector constants — ringSectorCount, sectorSupportMin, minSupportingSectors — which MUST be measured, not asserted. The values in the design are placeholders, as is every constant marked [owed] in SupportRegion
  - SETTLED (Decision 29): ringMinSamples = 200 per band is confirmed with 5.6-7.0x margin — measured band counts [1120, 1132, 1213] and [1294, 1347, 1392], and inner-band sectors carry 102-184 samples apiece against the 25 Decision 20 targets
  - SETTLED (Decision 29), and its one instruction MEASURED AND REFUSED (Decision 39): ringInnerMm = 8 holds at corpus range — the 4px smear is 7.45mm and 7.36mm at 338.9mm and 336.9mm — with an envelope now computed as ringInnerMm x f_d / 4 rather than quoted, 364.1mm and 366.4mm, the corpus standing at 93.1% and 92.0% of it. Decision 29 said the radius "must become max(ringInnerMm, 4 x mmPerPx)" beyond that; it must not. mmPerPx is z/f_d and carries range and grid resolution alike, but only range moves the smear, because a coarser grid subsamples a map ARKit has already smoothed. At 128px the smear-tracking radius reads 14.9mm for a physical smear still near 7.4, leaves three ring bands of 3.37mm against depth pixels of 3.73mm — each narrower than one pixel — and drops 1785135663727's inner band to 166 against the 200 floor, on the very grid where the plane transfers within 0.9mm. This is the boundary of the conversion Decisions 37 and 38 rest on: mmPerPx repairs grid dependence and cannot repair range dependence. The envelope is a RANGE bound, only a capture closes it, and the session now records the range per capture. Closes the prerequisites item of the same name
  - MEASURED, NOT SETTLED (Decision 29): per-sample sigma on a flat surface is 3.44mm on 1785135663727 and 6.98mm on 1785901032716, at 338.9mm and 336.9mm — the same range, so a 2x surface difference, and ringBandMm = 5 falls between them. The Decision 46 tension is resolved in KIND (its 20mm bar is a whole-plane residual, not a per-sample sigma) but ringSupportMin cannot be derived until a matte-surface capture characterises the spread. Now a REQUIREMENT of the capture session
  - SETTLED (Decision 29): supportVisibilityMin is firable and the unfirability argument was against the wrong region. The ratio is computed over the ANNULUS (0-50mm), which begins at the food boundary, not the ring (8-25mm), so a thin strip IS counted. Measured ceilings 1.710 and 1.426; the highest-support candidate reaches 0.880 and 1.032. The VALUE still needs capture 4
  - BLOCKED, with the reason now measured (Decisions 29, 30): the corpus supplies no clean correct-fit case — the plate-top candidate on 1785135663727 has per-sector inner medians reaching -32.6mm and the highest-support candidate on 1785901032716 is the TABLE, with three sectors +16.6 to +19.8mm above it. Both score 5 of 8, inside the 4...7 band Decision 18's geometry produces, so no minSupportingSectors separates them. The sign does separate them and the count discards it (Decision 30). The trio now waits on captures 1-6 ALONE — the proposal is settled by Decision 40, see below
  - RETIRED, not deferred (Decision 32): minCandidateSamples was two constants under one name. Its whole-fit half is gone — fitFoodSupportPlane now tests ring-band feasibility directly against the already-measured ringMinSamples, which is exact rather than a proxy and provably outcome-identical. Its extraction-pass half survives as minResidueSamples at the same value, still [owed] but bounded above at 581 by the measured per-pass residues [10469, 3310, 581] and [12551, 2811, 932]. This is the first owed value the feature has removed rather than postponed
  - BRACKETED (Decision 32), then RE-DENOMINATED (Decision 37): minAcceptedExtentPx sat in 13...26 on the corpus — above a 153-sample 12px sliver it correctly rejects, at or below the 26px smallest extent that reaches the later guards. It is now minAcceptedExtentMm = 44, bracketed 22.3...47.8mm on measured extents of 229/141/22mm and 285/81/48mm. The VALUE did not move — 24px is 44.68 and 44.14mm at the corpus mmPerPx, so 44 is the largest whole millimetre at or below both and every corpus verdict is unchanged — and it is still owed. What changed is that the bracket is PHYSICAL rather than a 256x192 one, so the capture session may set it against captures at any depth resolution
  - MEASURED, RULE RESTATED (Decision 33): ringOuterMm's stated derivation — "inside the smallest measured plate margin" — is unsatisfiable. The support margin, the distance at which the surface departs by more than ringBandMm, is [16, 40, 10, 42, 6, 4, 6, 44]mm and [34, 4, 46, 8, 30, 14, 12, 6]mm, every in-ring departure a 5.1-15.6mm fall, so the plate ends inside the ring in five of eight directions and the smallest margin (4mm) is inside ringInnerMm. Only 4 of 8 sectors reach the 13.7mm the sector measure is decided at, so minSupportingSectors = 6 is unreachable by GEOMETRY before any noise bar is consulted — ringOuterMm and the trio are one derivation, and the session must span plate sizes and food placements
  - MEASURED (Decision 35): Req 5.1's tolerance is 1mm of plane movement at the food and its named fixture is 1785135663727. One implementation serves both paths, so identical bytes agree exactly and the quantity at risk is the DEPTH GRID — across a 2x halving the plane moves 0.835mm and 0.037mm, normals tilting 0.945 and 0.063 degrees. Three riders: the transfer floors at the RING (64x48 leaves the inner band at 37 and 32 samples against ringMinSamples 200, the same mmPerPx bound as Decision 29's 365mm range envelope); planeCandidateCount is grid-dependent where the plane is not, 3 passes native and 2 halved (CLOSED by Decision 38 — see below); and minAcceptedExtentPx was the ONLY bar denominated in pixels (CLOSED by Decision 37 — see below). The DEVICE leg stays task 27's
  - CLOSED (Decision 37): Decision 35's third rider — minAcceptedExtentPx the ONLY bar denominated in pixels, so a surface admitted at 44px is rejected as a sliver at 22px — is repaired rather than documented. Converted through the same mmPerPx the ring radii already use, four surfaces paired across the 2x halving drift 1.698, 0.102, 1.839 and 0.000mm in millimetres while their pixel extents halve (123->61, 76->38, 155->77, 44->22), and verdict flips fall from one to ZERO. Req 5.1's transfer claim carries no exception and no bar in admissibility is denominated in pixels. N5k's 3.389x pixel-density gap is neutralised before Bucket C rather than during it. The other two riders stand: the ring sample floor, and planeCandidateCount (the latter CLOSED by Decision 38 — see below)
  - CLOSED (Decision 38): Decision 35's second rider — planeCandidateCount grid-dependent where the plane is not — is repaired rather than documented, and the cause was one constant. minResidueSamples was a raw SAMPLE count, and sample counts quarter under a 2x halving where the surface does not, so pass 3 (entering with 581 and 932 samples natively) was cut. minResidueSamples = 500 becomes minResidueAreaMm2 = 1691, converted through the same mmPerPx, rounded UP so the bar is never weaker. The VALUE did not move — 500 samples is 1732.6 and 1691.5mm2 on the two captures, so 1691 is the largest whole mm2 at or below both and every corpus pass keeps its verdict. The residue AREA is the invariant: the annulus agrees to 0.29% and 1.17% across the halving where its sample count quarters, later passes to 5.02/6.43/4.94/22.75% because inlier removal is resolved on the grid. Candidate count is now 3 -> 3 and the plane at the food is unchanged. ONE rider is left, the ring sample floor, and it is correct as it stands: ringMinSamples is a statistical requirement per sector, so its refusal at 64x48 is the transfer's honest resolution floor and not a denomination defect
  - BOUNDED ABOVE, and the shipped value is outside the bound (Decision 36): fallbackPenalty is a price, not a bar, and Req 4.6 — "no higher than a restricted fit of EQUAL residual" — is met by any value in (0, 1), so it cannot choose one. sigmaPlane is exp(-r/5), so a penalty p charges -5.ln(p) mm of plane error and 0.9 charges 0.53 mm. Measured per food sample, the edge-band plane adds 18.37 mm to the mean food pixel on 1785135663727 (p10 7.96, p90 28.61; the planes are 7.18 degrees apart, so Decision 35's single ray will not do), pricing it at 0.025 — a 35.5x over-report, corroborated by the regression suite's 408 cm3. The residual channel works AGAINST it: the fallback's residual is LOWER than the restricted fit's (1.95 vs 2.33 mm), so 71% of the penalty cancels that advantage and the net reduction is 3.1%. One-sided, because the fallback is the CORRECT plane when food rests on the surrounding surface — so the constant prices a mixture whose weight is Req 4.5's rate. Pricing it per capture from the persisted ring measure is measured and rejected: ratios 0.231 and 2.471, wrong in both directions
  - SETTLED as a RULE, its count still owed (Decision 40): Decision 30's proposal is resolved and it was the task's last non-capture blocker. The rule is that a FAILING sector — below sectorSupportMin — whose signed inner-band median exceeds +ringBandMm is CROSSED and rejects the candidate above a count; below -ringBandMm it has ESCAPED, which is the plate ending (Decision 33) and not grounds for rejection. Decision 30 left the proposal open because "a rule for rejecting on signed sectors needs a threshold", and measured that holds on ONE axis only. The magnitude bar is ringBandMm, already [inherited]: the plate candidate's highest failing median is -6.794mm and the table candidate's lowest is +16.603mm, a 23.397mm window with 5 sitting 11.794 above its floor and 11.603 below its ceiling. Restricting to FAILING sectors is what earns that — over all sectors the window is +3.846...+5.974mm, a tenth as wide, and the bar would be fitted rather than inherited. The rule is the per-arc form of ringMedianMaxMm, which on the table candidate reads +3.04mm and does NOT fire while three of its sectors read +16.6 to +19.8: Decision 18's silent-failure case measured rather than argued. What is owed is the COUNT, maxCrossedSectors, bracketed 0...2 (0 crossed on the plate candidate, 3 on the table one) and set by capture 6. NOTHING is rewired — shipping the rule means asserting that count, which Req 3.7 forbids for exactly these constants
  - SECOND BRACKET, and on one constant it contradicts the first (Decision 41): the committed SUITE bounds six owed constants, measured per assertion rather than per scene. ringSupportMin <= 0.676, minSupportingSectors 6...7, bandStepMaxMm 0.024...9.288mm, supportVisibilityMin <= 2.667, foodEnvelopeMinMm -6.758...8.233mm, escapeBandMm >= 14.868mm. Two are the ONLY bound that exists — the corpus gives ringSupportMin no ceiling (Decision 29) and bandStepMaxMm no floor (Decision 34). Two bind TIGHTER than the corpus, so a value set from captures alone can land inside the corpus bracket and outside the suite's: foodEnvelopeMinMm 8.233 against 25.793mm, escapeBandMm 14.868 against a corpus reaching +5.750mm. One CONTRADICTS: a real intended candidate scores 5 of 8 sectors (Decision 33) so minSupportingSectors must fall to 5 or below, while the silent-failure scene the guard exists to reject ALSO scores 5 and floors the suite at 6. No value satisfies both — that is Decision 30's finding as a suite constraint, and it resolves when Decision 40's crossed-sector rule lands, with the SCENE moving with the constant. Closes the prerequisites item "set the guard constants before task 8 hard-codes them", the last one that was not a hardware gate
  - MEASURED AS A FUNCTION, not as a number (Decision 42): Req 4.5's fallback rate over the committed corpus is a readout of the OWED constants and of nothing else, so a threshold stated now grades the placeholders — Req 3.7's circularity arriving at Req 4.5 by another route. The shipped placeholders fall back on 2 of 2 captures (rate 1.000, Req 4.5's own "delivering nothing"); minSupportingSectors swept alone reads 8-6 → 1.000 then 5-0 → 0.500, one bar crossing the 5-of-8 sectors Decision 33 measured; every owed bar at its loosest reads 0.000. The rate reaching zero costs NO wrong plane — both captures then select the candidate nearest Req 3.1's zero, -0.521mm and -1.023mm — so the geometry is sound and the distance from 100% to 0% is constants the suite contradicts (Decision 41). What holds the wrong planes out there is ringMedianMaxMm, which is [inherited], and it clears the table candidate by 0.338mm on a 5mm bar (6.8%): an accidental sub-millimetre separation standing in for the sector guard, and the argument for Decision 40's rule that does not need capture 6. The 0.000 is a BOUND not a proposal — on 1785901032716 the right plane is admissible only at support 0.362 over 2 of 8 sectors, Decision 33's plate margin read from the rate's side. Req 4.5's denominator problem stands as the SECOND reason, not the only one
  - BOTH BRACKETS AGREE, and on nothing else do they (Decision 43): read through Decision 40's rule, the committed suite brackets maxCrossedSectors at 0...2 — the corpus's own bracket unchanged — on the same eight scenes where minSupportingSectors has an EMPTY joint interval of 6...5. Decision 41's third negative is therefore withdrawn: NO committed scene has to move when the crossed-sector rule lands, because the collision belongs to the unsigned count and not to the suite. Five scenes whose assertions require the sector guard to pass carry 0 crossed sectors; the silent-failure scene carries 3 at +19.95 to +19.98mm, mirroring the corpus table candidate's 3 at +16.6 to +19.8mm. This is the ONLY owed constant whose two sources agree exactly, so the session sets it from captures with no suite interaction to track. It stays owed: every committed scene and both corpus candidates return the same verdict at 0, at 1 and at 2, so nothing in hand narrows the bracket and any choice among the three is asserting. Two side findings — overhangingFood is the first committed scene to exercise the rule's ESCAPE half, at -20.024mm; and neither rimmed-plate scene covers Decision 40's stated blind spot, both reading 8 of 8 supporting with no failing sector because their rims never reach the inner band the sector median is computed over, so captures 3 and 4 are its only source. Against Decision 42's 0.338mm: the rule rejects the table candidate by a one-sector margin at the loosest admissible ceiling and three at the tightest
  - REMAINING and gated: ringSupportMin, the sector trio plus maxCrossedSectors (Decision 40), ringSupportMarginMin, ringOuterMm (against the restated rule), bandStepMaxMm, foodEnvelopeMinMm, minResidueAreaMm2 (floor only — the denomination is settled, Decision 38), minAcceptedExtentMm (value only — the denomination is settled, Decision 37), supportVisibilityMin (value), Req 4.5's fallback-rate threshold, fallbackPenalty (value — now the SAME gate as the rate, Decision 36). Req 4.5's denominator does not exist until model-production Bucket C: N5k pre-checkpoint ingestion runs no segmenter, so those 3,490 fixtures carry no food mask and fitFoodSupportPlane has no input on them
  - UNEXERCISED, not merely unset (Decision 34): of the nine rejection reasons only three ever fire on the corpus — extent, supportFraction, sectors — and a fourth, ringMedian, only when the guards are evaluated independently instead of short-circuited. Five never fire, and four owed constants sit behind them. foodEnvelopeMinMm is bounded ABOVE at 25.8mm by the intended candidate's envelope and not below (every corpus envelope is positive, 7.2-39.6mm; the design's "bread p90 ~ +8mm" is measured at +26.6mm). bandStepMaxMm reads an outward RISE and every corpus step is a fall of -0.5 to -6.5mm. supportVisibilityMin is firable but never fired — corpus floor 0.246 against a 0.15 bar. escapeBandMm's one-sidedness is confirmed correct for Req 3.3, but the corpus reaches +5.7mm against a 30mm bar and NO planned capture fires it. ringSupportMarginMin cannot run at all — it needs two admissible candidates and no capture yields one; the gaps real candidates open, 0.312 and 0.117, straddle the shipped 0.15
  - The instrumented pass exists — MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift. Adding the six session captures is cutting slices with tools/fixture_slice.py and extending its captures list
  - TRIED AND REJECTED (Decision 31): the 208 g mounded-rice bundle 1785054950406 is the non-flat anchor the corpus lacks and it slices cleanly, so the FixtureLoader failure was never the real bar. It is disqualified on depth confidence — 43.2% of its food mask is ARKit-low against 0.0% on both admitted captures, the discarded samples are the near ones (247.9mm against the surviving 277.8mm), so tau_conf removes the mound and the best candidate reads the food 9.0mm BELOW its own plane. Committed as rejectedCaptures with the measurement asserted, because admitting it scores 3 sectors and flips the sector test to a spurious "separable". Prerequisites capture 2 must still be taken
  - Record each with its derivation in decision_log.md
  - Blocked-by: 284ca5k (Implement fallback-rate reporting in the accuracy report), 284ca5n (Commit depth-only fixture slices and add the regression criteria)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.1](requirements.md#5.1)

- [ ] 27. STOP — on-device verification against weighed food <!-- id:284ca5s -->
  - Human-gated: deploy Release and capture weighed flat food on the iPhone 16 Pro; confirm the corrected volume and that the reference recorded is .foodSupport
  - EXPECT .edgeBand until task 26 sets the constants (Decision 42): the shipped placeholders fall back on 2 of 2 committed captures, so a device capture of this kind records .edgeBand and this task's reference check fails for CONSTANT reasons rather than implementation ones. Running it before task 26 measures nothing about the feature
  - Also capture the weighed rimmed-plate case on the SINGLE-VIEW path (Req 7.10; prerequisites capture 4) — no such capture exists, and per Req 7.11 a weighed capture is evidence only if capturePath confirms single_view_lidar. The 2026-08-05 session lost all four weighed truths to the two-view path
  - Measure added latency and peak memory at 1920x1440 for Req 7.6 — this path has produced an OOM before, and CPU is the quantity at risk now that adaptive iteration makes it scene-dependent
  - Pull the DB and confirm the persisted ring statistics read ~0 on a correct fit
  - Blocked-by: 284ca5r (Determine the constants the design deliberately left unstated)
  - Stream: 1
  - Requirements: [7.6](requirements.md#7.6), [7.8](requirements.md#7.8), [7.10](requirements.md#7.10), [7.11](requirements.md#7.11)
