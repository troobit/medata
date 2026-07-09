---
references:
    - requirements.md
    - design.md
    - decision_log.md
---
# Home Router

## Records surface & shared plumbing

- [ ] 1. Add MealRouting.swift with RecordRow and the relocated shared symbols <!-- id:46pogp1 -->
  - New App/MealRouting.swift; move mealRouteDestination(_:store:path:) and CloseCoverButton out of DataView.swift (same module — TrendsView/SettingsView/CaptureFlowView must still resolve them)
  - RecordRow: Identifiable — cases meal(DisplayMeal), insulin(InsulinEntry), glucose(GlucoseRow); GlucoseRow carries (id: Event.id, timestamp, mmolL) since GlucoseReading has no id
  - timestamp is the sort key; id is the stable tie-break (UUID for meal/insulin, Event.id for glucose)
  - .intake(IntakeRecord) is the Track C extension point (Decision 14) — document only, do not add here
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)
  - References: design.md, decision_log.md

- [ ] 2. Implement RecordsModel — merged, live, most-recent-first <!-- id:46pogp2 -->
  - @Observable; meals via allMeals() composed with the DisplayMeal/MealHistoryModel corrections overlay (store.corrections(for:) per meal) so the row shows the corrected total, not MealRecord's original estimate
  - insulin via insulinEntry(from:); glucose by mapping .bsl Events to GlucoseRow keeping Event.id — do NOT reuse TrendsModel's id-dropping decoder
  - events(in:type:) is range-bounded — pass a Date.distantPast...Date.distantFuture sentinel for the all-time list (Decision 8)
  - merge, sort timestamp desc + id tie-break; subscribe to store.eventsDidChange and reload() on each tick
  - Blocked-by: 46pogp1 (Add MealRouting.swift with RecordRow and the relocated shared symbols)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)
  - References: design.md, decision_log.md

- [ ] 3. Implement RecordsView — unified timeline with delete <!-- id:46pogp3 -->
  - NavigationStack(path: [MealRoute]); rows visibly type-distinguished, each showing key value + timestamp (meal: corrected carbs g; insulin: units + bolus/basal; glucose: mmol/L)
  - meal rows NavigationLink(value: MealRoute.overview) via the shared mealRouteDestination; insulin and glucose rows do not navigate
  - swipe-to-delete on meal + insulin rows → store.deleteMeal(id:)/deleteInsulinEvent(id:), no confirmation dialog; glucose read-only
  - empty state: empty list, no copy (Req 3.8, no-disclaimer rule); CloseCoverButton in topBarLeading (Req 1.4)
  - Blocked-by: 46pogp2 (Implement RecordsModel — merged, live, most-recent-first)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8)
  - References: design.md

## Shell re-root & Graph demotion

- [ ] 4. Extend AppRoot.ActiveSheet, present the five covers, remove DataView <!-- id:46pogp4 -->
  - ActiveSheet → capture / intake / records / graph / settings; fullScreenCover(item:) presents CaptureFlowView / IntakeView / RecordsView / TrendsView / SettingsView, each carrying CloseCoverButton
  - .intake presents the Track C-owned IntakeView (forward reference, Decision 12) — the branch compiles once IntakeView lands
  - delete DataView.swift (Records supersedes the meal-only Data screen, Decision 6); the .data route is gone
  - Blocked-by: 46pogp3 (Implement RecordsView — unified timeline with delete)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [3.9](requirements.md#3.9)
  - References: design.md, decision_log.md

- [ ] 5. Create HomeView — the launch-root router <!-- id:46pogp5 -->
  - App/HomeView.swift; six controls (Capture, Intake, Dose, Records, Graph, Settings) firing closures injected by AppRoot; no presentation state of its own
  - Capture is the primary action — accent-prominent (.borderedProminent .tint(.medataAccent)), most prominent position
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)
  - References: design.md

- [ ] 6. Swap AppRoot root content to HomeView and wire it <!-- id:46pogp6 -->
  - AppRoot.body renders HomeView instead of TrendsView; inject closures that set activeSheet / showInsulinSheet
  - keep onChange(of: activeSheet) → capturePresented()/captureDismissed() unchanged (AR session armed only while .capture, Req 1.5); keep onOpenURL + pendingDeepLink deferral in AppRoot (Decision 9)
  - Blocked-by: 46pogp4 (Extend AppRoot.ActiveSheet, present the five covers, remove DataView), 46pogp5 (Create HomeView — the launch-root router)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1)
  - References: design.md, decision_log.md

- [ ] 7. Relocate the insulin sheet and deep-link handoff to AppRoot <!-- id:46pogp7 -->
  - move insulin .sheet(isPresented: $showInsulinSheet, onDismiss:) and the onInsulinSheetDismiss pending-.captureCover handoff from TrendsView to AppRoot (Decision 10)
  - the Dose home control and medata://insulin/add both target this sheet; preserve the deferral-behind-a-conflicting-surface behaviour
  - Blocked-by: 46pogp6 (Swap AppRoot root content to HomeView and wire it)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6)
  - References: design.md, decision_log.md

- [ ] 8. Demote Graph to visualisation-only in TrendsView <!-- id:46pogp8 -->
  - remove the graph.data / graph.settings / graph.insulin / graph.capture toolbar controls and their injected closures/bindings; remove the now-dead .onChange(of: showInsulinSheet)
  - remove the inline day-insulin .onDelete (Req 2.4); keep the chart + ranges, trends.options, and the day-meal tap-through (Decision 11)
  - add CloseCoverButton in topBarLeading (Graph is now a cover)
  - Blocked-by: 46pogp7 (Relocate the insulin sheet and deep-link handoff to AppRoot)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)
  - References: design.md, decision_log.md

## Verify

- [ ] 9. On-device verification of the home-router flow <!-- id:46pogp9 -->
  - make deploy-device (or deploy-release-stub) + on device: HomeView root, no tab bar; six controls route, Capture prominent; each surface closes to home; AR session only during Capture; medata://capture and medata://insulin/add route and defer behind an open surface
  - Graph shows no entry-point controls and no delete; Records merges meals+insulin+glucose most-recent-first, a delete reflects live on Records and Graph, glucose not deletable, empty Records has no copy
  - make test stays green (MedataCore). No app-target unit/UI tests added — MVP test gate; all tasks are UI/wiring (TDD-exempt per the starwave-tasks rule + CLAUDE.md)
  - Intake route's full verification is gated on Track C's IntakeView landing (forward reference); the other five routes verify independently
  - Blocked-by: 46pogp8 (Demote Graph to visualisation-only in TrendsView)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8)
  - References: design.md
