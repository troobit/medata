# Decision Log: Home Router

## Decision 1: Full spec workflow (not smolspec)

**Date**: 2026-07-07
**Status**: accepted

### Context

The feature introduces a new launch root, re-roots the navigation shell (reversing design-handoff-00 Decision 20), moves every entry point off the Graph toolbar, and adds a records surface that spans all three event types. A scope assessment estimated well over 80 LOC across 6+ files (new home view, records view, `AppRoot`, `TrendsView`, route enums, a unifying record model), with breaking navigation changes and cross-cutting data-layer concerns.

### Decision

Use the full spec workflow (requirements → design → tasks with approval gates).

### Rationale

Every full-spec threshold is met: >80 LOC, >3 files, multiple subsystems (shell + data layer), breaking navigation change, and reversal of two accepted decisions. The user approved the full-spec path at scope assessment.

### Alternatives Considered

- **Smolspec**: Lightweight path — Rejected because the change exceeds every smolspec bound (LOC, file count, breaking navigation change, cross-cutting data model).

### Consequences

**Positive:**
- The shell inversion and records-model forks get resolved before implementation.

**Negative:**
- More upfront process than a direct build.

---

## Decision 2: Home page is a pure router, no summary data

**Date**: 2026-07-07
**Status**: accepted

### Context

The new home page could be either a plain navigation hub or a hub that also surfaces at-a-glance data (today's carb total, latest glucose). More on the home page means more to build and maintain.

### Decision

The home page is a pure router: controls to Capture, Intake, Dose, Records, Graph, and Settings, and nothing else. No summary data.

### Rationale

The smallest thing that satisfies "a home page that routes to everything." A summary duplicates what Graph and Records already show and can be added later if wanted. User chose the pure-router option at the requirements gate.

### Alternatives Considered

- **Router + summary**: Home also shows today's carbs / latest glucose — Rejected as premature; duplicates Graph/Records and adds surface without a demonstrated need.

### Consequences

**Positive:**
- Minimal home page; fastest to build.

**Negative:**
- The user must open Graph or Records to see any data — the home page shows none.

---

## Decision 3: Records is a merged chronological timeline

**Date**: 2026-07-07
**Status**: accepted

### Context

The records surface must show three event types (meals, insulin, glucose) that today live on three different screens. It could interleave them in one list or split them into per-type sections/filters.

### Decision

Records is one chronological timeline, most-recent-first, with all three types interleaved and each row tagged by type.

### Rationale

A single timeline is the closest match to "one place that lists everything" and avoids the sectioning/filter UI, which works against a quick review-and-remove flow. User chose the merged-timeline option.

### Alternatives Considered

- **Sectioned/filterable by type**: Meals / Insulin / Glucose tabs or a segmented filter — Rejected as more UI than the review-and-delete task needs; grouping can be added later.

### Consequences

**Positive:**
- One list, one mental model; simplest records UI.

**Negative:**
- Three decode paths (meal protobuf, insulin JSON metadata, glucose value) must render into one row model; no per-type filtering.

---

## Decision 4: Records is delete-only; in-place editing deferred

**Date**: 2026-07-07
**Status**: accepted (supersedes the requirements-gate "editable" selections)

### Context

At the requirements gate the user initially selected editable+delete for meals (via the corrections flow) and for insulin (reopening the dose sheet). The user then interrupted to revise: records should be delete-only for both meals and insulin — "if they're wrong we can re-add them" — with editing deferred to a future feature if UX testers find it necessary. Less code is preferred for now.

### Decision

The Records surface deletes meals and insulin doses; it does not edit any record in place. Editing is out of scope for this spec.

### Rationale

Delete-and-re-add covers the correction need for the low-friction manual records with far less code than an edit UI, and it sidesteps the immutable-meal/append-only-correction conflict entirely (delete already exists and cascades; editing a meal's carb value would have required routing through the corrections model). Editing can be added later once UX testing shows it is needed. Direct user steer.

### Alternatives Considered

- **Editable + delete (meals via corrections flow, insulin via dose sheet)**: Uniform edit/delete — Rejected by the user as more code than warranted now; editing deferred.
- **Full in-place meal value edit**: Simplest UX — Rejected because it breaks the append-only correction model (event-log-schema Req 4.4).

### Consequences

**Positive:**
- Much less code; no edit UI, no corrections-flow coupling, no immutable-meal conflict.
- `deleteMeal`/`deleteInsulinEvent` already exist and cascade correctly.

**Negative:**
- Fixing a mistimed or mis-valued record means delete then re-add. Editing must arrive as a later feature if UX testing demands it.

---

## Decision 5: Glucose is read-only on the Records surface

**Date**: 2026-07-07
**Status**: superseded by ui/records-deletion Decision 3 (glucose rows become deletable via a bsl-gated `deleteBslEvent(id:)`)

### Context

Glucose readings are import-sourced from LibreLink screenshots via a keep-first merge; there is no glucose edit/delete UI today. The records surface could make glucose deletable (or editable) for uniformity with meals and insulin.

### Decision

Glucose rows appear on the Records timeline but are read-only — neither editable nor deletable.

### Rationale

A deleted glucose reading would be reintroduced by the next import (keep-first merge), so a delete affordance would appear not to work. Glucose has an authoritative external source; meals and insulin are user-entered and freely re-addable. Keeping glucose read-only matches its provenance and avoids a confusing no-op.

### Alternatives Considered

- **Editable + delete**: Most uniform — Rejected; lets manual edits diverge from the import source and a delete is undone on re-import.
- **Hide glucose from Records entirely**: Simplest — Rejected; the user wants one place that lists everything recorded, and glucose is part of the record.

### Consequences

**Positive:**
- No misleading no-op affordance; glucose stays consistent with its import source.

**Negative:**
- The Records surface has an asymmetry — two of three types are deletable, one is not.

---

## Decision 6: The Records surface replaces the meal-only Data screen

**Date**: 2026-07-07
**Status**: accepted

### Context

Today the Data screen (`DataView`) lists meals only, presented as a full-screen cover from the Graph toolbar. The new Records surface lists meals plus insulin and glucose. Keeping both would leave two meal lists.

### Decision

The Records surface supersedes the meal-only Data screen; the home page routes to Records, not to a separate Data screen.

### Rationale

Two overlapping meal lists is redundant. Records is a superset of what Data showed, so folding Data into Records keeps a single records place and one fewer route.

### Alternatives Considered

- **Keep Data and add Records alongside**: Least disruptive — Rejected; two meal lists confuse and duplicate.

### Consequences

**Positive:**
- One records place; one fewer home route to reason about.

**Negative:**
- `DataView`'s meal-specific presentation is absorbed into the unified timeline; any meal-only affordances must be preserved on the meal row/detail.

---

## Decision 7: Reverses design-handoff-00 Decision 20 (Graph as launch root)

**Date**: 2026-07-07
**Status**: accepted

### Context

design-handoff-00 Decision 20 made Graph the launch root with Capture/Data/Settings/Insulin entry points on its toolbar. This spec introduces a home page as the root and moves those entry points onto it, directly reversing that decision. The project `no-disclaimer-copy` memory also records "Graph is the launch root," which becomes stale.

### Decision

Record that this spec supersedes design-handoff-00 Decision 20. Graph is no longer the launch root; the home page is.

### Rationale

The user directed the change; capturing the supersession keeps the decision history traceable and prevents re-litigation. The AR-session-only-while-Capture lifecycle from Decision 20 is preserved, now anchored at the home root.

### Alternatives Considered

- **Leave Graph as root**: No shell change — Rejected; the user explicitly wants a home router with Graph as visualisation only.

### Consequences

**Positive:**
- Traceable supersession; the shell history stays coherent.

**Negative:**
- Third re-root of the app in the design-handoff-00 history; the `no-disclaimer-copy` memory note ("Graph is the launch root") must be updated once this lands.

---

## Decision 8: Records is all-time and unwindowed; delete is immediate via standard swipe-reveal

**Date**: 2026-07-07
**Status**: accepted

### Context

Design-critic review raised two records-surface concerns. (1) Volume: glucose is bulk-imported from LibreLink (dozens of readings/day), so an unbounded merged timeline could bury the meals/insulin the user came to delete. (2) Safety: a meal delete is irreversible and cascades the meal's corrections and stored photo artefacts, yet an inline swipe offers no confirmation. Both were put to the user as explicit choices.

### Decision

The Records timeline lists all records for all time with no windowing, pagination, or filtering. Deletion uses the standard iOS swipe-to-delete interaction (swipe reveals a Delete button); tapping it deletes immediately with no additional confirmation dialog.

### Rationale

The user chose the simplest build for both: accept the glucose volume rather than add windowing/pagination code, and rely on the swipe-reveal's inherent two-step (swipe, then tap Delete) rather than an extra confirmation. This matches the feature's low-friction, "less code for now, re-add if wrong" philosophy. If real-world glucose volume or accidental deletes prove painful in UX testing, windowing and/or confirmation can be added later.

### Alternatives Considered

- **Windowed timeline (day-grouped, recent-first, load-more)**: Bounds glucose volume — Rejected by the user in favour of the simpler all-time list.
- **Exclude glucose from Records**: Removes the volume problem — Rejected; the user wants one place listing everything, and glucose already appears read-only.
- **Explicit confirmation dialog on delete**: Safer against accidental loss — Rejected as unnecessary friction over the standard swipe-reveal.

### Consequences

**Positive:**
- No windowing/pagination or confirmation-dialog code; simplest records surface.

**Negative:**
- The timeline degrades as imported glucose accumulates; meals/insulin can be sparse among glucose rows.
- An accidental swipe-then-tap destroys a meal plus its corrections and photos with no undo.

---

## Decision 9: AppRoot stays the presentation coordinator; HomeView is root content only

**Date**: 2026-07-10
**Status**: accepted

### Context

Re-rooting the shell (Req 2.1) could put presentation state (cover selection, insulin sheet, deep-link deferral, AR-session trigger) into the new `HomeView`, or keep it in `AppRoot` and only swap the root content. `AppRoot` currently owns all of that state and drives the AR session from `onChange(of: activeSheet)`.

### Decision

`AppRoot` remains the presentation coordinator; only its root content changes from `TrendsView` to `HomeView`. `HomeView` holds no presentation state — it invokes routes through closures injected by `AppRoot`.

### Rationale

The deep-link handler, deferral state, and AR-session lifecycle are already correct and centralised in `AppRoot`; moving them into `HomeView` would re-implement working logic for no gain. Swapping only the root content is the minimal change and keeps the AR-session trigger keyed on `activeSheet == .capture` regardless of what the root is.

### Alternatives Considered

- **HomeView owns presentation state**: Self-contained root — Rejected; duplicates/relocates working deep-link + AR-session logic and widens the change surface.

### Consequences

**Positive:**
- Minimal diff; deep-link and AR-session behaviour preserved verbatim.

**Negative:**
- `AppRoot` keeps growing as the single coordinator; `HomeView` depends on injected closures rather than being self-contained.

---

## Decision 10: Dose stays a sheet, relocated from TrendsView to AppRoot

**Date**: 2026-07-10
**Status**: accepted

### Context

Insulin dosing is today a `.sheet(isPresented: $showInsulinSheet)` presented from `TrendsView` (the old root), reachable from the Graph toolbar and `medata://insulin/add`. With Graph demoted, the Dose control lives on the home page, and Req 1.6 requires the control and the deep link to open the *same* sheet.

### Decision

Dose remains the existing insulin dose-entry `.sheet` (not a new `ActiveSheet` cover); its presentation and the `onInsulinSheetDismiss` pending-deep-link handoff relocate from `TrendsView` to `AppRoot`.

### Rationale

A `.sheet` coexists with the mutually-exclusive cover `item:`, so keeping Dose a sheet avoids collapsing it into the cover enum and preserves the exact dose-entry surface the deep link already targets. It must move to `AppRoot` because its old host (`TrendsView`) is no longer the root.

### Alternatives Considered

- **Make Dose a `fullScreenCover` case**: Uniform with other routes — Rejected; changes the dose surface, and the cover `item:` is single-select so it would fight the deep-link deferral that already toggles the sheet independently.

### Consequences

**Positive:**
- Same dose sheet as today; deep-link deferral logic unchanged.

**Negative:**
- `AppRoot` presents both a cover `item:` and a `.sheet`; two presentation channels to reason about.

---

## Decision 11: Graph keeps meal tap-through; only its direct delete affordance is removed

**Date**: 2026-07-10
**Status**: accepted (tap-through destination redefined by Decision 16: the shared meal detail is `ResultView`; `MealOverviewView` is deleted)

### Context

Req 2.4 forbids record deletion on Graph. Graph's Day view has two inline lists: day-meals whose rows navigate to `MealOverviewView` (which itself can delete), and day-insulin with swipe-to-delete. Removing the meal navigation would fully sever any delete path from Graph; keeping it re-exposes delete transitively through the shared meal detail.

### Decision

Remove only Graph's direct delete affordance — the day-insulin swipe-to-delete. Keep the day-meal list navigating to the shared `MealOverviewView`. Graph presents no delete UI of its own; deletion reachable via the shared meal detail is accepted.

### Rationale

User decision at the design gate ("keep meal tap-through"). Req 2.4 is satisfied at the Graph surface — Graph shows no delete control — while the meal detail stays a single shared screen rather than being forked into deletable and non-deletable variants.

### Alternatives Considered

- **Read-only, no navigation**: day breakdown non-navigating — Rejected by the user; removes a useful jump to meal detail.
- **Drop the inline lists entirely (chart-only)**: Simplest "visualisation only" — Rejected; changes the Day view more than Req 2.2's "unchanged visualisation" intends.

### Consequences

**Positive:**
- Meal detail stays one shared screen; Graph's Day view keeps its jump-to-detail.

**Negative:**
- A delete is still reachable in two taps from Graph via the shared detail; "no deletion on Graph" holds only for Graph's own chrome.

---

## Decision 12: Intake seam assumes IntakeView exists; designed for minimal merge conflict

**Date**: 2026-07-10
**Status**: accepted

### Context

The `intake` route's content is owned by the parallel `manual-carb-intake` spec (Track C). The user directed that this design assume that surface already exists and structure the seam so the two parallel streams rarely edit the same lines.

### Decision

`ActiveSheet.intake` constructs a `manual-carb-intake`-owned `IntakeView()` by name in a one-line cover branch. `RecordRow` is an open enum so `manual-carb-intake` adds a single `.intake(IntakeRecord)` case plus one additive merge source in `RecordsModel`, making manual intake records deletable in Records without reworking existing cases. The intake subtype taxonomy lives inside `IntakeRecord` (Decision 14), not in `RecordRow`.

### Rationale

The two seams differ in kind. The `IntakeView` seam is genuinely disjoint: home-router owns the `ActiveSheet.intake` case and its one-line cover branch; Track C owns `IntakeView` in its own file, a line home-router never edits. The `RecordRow` seam is shared-file **additive**: Track C adds a single `.intake(IntakeRecord)` case plus arms in the `timestamp`/`id` switches and one merge line in `RecordsModel` — same files home-router authored, but additive arms (Swift exhaustiveness), so low collision rather than zero. Because intake subtypes live inside `IntakeRecord` (Decision 14), adding subtypes later touches neither `RecordRow` nor home-router. Either delivery order merges cleanly. This also gives `manual-carb-intake`'s deferred edit/delete a home on the Records surface.

### Alternatives Considered

- **Feature-flag / placeholder / disabled interim control**: Ship Intake inert until Track C lands — Rejected per the user's "assume it exists" directive; adds throwaway code and a dead control.

### Consequences

**Positive:**
- Parallel streams merge with minimal conflict; no interim placeholder code; manual carb records get delete via Records.

**Negative:**
- Home-router does not compile end-to-end on its own branch until `IntakeView` exists; the `intake` route is a forward reference until the streams meet.

---

## Decision 13: Unified RecordRow enum; relocate shared meal-routing symbols out of DataView

**Date**: 2026-07-10
**Status**: accepted

### Context

`RecordsView` replaces `DataView`, which is removed. Two symbols live in `DataView.swift` but are used by surfaces that remain: `mealRouteDestination(_:store:path:)` (meal-detail navigation, used by `TrendsView` and the new `RecordsView`) and `CloseCoverButton` (used by four surfaces). The three record types must render into one list.

### Decision

Introduce a `RecordRow` view-model enum (`meal`/`insulin`/`glucose`, open for `.intake(IntakeRecord)`) with a `timestamp` sort key and a stable `id` tie-break. `RecordRow.meal` carries a `DisplayMeal` (the corrected-total overlay), not a raw `MealRecord`; glucose carries the source `Event.id` since `GlucoseReading` has none. Relocate `mealRouteDestination` and `CloseCoverButton` from `DataView.swift` into a shared `App/MealRouting.swift` so removing `DataView` does not orphan them. `RecordsModel` maps each source **directly** (reusing `MealHistoryModel`'s corrections composition for meals); it does **not** reuse `TrendsModel`'s plotting decoders.

### Rationale

Records needs one row abstraction over three decode paths; relocating the shared symbols is required to delete `DataView` without breaking `TrendsView`. Two corrections surfaced in design-critic review forced the payload/decoder choices: (1) `MealRecord.macros.totalCarbsG` is the *original* estimate, so Req 3.2's corrected total must come from the `DisplayMeal`/`MealHistoryModel` overlay — the same reason those types already exist; (2) `TrendsModel`'s glucose decoder drops `Event.id`, so reusing it would leave glucose without a tie-break key, and `TrendsModel` carries a documented perf-hang history (`graph-month-selection-hang`). Mapping directly in `RecordsModel` keeps the source ids and leaves the perf-sensitive file untouched — no requirement demanded the shared-decoder DRY win.

### Alternatives Considered

- **Reuse `TrendsModel`'s glucose/insulin decoders via a shared helper**: DRY — Rejected; drops `Event.id` (breaks the glucose tie-break) and churns a perf-hang-prone file for no required benefit.
- **`RecordRow.meal(MealRecord)` with the raw estimate**: Simpler payload — Rejected; cannot satisfy Req 3.2 (shows the pre-correction total).
- **Add an `id` to `GlucoseReading`**: Uniform ids — Rejected; touches Persistence + its MedataCore test coverage when keeping the source `Event.id` at the row costs nothing.
- **Keep the symbols in `DataView.swift` as a symbol dump**: No move — Rejected; leaves a dead view file solely to host shared helpers.

### Consequences

**Positive:**
- One row abstraction; shared symbols have a clear home; each type keeps a stable id and the meal row shows the corrected total.
- `TrendsModel` is untouched; `RecordRow` extensibility is the Track C seam (Decision 12).

**Negative:**
- A new `MealRouting.swift` file, and `RecordsModel` reuses `MealHistoryModel`'s per-meal corrections composition — a full rebuild per `eventsDidChange` tick (accepted under Decision 8).

---

## Decision 14: Intake is one `RecordRow` case with an internal subtype, not per-subtype cases

**Date**: 2026-07-10
**Status**: accepted

### Context

The Records seam for `manual-carb-intake` (Track C) needs a shape for manual intake records. The user's model is "intake with subsets — carb, alcohol, and so on." That could be one `RecordRow.intake` case carrying a category, or a case per subtype (`.carbIntake`, `.alcoholIntake`, …). This design owns only the *seam shape*; the taxonomy itself belongs to Track C.

### Decision

`RecordRow` gains a single `.intake(IntakeRecord)` case (a discriminated union) whose subtype (`carb`, `alcohol`, …) is a field inside the Track-C-owned `IntakeRecord`. Home-router renders an intake row from `IntakeRecord`'s own display value + type label and stays agnostic to the category set. The subtype identifier for alcohol is `alcohol`, not `booze`.

### Rationale

One case with the subtype in the payload keeps `RecordRow`'s `timestamp`/`id`/render switches stable as subtypes grow, and — key for the two parallel streams — adding a subtype later touches neither `RecordRow` nor any home-router file. It mirrors the app's event-log philosophy (one type, discriminator inside) and aligns with the route already being named `intake`. `alcohol` is the clinical/nutrition term and is substantive here (alcohol can drive delayed hypoglycaemia), so it earns a first-class subtype; `booze` is acceptable only as later UI copy, never as the code identifier. The concrete category set and `IntakeRecord`'s fields are Track C's to define — this decision fixes only that intake is one row case with an internal category.

### Alternatives Considered

- **A `RecordRow` case per subtype (`.carbIntake`, `.alcoholIntake`, …)**: Explicit — Rejected; explodes `RecordRow`'s switches and forces a home-router edit for every new subtype.
- **`booze` as the code identifier**: Matches the user's casual phrasing — Rejected for code; `alcohol` is the clinical term and reads correctly in a health context. "Booze" may resurface as UI copy if wanted.

### Consequences

**Positive:**
- `RecordRow` is stable against subtype growth; new intake subtypes are a pure Track C change.
- Clear ownership split: home-router fixes the seam shape, Track C owns the taxonomy.

**Negative:**
- Home-router references `IntakeRecord` before Track C defines it (the same accepted forward-reference as `IntakeView`, Decision 12).
- Intake-row rendering depends on `IntakeRecord` exposing a display value + label; that contract must be agreed with Track C.

---

## Decision 15: Home shows the latest glucose reading, narrowing the pure-router rule

**Date**: 2026-08-04
**Status**: accepted (narrows Decision 2; its display-only rule is superseded by `specs/data/fingerprick-glucose` Decision 5, which makes the reading a route to Graph — the "obvious first extension" anticipated below)

### Context

Decision 2 made the home page a pure router with no summary data, on the reasoning that a summary duplicates Graph and Records and had no demonstrated need. The on-device pass of task 9 supplied that demonstration: the router itself was judged fine, but the reading the developer checks most often — current blood sugar — required opening Graph every time, and the app's whole reason to exist sits downstream of that number.

Two mechanisms already existed to serve it: the lock-screen widget's `GlucoseSnapshot` pipeline (`GlucoseWidgetPublisher` → App Group defaults → `GlucoseTimeline.render`), and the store rows both it and Graph read. The choice was which to reuse, and how much of the widget's staleness ladder applies to an in-app surface.

### Decision

The home page shows the most recent glucose reading, in mmol/L, as its topmost and most prominent content, with a trend arrow when the readings support a rate. It is display-only and not a route. Everything else stays out of Decision 2's non-goal — no carb total, no insulin-on-board, no chart.

The reading is derived by a new shared `GlucoseSnapshotSource` in `Persistence`, called by both the home model and the widget publisher, and read from the **store** rather than from the App Group container. Freshness reuses `GlucoseTimeline.staleAge` to gate the arrow and the band colour, but home shows the *value* at any age with its age beside it — it does not adopt the widget's 30-minute number-withholding rung.

### Rationale

Promoting one value is not the "router + summary" alternative Decision 2 rejected: that was a roll-up of derived totals duplicating Graph. This is the single live measurement the app is built around, and it is not derived from anything else on the home page.

Sharing the derivation is the load-bearing part. Two surfaces independently computing "the latest reading and its trend" is exactly how they drift, and this derivation already carries a field-learned rule — the one-hour future-skew window bound from `glucose-widget-lagged-a-reading-behind` — that a second implementation would have to re-learn the same painful way. Extracting it makes agreement structural (Req 4.7) rather than a convention.

Reading the store rather than the App Group snapshot matters right now: `glucose-lock-widget` task 14 (the App Group round-trip) is still unverified on device, and a nil-suite `UserDefaults(suiteName:)` hands back a *private* store rather than failing, so a misprovisioned App Group would silently render home as "never recorded". The app has the rows; there is no reason to route them through a container it does not need.

Withholding the number past 30 minutes is right for the lock screen — a glance with no context, where a stale number reads as current — and wrong here. Home is entered deliberately, the age sits beside the value, and "show me my most recent reading" is the stated requirement; a surface that answers it with "1 h ago" and no number has not answered it. The arrow and the band colour are withheld because they are statements about *now* (a rate, a position against target), not about the reading.

### Alternatives Considered

- **Keep Decision 2 unchanged; route to Graph for glucose**: No new surface, no new code — Rejected: the device pass identified this as the gap, and one tap per glance for the app's central number is the cost Decision 2 accepted before that evidence existed.
- **Read `GlucoseSnapshotStore` (the App Group defaults) instead of the store**: Zero query cost, exactly what the widget shows — Rejected: it makes an in-app surface depend on unverified App Group provisioning, and a missing entitlement degrades silently to "never recorded" rather than failing loudly.
- **Reuse `GlucoseTimeline.render` wholesale**: One ladder, no divergence to explain — Rejected: its `.lastReading` rung structurally drops the value, contradicting Req 4.2. Adding a fourth case for home would push a home-page rule into the widget's contract.
- **Duplicate the derivation in `HomeGlucoseModel`**: No change to shipped widget code — Rejected: guarantees the two surfaces drift, and would have shipped without the future-skew window bound.
- **Make the reading tappable, routing to Graph**: Natural affordance, matches the widget's `medata://graph` tap target — Rejected for now as scope beyond the ask; the reading stays display-only (Req 4.8) and this is the obvious first extension if the device pass wants it.

### Consequences

**Positive:**
- The number the app is built around is visible at launch with no navigation.
- Home and the lock-screen widget cannot disagree about the latest reading — one derivation, one set of window rules.
- The future-skew bound and the display horizon now have a single stated home instead of living in an App-target actor.
- Home works correctly on a build whose App Group is not provisioned.

**Negative:**
- Home is no longer a pure router; the next "just one more number" request has a precedent to point at, and Decision 2's line now needs defending case by case.
- One more `eventsDidChange` subscriber rebuilding on every tick — bounded (a 24-hour `bsl` read, ~288 rows) but no longer zero, and it runs while home is the visible root.
- Home and the widget deliberately differ past 30 minutes, so "what does the app show for a stale reading" now has two correct answers depending on the surface.
- `Persistence` gained a small public surface (`GlucoseSnapshotSource`) that exists for two callers.

---

## Decision 16: A tapped meal row lands on one detail surface; the overview hop is deleted

**Date**: 2026-08-26
**Status**: accepted

### Context

`specs/ui/design-handoff-00` introduced the Meal overview as its own page ("Meal overview (§9) — new `MealOverviewView.swift`") with the full detail one push deeper: "Overview → Full result → Done lands back on Overview" (`specs/ui/design-handoff-00/design.md`). This spec carried that chain into Records unchanged. `specs/ui/meal-review` later collapsed the *capture* stack to a single surface ("Collapse the read-only segmentation review and the result screen into one post-capture surface") and demoted `ResultView` to the history read path — leaving history the only path where a meal's detail still sits behind an intermediate summary. `specs/data/insulin-dosing` task 8 then added a third, DEBUG-only push (`⋯ → Review`) because the dose surface was unreachable from history at all. On device, the tap lands on a summary whose per-food rows, adjustment surface, and dose readout each require a further push — the detail reads as hidden.

### Decision

A meal row in Records and in the Graph's day list navigates directly to `ResultView` as the one meal-detail surface, which absorbs the overview's remaining content (capture-metadata line, delete menu with confirmation, mask-overlaid photo) and renders the recorded dose readout (`specs/data/insulin-dosing` Req 6.10). `MealOverviewView`, `MealRoute.overview`, and the DEBUG `MealRoute.review` push are deleted.

### Rationale

`ResultView` already holds the per-food rows with the serving-adjustment surface, corrections handling, the photo, the recorded dose-suggestion line, and the quick-preset draft — the overview duplicated a subset of it and existed only to push to it. Deleting the summary rather than enriching it follows the precedent `specs/ui/meal-review` set for the capture stack: one surface per meal, everything on it. Req 3.3 is redefined in place to require the single screen.

### Alternatives Considered

- **Keep the overview and add the dose line to it**: The smallest edit — rejected because the adjustment surface and per-food detail stay a push deeper; the intermediate hop is the defect, not the missing line.
- **Reuse `MealReviewView` as the history surface**: Already a one-surface meal view — rejected because its verbs are capture verbs (Record, Retake); a stored meal is already recorded, and the DEBUG route's Retake-means-delete compromise showed the fit is wrong.
- **A new combined view replacing both**: Rejected as duplication; `ResultView` already is the combined view minus ~three overview-only elements.

### Consequences

**Positive:**
- One tap from Records or the Graph to a meal's full detail, dose readout included.
- `MealOverviewView` (~246 lines duplicating `ResultView` content) is deleted; `specs/ui/shared-meal-components` loses a consumer, which lowers its DRY surface.
- The DEBUG-only third page and its Retake-means-delete compromise go away.

**Negative:**
- `ResultView` grows the overview-only elements (metadata line, delete confirmation, overlay photo path) on an already-large file.
- `specs/data/insulin-dosing` task 16's review-line judgement loses its no-camera entry point; judging the review line now requires a real capture.
- design-handoff-00 §9's page documentation is superseded and must say so.

---
