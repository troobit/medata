# Two-view geometry audit (night of 2026-09-24)

**Verified 2026-09-25** (two-view-trust Decision 4): on bundle `1790310086654`
the stored transform maps the nadir card's corners onto the oblique card face
within 10 px; every alternative convention misses by 20–700 px. §1–2 below
describe the state before the fix. `HarnessCLI cards --oblique` replays the
detector on the oblique view; Vision's oblique quad includes the card's side
and shadow (15–20 px outside the face at 26°), so it is not the yardstick.

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

**Card detection replays off-device since 2026-09-25.** `VisionCardDetector`
moved from the App target into the `CardDetectionVision` SwiftPM target
(Vision exists on macOS 14 too) and `HarnessCLI cards <bundle.fixture>…`
runs it on a stored nadir frame, solves `CardPoseSolver` on every quad, and
prints the card-plane scale beside the LiDAR scale at the food plane. The
replay is faithful: a BGRA8 decode of the stored PNG reproduces the quads
Vision returns on the device path to the pixel. What it measured on the two
2026-08-11 bundles with a real yellow ID-1 card on the board:

- **The device's single pick is never the card.** With
  `maximumObservations = 1` (production) Vision returned the bread slice on
  `1786439234576` (residual 85 px, edges 188/311 px — the short edge first, so
  the solver was also fed the sides swapped) and a phantom rectangle on the
  plate rim on `1786439300420` (residual 145 px). The card was plainly visible
  in both frames.
- **`--max-observations 8` finds the card on one bundle only.** On
  `1786439300420` it is candidate 2 of 3: residual 2.66 px, t_z −441 mm,
  0.3206 mm/px at the card against 0.3518 mm/px at the LiDAR food plane
  (|d| 479 mm / f_mean) — a 9 % symmetric disagreement. On `1786439234576`
  the card is not a candidate at all, even with the aspect band widened to
  0.3–1.0 and `minimumSize` 0.02: yellow card on pale wood, rounded corners,
  rotated ~35°. So the production policy "first observation wins" loses the
  card whenever a plate or food rectangle outranks it, and Vision misses
  low-contrast cards outright.
- **The argmax labels the card as cheese, never background.** The card quad
  on `1786439300420` is 50 % `cheese(13)` / 50 % `background(33)`; the card
  region on `1786439234576` is 80 % background / 20 % cheese. That is the
  Req 4.6 exclusion's motivation (the card must not be integrated as food);
  it also means the segmenter does not see the card as background, so a
  "card pixels = background" check would not catch it.
- On the three 2026-09-24 no-card bundles the single pick was the bread roll
  (`1790232615202`, `1790232681422`: 76 % / 64 % `bread_wholemeal` inside the
  quad) and a tilted rectangle spanning the plate and the table
  (`1790223818017`, 99 % background) — the "card+lidar" false positives the
  corpus rows already showed, with scales 0.14–0.09 mm/px against LiDAR
  0.28–0.24 (66–94 % disagreement).

## 4. What the offline replay can and cannot do

- `HarnessCLI volumes --fixtures-dir … --checkpoint-sha256 …` prints the
  per-class volumes, plane and growth a bundle replays to (added tonight).
  Two-view replay now fits the LiDAR plane when the bundle has depth.
- `HarnessCLI cards <bundle.fixture>… [--max-observations N]` prints, per
  ranked Vision rectangle, the corners, edge lengths, P4P residual, t_z and
  card-plane scale beside the LiDAR food-plane scale (§3). Positional paths,
  no checkpoint gate: it reads the nadir PNG through
  `FixtureRunner.nadirFrame`, and uses the stored argmax only for the plane
  fit's food mask. ~15 s per 400 MB bundle, most of it protobuf decode.
- The carve cannot be demonstrated on real bundles until §2 is fixed; the
  demo variants prove only that silhouettes are not the blocker.
- Non-LiDAR volume replay (depth cleared, card branch) does not exist:
  `FixtureRunner` requires depth. Card *detection* replays (above); the
  card-only plane fit and the carve it would feed do not.

## 5. Object reconciliation before volume (2026-09-25, two-view-trust Decisions 5–6)

`ObjectReconciler` (Volume, one file) runs on both paths before volume: in
`Pipeline` at the top of the single-view branch (before growth) and after
the oblique is segmented on two-view, and in the matching places of
`FixtureRunner`. Per view it takes the carvable mask (`isCarvableClass`),
dilates it 3 px, and labels 4-connected components; the view is ONE object
when the largest component holds ≥ 90 % of the carvable pixels. A single
object takes one class — the user's when given, else the named class with
the most pixels (the nadir's over the oblique's on two-view), else
`unknown_food` — in the argmax and in the probability tensor (the other
carvable channels' mass is added to the chosen channel and zeroed). A view
that is not one object is left alone. The row records
`twoViewReconciliation {nadirClasses, obliqueClasses?, nadirSingleObject,
obliqueSingleObject?, chosenClass, applied}` (oblique fields nil on
single-view) and the Shutter log prints `event=object.reconcile`. The
bundle keeps the raw segmenter outputs. `FixtureRunner.run(reconciliation:
false)` replays the raw labels.

Why the class-count gate of Decision 5 was replaced: the segmenter splits
one roll into bread_white + bread_wholemeal + unknown_food across one blob
(`1790315734391` oblique: 31 k / 20 k / 22 k px in a single component).

**The ID-1 card was the second object in every 2026-09-25 afternoon
two-view capture.** On `1790315734391` and `1790315814452` each view had
exactly two carvable components: the roll and a ~210 × 310 px `unknown_food`
blob at the card's position (`HarnessCLI cards` picks the card there:
residual 3.35 / 1.13 px, disagreement 4 %). The largest component held
74 % / 64 % and 74 % / 90 % of the carvable pixels (nadir / oblique),
unchanged up to a 48 px dilation, so the gate correctly said "two objects".
The nadir quad was already cleared on device (Req 4.6, nadir half); the
oblique half (task 8, 2026-09-25) now clears the card there too:
`CardPose.cornersCameraMm` (the ISO 7810 model corners through R·X + t, mm,
§6.0 nadir frame) go through `t1to2` and the oblique intrinsics in
`PipelineBridges.projectToOblique`, and `excluding(quad:)` clears the
result; the card block records `obliqueClearedPixels` and the Shutter log
prints `event=card view=oblique`. `FixtureRunner` now runs the same card
pick (`pickCard`: Vision on the stored nadir PNG, `CardPoseSolver.pick`
with the LiDAR scale at the first plane) and the same nadir/oblique
clearing on both replay paths; `run(cardExclusion: false)` replays without
it. With it, each bundle is one carved row (β = 1): `1790315734391`
bread_white 920 cm³ (was 90 + 63 + 1049), `1790315814452` bread_wholemeal
930 cm³ (was 41 + 741 + 264), `1790310086654` bread_wholemeal 851 cm³ (was
315 + 402 + 81). Single-view `1790315900185`: bread_wholemeal 289 +
unknown_food 121 → bread_wholemeal 410 cm³ (growth leak still included).

The carved numbers stay 2–3× the roll (~12 × 7 × 4 cm) because the nadir
silhouette is wider than the roll and an oblique ~26° from vertical bounds
height only near its far edge; the grid's 120 mm `verticalExtentMm` is the
other cap. Tighter silhouettes (Req 3) and a wider baseline are the levers.

## 4. What the 2–3× over-read actually was (2026-09-25 evening)

Two measured causes, both now fixed in `MedataCore/Sources/Volume/`.

**The grid's vertical extent was setting the answer.** Two silhouette cones
at the tilts the aim guide allows never close over a low food: a voxel at
height h only leaves the oblique silhouette once h·tan(θ) exceeds the
object's extent along the tilt direction — 139 mm / tan(22.2°) ≈ 340 mm for
the roll, far above any grid. Inside the food's true height the carve is
accurate (a synthetic control with exact silhouettes, real intrinsics and
the real baseline carves ~375 cm³ against a voxelised truth of 337);
everything above is un-carved hull, and the top layer at 118.5 mm still
kept 42 % of the base layer's voxels. Cumulative volume by cap on
`1790318627741`: 24 mm → 238, 40 → 379, 48 → 460, 62 → 587, 72 → 656, 86 →
756, 96 → 810, 120 → 927 cm³. So `VoxelGridSizer.verticalExtentMm` was not
a safety cap — it was the estimate. When the nadir frame carries depth the
grid is now sized to the food: `VoxelGridSizer.measuredFoodHeightMm` takes
the 98th percentile of the per-pixel height above the support plane over
the nadir food mask (same `heightAboveSupportPlaneMm` the single-view
height field uses), adds a 5 mm margin, and clamps to [30, 120] mm. The
percentile, not the maximum, so one bad return cannot set the grid; 5 mm
and not more because the percentile measured ABOVE the food on all three
bundles (47.3, 50.4, 36.0 mm on rolls of ~40 mm — it is taken over the same
smoothed depth the plane was fitted to), so the margin covers only
quantisation and the plane residual. Z is rounded up to a whole voxel and
no longer to a threadgroup: 8 voxels is 24 mm at the default edge, most of
a 40 mm food. The kernel's `gid.z >= dims_z` guard makes a ragged dims_z
safe. With no depth the constant AND its old rounding stand, byte for byte,
so the non-LiDAR two-view path is unchanged.

**The carve's silhouette was softer than every other consumer's.** The test
was `(1 − q[bg]) ≥ 0.5` on the RAW tensor, while `MaskMatcher`,
`VoxelGridSizer`, the review overlay and persistence all read the
REGULARISED argmax; `ObjectReconciler.relabel` then concentrates every
carvable channel into one, so a pixel with no winning class but half its
mass off background passed. On `1790318627741`: nadir 138,671 px soft
against 108,531 px of label-food (118.3 vs 92.6 cm², +28 %), oblique 77,932
vs 60,949 — against a roll footprint of ~84 cm². `VoxelCarveView` now
carries the regularised `argmax` and a pixel is in the silhouette only if
its label is carvable (the same `isCarvableClass` MaskMatcher uses); the
tensor is still what resolves the per-voxel class. The single-view
extrusion fallback uses the label map the same way. A nil `argmax` keeps
the old soft test for synthetic tests. `HeightFieldEstimator` is NOT
touched — the single-view path reads the roll correctly today and is the
reference the two-view number is measured against.

Replay of the three bundles (β = 1, totals in cm³):

| bundle | before | height only | hard silhouette only | both |
|---|---|---|---|---|
| `1790318627741` | 926.9 | 512.8 | 709.8 | **397.1** |
| `1790315814452` | 929.1 | 598.8 | 781.6 | **509.8** |
| `1790310086654` | 850.3 | 442.5 | 678.9 | **351.4** |

Measured heights / grid extents: 47.3 → 54 mm, 50.4 → 57 mm, 36.0 → 42 mm.

**Still over.** Single-view LiDAR of the same roll minutes apart reads
267–272 cm³, and the target band is 267–302; the carve lands 1.3–1.9× above
it. Capping alone cannot reach the band — the cap sweep shows ~379 cm³ at
the roll's true 40 mm even with the old silhouette, and ~357 at 48 mm with
the hard one. What remains is the footprint: the nadir mask is still wider
than the roll (92.6 cm² of label-food against ~84 cm² real) and the
perspective cone widens the hull with height. The row now records
`voxelGrid {measuredFoodHeightMm, verticalExtentMm, dimsZ, edgeMm}` and the
Shutter log prints `event=grid.height`, so the bound is auditable per
attempt.

**A phone without LiDAR still has no height bound at all.** The measured
extent needs nadir depth; without it the 120 mm constant stands, and
nothing in the two-view geometry closes the hull from above at any tilt the
aim guide allows. That path therefore keeps the full over-read this section
describes. The only bounds available to it are a wider baseline (a tilt
where the cones actually close), the ID-1 card's own plane, or an explicit
prior height — none of them built.

## 6. The no-depth path is now flagged, and its refusal says what is missing (2026-09-25 night)

Two changes close out two-view-trust tasks 13 and 18 on the finding above.
Every two-view attempt whose nadir frame carries no depth is now stamped
`degradedReason = unbounded_carve_height` on its outcome row, by
`PipelineDiagnostics.recordDegraded` at the very top of `runEstimation` —
before any stage can refuse, so a refused row carries the same fact about the
capture that a successful one would. The review screen does not read the
outcome row, so it re-derives the same condition from the persisted meal
(`MealRecord.carveHeightWasUnbounded`: `capturePath == .twoViewSfS && !scale.lidarScaleAvailable`,
the LiDAR scale being the record's witness for nadir depth), and renders it
through the accessory-signal line MealReviewView already uses for the
calibration and drink flags. The copy says the height was not measured and the
volume is therefore not a measurement — deliberately not "a lower bound",
which would read as "the true number is higher" when the measured direction of
the error is 1.6-2.5x too high.

Separately, `SupportPlaneError.noLowerSilhouetteEdges` no longer maps to
`EstimationFailure.noScaleAvailable`. Since 9f02ff2 the card-only branch of
`LiDARSupportPlaneFitter` refuses with that case whenever there is no depth,
and on such a capture the card usually resolves scale perfectly well — it is
the plane that is missing, at stage D, before scale resolution at stage E ever
runs. The new case is `noSupportPlaneWithoutDepth` ("no plane" / "No depth to
fit the table surface" in the capture overlay). The practical consequence: with
the `Capture without depth` developer switch on, a two-view capture refuses
there and never reaches the carve, so the degraded flag is today exercised by
the outcome row and by tests rather than by a number on screen. It becomes
visible in review the moment a card-plane or other no-depth support plane
exists.
