# Decision Log: Depth-Grown Food Region

## Decision 1: Grow by depth continuity from the segmenter's seeds, then refit the plane

**Date**: 2026-09-24
**Status**: accepted

### Context

The sesame-roll captures of 2026-09-23 and 2026-09-24 show the segmenter labelling a few percent of a food it does not know, while LiDAR shows the whole food as one raised slab. Volume is integrated per pixel of the label map, so the record under-reads by the fraction the model missed. A retrain fixes one texture; the geometry fix applies to any partly recognised food.

The first support-plane fit on the single-view path runs before segmentation, from the pre-shutter mask (Pipeline stage D). On the 14:23:38 capture it fell back to `edgeBand` (the table, ring median 19.7 mm), because the contact ring around the two specks lay on the roll's own top. Any criterion that reads "raised above the plane" therefore includes the entire plate on this capture.

### Decision

Seeds are the food-like pixels of the regularised label map. The region grows on the depth grid by multi-source breadth-first fill through 4-neighbour steps with |Δz| ≤ 4 mm and confidence ≥ `tauConfidence`; first arrival labels a cell. Growth that exceeds 0.35 of the frame is discarded. When growth changed the map, the plane is refit with the grown region as the food mask; the grown region is then pruned to the cells at least 3 mm above the refit plane (the first plane when the refit refuses), and the refit plane and the metric scale derived from it are used when the pruned region still has added pixels. Order: grow, refit, prune.

### Rationale

Continuity is what LiDAR resolves best on a nadir view: the roll's edge is a 20–40 mm drop over one or two depth pixels, while the plate is a smooth gradient. The height floor is applied after the refit rather than during the fill because the first plane is fitted from the pre-shutter mask: when that mask is a speck on a flat-topped food the contact ring lies on the food and the plane is the food's own top, so measured against it nothing is raised and a fill gated on height would be inert on the capture the pass exists for (the replay test's synthetic disc reproduces this: first fit `edgeBand` at the food top, refit `foodSupport` on the plate). Continuity finds the slab without a plane, the refit puts the ring on the plate, and the prune removes what the fill reached that is not raised above it. On an `edgeBand` fit the floor cannot bound a leak, because the plate sits 19.7 mm above that plane; the cliff does. On a `foodSupport` fit the floor is what drops plate pixels that sit above the plane by fit noise (residual 1.5–1.8 mm here), which is why it is 3 mm rather than 0. Refitting with the grown region moves the contact ring off the food and onto the plate, which is the fit the support-plane-reference spec wants and the one this capture did not get. The cap is a coarse stop for the case where the fill runs over the whole plate; the corpus sweep (Decision 2) decides whether it and the cliff value are right.

### Alternatives Considered

- **Height above the first plane only, no continuity**: A pixel is food when it sits more than h_min above the fitted plane - Rejected because the first plane was the table on the motivating capture, so the whole plate qualifies.
- **Continuity gated on height above the first plane during the fill**: The first draft of this decision - Rejected because a first plane on a flat food's top makes the fill inert (see Rationale); the prune after the refit keeps the floor's protection without that failure.
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
