# Decision Log: Depth-Grown Food Region

## Decision 1: Grow by depth continuity from the segmenter's seeds, then refit the plane

**Date**: 2026-09-24
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

**Shipped: cliff 3 mm, floor 3 mm, cap 0.35.** The Req 8 rule's "largest cliff" clause is set aside for the outlier above; the rule's other clauses hold at 3/3.

**The carb-MAE half, measured overnight 2026-09-24/25 on Nutrition5k.** `tools/nutrition5k/ingest.py --checkpoint` re-ingested with the shipped checkpoint (after fixing its 513×513 tensor size), giving 236 `single_dominant` plates with probability tensors and weighed carbs (BACKLOG 23 closed for this purpose). `HarnessCLI accuracy` over them, sliver 0.05, growth 3/3/0.35:

| growth | scored | carb MAE | MAPE | growth applied |
|---|---|---|---|---|
| off (cap 0) | 216 | 9.29 g | 92.0 % | 0 |
| on | 217 | 9.47 g | 99.7 % | 202 of 217 |

Growth raises carb MAE by 0.18 g and MAPE by 7.7 points, so the "carb MAE must not rise" clause **fails on this corpus**, narrowly. The reading: N5k plates are mixed dishes in which the model labels one dominant class; growth extends that class over neighbouring foods the model left as background, which is the adjacent-foods-without-a-cliff risk the smolspec names. The sesame-roll case (one food, mostly unrecognised) is the opposite regime. Options for the 2026-09-25 decision: gate growth on the plate's ungrown food-like area (apply only when the segmenter found little), cap the added area relative to the seed, or accept the N5k cost as the price of not reading 4 g for a roll. Not changed tonight; the shipped constants stand pending that call.

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

## Decision 2: The constants are set by a corpus sweep that gates the merge to main, not the device pass

**Date**: 2026-09-24
**Status**: accepted

### Context

The developer is running an on-device loop and wants the fix on the phone today. The corpus holds 144 captures with depth, enough to measure how often growth adds area on already well-segmented plates (where it should add little), how often the cap trips, and whether 4 mm cuts real food. That measurement takes a harness run, not a device sitting.

### Decision

Ship the starting constants (cliff 4 mm, cap 0.35) for the device pass. The sweep over the corpus captures runs as its own task, its table is appended to Decision 1, and the merge of `research` into `main` waits on it. This mirrors unknown-food-nameable Decision 4.

### Rationale

The device pass answers whether the roll is measured whole; the sweep answers whether the rule harms plates it should not touch. Neither answer needs the other first, and sequencing the sweep before the device pass would cost the sitting.

### Alternatives Considered

- **Sweep first**: Rejected as costing the sitting for a question the sitting cannot answer.
- **Ship without a sweep**: Rejected because a leak on well-segmented plates would over-read every meal silently.

### Consequences

**Positive:**
- The device loop keeps moving; the evidence still lands before main.

**Negative:**
- The constants on the phone today may move after the sweep.

---
