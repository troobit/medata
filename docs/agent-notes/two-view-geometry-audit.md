# Two-view geometry audit (night of 2026-09-24)

What was found while preparing the "user identifies the food in both photos"
options (`specs/estimation/two-view-trust/`). Read this before touching the
two-view path, `MaskMatcher`, `VoxelCarveEstimator`, or the card path.

## 1. No two-view number in the corpus has ever come from the carve

Every recorded two-view volume is the §6.6 single-view-only fallback: the
class's silhouette in ONE view extruded to the support plane at a fixed 30 mm
prior height (`VoxelCarveEstimator.singleViewExtrudedVolumeMm3`). Evidence:

- The sesame-roll two-view bundle `1790232615202-success` (2026-09-24 16:50)
  labels the roll `bread_wholemeal` in the nadir and `unknown_food` in the
  oblique. `MaskMatcher.match` matches by label only, so nothing is matched;
  bread is extruded from the nadir (383 cm³) and unknown from the oblique
  (317 cm³, the "phantom" row fixed in bugfix two-view-unknown-carve — it was
  the roll, under another label).
- Relabelling the oblique unknown to bread (so the classes match) and
  replaying (`HarnessCLI volumes`) gives `noFoodVolumeRecovered`: the carve
  finds no voxel inside both silhouettes. Same with user-quality silhouettes
  (both masks dilated 12 px). The single-view-only fallback is the only
  path that ever produced a number.
- `field-truth-sessions.md` 2026-08-16 recorded two-view under-reading
  9.5–10.2× against weighed truth. That is the 30 mm extrusion, not a carve.

## 2. The stored inter-view transform does not match the photos

`PbMealFixture.t_1_to_2` = `(worldFromCamera₂)⁻¹ · worldFromCamera₁` from
ARKit poses (`PipelineBridges.transform1To2`). Measured:

| bundle | rotation angle | translation (as stored) |
|---|---|---|
| `1790232615202` (16:50, tilt 3° → 28.5°) | 73°, axis mostly camera y/z | (−0.042, −0.112, 0.077) |
| `1790223844719` (14:24) | 163° | (−0.034, 0.004, −0.016) |

Root cause, found after the table above was written: **`PipelineBridges.rigidInverse`
never transposed the rotation.** It read R^T(i, j) as `columns[j][i]`, which is R
itself, and returned [R | −R·t]. `transform1To2 = rigidInverse(W₂) · W₁` therefore
composed R₂·R₁ instead of R₂ᵀ·R₁. Two cameras that both look down have R₁ ≈ R₂ ≈
R_down, so the "relative" rotation came out near R_down², a ~180° turn (163° on the
morning bundle; 73° on the afternoon one, where the phone was also rotated in
hand) in place of the real ~25°. Fixed 2026-09-25, pinned by
`TwoViewTransformTests.rigidInverseInverts`. The two further problems below were
real as well and are fixed in the same change:

1. **Units.** ARKit poses are in metres; every point in the carve is in mm
   (`applyMat4(transform1To2, p1)` on mm voxel centres). Nothing converts.
   The oblique camera is therefore placed ~0.1 mm from the nadir camera.
2. **Frame.** ARKit's camera frame is +y up; the carve's §6.0 frame is +y down
   (the image row direction, as `projectCamera1` and `CameraGravity` assume).
   The pose transform was applied without conjugation. `transform1To2` now
   returns F·(W₂⁻¹·W₁)·F with F = diag(1, −1, 1, 1), translation × 1000.
3. **Grid.** `VoxelGridSizer` built its vertical axis as `−gravity`, reading
   `RawFrame.gravity` as pointing down; since bugfix
   capture-no-flat-surface-gravity-frame that field carries WORLD-UP (it is
   what the plane fitter aligns its normal to). On every real capture the
   whole grid sat under the support plane and the carve discarded it —
   `VoxelCarvePlaneExclusionTests` had pinned "23,040 of 23,040 voxels
   excluded under the convention Pipeline passes" as the expected state.
   The axis is now `+gravity`; the test pins zero excluded.
4. **Session reset between shots.** Going inactive while the nadir frame is
   stashed stopped the session; on return it re-ran with `.resetTracking`,
   giving the oblique a new world origin. `RawFrame.sessionGeneration` now
   stamps every frame, the pipeline refuses a pair from different
   generations (`arWorldTrackingLost`), and the capture model drops the
   stashed nadir on suspend. Both poses and the mm transform are recorded on
   the outcome row (`twoViewPoses`).

The numpy brute force over axis conventions could not have found (1)–(4)
because the stored transform was already the product of the wrong
composition; old bundles cannot be re-carved (their `worldFromCamera` poses
were not stored). Tomorrow's capture is the first that can.

The numpy replication is in the session scratchpad (`night/`); the fixture
variants (`fx-A-reconciled`, `fx-B-user-silhouettes`, `fx-C-nadir-only-user`)
are the inputs for the morning demo.

**Verification protocol (device, ~15 min, tethered), still required — the
four fixes are unit-tested, not device-tested:** at each shutter log
`camera.transform` (all 16 floats), `camera.eulerAngles`, `frame.timestamp`,
`trackingState`, and the session run count; photograph a printed checkerboard
or the ID-1 card in both views. Offline: the card's four corners give an
independent relative pose (P4P in each view); compare with the stored
transform. If they disagree by the 70° seen here, the pose plumbing is wrong;
if they agree, the carve's convention is wrong.

## 3. The card path has never run

Findings from the card-path research (see the spec's decision log for the
citations): `scaleSource = "card"` has never been recorded in any corpus DB;
every `"card+lidar"` row is Vision's rectangle detector firing on a plate rim
or placemat (σ_scale disagreements of 17–66 % on the 2026-09-24 rows, no card
in the scene); a false card can only raise σ_scale, never lower it;
`CardOnlyPlaneFitter` is fed the card's own bottom corners plus a hard-coded
20 mm "food centroid" instead of the food's lower silhouette edges (Req 4.3);
the "include a card" reminder (iphone-experience Req 6.1) is marked done and
not built; `includeCardThisCapture` has no readers; `noLidarConfidence` /
`noCardConfidence` (pipeline Req 7.3/7.4) are unimplemented. The path that
non-LiDAR phones must use has zero production observations and no tracker
entry. Backlog 25–27 now carry it.

## 4. What the offline replay can and cannot do

- `HarnessCLI volumes --fixtures-dir … --checkpoint-sha256 …` prints the
  per-class volumes, plane and growth a bundle replays to (added tonight).
  Two-view replay now fits the LiDAR plane when the bundle has depth.
- The carve cannot be demonstrated on real bundles until §2 is fixed; the
  demo variants prove only that silhouettes are not the blocker.
- Non-LiDAR replay (depth cleared, card branch) does not exist:
  `FixtureRunner` requires depth.
