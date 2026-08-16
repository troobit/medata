# Requirements: Manual Carb/Macro Intake

## Introduction

MeData currently records carbs only as a by-product of the photo/estimation pipeline. This feature adds a direct manual intake path: a carb-entry sheet modelled on the existing insulin-dose flow, and one-tap quick-add presets (e.g. a pint, a bagel, chips) that write straight to the ledger — so carbs can be logged in seconds without the camera. It also lets the user manage their own quick-add presets and edit or delete any ledger record, keeping the barrier to timely, accurate logging as low as possible.

A quick-add preset has two origins. It can be authored by hand (Req 4), or it can be born from a successful capture (Req 8): a meal eaten repeatedly at the same place is measured once with the camera and replayed with a tap on every later visit, so the second photo of a plate already measured is never taken.

## Dependencies

- **Home-router navigation shell** (separate `specs/ui/` spec, not yet written). That spec introduces a new home page routing to `intake` / `dose` / `records` and demotes Graph to visualisation only. This feature supplies the content of the `intake` route; the entry point itself is owned by the home-router spec. Until it lands, the intake surface can be reached from a temporary entry point (design decides the seam).

## Non-Goals

- The new home page / primary router and the demotion of Graph to visualisation-only — owned by the separate home-router `specs/ui/` spec; this feature only provides the `intake` route's content.
- Any change to the photo/estimation capture pipeline — it continues to write meal records exactly as today.
- Food-database (CoFID/AFCD) lookup for quick-add values — preset carb/macro values are fixed and user-set, not resolved from the bundled databases.
- Home-screen / lock-screen widgets and URL deep links for one-tap logging — deferred; not part of this feature.
- Named or nested quick-add groups — presets are a single flat collection (interpretation pending confirmation at review).
- Universal edit/delete over photo meals, insulin, and glucose records — deferred to the records/home-router spec, which owns the unified records surface; this spec edits/deletes manually-added carb entries only.
- Displaying macros in the graph or in daily totals — captured macros are shown only in an entry's own detail; no aggregate macro view.
- Recreating a meal from a preset — a preset replays as a manual carb record, never as a photo-derived meal. The originating capture's per-class decomposition, masks, photos, and confidence are not restored (Req 8.7).
- Recognising a repeat meal automatically — the app does not match a new capture against existing presets, nor suggest one. Saving a preset and replaying it are both explicit user actions.
- Re-deriving a capture-born preset when calibration lands — a preset's carbohydrate value is frozen at creation and is only ever changed by the user editing it.

## Requirements

### 1. Manual carb entry sheet

**User Story:** As someone logging my intake, I want to enter a carb amount and time in a simple sheet, so that I can record carbs without using the camera.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL present a carb-entry sheet reachable from the intake surface, following the same presentation pattern as the existing insulin-dose sheet (a modal sheet with a single primary field, an adjustable timestamp, and an explicit Save), using an input affordance suited to the carbohydrate range rather than the insulin stepper.  
2. <a name="1.2"></a>The sheet SHALL let the user enter a carbohydrate amount in whole grams and set a timestamp that defaults to the current time and can be back-dated.  
3. <a name="1.3"></a>WHEN the user taps Save, the system SHALL write one carb record to the ledger and dismiss the sheet.  
4. <a name="1.4"></a>The Save action SHALL be available only when the carbohydrate amount is at least 1 g, and the amount SHALL be constrained to the range 1–999 g.  

### 2. Optional macros

**User Story:** As someone tracking more than carbs, I want to optionally add protein, fat, and fibre to an entry, so that I can capture fuller nutrition when I have it without slowing the common case.

**Acceptance Criteria:**

1. <a name="2.1"></a>The carb-entry sheet SHALL keep protein, fat, and fibre behind a disclosure so the default path shows only the carbohydrate field.  
2. <a name="2.2"></a>WHERE the user expands the disclosure, the system SHALL allow entering protein, fat, and fibre in grams, each optional and independently omittable.  
3. <a name="2.3"></a>WHEN a macro field is left empty, the saved record SHALL record that macro as absent rather than zero.  
4. <a name="2.4"></a>The system SHALL display an entry's captured macros in that entry's detail/edit view; macros do not appear in the graph or in daily totals.  

### 3. Quick-add presets (one-tap logging)

**User Story:** As someone who eats the same things often, I want one-tap buttons for common items, so that a record lands in the ledger with a single tap.

**Acceptance Criteria:**

1. <a name="3.1"></a>The intake surface SHALL display the user's quick-add presets as tappable buttons, each labelled with its name (e.g. "A pint", "Bagel", "Chips").  
2. <a name="3.2"></a>WHEN the user taps a quick-add preset, the system SHALL write one carb record to the ledger using the preset's stored carbohydrate and macro values, timestamped at the current time, with no further prompt or confirmation.  
3. <a name="3.3"></a>The system SHALL ship a default set of quick-add presets so the surface is usable before the user creates any: "A pint" (17 g), "Bagel" (45 g), and "Chips" (40 g), carbohydrate values only. These authored defaults SHALL be editable and deletable like any user-created preset.  

### 4. Managing quick-add presets

**User Story:** As someone with my own habits, I want to create, edit, and delete quick-add presets, so that the buttons match what I actually eat.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL let the user create a quick-add preset with a name and a fixed carbohydrate value, and optionally protein, fat, and fibre in grams.  
2. <a name="4.2"></a>The system SHALL let the user edit and delete any existing quick-add preset.  
3. <a name="4.3"></a>Quick-add presets SHALL persist across app launches.  
4. <a name="4.4"></a>The system SHALL let the user save the values of a just-entered manual entry as a new quick-add preset, prompting for the preset's name, so a one-off entry becomes a reusable one-tap button.  

### 5. Intake surface

**User Story:** As a user, I want a single intake screen gathering manual entry and quick-adds, so that logging carbs is one clear place.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL provide an intake surface that hosts the quick-add presets and an affordance to open the carb-entry sheet.  
2. <a name="5.2"></a>The intake surface SHALL be presented via the home router's `intake` route; until that route exists, it SHALL be reachable from a single entry point in the app's current navigation.  

### 6. Ledger representation

**User Story:** As a user, I want manually-added carbs to appear in my records and graph like any other carbs, so that my totals stay complete.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL store each manual carb entry and each quick-add as a ledger event that is distinguishable from photo-derived meals.  
2. <a name="6.2"></a>Manual carb records SHALL contribute to the same carbohydrate totals and graph carb series as photo-derived meals.  
3. <a name="6.3"></a>WHEN a manual carb record is written or removed, the system SHALL emit the ledger change notification so dependent views refresh.  

### 7. Edit and delete manual entries

**User Story:** As a user, I want to change or remove a manual entry quickly, so that mistakes and mistimings don't corrupt my history.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL present the user's recent manual carb entries (both keyed-in and quick-add) in a list reachable from the intake surface.  
2. <a name="7.2"></a>The list SHALL let the user edit a manual entry's carbohydrate value, its optional macros, and its timestamp.  
3. <a name="7.3"></a>The list SHALL let the user delete a manual entry.  
4. <a name="7.4"></a>WHEN a manual entry is edited or deleted, the system SHALL persist the change and emit the ledger change notification so the affected carbohydrate totals and graph series refresh.  
5. <a name="7.5"></a>The edit and delete actions SHALL be reachable inline from the entry, without navigating through intermediate screens.  

*Note: edit/delete over photo meals, insulin, and glucose records is out of scope here — it belongs to the records/home-router spec that owns the unified records surface (see Non-Goals).*

### 8. Quick-add preset from a captured meal

**User Story:** As someone who eats the same meal at the same place again and again, I want to save a captured meal as a quick-add preset, so that on every later visit I log it with one tap instead of photographing a plate I have already measured.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL offer a save-as-preset action on a meal's result surface, both on the surface shown immediately after a successful capture and on the surface reached from records.  
2. <a name="8.2"></a>WHEN the user invokes the save-as-preset action, the system SHALL open the same preset-creation surface used for a hand-authored preset (Req 4.1), pre-filled with the meal's carbohydrate value and with a preset name derived from the meal's detected foods, both editable before the preset is saved.  
3. <a name="8.3"></a>The carbohydrate value carried into the preset SHALL be the total the result surface is displaying at that moment, including any corrections the user has already made to that meal, rather than the pipeline's original estimate.  
4. <a name="8.4"></a>The preset SHALL carry a carbohydrate value only; protein, fat, and fibre SHALL be left absent for the user to supply.  
5. <a name="8.5"></a>The save-as-preset action SHALL be available for any displayed meal result regardless of its confidence band or calibration state.  
6. <a name="8.6"></a>A preset created from a meal SHALL behave as any other quick-add preset wherever it appears — the same tile, the same one-tap write (Req 3.2), and the same edit and delete (Req 4.2).  
7. <a name="8.7"></a>WHEN a preset created from a meal is tapped, the system SHALL write one manual carb record exactly as any other quick-add does, and SHALL NOT create a meal record or any photo-derived data.  
8. <a name="8.8"></a>The system SHALL record which meal a preset was created from as a point-in-time stamp; correcting or deleting the originating meal SHALL NOT change, invalidate, or remove the preset.  
9. <a name="8.9"></a>WHEN a preset created from a meal is subsequently edited (Req 4.2), the system SHALL preserve its originating-meal stamp.  

*Note: a refused capture produces no result surface, so there is nothing to save from it; Req 8.5 constrains only results that are actually displayed.*
