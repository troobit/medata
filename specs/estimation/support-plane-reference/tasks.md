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
  - Scene cases: plate 20mm above table with table dominant 9:1; ring straddling 50/50 (rejected on sectors, Decision 19); rimmed plate well partly visible with the rim in the outer band (inner band wins — the step guard reads inner-to-mid only, Decision 21); rimmed plate with the rim step inside the mid band (rejected to fallback); rimmed plate well fully covered (visibility fails); bowl; co-height board; overhanging food below the plane must NOT trigger guards; candidate below the lowest admissible; winner below minAcceptedExtentPx; food mask at frame edge
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

- [ ] 9. Write failing tests for fitter dispatch and the lazy fallback <!-- id:284ca5a -->
  - Restricted fit attempted FIRST (Decision 5 ordering); edge-band fit computed only on the rejection path
  - Assert the fallback plane is byte-identical to today's edge-band result, and that the refusal conditions of pipeline Req 4.5 are unchanged
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [ ] 10. Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats <!-- id:284ca5b -->
  - Stats gain reference, ring statistics and candidate count
  - candidatePointCount/inlierCount now mean NATIVE DEPTH SAMPLES on a .foodSupport row and colour-grid points on .edgeBand — they differ ~56x and must never be compared across references
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane), 284ca5a (Write failing tests for fitter dispatch and the lazy fallback)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [ ] 11. Write failing tests for the persisted diagnostic fields <!-- id:284ca5c -->
  - Pre-feature rows decode with the fields absent — assert no default is supplied, since a default destroys the distinction the fields exist to provide
  - Ring statistics are computed and persisted on the FALLBACK path too; Req 6.2's before/after comparison is unexecutable otherwise
  - Assert the sector count is persisted on both paths (Req 6.4), and the band medians with it — the radial profile is what identifies a rim-borne ring after the fact (Decision 14)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [ ] 12. Add the EstimationAttemptRecord fields and persist from both paths <!-- id:284ca5d -->
  - planeReference, planeRingMedianMm, planeRingBandMediansMm, planeCandidateCount, planeSupportingSectors — all optional, no default. No planeRingMadMm: the MAD statistic is deleted with its guard (Decision 19)
  - Req 3.5 needs no new field: foodRegionCoveragePercent already persists on EstimationAttemptRecord (PipelineDiagnostics.swift:200)
  - planeSupportingSectors is what makes Req 6.4 executable: a ring median of ~0 alone cannot distinguish a correct fit from a ring that crossed the plate edge onto the table
  - No migration and no backfill: stored meals are left exactly as recorded (Decision 6)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5c (Write failing tests for the persisted diagnostic fields)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.9](requirements.md#7.9)

- [ ] 13. Write a failing test for the fallback confidence penalty <!-- id:284ca5e -->
  - sigmaPlane = exp(-r/5) * iter_penalty * fallbackPenalty; assert the persisted residual is unchanged by the penalty
  - Stream: 1
  - Requirements: [4.6](requirements.md#4.6)

- [ ] 14. Implement fallbackPenalty on sigmaPlane <!-- id:284ca5f -->
  - Multiplicative and separate so planeResidualMm stays the measured residual (Decision 12)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5e (Write a failing test for the fallback confidence penalty)
  - Stream: 1
  - Requirements: [4.6](requirements.md#4.6)

## Harness parity and reporting

- [ ] 15. Write a failing test that device and offline derive the same support plane <!-- id:284ca5g -->
  - One shared implementation is what makes this structural rather than a convention — the test guards the deletion in the next task
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1)

- [ ] 16. Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path <!-- id:284ca5h -->
  - HarnessCore already depends on SupportPlane, so the promotion moves in the allowed direction and no shipped code gains a HARNESS_ENABLED dependency
  - FixtureRunner has no food mask at that call site today — derive it from nadirSeg's argmax, the same source the device segmenter produces
  - Do NOT delete plateRegionMask/fitPlateRegionPlane: CalibrationArtifact.mixtureObservation:157 is a live caller (reached from HarnessCLI/main.swift:397 and :542) and mixture fixtures carry neither probs nor argmax, so no food mask can be derived there (Decision 17)
  - Report the skip counts at both mixture call sites — they wrap mixtureObservation in try?/catch, so a broken fitter empties the corpus while the run still reports success
  - Removes the estimatorPath branch from FixtureRunner.run only
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane), 284ca5g (Write a failing test that device and offline derive the same support plane)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [2.2](requirements.md#2.2)

- [ ] 17. Regenerate the N5k calibration results against the promoted path <!-- id:284ca5i -->
  - Moving the single-dominant branch off fitPlateRegionPlane changes those N5k outputs, so the previously recorded nutrition5k-calibration results are rebased
  - Mixture fixtures do NOT move (Decision 17), so the corpus spans two references permanently, not just in transition — Req 5.4's within-reference rule is a standing constraint
  - This restores validity of existing artefacts against the corrected geometry; it is NOT new beta_c gravimetric calibration, which stays a Non-Goal
  - May need compute time; see prerequisites.md
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

- [ ] 18. Write a failing test for fallback-rate aggregation in the accuracy report <!-- id:284ca5j -->
  - Decision 11's decisive argument for this architecture rests on the fallback rate being measurable, so an unreported rate makes that argument unfalsifiable
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [ ] 19. Implement fallback-rate reporting in the accuracy report <!-- id:284ca5k -->
  - Aggregate across the fixture corpus, segmented by reference
  - Blocked-by: 284ca5d (Add the EstimationAttemptRecord fields and persist from both paths), 284ca5j (Write a failing test for fallback-rate aggregation in the accuracy report)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [ ] 20. Write failing tests for the calibration-artefact reference guard <!-- id:284ca5l -->
  - Absent reference MUST block application, not permit it — every artefact produced before this feature records none, and those are the ones calibrated on the old basis
  - Assert beta_c is fitted on the subset sharing the reference it will be applied under
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

- [ ] 21. Add supportPlaneReference to the calibration artefact and enforce it fail-closed <!-- id:284ca5m -->
  - Nothing breaks today because every beta is uncalibrated_unity (Decision 10)
  - Blocked-by: 284ca5b (Implement LiDARSupportPlaneFitter dispatch and extend SupportPlaneFitStats), 284ca5l (Write failing tests for the calibration-artefact reference guard)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

## Regression fixtures and cleanup

- [ ] 22. Commit depth-only fixture slices and add the regression criteria <!-- id:284ca5n -->
  - The 195/204 MB bundles are large because of RGB; a 256x192 Float32 depth map plus the food mask is ~200 KB, so committing a slice makes Reqs 6.2 and 7.1 executable by anyone
  - 7.1 parity: capture 1785135663727 within 5% of 235.96 cm3 (a parity check against a known implementation — that capture has no weighed truth)
  - 7.2: capture 1785901032716 volume within 20% of 200 cm3, class pinned as a precondition since mass depends on class and density this feature does not control
  - 7.3: a weighed non-flat capture — NOT the 208 g rice bundle, which FixtureLoader loads zero meals from; see prerequisites.md for the replacement. 7.4: the bowl fixture exercises the fallback path
  - 6.2: ring measure +18..+26 mm under the pre-feature fit, ~0 under the corrected fit
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

- [ ] 23. Un-skip PlateTopSupportPlaneTests and delete the superseded code <!-- id:284ca5o -->
  - PlateTopSupportPlaneTests (MedataCore/Tests/VolumeTests/, XCTSkip at :55) encodes exactly this resolution and was skipped pending it
  - KEEP PlateRegionPlaneTests — the flood fill it tests survives for the mixture path (Decision 17). Delete only the untracked DiagProbe/ probe
  - Confirm the three prior plane-fit bugfixes still hold: no allocation failure at 1920x1440, no degenerate fit on a clean capture, no matte-table confidence regression
  - Blocked-by: 284ca5h (Wire FixtureRunner's single-dominant branch to the promoted path; KEEP the flood fill for the mixture path)
  - Stream: 1
  - Requirements: [7.5](requirements.md#7.5)

- [ ] 24. Measure and state the voxel-carve excluded-voxel change <!-- id:284ca5p -->
  - VoxelCarveEstimator excludes signedDistanceToPlane < 0 — a HARD exclusion, unlike the height field's max(0, .) clamp
  - Raising the plane 26 mm deletes a slab, and overhanging food (Decision 4) sits inside it, so the effect there is deletion rather than under-measurement and compounds with the accepted 11% bracket
  - Blocked-by: 284ca59 (Implement fitFoodSupportPlane)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6)

## Documents

- [ ] 25. Amend every document that names the old support-plane reference <!-- id:284ca5q -->
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
  - Confirm the derived ringMinSamples = 200 floor (Decision 20) against the corpus fallback rate: it trades small-and-far food for sector statistics that mean something, and the corpus is what shows whether the trade is priced right
  - Measure the support-surface depth noise distribution: ringSupportMin = 0.6 with a +/-5mm band implies sigma_z <= 5.9mm, which is in tension with the matte-table evidence behind Decision 46's 20mm bar. If real noise exceeds ~6mm, every matte-table capture falls back for a reason unrelated to plane selection
  - Record each with its derivation in decision_log.md
  - Blocked-by: 284ca5k (Implement fallback-rate reporting in the accuracy report), 284ca5n (Commit depth-only fixture slices and add the regression criteria)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.1](requirements.md#5.1)

- [ ] 27. STOP — on-device verification against weighed food <!-- id:284ca5s -->
  - Human-gated: deploy Release and capture weighed flat food on the iPhone 16 Pro; confirm the corrected volume and that the reference recorded is .foodSupport
  - Also capture the weighed rimmed-plate case on the SINGLE-VIEW path (Req 7.10; prerequisites capture 4) — no such capture exists, and per Req 7.11 a weighed capture is evidence only if capturePath confirms single_view_lidar. The 2026-08-05 session lost all four weighed truths to the two-view path
  - Measure added latency and peak memory at 1920x1440 for Req 7.6 — this path has produced an OOM before, and CPU is the quantity at risk now that adaptive iteration makes it scene-dependent
  - Pull the DB and confirm the persisted ring statistics read ~0 on a correct fit
  - Blocked-by: 284ca5r (Determine the constants the design deliberately left unstated)
  - Stream: 1
  - Requirements: [7.6](requirements.md#7.6), [7.8](requirements.md#7.8), [7.10](requirements.md#7.10), [7.11](requirements.md#7.11)
