---
references:
    - specs/data/manual-carb-intake/requirements.md
    - specs/data/manual-carb-intake/design.md
    - specs/data/manual-carb-intake/decision_log.md
---
# Tasks: Manual Carb/Macro Intake

## Persistence: intake events

- [x] 1. Write tests for EventType.intake save/update/delete/range-validation <!-- id:yh454ud -->
  - New MedataCore/Tests/PersistenceTests/IntakeEventTests.swift, XCTest style matching InsulinEventTests.swift (temp GRDBPersistenceStore, setUp/tearDown)
  - Cover: saveIntakeEntry writes one events row (event_type=intake, value=carbs, metadata has subtype/schema_version/source, omits macro keys when absent per Req 2.3)
  - Cover: updateIntakeEntry updates the same row id; deleteIntakeEntry deletes only event_type=intake rows (a same-id meal/insulin/bsl row survives)
  - Cover: carbsG outside 1...999 throws PersistenceError.intakeCarbsOutOfRange on both save and update
  - Cover: eventsDidChange fires once per write
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.3](requirements.md#2.3), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: design.md#Event type and storage, design.md#PersistenceStore additions

- [x] 2. Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests <!-- id:yh454ue -->
  - Add EventType.intake constant; new types in MedataCore/Sources/Persistence (new IntakeEvent.swift file alongside the existing InsulinDose types)
  - Add PersistenceError.intakeCarbsOutOfRange(Double) case
  - GRDBPersistenceStore implementations mirror saveInsulinDose/deleteInsulinEvent exactly; metadata JSON omits nil macro keys, never null
  - Blocked-by: yh454ud (Write tests for EventType.intake save/update/delete/range-validation)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.3](requirements.md#2.3), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: design.md#Event type and storage, design.md#PersistenceStore additions

## Persistence: quick-add presets

- [x] 3. Write tests for quick_presets table CRUD and first-launch seeding <!-- id:yh454uf -->
  - New MedataCore/Tests/PersistenceTests/QuickPresetTests.swift, XCTest style matching InsulinEventTests.swift
  - Cover: saveQuickPreset insert + update-by-id, deleteQuickPreset, quickPresets() returns sort_order ASC, macro fields NULL when absent
  - Cover: first store-init on an empty DB seeds exactly the three authored defaults (A pint 17g, Bagel 45g, Chips 40g); a second init does NOT reseed once presets exist
  - Stream: 2
  - Requirements: [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)
  - References: design.md#Quick-add presets — new table

- [x] 4. Implement quick_presets schema (v4->v5 migration) and QuickPreset CRUD to pass tests <!-- id:yh454ug -->
  - GRDBPersistenceStore.createSchema adds CREATE TABLE IF NOT EXISTS quick_presets; migrate() re-stamps schema_version='5' matching the processed_images/v4 precedent
  - QuickPreset struct + quickPresets()/saveQuickPreset()/deleteQuickPreset() in Persistence
  - Idempotent first-launch seed of the 3 defaults gated on the table being empty at store-init
  - Blocked-by: yh454uf (Write tests for quick_presets table CRUD and first-launch seeding)
  - Stream: 2
  - Requirements: [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)
  - References: design.md#Quick-add presets — new table

## Graph and Records integration

- [x] 5. Extend TrendsModel to fold .intake events into carbBars <!-- id:yh454uh -->
  - App/TrendsModel.swift reload() adds a fourth events(in:type:) fetch for EventType.intake, decoded into private(set) var intakeCarbs: [DatedValue]
  - recomputeSeries merges meals+intakeCarbs into one carbBars series for both Day (per-entry TrendsChartPoint) and Week/Month (combined samples through the existing single TrendsMath.dailyBuckets call) per design.md's sketch
  - No new test task — App-layer, build+on-device gate only (testing-mvp-minimal convention)
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2)
  - References: design.md#Carb totals and graph series

- [x] 6. Add RecordRow.intake(IntakeRecord) case and wire RecordsModel/delete <!-- id:yh454ui -->
  - App/MealRouting.swift adds IntakeRecord struct (wraps IntakeEntry: id/timestamp/displayValue/typeLabel="Carbs") and the .intake case plus its timestamp/id switch arms (id via entry.id.uuidString)
  - App/RecordsModel.swift adds private loadIntake() with its own private intakeEntry(from:) decoder (not shared — matches home-router Decision 13's per-model-decoder convention), merged in reload()
  - One additive case in RecordsModel.delete(_:) calling store.deleteIntakeEntry(id:)
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1)
  - References: design.md#Records integration

## Intake surface

- [x] 7. Build CarbEntryModel and CarbEntrySheet (new + edit) <!-- id:yh454uj -->
  - New App/CarbEntryModel.swift (@Observable @MainActor): carbs text field state clamped 1-999, macro fields with disclosure-expanded-if-editing-has-macros per design.md, timestamp defaulting to now/back-dateable, save()/update() via store, optional editing: IntakeEntry? init param
  - New App/CarbEntrySheet.swift: NavigationStack, numeric keypad TextField for carbs (no stepper), DatePicker matching InsulinDoseSheet.timeRow, DisclosureGroup for protein/fat/fibre, Save button disabled below 1g
  - No test task — App-layer UI, build+on-device gate
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests), yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [7.2](requirements.md#7.2)
  - References: design.md#Views

- [x] 8. Build QuickPresetEditSheet and save-as-preset action <!-- id:yh454uk -->
  - New App/QuickPresetEditSheet.swift: name field + carb/macro fields, create or edit an existing QuickPreset
  - CarbEntrySheet gains the "Save as quick-add" secondary action opening QuickPresetEditSheet pre-filled from the just-saved entry's values, independent of the entry save (cancelling creates no preset)
  - No test task — App-layer UI
  - Blocked-by: yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4)
  - References: design.md#Views

- [x] 9. Build IntakeModel <!-- id:yh454ul -->
  - New App/IntakeModel.swift (@Observable @MainActor): loads/reloads quickPresets() and recent intake entries via events(in:type:) with the all-time sentinel + own private intakeEntry(from:) decoder, sorted desc + truncated in Swift per design.md
  - tapPreset(_:) calls saveIntakeEntry directly with source=.quickadd/presetID set, no sheet
  - Subscribes to store.eventsDidChange, same pattern as MealHistoryModel/RecordsModel
  - delete(_:) for both recent entries and presets
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests), yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.3](requirements.md#4.3), [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)
  - References: design.md#Views

- [x] 10. Replace IntakeView.swift wholesale and wire quick-add grid + recent-entries list <!-- id:yh454um -->
  - App/IntakeView.swift body replaced (currently a Color.surfacePrimary placeholder): quick-add grid
  - one button per preset labelled with preset.name (Req 3.1)
  - "Enter amount" affordance opening CarbEntrySheet()
  - Recent-entries List section below with .swipeActions delete (no confirmation
  - matches RecordsView) and tap-to-edit opening CarbEntrySheet(editing:) inline (Req 7.5
  - no intermediate screens)
  - Keep the existing NavigationStack + CloseCoverButton shell
  - Req 5.2 needs no new wiring here: home-router's AppRoot already presents IntakeView() from ActiveSheet.intake (design.md#Home-router seam) — this task only replaces IntakeView's body
  - No test task — App-layer UI
  - verified by the on-device checklist in design.md
  - Blocked-by: yh454uj (Build CarbEntryModel and CarbEntrySheet new + edit), yh454uk (Build QuickPresetEditSheet and save-as-preset action), yh454ul (Build IntakeModel)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [7.1](requirements.md#7.1), [7.3](requirements.md#7.3), [7.5](requirements.md#7.5)
  - References: design.md#Views

## Verification

- [x] 11. Register new files in project.pbxproj and build <!-- id:yh454un -->
  - Register IntakeEvent.swift, CarbEntryModel.swift, CarbEntrySheet.swift, QuickPresetEditSheet.swift, IntakeModel.swift, IntakeEventTests.swift, QuickPresetTests.swift in MeData.xcodeproj/project.pbxproj (four-section checklist per docs/agent-notes/ui-capture-flow.md)
  - Run make build and make test; report both XCTest and swift-testing totals
  - Run make spell
  - Blocked-by: yh454uh (Extend TrendsModel to fold .intake events into carbBars), yh454ui (Add RecordRow.intakeIntakeRecord case and wire RecordsModel/delete), yh454uj (Build CarbEntryModel and CarbEntrySheet new + edit), yh454uk (Build QuickPresetEditSheet and save-as-preset action), yh454ul (Build IntakeModel), yh454um (Replace IntakeView.swift wholesale and wire quick-add grid + recent-entries list)
  - Stream: 1
  - References: docs/agent-notes/ui-capture-flow.md, docs/agent-notes/device-build-and-test.md

## Preset origin stamp (Req 8.8, 8.9)

- [ ] 12. Write tests for quick_presets.source_meal_id round-trip and the schema 9 to 10 migration <!-- id:yh454uo -->
  - Extend MedataCore/Tests/PersistenceTests/QuickPresetTests.swift, XCTest style matching the existing cases
  - Cover: saveQuickPreset persists sourceMealID and quickPresets() reads it back; nil round-trips as NULL
  - Cover: an INSERT OR REPLACE update of an existing preset preserves source_meal_id when the caller passes it through, per Req 8.9
  - Cover: a DB created at schema 9 (quick_presets without the column) gains source_meal_id on open, its existing presets survive with NULL, and a second open does not throw duplicate column name
  - Cover: deleting the meal named by source_meal_id leaves the preset row and its value unchanged (Req 8.8) - the stamp is never dereferenced
  - Stream: 1
  - Requirements: [8.8](requirements.md#8.8), [8.9](requirements.md#8.9)
  - References: design.md#Schema: quick_presets.source_meal_id

- [ ] 13. Implement schema v10, QuickPreset.sourceMealID, and QuickPreset.nextSortOrder(after:) <!-- id:yh454up -->
  - GRDBPersistenceStore.createSchema: quick_presets CREATE TABLE gains source_meal_id TEXT (nullable); stamp schema_version 10
  - migrate(): read the stored schema_version before re-stamping and run ALTER TABLE quick_presets ADD COLUMN source_meal_id TEXT only when it is below 10 - ADD COLUMN is not idempotent in SQLite. Non-destructive, so event-log-schema Decision 10 still holds
  - Update the migrate() header comment with the version-9 line, matching the existing per-version notes
  - QuickPreset gains public var sourceMealID: UUID?; quickPreset(from:) decodes it, saveQuickPreset binds it
  - Add public static func nextSortOrder(after presets: [QuickPreset]) -> Int to QuickPreset and rewrite IntakeModel.nextSortOrder to call it - one expression, three call sites
  - Blocked-by: yh454uo (Write tests for quick_presets.source_meal_id round-trip and the schema 9 to 10 migration)
  - Stream: 1
  - Requirements: [8.8](requirements.md#8.8), [8.9](requirements.md#8.9)
  - References: design.md#Schema: quick_presets.source_meal_id, decision_log.md

- [ ] 14. Carry sourceMealID through QuickPresetEditSheet edits <!-- id:yh454uq -->
  - App/QuickPresetEditSheet.swift destructures the preset it is given and reconstructs a QuickPreset on save, so an edit silently drops the new column
  - Capture private let sourceMealID: UUID? in init alongside presetID/sortOrder and pass it through untouched on save
  - No test task - App-layer UI; covered by the store-level Req 8.9 case and the on-device checklist
  - Blocked-by: yh454up (Implement schema v10, QuickPreset.sourceMealID, and QuickPreset.nextSortOrderafter:)
  - Stream: 1
  - Requirements: [8.9](requirements.md#8.9)
  - References: design.md#Schema: quick_presets.source_meal_id

## Save as quick-add from a result surface (Req 8)

- [ ] 15. Add the shared quickPresetDraft builder to MealRouting.swift <!-- id:yh454ur -->
  - App/MealRouting.swift - the existing home for App-layer meal plumbing shared across surfaces, so no new file and no project.pbxproj registration
  - quickPresetDraft(displayedCarbsG:foodNames:sourceMealID:existingPresets:) -> QuickPreset
  - Name: first two prettified food names joined with " + ", then " +N" when N further foods remain; empty when the caller passes no names
  - Carbs: Double(displayedCarbsG.rounded()) clamped into CarbEntryModel.minCarbs...maxCarbs (1...999); a meal rounding to 0 g yields an empty carb field and a disabled Save via the sheet existing canSave rule
  - Macros: left absent (Req 8.4) - clinicalTotals protein/fat/fibre are deliberately not carried
  - sortOrder from QuickPreset.nextSortOrder(after: existingPresets)
  - Blocked-by: yh454up (Implement schema v10, QuickPreset.sourceMealID, and QuickPreset.nextSortOrderafter:)
  - Stream: 1
  - Requirements: [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4)
  - References: design.md#The flattening, and what survives it, design.md#Which number is frozen

- [ ] 16. Add Save as quick-add to MealReviewView (post-capture) <!-- id:yh454us -->
  - One non-destructive Button in the existing ToolbarItem(placement: .topBarTrailing) Menu, above Retake and Delete; label "Save as quick-add" - the string CarbEntrySheet already ships; a11y id review.saveAsQuickAdd
  - @State private var presetDraft: QuickPreset? plus .sheet(item:) presenting QuickPresetEditSheet(store:preset:isNew: true), same construction as CarbEntrySheet
  - Draft inputs: model.pendingTotalCarbsG (corrected total, Req 8.3), model.activeFoods.map { MealReviewModel.prettify($0.currentClassId) } in the existing carbs-descending order, model.record.id, and store.quickPresets() fetched inside the menu action with the usual (try? ...) ?? [] fallback
  - No confidence, calibration, or dev_stub gate (Req 8.5, Decision 12); no new copy beyond the label (developer-phase no-disclaimer rule)
  - No test task - App-layer UI, build + on-device gate
  - Blocked-by: yh454ur (Add the shared quickPresetDraft builder to MealRouting.swift)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.5](requirements.md#8.5)
  - References: design.md#The action on the two result surfaces

- [ ] 17. Add Save as quick-add to ResultView (from records) <!-- id:yh454ut -->
  - One Button in the actionRow ellipsis Menu, above the destructive Delete; same "Save as quick-add" label; a11y id result.saveAsQuickAdd
  - Same @State presetDraft + .sheet(item:) shape as the review surface; ResultView already holds let store: any PersistenceStore
  - Draft inputs: heroCarbsG (the displayed total, adjustments and corrections included, Req 8.3), the existing prettified carbs-sorted rows, record.id, and store.quickPresets()
  - No test task - App-layer UI, build + on-device gate
  - Blocked-by: yh454ur (Add the shared quickPresetDraft builder to MealRouting.swift)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.5](requirements.md#8.5)
  - References: design.md#The action on the two result surfaces

- [ ] 18. Build, test, spell, and run the Req 8 on-device checklist <!-- id:yh454uu -->
  - No new files, so no project.pbxproj registration - confirm that is still true before building
  - Run make build and make test; report both XCTest and swift-testing totals
  - Run make spell
  - Walk the Req 8 on-device checklist in design.md, including the schema-8 carry-over DB case and the sqlite3 check that source_meal_id survives an edit
  - Blocked-by: yh454us (Add Save as quick-add to MealReviewView post-capture), yh454ut (Add Save as quick-add to ResultView from records), yh454uq (Carry sourceMealID through QuickPresetEditSheet edits)
  - Stream: 1
  - Requirements: [8.6](requirements.md#8.6), [8.7](requirements.md#8.7)
  - References: design.md#Testing Strategy, docs/agent-notes/device-build-and-test.md
