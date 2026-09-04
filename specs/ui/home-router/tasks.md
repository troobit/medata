---
references:
    - specs/ui/home-router/requirements.md
    - specs/ui/home-router/design.md
    - specs/ui/home-router/decision_log.md
---
# Home Router

## Records surface & shared plumbing

- [x] 1. Add MealRouting.swift with RecordRow and the relocated shared symbols <!-- id:46pogp1 -->
  - New App/MealRouting.swift; move mealRouteDestination(_:store:path:) and CloseCoverButton out of DataView.swift (same module — TrendsView/SettingsView/CaptureFlowView must still resolve them)
  - RecordRow: Identifiable — cases meal(DisplayMeal), insulin(InsulinEntry), glucose(GlucoseRow); GlucoseRow carries (id: Event.id, timestamp, mmolL) since GlucoseReading has no id
  - timestamp is the sort key; id is the stable tie-break (UUID for meal/insulin, Event.id for glucose)
  - .intake(IntakeRecord) is the Track C extension point (Decision 14) — document only, do not add here
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)
  - References: design.md, decision_log.md

- [x] 2. Implement RecordsModel — merged, live, most-recent-first <!-- id:46pogp2 -->
  - @Observable; meals via allMeals() composed with the DisplayMeal/MealHistoryModel corrections overlay (store.corrections(for:) per meal) so the row shows the corrected total, not MealRecord's original estimate
  - insulin via insulinEntry(from:); glucose by mapping .bsl Events to GlucoseRow keeping Event.id — do NOT reuse TrendsModel's id-dropping decoder
  - events(in:type:) is range-bounded — pass a Date.distantPast...Date.distantFuture sentinel for the all-time list (Decision 8)
  - merge, sort timestamp desc + id tie-break; subscribe to store.eventsDidChange and reload() on each tick
  - Blocked-by: 46pogp1 (Add MealRouting.swift with RecordRow and the relocated shared symbols)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)
  - References: design.md, decision_log.md

- [x] 3. Implement RecordsView — unified timeline with delete <!-- id:46pogp3 -->
  - NavigationStack(path: [MealRoute]); rows visibly type-distinguished, each showing key value + timestamp (meal: corrected carbs g; insulin: units + bolus/basal; glucose: mmol/L)
  - meal rows NavigationLink(value: MealRoute.overview) via the shared mealRouteDestination; insulin and glucose rows do not navigate
  - swipe-to-delete on meal + insulin rows → store.deleteMeal(id:)/deleteInsulinEvent(id:), no confirmation dialog; glucose read-only
  - empty state: empty list, no copy (Req 3.8, no-disclaimer rule); CloseCoverButton in topBarLeading (Req 1.4)
  - Blocked-by: 46pogp2 (Implement RecordsModel — merged, live, most-recent-first)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8)
  - References: design.md

## Shell re-root & Graph demotion

- [x] 4. Extend AppRoot.ActiveSheet, present the five covers, remove DataView <!-- id:46pogp4 -->
  - ActiveSheet → capture / intake / records / graph / settings; fullScreenCover(item:) presents CaptureFlowView / IntakeView / RecordsView / TrendsView / SettingsView, each carrying CloseCoverButton
  - .intake presents the Track C-owned IntakeView (forward reference, Decision 12) — the branch compiles once IntakeView lands
  - delete DataView.swift (Records supersedes the meal-only Data screen, Decision 6); the .data route is gone
  - Blocked-by: 46pogp3 (Implement RecordsView — unified timeline with delete)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [3.9](requirements.md#3.9)
  - References: design.md, decision_log.md

- [x] 5. Create HomeView — the launch-root router <!-- id:46pogp5 -->
  - App/HomeView.swift; six controls (Capture, Intake, Dose, Records, Graph, Settings) firing closures injected by AppRoot; no presentation state of its own
  - Capture is the primary action — accent-prominent (.borderedProminent .tint(.medataAccent)), most prominent position
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)
  - References: design.md

- [x] 6. Swap AppRoot root content to HomeView and wire it <!-- id:46pogp6 -->
  - AppRoot.body renders HomeView instead of TrendsView; inject closures that set activeSheet / showInsulinSheet
  - keep onChange(of: activeSheet) → capturePresented()/captureDismissed() unchanged (AR session armed only while .capture, Req 1.5); keep onOpenURL + pendingDeepLink deferral in AppRoot (Decision 9)
  - Blocked-by: 46pogp4 (Extend AppRoot.ActiveSheet, present the five covers, remove DataView), 46pogp5 (Create HomeView — the launch-root router)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1)
  - References: design.md, decision_log.md

- [x] 7. Relocate the insulin sheet and deep-link handoff to AppRoot <!-- id:46pogp7 -->
  - move insulin .sheet(isPresented: $showInsulinSheet, onDismiss:) and the onInsulinSheetDismiss pending-.captureCover handoff from TrendsView to AppRoot (Decision 10)
  - the Dose home control and medata://insulin/add both target this sheet; preserve the deferral-behind-a-conflicting-surface behaviour
  - Blocked-by: 46pogp6 (Swap AppRoot root content to HomeView and wire it)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6)
  - References: design.md, decision_log.md

- [x] 8. Demote Graph to visualisation-only in TrendsView <!-- id:46pogp8 -->
  - remove the graph.data / graph.settings / graph.insulin / graph.capture toolbar controls and their injected closures/bindings; remove the now-dead .onChange(of: showInsulinSheet)
  - remove the inline day-insulin .onDelete (Req 2.4); keep the chart + ranges, trends.options, and the day-meal tap-through (Decision 11)
  - add CloseCoverButton in topBarLeading (Graph is now a cover)
  - Blocked-by: 46pogp7 (Relocate the insulin sheet and deep-link handoff to AppRoot)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)
  - References: design.md, decision_log.md

## Verify

- [x] 9. On-device verification of the home-router flow <!-- id:46pogp9 -->
  - make deploy-device (or deploy-release-stub) + on device: HomeView root, no tab bar; six controls route, Capture prominent; each surface closes to home; AR session only during Capture; medata://capture and medata://insulin/add route and defer behind an open surface
  - Graph shows no entry-point controls and no delete; Records merges meals+insulin+glucose most-recent-first, a delete reflects live on Records and Graph, glucose not deletable, empty Records has no copy
  - make test stays green (MedataCore). No app-target unit/UI tests added — MVP test gate; all tasks are UI/wiring (TDD-exempt per the starwave-tasks rule + CLAUDE.md)
  - Intake route's full verification is gated on Track C's IntakeView landing (forward reference); the other five routes verify independently
  - 2026-08-04 device pass: routing confirmed fine by the developer. Outstanding before this ticks — deep-link deferral, AR-session release timing, and the Records delete/add live-reflect items above; re-check alongside task 11 on the same build
  - 2026-08-13 developer verdict: gate closed — home screen verified fine on device; the outstanding 2026-08-04 checklist items are accepted under this blanket verdict
  - Blocked-by: 46pogp8 (Demote Graph to visualisation-only in TrendsView)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8)
  - References: design.md

## Latest-glucose header

- [x] 10. Latest-glucose header on the home page <!-- id:gnuq1hq -->
  - GlucoseSnapshotSource in Persistence — lift the display-horizon read; the future-skew window bound and the snapshot derivation out of GlucoseWidgetPublisher; the publisher calls it and keeps only its write/reload plus the futureReading log (Req 4.7)
  - App/HomeGlucoseModel.swift — @Observable @MainActor holding one GlucoseSnapshot; reloads on store.eventsDidChange (RecordsModel pattern). Reads the STORE not GlucoseSnapshotStore so the header does not depend on App Group provisioning
  - HomeView.glucoseHeader — value + mmol/L + age above the route controls; TimelineView(.periodic by 60) so the age advances; arrow and band colour withheld past GlucoseTimeline.staleAge; em-dash placeholder with no copy when nothing is inside the horizon
  - Owned as @State on AppRoot; not inside HomeView — HomeView is rebuilt on every cover present/dismiss and would otherwise re-subscribe each time
  - Register HomeGlucoseModel.swift in project.pbxproj (four places — App/ is not a synchronised group)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.8](requirements.md#4.8)
  - References: design.md, decision_log.md

- [x] 11. STOP — on-device verification of the latest-glucose header <!-- id:31pjp18 -->
  - make deploy-device + on device: the reading is the topmost content on home above Capture; value matches the newest bsl row and the lock-screen widget
  - trend arrow present when readings support a rate; absent (not a placeholder) when they do not
  - let a reading go past 15 min: arrow and band colour disappear; value and age remain; age advances while home is open
  - no reading inside 24 h: em-dash placeholder with no copy
  - a fresh CGM/HealthKit reading lands while home is visible and the header updates with no manual refresh
  - make test stays green (MedataCore); no app-target tests added — MVP test gate
  - 2026-08-04 build 470bb1b-20260804-225023 (Release + real segmenter): header renders a live reading on device — remaining items above still to check
  - 2026-08-13 developer verdict: STOP gate closed — home screen incl. latest-glucose header verified fine on device; the remaining checklist items are accepted under this blanket verdict
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.8](requirements.md#4.8)
  - References: design.md

## Meal-detail collapse (Decision 16)

- [x] 12. ResultView absorbs the overview's content (UI, no new tests) <!-- id:gnuq1hr -->
  - From App/MealOverviewView.swift into App/ResultView.swift: the capture-metadata line, the toolbar ⋯ menu with Delete behind its confirmation dialog, and the mask-overlay photo path (MaskOverlayLoader) — integration points per the design's meal-detail bullet
  - The dose readout on this surface recomputes live (insulin-dosing Req 6.10/6.12; its Phase 9 tasks own the model) — this task wires the surface, not the arithmetic
  - App-target change: gate is make build-app + the device look (project test rule)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3)

- [x] 13. Reroute Records and the Graph day list; delete the overview and the DEBUG review route <!-- id:gnuq1hs -->
  - App/RecordsView.swift:153 and App/TrendsView.swift:361 NavigationLinks push MealRoute.result
  - Delete App/MealOverviewView.swift, the MealRoute.overview and DEBUG MealRoute.review cases (App/CaptureState.swift), and their destinations in App/MealRouting.swift — mealRouteDestination collapses to .result
  - Remove the file from project.pbxproj in the four places (docs/agent-notes/ui-capture-flow.md checklist)
  - Done/Delete unwind: .result already pops one on Done and removeAll on delete — with a one-element path both land on the list
  - Blocked-by: gnuq1hr (ResultView absorbs the overview's content UI, no new tests)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4)

- [x] 14. Gate + STOP — build, spell, and the on-device collapse check <!-- id:gnuq1ht -->
  - make build-app + make spell; then on device: one tap from a Records meal row and from a Graph day-list row lands on the full detail (photo with overlays, food rows with adjustment, metadata, delete, dose line); no intermediate screen exists anywhere; delete from the detail unwinds to the list
  - Blocked-by: gnuq1hs (Reroute Records and the Graph day list; delete the overview and the DEBUG review route)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [3.6](requirements.md#3.6)
