# Decision Log: design-handoff-00

## Decision 1: Name the spec after the numbered handoff series

**Date**: 2026-07-04
**Status**: accepted

### Context

The first external design handoff arrived in `tmp/design/design_handoff_medata/`. The user requires the design references to be flexible, durable, and versionable, since the UI design is expected to change again.

### Decision

Name the spec `specs/ui/design-handoff-00/` and archive the handoff under `design-system/wireframes/design-handoff-00/`. Future handoffs increment the number (01, 02, …) as new specs and archives.

### Rationale

Numbering the handoff makes the design source itself the versioned artefact: each spec is pinned to exactly one handoff, and a future redesign is a new numbered pair rather than an in-place rewrite. The user chose `design-handoff-00` over the proposed `design-handoff-v2`.

### Alternatives Considered

- **`ui-refresh`**: Outcome-named - Rejected as vague once a second refresh lands
- **`trends-and-redesign`**: Capability-named - Rejected; the handoff spans all screens, not just Trends

### Consequences

**Positive:**
- Deterministic naming for future handoffs; archive and spec share one id
- Git history plus the manifest give the durable pinning the user asked for (Decision 10 dropped the explicit SHA field)

**Negative:**
- The name says nothing about content; readers need the spec introduction

---

## Decision 2: Adopt the scaffold's Capture-rooted navigation shell

**Date**: 2026-07-04
**Status**: accepted

### Context

The existing app implements a three-tab `TabView` (Photo / Meals / Settings) per `specs/ui/iphone-experience/` (v1.1, Done). The handoff scaffold instead roots a single `NavigationStack` on the Capture screen with Data, Trends, and Settings presented as sheets.

### Decision

Adopt the handoff's Capture-rooted shell. The tab-shell requirements of `iphone-experience` are superseded on this point.

### Rationale

The user confirmed the scaffold shell. It makes capture the zero-friction default action, matches the wireframes, and gives Trends a natural home without inventing a fourth tab.

### Alternatives Considered

- **Keep tabs, adopt screens**: Less churn - Rejected; diverges from the wireframes and leaves Trends without a designed slot
- **Decide during design**: Defer - Rejected; the shell shapes too many requirements to leave open

### Consequences

**Positive:**
- Matches the design handoff exactly; simpler root hierarchy
- Launch lands directly on the camera

**Negative:**
- Supersedes a Done spec's shell; `iphone-experience` needs a supersession note
- Tab-era code (AppTab, tab wiring) becomes dead and must be removed

---

## Decision 3: Glucose = local `bsl` events + opt-in read-only HealthKit import

**Date**: 2026-07-04
**Status**: superseded by Decision 6 (importer portion only — the read-from-`bsl` portion stands as Req 11.1)

### Context

Trends charts glucose against carbs. The sibling project `imgdatacollector` extracts LibreLink screenshot data into an `events` table as `event_type = "bsl"` rows (one-decimal mmol/L) — the same events schema Medata already uses for meals. CGM vendors do not reliably share data via HealthKit, so no single acquisition path is guaranteed.

### Decision

Trends reads glucose exclusively from `bsl` rows in the local events store. This spec adds one acquisition path: an opt-in, off-by-default, read-only HealthKit importer that writes `bsl` events in mmol/L. imgdatacollector ingestion stays external and future.

### Rationale

Reading from `bsl` events decouples the chart from every acquisition path — HealthKit, screenshot extraction, or future imports all converge on one row shape that already matches imgdatacollector's output. The user confirmed HealthKit should be facilitated and configurable but not assumed.

### Alternatives Considered

- **Read bsl only, no importer**: Smallest scope - Rejected; Trends would show no real data on device for HealthKit users
- **File import of imgdatacollector exports**: Direct integration - Deferred; that pipeline is still being built in its own repo

### Consequences

**Positive:**
- One glucose row shape shared across repos; Trends never cares about the source
- Read-only import keeps the "never writes to your glucose device" promise trivially true

**Negative:**
- HealthKit entitlement, permission UX, and dedup logic enter this spec's scope
- Libre users without Health sync still see an empty glucose series until imgdatacollector lands

---

## Decision 4: Settings match shipped reality, not the handoff's stale items

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff's Settings screen includes photo-retention controls and a "CoFID 2024 + IFCDB 2023 overlay" database section. The app deleted its RetentionScheduler in the recent P1 cleanups, and the bundled databases are CoFID + AFCD (CoFID-wins merge); IFCDB does not ship.

### Decision

Settings follows reality: CoFID + AFCD in the database section, no retention controls. The deviations are recorded in the handoff manifest (Req 15.2).

### Rationale

The user confirmed matching reality. The handoff was drawn against an older requirements snapshot; re-implementing removed features or naming an unshipped database would make the UI lie.

### Alternatives Considered

- **Reinstate retention**: Follow handoff fully - Rejected by user; retention stays deleted
- **Handoff verbatim (incl. IFCDB)**: Zero-deviation adoption - Rejected; IFCDB is not what ships

### Consequences

**Positive:**
- Settings describes the actual app; no dead controls
- Deviation trail lives in the manifest, keeping the handoff archive honest

**Negative:**
- The archived wireframes and the shipped Settings screen intentionally differ; readers must check the manifest

---

## Decision 5: Keep the four-tier confidence scheme

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff draws a three-tier confidence chip (High ≥ 0.8 / Moderate 0.6–0.8 / Low < 0.6). The shipped app uses four tiers (High / Moderate / Low / Very Low at 0.75 / 0.5 / 0.2) per iphone-experience Decision 17, chosen because real capture confidences cluster low; a retake prompt fires below 0.2. The design-critic flagged the draft's silent adoption of the handoff scheme as a blocker.

### Decision

Keep the four-tier scheme and the σ < 0.2 retake prompt (Req 6.2). The handoff's three-tier chip is a logged deviation in the manifest. The UI spec does not define how confidence is computed — it presents the pipeline's persisted value.

### Rationale

User confirmed. Same principle as Decision 4: the handoff was drawn against a stale requirements snapshot; shipped, data-motivated behaviour wins over stale design intent.

### Alternatives Considered

- **Adopt three-tier**: Handoff fidelity - Rejected; most real estimates would read "Low" and the retake prompt loses its home

### Consequences

**Positive:**
- Decision 17's calibration survives; no regression in user feedback quality

**Negative:**
- Chip visual needs a four-tier treatment the wireframes never drew — design phase resolves against the existing `ConfidencePill`

---

## Decision 6: HealthKit import splits into a follow-up specs/data/ spec

**Date**: 2026-07-04
**Status**: accepted

### Context

The requirements originally included an opt-in read-only HealthKit importer. The design-critic showed it under-specified for a data-ingestion feature (trigger, window, dedup key, unit normalisation, entitlement) and out of place in a UI spec.

### Decision

Remove the importer from this spec. Trends reads `bsl` events only (Req 11). The importer becomes its own small `specs/data/` spec, queued after this one.

### Rationale

User chose the split. It mirrors how imgdatacollector stays external: acquisition paths converge on the `bsl` row shape, and the UI never cares which ones exist yet.

### Alternatives Considered

- **Keep here with tightened ACs**: One implementation wave - Rejected by user; separation is cleaner and keeps this spec purely UI

### Consequences

**Positive:**
- This spec has no HealthKit entitlement, permission UX, or dedup scope
- The importer spec can be written against the event-log-schema contract independently

**Negative:**
- On-device Trends shows an empty glucose series until an ingestion path ships

---

## Decision 7: Segmentation review is post-hoc; the pipeline stays single-shot

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff's flow reads Capture → (estimate) → Segmentation review → Result, but its review screen carries an `Estimate carbs` CTA, implying segmentation is shown before estimation — which would split the single-shot `Pipeline.estimate(_:)` contract into two user-visible phases.

### Decision

The full estimate runs during the in-flight state (existing `MedataLoadingSymbol` draw-on mark, inputs locked). Segmentation review then displays the completed estimate's masks; its primary action merely advances to Result and must not imply pending work (Req 5.3 — final label owned by the copy inventory).

### Rationale

Preserves the estimation-path contract (a hard invariant's neighbour — deterministic, offline, single-shot) at zero cost to the user experience: the same screens appear in the same order. The handoff's "(estimate)" placement supports this reading; only its CTA copy conflicts, and the minimal-wording mandate rewrites that copy anyway.

### Alternatives Considered

- **Split pipeline (segment → confirm → estimate)**: True pre-estimation review - Rejected; an architectural change to the estimation contract smuggled in by screen order, with no user-visible benefit claimed by the handoff
- **Skip the review screen**: Simpler flow - Rejected; the handoff includes it and it carries the unknown-region warnings

### Consequences

**Positive:**
- No estimation-path changes; the new loader gets its call site (loading-symbol-animation follow-up `ldsym06` naturally lands here)

**Negative:**
- The review screen cannot offer per-class exclusion before estimation; any such interaction would need the split this decision rejects

---

## Decision 8: Bubble level is continuous, stage-relative, and non-gating

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff's bubble level is green within ±5° of flat, amber otherwise. iphone-experience Decision 19 deliberately removed binary tilt treatment and tilt shutter-gating (only the oblique |Δθ − 25°| > 30° cap remains), and the two-view oblique stage targets 25°, where a "flat" bubble is wrong guidance.

### Decision

Adopt the bubble level visual, but: it drifts continuously, its reference is the current stage's target angle (flat for nadir, 25° for oblique), colour is supplementary to position (colour-not-only rule), and it gates nothing (Req 2.3, 2.6).

### Rationale

Keeps the handoff's glanceable instrument aesthetic while retaining Decision 19's evidence-based philosophy: tilt information, not tilt enforcement. Stage-relative targeting makes the same control correct on both capture paths.

### Alternatives Considered

- **Handoff verbatim (flat-only, binary)**: Design fidelity - Rejected; reinstates the exact treatment Decision 19 superseded and misleads during the oblique stage
- **Keep the existing Δθ text readout, no bubble**: Zero visual change - Rejected; the bubble is central to the handoff's data-only chrome

### Consequences

**Positive:**
- One control serves both stages; no binary gate returns

**Negative:**
- Slightly more implementation logic (per-stage target) than the wireframe drew

---

## Decision 9: Fresh-install default capture path is 1-view on LiDAR devices

**Date**: 2026-07-04
**Status**: accepted

### Context

iphone-experience §4 made Double (two-view) the persistent default. The handoff marks `Quick (1 photo)` as recommended, and the single-view path is the one that works end-to-end on the primary device today.

### Decision

Fresh installs default to 1-view on LiDAR devices and 2-view on non-LiDAR devices; the chosen mode persists via the existing capture-mode setting (Req 16.2).

### Rationale

The recommended path and the default should agree, and the default should be the path that works. Non-LiDAR devices physically require two-view, so the default forks on capability.

### Alternatives Considered

- **Keep Double as default**: Old spec continuity - Rejected; contradicts the handoff's "recommended" marker and defaults users into the less-complete path

### Consequences

**Positive:**
- First capture uses the proven path on the primary device

**Negative:**
- Two-view gets less incidental exercise from LiDAR users during development

---

## Decision 10: Handoffs archive as one bulk folder, manifest without a SHA field

**Date**: 2026-07-04
**Status**: accepted

### Context

`docs/agent-notes/wireframe-intake.md` prescribed a one-file-per-screen landing zone (`design-system/wireframes/<screen>.<ext>`). Handoff 00 arrived as a coherent bundle (wireframes + scaffold + README) whose internal cross-references would break if split. The draft manifest also required recording "the archive commit SHA once known", which forces a self-referential follow-up commit.

### Decision

Each handoff archives verbatim as one folder, `design-system/wireframes/design-handoff-NN/`, with a manifest recording id, date, source, and deviations. No SHA field — git history already pins the archive. The intake note's landing-zone section is updated to match when the archive lands.

### Rationale

The bundle is the artefact; splitting it destroys information. A SHA recorded inside the commit it describes is either wrong or requires a second commit — `git log -- design-system/wireframes/design-handoff-00/` answers the question for free.

### Alternatives Considered

- **One file per screen (intake note as written)**: Existing convention - Rejected; breaks bundle cross-references and loses the scaffold entirely
- **Manifest with SHA field**: Explicit pinning - Rejected as self-referential ceremony

### Consequences

**Positive:**
- Verbatim archive; deviations list is the only curated content

**Negative:**
- `docs/agent-notes/wireframe-intake.md` needs a small update at implementation time

---

## Decision 11: Reskin in place — keep the state machine, rebuild the chrome

**Date**: 2026-07-04
**Status**: accepted

### Context

The scaffold is mock-driven and far simpler than the shipped capture flow (`CaptureFlowModel` state machine, pre-shutter mask gating, two-stage capture, refusal handling, live telemetry). `CaptureFlowView` already owns a capture-rooted `NavigationStack` inside the TabView. The intake rules forbid direct wireframe ports.

### Decision

Remove the TabView shell and rebuild screen chrome in `App/` against design-system pages, keeping `CaptureFlowModel`, all services, and existing components (`ConfidencePill`, `MedataLoadingSymbol`, `LiveSampleObserver`, the bubble-guide maths). The scaffold is layout reference only.

### Rationale

User confirmed. The working state machine embodies a year of capture-flow decisions (Decisions 11/17/19/35 of iphone-experience); porting the scaffold would discard them for mock code that must then be rewired anyway.

### Alternatives Considered

- **Port scaffold + wire services**: Faster visual fidelity - Rejected; discards the state machine and violates intake rules
- **Hybrid per screen**: Port only greenfield screens - Rejected; even Trends/Overview bind to real store APIs the scaffold lacks, so the port saves nothing

### Consequences

**Positive:**
- Capture behaviour provably unchanged under new chrome (Req 2.6)
- New screens bind to real `PersistenceStore` APIs from day one

**Negative:**
- Layout must be re-derived from the scaffold by reading, not reusing, its code

---

## Decision 12: MASTER.md amendments — no palette swap, two new tokens, tab-bar invariant deleted

**Date**: 2026-07-04
**Status**: accepted

### Context

The scaffold ships its own `DS` token set (paper/ink greyscale, green `#2d8b5f`, amber `#c97a1f`) that conflicts with `design-system/MASTER.md` (OLED black capture, `#63FF00` accent, system grouped surfaces). MASTER.md also carries a layout invariant — "tab bar visible on all tabs" — that the new shell removes.

### Decision

MASTER.md stays authoritative: handoff greens map to `medataAccent`, ambers to `systemOrange` (per the wireframe-intake reconciliation rule). Two tokens are added: `seriesGlucose` (systemOrange) and `bandTarget` (medataAccent at 10 % opacity). The tab-bar layout invariant is deleted. The scaffold palette is not adopted.

### Rationale

The handoff self-describes as low-fidelity ("grayscale + two accents… not for final visual styling"), so its palette is a sketch convention, not a design instruction. The two new tokens are the only semantic gaps Trends actually exposes.

### Alternatives Considered

- **Adopt scaffold DS palette**: Handoff fidelity - Rejected; the handoff itself says not to, and it would retire the OLED capture aesthetic without a stated reason
- **Map amber to a new bespoke colour**: Closer to wireframe - Rejected; `systemOrange` already serves the warning role (`confidenceModerate`)

### Consequences

**Positive:**
- One token system; Trends colours are named, not hard-coded

**Negative:**
- Shipped screens will look different from the archived wireframes (already true by fidelity note; manifest records it)

---

## Decision 13: `EventType.bsl` constant + DEBUG-only demo seeding

**Date**: 2026-07-04
**Status**: accepted

### Context

Trends reads `bsl` events, but no ingestion path ships in this spec (Decision 6), so on-device verification would only ever see the empty state. The store's `events(in:type:)` already accepts arbitrary type strings; only the constant is missing.

### Decision

Add `EventType.bsl` to MedataCore (value = mmol/L, imgdatacollector row shape). Add a `#if DEBUG` `seedDemoBslEvents()` extension on `GRDBPersistenceStore` (24 h of synthetic readings, 15-min spacing) triggered from a DEBUG-only Settings row. No public event-write API is added — that belongs to the future importer spec.

### Rationale

Verification needs real rows in the real store; a DEBUG seed is the smallest honest path. Deferring a general write API avoids designing the importer's contract prematurely.

### Alternatives Considered

- **Public `saveEvent` API now**: Ready for the importer - Rejected; API design without its consumer is guesswork
- **Verify against empty chart only**: Zero code - Rejected; leaves the dual-series chart, TIR, and axis mapping unverified on device

### Consequences

**Positive:**
- Full Trends surface verifiable on device before any importer exists

**Negative:**
- DEBUG-only code path in the store extension (gated, never ships in Release)

---

## Decision 14: Torch control dropped from capture chrome

**Date**: 2026-07-04
**Status**: accepted (user confirmed at design review)

### Context

The existing `CaptureTopBar` has a torch toggle. Req 2.1's chrome enumeration is exhaustive ("SHALL contain exactly") and, following the handoff, omits it. Low light is a real capture failure mode (`insufficientLight` refusal exists).

### Decision

Remove the torch control. The `more light` error state (§4) remains the guidance for dark scenes.

### Rationale

The requirement is binding as written and the handoff's data-only chrome has no slot for it. Flagged as proposed because it is a functional removal, not just a reskin — user confirmation requested at the design gate.

### Alternatives Considered

- **Keep torch in the top bar**: Preserves the low-light tool - Requires amending Req 2.1's exhaustive list
- **Torch only in the error state**: Offer torch as an action on `more light` - Smaller surface, but invents UI the handoff never drew

### Consequences

**Positive:**
- Chrome matches the requirement exactly

**Negative:**
- Dark-scene users lose the in-app remedy; retake guidance is the only path
- *(Post-implementation note)* No low-light `EstimationFailure` case exists in the pipeline, so the `more light` error state this decision leaned on is dormant — the copy-inventory row is retained but unimplemented until light-level detection exists (out of this spec's scope)

---

## Decision 15: Pipeline persists the segmentation mask as a per-meal artefact

**Date**: 2026-07-04
**Status**: accepted

### Context

The design assumed mask artefacts existed; the design-critic proved the pipeline persists none (`save(record, artefacts: [])` at Stage L) — every mask-overlay surface (§5.1, §9.1) would hit the photo-only fallback on every device, and no id→colour table exists for tinting or swatches.

### Decision

At Stage L, encode the segmentation label raster as an indexed PNG (~20–50 KB) and save it as a `MealArtefact(kind: "mask")` under the existing `meals/{id}/` layout. Add a deterministic, palette-versioned id→colour table beside `ClassPalette` in MedataCore. Artefact write failure logs and never fails the meal save. Pre-existing meals fall back photo-only (no backfill).

### Rationale

User chose persistence over in-memory-only. It is a storage-only change — estimation maths untouched, deletion already cascades — and it is the only path that makes Meal overview's masks (Req 9.1) real rather than permanently amended away.

### Alternatives Considered

- **In-memory mask for fresh captures only**: No pipeline change - Rejected by user; history overlays would never work and Req 9.1 would be permanently degraded
- **Persist full probability tensor**: Richer future use - Rejected; megabytes per meal for no current requirement

### Consequences

**Positive:**
- Mask overlays work for all future meals; one colour source for overlays, swatches, and design pages

**Negative:**
- ~20–50 KB per meal; the "storage-only" boundary must be policed in review (no estimation-path drift)

---

## Decision 16: Per-class σ and per-class confidence chips dropped

**Date**: 2026-07-04
**Status**: accepted

### Context

Reqs 6.4/9.2 specified per-class σ and Req 5.1 per-class confidence chips, but `PbPerClassMacros` carries no σ and the pipeline computes confidence at meal level only. The handoff drew per-class σ against a data model that never existed.

### Decision

Amend the requirements (v0.4): per-food rows show name, mass, volume, carbs; the review screen's class list carries mask-colour swatches, not confidence chips; meal-level confidence (four-tier pill) remains the only confidence surface.

### Rationale

User chose the amendment over extending the proto and estimation output. New per-class confidence maths inside a UI spec would breach the spec's own boundary (estimation path frozen), and no consumer of per-class σ exists beyond decoration.

### Alternatives Considered

- **Add per-class σ to pipeline output**: Handoff fidelity - Rejected by user; estimation-path change with maths that does not exist yet

### Consequences

**Positive:**
- UI spec stays off the estimation path; rows show only real data

**Negative:**
- Archived wireframes show a σ column the app will not have (manifest deviation)

---

## Decision 17: Result keeps auto-persist; `Save` becomes `Done`, `Delete` is the discard path

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff's `Save to history` implies the meal is unsaved on the Result screen, but `Pipeline.estimate` persists at Stage L before Result renders. A no-op Save would lie; backing out without tapping it would still leave the meal in Data.

### Decision

Keep persist-at-estimate. Result actions (Req 6.6/6.7 v0.4): `Adjust` + `Done`; ⋯ menu carries Retake and Delete on fresh captures, Delete only from history. Delete is the explicit discard path.

### Rationale

User confirmed. Persist-at-estimate is loss-proof (app death mid-review loses nothing) and already shipped; renaming the button to match reality is cheaper and honester than re-architecting the save stage.

### Alternatives Considered

- **Defer persistence until Save**: Honest Save button - Rejected by user; touches the estimation path's save stage and risks silent data loss

### Consequences

**Positive:**
- No pipeline change; no data-loss window; copy tells the truth

**Negative:**
- Users who expect "not saved until I say so" get the opposite; the Data screen is the corrective surface

---

## Decision 18: `appendCorrection` now emits `eventsDidChange`

**Date**: 2026-07-04
**Status**: accepted

### Context

The store's change stream deliberately did not fire on `appendCorrection` (event-log-schema phase had no correction UI). With Data rows and Meal overview now composing corrected totals (Req 7.3), nothing would tell them a correction landed.

### Decision

`GRDBPersistenceStore.appendCorrection` notifies `eventsDidChange` after a successful insert. Data reloads via its existing subscription; Meal overview re-reads corrections while visible.

### Rationale

The alternative is per-screen ad-hoc callbacks threaded through navigation, which breaks the store-as-single-source pattern every other refresh path uses.

### Alternatives Considered

- **Completion-callback plumbing from ManualCorrectionView**: No store change - Rejected; couples navigation to persistence semantics and misses future correction writers
- **Poll corrections on appear**: No change anywhere - Rejected; stale totals whenever the list is already visible

### Consequences

**Positive:**
- One refresh mechanism for meals and corrections alike

**Negative:**
- A documented behaviour change to the store contract (the event-log-schema design note saying corrections do not emit becomes stale and is updated in the same commit series)

---

## Decision 19: Data / Trends / Settings present as full screens, not sheets

**Date**: 2026-07-04
**Status**: accepted

### Context

The handoff (and Req 1.2 as approved) presented Data, Trends, and Settings as sheets over Capture. After seeing the implementation, the user directed that these surfaces be full screens rather than temporary modals above the camera.

### Decision

The three surfaces present full-screen (`.fullScreenCover(item:)` on the same `ActiveSheet` state). The AR-session lifecycle hooks (`sheetDidPresent`/`sheetDidDismiss`) are unchanged. Because full-screen covers have no drag-to-dismiss, each surface carries an explicit close control (xmark, accessibility label `Close`) returning to Capture. Reqs 1.2/1.5 amended (v0.5).

### Rationale

Direct user instruction — the user zone wins over the handoff drawing. The item-driven presentation swap keeps every behavioural guarantee (mutual exclusivity, session release/re-arm) while changing only the container.

### Alternatives Considered

- **Push onto the root NavigationStack**: Also full-screen - Rejected; entangles the three surfaces with the capture flow's path (review/result/correction) and gives them a back chevron into camera state instead of a deliberate close
- **Keep sheets**: As drawn - Rejected by user

### Consequences

**Positive:**
- Surfaces read as destinations, not overlays; no camera peeking through

**Negative:**
- Deviates from the archived wireframes (manifest deviation); explicit close controls become mandatory on all three surfaces

---

## Decision 20: Graph is the launch root; Capture becomes a presented surface

**Date**: 2026-07-04
**Status**: accepted

### Context

The Capture-rooted shell (Req 1.1 as implemented) opens the app on the camera. The user finds this annoying in developer use and directed that the Graph screen be the default, with the camera one tap away.

### Decision

Graph is the full-screen navigation root. Capture, Data, and Settings present as full-screen covers from Graph controls, Capture's control being the most prominent. The AR session runs only while the Capture surface is presented (armed on present via the initialising state, released ≤200 ms on close/background). Capture's chrome gains a close control and loses the Trends/Data/Settings buttons, which move to Graph. Reqs 1.1/1.2/1.5/1.6/2.1 amended (v0.6).

### Rationale

Direct user instruction. Side benefits: no camera permission prompt or AR battery cost at launch, and the existing `isCovered` lifecycle plumbing inverts cleanly (session off by default, on while capturing).

### Alternatives Considered

- **Keep Capture root, add a launch preference**: Configurable - Rejected; adds a setting nobody asked for over a direct instruction
- **Tab shell revival**: Peer surfaces - Rejected; reverses Decision 2 and the handoff shell entirely

### Consequences

**Positive:**
- Launch lands on the data the developer checks most; AR runs only when needed

**Negative:**
- Second inversion of the shell in one day — the archived wireframes now describe neither root (manifest deviation); capture is two taps from cold start for real meal logging

---

## Decision 21: Trends renamed Graph; developer-phase copy rule bans disclaimer messaging

**Date**: 2026-07-04
**Status**: accepted

### Context

The user renamed Trends to `Graph` (everywhere in UI) and ordered the `Glucose is read-only…` footer removed, establishing a project rule: while the app is developer-only, reassurance/disclaimer copy is distracting noise — the developer already knows.

### Decision

`Trends` → `Graph` in every user-facing string (titles, buttons, accessibility labels; internal type/key names unaffected). Removed under the new §14.5 rule: the Graph read-only footer (former Req 10.7), the Settings LibreLink explainer footnote, and the correction preservation notice. The About screen stays as the sole legal/attribution surface (CoFID attribution is licence-required); functional accuracy signals (calibration banner, very-low retake) are not disclaimers and stay. Rule recorded in project CLAUDE.md.

### Rationale

Direct user instruction, generalised as requested ("Project rule now is to exclude this type of messaging"). Distinguishing reassurance copy (removed) from functional accuracy signals (kept) preserves the research-spec contracts while cutting the noise.

### Alternatives Considered

- **Remove only the named footer**: Minimal reading - Rejected; the user explicitly generalised to "this type of messaging"
- **Strip About too**: Maximal reading - Rejected; CoFID attribution is a licence obligation and About is out of the way

### Consequences

**Positive:**
- Quieter screens; one recorded rule prevents re-litigating each new string

**Negative:**
- Before any non-developer release, the removed copy (and likely more) must be revisited — the rule is explicitly phase-scoped

---

## Decision 22: Confidence pill removed from the Data/summary page

**Date**: 2026-07-05
**Status**: accepted

### Context

Decision 5 kept the four-tier confidence pill, and its amendment (this log, Decision "per-food rows / only confidence surface") established meal-level confidence as the only confidence surface — shown on the result view and the meal-history/Data row. On device the pill on the Data/summary row, sitting directly beside the meal's carb total, read as a claim that the meal was "high" in carbohydrate rather than that the estimate was high-confidence. That is a dietary/diagnostic-sounding implication the app must not make.

### Decision

Drop the confidence pill from the Data/summary list row. It stays on the meal-detail screen and the just-captured result screen, where the context makes "confidence" unambiguous. This narrows the earlier "only confidence surface" claim: meal-level confidence remains the only confidence *value* surfaced, but it is no longer shown on the summary page. The four-tier scheme and the σ < 0.20 retake surface are unchanged. See iphone-experience Decision 22 for the row-level detail.

### Rationale

A confidence badge is a property of the estimate, not of the food. Next to a gram figure on a dense list it is misread as a judgement about the meal. The detail and result screens present the carb total as the focal figure with the pill clearly bound to the estimate, so the confidence reading holds there without the summary-page ambiguity.

### Alternatives Considered

- **Leave the earlier decision as written**: Keeps the misleading summary-page badge - rejected; the misread is real and observed on device.
- **Add an explicit "confidence" caption on the row**: More text on the densest surface without resolving the competition with the carb figure - rejected.

### Consequences

**Positive:**
- The summary page no longer implies anything about the meal's carbohydrate level.

**Negative:**
- Confidence is not visible until a meal is opened.
- The earlier "only confidence surface" wording must now be read alongside this entry.

---
