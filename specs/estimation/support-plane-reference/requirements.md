# Requirements: Support Plane Reference

## Introduction

The LiDAR support plane is fitted to the table rather than to the surface the food rests on — measured 26.1 mm too low — and because volume is integrated per-pixel above that plane, the offset is added to every food pixel and produces a 2–3.6× volume over-read that is proportionally largest on the flattest food. Two independent weighed captures confirm the magnitude: 2 slices of bread at 80 g read as 285.94 g (3.57×, implying a 10.1 mm slice), and 208 g of rice read as 440 g (2.1×). The current code faithfully implements the current specification — pipeline Req 4.2 fits "at and around the lower edge of the food bounding region" and `DECISIONS.md` MD-9 calls edge-band sampling "the table-plane prior" — so this feature changes what the specification asks for, not merely how it is implemented.

## Non-Goals

- Measuring food in a vessel whose walls rise above the food accurately — such captures fall back to the existing reference rather than being measured from the vessel interior.
- Compensating for food that overhangs its support; the resulting under-measurement is accepted and documented (Decision 4).
- Re-estimating, migrating, or rewriting meals already stored against the old reference.
- β_c gravimetric calibration itself (deferred by model-production Decision 3); this feature fixes the geometric basis calibration will later be run against, and constrains how calibration may use it.
- The accuracy of the two-view silhouette carve, which under-reads for unrelated reasons — measured on 2026-08-05 at **9.5×** (196 g bread read as 20.7 g) and **10.2×** (320 g white rice read as 31.4 g), both with the class correct. That is an order of magnitude, not a margin, and it is a separate defect: this feature changes only the depth-derived plane.

**Deliberately no longer excluded.** Segmentation accuracy was excluded in an earlier draft. It cannot be: Req 3 makes the food mask an input to selecting the *geometric reference*, so a mask error changes which plane is used and can change the answer by ~3×. The dependency is stated in Req 3.5 rather than waved away.

## Requirements

### 1. The support plane is the surface the food rests on

**User Story:** As a developer, I want volume integrated from the surface the food actually rests on, so that the carb number is not inflated by the height of the plate.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL define the support plane as the surface on which the food rests, and SHALL integrate food volume above that surface.  
2. <a name="1.2"></a>WHERE LiDAR depth is available AND the food rests on a raised support such as a plate or board, the fitted plane SHALL lie on that support's top surface rather than on the surrounding table.  
3. <a name="1.3"></a>WHERE food extends beyond the fitted support region, the system SHALL measure it against the same fitted plane and SHALL NOT extend or re-fit the plane to cover it.  
4. <a name="1.4"></a>This feature SHALL amend, not merely cite, every document that names the old reference: pipeline Req 4.2, pipeline design §6.2, the pipeline glossary, and `DECISIONS.md` MD-9. A declaration of supersession that leaves the superseded text in place SHALL NOT satisfy this criterion.  
5. <a name="1.5"></a>The definitional change SHALL apply to the two-view + ID-1-card path's support plane (pipeline Req 4.3), which already targets the surface the food rests on; that path's behaviour SHALL be unchanged because it derives no plane from depth.  
6. <a name="1.6"></a>The voxel carve's use of the support plane as a lower carving bound (pipeline Req 4.4) SHALL be evaluated against the corrected plane, and any change in excluded voxels SHALL be stated.  

### 2. How the restricted region is chosen and fitted

**User Story:** As a developer, I want the fitted region defined operationally rather than by intent, so that "the surface the food rests on" is something the system can be tested against rather than asserted to have found.

**Acceptance Criteria:**

1. <a name="2.1"></a>The depth points used for the restricted fit SHALL contain no pixel of the food region mask, preserving the exclusion the existing edge-band scan already performs.  
2. <a name="2.2"></a>The restricted region SHALL be derived from the food region's position in the frame and SHALL be contiguous with it. It SHALL NOT be derived from a fixed frame position — the existing offline implementation seeds at the frame centre on the stated assumption that "the rig centres the plate under the camera", which does not hold for handheld capture where the user centres the food.  
3. <a name="2.3"></a>The restricted fit SHALL be subject to a documented dispersion bar on the contact ring's inner band, and SHALL reject a fit whose inner band straddles two surfaces, so that a half-corrected plane is not recorded as a full success. A plane-residual bar SHALL NOT be used for this purpose: under RANSAC the residual is computed only over inliers already within the inlier band, so it is bounded by construction and can never fire (Decision 16).  
4. <a name="2.4"></a>Candidate sufficiency SHALL be assessed in independent depth samples, not in colour-grid points. Candidates are currently enumerated at 1920×1440 with depth sampled from a 256×192 map, replicating each measurement about 56 times, which inflates every count derived from them.  
5. <a name="2.5"></a>The system SHALL state the minimum food height it can resolve, given that the region is bounded by a depth discontinuity and ARKit's depth map is smoothed over several pixels. Food thinner than that bound SHALL be documented as out of scope for the correction rather than silently under-measured.  

### 3. Rejecting a region that is not the support surface

**User Story:** As a developer, I want the fit rejected when it lands on the wrong surface, so that a wrong plane cannot be recorded as a correct one.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL compute the median signed height, above the candidate plane, of non-food depth samples in a thin ring immediately outside the food region boundary. A plane on the surface the food rests on SHALL read approximately zero; the table plane reads strongly positive; a plane on a vessel rim reads negative.  
2. <a name="3.2"></a>IF that ring measure falls outside a documented band around zero, THEN the system SHALL reject the restricted fit and fall back per Req 4.  
3. <a name="3.3"></a>The system SHALL reject a restricted fit whose plane lies below the plane the edge-band fit produces for the same capture, since the surface the food rests on cannot be further from the camera than the surrounding surface.  
4. <a name="3.4"></a>The system SHALL NOT integrate volume against a support plane that lies above the food region's depth samples by more than the documented band of [3.2](#3.2). This bounds [1.3](#1.3): overhanging food legitimately sits below the plane and SHALL NOT trigger rejection.  
5. <a name="3.5"></a>WHERE the food mask determines which reference is selected, the system SHALL record the mask's food coverage alongside the selected reference, so a reference flip caused by mask instability is attributable after the fact.  
6. <a name="3.6"></a>The system SHALL evaluate ring support in angular sectors as well as in aggregate, and SHALL reject a candidate whose supporting samples are confined to a subset of those sectors. An aggregate support fraction cannot distinguish a ring lying wholly on the surface the food rests on from one that has crossed that surface's edge onto the surrounding surface: a ring 65 % on the table is 100 % table across roughly 235° and 0 % across the remainder, yet scores 0.65 in aggregate, passes every other guard, and reproduces the defect this feature exists to remove while recording a ring median of approximately zero.  
7. <a name="3.7"></a>The sector measure SHALL be derived from measurement against the fixture corpus rather than asserted, and its derivation SHALL be recorded. This applies to the sector count, the per-sector support bar, and the number of failing sectors that constitutes a rejection.  
8. <a name="3.8"></a>The system SHALL resolve the contact ring into radial bands and treat the band nearest the food boundary as authoritative for selection, since the support surface is by definition the one immediately adjacent to the food. An outward rise across bands beyond a documented step SHALL be treated as a raised vessel edge rather than as the support surface (Decision 14).  
9. <a name="3.9"></a>WHERE the visible support region is too small relative to the food region for the support surface to be observed at all, the system SHALL reject the restricted fit and fall back. When food fills a plate's well the well produces no depth samples, so no candidate plane can be fitted to it, and the system SHALL NOT select a raised edge in its place (Decision 14).  

### 4. Fallback, and knowing how often it fires

**User Story:** As a developer, I want a fallback that cannot make today's captures fail, and a measurement of how often it fires, so that the fallback cannot quietly become the normal path.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN the restricted fit is not produced, fails the dispersion bar of [2.3](#2.3), or is rejected under Req 3, THEN the system SHALL complete the estimate using the existing edge-band fit.  
2. <a name="4.2"></a>The set of conditions under which the pipeline refuses to compute SHALL be unchanged from pipeline Req 4.5.  
3. <a name="4.3"></a>WHEN the fallback fires, the support plane used SHALL be identical to the one the edge-band fit produces for the same capture.  
4. <a name="4.4"></a>The system SHALL record which reference produced the plane for every attempt, and SHALL report the fallback rate aggregated across a fixture corpus.  
5. <a name="4.5"></a>A fallback rate above a stated threshold SHALL constitute a defect against this feature rather than a successful outcome, since a change where every capture falls back satisfies [4.1](#4.1)–[4.3](#4.3) while delivering nothing.  
6. <a name="4.6"></a>WHEN the fallback fires, the reported confidence SHALL be no higher than for a restricted fit of equal residual. This is a functional accuracy signal, not a disclaimer, and is therefore permitted under the developer-phase copy rule.  

### 5. One reference for the device and the offline paths

**User Story:** As a developer, I want the device and the offline harness to reference the same surface, so that a calibration constant derived offline is valid when applied on device.

**Acceptance Criteria:**

1. <a name="5.1"></a>Given the same capture inputs, the device and the offline replay SHALL produce support-plane coefficients equal within a documented tolerance, verified on a named fixture.  
2. <a name="5.2"></a>The β_c calibration transfer contract SHALL state the support-plane reference alongside masking, closing the contradiction with `nutrition5k-calibration` Req 3.6, which already requires integration above the plate top offline.  
3. <a name="5.3"></a>The system SHALL apply β_c values only when the calibration artefact records a support-plane reference matching the one in use. An artefact recording no reference SHALL block application rather than permit it — every artefact produced before this feature records none, and those are precisely the ones calibrated on the old basis.  
4. <a name="5.4"></a>WHERE a calibration corpus contains attempts recorded against more than one reference, β_c SHALL be fitted on the subset sharing the reference it will be applied under.  

### 6. Diagnostics

**User Story:** As a developer, I want the evidence that distinguishes a right fit from a wrong one recorded per attempt, so that this class of defect is visible without an offline investigation.

**Acceptance Criteria:**

1. <a name="6.1"></a>For every attempt that derives a support plane from depth, the system SHALL persist the reference used and the ring measure of [3.1](#3.1), queryable from a pulled device database.  
2. <a name="6.2"></a>Replaying capture `1785135663727` under the pre-feature fit SHALL yield a ring measure in the +18…+26 mm range recorded by the diagnosis, and under the corrected fit SHALL yield approximately zero. This makes the diagnostic falsifiable rather than merely recorded.  
3. <a name="6.3"></a>Attempts recorded before this feature SHALL remain distinguishable from attempts recorded after it; the field SHALL be absent rather than defaulted on pre-feature rows.  
4. <a name="6.4"></a>The system SHALL persist the sector evidence of [3.6](#3.6) — at minimum the count of sectors meeting the per-sector support bar — so that a capture whose ring crossed the support's edge is identifiable from the record alone. A ring median near zero SHALL NOT be sufficient evidence that a fit was correct, since the failure mode of [3.6](#3.6) produces exactly that value.  

### 7. Accuracy outcome and preserved invariants

**User Story:** As a developer, I want the correction measured against weighed truth and the prior plane-fit bugfixes held, so that the fix is proven and nothing regresses.

**Acceptance Criteria:**

1. <a name="7.1"></a>Replaying capture `1785135663727` SHALL yield a food volume within 5 % of 235.96 cm³, the value the restricted fit produced during diagnosis, against 682.96 cm³ under the current fit. This is a parity check against a known implementation, not an accuracy claim — that capture has no weighed truth.  
2. <a name="7.2"></a>Replaying capture `1785901032716` (2 slices of bread, weighed at 80 g) SHALL yield a food **volume** within 20 % of 200 cm³, against 714.84 cm³ today. The criterion is stated in volume because mass depends on the class and density this feature does not control, and the same scene classified as both `bread_wholemeal` and `carrot` 30 s apart. The class SHALL be pinned as a test precondition. The 20 % band is the sum of the accepted overhang under-measure (~11 %, Decision 4) and the measured device-to-replay divergence (~5 %), rounded up.  
3. <a name="7.3"></a>Replaying the 208 g weighed rice capture SHALL yield a food volume within the same 20 % band of the volume implied by its weighed mass and recorded density, providing a second truth-anchored case on non-flat food.  
4. <a name="7.4"></a>At least one acceptance case SHALL exercise the fallback path, which is otherwise the least-tested code in the feature.  
5. <a name="7.5"></a>The system SHALL continue to satisfy the three prior plane-fit bugfixes: no allocation failure at 1920×1440, no degenerate fit on a clean capture, and no regression in matte-table confidence handling.  
6. <a name="7.6"></a>The added region derivation, second fit and ring measure SHALL stay within a stated added-latency and peak-memory budget at 1920×1440, given that this path has already produced an out-of-memory failure at that resolution.  
7. <a name="7.7"></a>Identical capture bytes SHALL produce an identical support plane and an identical selected reference across runs.  
8. <a name="7.8"></a>The feature SHALL be verified on device against a weighed flat-food capture, not only in offline replay.  
9. <a name="7.9"></a>Meals already stored SHALL NOT be re-estimated, rewritten, or migrated.  
10. <a name="7.10"></a>At least one acceptance case SHALL be a weighed **single-view LiDAR** capture on a lipped or rimmed plate, exercising [3.6](#3.6) and [3.7](#3.7). No such capture exists: the 2026-08-05 session produced a lipped-plate capture of heaped rice (`1785921526968`, 245 g weighed, read as 841 g across `carrot` + `mixed_vegetables`) but on the two-view path, where no depth-derived plane is selected, so it cannot exercise either criterion.  
11. <a name="7.11"></a>A weighed capture SHALL count as evidence for this feature only where it completed on the single-view LiDAR path. In the 2026-08-05 session all 22 single-view attempts refused and all three successes were two-view, so four weighed truths yielded no usable evidence.  

## Test artefacts

Reqs 6.2, 7.1, 7.2 and 7.3 name capture bundles that live on the device under `Documents/captures/`, not in the repository — `1785135663727-success.fixture` (195 MB) and `1785901032716-success.fixture` (204 MB), both pulled with `devicectl copy from` per `docs/agent-notes/device-build-and-test.md`. Design MUST state where these are kept for repeatable runs and what happens when they are absent, since an acceptance criterion nobody can execute is not one.
