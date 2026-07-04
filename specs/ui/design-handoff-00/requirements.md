# UI Design Handoff 00 — Requirements

**Version:** 0.6 (post-implementation amendments: Decision 19 — full-screen surfaces; Decisions 20–21 — Graph as launch root, Trends→Graph rename, developer-phase copy rule)
**Date:** 2026-07-04
**Status:** In review
**Sources:** `tmp/design/design_handoff_medata/` (wireframes v1/v2 + SwiftUI scaffold), to be archived per §15. Supersedes and amends parts of `specs/ui/iphone-experience/` per the table in §16.

## Introduction

The first external design handoff (handoff 00) redesigns the app's user-facing surface: a full-bleed Capture root replaces the three-tab shell, Result gains a per-class breakdown, and two new screens arrive — Trends (carbs charted against imported blood glucose) and Meal overview. This spec adopts those designs into the existing app, amended by two standing mandates: all UI copy is minimal, and the design references themselves are archived and versioned so future handoffs can amend them traceably.

## Out of Scope

- HealthKit glucose import (split to a follow-up `specs/data/` spec; this spec only reads `bsl` events — decision_log Decision 6)
- Ingesting glucose from LibreLink screenshots (lives in the external `imgdatacollector` project; only its `bsl` event shape is consumed here)
- Writing to HealthKit or any glucose device
- Photo-retention controls (RetentionScheduler was removed; not reinstated)
- IFCDB database overlay (the shipped databases are CoFID + AFCD)
- Protein/fat/energy values anywhere (placeholder capsules only, no data)
- Sign-in / accounts (Account row is visible but disabled)
- Meal naming or editing of meal titles (Data rows stay anonymous)
- Splitting the estimation pipeline into user-visible segment/estimate phases (segmentation review is post-hoc — Decision 7)
- Pixel-fidelity to the wireframes (they are low-fi; native iOS idioms win)
- Figma bridge for the design system (paste/archive path only)
- Localisation beyond Irish/British English; iPad/Watch layouts; landscape

## Requirements

### 1. Navigation shell and flow

**User Story:** As a user, I want the camera front and centre when the app opens, so that capturing a meal is the zero-friction default action.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the app launches, THEN it SHALL present the Graph screen full-screen as the navigation root, with no tab bar (amended per Decision 20 — Capture is no longer the launch screen).  
2. <a name="1.2"></a>The Capture, Data (meal log), and Settings screens SHALL each be reachable from Graph-screen controls and SHALL present as full screens (not partial-height modals), each with an explicit close control returning to Graph (Decisions 19–20). The Capture control SHALL be the most prominent.  
3. <a name="1.3"></a>WHEN the shutter fires, THEN the app SHALL enter an estimating state — the existing draw-on Medata loading mark shown, shutter and mode controls locked — and WHEN estimation completes, THEN the flow SHALL push Segmentation review (§5), then Result (§6), then optionally Manual correction (§7), returning to Capture on dismissal.  
4. <a name="1.4"></a>Backgrounding during estimation SHALL behave as it does today (iphone-experience 8.3 remains binding); estimation failure SHALL return to Capture with the §4 error state.  
5. <a name="1.5"></a>The AR session SHALL run only while the Capture surface is presented: armed on presentation through the existing initialising state, released within 200 ms of the surface closing or the app backgrounding (Decision 20).  
6. <a name="1.6"></a>Existing shell behaviours SHALL be preserved: portrait-only, and the camera-permission refusal state still reachable and recoverable, with the Capture surface's close control remaining usable from the refusal state.

### 2. Capture screen chrome

**User Story:** As a user, I want the capture screen to show only live data — no instructions — so that nothing distracts from framing the plate.

**Acceptance Criteria:**

1. <a name="2.1"></a>The capture chrome SHALL contain exactly: a close control (top-leading, returning to Graph), a mode capsule (top-centre), a bubble level (top-right), a telemetry capsule above the shutter, and a bottom row of mode button and shutter (Trends/Data/Settings buttons moved to the Graph root — Decision 20). Transient state surfaces (status hints, the two-view nadir confirmation thumbnail, oblique guidance) are not chrome; they are preserved per §16 rows 1/2/5/12 and restyled per the capture design page.  
2. <a name="2.2"></a>The mode capsule SHALL read, in monospaced type: `1-VIEW · LiDAR` (single path), `2-VIEW · NADIR` (two-view first stage), or `2-VIEW · OBLIQUE` (two-view second stage).  
3. <a name="2.3"></a>The bubble level SHALL drift continuously with device tilt relative to the current stage's target angle (flat for nadir stages, 25° for the oblique stage), tinted green within ±5° of target and amber beyond, always paired with a non-colour cue (bubble position). It SHALL NOT gate the shutter.  
4. <a name="2.4"></a>The telemetry capsule SHALL show live tilt in degrees, subject distance in cm, and a LiDAR dot that is green WHEN depth data is available (e.g. `tilt 1.8° · dist 34 cm · LiDAR ●`). ON non-LiDAR devices the distance field SHALL show the static target band (`30–40 cm`) as guidance and the dot SHALL be grey — the grey dot is the guidance-mode indicator (amends iphone-experience 3.2/3.3).  
5. <a name="2.5"></a>Tapping the mode button SHALL toggle 1-view/2-view; long-pressing it SHALL open the capture-path fork sheet (§3).  
6. <a name="2.6"></a>The following existing gates SHALL keep working unchanged under the new chrome: shutter disabled until AR tracking is normal, the LiDAR working-distance band, the oblique-stage |Δθ − 25°| ≤ 15° gate, the estimating-state input lock, blocked-shutter feedback, and the active-refusal sheet. No new tilt gate SHALL be introduced.

### 3. Capture-path fork sheet

**User Story:** As a user without LiDAR (or wanting the canonical path), I want to choose the capture method, so that I can still get a scaled estimate.

**Acceptance Criteria:**

1. <a name="3.1"></a>The fork sheet SHALL offer `Quick (1 photo)` (marked recommended, requires LiDAR) and `Two-view (canonical)`.  
2. <a name="3.2"></a>The sheet SHALL include a reference-card toggle that seeds from the Settings always-include-card default (§12.1); a per-capture override SHALL apply to that capture only and SHALL NOT change the stored default.  
3. <a name="3.3"></a>IF LiDAR is unavailable on the device, THEN the quick path SHALL be disabled with the two-view path preselected.

### 4. Capture error state

**User Story:** As a user whose shot failed a gate, I want a terse explanation and a way out, so that I am never stuck.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a capture fails a gate (§2.6) or estimation fails, THEN the screen SHALL show an amber ghost outline, a short status chip (e.g. `too far`), a one-line fix hint, and escape actions — retry, `2-view`, and Cancel — with no dead-end state. Retry SHALL resume at the failed stage with the AR session still live (folds in iphone-experience 10.2/10.3; §4 owns the presentation).  
2. <a name="4.2"></a>Error copy SHALL follow the minimal-wording rule (§14): status chips ≤ 3 words, fix hints one clause.

### 5. Segmentation review

**User Story:** As a user, I want to see what was recognised before the number, so that I can judge whether the estimate is trustworthy.

**Acceptance Criteria:**

1. <a name="5.1"></a>The review screen SHALL show the captured photo with the completed estimate's per-class mask overlays and a class list with per-class mask-colour swatches (post-hoc display; the pipeline is not split — Decision 7; no per-class confidence exists — Decision 16).  
2. <a name="5.2"></a>WHEN the estimate contains unknown regions or unsupported liquids, THEN an amber banner (icon + text, not colour alone) SHALL say so in minimal wording.  
3. <a name="5.3"></a>The primary action SHALL advance to Result; its label is owned by the copy inventory (§14.2) and SHALL NOT imply estimation is still pending.

### 6. Result

**User Story:** As a user, I want one number I can act on, with the evidence beneath it, so that dosing decisions are fast but checkable.

**Acceptance Criteria:**

1. <a name="6.1"></a>The Result screen SHALL show the carb total rounded to 1 g as the visually dominant hero with a `g carbs` suffix (type size owned by the screen's design-system page).  
2. <a name="6.2"></a>A confidence chip below the hero SHALL present the pipeline's persisted meal confidence using the existing four-tier scheme (High / Moderate / Low / Very Low at 0.75 / 0.5 / 0.2, icon + colour per the existing `ConfidencePill`); the existing retake prompt below 0.2 SHALL be preserved. This spec SHALL NOT redefine how confidence is computed.  
3. <a name="6.3"></a>A summary card SHALL show the photo thumbnail, `N foods recognised`, total mass, and the food-database edition.  
4. <a name="6.4"></a>Per-class rows SHALL each show name, mass (g), volume (cm³), and carbs (g) (per-class σ dropped — Decision 16).  
5. <a name="6.5"></a>Dashed, disabled `Protein — soon` and `Fat — soon` capsules SHALL hold layout space so nothing shifts when macros land.  
6. <a name="6.6"></a>The meal is persisted when estimation completes (existing behaviour). WHEN Result is reached from a fresh capture, THEN actions SHALL be `Adjust` (bordered) and `Done` (prominent), with Retake and Delete in a ⋯ menu — Delete is the discard path (Decision 17).  
7. <a name="6.7"></a>WHEN Result is reached from Meal overview (§9), THEN actions SHALL be `Adjust` and `Done`, with Delete (no Retake) in the ⋯ menu.  
8. <a name="6.8"></a>WHEN the photo asset is unavailable (Photos authorisation denied, asset deleted, or `photoAssetID` empty), THEN thumbnail slots (here, §8.2, §9.1) SHALL show a neutral placeholder; WHEN mask artefacts are unavailable, THEN mask-overlay surfaces (§5.1, §9.1) SHALL show the photo (or placeholder) without overlays. Neither case SHALL error.

### 7. Manual correction

**User Story:** As a user who knows the estimate is off, I want to correct it without losing the original, so that the record stays honest.

**Acceptance Criteria:**

1. <a name="7.1"></a>The correction screen SHALL offer a total-carbs stepper, per-food value edits, and an optional note field.  
2. <a name="7.2"></a>Saving a correction SHALL store it alongside the original estimate; the original values SHALL remain retrievable unchanged.  
3. <a name="7.3"></a>Corrected meals SHALL carry a visible `user-corrected` marker wherever the meal is shown (§8, §9).

### 8. Data (meal log)

**User Story:** As a user, I want a plain chronological log of my meals, so that I can find and revisit any capture.

**Acceptance Criteria:**

1. <a name="8.1"></a>The screen SHALL be titled `Data` and SHALL list meals grouped by day, newest first.  
2. <a name="8.2"></a>Each row SHALL show only: thumbnail (per §6.8), time, carbs (g), and confidence chip — no meal names.  
3. <a name="8.3"></a>Tapping a row SHALL open the Meal overview (§9), not the full Result.  
4. <a name="8.4"></a>Meals saved before this redesign SHALL appear correctly in the new list (same store, no migration).  
5. <a name="8.5"></a>WHEN no meals exist, THEN the screen SHALL show a minimal empty state (per §14), not a blank list.

### 9. Meal overview

**User Story:** As a user reviewing history, I want a compact recap of one meal — photo, masks, numbers — so that I rarely need the full Result screen.

**Acceptance Criteria:**

1. <a name="9.1"></a>The overview SHALL show the captured photo with mask overlays (fallbacks per §6.8), a compact carb total with confidence chip (size owned by the design-system page), and a capture-metadata line.  
2. <a name="9.2"></a>Per-class rows SHALL show a mask-colour swatch, mass (g), volume (cm³), and carbs (g) (no σ — Decision 16); a `corrected` marker SHALL appear when a correction exists.  
3. <a name="9.3"></a>Actions SHALL be `Adjust` (bordered → Manual correction) and `Full result` (prominent → Result per §6.7); delete SHALL be available via a ⋯ menu with confirmation.

### 10. Graph (renamed from Trends — Decision 21; `Graph` everywhere in UI)

**User Story:** As a user managing glucose, I want my carb intake charted against my glucose curve, so that I can see how meals move my levels.

**Acceptance Criteria:**

1. <a name="10.1"></a>The Graph screen SHALL offer Day / Week / Month ranges via a segmented control.  
2. <a name="10.2"></a>The Day view SHALL chart glucose as a line (mmol/L, leading axis) and carbs as bars at meal timestamps (g, trailing axis labelled in grams) on one chart, with a translucent band marking the 3.9–10.0 mmol/L target range. The chart scale SHALL accommodate the full data range of both series (no clipping at a fixed carb maximum).  
3. <a name="10.3"></a>The Week view SHALL show total carbs per day as bars and average glucose per day as a line; the Month view SHALL show the same semantics across the calendar month.  
4. <a name="10.4"></a>Metric chips under the chart SHALL toggle Carbs and Glucose series inclusion; Protein and Fat chips SHALL be dashed and disabled.  
5. <a name="10.5"></a>Summary cards SHALL show total (or average) carbs, time in range, and average glucose for the selected range. Time in range SHALL be computed time-weighted between consecutive glucose readings, excluding gaps longer than 60 minutes from the denominator; WHEN no glucose data qualifies, THEN the card SHALL show `—`.  
6. <a name="10.6"></a>The Day view SHALL list that day's meals below the chart; each row SHALL open its Meal overview (deviation from handoff §3, logged in the manifest).  
7. <a name="10.7"></a>*Removed (Decision 21):* the read-only footer note is deleted; the Graph screen SHALL carry no disclaimer copy per §14.5.  
8. <a name="10.8"></a>A graph-options sheet SHALL offer: per-metric toggles with one-line source captions, target-band toggle, disabled Protein · Fat row, and a y-scale control (Auto, or Fixed with an 8–25 mmol/L max stepper).  
9. <a name="10.9"></a>WHEN no glucose data exists for the range, THEN the chart SHALL still render the carb series with an unobtrusive `no glucose data` state, not an error.

### 11. Glucose data

**User Story:** As a user, I want Trends to chart whatever glucose readings my data store holds, so that the chart works no matter how readings were ingested.

**Acceptance Criteria:**

1. <a name="11.1"></a>Trends SHALL read glucose exclusively from `bsl` rows in the existing events store, per the row shape defined by `specs/data/event-log-schema/` (`event_type = "bsl"`, value in mmol/L), regardless of ingestion path.  
2. <a name="11.2"></a>Glucose values SHALL be displayed in mmol/L only, to one decimal place.

### 12. Settings

**User Story:** As a user, I want capture defaults and data controls in one place, so that configuration stays out of the capture flow.

**Acceptance Criteria:**

1. <a name="12.1"></a>Settings SHALL contain: a disabled `Account` row, a food-database section, capture defaults (default path, always-include-card toggle), data export, and About.  
2. <a name="12.2"></a>The food-database section SHALL name the actually bundled editions — CoFID and AFCD (CoFID-wins merge) — not IFCDB.  
3. <a name="12.3"></a>Settings SHALL NOT contain photo-retention controls.  
4. <a name="12.4"></a>Existing settings behaviours (export, capture defaults persistence) SHALL keep working unchanged.

### 13. About / legal

**User Story:** As a user, I want to see where the numbers come from and what the app is not, so that I can trust its limits.

**Acceptance Criteria:**

1. <a name="13.1"></a>About SHALL include: CoFID attribution (Crown Copyright, Open Government Licence v3), AFCD attribution, a one-paragraph method summary, a `Not a medical device` statement, and a privacy note stating all processing is on-device. Legal and safety copy here is exempt from §14.1.

### 14. Minimal wording and indicator rules

**User Story:** As a user, I want terse, glanceable UI text, so that the interface reads like an instrument, not a conversation.

**Acceptance Criteria:**

1. <a name="14.1"></a>Every user-facing string SHALL use the shortest phrasing that keeps its meaning: no full sentences where a fragment works, no filler. Binding examples: `Hold the phone level` → `Hold level`; `Skip to 2-view` → `2-view`; `Hold the phone 30–40 cm from the food.` → `30–40 cm`; `It's too dark to read the plate edge reliably.` → `More light`. Exempt: legal/safety copy explicitly marked so (§10.7, §13.1).  
2. <a name="14.2"></a>The design phase SHALL produce a copy inventory listing every user-facing string on the redesigned screens with its final minimal form; compliance with 14.1 is defined as verbatim match with the inventory.  
3. <a name="14.3"></a>All copy SHALL use Irish/British English spelling and pass `make spell`.  
4. <a name="14.4"></a>Every colour-coded status indicator (bubble level, confidence chips, banners, LiDAR dot) SHALL pair colour with a non-colour cue — icon, position, or text — per `design-system/MASTER.md`.  
5. <a name="14.5"></a>WHILE the app is developer-only, screens SHALL carry no reassurance or disclaimer copy (privacy notes, read-only warnings, data-preservation notices) — the developer already knows (Decision 21). The About screen remains the sole legal/attribution surface; functional accuracy signals (calibration banner, very-low retake surface) are NOT disclaimers and stay.

### 15. Versioned design references

**User Story:** As a maintainer, I want each design handoff archived and pinned, so that future design changes are diffs against a known version, not folklore.

**Acceptance Criteria:**

1. <a name="15.1"></a>The handoff artefacts (wireframes + scaffold + README) SHALL be committed verbatim under `design-system/wireframes/design-handoff-00/` as inert reference — no target membership, nothing imports them (this bulk-folder archive supersedes the one-file-per-screen landing zone in `docs/agent-notes/wireframe-intake.md` — Decision 10).  
2. <a name="15.2"></a>A manifest in that folder SHALL record: handoff id (00), date received, source description, and the list of deviations this spec makes from the handoff, with each behavioural deviation linking to a decision-log entry (blanket copy rewrites cite §14 once).  
3. <a name="15.3"></a>Each redesigned screen SHALL get a `design-system/pages/<screen>.md` page reconciling the wireframe to `design-system/MASTER.md` tokens, following the existing `photo-tab.md` shape; type sizes and colours referenced by §5–§10 live there, not in this document.  

*Note (non-normative): a future handoff lands as `design-handoff-01` — a new archive folder, new/updated screen pages, and its own spec; this document stays fixed to handoff 00.*

### 16. Supersession of iphone-experience

**User Story:** As a maintainer, I want the old UI spec's status explicit per requirement, so that no one implements against a superseded contract.

**Acceptance Criteria:**

1. <a name="16.1"></a>The supersession table below SHALL be binding, and a reciprocal status note SHALL be added to `specs/ui/iphone-experience/requirements.md` in the same commit series as this spec.  
2. <a name="16.2"></a>The fresh-install default capture path SHALL be 1-view on LiDAR devices and 2-view on non-LiDAR devices; the user's chosen mode SHALL persist across launches via the existing capture-mode setting.

| iphone-experience § | Status under handoff 00 |
|---|---|
| 1 Capture-flow main view | Amended — chrome per §2 here; 1.2/1.6 still binding; 1.3 amended (refusal message + Settings deep-link retained; tab-bar clause superseded, sheet controls stay usable per §1.6) |
| 2 Tilt indicator | Amended — bubble level (§2.3) + telemetry tilt (§2.4) replace the Δθ + σ_tilt% readout; the σ_tilt% display is dropped (manifest deviation); Decision 19's continuous, non-gating principle retained |
| 3 Working-distance gate | Amended — gate itself binding; non-LiDAR guidance hint and mode indicator now live in the telemetry capsule (§2.4: `30–40 cm` band, grey dot) |
| 4 Capture-mode toggle | Superseded — mode button + fork sheet (§2.5, §3); default per §16.2 |
| 5 Two-view capture sequence | Amended — 5.1/5.3–5.6 still binding; 5.2's per-stage instruction line superseded (the mode capsule §2.2 is the stage prompt) |
| 6 ID-1 card guidance | Amended — card choice moves to fork sheet (§3.2) |
| 7 Shutter button | Still binding (visual per design-system page) |
| 8 Estimation in flight | Amended — loading mark + flow per §1.3/§1.4 |
| 9 Result view | Superseded by §6 (four-tier pill retained) |
| 10 Refusal handling | Amended — §4 owns failure presentation; 10.2/10.3 semantics (retry at same stage, AR live) fold into §4.1 |
| 11 Settings | Amended by §12; old 11.1's removal of the capture-view settings entry point is reversed by §2.1's settings button |
| 12 Localisation | Amended — 12.1 binding; 12.2 (verbatim `localisedMessage`) superseded: failure copy is owned by the §14.2 inventory |
| 13 Permissions | Still binding (+ Photos fallbacks §6.8) |
| 14 Responsiveness | Still binding |
| 15 Branding | Still binding |
| 16 System interruptions | Still binding |
| 17 Privacy / on-device | Still binding |
| 18 Tab navigation shell | Superseded by §1 |
| 19 Meals tab | Superseded by §8 + §9 |
| 20 Visual design | Amended — handoff-00 design-system pages take over per §15.3 |
