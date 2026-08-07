# Decision Log: Meal Review

## Decision 1: Split the work into one spec and two amendments

**Date**: 2026-08-05
**Status**: accepted

### Context

The originating request covered six things: a merged post-capture review surface, per-item add/remove by serving or grams, correcting a wrongly classified region, recording those errors for later debugging, tidying the capture screen's visuals, and removing the summary cards from the Graph page. `specs/PROCESS.md` §3 states that "a capability that needs two unrelated acceptance bars is two specs", and separately that an item which "refines or grows an existing capability and shares its acceptance bar" is an extension to that spec rather than a new folder.

The capture-chrome tidy refines `ui/design-handoff-00` §2, which already enumerates the exact chrome inventory. The Graph card removal contradicts `ui/design-handoff-00` Req 10.5, its `copy-inventory.md` line 117, and `regression-suggestion-integration` PRD App Req 9.

### Decision

One new spec folder, `specs/ui/meal-review/`, covering the review surface, region correction, amount adjustment and correction data. The capture-chrome tidy and the Graph card removal are handled as amendments to their owning specs, each with its own decision-log entry, not as new folders.

### Rationale

The three pieces have unrelated acceptance bars: a measurable interaction-cost bar for the review surface, a subjective visual bar for the capture chrome, and a pure removal for the Graph cards. Bundling them behind one set of approval gates would block a thirty-five-line deletion behind the largest piece of UI work in the backlog. PROCESS §3 also forbids naming a spec after an effort or phase, which rules out a folder named for the removal.

### Alternatives Considered

- **One spec covering all six themes**: Matches how the work was described - Rejected because it bundles unrelated acceptance bars and gates the smallest change behind the largest.
- **Three new spec folders**: Gives each piece its own gates - Rejected because two of the three are extensions under PROCESS §3, and a folder named for a deletion violates the naming rule.
- **Six separate specs, one per theme**: Maximum separation - Rejected as spec proliferation; the review surface, region correction and correction data share one acceptance bar and belong together.

### Consequences

**Positive:**
- The Graph card removal can land without waiting on the review redesign.
- Each superseded requirement is amended in the document that owns it, so the spec set holds one answer.
- Folder naming stays inside the PROCESS §3 convention.

**Negative:**
- Three pieces of work to track instead of one.
- Amending a spec marked Done (`design-handoff-00`) is less visible than a new folder, and relies on the decision log to record why.

---

## Decision 2: Merge the segmentation review and result screens

**Date**: 2026-08-05
**Status**: accepted

### Context

The post-capture flow currently has two screens. `SegmentationReviewView` shows the photo with per-class mask overlays and a read-only class list; its overlay is explicitly non-interactive and its sole action advances to `ResultView`. `ResultView` carries the per-food serving steppers, plate-fraction control and gram editor, but shows the meal only as a 64 pt thumbnail with no regions.

The screen that shows which region the model assigned to which food is the one that permits no editing; the screen that permits editing does not show the regions. The intermediate action is a pure pass-through with no other function.

### Decision

Collapse both into one review surface showing the photo, the outlined regions, the total and the editable food rows together. No intermediate screen between estimation completing and the review surface.

### Rationale

Correcting a region requires seeing the region and the value it produces at the same time. Splitting them means the user forms a judgement on one screen and acts on another, from memory. Removing the pass-through also reclaims a mandatory tap on every single capture, which is the cheapest part of the interaction-cost target in Req 8.

### Alternatives Considered

- **Keep both screens, add editing to the review screen**: Smaller change, no navigation rework - Rejected because it duplicates the food rows across two screens and leaves the pass-through tap in place.
- **Keep both screens, add the photo and regions to the result screen**: Also smaller - Rejected for the same duplication, and it makes the segmentation screen redundant rather than useful.

### Consequences

**Positive:**
- The evidence and the number the user is judging sit on one screen.
- One mandatory tap removed from every capture.
- One surface to style rather than two divergent ones.

**Negative:**
- A denser screen; row-per-item layouts stop fitting one screen beyond roughly four foods.
- `CaptureRoute` loses its `.review` case, and the navigation stack shape changes.

---

## Decision 3: Reinstate relabelling, post-hoc

**Date**: 2026-08-05
**Status**: accepted

### Context

The original design handoff carried a "Tap a region to confirm or relabel" instruction line. It was dropped during `ui/design-handoff-00`, recorded as dropped in that spec's `copy-inventory.md`, and hardened into an anti-pattern in `design-system/pages/segmentation-review.md`: "Do NOT offer a relabel / per-class exclusion interaction - that would need the pipeline split this spec rejects (Decision 7)."

Decision 7's actual concern was splitting estimation into two user-visible phases, so that segmentation review would appear to be pending work rather than a completed estimate.

### Decision

Reinstate relabelling as a post-hoc correction of a completed estimate. Explicitly supersede the copy-inventory row and the design-system anti-pattern, editing both out. Decision 7 itself remains in force.

### Rationale

A relabel applied after the estimate has completed does not split the pipeline. The estimate still runs in one pass; the user then edits its output, exactly as they already edit amounts. The rejection rationale therefore does not reach this case, but the written prohibition does, so it must be removed rather than worked around.

The evidence for prioritising relabel is strong: carbohydrate is derived as volume × density × carbs-per-gram, so a wrong class corrupts two of the three factors while a wrong boundary corrupts only one. Two bugfix reports (`result-view-defects`, `unrecognised-food-estimated-as-residual-sliver`) record misclassification as an observed, recurring failure with no user recourse.

### Alternatives Considered

- **Leave relabelling out and rely on amount correction alone**: No supersession needed - Rejected because scaling grams cannot fix a wrong density or a wrong carbs-per-gram figure; the user would be tuning the wrong variable.
- **Add relabelling without amending the design-system page**: Faster - Rejected because `ui/design-handoff-00` Req 15.3 makes the design-system pages normative, so the contradiction would be live in the spec set.
- **Reopen Decision 7 and split the pipeline into segment-then-estimate phases**: Would allow correction before the estimate runs - Rejected as a much larger change that Decision 7 considered and refused on its own merits.

### Consequences

**Positive:**
- The most damaging error mode gains a user remedy.
- The recorded relabels are unambiguous ground truth for later model work.

**Negative:**
- Two existing documents must be edited, one of which belongs to a spec marked Done.
- Relabelling introduces a food-picker surface that did not previously exist.

---

## Decision 4: No boundary editing

**Date**: 2026-08-05
**Status**: accepted

### Context

Correcting a machine-produced mask can mean changing what a region is called, or changing its shape. Both were considered.

Measured interaction costs from the interactive-segmentation literature: verifying a region takes about 3.5 s, relabelling about 4 s, click-based refinement about 15 s, and hand-painting a mask about 79 s per instance (COCO annotation timings). Holz and Baudisch measured roughly 4 mm of systematic touch error under the contact-centre model that phones expose, so a tap can reliably identify a region but cannot reliably place a boundary. Google's Fluid Annotation shipped no boundary editing at all and still reached three times the speed of polygon annotation at comparable inter-annotator agreement, with an action mix of 33% add, 31% remove, 26% relabel.

### Decision

Support relabel and reject. Do not support boundary brushes, lasso, magic wand, or expand/contract. Absorb boundary error through amount correction, and retain the ratio of corrected to predicted mass as a scalar boundary-error proxy.

### Rationale

Boundary work is roughly twenty times the cost of a relabel and is the interaction a phone is worst at. It is also the less damaging error: a wrong boundary corrupts only the volume term, which the existing serving and gram controls already correct directly. Recording the implied scale factor gives a regression target for the volume pipeline at no interaction cost.

### Alternatives Considered

- **Scribble-based add/subtract refinement**: Preferred by 15 of 16 participants in the ScribblePrompt study - Rejected because that study was desktop, expert and medical; median 94 s per image and two-handed.
- **Click-based refinement (SAM/RITM/SimpleClick style)**: About four clicks to 90% IoU - Rejected because it requires re-running inference per click and real-user clicks inflate the required count well above the idealised benchmark.
- **Region split via a drawn line**: Would complete the merge/split pair - Rejected as requiring a boundary, which is the thing being excluded.

### Consequences

**Positive:**
- Every correction stays a single tap or a short sequence of taps.
- No inference re-run on the correction path, preserving the offline determinism invariant.
- Boundary error still yields a usable numeric signal.

**Negative:**
- A detected area that has swallowed part of a neighbouring food cannot be corrected exactly; only its amount can be scaled.
- The recorded masks carry the model's boundary noise into any future training export.

---

## Decision 10: A detected food is a class, not a blob

**Date**: 2026-08-05
**Status**: accepted

### Context

The requirements were first drafted around per-area correction: tap one of three blobs of rice, relabel it, or merge the three into one. Review against the code showed that entity does not exist.

The segmenter is semantic, not instance-based. `SegmentationResult` (`MedataCore/Sources/Segmentation/SegmentationTypes.swift:59-60`) carries an argmax map and per-class mean probabilities, with no connected-component labelling. Everything downstream is keyed by class-id string: `VolumeResult.proto` holds `map<string, float> per_class_volumes_cm3`, `MacroResult` holds `map<string, PerClassMacros>`, and the persisted mask artefact is an 8-bit class-index raster. Three separate blobs of rice are one entry, not three, and nothing in the stored data can distinguish them.

Two options were put to the user: correct by food, or add connected-component instance labelling with instance-keyed volumes, macros and a changed mask artefact format.

### Decision

A detected food is a class. Selecting any marked area selects every area of that class, and a relabel or rejection applies to all of it. Merge and split are removed from scope entirely — same-class areas are already one entry, so there is nothing to merge.

### Rationale

Instance labelling is an estimation-path change: new instance identity that must remain stable, instance-keyed volume and macro records, and a new mask artefact format. None of that belongs in a UI spec, and it would land while `support-plane-reference` is already rewriting the volume path.

The class model also loses less than it appears to. The error that matters is the class error, because it corrupts two of the three factors in volume × density × carbs-per-gram, and a class error is by definition class-wide. What is genuinely lost is the case where the model splits one real food across two classes — half the rice called couscous — which can then only be corrected in aggregate.

### Alternatives Considered

- **Add connected-component instance labelling**: Makes per-blob relabel and merge real, and matches how a user perceives the plate - Rejected as a substantial estimation-path change outside this spec's scope, colliding with in-flight volume work.
- **Ship class-keyed now, shape the correction records so instances can be added later**: Defers rather than cancels - Not taken; the user chose the simpler model, and Req 9.8 retains the class index, which is the identity that actually exists.

### Consequences

**Positive:**
- No estimation-path change, no mask artefact change, no new identity to keep stable.
- Works against the mask already persisted, so existing captures stay correctable in principle.
- Removes an entire requirement section and its interaction-composition problems.

**Negative:**
- A food the model split across two classes can only be corrected in aggregate.
- The correction corpus carries no sub-class spatial detail, so a future instance-based segmenter cannot learn per-blob corrections from it.

---

## Decision 11: A relabel re-applies the corrected food's own β_c to the pre-correction volume

**Date**: 2026-08-05
**Status**: accepted

### Context

Decision 8 settled that a relabel recomputes carbohydrate. It did not say from which volume, and that turns out to matter.

`PerClassMacros.volume_cm3` is annotated in the proto as **β-corrected**, alongside `beta_used` and `beta_status`. β_c is fitted per class. So the volume stored against a detected food already has that class's β baked in. Retaining it across a relabel would carry rice's β into the couscous figure.

An earlier draft of this decision claimed `VolumeResult.per_class_volumes_cm3` held a raw pre-β figure. Review against source disproved it: β is multiplied in **during volume estimation**, not during the macro stage — `Pipeline.swift:382` passes `beta:` into `HeightFieldEstimator.integrate`, which computes `perClass[name] = preCm3 * beta` (`HeightFieldEstimator.swift:192`), and `Macros.compute` then takes those already-corrected volumes with no β parameter. **No pre-β volume is stored anywhere.**

It is recoverable arithmetically: `PerClassMacros.beta_used` retains the factor that was applied, so dividing it out reconstructs the pre-β volume exactly.

### Decision

A relabel removes the β applied under the original class by dividing out the retained `beta_used`, then applies the chosen food's own β_c, density and carbohydrate coefficient to the result. The requirement is worded as removing and re-applying β, not as reading a pre-β field that does not exist.

### Rationale

β_c is a per-class correction for that class's systematic volume error. Carrying one class's β into another's estimate is not conservatism, it is a category error — the correction no longer refers to anything. Re-deriving from the pre-β volume reproduces exactly what the pipeline would have computed had the segmenter been right first time, which is the only defensible target.

This also keeps the recomputation identical in shape to `Pipeline`'s own derivation rather than a parallel arithmetic path, so a corrected meal and a re-derived one agree.

### Alternatives Considered

- **Retain the β-corrected volume unchanged**: Simplest, and keeps the volume term literally untouched - Rejected because it applies the wrong class's correction factor, producing a number that misattributes its own error.
- **Drop β entirely for relabelled foods**: Avoids choosing - Rejected because it makes corrected foods systematically inconsistent with uncorrected ones in the same meal.
- **Persist a pre-β volume alongside the corrected one**: Removes the division and any rounding it introduces - Rejected as a change to the estimation path and the stored record for something `beta_used` already makes recoverable.

### Consequences

**Positive:**
- A relabelled food is derived exactly as a correctly-classified one would have been.
- The retained original and the corrected value are both explicable.
- No estimation-path or schema change: `beta_used` is already persisted per class.

**Negative:**
- The correction path depends on `beta_used` being present and non-zero; a record where it is absent cannot be relabelled without falling back to the uncorrected volume.
- Dividing out and re-multiplying introduces float round-trip error that a stored pre-β volume would not.
- Where the chosen food has no fitted β_c, its calibration status must be surfaced through the same path the pipeline uses (Req 3.4a), or corrected foods will silently differ in calibration state from uncorrected ones.

---

## Decision 5: The correction is the error report

**Date**: 2026-08-05
**Status**: accepted

### Context

The request asked for a way to record model errors for later debugging and improvement. That can be an explicit "report a problem" affordance, or implicit capture of the corrections the user is making anyway.

Apple's machine-learning guidance states that explicit feedback "requires people to take action" and should be requested only when necessary. Google PAIR and the Microsoft HAX guidelines both distinguish explicit per-output feedback from reuse of existing interaction data, and both caution against feedback fatigue. Shipping practice leans implicit: Tesla's shadow mode logs the divergence between model decision and human action with no user-facing report control.

### Decision

No "report a problem" affordance. Every relabel, rejection, merge and amount adjustment is retained as a structured record carrying the original prediction. Confirmations and abandonments are retained too. One explicit affordance is added — stating that a food is absent from the database — because that signal is invisible to correction logs.

### Rationale

An explicit report and a correction compete for the same user moment, and the report yields worse data: sparse, self-selected, and unaccompanied by the fix. The ambiguity that usually undermines implicit signals does not apply here, because a relabel from rice to couscous is stated ground truth rather than inferred preference.

Confirmations must be retained because a correction-only log is a pure negative-sample store: per-class precision cannot be computed from it, and any retraining on it is biased toward the failure modes. Abandonments must be retained because a user who opens the picker and gives up is the clearest signal that the ranked alternatives are failing.

### Alternatives Considered

- **An explicit "this is wrong" button per region**: Direct and unambiguous - Rejected because it duplicates the correction the user is already making, and yields a report without a fix.
- **A post-save "was this right?" prompt**: Would capture the confirm case explicitly - Rejected as feedback fatigue; HAX G15-B advises requesting explicit feedback on selected outputs, not all of them.
- **A bulk "everything looks right" confirm button**: Cheap way to capture confirmations - Rejected because pre-annotation confirmation induces automation bias, so label quality degrades as trust grows while the metrics improve.

### Consequences

**Positive:**
- No additional interaction cost for producing error data.
- The data carries both the wrong answer and the right one.
- Out-of-vocabulary foods, which no correction log can surface, still get captured.

**Negative:**
- Retaining confirmations and abandonments increases record volume, so eviction bounds need attention.
- The user is not explicitly prompted about data capture, so the existing diagnostics browser and export become the disclosure surface.

---

## Decision 6: Retain auto-persist; do not defer recording to the primary action

**Date**: 2026-08-05
**Status**: accepted

### Context

The meal record is currently written inside `Pipeline.estimate`, before the review surface renders. There is no Save button; the primary action dismisses, and Retake and Delete remove an already-written record. This was established by `ui/design-handoff-00` Decision 17.

Apple's Sheets guidance says a Done button should always be paired with a Cancel button, and its undo guidance discourages bespoke undo buttons. Read together these favour deferring persistence until the user confirms, which would make Retake discard an unsaved draft rather than delete a saved row.

### Decision

Keep auto-persist. The meal is recorded when estimation completes, not when the primary action is tapped. Each correction is retained at the moment it is made, not held pending until the primary action; the primary action updates the recorded total and dismisses.

### Rationale

The stated goal is that a capture which goes badly wrong still yields good data. Deferring persistence discards every abandoned capture — the backgrounded ones, the ones the user walks away from, the ones so wrong the user gives up — which are the most diagnostically valuable records. That directly contradicts Decision 5's requirement to retain abandonments.

The generic iOS convention assumes the user's intent is the only thing worth preserving. Here the failed attempt is itself the product.

### Alternatives Considered

- **Defer persistence to the primary action**: Matches Apple's Sheets guidance and makes Retake non-destructive - Rejected because it silently discards abandoned captures, which are the records most worth keeping.
- **Persist a draft immediately and promote it on confirm**: Would satisfy both - Rejected as two record states to reason about, for a developer-phase app where the meal record is already append-only and deletable.
- **Auto-persist the meal but hold corrections pending until the primary action**: The original draft of this decision - Rejected on review: it loses every correction if the app is backgrounded and killed mid-review, which is the exact failure this decision claims to prevent. Corrections are therefore retained incrementally (Req 9.2).

### Consequences

**Positive:**
- Abandoned and backgrounded captures still produce data, and so do the corrections made before abandonment.
- No change to the existing persistence path or to `design-handoff-00` Decision 17.
- The primary action stays a single uncontested tap.

**Negative:**
- Diverges from Apple's documented confirm-step convention.
- Retake and Delete continue to delete a written row rather than discard a draft, so a discarded capture leaves and then removes a record.
- Between estimation completing and the primary action, the recorded meal carries the uncorrected total, so Records and Graph can briefly show a figure the user has already contradicted on screen. Bounded by the review session, and preferred to losing the data outright.
- The claim that abandoned captures still produce data does **not** hold against the storage layer as it stands. `GRDBPersistenceStore.swift:177` and `:542` both execute `DELETE FROM corrections WHERE meal_id = ?`, so retake and delete — the two explicit abandonment paths — currently destroy every correction made during the session along with the meal. Req 9.10 requires that cascade be broken; until it is, this decision's central justification survives for backgrounding only.

---

## Decision 7: Regions are marked by outline, and shown by default

**Date**: 2026-08-05
**Status**: accepted

### Context

The overlay today composites a fully colourised per-class raster over the photo at 0.55 alpha, drawn as soon as the screen appears.

Apple's own surfaces do the opposite in two respects. They prefer outlining a detected subject, or dimming its surroundings, over filling it — the WWDC23 subject-lift session uses an exposure-adjustment filter to dim the background rather than tinting the subject. And they draw nothing until asked: Live Text highlights only after the button is tapped, and `DataScannerViewController.isHighlightingEnabled` defaults to false.

### Decision

Mark regions by outline, with a separating stroke between adjacent regions, and de-emphasise the surroundings when a region is selected. Show the regions from the moment the surface appears; do not put them behind a reveal affordance.

### Rationale

Adopt the outline half of Apple's pattern and reject the latency half. Filling a region obscures the pixels the user is being asked to judge, which defeats the screen's purpose — so outline wins on this screen for the same reason it wins on Apple's.

But on Live Text and subject lift, detection is incidental to the user's task. Here, judging and correcting the regions is the task. A reveal affordance would add a tap to the primary job on every capture, which contradicts Req 8.

### Alternatives Considered

- **Keep the colourised fill**: Already implemented, clearly shows extent - Rejected because it hides the evidence under the annotation.
- **Regions hidden behind a "show regions" toggle, defaulting off**: Matches Apple's resting state and gives the cleanest first impression - Rejected because correcting regions is the reason the screen exists.
- **Fill at much lower alpha**: A compromise - Rejected because low-alpha fills over arbitrary food photography are unreliable to distinguish, and colour alone cannot be the identifying channel anyway.

### Consequences

**Positive:**
- The food stays visible while its extent is still legible.
- Region extent and the user's judgement of it no longer compete for the same pixels.

**Negative:**
- Outlines are harder to follow than fills for small or fragmented regions.
- `MaskOverlayLoader`'s colourised-raster path needs replacing with a contour-derived one, and it is shared with `MealOverviewView`.

---

## Decision 8: Relabelling recomputes the carbohydrate figure

**Date**: 2026-08-05
**Status**: accepted

### Context

When a region is relabelled, the carbohydrate figure can either be re-derived from the corrected food's database row, or left as estimated with the relabel retained only as data.

`estimation/pipeline` Req 14.3 states that corrections "SHALL NOT be used to refine any model, density value, or β_c in v1". Separately, `estimation/support-plane-reference` is currently addressing a 2 to 3.6× volume over-read, so the volume term a recomputation would build on is known to be wrong today.

This was put to the user during requirements gathering. They confirmed recomputation, and framed the product priority behind it: recording a meal accurately and quickly is the goal, and a model that is only good enough to speed that recording up may be sufficient. Retaining the original prediction for later pipeline review is an addition to recomputation, not an alternative to it.

### Decision

A relabel retains the region's measured volume and re-derives its mass and carbohydrate contribution from the chosen food, updating the meal total live. The original prediction is retained unchanged alongside.

### Rationale

The primary action records what the screen displays, with no confirmation step (Req 8.4). A screen that has just been told a region is couscous but still displays and then records the rice figure would write a value the user has explicitly contradicted.

Re-deriving from a different database row is not model refinement: the pipeline already performs that lookup, and no density, β_c or model weight is altered. Req 14.3 is therefore not engaged.

The volume over-read is a real objection, but it applies equally to the uncorrected figure, and Req 9.3 keeps the meal re-derivable once the pipeline is fixed. It also mis-frames the product: the estimate does not have to be right unaided, it has to get the user to a correct recorded figure faster than entering it by hand. Recomputation is what converts a class correction into that figure.

### Alternatives Considered

- **Retain the relabel without recomputing**: Keeps this spec clear of the estimation path entirely, and avoids compounding a known-bad volume - Rejected because the screen would knowingly record a figure it has been told is wrong, and the user would have to correct the amount separately to fix a class error.
- **Recompute and mark the affected rows as user-derived**: Keeps provenance legible on the screen - Partially adopted; the existing user-corrected marker covers the meal, and per-row marking is deferred as ornament this screen does not need.

### Consequences

**Positive:**
- The recorded figure matches the user's stated understanding of the plate.
- No separate amount correction needed to fix a class error.

**Negative:**
- This spec now touches the estimation path, not only the UI, so the recomputation must stay deterministic, offline and consistent with `Pipeline`'s own derivation.
- Recomputing on a volume that `support-plane-reference` is still correcting produces a confidently wrong number in a new way.

### Impact

Req 3.3, Req 3.4 and Req 8.3 depend on this. The recomputation must share `Pipeline`'s own derivation rather than reimplementing it, or a corrected meal and a re-derived one will disagree.

---

## Decision 9: The corrections are shown, and the corpus is the deliverable

**Date**: 2026-08-05
**Status**: accepted

### Context

The review surface could present only its current state — the corrected foods and the resulting total — with the corrections themselves visible only in the diagnostics browser. That is the conventional choice: the user knows what they just changed, so showing it back is redundant.

The stated purpose of this work is otherwise. What is being built is a corpus: the prediction, the result, and the user's correction, retained together so later models and a growing food corpus can be trained and evaluated against them. The interface is the means of collecting it.

### Decision

Show the corrections on the review surface, not only the corrected state — each corrected region and row displays what it was predicted as alongside what it was corrected to. Weight the spec's acceptance bar toward the completeness and fidelity of the retained data rather than toward interface refinement.

### Rationale

Displaying the delta makes the correction checkable at the moment it is cheapest to undo. A row that silently reads "couscous" cannot be distinguished from one that was always couscous, so a mis-tap is invisible until the data is exported and wrong.

It also matches what the record stores. Req 9.2 keeps predictions immutable and appends corrections; a screen that renders only the corrected state presents a different shape from the one being persisted, and the persisted shape is the product.

The weighting follows from the same reasoning. Interface work here is instrumental — it exists to make corrections cheap enough that they happen. Where a choice trades interface polish against data fidelity or completeness, fidelity wins.

### Alternatives Considered

- **Show only the corrected state**: Cleaner and less dense, and the user has just made the change so it is fresh - Rejected because a mis-tap becomes undetectable, and the screen would misrepresent the append-only record behind it.
- **Show the delta only in the diagnostics browser**: Keeps the review surface uncluttered - Rejected because the correction is verifiable only at the moment it is made; by the time the developer opens diagnostics, the plate is gone.
- **Show the delta transiently, then collapse to the corrected state**: A compromise on density - Rejected as a hidden state change that makes the screen's meaning depend on when it is read.

### Consequences

**Positive:**
- Mis-taps are visible and reversible while the plate is still in front of the user.
- The screen and the persisted record have the same shape.
- Prioritisation is explicit when interface polish and data fidelity conflict.

**Negative:**
- Denser rows, which compounds the layout pressure Decision 2 already introduced beyond about four foods.
- The surface must render a state — predicted versus corrected — that has no equivalent in the current UI.

---

---

## Decision 12: Two correction stores, both surviving meal deletion, written in one transaction

**Date**: 2026-08-06
**Status**: superseded by Decision 16

> Superseded in two respects: the corpus store is no longer an append-only event stream, and the withdrawal of the `corrections` cascade break was verified correct — every reader reaches `corrections` only via a meal already fetched from `events`, so an orphaned row is unreachable. The transactional dual-write, and the reasoning for it, stand.

### Context

Corrections serve two purposes with different lifetimes. The meal's *current value* is read by every display surface from the `corrections` table (`MealHistoryModel.swift:81`, `TrendsModel.swift:108`, `RecordsModel.swift:105-121`, `ResultView.swift:1019`), latest row wins, per `event-log-schema` Req 4.4. The *corpus* needs every action, including ones that never changed a value.

An earlier draft of the design kept `corrections` cascading on delete and wrote it only at the primary action.

### Decision

Two tables. `correction_events` is the corpus; `corrections` remains the current-value overlay. Neither cascades on meal deletion. Both are written in the same `queue.write` transaction on every mutation, not at the primary action.

### Rationale

Deferring the `corrections` write recreates the failure Decision 6 rejected: a session killed after a relabel leaves the corpus holding the correction while Records shows the uncorrected total permanently. Decision 6's claim that the divergence window is "bounded by the review session" is only true if both stores are written together.

Exempting `corrections` from the cascade break was also wrong. `PbUserCorrection.note` carries the machine-readable per-food serving amounts (`ResultView.swift:765-772`), which Req 9.1 and 9.4 count as retained correction data. Deleting it on retake destroys exactly what Decision 6 exists to preserve.

### Alternatives Considered

- **One store serving both purposes**: No divergence possible - Rejected because the corpus needs unchanged and abandonment rows that would corrupt a latest-wins current-value read.
- **Keep `corrections` cascading, break only `correction_events`**: Smaller change, and a deleted meal arguably has no current value - Rejected because `corrections` also holds correction data, and because `requirements.md`'s supersession register already says both must break.
- **Write `corrections` at the primary action only**: Fewer writes - Rejected on the kill-mid-review case above.

### Consequences

**Positive:**
- Corpus and displayed value cannot disagree, including after termination.
- `record()` reduces to dismissal.

**Negative:**
- Every mutation costs a transaction rather than one write at the end; amount events are debounced at 500 ms per food to bound this.
- Orphaned `corrections` rows now accumulate for deleted meals, which the existing latest-wins readers never expected to see.

---

## Decision 13: Rank relabel candidates from a per-class candidate matrix, not `perClassMeanProb`

**Date**: 2026-08-06
**Status**: superseded by Decision 18

> The finding stands — `perClassMeanProb` is the wrong quantity and cannot order a relabel shortlist. The remedy is deferred: Decision 18 splits the candidate matrix into an estimation-domain spec and ships recency ordering here.

### Context

The design first proposed ordering relabel alternatives by `SegmentationResult.perClassMeanProb`, described as one score per class.

Review against source disproved it. `PostProcessing.swift:172-177` increments `perClassCount[cId]` only where `cId` won the argmax, so the map holds an entry only for classes already detected on the plate — each of which already has its own row — and the value is the winner's mean confidence, not a candidate posterior. The food the user wants has no entry at all. It is also computed before `regulariseLabelMap` (`:193`) while the persisted mask uses the cleaned argmax.

`cofid_db.sqlite` `foods` has 33 rows, one per palette class, of which 25 are solid food classes.

### Decision

Accumulate, in the existing pixel loop, the mean probability of every candidate class over each detected class's pixels. Store the top five per detected class on the meal record as a new `class_candidates` map. Order alternatives from that.

### Rationale

That is the quantity the question actually asks — "what else might this be" — rather than "how sure was the winner". The small class count makes it affordable: `resized[off + c]` is already in scope for every `c` in a pass that is already O(pixels × classes), and the stored result is ~500 bytes per meal.

It goes on `PbMealRecord` rather than `PbMacroResult` because `PaletteMigrator.swift:101-103` copies `meal.macros` wholesale while migrating only `perClass` and `totalCarbsG`; a class-keyed map added there would survive a v1→v2 migration unmigrated, leaving stale keys beside migrated ones.

### Alternatives Considered

- **Read runner-up scores from the capture bundle at review time**: The full probability tensor is already written there - Rejected because the bundle is ~200 MB and would be read during a screen transition.
- **Keep `perClassMeanProb` as a cheap approximation**: No pipeline change - Rejected because it is not a weak signal but the wrong quantity, and is empty for exactly the classes needed.
- **Order alphabetically or by recency alone**: No pipeline change at all - Rejected as discarding the model's own evidence, though it is the fallback for liquids and for replayed fixtures.

### Consequences

**Positive:**
- The shortlist can contain foods the model never chose, which is the whole point of a relabel.
- Computed from the cleaned argmax, so it agrees with the outlines shown.

**Negative:**
- A pipeline and record-schema change from a UI spec, with a `PaletteMigrator` obligation attached.
- Liquid classes get no candidate row, so their alternatives are recency-ordered only.
- Replayed device bundles produce meals with no ordering source (`FixtureRunner.swift:273-276`).

---

## Decision 14: A relabel is refused when the original β is unrecoverable

**Date**: 2026-08-06
**Status**: superseded by Decision 17

> The refusal path existed only because the pre-β volume had to be recovered by division. Decision 17 persists it instead, so there is nothing to divide by and nothing to refuse. The refusal survives only as a fallback for records written before that field exists.

### Context

Decision 11 divides out `PerClassMacros.beta_used` to recover the pre-β volume. Its first draft said that where `beta_used` is absent or non-positive, the relabel proceeds using the stored volume unchanged, with the event flagged.

### Decision

Refuse the numerical relabel when `beta_used` is not finite or not greater than zero. Reject, absent-food and amount adjustment remain available. A diagnostic event is written.

### Rationale

Proceeding applies the *original* class's β to the corrected food's figure — the exact category error Decision 11 was written to prevent, now shipped as a supported path. The user sees a confident number; only a later export filter knows it is junk. `FoodEntry.beta` is documented β_c ∈ (0, 1], so a non-positive value means a corrupt record, and a corrupt record is not something to compute on.

### Alternatives Considered

- **Proceed with the stored volume, flag the event**: Never blocks the user - Rejected as displaying a knowingly wrong figure.
- **Proceed with β = 1**: Neutral factor - Rejected as indistinguishable to the user from a calibrated figure, with no signal that calibration was skipped.

### Consequences

**Positive:**
- No path produces a figure carrying another class's calibration.
- The failure is visible at the moment it happens rather than at export.

**Negative:**
- A corrupt record cannot be relabelled at all, only rejected or amount-adjusted.

---

## Decision 15: `PbUserCorrection` gains a corrected-class map

**Date**: 2026-08-06
**Status**: accepted

### Context

Every history surface renders food names from `record.macros.perClass` keys (`ResultView.swift:316-330`). `PbUserCorrection` carries corrected carbohydrate but no corrected class, so a meal relabelled rice → couscous would display "Rice" at couscous's figure for the life of the record. The Non-Goal excluding correction *from* Records does not license *displaying* a correction wrongly.

Put to the user during design; they chose to extend the schema.

### Decision

Add `map<string, string> corrected_class_ids` to `PbUserCorrection`, keyed by predicted class id. Every surface naming a food resolves through it (Req 8.7).

### Rationale

The alternative is an app that knowingly displays a food name the user has already corrected. The field is additive with an empty default, so existing readers stay valid and `estimation/pipeline` Req 14.4's requirement that the schema be portable and shared verbatim with the clinical track is preserved rather than broken.

### Alternatives Considered

- **Accept the stale name, document it**: No schema change, and the corpus has the right class regardless - Rejected by the user; the carb figure being right does not excuse the name being wrong.
- **Suppress per-food names on corrected meals**: No schema change, nothing false shown - Rejected as degrading the history view to hide a problem rather than fixing it.

### Consequences

**Positive:**
- A corrected meal reads correctly everywhere it appears.
- Additive change; no migration needed for existing records.

**Negative:**
- Touches a schema shared with the future clinical track, so the change must be mirrored there.
- History surfaces must now resolve names through the correction overlay rather than reading `macros.perClass` directly.

---

## Decision 16: One correction record per detected food, never discarded

**Date**: 2026-08-06
**Status**: accepted, supersedes the store design in Decision 12

### Context

Decision 12 specified an append-only `correction_events` stream: one row per user action, bounded at 5000 rows, evicting unchanged-food records before corrections. Explaining that design back at three levels exposed two problems. Req 9.11's eviction discarded exactly the confirmations Decision 5 had argued were essential — without them per-class precision cannot be computed, which is the pure negative-sample store Decision 5 rejected. And an append-only stream needed a monotonic key, per-action rows for every stepper repeat, and debouncing to keep the write rate sane.

The user rejected discarding corrections on any basis: the recorded numbers are what future regressions run against and what future models train on, so an evicted record is a regression that can no longer be run. They also proposed the simplification: carry the original values — including density and food composition — in the same record as the corrected ones, rather than accumulating amendments.

### Decision

One row per detected food per capture, keyed `(meal_id, predicted_class)`, holding a predicted side that never changes and a corrected side updated in place. No eviction on age, count, or sweep. Both sides carry density and carbohydrate coefficient, not only the derived figures.

### Rationale

Storing the original beside the final removes the reason the stream existed. Intermediate states have no training value — what matters is what the model said and what the human said it should have been — so the amendment history was cost without benefit.

It also removes a chain of derived machinery: no monotonic key, so the millisecond-collision defect cannot arise; no per-repeat rows, so no debouncing is needed for correctness; no bound, so no eviction ordering to reconcile with Decision 5; and an unchanged food is simply a row whose corrected side is unset, so confirmations are retained by construction rather than by policy.

Carrying density and coefficient in the record makes each row a self-contained training example, readable without the app, without the food database at the edition that produced it, and without the mask. Retention is cheap enough to be honest about: roughly a kilobyte per detected food including SQL row and index overhead, so three meals a day over a decade is **~50 MB**. (An earlier draft of this entry claimed single-digit megabytes; that was wrong by an order of magnitude, and the conclusion survives the correction.)

### Alternatives Considered

- **Append-only events with a larger bound**: Preserves full amendment history - Rejected because the history has no training value and any bound eventually discards data the corpus exists to keep.
- **Append-only events with no bound**: Keeps everything and preserves history - Rejected on growth *rate* rather than boundedness; the chosen option is also unbounded, so citing unbounded growth against it alone would be dishonest. Per-action rows grow with interactions, per-food rows with captures.
- **One row per food with an amendment list inside the same record**: Keeps every structural benefit — one table, natural key, no eviction, no debounce — while preserving the sequence - Rejected because the retained sequence would be used to evaluate the shortlist ranker, and that evaluation is better served by `shortlist_rank` and `shortlist_source` than by replaying amendments.
- **Reference the food database rather than copying density and coefficient**: Smaller rows - Rejected because a database edition change would silently reinterpret every historic record, which is the failure mode the corpus most needs to be immune to.

### Consequences

**Positive:**
- Nothing the user corrects is ever discarded.
- Each row is a complete training example with no external dependency.
- Removes the bound, the eviction policy, the monotonic key and the debounce requirement.
- Confirmations are retained structurally, satisfying Decision 5 without a policy that fights it.

**Negative:**
- Intermediate corrections are not recoverable; a user who relabels twice leaves only the second. This is fully lossless for macro-stage regression replay and for class-correction training, but it does lose *shortlist-ranker* signal: someone who took rank 1, disliked the figure and switched to rank 4 is indistinguishable from someone who took rank 4 outright. Decision 16's framing that intermediate states have no training value holds for the estimator and not for the ranker.
- Per-action timing is not retained, so the interaction-cost evidence Decision 4 rests on cannot be validated against real use from the corpus.
- One store in the app is now deliberately exempt from bounding, which must be stated wherever retention policy is reviewed.
- The artefact sweep must exempt meals holding a record, or the mask that provides pixel-level supervision is lost while the record survives.


---

## Decision 17: Persist the pre-β volume rather than recovering it by division

**Date**: 2026-08-06
**Status**: accepted, supersedes Decision 14 and amends Decision 11

### Context

Decision 11 established that a relabel must strip the original class's β before applying the corrected food's. It asserted that "no pre-β volume is stored anywhere", and therefore recovered it as `stored.volumeCm3 / stored.betaUsed`. Decision 14 then added a refusal path for records where `beta_used` is zero or non-finite, since dividing by it is undefined.

That assertion was true of the persisted record and false of the pipeline. `VolumeEstimate.perClassVolumesPreBetaCm3` (`VolumeTypes.swift:84`) is produced by both estimators (`HeightFieldEstimator.swift:190, 197`; `VoxelCarveEstimator.swift:244`) and already flows into `PipelineDiagnostics` (`:128`). It is simply dropped before the meal record is written. `VolumeResult.proto` uses fields 1–4, leaving field 5 free.

### Decision

Persist the pre-β per-class volumes on `PbVolumeResult` as field 5, and derive a relabel from that value directly. Retain the division only as a fallback for records written before the field exists.

### Rationale

The value the derivation needs is already computed; not persisting it was an oversight rather than a constraint. Reading it removes the division, the float round-trip Decision 11 listed as a negative consequence, and Decision 14's entire refusal path — a relabel can no longer fail on a corrupt β because it no longer divides by one.

Decision 11 considered and rejected exactly this, on the grounds that it was "a change to the estimation path and the stored record". That reason no longer holds: this design already makes a larger change to both for the candidate matrix, and one additive proto field is the smaller of the two.

### Alternatives Considered

- **Keep the division and the refusal path**: No schema change at all - Rejected because it fails on records the app itself wrote, and reimplements a derivation the codebase already has twice.
- **Recompute the pre-β volume from the β table at review time**: No schema change, no division - Rejected because a β table update would silently change the meaning of historic records, which is the drift Decision 16 exists to prevent.

### Consequences

**Positive:**
- No division, so no unrecoverable-β case and no refusal path.
- Exact rather than round-tripped, which matters for a corpus.
- The relabel derivation matches what the pipeline computed, by construction.

**Negative:**
- One more additive field on the record, and `PaletteMigrator` must carry it.
- Records written before the field exists still need the division fallback, so both paths must be implemented and tested.
- `PaletteMigrator.swift:83-86` already implements this arithmetic independently; a third call site makes the case for extracting it into `MedataCore/Sources/Macros/` rather than specifying it again.


---

## Decision 18: Defer the candidate matrix to an estimation-domain spec; order the shortlist by recency

**Date**: 2026-08-06
**Status**: accepted, supersedes Decision 13

### Context

Decision 13 established that the relabel shortlist should be ordered by a per-class candidate matrix, accumulated during segmentation. Specifying it properly grew the estimation-side change rather than shrinking it: a new parallelised pass over the full-resolution probability tensor after `regulariseLabelMap` (~91 M loads and adds at 1920 × 1440 × 33, on the timed capture path), a new `ClassCandidates` message, a `PbMealRecord` field, a `PaletteMigrator` migration obligation, and a device performance prerequisite — all inside a spec filed under `ui/`.

The design also conceded two fallbacks that undercut the ordering's status as a functional gate: liquid classes get no candidate row and fall back to recency, and replayed capture bundles pass an empty map (`FixtureRunner.swift:273-276`), so they do too.

Decision 10 refused connected-component instance labelling partly because it "would land while `support-plane-reference` is already rewriting the volume path". The same argument applies here and was not applied.

### Decision

Defer the candidate matrix to an estimation-domain spec. This spec orders the relabel shortlist by recency — foods the user has recently chosen for a food of that kind — and relies on the full eligible list for everything else. Each correction record carries `shortlist_source` naming the ordering that produced it.

### Rationale

The eligible universe is 25 solid classes. A five-item shortlist already covers a fifth of it, and the full list is one interaction away, so ordering is a convenience rather than the thing that makes relabelling work. Shipping recency first gets the correction surface — and the corpus it feeds — into use without adding a pass to the estimation path during someone else's rewrite of it.

`shortlist_source` is what makes the deferral safe rather than merely cheap. Without it, `shortlist_rank` would mean "position in a recency list" for early records and "position in a score list" for later ones, with nothing distinguishing them — quietly corrupting the one measurement that says whether the shortlist is any good.

### Alternatives Considered

- **Ship the candidate matrix with this spec**: Score ordering from day one, and no mixed-provenance records - Rejected as a pipeline change inside a UI spec, landing on the timed path while the volume path is already being rewritten.
- **Drop ordering permanently, alphabetical or recency only**: Simplest, defensible on 25 items - Rejected because it discards the model's own evidence about what else a region might be, which is precisely what a relabel shortlist should use.

### Consequences

**Positive:**
- This spec no longer changes `PostProcessing`, `PbMealRecord` or `PaletteMigrator`, and needs no device performance prerequisite.
- The correction surface and its corpus can land while the estimation work is sequenced separately.
- Records stay comparable across the transition.

**Negative:**
- The shortlist is worse until the estimation spec lands: recency cannot suggest a food the user has never chosen.
- Early corpus rows carry recency-ordered ranks, so shortlist-quality analysis must partition on `shortlist_source`.
- A second spec is now owed, and until it exists Decision 13's finding sits recorded but unremedied. Filed 2026-08-07 as [`estimation/alternative-class-candidates`](../../estimation/alternative-class-candidates/requirements.md), at its requirements gate; its Decision 3 corrects two figures used above — the tensor is 36 channels, not 33 (~99.5 M reads at 1920 × 1440), and the loop this decision proposed extending is serial, not parallelised.
