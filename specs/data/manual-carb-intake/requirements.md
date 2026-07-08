# Requirements: Manual Carb/Macro Intake

## Introduction

MeData currently records carbs only as a by-product of the photo/estimation pipeline. This feature adds a direct manual intake path: a carb-entry sheet modelled on the existing insulin-dose flow, and one-tap quick-add presets (e.g. a pint, a bagel, chips) that write straight to the ledger — so carbs can be logged in seconds without the camera. It also lets the user manage their own quick-add presets and edit or delete any ledger record, keeping the barrier to timely, accurate logging as low as possible.

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
