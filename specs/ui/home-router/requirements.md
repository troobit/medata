# Requirements: Home Router

## Introduction

MeData currently opens on the Graph screen and hangs every entry point — Capture, Data, Settings, insulin dosing — off the Graph toolbar (design-handoff-00 Decision 20). This feature introduces a new home page that becomes the launch root and acts as the app's primary router to Capture, Intake, Dose, Records, Graph, and Settings, demoting Graph to a visualisation-only surface. It also adds a single Records surface that lists meals, insulin, and glucose in one chronological timeline and lets the user delete the records they own, replacing the meal-only Data screen.

## Dependencies

- **Manual carb/macro intake** (`specs/data/manual-carb-intake/`). That spec supplies the content of the `intake` route (the carb-entry sheet and quick-add presets); this spec owns the route and its entry point on the home page. The two specs meet at that seam. Delivery order is not fixed: if the home page ships before the intake surface is integrated, the design decides the interim destination of the Intake control — this spec does not block on `manual-carb-intake`.

## Non-Goals

- Editing records in place. Meals and insulin are delete-and-re-add only for now; in-place editing is deferred to a future feature pending UX feedback.
- Editing or deleting glucose readings. Glucose is import-sourced (LibreLink) and remains read-only; a deletion would be undone by the next import.
- The `intake` route's content — the carb-entry sheet and quick-add presets are owned by `manual-carb-intake`; this spec provides only the route and its home-page control.
- Changes to the capture/estimation pipeline, the insulin dose-entry sheet's internals, or the meal-correction flow — only where they are launched from changes.
- Changes to the Graph chart's data, series, or ranges — Graph keeps its existing visualisation; only its role as root and its toolbar entry points change.
- At-a-glance summary data on the home page (e.g. today's carb total, latest glucose) — the home page is a pure router; a summary is deferred.
- Search, filtering, grouping, or per-type sectioning on the Records timeline.

## Requirements

### 1. Home page as launch root and router

**User Story:** As a user, I want the app to open on a home page that routes to everything, so that no single surface is privileged as the entry point.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the app launches, THEN it SHALL present the home page full-screen as the navigation root, with no tab bar (reverses design-handoff-00 Decision 20, which made Graph the launch root).  
2. <a name="1.2"></a>The home page SHALL present a control for each of these routes — Capture, Intake, Dose, Records, Graph, and Settings — each opening the corresponding surface.  
3. <a name="1.3"></a>The Capture control SHALL be presented as the home page's primary action — given the most visually prominent treatment and position among the route controls.  
4. <a name="1.4"></a>Each surface presented from the home page SHALL carry an explicit close control returning to the home page, matching the existing full-screen-cover close pattern (design-handoff-00 Decision 19).  
5. <a name="1.5"></a>The AR session SHALL run only while the Capture surface is presented — armed on presentation, released within 200 ms of the surface closing or the app backgrounding — anchored at the home root (behaviour preserved from Decision 20).  
6. <a name="1.6"></a>Existing deep links SHALL continue to work from the home root: `medata://capture` SHALL open Capture and `medata://insulin/add` SHALL open the Dose surface (the same insulin dose-entry sheet the Dose control opens). WHEN a deep link arrives while a conflicting surface is already presented, THEN it SHALL be deferred and honoured once that surface closes, preserving the current deferral behaviour.  

### 2. Graph demoted to visualisation only

**User Story:** As a user, I want Graph to be just the chart, so that it stops doubling as the app's navigation hub.

**Acceptance Criteria:**

1. <a name="2.1"></a>Graph SHALL be reachable as a route from the home page and SHALL NOT be the launch root.  
2. <a name="2.2"></a>Graph SHALL retain its existing glucose, carbs, and insulin visualisation across the Day, Week, and Month ranges unchanged.  
3. <a name="2.3"></a>The Capture, Data, Settings, and Dose (insulin) entry-point controls SHALL be removed from the Graph chrome, having moved to the home page.  
4. <a name="2.4"></a>Graph SHALL NOT provide record deletion; deletion of records is provided only on the Records surface (§3).  

### 3. Unified Records surface

**User Story:** As a user, I want one place that lists everything I've recorded, so that I can review and remove entries without hunting across screens.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL provide a Records surface, reachable from the home page, that presents all meals, insulin doses, and glucose readings in one chronological timeline ordered most-recent-first, with no filtering or windowing; records sharing a timestamp SHALL be ordered by a stable, deterministic tie-break.  
2. <a name="3.2"></a>Each row SHALL be visibly distinguishable by record type and SHALL show that record's key value and timestamp — carbohydrate grams for a meal, units with bolus/basal for an insulin dose, and mmol/L for a glucose reading. For a corrected meal, the row SHALL show the meal's current carbohydrate total including any correction.  
3. <a name="3.3"></a>WHEN the user taps a meal row, THEN the system SHALL present that meal's existing detail view; insulin and glucose rows SHALL NOT navigate to a detail view.  
4. <a name="3.4"></a>The system SHALL let the user delete a meal record and an insulin record from the Records surface via an inline delete affordance (the existing swipe-to-delete interaction); deleting a meal SHALL cascade its corrections and artefacts as the current delete does, and no additional confirmation step SHALL be required beyond the affordance itself.  
5. <a name="3.5"></a>Glucose rows SHALL be read-only — neither editable nor deletable from the Records surface.  
6. <a name="3.6"></a>WHEN a record is deleted, THEN the system SHALL persist the deletion, and the Graph, the Records list itself, and any other dependent view SHALL reflect the change without a manual refresh.  
7. <a name="3.7"></a>WHEN a record is added elsewhere in the app, THEN the Records surface SHALL reflect it without a manual refresh.  
8. <a name="3.8"></a>WHEN there are no records, THEN the Records surface SHALL present an empty timeline with no reassurance or explanatory copy (developer-phase no-disclaimer rule).  
9. <a name="3.9"></a>The Records surface SHALL replace the meal-only Data screen; the home page SHALL route to Records rather than to a separate meal-only Data screen.  
