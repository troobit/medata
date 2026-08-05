# Prerequisites for Support Plane Reference

These require human action or hardware access and cannot be completed by a coding agent.
Each names the task it blocks, so a blocked task is traceable to the thing that unblocks it.

## Done

- [x] **Pull the diagnosed and weighed-bread capture bundles from the device.** Done 2026-08-05.
  Both live in `tmp/device_captures/` (gitignored), pulled with:

  ```bash
  xcrun devicectl device copy from --device 6AD781BA-89FF-5A82-A2A1-B5EC9469F465 \
    --domain-type appDataContainer --domain-identifier rtob.MeData \
    --source Documents/captures/<stem>.fixture \
    --destination tmp/device_captures/<stem>.fixture
  ```

  | Stem | Grades | Weighed truth |
  |---|---|---|
  | `1785135663727-success` | Reqs 6.2, 7.1 | none — parity check only |
  | `1785901032716-success` | Req 7.2 | 80 g bread, 34 g carbs |

  Both stamp checkpoint `ab812dc3aa9d`, so replay is
  `make harness-accuracy FIXTURES=tmp/device_captures SHA=ab812dc3aa9d`. Both load and estimate
  (98.9 g and 106.2 g predicted carbs). `scoredCount` is 0 because device bundles record ground
  truth as zero — expected, and why the weighed masses above are carried here in the spec rather
  than read from the bundle. Unblocks tasks 22 and 26.

## Answerable without any new capture

Design re-validation (Decisions 15–18) found that most of the open numbers do not need a
capture session. Do these first — they are cheaper and two of them can invalidate a guard
before it is written.

- [x] **Does `foodAboveFractionMax = 0.05` reject this feature's own reference capture?**
  **Answered — yes, it does, and no capture query was needed.** Decision 4 already brackets the
  weighed bread capture at 236–262 cm³, an ~11 % spread attributable entirely to the overhanging
  slice, so ~11 % of food samples sit below the plate plane against a 5 % bar. The capture would
  fall back and fail Req 7.2. The guard is replaced by a millimetre-denominated upper-envelope
  test (Decision 22); the fraction is gone.

- [ ] **Is `ringInnerMm = 8` inside the depth smear at real capture distance?** The smear is a
  fixed count of depth *pixels* (~4), so its size in millimetres scales with range — about
  6 mm at 300 mm but about 10 mm at 500 mm. Read the median food depth off both pulled bundles
  and state the capture-distance envelope. If 8 mm sits inside the smear at ordinary handheld
  range, the radius has to become `max(ringInnerMm, kSmearPx × mmPerDepthPixel)`. This also
  bears on Decision 14, which rejected shrinking `ringInnerMm` on the grounds it was "already at
  the ~7 mm depth smear floor" — true at one distance only.

- [ ] **Measure your own plates with a ruler.** Rim height above the well, and well diameter,
  for the plates you actually eat off. The design's rimmed-plate exposure table uses assumed
  "ordinary dinnerware" figures of 12/18/28 mm. For a developer-phase tool the population that
  matters is one cupboard, so this replaces an assumption with a measurement in minutes. It also
  sets whether `bandStepMaxMm = 6` sits safely below your smallest real rim step.

- [ ] **Decide which corpus Req 4.5's fallback rate is measured on.** After task 17 regenerates,
  ~3,500 N5k dishes run through the same fitter — a real denominator at zero capture cost, but a
  fixed overhead rig, so its rate does not transfer to handheld ARKit with domestic clutter. The
  defensible form is two figures: an N5k **rate** that gates the algorithm, and a device **count**
  until the device corpus is large enough for a percentage to mean anything. Req 4.5 currently
  names one threshold and cannot carry both.

## Session attempted 2026-08-05 09:09–09:20 — four weighed truths, none usable

Recorded so the next sitting does not repeat it. The session covered captures 2, 4 and 5 of the
table below and produced **no evidence for this feature**, because every capture that completed
did so on the wrong path.

| Attempt | Truth | Estimate | Error | Class | Path |
|---|---|---|---|---|---|
| bowl of prawns | — | refused | repeated `noFoodPixels`, then `unrecognisedFood` | — | mixed |
| `1785921329668` bread | 196 g | 20.7 g | **9.5× under** | `bread_white` ✓ | two-view |
| `1785921526968` heaped rice, lipped plate | 245 g | 841 g | **3.4× over** | `carrot` + `mixed_vegetables` ✗ | two-view |
| `1785921628874` white rice | 320 g | 31.4 g | **10.2× under** | `white_rice` ✓ | two-view |

**All 22 `single_view_lidar` attempts refused; all three successes were `two_view_sfs`.** The
two-view carve is a Non-Goal, so a weighed capture that lands there is not evidence for this spec
however carefully it was weighed. Three lessons, each now a rule for the next session:

1. **Set Single mode and confirm it per capture.** This is the whole reason the session yielded
   nothing. Check `capturePath` in the estimation log before trusting a capture.
2. **The bowl capture needs in-palette food.** Prawns are not among the 25 solid classes, so the
   bowl attempts refused at segmentation with `unrecognisedFood` / `noFoodPixels` and never reached
   plane selection. A bowl capture can only test Req 7.4's fallback if the food is recognised — use
   rice, pasta or cereal.
3. **`worldTrackingDegraded` cost 13 attempts.** Not this feature's defect, but it is why a sitting
   yields far fewer usable captures than shutter presses; plan for roughly half.

Two findings worth keeping even though they do not grade this feature. The two-view under-read is
**~10×**, not the ~4× previously recorded — an order of magnitude, and it belongs to
`bugfixes/two-view-carve-no-volume`. And `1785921526968` reported `foodRegionCoveragePercent: 0`
and a `planeCandidateCount` of 30,576 against ~1M on the neighbouring captures, yet still returned
a "success" with 1,262 cm³ of volume — a success recorded on a frame with no confident depth over
the food at all.

`1785921526968` is also the **only lipped-plate capture that exists**, which is why Req 7.10 asks
for a single-view one: Decision 14's radial-band and support-visibility mitigations currently have
no field evidence of any kind.

## Captures still needed

One sitting, one plate set, roughly twenty-five minutes. Only three of the six need the scale — the
rimmed pair and the bowl are judged on *which surface was selected*, not on volume.

| # | Capture | Weigh? | Sets |
|---|---|---|---|
| 1 | Flat food on a flat plate (bread) | yes | Req 7.8 on-device verification |
| 2 | Mounded food, 20–40 mm tall (rice, mash, couscous) | yes | Req 7.3 non-flat anchor |
| 3 | Rimmed plate, well ~30 % covered | no | inner-band selection on real depth |
| 4 | **Same** rimmed plate, well ~90 % covered | yes | `supportVisibilityMin` — nothing else can set it; also Req 7.10 |
| 5 | Bowl, walls above the food, **in-palette food** (rice/pasta/cereal) | no | Req 7.4 fallback path |
| 6 | Food filling a **small** plate to within ~10 mm of the edge | yes | Req 3.6 sector guard — the silent-failure case |

Captures 3 and 4 must be the **same plate** at two fill levels: the pair is what separates
"well partly visible, inner band should win" from "well unobservable, must fall back", and a
single fill level cannot distinguish them. Capture 6 is the only one that exercises Req 3.6's
silent-failure case — food near a plate's edge, where the aggregate ring support favours the
table. Use a genuinely small plate; a dinner plate with a normal serving will not trigger it.

**Why capture 2 exists.** The defect adds a roughly constant *height* to every food pixel, so the
relative over-read scales inversely with food height — 3.57× on flat bread, 2.1× on mounded rice.
The bread bundle already holds the flat end. Without a non-flat anchor, a fix that overcorrects
tall food passes every criterion in the spec. The 208 g rice bundle cannot serve: it is still on
the device and was pulled, but `FixtureLoader` loads zero meals from it, and repairing a July
bundle is dearer than plating rice once on the current build.

**Why capture 1 is not the bundle we already have.** `1785901032716-success` covers the *replay*
criterion (Req 7.2). Req 7.8 is on-device verification, which by definition must run against the
built feature and cannot be satisfied by a stored bundle.

**Dump ring statistics, not just volumes.** Run all six through an instrumented pass with the
guards **disabled**, recording per-candidate `supportFraction`, `bandMedianMm`,
`supportVisibility`, the **per-sector** support fractions, and the raw signed heights (the
noise distribution below is computed from these; there is no MAD statistic to dump —
Decision 19 deleted it with its guard). Setting `ringSupportMin`,
`ringSupportMarginMin`, `supportVisibilityMin` and the three sector constants from the observed
separation is the point of the session; asserting them first and then measuring the fallback rate
they cause is circular, and Req 3.7 now forbids it for the sector constants. Task 26 already
commits to a corpus measurement pass — this feeds six inputs into the pass that exists for four
outputs.

Record the support-surface **depth-noise distribution** in the same pass. `ringSupportMin = 0.6`
over a ±5 mm band implies σ_z ≲ 5.9 mm, which is in tension with the matte-table evidence behind
Decision 46's 20 mm residual bar. If your table's real noise exceeds ~6 mm, every capture on it
falls back for a reason that has nothing to do with plane selection — capture at least one on a
matte surface to find out.

### Recording a capture

For each: weigh the food, plate it, capture on the iPhone 16 Pro, then note the stem, the
weighed grams, the food class and the vessel (flat plate / rimmed plate / bowl) in
`docs/agent-notes/field-truth-sessions.md`, following the 2026-07-26 session's table format.
The mass has to be written down at capture time — bundles record ground truth as zero and there
is no way to recover it afterwards.

## During implementation

- [ ] **Compute time for task 17.** Regenerating the N5k calibration results after the
  single-dominant branch moves off `fitPlateRegionPlane` re-runs the harness over the
  Nutrition5k corpus. Confirm the machine is free before starting, and do not launch it from a
  worktree (see `docs/ml-training.md` run hygiene).

- [ ] **Set the guard constants before task 8 hard-codes them.** `tasks.md` currently orders
  task 8 (`fitFoodSupportPlane`, which carries every threshold) before task 26 (determine the
  constants), so the numbers get baked into code and tests before anything measures them. Either
  reorder, or split task 8 into extract-and-instrument then threshold. Flagged rather than
  reordered here because it is a task-list change, not a hardware gate.

## Before testing

- [ ] **Xcode available for the latency and peak-memory measurement** in task 27 (Req 7.6). This
  path produced a 32 GB allocation failure at 1920×1440 before, and adaptive iteration now makes
  CPU scene-dependent, so both need measuring rather than asserting.

## Spec edits these unblock

Req 7.3 still names "the 208 g weighed rice capture" and must be repointed at capture 2's stem
and weighed mass once it exists. Task 22 has already been amended to point here instead.
