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
  **Answered 2026-08-05 by the task 26 measurement pass (Decision 29) — yes at this corpus's
  range, and only there.** Measured on both committed slices: `mmPerPx` 1.862 and 1.839 at
  median food depths of 338.9 mm and 336.9 mm, so the ~4 px smear spans **7.45 mm and
  7.36 mm** — inside 8 mm on both, but with under 8 % to spare. Since `smear_mm = 4z/f_d`,
  the envelope is `ringInnerMm × f_d / 4`: **364.1 mm** at f_d 182.0 px and **366.4 mm** at
  183.2 px, so the corpus stands at **93.1 %** and **92.0 %** of its own bound. At 500 mm the
  smear is ~11 mm. Decision 14's "already at the ~7 mm depth smear floor" is confirmed here
  and nowhere else.

  **The repair this item used to prescribe is measured and rejected (Decision 39).** It read
  "the radius must become `max(ringInnerMm, 4 × mmPerPx)`". It must not: `mmPerPx` is `z/f_d`
  and carries range and grid resolution alike, but only range moves the smear, because a
  coarser grid subsamples a map ARKit has already smoothed. At 128 px the smear-tracking
  radius reads 14.9 mm for a physical smear still near 7.4, leaving three ring bands of
  3.37 mm against depth pixels of 3.73 mm — each narrower than one pixel — and
  `1785135663727` loses ring feasibility (inner band 166 against a 200 floor) on the grid
  where the plane transfers within 0.9 mm today. **The envelope is a range bound, and only a
  capture can close it** — which is why the range is now on the recording list below.

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

  **`fallbackPenalty` is now behind this same gate (Decision 36).** The penalty is denominated in
  millimetres of plane error — σ_plane is exp(−r/5), so 0.9 charges 0.53 mm — and the corpus
  measures the edge-band plane adding **18.37 mm** to the mean food pixel on `1785135663727`,
  which prices it at 0.025. That is a ceiling and not a value: the fallback is the *correct* plane
  whenever food rests directly on the surrounding surface, so one constant prices a mixture whose
  weight is exactly this fallback rate. Deferring the rate defers the penalty with it.

  So the choice is now between deferring Req 4.5's rate until Bucket C, or measuring it on the
  device corpus, which is far too small for a percentage. The rest of the original reasoning
  still stands and still argues against a single threshold: N5k is a fixed overhead rig, so its
  rate would not transfer to handheld ARKit with domestic clutter even once it exists. The
  defensible form remains two figures — an N5k **rate** gating the algorithm, a device **count**
  until the device corpus can carry a percentage — and Req 4.5 names one threshold and cannot
  carry both.

  **And the denominator is the SECOND blocker, not the first (Decision 42).** On the corpus that
  exists the rate is a readout of the `[owed]` constants and of nothing else, so a threshold
  stated before they are set grades the placeholders — Req 3.7's circularity reaching Req 4.5 by
  another route. Measured: the shipped placeholders fall back on **2 of 2** captures (rate
  **1.000**, Req 4.5's own "delivering nothing"); `minSupportingSectors` swept alone reads
  `8-6 → 1.000`, then `5-0 → 0.500`; every owed bar at its loosest reads **0.000**. The rate
  reaching zero costs **no wrong plane** — both captures then select the candidate nearest
  Req 3.1's zero (−0.521 mm and −1.023 mm) — so nothing structural is wrong and the whole
  distance from 100 % to 0 % is constants the committed suite contradicts (Decision 41). What
  holds the wrong planes out there is `ringMedianMaxMm`, which is `[inherited]`, clearing the
  table candidate by **0.338 mm** on a 5 mm bar. The 0.000 is a bound rather than a proposal:
  on `1785901032716` the right plane is admissible only at support 0.362 over 2 of 8 sectors,
  which is Decision 33's plate margin read from the rate's side, and it is another reason the
  sitting must span plate sizes.

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

## 2026-08-11 — first field firing of the promoted path, and it confirms the range trap

One capture from the 2026-08-11 weighed-bread session (58 g slice, white plate,
iPhone 16 Pro, Release `9509b27-20260811-185011`) is sliced and committed as
`MedataCore/Tests/SupportPlaneTests/Fixtures/1786439141215.depthslice`, pulled
bundle in `tmp/device_captures/`. It is the **first real capture the restricted
fit admitted**: the device recorded `planeReference=foodSupport` (6/8 supporting
sectors, ring median −0.97 mm, residual 1.81 mm), and the harness replay selects
`foodSupport` on the same bundle (`accuracy` run, `foodSupport=1`, fallback rate
0.0 %) — Req 5.1 parity holding on a field capture.

The estimate is **3.0× UNDER by mass** (19.4 g vs 58 g; 48.6 cm³ vs ~215
expected). A probe run of `SupportPlaneCorpusMeasurementTests` with the stem
admitted measured why it cannot yet be corpus evidence:

- **Plane-at-food is 408.97 mm** — the capture was taken from ~41 cm, past the
  ~364 mm envelope (`ringInnerMm × f_d / 4`); the smear at that range is
  `4z/f_d ≈ 9.0 mm > ringInnerMm = 8`. This is exactly the Decision 39 trap: the
  inner ring band sits inside the depth smear, the ring measure is food-edge
  contaminated, and nothing in the estimate says so — the fit reads clean
  (probe: support 0.616, ring median −0.011 mm, crossed 2, supporting 6,
  seed spread 0.006 mm) while the volume is 3× short.
- **Its halved-grid extraction yields zero residues** ([5,276, 389] samples
  native → [] halved; floor 350 → 88), so the committed residue-area invariant
  ("the area survives a grid halving") fails on it and the test's indexing then
  traps. The invariant was written on two inside-envelope captures; whether it
  is a property of the algorithm or of their range is now an open question this
  capture raises.
- Sector verdicts at the shipped constants: crossed [2] supporting [6] — read
  AT the smear-contaminated ring, so not usable for `maxCrossedSectors`.

What this buys the sitting: the paired-capture rule is now mandatory, not
advisory — **re-shoot the same flat-bread scene from inside ~360 mm** (tape
measure) and the pair separates a contaminated ring measure from a real one.
Until that pair exists the slice stays out of `captures`, mirroring the
`rejectedCaptures` precedent, with the reason recorded here rather than
asserted in the suite (its disqualifier is range, which no threshold in the
fitter reads).

## Captures still needed

One sitting, one plate set, roughly twenty-five minutes. Only three of the six need the scale — the
rimmed pair and the bowl are judged on *which surface was selected*, not on volume.

| # | Capture | Weigh? | Sets |
|---|---|---|---|
| 1 | Flat food on a flat plate (bread) | yes | Req 7.8 on-device verification |
| 2 | Mounded food, 20–40 mm tall (rice, mash, couscous) | yes | Req 7.3 non-flat anchor |
| 3 | Rimmed plate, well ~30 % covered | no | inner-band selection on real depth; the only source for Decision 40's rimmed-plate counter-case, which the suite does not cover (Decision 43) |
| 4 | **Same** rimmed plate, well ~90 % covered | yes | `supportVisibilityMin` — nothing else can set it; also Req 7.10 |
| 5 | Bowl, walls above the food, **in-palette food** (rice/pasta/cereal) | no | Req 7.4 fallback path |
| 6 | Food filling a **small** plate to within ~10 mm of the edge | yes | Req 3.6 sector guard — the silent-failure case; sets `maxCrossedSectors` (Decision 40) |

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

**And the exclusion has been re-grounded, because τ_conf is itself owed (Decision 53).** Sweeping
the confidence bar shows the second reason above is a restatement of the first: at τ_conf = 0 the
same slice reads a food envelope of **+58.4 mm**. The mound is in the data and it is τ_conf that
removes it. The third reason reverses too — the spurious separable count needs 4 supporting
sectors, and the capture reads 2 at τ_conf = 0 and 3 at the shipped bar, reaching 4 only in the
HIGH-only state. What the exclusion actually rests on is that admitting the LOW samples the mound
is made of wrecks the ring fit the capture would have to anchor: its intended candidate's ring
median goes from a near-exact **−0.018 mm** to **−4.589 mm**. The capture's mound and its usable
support surface cannot both be present at any one setting, so capture 2 is still required and no
threshold recovers it. The 43.2 % is also the *support plane's* bar; at
`HeightFieldEstimator.tauConfidence = 0.66`, which is what consumes the food samples, the share is
**60.3 %**, and the "0.0 % on both committed captures" reads 2.7 % and 1.9 % there.

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
(added for Decision 33 — how far the plate extends beyond the food, per arc), and the **full
guard-verdict vector** per candidate (added for Decision 34 — `admissibility` short-circuits, so
the reason it returns says which guard came *first*, not which guards fired). Setting `ringSupportMin`,
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
Pipeline Decision 46's 20 mm bar is a *whole-plane residual over a matte table*, not a per-sample σ, so it
was never the same quantity — but the underlying worry it encodes is now measured and real. Take
at least one of the six on a matte surface, and note the surface material for each.

**And that capture now bounds two constants, not one (Decision 53).** The matte-table bug was
fixed by *lowering τ_conf* so MEDIUM-confidence returns survive, and MEDIUM-confidence returns are
the noisier ones — so `ringSupportMin` and `τ_conf` are the same question asked twice. On the
committed corpus, discarding MEDIUM raises the achievable support on both captures (0.629 → 0.690
and 0.362 → 0.379) and raises `ringSupportMin`'s corpus ceiling from 0.362 to 0.497, while
reproducing **no** starvation — every ring band still clears `ringMinSamples` and the fitter's own
band scan still returns a plane. So the corpus mildly prefers the state the shipped value rejects
and cannot justify either. The matte capture is what decides both. Record the ARKit confidence
histogram for each of the six alongside the surface material: the whole domain of τ_conf is which
of the three levels survives, so the level mix per surface *is* the measurement.

**Four guards have never fired, so four captures have a second job (Decision 34).** Setting a
constant and *exercising* the guard it gates are different asks, and for these four only the
second is within reach of a capture session. Of the nine rejection reasons, three ever fire on
the corpus — `extent`, `supportFraction`, `sectors` — and a fourth, `ringMedian`, only when the
guards are evaluated independently rather than short-circuited. Which capture fires which:

| Guard | What the corpus reaches | The capture that fires it |
|---|---|---|
| `foodEnvelopeMinMm` | **bracketed 7.154…21.041 mm** — a plane above the surface reads a *positive* 7.154 mm (Decision 48), and both ends are readings at `foodEnvelopePercentile` and at `ringSupportMin` (Decision 56) | 5, the bowl — still the only source of a *negative* envelope |
| `foodEnvelopePercentile` | **bracketed 0.1…0.92** — the bar's own denominator, moving its corpus ceiling 45.453 mm across the domain (Decision 56) | none — the floor is the committed suite's at the shipped bar, the ceiling the corpus's |
| `bandStepMaxMm` | every inner→mid step a **fall**, −0.5…−6.5 mm | 3 and 4, the rimmed plate — the only source of an outward rise |
| `supportVisibilityMin` | floor 0.246 against a 0.15 bar | 4, the ~90 %-covered well |
| `escapeBandMm` | annulus medians −36.6…**+5.7** mm against a 30 mm bar | **none of the six** — see below |

`escapeBandMm` fires when the surroundings sit more than 30 mm *above* the candidate plane
(Req 3.3; the one-sidedness is confirmed correct). No planned capture produces that, so it will
still be unexercised after the sitting unless one is arranged deliberately — food on a plate set
down inside something with walls well above it, or a capture where the depth region escapes
through a dropout. Worth one shutter press if the sitting allows; note that it is a deliberate
adversarial capture rather than a normal meal.

`ringSupportMarginMin` is not on the table at all: it compares the top two **admissible**
candidates, and until some capture yields two, it cannot run. The gaps real candidates open are
0.312 and 0.117, straddling the shipped 0.15.

**Capture 6 now sets a named count, not just a scene (Decision 40).** The sector rule that replaces
the unsigned count is stated: a **failing** sector — below `sectorSupportMin` — whose signed
inner-band median exceeds `+ringBandMm` is **crossed**, and a candidate is rejected when more than
`maxCrossedSectors` sectors are crossed; below `−ringBandMm` the sector has **escaped**, which is
the plate ending and not grounds for rejection. Its magnitude bar is inherited (`ringBandMm`, with
an 11.7 mm margin on each side of a 23.4 mm separating window), so the session has **one** number
to set here rather than a threshold and a count. The corpus brackets `maxCrossedSectors` at
**0…2** — the plate-top candidate carries 0 crossed sectors and the table candidate carries 3 —
and capture 6 is what closes it: a correct fit on a small plate is the only scene that shows how
many crossed sectors a *right* plane can carry. Dump the crossed and escaped counts alongside the
per-sector medians. Note that a rimmed plate is the counter-case, where a correct plane's ring can
reach a rim genuinely above it, so captures 3 and 4 grade the rule as well as capture 6 sets it.

**The corpus narrows that to a single value once the intended plane is identified correctly
(Decision 48).** The 0…2 above takes its floor from the plate-top candidate on `1785135663727` —
the *highest-support* candidate there, and the correct one. On `1785901032716` the highest-support
candidate is the **table**, the plane the guard exists to reject, and the plane a correct fit must
admit is the second extraction pass — nearest Req 3.1's zero at a ring median of −2.658 mm, and
carrying **2** crossed sectors. Floor 2, ceiling 2 (the table's 3, minus one). So at the shipped
`(ringOuterMm, ringSectorCount, sectorSupportMin, ringBandCount)` the corpus determines the
constant, and the sitting's job at capture 6 is to **confirm or break** that rather than choose
freely inside 0…2. Bring the reading back to those four constants before treating it as settled —
each is bracketed and each re-denominates this one.

**And the committed suite agrees with the corpus here, which it does nowhere else (Decision 43).**
Read through the rule, the eight committed scenes bracket `maxCrossedSectors` at **0…2** — the
same interval the corpus gives, on the same scenes where `minSupportingSectors` has an empty joint
interval of 6…5. Two things follow for the sitting. This is the one `[owed]` constant that can be
set from captures with no risk of turning the suite red, because there is no tighter suite bound
to land outside. And the rimmed-plate counter-case above is confirmed **uncovered** by the suite:
both committed rimmed-plate scenes read 8 of 8 supporting with no failing sector, because their
rims never reach the inner band the sector median is computed over. Captures 3 and 4 are the only
source for it, so shoot at least one of them with the food close enough to the rim that the ring
reaches it, and record whether the rim falls in the inner band.

**Fix `ringOuterMm`, `ringSectorCount` AND `sectorSupportMin` BEFORE the sitting, and fix all three
TOGETHER (Decisions 44, 45, 46).** Every sector bracket in this document is a count of sectors read
at eight of them, at a support bar of 0.5, **on a ring 25 mm wide**. Re-cut the same rings at nine counts and the joint bracket on
`maxCrossedSectors` takes eight distinct values: **0…0** at four sectors, 0…1 at six, **0…2** at
eight, 1…2 at ten and eleven. Take the captures first and choose the count afterwards and capture 6
measures nothing, because the number it produces is denominated in a constant that was still moving.

Decision 44 said to fix the count first and read the rest in the unit it set. That ordering is
**superseded**: the count's own bracket is a function of the bar. Counts with a clean pass side —
the plane a correct fit must admit reading no crossed sector, and the rule still firing on the
plane it must reject — are 6, 8, 10, 11 at a bar of 0.1–0.2; **all five** Req 5.1 permits at 0.3;
4, 6, 8, 10 at 0.4; and 4, 6, 8 from 0.5 up. So the pass-side erosion above eight sectors that
gives 4…8 its top is itself a consequence of the bar sitting at 0.5.

~~And the pair is a **triple** (Decision 46). `ringOuterMm` is upstream of both, because it moves the
**annulus** — `2 × ringOuterMm` is the candidate bound — so extraction runs on a different sample
set at every value and the radius selects *which plane* the count and the bar are then read on.
Fix it first, then the pair.~~ **Superseded (Decision 49.)** The candidate bound is now
`annulusOuterMm`, a constant of its own, and it is what moved the plane: pin it and the radius
moves the selected plane 0.000 mm at every value from 13 to 40 mm on both captures. The pair is a
pair, the radius is fixed *beside* it, and the bound is a **fourth** constant to choose. Decision 50
adds a **fifth**, `inlierRemovalMultiple`, and puts it before the residue floor and the pass cap.
Choose all five and record them, with the reason, before the sitting.

The radius is bracketed **22…32 mm** (Decision 46), and Decision 49 removes the rider that it must
not be interpolated:

- **Floor, 22 mm, from Req 5.1.** A narrower ring holds fewer samples per radial band and the 2×
  grid halving quarters them, so below 22 mm `ringBandsAreFeasible` refuses on a grid where the
  plane still transfers within a millimetre — halved bands read [78, 111, 48] at 13 mm against the
  200 floor. This is the mirror of the count's ceiling of 11: both come off the same halving.
- **Ceiling, 32 mm, from the committed suite.** The scenes place their features at fixed pixel
  radii, so at 35 mm the ring reaches the rim a scene deliberately put outside it, every sector of
  a scene that must *pass* reads crossed, and both suite intervals go empty. Above 32 mm the
  committed suite goes red and the scenes have to move with the constant.
- ~~**No interpolation.** The pass side alternates at 1 mm steps: the corpus's only intended-correct
  candidate reads 0 crossed sectors at 22, 23, 25, 26, 28, 29 and 31 mm and **2** at 24, 27, 30 and
  32 mm.~~ **Superseded (Decision 49):** the alternation is the annulus resizing with the radius.
  With the bound pinned the same candidate reads 0 crossed at every radius in the sweep, so the
  bracket may be interpolated.
- ~~**It moves the answer, not just the bracket.**~~ **Superseded (Decision 49):** it moves 0.000 mm
  once the bound is pinned. The 18.719 mm and 4.162 mm belong to `annulusOuterMm`. Still record the
  plane at the food for every candidate on every capture, not just the winner — that is what made
  the decomposition readable.

The candidate bound is bracketed **50…75 mm** by the corpus, and by the corpus alone:

- **Floor, 50 mm — the shipped value sits on it.** Below it the plane a correct fit must admit is
  itself crossed: `maxCrossedSectors` reads 3…unbounded at 31.25 mm and an empty interval at 25,
  37.5 and 43.75 mm. At 25 mm the bound has collapsed onto the ring and extraction yields two
  candidates rather than three.
- **Ceiling, 75 mm.** At 100 mm the interval collapses the other way — the plate capture's intended
  candidate reads **6** crossed sectors and a ring median of +1.793 mm, the annulus having reached
  surfaces beyond the plate.
- **The committed suite cannot see it.** The scenes never run extraction, so the bound reaches them
  only through `visibility` and `escaped`, both of which never fire (Decision 34). Every scene keeps
  its verdict from 25 mm to 100 mm, so this constant has no second source: the captures are it.
- **It is what determines `maxCrossedSectors`.** Decision 48's determination at 2 holds at 50 mm and
  nowhere else in the sweep; 62.5 and 75 mm widen it to 2…4. Read the two together.
- **Req 7.6 is denominated here.** The annulus holds 10 469 and 12 551 samples at 50 mm against
  19 427 and 25 659 at 100 mm, and RANSAC iterates over all of them. Measure latency at whatever
  value the sitting sets, not at the shipped one.
- **Keep the ring inside the bound.** Free while it was a multiple ≥ 1; an invariant now that the
  two are independent.

The removal band is bracketed **1…2.5×** by the corpus (Decision 50), and the shipped 2× sits
strictly inside it — the only owed constant in this feature that does:

- **Its stated rule is false, so there is nothing to inherit.** "A 1× shell seeds near-duplicate
  planes on the next pass" is wrong on this corpus: no adjacent pass pair at any multiple is a
  near-duplicate, the closest at 1× diverging by 30.807 mm across the annulus against a 5 mm inlier
  band. CC-RANSAC keeps the largest *connected* component, so what a 1× shell leaves is a thin ring
  around a surface already taken. Do not carry the claim into the sitting.
- **Floor, 1×, and it is structural rather than measured.** Below it a pass leaves samples it
  selected within `inlierBandMm` and the next pass can re-find the same plane. The corpus does not
  raise it: at 1× the intended candidate is still admissible and still separable.
- **Ceiling, 2.5×, from the corpus.** A shell wide enough to take the table takes the plate with it.
  On `1785901032716` the intended plane's ring median degrades −2.203, −2.309, −2.377, −2.658,
  −3.011 mm over 1…2.5× and at 3× the candidate is gone — the nearest-to-zero plane is the **table**
  at +3.039 mm with 3 crossed sectors, so `maxCrossedSectors` reads 3…unbounded.
- **Interpolable.** Unlike the radius (Decision 46), the readings are monotone across the sweep.
- **It does not move the plane.** 0.000 mm at the food on both captures at every multiple, because
  removal happens *after* a pass and the ranking picks pass 1 throughout. Bracket-only.
- **Fix it before `minResidueAreaMm2` and `maxCandidatePlanes`.** Natural extraction depth runs
  [7, 5] passes at 1×, [5, 3] at 1.25×, [4, 3] at 1.5×, [3, 3] at 2× and [2, 1] at 6×, so the cap
  truncates below the shipped value — Decision 48's "the cap never fires" is a reading at 2×.
  Req 7.6's latency follows the same chain.
- **The committed suite cannot express a reading on it at all.** Not silent by measurement, as the
  candidate bound was, but structurally: no scene runs extraction. The captures are the only source.
- **`maxCrossedSectors` is *not* denominated in it.** It reads 2…2 at every multiple the bracket
  admits, so the two may be set independently — true of no other constant that changes the
  candidate set.

The RANSAC budget is **two** constants, and the sitting does not set either of them — this is the
one place the committed corpus alone is the source (Decision 51):

- **`ransacSuccessProbability` is bracketed 0.9…unbounded, and it is the end of the clamp that
  binds.** `requiredIterations` is `min(cap, target)` and the target is always the smaller: the
  passes spend 72, 11, 250 and 12, 41, 5 against a cap of 2048. It carried no provenance marker at
  all until now.
- **It moves the plane 3.704 mm**, past the 1 mm Req 5.1 is measured at — only `annulusOuterMm`
  otherwise does. **Do not interpolate**: the readings wander (351.620, 349.473, 353.130, 351.328,
  349.426, 349.426 mm) rather than climb, as Decision 46's radius did and Decision 50's removal
  band did not.
- **It is what the ~2 mm of draw dependence is denominated in.** Decision 46's eight-seed control
  re-run against the cap does not move (2.095 mm at 256, 2048 and 8192); re-run against the target
  it collapses 2.095 → 0.194 mm at 0.99999. Every plane figure Decisions 40–50 quote carries that
  dependence, and it is **removable** — which is a reason to fix this constant early, since
  tightening it may be worth re-reading the other brackets at.
- **`maxIterationsPerPass` never fires and is bracketed 128…unbounded.** The largest draw the
  corpus needs is 250, so nothing at or above 256 is distinguishable. Its floor is a verdict flip
  at 64 (5 supporting / 0 crossed → 3 / 2); its ceiling belongs to **Req 7.6 and task 27**, not to
  a capture, and the low-inlier-ratio scene where it would fire is one this corpus lacks. There is
  8× of headroom to pay for a tighter target before latency is consulted.
- **No capture is required for either.** Unlike every other owed constant, these are settable from
  the committed slices — but choosing a value inside a bracket is still asserting, which Req 3.7
  forbids.

The budget is **three** constants, not two: the third is on the **fallback** leg and behaves
nothing like the other two (Decision 57).

- **`LiDARPlaneFitter.maxIterations` is bracketed 8…unbounded by the corpus and 4…unbounded by the
  committed regression suite**, with the shipped 256 strictly inside both, and it is the only
  constant task 26 has measured that a single leg reads. There is no adaptive stopping on this
  leg at all.
- **Its search never converges**, so no value is a convergence point: 1024 draws still find a
  better hypothesis on both captures (#689 and #1005, against the #76 and #210 that 256 stops at).
  The exact mirror of `maxIterationsPerPass`, which never binds.
- **It is a floor, not a knob.** The plane spans 23.474 mm and 0.152 mm at the food over 1…1024
  and every millimetre of the wide one is below a budget of 8. From 8 up the captures hold to
  0.027 and 0.152 mm, inside Req 5.1.
- **The sweep is exact at every intermediate value** — a budget-B run is a strict prefix of a
  budget-B′ run — so unlike `ransacSuccessProbability` there is no interpolation rider in either
  direction.
- **The committed suite bounds it, through the fallback leg for the first time.** At a budget of
  1 or 2 all three of `SupportPlaneRegressionSliceTests`'s parity-capture bands go red at once.
  The suite is the **looser** source here (4 against the corpus's 8), which reverses the risk
  Decision 41 recorded.
- **Both brackets are readings at `gravityAngleMaxRad`**, and both floors rest on the easiest
  surface in the corpus — the matte-table capture is what would price this constant properly.
  **Req 7.6 and the corpus point the same way**, which is true of no other owed constant.

The count is bracketed **4…8** by what is in hand, with a hard ceiling of **11**:

- **No floor.** The crossed-sector rule separates the corpus's plate-top candidate from its table
  candidate at every count from 4 to 32, so a coarse cut does not average the crossing away.
- **Top of the bracket, 8.** The plate-top candidate — the plane a correct fit must admit — reads
  0 crossed sectors at 4, 6 and 8 and **1** from 10 upward: narrow arcs resolve the direction its
  own ring ran off the plate onto the table, and the rule's floor stops being zero.
- **Hard ceiling, 11.** `ringMinSamples` *is* `ringSectorCount × 25`, so finer arcs raise the floor
  the ring must clear. Req 5.1's 2× grid halving leaves the thinnest radial band at 292 samples,
  and 292/25 = 11. Above that the plane still transfers within a millimetre and the ring measure
  refuses — the native grid would have carried 44.

One trap, because it looks like a shortcut. A *coarser* cut leaves *less* freedom in the constant
it denominates: at four sectors `maxCrossedSectors` is **determined at 0** by the corpus and the
committed suite together, so choosing four would close it without capture 6 at all. Do not. It
asserts `ringSectorCount` in order to avoid asserting `maxCrossedSectors`, and whether a 90° arc
resolves Req 3.6's straddle is a property of scenes the corpus does not contain — which is what
capture 6 is for. Note the choice and its reason before the sitting, and record every sector figure
with the count **and the bar** it was read at.

The bar is bracketed **0…0.5** and the shipped 0.5 is **on** the ceiling (Decision 45):

- **Floor, and it is the rule's own.** At 0 no sector fails, so the population the crossed-sector
  rule reads is empty and it admits the plane Decision 18 exists to reject. At eight sectors that
  is the only silent bar; at four the floor rises to 0.3, which is the coupling from the other side.
- **Ceiling, 0.5, and it is a cliff rather than a slope.** The room `ringBandMm` has — how far it
  may move before either corpus candidate changes its crossed count — is 49.167 mm at 0.1–0.3,
  26.283 at 0.4, **23.397 at 0.5**, then **2.263 at 0.6** and 2.128 at 1.0. A 10.339× collapse in
  one notch, at exactly the shipped value. Decision 40 already supplied the criterion — 2.128 mm is
  "fitted", 23.397 mm is "inherited" — so no new threshold is needed to read it.
- **Why both edges move.** As the bar rises, noisy sectors that sit *on* the correct plane start
  failing and read near zero, lifting the window's floor from −32.564 to +3.846 mm; sectors holding
  the table plane at a small positive offset fail too and become crossed, dropping its ceiling from
  +16.603 to +5.974 mm. The bar is squeezed from both directions by one constant.

Dump the per-sector fractions for every capture so the bar can be re-read off the sitting at any
value, not only the one chosen going in. Nothing about the cliff generalises from two captures — it
is sharp because a handful of sectors cross together between 0.5 and 0.6 on the corpus's two
candidates, and only the session can say whether that holds on a plate it has not seen.

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

**Note the capture RANGE for every capture (Decision 39).** How far the phone was from the food,
to the nearest centimetre — a tape measure, or read `mmPerPx × f_d` back off the slice afterwards.
This is the cheapest thing on the list and the only one with a hard bound already measured against
it: `ringInnerMm = 8` covers the ~4 px depth smear only out to `ringInnerMm × f_d / 4`, which is
**364 mm** on this device, and the two committed captures sit at **93 %** and **92 %** of that. A
capture taken from a little further back has its inner ring band inside the smear, so its ring
median and per-sector fractions are contaminated by food-edge bleed — and nothing in the estimate
says so. The obvious fix, scaling the radius with `mmPerPx`, is measured and rejected (Decision 39),
so a capture is the only thing that can close this. **If a capture must be taken beyond ~360 mm,
take a second of the same scene inside it**: the pair is what separates a contaminated ring measure
from a real one.

**Note the depth resolution if any capture is not a 256×192 LiDAR frame (Decision 35).** The plane
itself transfers: across a 2× grid halving it moves 0.835 mm and 0.037 mm on the two committed
captures, which is what Req 5.1's 1 mm tolerance is set from. One thing still does not:
`planeCandidateCount` drops from three passes to two, so it reads resolution rather than scene.

The extent bar no longer needs this warning. It was `minAcceptedExtentPx`, denominated in **pixels**
— the only bar in `admissibility` that was — so its 13…26 bracket held only at 256×192 and a surface
admitted at 44 px was rejected as a sliver at 22 px. **Decision 37 re-denominated it** to
`minAcceptedExtentMm = 44`, bracketed at 22.3…47.8 mm, and the session may now set it in millimetres
against captures at any depth resolution without restating the bracket.

**A capture can succeed and still be empty.** The 208 g rice bundle returned a plausible
603 cm³ at capture time and reads as well-formed everywhere except the confidence map, where
41 % of the frame is ARKit-low and the mound is entirely inside that share (Decision 31). Two
captures in this corpus read 22.7 % and 0.1 % frame-wide, so the spread between a good frame
and a lost one is wide and invisible from the estimate. Take each of the six twice if the
sitting allows, and treat `foodRegionCoveragePercent` — already persisted on every attempt —
as the field-side reading of the same quantity.

### Recording a capture

For each: weigh the food, plate it, capture on the iPhone 16 Pro, then note the stem, the
weighed grams, the food class, the vessel (flat plate / rimmed plate / bowl), the plate diameter
and the food's placement on it, the surface material, and the **capture range** in
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

- [x] **Set the guard constants before task 8 hard-codes them.** **Answered 2026-08-06 by
  measurement, not by reordering (Decision 41).** The item read: "`tasks.md` currently orders
  task 8 (`fitFoodSupportPlane`, which carries every threshold) before task 26 (determine the
  constants), so the numbers get baked into code and tests before anything measures them.
  Either reorder, or split task 8 into extract-and-instrument then threshold." Task 8 shipped,
  so reordering is no longer available; what the worry was actually about is measurable.

  The code half is handled by the `[derived]`/`[measured]`/`[inherited]`/`[owed]` provenance
  annotation and Req 3.7's ban on shipping the sector constants asserted. The test half was
  not. The scene suites reference owed constants twenty-eight times, all symbolically —
  which is not the same as insulation, because a fixed scene asserted against a moving
  constant still flips. `committedScenesBoundTheOwedConstants` measures the interval each
  constant can move in before a committed assertion changes verdict:

  | Constant | Suite interval | Corpus bracket |
  |---|---|---|
  | `ringSupportMin` | ≤ 0.676 | ≤ 0.362, the corpus's first ceiling (Decision 52) — and itself a reading at τ_conf: ≤ 0.497 with HIGH-confidence samples only (Decision 53). The **value** still needs the matte capture |
  | `minSupportingSectors` | 6…7 | ≤ 5 |
  | `bandStepMaxMm` | 0.024…9.288 mm | no floor at all |
  | `supportVisibilityMin` | ≤ 2.667 | ≥ 0.246 |
  | `foodEnvelopeMinMm` | −6.758…8.233 mm | 7.154…21.041 mm (Decision 48) — **both intervals are readings at `foodEnvelopePercentile`**, and the corpus floor exists only for `ringSupportMin` ≤ 0.304 (Decision 56) |
  | `foodEnvelopePercentile` | floor **0.1** at the shipped bar — `overhangingFood` fires below it, and no owed value enters that bound | ceiling **0.92**, where the corpus floor passes the suite's ceiling (Decision 56) |
  | `escapeBandMm` | ≥ 14.868 mm | reaches +5.750 mm |
  | `maxCrossedSectors` | 0…2 | **2…2** at full pass depth (Decision 48; 0…2 in Decision 43) |
  | `maxCandidatePlanes` | ≥ 2 (`sequentialExtractionSurfacesThePlate`) | ≥ 2, no ceiling — the cap never fires *at 2× removal* (Decisions 48, 50) |
  | `inlierRemovalMultiple` | none — no scene runs extraction | 1…2.5× (Decision 50) |
  | `ransacSuccessProbability` | none — no scene runs extraction | 0.9…unbounded (Decision 51) |
  | `maxIterationsPerPass` | none — no scene runs extraction | 128…unbounded (Decision 51) |
  | `inlierBandMm` | none — every reading from 1 to 12.5 mm is identical, because scene noise is ±0.3 mm | **empty** at the shipped bars; 5 mm at `ringSupportMin` ≤ 0.362, 6 mm with HIGH-confidence samples only (Decisions 52, 53) |
  | `confidenceThreshold` (τ_conf) | none — scenes carry no confidence map | **three states**, not an interval; accept-LOW ruled out, the other two undecidable without a matte capture (Decision 53) |

  **Both sector rows are denominated in `ringSectorCount`, which is `[owed]` too
  (Decision 44), and in `sectorSupportMin`, which is `[owed]` as well (Decision 45).**
  `minSupportingSectors` 6…7 and `maxCrossedSectors` 0…2 hold at eight sectors and a bar of 0.5,
  and nowhere else: at four sectors the latter is 0…0, and at eight sectors with a bar of 0.1 it is
  0…0 too. Fix the **pair** before reading either — see the capture-session section above.

  **Two of these bind tighter than the corpus**, so a value set at the sitting against captures
  alone can land inside the corpus's bracket and outside the suite's: `foodEnvelopeMinMm` above
  8.233 mm breaks the overhanging-food scene, and `escapeBandMm` below 14.868 mm breaks the
  rim-in-the-outer-band scene. Check both against this table before writing a value down.

  **And the envelope row is denominated in a constant that is not in this table's left
  column** — `foodEnvelopePercentile`, `[owed]` since Decision 56. Both intervals move with it:
  the corpus ceiling runs −19.415…26.038 mm over p ∈ [0, 1] and the suite's −6.440…8.299 mm, so
  the 1.079 mm joint window is a reading at the shipped 0.90 and reads 8.779 mm at p = 0.5. Fix
  the percentile **before** the bar, and note that the shipped 0.90 is admissible only where
  `ringSupportMin` exceeds 0.183.

  **And one contradicts it.** A real intended candidate scores 5 of 8 sectors (Decision 33), so
  `minSupportingSectors` has to come down to 5 or below — but the silent-failure scene the guard
  exists to reject scores 5 as well, so the suite floors it at 6. No value satisfies both. This
  is not a session problem to solve at the table: it is Decision 30's finding, and it resolves
  when Decision 40's crossed-sector rule replaces the unsigned count. ~~The scene moves with it.~~
  **Superseded by Decision 43**: the scene does not move. Measured on the same eight scenes, the
  rule brackets `maxCrossedSectors` at 0…2 where the count's joint interval is empty, so the
  collision belongs to the count alone and every committed scene survives the replacement intact.
  **Confirmed over the whole grid (Decision 45)**: across five counts × eleven support bars, no
  cell collides — wherever the rule fires at all, the suite and the corpus admit a common
  `maxCrossedSectors`. The agreement is a property of the rule, not of the shipped pair.

## Before testing

- [ ] **Xcode available for the latency and peak-memory measurement** in task 27 (Req 7.6). This
  path produced a 32 GB allocation failure at 1920×1440 before, and adaptive iteration now makes
  CPU scene-dependent, so both need measuring rather than asserting.

## Spec edits these unblock

Req 7.3 still names "the 208 g weighed rice capture" and must be repointed at capture 2's stem
and weighed mass once it exists. Task 22 has already been amended to point here instead.
