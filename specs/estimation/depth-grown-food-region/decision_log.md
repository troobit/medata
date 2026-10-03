# Decision Log: Depth-Grown Food Region

## Decision 1: Grow by depth continuity from the segmenter's seeds, then refit the plane

**Date**: 2026-10-03
**Status**: accepted

### Context

The sesame-roll captures of 2026-09-23 and 2026-09-24 show the segmenter labelling a few percent of a food it does not know, while LiDAR shows the whole food as one raised slab. Volume is integrated per pixel of the label map, so the record under-reads by the fraction the model missed. A retrain fixes one texture; the geometry fix applies to any partly recognised food.

The first support-plane fit on the single-view path runs before segmentation, from the pre-shutter mask (Pipeline stage D). On the 14:23:38 capture it fell back to `edgeBand` (the table, ring median 19.7 mm), because the contact ring around the two specks lay on the roll's own top. Any criterion that reads "raised above the plane" therefore includes the entire plate on this capture.

### Decision

Seeds are the food-like pixels of the regularised label map. The region grows on the depth grid by multi-source breadth-first fill through 4-neighbour steps with |Δz| ≤ 4 mm, confidence ≥ `tauConfidence`, and the cell's surface at least 3 mm above the support surface: the first plane on a `foodSupport` fit, the first plane plus the fitter's ring median on an `edgeBand` fit. First arrival labels a cell. Growth that exceeds 0.35 of the frame is discarded. When growth changed the map, the plane is refit with the grown region as the food mask; the grown region is then pruned by the same height test against the refit plane (the first plane when the refit refuses), and the refit plane and the metric scale derived from it are used when the pruned region still has added pixels. Order: grow, refit, prune.

### Rationale

**Revised the same day by the corpus sweep.** The first draft admitted cells by depth continuity alone and applied the height floor only after the refit, on the claim that the roll's edge is a 20–40 mm drop over one or two depth pixels. The sweep over the 10 loadable single-view successes on `ab812dc3aa9d` (task 5) showed otherwise: at every cliff value tried (3, 4, 6 mm) and every floor, the fill either tripped the 0.35 cap (7 of 10 captures, the roll capture among them) or leaked 5–11 % of the frame onto the plate with the refit still `edgeBand` (3 of 10), identically across all nine settings. ARKit's smoothed depth renders the food-to-plate edge as a slope of a few millimetres per cell, so continuity cannot bound the fill on real captures. What can is the support surface's level, and the fitter already measures it: on an `edgeBand` fit the ring median is the plate top's height above the table plane (+19.7 mm on the roll capture; the `RingStatistics` comment gives +18…+26 mm as the corpus range). Admitting a cell only when its height above the plane, less that offset, clears the 3 mm floor keeps the fill on the food.

The floor is applied again after the refit rather than only during the fill because the first plane is fitted from the pre-shutter mask: when that mask is a speck on a flat-topped food the contact ring lies on the food and the plane is the food's own top, so measured against it nothing is raised and a fill gated on height would be inert on the capture the pass exists for (the replay test's synthetic disc reproduces this: first fit `edgeBand` at the food top, refit `foodSupport` on the plate). Continuity finds the slab without a plane, the refit puts the ring on the plate, and the prune removes what the fill reached that is not raised above it. On an `edgeBand` fit the floor cannot bound a leak, because the plate sits 19.7 mm above that plane; the cliff does. On a `foodSupport` fit the floor is what drops plate pixels that sit above the plane by fit noise (residual 1.5–1.8 mm here), which is why it is 3 mm rather than 0. Refitting with the grown region moves the contact ring off the food and onto the plate, which is the fit the support-plane-reference spec wants and the one this capture did not get. The cap is a coarse stop for the case where the fill runs over the whole plate; the corpus sweep (Decision 2) decides whether it and the cliff value are right.

### The sweep (task 5, 2026-09-24)

`HarnessCLI accuracy --growth-cliff-mm C --growth-floor-mm F` over the 10 loadable single-view successes on `ab812dc3aa9d` in the corpus (`1786450130307-success` is a truncated file, 170,000,000 bytes, and is excluded; `1785125982524-success` refuses with `noFoodVolumeRecovered` before and after growth). "Added" is the food-like frame fraction after growth over before, on the 7 captures whose ungrown food-like area is at least 5 % of the frame. Cap 0.35 throughout.

| cliff mm | floor mm | median added | largest added | cap trips | roll capture `1790223818017` after (refit) | refits landing `foodSupport` |
|---|---|---|---|---|---|---|
| 3 | 2 | +40 % | +153 % | 0 | 7.2 % (foodSupport) | 5/10 |
| 3 | 3 | +9 % | +61 % | 0 | 7.1 % (foodSupport) | 4/10 |
| 3 | 5 | +0 % | +59 % | 0 | 7.0 % (edgeBand) | 3/10 |
| 4 | 2 | +40 % | +153 % | 0 | 7.3 % (foodSupport) | 5/10 |
| 4 | 3 | +9 % | +86 % | 0 | 7.2 % (foodSupport) | 4/10 |
| 4 | 5 | +0 % | +83 % | 0 | 7.1 % (edgeBand) | 3/10 |
| 6 | 2 | +40 % | +153 % | 0 | 7.3 % (foodSupport) | 5/10 |
| 6 | 3 | +9 % | +86 % | 0 | 7.2 % (foodSupport) | 4/10 |
| 6 | 5 | +0 % | +83 % | 0 | 7.1 % (foodSupport) | 4/10 |

The roll capture grows from 0.49 % to 7.1 % of the frame at every setting — the roll's footprint in the photo — and its refit lands on the plate as `foodSupport` at floors 2 and 3. Floor 2 fails the 20 % bar (median +40 %; `1786844576261`, a well-segmented bread plate, grows 2.5×, which is plate noise admitted). Floor 3 passes (+9 %) and floor 5 adds nothing on the well-segmented plates but drops the roll's refit back to `edgeBand` at cliffs 3 and 4. Cliff has no effect on the median; it moves only the largest single addition (`1785135663727`, bread on a white plate, 12 % → 19 % at cliff 3 and → 23 % at 4 and 6). Without a truth mask that addition cannot be called food or leak, so the tighter cliff ships.

**Shipped: cliff 3 mm, floor 3 mm, cap 0.35.** The Req 8 rule's "largest cliff" clause is set aside for the outlier above; the rule's other clauses hold at 3/3. **Revised 2026-09-25 (Decision 3): floor 5 mm.** This sweep ran on a harness path that fitted the first plane from the argmax rather than the pre-shutter mask the device uses; on the device path floor 3 leaks a plate blob to the rim on both roll captures and floor 5 does not.

**The carb-MAE half, measured overnight 2026-09-24/25 on Nutrition5k.** `tools/nutrition5k/ingest.py --checkpoint` re-ingested with the shipped checkpoint (after fixing its 513×513 tensor size), giving 236 `single_dominant` plates with probability tensors and weighed carbs (BACKLOG 23 closed for this purpose). `HarnessCLI accuracy` over them, sliver 0.05, growth 3/3/0.35:

| growth | scored | carb MAE | MAPE | growth applied |
|---|---|---|---|---|
| off (cap 0) | 216 | 9.29 g | 92.0 % | 0 |
| on | 217 | 9.47 g | 99.7 % | 202 of 217 |

At commit `3022b80` growth raised carb MAE by 0.18 g and MAPE by 7.7 points, so the "carb MAE must not rise" clause failed on this corpus, narrowly; the table reproduces exactly with that commit's harness (re-run 2026-10-03). **It does not reproduce on the shipped pipeline.** At `abd9750`, cliff 3 / floor 5 / cap 0.35 / band 10, growth reads 9.18 g / 93.7 % over 217 scored plates against 9.33 g / 95.2 % over 216 without it — growth now lowers both. The floor and band are not why: floor 3 with no band reads 9.13 g / 93.2 % at `abd9750`. The pipeline changed between the two commits (Decision 3's table-refit guard among the changes); the cause was not bisected. N5k also cannot say whether the added region is food: 206 of the 216 plates read low without growth, so any added volume scores as an improvement. The gate this paragraph proposed — apply growth only when the segmenter found little — shipped on the weighed plates' evidence instead: Decision 5.

### Alternatives Considered

- **Height above the first plane only, no continuity**: A pixel is food when it sits more than h_min above the fitted plane - Rejected because the first plane was the table on the motivating capture, so the whole plate qualifies.
- **Continuity only during the fill, height floor only after the refit**: The first shipped draft - Rejected by the corpus sweep: the fill leaked or tripped the cap on all 10 captures at every setting (see Rationale).
- **Continuity gated on height above the first plane with no offset**: Rejected because on an `edgeBand` plane the whole plate is raised; the ring median is what places the support surface on the plate. The remaining inert case — a first plane admitted as `foodSupport` on a flat food's own top — is accepted: the estimate is then today's.
- **Refit the plane first, then grow by height**: Rejected because the first refit has only the seed mask and produced the same `edgeBand` fallback; growth is what gives the fitter a usable mask.
- **Rewrite the probability tensor for grown pixels**: Would let the integrator's silhouette test pass unchanged - Rejected because it fabricates model evidence that the candidate-evidence pass and σ_seg would then read; a silhouette override on the integrator is explicit and leaves the tensor honest.
- **One slab, one class (dominant seed takes the whole connected region)**: Cleaner for a single food the model labels with two bread classes - Rejected because two foods that touch without a cliff (rice against curry) would merge into one row; first arrival only extends each class and never removes one.
- **Retrain on roll data (myfoodrepo-bridge)**: Rejected for this change; it fixes one texture, takes hours to days before a device pass, and does not remove the under-read for the next unknown food.

### Consequences

**Positive:**
- A food the model only partly recognises is measured whole, and its review outline shows the whole food.
- The refit gives the plane fitter a mask around the real food, so `foodSupport` fits become reachable on captures that fell to `edgeBand`.
- Deterministic and offline; the bundle keeps the ungrown map so replay reproduces the result.

**Negative:**
- Two new constants set by hand until the corpus sweep (Decision 2) measures them.
- A gently sloped food can leak onto the plate up to the cap; below the cap the leak over-reads.
- Single-view numbers recorded before this change are not comparable with those after it.

### Impact

`Volume/FoodRegionGrowth.swift` (new), `HeightFieldEstimator.Inputs`, `Pipeline.estimate` single-view branch, `PipelineDiagnostics`, `FixtureRunner`, `HarnessCLI accuracy`.

---

## Decision 2: The corpus sweep gates the merge, and the shipped constants pass it

**Date**: 2026-09-25
**Status**: accepted

### Context

The merge of `research` into `main` is gated on a corpus sweep rather than on a device sitting: the device pass answers whether the roll is measured whole, and only a sweep answers whether the rule harms plates it should not touch. Decision 1's sweep was meant to be that gate, but Decision 3 found it had run on a divergent replay path — `FixtureRunner` fitted the first support plane from the argmax while the device fits it from the pre-shutter mask — so its table does not describe the shipped pipeline. Two constants have moved since as well: the floor rose to 5 mm and a table refit is never adopted (Decision 3), and a seed-relative band of 10 mm was added (Decision 4).

The gate was therefore standing on stale numbers. This entry replaces them with a sweep run on the corrected path over the corpus's single-view successes, including the 2026-09-24 and 2026-09-25 roll bundles that did not exist when Decision 1 was written.

### Decision

The corpus sweep, not the device pass, gates the merge of `research` into `main`, and its table lives in this entry. Re-run on the corrected replay path at commit `a785187`, the shipped constants — cliff 3 mm, floor 5 mm, cap 0.35, seed band 10 mm — **pass the Req 8 rule**, so the gate is met and the merge is unblocked on area. The carb cost measured against the corpus's weighed plates is recorded here as a known regression, not as a blocker.

### Rationale

Req 8's rule has three clauses and the shipped setting meets all three. On the 11 captures whose ungrown food-like area is at least 5 % of the frame, growth adds **+0.5 % at the median**, well inside the 20 % bar. The **cap trips on none** — and that is a measurement, not an inference: every setting that showed no growth was re-run at `--growth-cap 1.0` and still showed none, so the eight no-growth rows are cases where the fill found nothing, not cases where the cap discarded a fill. On `1790223818017-success` the region grows from 0.49 % to 7.45 % of the frame with a `foodSupport` refit, which is the roll's footprint in the photo, so the grown region covers the raised slab.

The rule's *selection* clause — "the largest cliff value and smallest floor that meet the rule ship" — does not name the shipped floor. Floor 3 with the band also passes (median +5.5 %), so read mechanically the rule selects floor 3 mm. The shipped floor is one notch above it, adopted in Decision 3 on device evidence (a contiguous plate blob to the rim on both 2026-09-25 roll captures). The corpus does not contradict that choice and supports it on the two figures the median hides: the largest single addition halves (+72 % at floor 3 against +36 % at floor 5), and the refit lands `foodSupport` on 13 of 19 bundles at floor 5 against 11 of 19 at floor 3, with 7 table refits at floor 3 that Decision 3's guard has to throw away. Floor 8 buys nothing over floor 5 on the median and costs the well-segmented plates volume. The band at 10 mm beats both 0 and 15 on every column.

What the sweep does **not** support is the claim that growth improves accuracy. On the three weighed plates in the corpus the carb mean absolute error **rises from 33.2 g ungrown to 40.4 g at the shipped setting**. Two of the three are under-reads that growth moves 0.1–1.8 g toward truth; the third (`1785901032716`, 80 g of multigrain bread) was already reading 3.2× over and growth adds 36 % more area and flips its plane from the table to a `foodSupport` refit, taking it from +74.5 g to +97.7 g of carbohydrate. That is the same direction as the Nutrition5k result recorded in Decision 1 and the same mechanism: on a plate the segmenter already covers, growth can only add area, and area on a plate whose plane is wrong is added error. The case growth exists for — a food the model barely recognises — has no weighed truth in the corpus at all. Growth is accepted on that asymmetry, with eyes open: it fixes a 4 g reading of a whole roll and it makes an already-bad flat-bread over-read worse.

### The sweep (re-run 2026-09-25, commit `a785187`)

**Route.** `HarnessCLI volumes`, one bundle per invocation, not `HarnessCLI accuracy`: device bundles record ground truth as zero, so `accuracy` reports every meal as UNSCORED and exits non-zero, and its loader holds a whole directory of ~200 MB bundles in memory at once. `volumes` reports the same growth diagnostics plus the per-class volumes and the plane the volume used. The binary was built from committed `HEAD` (`a785187`) in a scratch copy of the tree, because other agents were editing `MedataCore/Sources` and `HarnessCore/` while the sweep ran; the numbers therefore describe the committed path and nothing else.

**Corpus.** Every single-view LiDAR success stamped `ab812dc3aa9d`: 11 pre-2026-09-24 bundles plus `1790223818017` and `1790232681422` (2026-09-24) and the seven single-view bundles under `pulls/20260925-*/captures/`. 20 bundles, of which `1785125982524` refuses `noFoodVolumeRecovered` before and after growth, leaving 19 scored. Two exclusions recorded in Decision 1 are stale: `captures/1786450130307-success.fixture` is the truncated 170,000,000-byte copy, but `pulls/20260827-3/captures/1786450130307-success.fixture` is intact and loads; and `1785054950406` (the 208 g rice plate) now loads and replays at 636 cm³ rather than yielding zero meals.

Cliff 3 mm and cap 0.35 throughout. "Added" is the food-like pixel count after growth over before, on the 11 captures whose ungrown food-like area is at least 5 % of the frame (1920 × 1440).

| floor mm | band mm | median added | largest added | cap trips | roll `1790223818017` after (refit) | refits `foodSupport` / `edgeBand` / none |
|---|---|---|---|---|---|---|
| 3 | 0 | +32.9 % | +72 % | 0 | 7.69 % (foodSupport) | 11 / 7 / 1 |
| 3 | 10 | +5.5 % | +72 % | 0 | 7.66 % (foodSupport) | 11 / 7 / 1 |
| 3 | 15 | +11.2 % | +72 % | 0 | 7.69 % (foodSupport) | 11 / 7 / 1 |
| 5 | 0 | +11.7 % | +64 % | 0 | 7.45 % (foodSupport) | 13 / 3 / 3 |
| **5** | **10** | **+0.5 %** | **+36 %** | **0** | **7.45 % (foodSupport)** | **13 / 3 / 3** |
| 5 | 15 | +0.5 % | +51 % | 0 | 7.45 % (foodSupport) | 13 / 3 / 3 |
| 8 | 0 | +11.7 % | +60 % | 0 | 7.25 % (foodSupport) | 11 / 4 / 4 |
| 8 | 10 | +0.1 % | +34 % | 0 | 7.25 % (foodSupport) | 11 / 4 / 4 |
| 8 | 15 | +0.1 % | +52 % | 0 | 7.25 % (foodSupport) | 11 / 4 / 4 |

n = 19 scored on every row; the refit column counts the reference the refit returned, not the plane adopted — an `edgeBand` refit is never adopted (Decision 3), and "none" means the fill added nothing so no refit was attempted. The largest addition at floor 3 is `1786322188388` (+72 %, 9.55 % → 16.38 % of the frame, 51.5 → 172.3 cm³), which floor 5 removes entirely.

Per bundle at the shipped setting (cliff 3, floor 5, cap 0.35, band 10):

| bundle | ungrown px (% frame) | first fit | ungrown cm³ | after px (% frame) | refit | adopted plane | cm³ | added |
|---|---|---|---|---|---|---|---|---|
| 1785054950406 | 435,165 (15.74 %) | edgeBand | 636.1 | 435,165 (15.74 %) | none | edgeBand | 636.1 | +0 % |
| 1785055060603 | 447,855 (16.20 %) | edgeBand | 600.7 | 447,855 (16.20 %) | none | edgeBand | 600.7 | +0 % |
| 1785062411645 | 315,076 (11.40 %) | edgeBand | 1470.3 | 315,076 (11.40 %) | edgeBand | edgeBand | 1470.3 | +0 % |
| 1785125982524 | — | — | refuses `noFoodVolumeRecovered` | — | — | — | — | — |
| 1785135663727 | 332,859 (12.04 %) | edgeBand | 683.0 | 375,686 (13.59 %) | foodSupport | foodSupport | 672.8 | +13 % |
| 1785901032716 | 482,388 (17.45 %) | edgeBand | 713.8 | 654,111 (23.66 %) | foodSupport | foodSupport | 866.4 | +36 % |
| 1786322188388 | 263,919 (9.55 %) | edgeBand | 51.5 | 263,919 (9.55 %) | none | edgeBand | 51.5 | +0 % |
| 1786439141215 | 95,781 (3.46 %) | foodSupport | 72.5 | 115,055 (4.16 %) | foodSupport | foodSupport | 83.9 | +20 % |
| 1786450130307 | 271,669 (9.83 %) | foodSupport | 77.5 | 272,944 (9.87 %) | foodSupport | foodSupport | 78.0 | +0 % |
| 1786844576261 | 232,720 (8.42 %) | edgeBand | 188.9 | 233,416 (8.44 %) | edgeBand | edgeBand | 189.6 | +0 % |
| 1786845356405 | 79,785 (2.89 %) | edgeBand | 81.7 | 192,353 (6.96 %) | foodSupport | foodSupport | 85.7 | +141 % |
| 1790223818017 | 13,571 (0.49 %) | edgeBand | 25.6 | 205,945 (7.45 %) | foodSupport | foodSupport | 230.7 | +1418 % |
| 1790232681422 | 146,278 (5.29 %) | foodSupport | 261.6 | 152,460 (5.51 %) | foodSupport | foodSupport | 283.5 | +4 % |
| 1790242780378 | 341,043 (12.34 %) | edgeBand | 253.7 | 423,548 (15.32 %) | edgeBand | edgeBand | 308.6 | +24 % |
| 1790310107431 | 112,439 (4.07 %) | foodSupport | 176.9 | 155,916 (5.64 %) | foodSupport | foodSupport | 219.4 | +39 % |
| 1790313330330 | 185,281 (6.70 %) | foodSupport | 253.4 | 206,481 (7.47 %) | foodSupport | foodSupport | 274.6 | +11 % |
| 1790315865030 | 121,881 (4.41 %) | edgeBand | 388.6 | 137,871 (4.99 %) | foodSupport | foodSupport | 309.5 | +13 % |
| 1790315900185 | 88,513 (3.20 %) | edgeBand | 171.3 | 141,758 (5.13 %) | foodSupport | foodSupport | 298.9 | +60 % |
| 1790318604792 | 124,022 (4.49 %) | edgeBand | 393.0 | 144,120 (5.21 %) | foodSupport | foodSupport | 272.0 | +16 % |
| 1790318616477 | 126,823 (4.59 %) | edgeBand | 429.6 | 143,328 (5.18 %) | foodSupport | foodSupport | 266.9 | +13 % |

The three roll bundles that motivated Decisions 3 and 4 (`1790310107431`, `1790315865030`, `1790315900185`) reproduce those entries' figures exactly, which is the check that this sweep and those decisions ran the same path.

**Against weighed truth.** The corpus holds three weighed plates on the single-view path (`docs/agent-notes/field-truth-sessions.md`, the 2026-08-05 and 2026-08-11 sittings). Carbohydrate, ungrown against the shipped setting:

| bundle | truth | ungrown cm³ / carbs | shipped cm³ / carbs | carb error before → after |
|---|---|---|---|---|
| 1785901032716 (80 g multigrain, 2 slices) | 34 g | 713.8 / 108.5 g | 866.4 / 131.7 g | +74.5 g → **+97.7 g** |
| 1786439141215 (58 g bread slice) | 24 g | 72.5 / 11.0 g | 83.9 / 12.8 g | −13.0 g → **−11.2 g** |
| 1786450130307 (same slice, re-shoot) | 24 g | 77.5 / 11.8 g | 78.0 / 11.9 g | −12.2 g → **−12.1 g** |
| **mean absolute error** | | **33.2 g** | **40.4 g** | **+7.2 g** |

### Alternatives Considered

- **Re-run through `HarnessCLI accuracy`, as Decision 1 did**: The command Req 8 names - Rejected because field bundles carry zero ground truth, so it scores nothing and exits non-zero, and its loader holds every fixture in the directory in memory at once; `volumes` reports the same growth and plane diagnostics per bundle plus the volumes, one bundle per invocation.
- **Drop the floor to 3 mm, which Req 8's selection clause names**: The smallest floor that passes the rule - Rejected because it doubles the largest single addition (+72 % against +36 %), adds 121 cm³ to a plate the segmenter had already covered (`1786322188388`), and returns a table refit on 7 of 19 bundles that the Decision 3 guard then discards; Decision 3's device evidence against it stands.
- **Block the merge on the weighed-truth carb regression**: The gate could be read as covering accuracy - Rejected because Req 8's rule is about added area and cap trips, the regression is one plate whose ungrown reading was already 3.2× over, and the defect behind it is the support plane, not the growth pass (`specs/estimation/support-plane-reference`).
- **Ship without a sweep**: Rejected because a leak on well-segmented plates would over-read every meal silently — which is exactly what the floor-3 rows show.
- **Sweep before the 2026-09-24 device pass**: Rejected at the time as costing the sitting for a question the sitting could not answer; the sitting is also what produced three of the bundles this sweep measures.

### Consequences

**Positive:**
- The merge gate now rests on numbers from the shipped replay path, reproduced against the two decisions taken since Decision 1.
- The cap is measured, not assumed, to trip on nothing across the whole grid.
- Floor 5 with the 10 mm band is the best cell in the grid on every column the rule cares about, so the constants on the phone need not move.

**Negative:**
- Growth costs 7.2 g of carbohydrate mean absolute error on the corpus's three weighed plates, all of it on one flat-bread plate that already over-read 3.2×; the sweep buys confidence about area, not about accuracy.
- The founding case has no weighed truth, so the benefit side of that trade is still judged by eye.
- The shipped floor is not the value Req 8's selection clause mechanically names; it is one notch above, carried by device evidence the corpus can only corroborate.
- Cliff was not re-swept: Decision 1 found it moved only the largest single addition, and 3 mm ships.

### Impact

Unblocks the merge of `research` into `main` for `specs/estimation/depth-grown-food-region`. No code change: `FoodRegionGrowthConfig.standard` keeps cliff 3 mm, floor 5 mm, cap 0.35, seed band 10 mm.

---

## Decision 3: A table refit is never adopted; the floor is 5 mm; the harness fits the first plane the way the device does

**Date**: 2026-09-25
**Status**: accepted

### Context

The 2026-09-25 single-view capture of the roll (`1790310107431`) grew from 112,439 to 200,165 pixels and read 518.7 cm³ against 280 cm³ for the same roll the day before, with plate speckles visible around the roll in the review outline. Replaying it with the first plane fitted from the pre-shutter mask, as the device does, reproduced the row exactly. The added cells all carry full depth confidence; 459 of 1,197 sit 3–5 mm above the first (plate) plane, most of them a contiguous blob running to the plate rim, because the plate is not level with the fitted plane by that much. That blob is about 11 cm³. The rest of the excess came from the refit: on the grown mask the fitter returned an `edgeBand` plane, the table 19 mm below the plate, and the integrator measures from the adopted plane with no offset, so the whole footprint gained 19 mm. Keeping the first plane gives 247 cm³ from the same mask.

The harness replay had been fitting the first plane from the argmax rather than the pre-shutter mask, so Decision 1's sweep and the `volumes`/`accuracy` commands were not seeing what the device saw (yesterday's capture replays as 690 cm³ on that path against 280 on the device).

### Decision

A refit that references `edgeBand` is not adopted: `SupportPlaneFitOutcome.foodSupportPlane` is what `Pipeline` and `FixtureRunner` prune against and adopt, and a table refit keeps the first plane and its offset. `FoodRegionGrowthConfig.standard` floor rises from 3 mm to 5 mm. `FixtureRunner` fits the first plane from the fixture's pre-shutter mask when it carries one.

### Rationale

The integrator has no offset term, so an adopted plane must be the food's support surface; the first plane already is on a `foodSupport` fit, and on an `edgeBand` first fit the ring-median offset is applied by the growth pass, not the integrator, so adopting a second `edgeBand` plane can only add the plate height to every pixel. On the four bundles replayed on the device path the guard changes only the rows where the refit was `edgeBand` (519 → 247, and a mixed plate 459 → 322) and leaves every `foodSupport` row untouched. Floor 5 removes the plate blob on both roll captures (200k → 164k and 194k → 177k pixels) without flipping any refit on the device path; the earlier finding that floor 5 "drops the roll's refit to edgeBand" came from the divergent replay path and is moot under the guard anyway.

### Alternatives Considered

- **Offset an adopted `edgeBand` refit by its ring median**: Rejected for now; it would also change every `edgeBand` first fit's integration, which is the known flat-food over-read and a separate decision with the whole corpus behind it.
- **A seed-median height band for added cells**: Rejected; the crust foot and the plate blob share the 3–5 mm band, and it does nothing about the plane.
- **Leave the floor at 3 mm and rely on the guard**: Rejected; the outline the owner reviews still shows the plate blob, and the blob is real volume (about 11 cm³) on a capture judged good by eye at 280.

### Consequences

**Positive:**
- Today's capture replays at 224 cm³ and yesterday's at 302 cm³ with the outline on the roll.
- The harness sees the device's first plane, so sweeps and accuracy runs measure the shipped path.

**Negative:**
- The Decision 1 sweep numbers are from the divergent path and need re-running before the merge gate in Decision 2 is applied.
- A capture whose first fit is `edgeBand` and whose refit would have been a correct `foodSupport` plane is unaffected; one whose refit is `edgeBand` keeps a first plane that may itself be wrong. The guard removes a wrong adoption, it does not add a right one.

---

## Decision 4: Added cells must reach the seed cells' median height minus a 10 mm band

**Date**: 2026-09-25
**Status**: accepted

### Context

With Decision 3 shipped, two more single-view captures of the roll on the same plate (`1790315900185`, no card; `1790315865030`, card cleared) still grew onto the plate at floor 5 mm: 88,513 → 241,743 and 168,334 → 283,421 pixels, with the plate's far half highlighted as food and 410 and 434 cm³ against roughly 220–300 for the roll on the earlier captures. The added cells all carry full depth confidence and are contiguous with the roll; they are not noise. On `1790315900185` the first plane is an `edgeBand` fit tilted 4.2° from the flat-in-z table (raw depth 394–403 mm across the frame, plane height −36 → −3 mm left to right), threading the plate top beside the food (ring median 1.05 mm) and leaving the plate's far half 6–16 mm above it while the food sits 30 mm above it. On `1790315865030` the first plane matches gravity but the table's depth field is itself non-planar (2.1° on the left column, 4.9° on the right), so the plate's near half reads 3–12 mm above the ring-median support. Both refits are `foodSupport` but 4–5° off the first plane and 3–4 mm below the plate top, so the prune bounds nothing. No fixed floor separates a plate at 6–16 mm from a food at 30 mm.

### Decision

`FoodRegionGrowthConfig` gains `seedBandMm` (`.standard` = 10 mm, 0 = no band). `prune` drops an added cell whose height above the adopted support surface (plane + offset, the floor's own measure) is below the seed cells' median height minus the band; the seed cells are the segmenter's own, measured against the same surface. The floor test stays. `HarnessCLI` takes `--growth-band-mm`.

### Rationale

The band is food-relative: seeds and added cells are measured against the same surface, so a plane tilt or a warped depth field shifts both and cancels. On the seven single-view bundles it cuts both leaks (410 → 299, 434 → 317 cm³) and trims the three roll captures by 5–18 cm³ (crust foot below the band), and it leaves the founding case (`1790223818017`, seed 0.5 % of the frame) and the mixed plate untouched. Replay on the device path (pre-shutter first plane, table refit never adopted), cm³ total and pixels after growth:

| bundle | ungrown | before (band 0) | shipped (band 10) |
|---|---|---|---|
| 1790315900185 | 171 (88,513) | 410 (241,743) | **299** (141,758) |
| 1790315865030 | 393 (168,334) | 434 (283,421) | **317** (187,762) |
| 1790310107431 | 177 | 224 (163,504) | 219 (155,916) |
| 1790232681422 | 262 | 302 (176,971) | 284 (152,460) |
| 1790313330330 | 253 | 284 (231,796) | 275 (206,481) |
| 1790223818017 | 26 | 231 (205,945) | 231 (205,945) |
| 1790242780378 | 254 | 309 (423,548) | 309 (423,548) |

### Alternatives Considered

- **Floor 8 or 12 mm**: The plate reaches +16 mm above a tilted plane, so floor 8 leaves `1790315900185` at 351 cm³ and floor 12 at 260 with the crust foot gone; floor 8 also flips `1790315865030`'s refit back to the table (447 cm³) and floor 12 flips `1790223818017` to the table (421 cm³). Rejected.
- **Cap the added area relative to the seed (≤ 1.5×)**: Kills the founding case (`1790223818017` grows 15×, 231 → 26 cm³) and misses `1790315865030` (0.68×). Rejected.
- **Reject a refit or first plane whose ring median is below −0.5 mm**: Good `foodSupport` refits read −1 to −2 mm; the check rejected them on `1790223818017` (231 → 438), `1790315865030` (434 → 580) and `1790310107431` (224 → 239) and passed the −0.36 refit it was meant to catch. Rejected.

### Consequences

**Positive:**
- Both 2026-09-25 afternoon captures replay with the outline on the roll and the volume in the range of the earlier captures.
- The band is one constant on the existing config; `prune`'s signature and every call site are unchanged.

**Negative:**
- The real defect stays open: the first plane can sit 4–5° off the table (`edgeBand` threading plate top and table on `1790315900185`) or match gravity over a depth field that is not planar (`1790315865030`). The band hides the plate from growth; the integrator still measures every pixel against that plane.
- A food whose crust foot is more than 10 mm below its median height loses that foot (5–18 cm³ on the roll captures here).
- The band needs seed cells with depth; a seed with no finite depth leaves the band inert and the floor alone applies.

---

## Decision 5: Growth applies only when the segmenter's own footprint is at most 200 cm²

**Date**: 2026-10-03
**Status**: accepted

### Context

Decision 2 recorded growth as a carbohydrate regression on the corpus's weighed single-view plates: mean absolute error 33.2 g without it, 40.4 g with it, all of the rise on `1785901032716` (two slices of multigrain, 80 g, 34 g of carbohydrate), which already read 3.2× over and went from +74.5 g to +97.7 g. Decision 1's overnight addendum measured a smaller cost on Nutrition5k and proposed the remedy this entry takes up: grow only when the segmenter found little. Two things have changed since. The roll the feature was built for was weighed on 2026-09-29 (104 g, 39.52 g of carbohydrate, 260 cm³ at the measured 0.4 g/cm³; `benchmark_meals` row `backfill-1790655037216-roll`), and its bundle `1790655022746` is kept in `medata-corpus/reports/calibration-20260929-roll/`. And the Nutrition5k cost no longer reproduces at `HEAD` (Decision 1, addendum).

The gate needs a quantity that means the same on every camera. The fraction of the frame does not: the same 58 g slice fills 3.5 % of the frame from 400 mm and 9.8 % from 273 mm, and a Nutrition5k frame (640 × 480 from a fixed rig) is not an iPhone frame. The single-view path always has a support plane when growth runs, so the footprint on it is available in cm².

### Decision

Before growth, measure the footprint of the segmenter's food-like pixels on the first support plane (`FoodRegionGrowth.foodAreaCm2`: each pixel's ray meets the plane at range α and covers α²·cos³θ / (fx·fy·|n̂·r̂|) of it). On the single-view path, when that footprint exceeds `FoodRegionGrowthConfig.standardSeedAreaGateCm2` = **200 cm²**, nothing grows and nothing is refit: the estimate is exactly the ungrown one. The two-view branch, which uses growth only to fit its plane (two-view-trust Decision 10), is never gated. Every outcome row carries `regionGrowth.seedAreaCm2`, `seedAreaGateCm2` and `gated`, and `event=region.grow` prints `seedAreaCm2=`, `gateCm2=` and `gated=`.

### Rationale

Every capture with truth that growth improved sits at or below about 145 cm² of seed; the one it made worse sits at 330 cm². The weighed roll's seed is 25 cm² (growth: −31.9 g → −5.1 g); the 58 g slice's two captures are 86 and 112 cm² (−13.0 → −11.2 g and −12.2 → −12.1 g); the multigrain plate is 330 cm² (+74.5 → +97.7 g). The same roll's eight 2026-09-24/25 single-view captures, measured in Decision 2 before their bundles were discarded, read 105.7 cm³ mean absolute error ungrown and 26.9 cm³ grown against the 260 cm³ the roll weighs (16.1 g → 4.1 g of carbohydrate); their seeds are 94–102 cm² on the three with a card in frame (card scale from the outcome rows) and an estimated 10–143 cm² on the other five (pixel counts at the 2026-09-29 capture's scale; their distances were not recorded). Any gate between about 145 and 330 cm² keeps all of those and removes the regression; 200 sits inside that gap and is about the footprint of two bread slices side by side. Nutrition5k cannot pick a value inside it — every gate from 175 cm² up scores identically to no gate — and it only rules out gates low enough to switch growth off on its plates.

Growth off by default loses to both: on Nutrition5k (9.33 g against 9.22 g), on the four weighed plates (32.9 g against 31.6 g ungated and 25.8 g gated), and on the roll's historical captures by a factor of four.

### The sweep (2026-10-03, `abd9750`)

**Route.** Nutrition5k: the 236 `single_dominant` fixtures of `tmp/n5k_fixtures_ckpt` (selected by their `estimator_path` stamp), `HarnessCLI accuracy` once with growth and once with `--growth-cap 0`, sliver 0.05 and every other constant as shipped. The gate is a function of the ungrown footprint only and gating yields exactly the ungrown estimate, so each threshold is the per-plate choice between those two runs; scored on the 216 plates both runs score. The 200 cm² row was then re-run for real with `--growth-gate-cm2 200` and matches (216-plate MAE 9.215 g, MAPE 93.67 %; 217 scored, 20 gated, three of which growth had changed). Weighed plates: `HarnessCLI volumes` on the bundles in `tmp/device_captures/` and the preserved roll bundle, carbohydrate as volume × 0.4 g/cm³ × 38 g/100 g (bread_wholemeal, which all four are). The roll replays as `unknown_food` (0 g) plus a phantom `coffee` region the developer rejected on the device; it is scored as its `unknown_food` volume under the class the developer named, without the phantom. Its replay matches the device row exactly (226.3 cm³ grown).

| gate cm² | N5k carb MAE (216) | N5k MAPE | N5k plates that grow | weighed ×3 MAE / MAPE | weighed ×4 (with the roll) MAE / MAPE |
|---|---|---|---|---|---|
| growth off | 9.334 g | 95.22 % | 0 | 33.2 g / 108.0 % | 32.9 g / 101.2 % |
| 20 | 9.329 g | 95.05 % | 2 | 33.2 g / 108.0 % | 32.9 g / 101.2 % |
| 50 | 9.267 g | 94.55 % | 76 | 33.2 g / 108.0 % | 26.2 g / 84.3 % |
| 100 | 9.224 g | 93.48 % | 149 | 32.7 g / 105.6 % | 25.8 g / 82.5 % |
| 150 | 9.217 g | 93.79 % | 179 | 32.6 g / 105.5 % | 25.8 g / 82.4 % |
| **200** | **9.215 g** | **93.67 %** | **182** | **32.6 g / 105.5 %** | **25.8 g / 82.4 %** |
| 250–300 | 9.215 g | 93.67 % | 183 | 32.6 g / 105.5 % | 25.8 g / 82.4 % |
| 400, or no gate | 9.215 g | 93.67 % | 185 | 40.4 g / 128.3 % | 31.6 g / 99.4 % |

Nutrition5k seeds run 13–380 cm² (median 70.5). Per weighed plate:

| bundle | truth | seed on first plane | growth off | growth on | gate 200 |
|---|---|---|---|---|---|
| `1785901032716` (80 g multigrain, 2 slices) | 34 g | 330.1 cm² | 108.5 g (+74.5) | 131.7 g (+97.7) | 108.5 g (+74.5), gated |
| `1786439141215` (58 g slice) | 24 g | 86.1 cm² | 11.0 g (−13.0) | 12.8 g (−11.2) | 12.8 g (−11.2) |
| `1786450130307` (same slice) | 24 g | 112.1 cm² | 11.8 g (−12.2) | 11.9 g (−12.1) | 11.9 g (−12.1) |
| `1790655022746` (104 g roll) | 39.52 g | 25.1 cm² | 7.6 g (−31.9); 49.8 cm³ | 34.4 g (−5.1); 226.3 cm³ | 34.4 g (−5.1) |

The 208 g rice plate (`1785054950406`) has a 302.3 cm² seed and growth adds nothing to it, so it reads the same in every row and is left out, as in Decision 2.

### Alternatives Considered

- **Growth off by default behind a developer switch**: The simpler remedy - Rejected because it loses to growth on every corpus measured (above), most of all on the roll it exists for; there is also no growth switch in `DeveloperFlags` to put it behind, so it would be new code too.
- **Gate on the fraction of the frame**: What the overnight addendum named - Rejected because it depends on camera distance (one slice reads 3.5 % and 9.8 %) and cannot be carried between the Nutrition5k rig and the phone; cm² on the plane is the same quantity on both.
- **Gate on how much growth adds relative to the seed**: Apply only when the segmenter found a small fraction of the raised region - Rejected because the roll's largest gains came from captures that grew only 1.1–1.2× (`1790318604792`: 124k → 144k pixels, 393 → 272 cm³); the gain there is the refit plane, not the area, and a ratio gate removes exactly those.
- **No gate; keep accepting the regression (Decision 2)**: Rejected because the gate costs nothing measurable on Nutrition5k or on any capture with truth and removes the one regression measured.
- **Fix the plane on the multigrain plate instead**: Its 3.2× over-read is the 26 mm table plane (support-plane-reference) - Not an alternative to the gate so much as the real fix for that plate; the gate does not preclude it.

### Consequences

**Positive:**
- The only measured growth regression is gone: weighed MAE 25.8 g against 31.6 g ungated (four plates) and 32.6 g against 40.4 g (the three of Decision 2).
- Nutrition5k is unchanged against ungated growth, and growth still applies to 182 of its 185 growing plates.
- A field pull now shows, per capture, the seed footprint, the gate and whether it applied.

**Negative:**
- The harmful side of the gate rests on one plate. Where it sits inside the 145–330 cm² gap is judgement, not a fit.
- A large food the segmenter only partly recognises (more than 200 cm² of seed) will not grow, and a gated capture also loses the refit — on the roll's card captures the refit's plane, not the added area, was the gain.
- Five of the eight historical roll seeds are estimated from pixel counts, not measured; the bundles are gone.
- The gate has not been on the phone. Its first field pulls should confirm `gated=false` on single foods and read `seedAreaCm2` against the footprint expected.

### Impact

`Volume/FoodRegionGrowth.swift` (`foodAreaCm2`, `seedAreaGateCm2`, `standardSeedAreaGateCm2`), `Volume/GrownRegionPlaneRefit.swift` (`gateBySeedArea`, `seedAreaCm2`, `gated`), `Pipeline.refitPlaneFromGrownRegion` (gated when `planeOnly` is false), `PipelineDiagnostics.RegionGrowthMeasurements`, `HarnessCore/FixtureRunner` (single-view replay gated), `MealCalibrationInput.RegionGrowth`, `HarnessCLI` (`--growth-gate-cm2`; the growth line and `volumes` rows print the seed area and the gate). The two-view branch, `CarveResidualAudit` and the LiDAR plane fit are unchanged.

---

## Decision 6: No second guard against growth; the toast over-read is not runaway growth

**Date**: 2026-10-03
**Status**: accepted

### Context

The 2026-10-03 replay of the weighed set (`docs/agent-notes/field-truth-sessions.md`, that day's entry) put the 83 g toast plate `1790748465041` (outcome `BF8BECC2`, build `2d39910`) at +105 % in mass at the true class. Growth took the segmenter's 43,039 px (27.8 cm² on the first plane) to 317,062 px, 7.4×, and the plate read bread_wholemeal 300.9 cm³ + `unknown_food` 125.0 cm³ = 426.0 cm³, which is 170.4 g at 0.4 g/cm³ against 83 g. Ungrown it reads 61.4 cm³ (−70 %). The seed is far under Decision 5's 200 cm² gate, so the gate let growth run. On the 104 g roll (`1790655022746`) growth goes 25.1 → 98.8 cm² (3.9×) and reads −13 %.

The working reading was that growth had spread over the plate, and that a second guard on how far growth spreads would separate the two plates: a cap on the ratio of grown to seed area, or on the grown footprint in cm², either falling back to the ungrown region or clamping the fill at the cap.

### Decision

Ship no second guard. The growth stage, `FoodRegionGrowthConfig.standard` and Decision 5's seed-area gate are unchanged. The toast's grown region is the toast, and its over-read comes from things growth does not control: the plate under the toast and the density.

### Rationale

**No variant beats the current state on both sets.** The only variants that leave Nutrition5k as it is are the ones that do nothing there: no Nutrition5k plate grows more than 2.64×, so a ratio fall-back from 3× up and a 6× clamp change no plate. Every footprint cap and every clamp that binds costs Nutrition5k mean absolute error or MAPE, and the 2× and 3× clamps take the 104 g roll out of ±20 % (−50.8 %, −27.1 %). The 150 cm² clamp lowers MAE by 0.004 g on 10 plates and raises MAPE by 0.08 points, which is noise either way. That leaves the ratio fall-back at 4–6×: Nutrition5k unchanged, rolls unchanged, toast +105 % → −70 %.

**The grown region is the toast.** Rendered against the bundle's own LiDAR depth, the segmenter labelled only the crust ends of two slices of toast. Measured from the board (the dominant plane), the depth shows the slices as two slabs 18–25 mm high, the plate between them 1–4 mm, and the plate rim 8–11 mm. The depth cells at least 12 mm above the board cover 207 cm² and hold 415 cm³. Growth's region is 205.2 cm² on the first plane and 426.0 cm³. Growth found the two slices and no plate. It is the case growth exists for: a food the segmenter partly recognised, with the depth showing all of it. The 104 g roll has the same shape at 3.9×, three seed blobs on a roll the depth shows whole. The ratio measures how much of the food the segmenter missed. It does not measure leaks.

**What the +105 % is.** Two parts, and growth controls neither. The plane is the board (`edgeBand`), and the refit from the grown mask also returned `edgeBand`, so Decision 3 kept it. The integrator measures from that plane, so every toast pixel carries the plate under it: 205 cm² × 1–4 mm = 20–80 cm³. The fitter's ring median (11.4 mm) is the rim, not the surface under the toast, so subtracting it would over-correct. The rest is 345–405 cm³ of toast against 83 g, which is 0.20–0.24 g/cm³: thick slices of toasted open-crumb bread, against the 0.4 g/cm³ that bread_wholemeal carries (measured on the roll). That density is inferred from this one plate, not measured. But the depth's own volume is far above the 207.5 cm³ that 0.4 g/cm³ implies, and the depth is not where the error is.

**So a guard would fix the toast by breaking its measurement.** The 4–6× fall-back improves the toast only by going back to the crust-only reading. That reading covers 13.6 % of the toast's footprint and swaps a +105 % over-read for a −70 % under-read. It scores better only because the two errors are compared as absolute values. Once the density or the plane is right for this plate, the grown reading is the closer one, and the guard would hold the plate at −70 %. The clamps cut a footprint that is correct, by distance from the crust seeds, which means the middle of each slice.

**And the ratio guard removes the case growth was built for.** On 2026-09-24, `1790223818017` grew 15.2× (13,571 → 205,945 px) and went from 25.6 to 230.7 cm³ against the roll's 260 cm³ (Decision 2). Every ratio cap from 2× to 15× falls back on it. Over the roll's eight 2026-09-24/25 single-view captures, volume mean absolute error would double, from 26.9 to 52.6 cm³ (10.8 → 21.0 g). A k× clamp would keep about k/15 of that roll. Its bundle is gone, so it is not in the replay tables, but these figures were measured at the time.

**And a footprint cap is a statement about plate size, not about leaks.** Any value under 205 cm² cuts the toast. 200 cm² sits 2.6 % under the toast, and Decision 5 chose 200 as "about two bread slices side by side". A cap there means that any partly recognised food bigger than two slices reads at the segmenter's footprint.

### The sweep (2026-10-03, `2a6f2b8`)

**Route.** `HarnessCLI` was a release build of `2a6f2b8`. Nutrition5k: the 236 `single_dominant` fixtures of `tmp/n5k_fixtures_ckpt`, with `accuracy` run once at the shipped constants (gate 200) and once with `--growth-cap 0`, sliver 0.05. They are scored on the 216 plates both runs score. A fall-back returns exactly the ungrown estimate, so each fall-back row is the per-plate choice between those two runs. The grown footprint (`foodAreaCm2` of the pruned map on the first plane) comes from a scratch build that matched the committed binary to 0.0 g on all 231 rows. The clamp rows are real runs of that scratch build: the fill stops when the labelled depth cells reach k × the seed cells, or the cm² cap scaled by seed cells per seed cm². The clamp counts depth cells, so the final pixel ratio and footprint run above the nominal value (toast: 2× → 2.82×, 100 cm² → 131 cm²). The scratch build was not committed. Weighed set: `volumes`. Mass at the true class is the kept regions × 0.4 g/cm³, kept as the review kept them: the roll without its phantom `coffee`, the 80 g roll `…654696` without its `white_rice`, and both toast regions.

Nutrition5k (216 plates; 182 grow at the current state):

| variant | carb MAE | MAPE | plates changed vs current |
|---|---|---|---|
| growth off | 9.334 g | 95.22 % | 182 |
| **current (seed-area gate 200 cm²)** | **9.215 g** | **93.67 %** | — |
| fall back, ratio > 2× | 9.249 g | 94.72 % | 5 |
| fall back, ratio > 3×, 4×, 5×, 6× (up to 16×) | 9.215 g | 93.67 % | 0 |
| fall back, grown > 100 cm² | 9.261 g | 94.58 % | 39 |
| fall back, grown > 150 cm² | 9.248 g | 94.67 % | 11 |
| fall back, grown > 175 cm² | 9.225 g | 94.03 % | 4 |
| fall back, grown > 200 cm² | 9.217 g | 93.79 % | 3 |
| fall back, grown > 250 cm² | 9.215 g | 93.67 % | 0 |
| clamp at 2× seed | 9.205 g | 93.60 % | 5 |
| clamp at 3× | 9.222 g | 93.78 % | 1 |
| clamp at 4× | 9.242 g | 94.11 % | 1 |
| clamp at 5× | 9.262 g | 94.45 % | 1 |
| clamp at 6× | 9.215 g | 93.67 % | 0 |
| clamp at 100 cm² | 9.239 g | 93.99 % | 33 |
| clamp at 150 cm² | 9.211 g | 93.75 % | 10 |
| clamp at 200 cm² | 9.224 g | 93.84 % | 2 |

On the growing plates the ratio has a median of 1.02×, a 90th percentile of 1.09× and a maximum of 2.64×. The grown footprint has a median of 68.1 cm², a 90th percentile of 121.7 cm² and a maximum of 219.0 cm². Nutrition5k reads low on 206 of its 216 plates, so it cannot say whether an added region is food.

Weighed set, mass at the true class against the scale. Ratio and footprint at the current state: 104 g roll 3.92× / 98.8 cm²; toast 7.37× / 205.2 cm²; 80 g roll a gated (seed 259.8 cm²); 80 g roll b 1.06× / 80.1 cm²; the two-view capture's growth is plane-only and never gated.

| variant | 104 g roll `…022746` | 83 g toast `…465041` | 80 g roll a `…654696` | 80 g roll b `…735795` | 80 g roll two-view `…787903` | MAE / MAPE (5) |
|---|---|---|---|---|---|---|
| growth off | −80.8 % | −70.4 % | +0.8 % | +14.2 % | +12.1 % | 32.8 g / 35.7 % |
| **current** | **−13.0 %** | **+105.3 %** | **+0.8 %** | **+18.4 %** | **+12.1 %** | **25.2 g / 29.9 %** |
| fall back, ratio > 2× or 3× | −80.8 % | −70.4 % | +0.8 % | +18.4 % | +12.1 % | 33.5 g / 36.5 % |
| fall back, ratio > 4×, 5× or 6× | −13.0 % | −70.4 % | +0.8 % | +18.4 % | +12.1 % | 19.4 g / 22.9 % |
| fall back, grown > 100, 150 or 200 cm² | −13.0 % | −70.4 % | +0.8 % | +18.4 % | +12.1 % | 19.4 g / 22.9 % |
| clamp at 2× seed | −50.8 % | −19.7 % | +0.8 % | +18.4 % | +12.1 % | 18.8 g / 20.4 % |
| clamp at 3× | −27.1 % | +12.4 % | +0.8 % | +18.4 % | +12.1 % | 12.7 g / 14.2 % |
| clamp at 4× | −13.0 % | +46.4 % | +0.8 % | +18.4 % | +12.1 % | 15.4 g / 18.1 % |
| clamp at 5× | −13.0 % | +78.6 % | +0.8 % | +18.4 % | +12.1 % | 20.8 g / 24.6 % |
| clamp at 6× | −13.0 % | +105.3 % | +0.8 % | +18.4 % | +12.1 % | 25.2 g / 29.9 % |
| clamp at 100 cm² | −13.0 % | +32.4 % | +0.8 % | +18.4 % | +12.1 % | 13.1 g / 15.3 % |
| clamp at 150 cm² | −13.0 % | +90.8 % | +0.8 % | +18.4 % | +12.1 % | 22.8 g / 27.0 % |
| clamp at 200 cm² | −13.0 % | +105.3 % | +0.8 % | +18.4 % | +12.1 % | 25.2 g / 29.9 % |

Decision 5's three older plates barely move. The multigrain plate is gated, and the 58 g slice grows 1.0–1.2×. Only the 100 cm² footprint rows touch them: the fall-back drops slice a's growth (103.4 cm² grown), and the clamp trims slice b by 0.2 g.

### Alternatives Considered

- **Ratio fall-back at 4–6×**: Fall back to the ungrown region when the pruned map is more than k times the seed - Rejected because it is a no-op on Nutrition5k and gains on the toast only by discarding 86 % of a correctly found footprint, and it would have discarded the 15.2× founding roll capture (25.6 against 230.7 cm³ for a 260 cm³ roll).
- **Grown-footprint fall-back at 150–200 cm²**: Fall back when the grown region covers more than A cm² - Rejected because it costs Nutrition5k at every value that cuts the toast (9.217–9.261 g), and it caps the size of food growth may find rather than detecting a leak.
- **Clamp the fill at the cap (ratio or cm²)**: Stop the fill when it reaches the cap and keep the partial region - Rejected because the values that help the toast either push the roll out of ±20 % (2×, 3×) or cost Nutrition5k (4×, 5×, 100 cm²). The partial region is set by distance from wherever the segmenter happened to fire, so whatever it gains on the toast comes from offsetting a density error by chance.
- **Measure grown pixels from the support surface (plane + ring median) on an `edgeBand` plane**: Removes the plate under the toast - Not taken here. It is a change to what every `edgeBand` volume measures (160 of 231 Nutrition5k fits), and here the ring median is the rim (11.4 mm), not the 1–4 mm surface under the toast. It belongs to `support-plane-reference`.

### Consequences

**Positive:**
- Growth keeps the founding case (15.2×) and the toast's correct footprint. The review outline on the toast still covers both slices.
- No new constant whose value rests on one plate.
- The field-truth reading is corrected: the toast is a density and plane case, not "flat food on a raised plate" defeating growth.

**Negative:**
- The toast keeps reading +105 % until the density for toasted bread or the plane under it is addressed. The five-capture MAE stays at 25.2 g where a 4–6× ratio guard would show 19.4 g.
- The density split (0.20–0.24 g/cm³) is inferred from one plate's mass and depth, not measured. The plate height under the toast comes from a narrow gap between the slices, where LiDAR smoothing may read low.
- The strongest case against the ratio guard is a capture whose bundle was discarded. Its numbers are from Decision 2, not from this replay.
- Growth still has no guard against a real leak beyond the 0.35 frame cap. No weighed or Nutrition5k plate shows one at the current constants.

### Impact

No code change. `FoodRegionGrowth`, `GrownRegionPlaneRefit`, the pipeline, the harness and the outcome schema are as Decision 5 left them. The follow-ups are elsewhere: a density for toasted bread (food database or class), and the plane under food on an `edgeBand` fit (`specs/estimation/support-plane-reference`).

---
