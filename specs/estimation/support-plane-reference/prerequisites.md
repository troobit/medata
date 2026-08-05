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

- [x] **Is `ringInnerMm = 8` inside the depth smear at real capture distance?**
  **Answered 2026-08-05 by the task 26 measurement pass (Decision 29) — no, and the envelope
  is ≈ 365 mm.** Measured on both committed slices: `mmPerPx` 1.862 and 1.839 at median food
  depths of 338.9 mm and 336.9 mm, so the ~4 px smear spans **7.45 mm and 7.36 mm** — inside
  8 mm on both, but with under 8 % to spare. Since `smear_mm = 4z/f_d` and `f_d ≈ 182 px`,
  8 mm covers range to **≈ 365 mm** and no further; at 500 mm the smear is ~11 mm. The
  radius must become `max(ringInnerMm, 4 × mmPerPx)` before any capture beyond ~365 mm is
  trusted. Decision 14's "already at the ~7 mm depth smear floor" is confirmed at this
  corpus's range and only there.

- [ ] **Measure your own plates with a ruler.** Rim height above the well, and well diameter,
  for the plates you actually eat off. The design's rimmed-plate exposure table uses assumed
  "ordinary dinnerware" figures of 12/18/28 mm. For a developer-phase tool the population that
  matters is one cupboard, so this replaces an assumption with a measurement in minutes. It also
  sets whether `bandStepMaxMm = 6` sits safely below your smallest real rim step.

- [ ] **Decide which corpus Req 4.5's fallback rate is measured on.** **The cheap denominator
  this item assumed does not exist.** It read: "after task 17 regenerates, ~3,500 N5k dishes run
  through the same fitter". Task 17 ran, and **none** of them do — pre-checkpoint ingestion
  stamps every plate `mixture`, mixture keeps the plate-region flood fill permanently
  (Decision 17), and `run_summary.json` records `single_dominant: 0`. N5k yields a
  promoted-path fallback rate only after model-production Bucket C lands and ingestion re-runs
  with `--checkpoint`.

  So the choice is now between deferring Req 4.5's rate until Bucket C, or measuring it on the
  device corpus, which is far too small for a percentage. The rest of the original reasoning
  still stands and still argues against a single threshold: N5k is a fixed overhead rig, so its
  rate would not transfer to handheld ARKit with domestic clutter even once it exists. The
  defensible form remains two figures — an N5k **rate** gating the algorithm, a device **count**
  until the device corpus can carry a percentage — and Req 4.5 names one threshold and cannot
  carry both.

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
tall food passes every criterion in the spec.

**The 208 g rice bundle cannot serve, and the reason is now measured (Decision 31).** It was
tried: `tools/fixture_slice.py` cuts `1785054950406-success.fixture` cleanly, so the
`FixtureLoader` failure is not a slice-level one and the capture runs through the whole
measurement pass. It is disqualified on the depth confidence map. **43.2 %** of its food-mask
samples carry ARKit's low confidence and are discarded at τ_conf — against **0.0 %** on both
committed captures — and the discarded ones are the *near* samples, median 247.9 mm against
the 277.8 mm of those that survive. τ_conf removes the mound. What reaches the fit is the flat
remnant around the pile, and the best candidate reports a food envelope of **−9.0 mm**, so
there is no mound left to anchor against. The slice is committed as `rejectedCaptures` with
that measurement asserted, because admitting it flips the sector derivation to a spurious
"separable" result. Capture 2 must still be taken.

**Why capture 1 is not the bundle we already have.** `1785901032716-success` covers the *replay*
criterion (Req 7.2). Req 7.8 is on-device verification, which by definition must run against the
built feature and cannot be satisfied by a stored bundle.

**Dump ring statistics, not just volumes.** The instrumented pass exists —
`SupportPlaneCorpusMeasurementTests`, run by `swift test --filter SupportPlaneCorpusMeasurement`
— so this is now a matter of cutting slices for the six captures with `tools/fixture_slice.py`
and adding their stems to its `captures` list. It runs with the guards **disabled** and records
per-candidate `supportFraction`, `bandMedianMm`, `supportVisibility`, the **per-sector** support
fractions, the **per-sector signed inner-band medians** (added for Decision 30 — the sign is what
separates a correct plane whose ring escaped from a table plane, and the unsigned count cannot),
the raw signed heights (the noise distribution below is computed from these; there is no MAD
statistic to dump — Decision 19 deleted it with its guard), and the **per-sector support margin**
(added for Decision 33 — how far the plate extends beyond the food, per arc). Setting `ringSupportMin`,
`ringSupportMarginMin`, `supportVisibilityMin` and the three sector constants from the observed
separation is the point of the session; asserting them first and then measuring the fallback rate
they cause is circular, and Req 3.7 now forbids it for the sector constants. Task 26 already
commits to a corpus measurement pass — this feeds six inputs into the pass that exists for four
outputs.

**A matte-surface capture is now REQUIRED, not suggested.** `ringSupportMin = 0.6` over a ±5 mm
band implies σ_z ≲ 5.9 mm. The measurement pass put per-sample σ on a flat surface at **3.44 mm**
on `1785135663727` and **6.98 mm** on `1785901032716` — at 338.9 mm and 336.9 mm, so the same
range, and a 2× spread that can only be the surface. `ringBandMm = 5` falls between them, which
means `ringSupportMin` cannot be derived at all until the spread is characterised (Decision 29).
Decision 46's 20 mm bar is a *whole-plane residual over a matte table*, not a per-sample σ, so it
was never the same quantity — but the underlying worry it encodes is now measured and real. Take
at least one of the six on a matte surface, and note the surface material for each.

**Vary how much plate shows, and record it.** The measured support margin — the distance from the
food boundary at which the surface falls away — is 16, 40, 10, 42, 6, 4, 6, 44 mm on
`1785135663727` and 34, 4, 46, 8, 30, 14, 12, 6 mm on `1785901032716`. The plate therefore ends
inside the 8–25 mm ring in five of eight directions on both, only four sectors reach the radius
the sector measure is decided at, and `minSupportingSectors = 6` is unreachable on either capture
by geometry alone (Decision 33). `ringOuterMm` and the sector trio are consequently **one**
derivation, not two, and the session cannot make it unless the six captures span the range: at
least one with the food well centred on a large plate, and at least one with the food close to the
edge. Note the plate diameter and the food's placement for each — the pass measures the margin per
sector, but only the session can arrange for the margins to differ.

**A capture can succeed and still be empty.** The 208 g rice bundle returned a plausible
603 cm³ at capture time and reads as well-formed everywhere except the confidence map, where
41 % of the frame is ARKit-low and the mound is entirely inside that share (Decision 31). Two
captures in this corpus read 22.7 % and 0.1 % frame-wide, so the spread between a good frame
and a lost one is wide and invisible from the estimate. Take each of the six twice if the
sitting allows, and treat `foodRegionCoveragePercent` — already persisted on every attempt —
as the field-side reading of the same quantity.

### Recording a capture

For each: weigh the food, plate it, capture on the iPhone 16 Pro, then note the stem, the
weighed grams, the food class and the vessel (flat plate / rimmed plate / bowl) in
`docs/agent-notes/field-truth-sessions.md`, following the 2026-07-26 session's table format.
The mass has to be written down at capture time — bundles record ground truth as zero and there
is no way to recover it afterwards.

## During implementation

- [x] **Compute time for task 17.** **Done 2026-08-05 — and the gate was mis-costed.** The
  run is ~4 minutes end to end on an idle 18-core Mac: ~90 s to ingest 3,490 dish folders,
  then two HarnessCLI passes under a minute each. It needs no scale rationing, so it ran from
  the worktree.

  The "segmenter pass over ~3,500 dishes" this gate warned about is **`--checkpoint` mode
  only**. Pre-checkpoint ingestion — which is what both committed artefacts used, and what
  the corpus still needs until model-production Bucket C lands — runs no model at all: it
  reads PNG pairs and writes fixtures. The expensive regeneration is the *post*-checkpoint
  one, and this was not it.

  What ran:

  ```bash
  python3 tools/nutrition5k/ingest.py --n5k-dir data --out tmp/n5k_fixtures
  .build/release/HarnessCLI calibrate[-and-eval] --fixtures-dir tmp/n5k_fixtures \
    --depth-test-split data/dish_ids/splits/depth_test_ids.txt \
    --ingest-summary tmp/n5k_fixtures/run_summary.json \
    --mapping-version 909f19f575a6 --seed 42 --output <artefact>
  ```

  The two committed artefacts —
  `specs/estimation/nutrition5k-calibration/artifacts/calibrate.json` and
  `accuracy_report.json` — recorded no `support_plane_reference`, so under the Req 5.3
  fail-closed guard they could no longer bake. They now do. Results, and why the numbers moved
  for a reason that is not the support plane, are in
  `docs/agent-notes/n5k-calibration-harness.md`. Every β is still `uncalibrated_unity`
  (Decision 10), so nothing downstream changed.

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
