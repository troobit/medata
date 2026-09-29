# Requirements scratch notes — support-plane-reference

**Status: SCRATCH. Not requirements.** These are working notes captured 2026-07-27
when the session ran low on context mid-interview. `requirements.md` has **not**
been written. A fresh session should resume Phase 2 (`/starwave:requirements`) from
here — the three open questions in §5 are unanswered and MUST be put to the user,
not guessed.

Domain: `estimation`. Folder name approved by the user (over `plate-top-support-plane`
and `flat-food-volume-overread`) because it stays accurate whichever way the bowl
question is decided. Full-spec workflow approved after scope assessment.

---

## 1. The defect

The LiDAR support plane fits the **table**, not the surface the food rests on —
measured **26.1 mm too low**.

`HeightFieldEstimator.integrate` computes `height = max(0, abs(pSup.z) - abs(pTop.z))`
per pixel, so the support plane is the reference for the *entire* volume. A plane
26 mm low adds 26 mm to **every** food pixel. Bread is ~11 mm thick, so a constant
offset becomes a ~2.9× relative error.

`LiDARPlaneFitter.collectCandidatePoints` (`.bandsAroundFoodRegion`, the device
default) samples non-food pixels in four bands, each as thick as the food bbox
perpendicular to it — 610 px sideways, 930 px vertically in the observed capture.
Those bands reach past the plate onto the worktop and off its edge to the floor
~880 mm below. RANSAC maximises inlier count, so the worktop wins on area:
**510,499 of 1,074,005** candidates within ±5 mm of the winner, versus **~64,000**
on the plate.

### Measurements

Capture bundle `1785135663727-success.fixture`, replayed offline against model
`coreml_ab812dc3aa9d`.

| Quantity | Value |
|---|---|
| Device volume (`estimation_outcomes`) | 682.31 cm³ |
| Offline replay, shipped band scan | **682.96 cm³** (reproduces device to 0.7 cm³) |
| Offline replay, plane fitted to plate surface | **235.96 cm³** |
| Shipped plane `distanceMm` | −369.84 (residual 1.95 mm) |
| Plate-surface plane `distanceMm` | −343.72 (residual 2.27 mm) |
| **Plane error** | **26.1 mm too low** |
| Footprint / mean height | 216.1 cm² / 32.3 mm (should be ~10.9 mm) |
| Density `bread_wholemeal` | 0.400 g/cm³ (MEASURED, correct) |
| β applied | 1.0 |
| Mass → readout | 272.92 g → 94.4 g; **"7.5 slices" → ~2.5** (36.0 g/slice, step 0.5) |

Median signed-height map: worktop ~0 mm (the fitted plane), a ring of plate at
**+18…+26 mm** hugging the food, food at +24…+40 mm, floor at −880 mm.

**Ruled out with evidence:** density, β (a factor of one), segmentation (two clean
slice blobs, class correct), the servings readout (arithmetic exact), any
minimum-height floor (`integrate` imposes none).

**Not bread-specific.** Same signature on other captures: rice 603 cm³/440 g
(independently confirmed as a **2.1× over-read** against 208 g weighed truth), apple
943 cm³/519 g. Consistent with a constant height offset.

**Independently reproduced with weighed truth, 2026-08-05.** A fresh capture
(`1785901032716`, build `6db23e7-20260805-115608`) of 2 slices multigrain bread weighed at
**80 g / ~34 g carbs** returned 714.84 cm³ → 285.94 g → 108.66 g carbs: a **3.57× mass** and
**3.20× carbs** over-read, with the class correct (`bread_wholemeal`), density correct
(0.400 MEASURED) and β = 1. Solving `(h + 26.1)/h = 3.57` gives an implied true slice thickness
of **10.1 mm** against the 10.9 mm derived above from a different capture — agreement to about a
millimetre, from an unrelated scene with independent truth. `planeResidualMm` 1.97 with
1,286,181/1,478,354 inliers: the fit is confident and wrong, exactly as the band-scan analysis
predicts. This removes any remaining doubt that the 26.1 mm figure is a property of the fit
rather than of that one capture.

---

## 2. The fix already exists — offline only

`HarnessCore/FixtureRunner.swift:139-196` already implements this, carrying the
identical diagnosis in its own comments: *"the table is the largest planar region —
an unrestricted RANSAC lands on it, violating Req 3.6 (integrate above the plate
top). The fix: a flood fill on 4-neighbour depth continuity (|Δz| ≤ documented
threshold) seeded at the frame centre stops at the plate-rim discontinuity; the
plane is then fitted inside that region only."*

Existing API:

- `plateRegionMask(depth:continuityThresholdMm:) -> BinaryMask?` — flood fill,
  `plateDepthContinuityThresholdMm = 5.0`, centre seed with
  `plateSeedSearchRadiusPx = 8` for specular nulls, sentinel/depth-0 pixels are
  barriers, returns nil when no valid seed exists.
- `fitPlateRegionPlane(depth:intrinsics:gravity:fixtureID:residualMaxMm:) throws -> SupportPlane`
  — fits restricted to the flood-filled region; resamples the mask to the colour
  grid by nearest neighbour when grids differ.
- Tested by `MedataCore/Tests/HarnessCLITests/PlateRegionPlaneTests.swift`
  (table 600 mm, plate top 580 mm, 20 mm rim).

### Hard architectural constraint

`HarnessCore` is `#if HARNESS_ENABLED`. CLAUDE.md: that flag gates code out of the
shipping binary and **"never make shipped code depend on it."** So the shared
implementation must be **promoted into** a production module
(`MedataCore/Sources/SupportPlane`), with HarnessCore depending on it — not a call
in the other direction. Req 5.1 / Decision 7 call same-path calibration "the
validity linchpin", so **one** function must serve both paths.

---

## 3. The calibration contradiction (highest reach)

`specs/estimation/nutrition5k-calibration` **Req 3.6** requires the *opposite*
offline — integrate above the plate top, not the surrounding table. So β_c is
**calibrated on one basis and applied on the other**.

Decision 7 / Req 5.1 enumerate only *masking* in the transfer contract, never the
plane reference. Left unaddressed, the deferred β_c calibration will absorb this
26 mm geometric offset as if it were a bulk-density property of food — baking the
error into the calibration constants where it becomes very hard to detect.
Requirements must close this.

---

## 4. Why a spec and not a patch

The table is the **documented, deliberately tuned** reference:

- pipeline **Req 4.2** — fit "at and around the lower edge of the food bounding region"
- `specs/DECISIONS.md` **MD-9** — calls edge-band sampling "the table-plane prior"
- `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture` **Decision 1** —
  tuned the mask so the band "sits on table pixels, not plate rim", *explicitly
  rejecting* a smaller fraction because it would overlap the plate

The code faithfully implements the spec. **The spec names the wrong surface.**

---

## 5. THREE OPEN QUESTIONS — unanswered, must go to the user

1. **Bowls.** The rim sits *above* the food surface. The candidate measured during
   diagnosis was an **annulus** hugging the food mask, which on a bowl would fit the
   rim, clamp heights to zero, and collapse volume — *worse than today*. The proven
   in-repo technique is a **flood fill**, which on a bowl may instead climb the inner
   wall to the rim. **The two techniques diverge precisely on the bowl case**, and a
   cereal bowl is an MVP capture target (myfoodrepo-bridge task 7).
2. **Overhanging food.** Present in the observed capture — the lower slice overhangs
   onto the worktop, so a plate plane **under**-measures it. True volume is bracketed
   at **236–262 cm³** depending on annulus radius; this is why the corrected figure
   is ~2.6 rather than exactly 2 slices. Decide whether overhang is accepted,
   detected, or compensated.
3. **Starvation.** `lidar-plane-fit-degenerate-on-clean-capture` **Decision 2**
   widened the bands precisely to avoid candidate starvation. Any narrowing needs a
   fallback that **cannot fail a previously succeeding fit**. Decide the fallback
   ladder and its ordering.

---

## 6. Scope the requirements must cover

- Redefine the support plane as "the surface the food rests on" across pipeline
  Req 4.2, design §6.2, the `requirements.md:30` glossary, and MD-9.
- One shared plane-fit function serving both device and offline paths, promoted into
  a production module (§2 constraint); reconcile nutrition5k-calibration Req 3.6 /
  Decision 15.
- Add the plane reference to Decision 7 / Req 5.1's transfer contract and Req 9.3's
  caveats.
- Explicit bowl and overhang behaviour (per §5).
- **A diagnostic recording the chosen plane's height above the next strong consensus
  plane.** No existing diagnostic could catch this defect — residual (1.95 mm),
  inlier count and coverage were **all healthy on the wrong plane**. Consider
  persistence into `estimation_outcomes`.
- Preserve the invariants of all three prior plane-fit bugfixes:
  `lidar-plane-fit-degenerate-on-clean-capture`,
  `lidar-plane-fit-matte-table-confidence`,
  `lidar-plane-fit-oom-on-device-1920x1440`.
- A flat-food accuracy fixture.
- The non-LiDAR two-view + ID-1-card path is **retained** (segmenter-foundation
  Decision 26) — requirements must state how the support-plane reference behaves on
  that path, which has **no depth map**.

---

## 7. Scope assessment (approved)

| Metric | Finding |
|---|---|
| Production LOC | ~300–450 (promotion ~110, device wiring ~50–100, bowl/overhang ~50–150, diagnostic ~80–120) |
| Files | 8+ — `LiDARPlaneFitter.swift`, `SupportPlaneFitter.swift`, `Pipeline.swift`, `VolumeTypes.swift`, `HarnessCore/FixtureRunner.swift`, a new shared module file, diagnostic persistence, tests |
| Subsystems | SupportPlane, Volume, Pipeline, HarnessCore, Persistence |
| Breaking | Yes — reverses MD-9, pipeline Req 4.2, and lidar-plane-fit-degenerate Decision 1 |
| Cross-cutting | Accuracy, reliability; changes the β_c calibration transfer contract |

Module sizes for reference: `LiDARPlaneFitter.swift` 468 lines,
`SupportPlaneFitter.swift` 158, `HeightFieldEstimator.swift` 230,
`VoxelCarveEstimator.swift` 350.

---

## 8. Existing artefacts and loose ends

- **Commit `99ba8c0`** — `MedataCore/Tests/VolumeTests/PlateTopSupportPlaneTests.swift`:
  synthetic 10 mm slab on a plate 20 mm above a table, table dominating bands ~9:1.
  Verified **red for the right reason** (plane 400.008 mm instead of 380; implied
  thickness 30.01 mm instead of 10 — a 3.00× synthetic over-read against the field's
  2.89×), then `XCTSkip`ped because it encodes **one** candidate resolution the spec
  must confirm. Requirements should say whether that encoded resolution is chosen.
- **The bugfix diagnosis is unfiled.** Suggested home
  `specs/bugfixes/flat-food-volume-overread-table-plane/report.md`. Full content is
  in the 2026-07-27 session transcript; §1 here reproduces the measurements.
- **`DiagProbe/`** at the repo root is an untracked throwaway probe from the
  diagnosis (its own header says "deleted after the investigation"). No
  `Package.swift` references it. Safe to delete.
- **`specs/estimation/segmenter-foundation/tasks.md` is modified, uncommitted** —
  task 14 unticked (its conversion run never happened; no
  `tools/segmenter/build/spike_segformer.json` exists). This unblocks tasks 20/21/22,
  which all declared it as their blocker.
- **Commit `d660392` is unmerged** on branch `worktree-agent-a7f27e163f1d67a80` — 6
  spec docs reconciling the iOS 26.5 / iPhone 16 Pro floor and non-LiDAR retention.
  Needs a merge decision.
- `specs/OVERVIEW.md` needs regenerating via `/specs-overview` once spec docs land.

---

## 9. Decisions taken this session — promote to `decision_log.md`

Neither is recorded as a proper Enhanced Nygard ADR yet; both should be, per
`/Users/r/repos/agentic-coding/claude/rules/references/decision-log-format.md`
(needs ≥2 alternatives with rejection reasons, and both positive and negative
consequences).

1. **Folder name `support-plane-reference`.** Rejected `plate-top-support-plane`
   (pre-commits to a plate being the reference, which the bowl question may
   complicate — a bowl's food rests on the bowl interior) and
   `flat-food-volume-overread` (symptom-named; understates scope, since rice
   over-read 2.1× and apple is affected too).
2. **Full-spec workflow over smolspec.** Every full-spec criterion is tripped: >80
   LOC, >3 files, multiple subsystems, breaking changes to documented decisions,
   cross-cutting accuracy/calibration concerns, and three genuinely ambiguous design
   questions.

---

## 10. Why this is the priority

Top MVP accuracy blocker. A 2–3.75× volume error dominates the carb number and
cannot be repaid by segmenter IoU work (currently 0.3927 against a 0.48 gate).
Per-meal carb MAE has **never** been measured end-to-end, so this defect is
uncharacterised in aggregate — the only weighed truth is two captures, both far
outside the ≤~13 g SNAQ target.
