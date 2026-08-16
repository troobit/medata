# Decision Log: Manual Carb/Macro Intake

## Decision 1: Full spec workflow (not smolspec)

**Date**: 2026-07-07
**Status**: accepted

### Context

The user asked to "facilitate carb/macro data intake without the estimation/photo pipeline" with new input screens, a modal, quick-add presets, user-definable quicksets, and edit/delete of records. A scope assessment estimated ~450–700 LOC of new Swift across multiple new files, a new ledger event type, and edit/delete semantics touching the existing read-only meal model.

### Decision

Use the full spec workflow (requirements → design → tasks with approval gates).

### Rationale

Every full-spec threshold is met: >80 LOC, >3 files, multiple subsystems (UI + data layer), a new data-layer event type, and real design forks. The user also explicitly requested a full spec.

### Alternatives Considered

- **Smolspec**: Lightweight path — Rejected because the change exceeds every smolspec bound (LOC, file count, cross-cutting data-model impact).

### Consequences

**Positive:**
- Design forks (quick-add value source, event type, edit/delete scope) get resolved before implementation.

**Negative:**
- More upfront process than a direct build.

---

## Decision 2: Carbs required, macros optional, shown only in entry detail

**Date**: 2026-07-07
**Status**: accepted

### Context

The feature is framed as "carb/macro" intake. Capturing four fields (carbs, protein, fat, fibre) per entry conflicts with the low-friction goal; capturing carbs only drops the "macro" half of the framing.

### Decision

Each entry requires a carbohydrate value; protein, fat, and fibre are optional, hidden behind a disclosure so the default path is a single carb field.

### Rationale

Keeps the common case one number (matching the insulin single-value flow) while still allowing fuller nutrition when the user has it. Balances the "carb/macro" framing against the "minimise interaction" objective.

### Alternatives Considered

- **Carbs only**: Fastest — Rejected because it drops macros entirely, contradicting the feature's stated scope.
- **Carbs + all macros always**: Richest data — Rejected because four fields per entry works against one-tap logging.

### Consequences

**Positive:**
- Fast path stays a single field; macros available on demand.

**Negative:**
- The record model and UI must handle absent (not zero) macro values.

### Impact

Design-critic flagged that nothing in the app consumes protein/fat/fibre (graph + totals are carbs + glucose), making captured macros write-only. Resolved by giving macros a consumer: an entry's captured macros are displayed in its own detail/edit view (Req 2.4). No aggregate/graph macro view is in scope.

---

## Decision 3: Quick-add values are fixed and user-set (not food-DB backed)

**Date**: 2026-07-07
**Status**: accepted

### Context

Quick-add items such as "a pint", "bagel", and "chips" are portion/colloquial items. The bundled CoFID/AFCD food databases are keyed by segmentation class-id and do not contain these portion items, so a live lookup would frequently miss.

### Decision

Each quick-add preset stores a fixed carbohydrate (and optional macro) value defined when the preset is created. No food-database lookup.

### Rationale

Fixed values are reliable, predictable, and match how the user thinks about these items ("a pint = N g"). The food DB's class-keyed structure is a poor fit for portion presets.

### Alternatives Considered

- **Food-database lookup**: Cleaner provenance — Rejected because the DBs lack portion items like "a pint" and are keyed by segmentation class.
- **DB where matched, else fixed**: Flexible — Rejected as premature; adds a matching/fallback rule to design and test without a demonstrated need.

### Consequences

**Positive:**
- Simple, deterministic preset values; no dependency on food-DB coverage.

**Negative:**
- Preset carb values are the user's responsibility; no automatic nutrition sourcing.

---

## Decision 4: Edit/delete scoped to manual carb entries only

**Date**: 2026-07-07
**Status**: accepted (supersedes the initial "any ledger record" choice)

### Context

The user first chose low-friction edit/delete over "any ledger record". Design-critic review then surfaced two blocking problems: (1) editing a photo meal's carb value directly contradicts the append-only correction model (event-log-schema Req 4.4 keeps the meal event's `value` immutable; a corrections UI already exists), and (2) there is no unified records list today — meals are in the Data screen, insulin in Trends — and the unified `records` surface is owned by the future home-router spec, not this one. So "any record" would rework a settled data model and build a records surface this spec does not own.

### Decision

This spec makes only manually-added carb entries (keyed-in and quick-add) editable and deletable, via a list of recent manual entries reachable from the intake surface. Universal edit/delete over photo meals, insulin, and glucose is deferred to the records/home-router spec.

### Rationale

Manual carb records have no correction model, so they are freely mutable with no conflict. Confining edit/delete to them resolves the Req 4.4 contradiction, keeps this spec self-owned (no dependency on the unbuilt unified records surface), and still delivers the low-friction fix/remove the user asked for on the records this feature creates.

### Alternatives Considered

- **Any ledger record**: Uniform edit/delete — Rejected after review: contradicts the immutable-meal/correction model and depends on a records surface owned by another spec.
- **Manual + insulin**: Also covers doses (no correction model) — Rejected to keep this spec's scope to the carb-intake records it creates; insulin edit belongs with the records surface.

### Consequences

**Positive:**
- No conflict with the correction model; spec stays self-contained and focused.
- Delivers fix/remove on exactly the records this feature introduces.

**Negative:**
- Editing meals/insulin/glucose still requires the future records/home-router spec; until then those remain edited via their current flows (meal corrections, etc.).

---

## Decision 5: Home router is a separate parallel spec; this spec owns the intake route only

**Date**: 2026-07-07
**Status**: accepted

### Context

Asked where the entry point should live, the user rejected the current design (Graph as launch root, design-handoff-00 Decision 20/21). They want a new home page acting as the primary router to `intake` / `dose` / `records`, with Graph reduced to visualisation only. They noted this "may need to be tied to a parallel ui/ spec."

### Decision

The new home page, Graph demotion, and dose/records routing become a separate `specs/ui/` spec. This `manual-carb-intake` spec covers the intake content only and assumes the home router provides an `intake` route.

### Rationale

Keeps each spec focused and lets intake proceed in parallel with the navigation-shell redesign. Matches the user's own steer.

### Alternatives Considered

- **Include the home router here**: One spec — Rejected as too broad; it would couple intake delivery to a navigation-shell redesign affecting dose, records, and Graph.
- **Defer the home page**: Keep Graph as root — Rejected because it leaves the entry point where the user said it should not be.

### Consequences

**Positive:**
- Focused specs; intake is not blocked on the shell redesign.

**Negative:**
- A cross-spec seam: the intake surface needs a temporary entry point until the home-router spec lands.
- Reverses design-handoff-00 Decision 20 (Graph as launch root); the home-router spec must record that supersession.

### Impact

A new `specs/ui/` home-router spec must be created (flagged in `nextup.md`). The `no-disclaimer-copy` memory note ("Graph is the launch root") becomes stale once the home router lands.

---

## Decision 6: "Quickset" interpreted as a flat collection of presets

**Date**: 2026-07-07
**Status**: accepted (resolved 2026-07-10 at the design gate)

### Context

The user wrote "have a quickset of options and create and add our own quicksets." This reads two ways: (a) a quickset is one preset, and the user creates many presets; or (b) a quickset is a named *group* of presets (e.g. a "pub" set, a "breakfast" set).

Requirements landed with interpretation (a) (Req 3.1–3.3, Req 4.1–4.4 all describe a single collection of individually named presets, no grouping field anywhere) but this decision was left `proposed` pending confirmation. At the design gate, no new information favours (b): the home-router spec that landed in parallel treats Records as one flat, ungrouped timeline (home-router Decision 3, rejecting sectioned/filtered views for the same reason), and the project's stated bias for this spec is minimalist UI and less code.

### Decision

Quick-add presets are a single flat, user-editable collection. Named/nested groups are a non-goal for this spec.

### Rationale

A flat collection is the simplest thing that satisfies the one-tap goal and avoids grouping UI (create-group, rename-group, move-preset-between-groups) that works against "minimise interaction." It matches the requirements as written and the sibling home-router spec's own flat-timeline choice. Grouping is additive later — a `groupName` field could be added to the preset row without breaking the flat rendering — so nothing here forecloses it.

### Alternatives Considered

- **Named preset groups**: Organise presets into sets — Rejected as premature complexity; adds grouping UI (group CRUD, assignment) without a demonstrated need, and requirements as written describe single presets, not groups.

### Consequences

**Positive:**
- Simplest preset model and UI; matches requirements as written.
- A `groupName` column could be added later without reshaping the flat list.

**Negative:**
- If the user later wants named sets (e.g. "pub" vs "breakfast"), that is new scope, not covered here.

---

## Decision 7: A capture-born preset is a flat number plus a derived name, not a stored decomposition

**Date**: 2026-08-16
**Status**: accepted

### Context

The user asked to "save as preset on a successful capture, and use later on", because "same meal photo would be redundant if I've eaten at that place before". The value is skipping a capture, not storing a number.

A successful capture is rich: `MealRecord.macros.perClass` carries, per detected class, a `volumeCm3`, `massG`, `carbsG`, `betaUsed`, `betaStatus`, `densitySource`, `coefficientSource`, `isLiquid`, and `deviceVerified`, alongside frames, masks, a support plane, a scale, and a confidence result. A `QuickPreset` carries a name, one carbohydrate value, three optional macros, and a sort order. Something has to give, and how much is kept determines what "use later on" can mean: replaying a number, or replaying a meal.

### Decision

A capture-born preset stores the meal's flat carbohydrate total and a name derived from the meal's detected foods. The per-class decomposition is dropped and is not recoverable from the preset. Replay is the existing one-tap quick-add: it writes an `intake` event exactly as any other preset does, and never reconstructs a `MealRecord`.

### Rationale

The redundant thing the user wants to skip is the *capture*, and a capture's whole output for logging purposes is one carbohydrate number — that is all the graph, the daily totals, and the dose maths consume. Everything else in a `MealRecord` describes *this plate on this day under this camera pose*: it is evidence for how the number was derived, not a template for a future meal. Re-materialising it a week later would assert measurements that were never taken.

Keeping the flat shape also keeps one preset model and one replay path. A capture-born preset is the same row as a hand-authored one, so it inherits the tile, the tap, the edit, and the delete with no branch anywhere (Req 8.6) — the amendment adds an origin, not a mechanism.

The loss is real but it is carried by the name rather than by data: the pre-filled name is built from the detected class names, so "Rice + Chicken breast +1" is the decomposition's surviving trace, and the user's own edit ("Nando's half chicken") is a better key to "that place I've eaten before" than any stored geometry.

### Alternatives Considered

- **Store the full per-class decomposition on the preset and re-materialise a `MealRecord` on replay**: Highest fidelity; the replayed meal would appear in Records as a meal — Rejected because it fabricates evidence. The replayed record would carry volumes, a support plane, and a confidence figure derived from a capture that did not happen on that day, corrupting the corpus the calibration work reads, and it would need a synthetic-meal path the existing design already rejected once ("synthesizing a fake `MealRecord` for a typed-in number is the wrong shape").
- **Store a live reference to the originating meal and re-read its carbs at replay time**: No duplicated number; corrections to the meal would flow through — Rejected because it breaks the snapshot immutability the rest of the ledger assumes, and it dangles: the review surface's Retake and Delete both delete the meal, which would silently break the preset.
- **Store carbs plus the per-class rows for display only (an expandable preset tile)**: Keeps the detail visible without replaying it — Rejected as scope with no consumer; it needs a preset detail surface, and the decomposition it shows is about a plate the user is no longer eating.

### Consequences

**Positive:**
- One preset model, one replay path, no branch on origin anywhere in the UI or store.
- The ledger never gains a meal that was not captured.
- The photo capture is skipped for repeat meals, which is the whole ask.

**Negative:**
- The originating meal's decomposition is unrecoverable from the preset; a user wanting the breakdown must open the original meal in Records while it still exists.
- A preset is one number for the whole plate, so eating three quarters of the usual portion means editing the entry afterwards, exactly as with a hand-authored preset.

---

## Decision 8: Freeze the displayed, correction-adjusted total, not the pipeline's original estimate

**Date**: 2026-08-16
**Status**: accepted

### Context

Both result surfaces show a total that can differ from `record.macros.totalCarbsG`. The review surface computes `pendingTotalCarbsG` — the stored total plus per-row deltas — so relabelling a food, rejecting a row, setting a gram amount, or scaling the plate to ½ all move it. `ResultView` shows `heroCarbsG`, which resolves through the same correction machinery. By the time a user decides "this is my usual", they have typically already corrected it.

### Decision

The value carried into the preset is the total the surface is displaying at that moment, corrections included (Req 8.3).

### Rationale

The corrected figure is the best number available: it is the estimate plus everything the user knows that the pipeline did not. Freezing the raw estimate instead would silently discard the user's own corrections at the exact moment they are asserting the meal is worth repeating — and would produce a preset whose value disagrees with the screen the user was looking at when they tapped, which is indefensible.

Mechanically it is also the cheaper option: both totals are existing computed properties on surfaces that already own them, so no new derivation is written.

### Alternatives Considered

- **Freeze `record.macros.totalCarbsG` (the pipeline's original)**: Provenance-pure — the preset would carry exactly what the engine said — Rejected because it contradicts the displayed number and throws away the user's corrections, which are the more accurate input.
- **Offer both and let the user choose**: Maximum control — Rejected as a choice with an obvious answer; it adds a picker to a two-tap flow to serve a case that does not arise.

### Consequences

**Positive:**
- The preset always equals the number on screen when it was created.
- User corrections, the most reliable signal available, are what get reused.

**Negative:**
- Two surfaces compute the displayed total differently, so the draft builder takes the total as a parameter rather than deriving it — a small extra seam.
- The preset's value can no longer be traced back to the engine's raw output, only to what the user accepted.

---

## Decision 9: Carry carbohydrate only; do not pre-fill protein, fat, or fibre

**Date**: 2026-08-16
**Status**: accepted

### Context

A `QuickPreset` has optional protein, fat, and fibre fields, and a `MealRecord` does hold all three in `macros.clinicalTotals`. They are computed by the pipeline but deliberately not surfaced: `ClinicalMacros.proto` states *"Computed but not surfaced in v1 per Req 12.6"*, and the result surfaces render inert `"Protein — soon"` / `"Fat — soon"` placeholders. Fibre exists only as a meal-level total; no per-class figure is produced at all.

### Decision

A capture-born preset carries carbohydrate only. The protein, fat, and fibre fields are left absent for the user to supply, and the macro disclosure opens collapsed as it does for a blank preset (Req 8.4).

### Rationale

Pre-filling those fields would surface, as editable user-owned values, numbers the estimation spec deliberately keeps unsurfaced and unvalidated. A preset field reads as an assertion the user made; a clinical total is an unreviewed by-product. Laundering one into the other through a preset is a back door around another spec's scope decision, and this spec does not get to make that call on the estimation spec's behalf.

It is also consistent with Decision 2, which gave macros a consumer only in an entry's own detail and kept them out of every aggregate view.

### Alternatives Considered

- **Pre-fill all four from `clinicalTotals`**: Richest preset; the data already exists — Rejected because it surfaces figures the estimation spec keeps unsurfaced, and presents unvalidated pipeline output as a user assertion.
- **Pre-fill protein and fat but not fibre** (the two with per-class backing): Partially grounded — Rejected as the worst of both: it still surfaces unsurfaced values, and an inconsistent macro set is harder to explain than either extreme.

### Consequences

**Positive:**
- No unsurfaced pipeline value leaks into a user-owned record.
- The preset sheet behaves identically whichever origin opened it.

**Negative:**
- A user who wants macros on a capture-born preset types them, even though the app computed them.
- If Req 12.6 is later revisited and macros are surfaced, this decision should be revisited with it.

---

## Decision 10: The originating meal is a point-in-time stamp, never dereferenced

**Date**: 2026-08-16
**Status**: accepted

### Context

A capture-born preset raises the question of whether it should reference the meal it came from, and whether that reference is live or a snapshot. The spec already has a precedent: a quick-add entry carries `preset_id`, described in the design as *"a point-in-time provenance stamp, not a live reference"* — written at save time, never read back, tolerated as dangling when the preset is deleted.

There is a live consumer waiting, though. Estimates ship with β = 1 (`beta_status = 'uncalibrated_unity'` for every class), so a frozen preset freezes a known over-read. When calibration lands, being able to identify which presets were born from uncalibrated estimates is a real need, and origin is the only thing that can answer it.

### Decision

`quick_presets` gains a nullable `source_meal_id TEXT` holding the originating `MealRecord.id`; NULL means hand-authored. It is written once and never dereferenced — no preset read looks the meal up, and deleting the meal leaves the stamp dangling and inert. `QuickPresetEditSheet` must carry it through an edit unchanged (Req 8.9).

### Rationale

Following the `preset_id` precedent rather than departing from it keeps one provenance idiom in this spec: a snapshot that records where a value came from without making the value depend on that source still existing. It satisfies Req 8.8 by construction — there is nothing to cascade, nothing to invalidate — rather than by a deletion rule that would have to be written, tested, and remembered.

The nullability carries the useful fact on its own: non-NULL means "this number was frozen from an estimate", which is exactly the predicate a future recalibration sweep needs, and it survives deletion of the meal even though the id itself does not.

### Alternatives Considered

- **Store no origin at all**: Simplest; no schema change, no migration, and nothing currently reads the column — Rejected because it makes capture-born presets permanently indistinguishable from hand-authored ones, which forecloses ever answering "which of my presets froze an uncalibrated estimate?" — a question Decision 11 knowingly leaves open.
- **A live foreign key with `ON DELETE CASCADE` (or a nulling trigger)**: Referentially clean — Rejected because it makes deleting a meal destroy or mutate a preset the user created deliberately, contradicting Req 8.8 and the snapshot model the entry-side `preset_id` already established.
- **Copy the meal's `beta_status` / calibration state onto the preset instead of the meal id**: Answers the recalibration question directly without dangling — Rejected as premature: it commits to a specific future remediation shape, and today every class is `uncalibrated_unity`, so the column would be a constant.

### Consequences

**Positive:**
- Req 8.8 holds with no cascade logic; meal deletion cannot touch a preset.
- One provenance idiom shared with the entry-side `preset_id`.
- A future calibration sweep has a handle to find affected presets.

**Negative:**
- Another written-but-never-read column — the same honest weakness `preset_id` carries.
- A dangling `source_meal_id` cannot be resolved once the meal is deleted, so the "which meal" half of the stamp is best-effort; only the "born from a capture" half is durable.
- Forces schema 8 → 9 and the first additive `ALTER TABLE` in the store. `ADD COLUMN` is not idempotent in SQLite, so `migrate` changes from an unconditional re-stamp into a read-the-stored-version-then-act pair. It stays non-destructive, so event-log-schema Decision 10 ("no destructive DDL ships") is unaffected.

---

## Decision 11: Accept freezing an uncalibrated over-read; mitigate by editability, not by a gate

**Date**: 2026-08-16
**Status**: accepted

### Context

Every class ships β = 1 with `beta_status = 'uncalibrated_unity'`, and the result surface says so in as many words: *"Uncalibrated estimate — volume bias is not yet corrected, so this carbohydrate value is more likely too high than too low."* A capture-born preset freezes that bias permanently, and every later one-tap replay repeats it — turning a per-meal error into a recurring one for exactly the meals the user eats most.

### Decision

Freezing an uncalibrated value is accepted. The save-as-preset action is not gated on calibration state or confidence band, no warning copy is added, and no automatic re-derivation is planned. The mitigation is that the pre-filled value is editable in the preset sheet before it is saved, and editable again afterwards.

### Rationale

The number being frozen is the same number the app is already showing, already logging to the ledger, and already feeding into the dose maths. A preset does not make it worse in kind; it makes it repeatable — and a repeatable number is one the user can correct *once* against how they actually felt afterwards, which a fresh capture every time does not allow. Freezing is arguably the better position for a systematically biased estimator: a habitually eaten meal converges on a value the user has validated, instead of re-sampling the bias on every visit.

Gating the action on confidence would also be self-defeating in practice. Debug builds use the stub segmenter, so a placeholder gate would hide the action precisely in the build the developer exercises on device, and a very-low-confidence gate would remove the escape hatch from the meals most in need of a user-supplied number.

Warning copy is out of the question regardless: `CLAUDE.md` bans reassurance and disclaimer messaging in developer-phase UI, and the uncalibrated banner already sits on the same screen, so the fact is stated once where it belongs.

### Alternatives Considered

- **Gate the action on a calibrated β (or on confidence ≥ moderate)**: Prevents freezing a known-biased number — Rejected because with β = 1 everywhere it would disable the feature entirely today, and it withholds the manual override from exactly the low-confidence meals that need it most.
- **Store the β state alongside the value and auto-re-derive presets when calibration lands**: Self-healing — Rejected as speculative: it commits now to a remediation whose shape depends on a calibration scheme that does not exist, and silently changing a value the user saved and may have already corrected is its own defect. Decision 10's `source_meal_id` leaves the door open to do this deliberately later.
- **Show a warning on the preset sheet when the value came from an uncalibrated estimate**: Informative — Rejected: banned by the developer-phase no-disclaimer rule, and redundant beside the uncalibrated banner already on the result surface.

### Consequences

**Positive:**
- The feature works today rather than waiting on calibration.
- A repeated meal's value can be corrected once and reused, which beats re-sampling the bias every visit.
- No new copy, no new gate, no new branch.

**Negative:**
- A preset saved without editing carries the over-read indefinitely, and every replay repeats it.
- Nothing prompts the user to revisit presets when calibration lands; that remediation is future work, with `source_meal_id` as its only handle.

---

## Decision 12: Offer the action on both result surfaces, in each one's existing overflow menu

**Date**: 2026-08-16
**Status**: accepted

### Context

There are two result surfaces. `MealReviewView` is the post-capture surface, pushed the moment an estimate succeeds; `ResultView` is the history read path, reached from Records or the graph. The user's request names the capture ("save as preset on a successful capture"), but the realising moment is often later — you learn a meal is a repeat on the *second* visit, by which time the first capture is history.

Both surfaces already carry a trailing overflow `Menu` (`Retake`/`Delete` on review, `Delete` on result), and both already hold a `store`.

### Decision

The action appears on both surfaces, as one non-destructive `Button` in each existing overflow menu, labelled "Save as quick-add" — the string `CarbEntrySheet` already ships for the same operation.

### Rationale

Restricting it to the post-capture surface would meet the letter of the request and miss its point: the user recognises a repeat retrospectively, and Records is where they are standing when they do. The marginal cost is one menu item over a shared draft builder, so the second surface is close to free.

Reusing the existing menus keeps both action rows unchanged — the review row is a single primary "Record N g" and the result row a single "Done", both deliberately sparse — and reusing the existing label keeps one phrase for one operation rather than teaching a second name for it.

### Alternatives Considered

- **Post-capture surface only**: Matches the request literally and is the smaller change — Rejected because a repeat meal is usually recognised after the fact, which is exactly when the capture is already in history.
- **A prominent button in the action row rather than a menu item**: More discoverable — Rejected because it competes with the single primary action on both surfaces; saving a preset is a deliberate, occasional act, which is what an overflow menu is for.
- **Records list swipe action instead of the result surface**: Reachable without opening a meal — Rejected because the pre-filled value must be the *displayed, corrected* total (Decision 8), which only exists once the surface has computed it.

### Consequences

**Positive:**
- Works both at capture time and retrospectively from history.
- No layout change on either surface; one shared draft builder serves both.

**Negative:**
- Two call sites to keep in step; a change to the draft rules must be verified on both.
- The action is one level down in a menu, so it is not discoverable without opening it.

---
