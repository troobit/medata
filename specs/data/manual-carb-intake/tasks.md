---
references:
    - requirements.md
    - design.md
    - decision_log.md
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

- [ ] 7. Build CarbEntryModel and CarbEntrySheet (new + edit) <!-- id:yh454uj -->
  - New App/CarbEntryModel.swift (@Observable @MainActor): carbs text field state clamped 1-999, macro fields with disclosure-expanded-if-editing-has-macros per design.md, timestamp defaulting to now/back-dateable, save()/update() via store, optional editing: IntakeEntry? init param
  - New App/CarbEntrySheet.swift: NavigationStack, numeric keypad TextField for carbs (no stepper), DatePicker matching InsulinDoseSheet.timeRow, DisclosureGroup for protein/fat/fibre, Save button disabled below 1g
  - No test task — App-layer UI, build+on-device gate
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests), yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [7.2](requirements.md#7.2)
  - References: design.md#Views

- [ ] 8. Build QuickPresetEditSheet and save-as-preset action <!-- id:yh454uk -->
  - New App/QuickPresetEditSheet.swift: name field + carb/macro fields, create or edit an existing QuickPreset
  - CarbEntrySheet gains the "Save as quick-add" secondary action opening QuickPresetEditSheet pre-filled from the just-saved entry's values, independent of the entry save (cancelling creates no preset)
  - No test task — App-layer UI
  - Blocked-by: yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4)
  - References: design.md#Views

- [ ] 9. Build IntakeModel <!-- id:yh454ul -->
  - New App/IntakeModel.swift (@Observable @MainActor): loads/reloads quickPresets() and recent intake entries via events(in:type:) with the all-time sentinel + own private intakeEntry(from:) decoder, sorted desc + truncated in Swift per design.md
  - tapPreset(_:) calls saveIntakeEntry directly with source=.quickadd/presetID set, no sheet
  - Subscribes to store.eventsDidChange, same pattern as MealHistoryModel/RecordsModel
  - delete(_:) for both recent entries and presets
  - Blocked-by: yh454ue (Implement EventType.intake, IntakeSubtype/IntakeMacros/IntakeSource/IntakeEntry, and saveIntakeEntry/updateIntakeEntry/deleteIntakeEntry to pass tests), yh454ug (Implement quick_presets schema v4->v5 migration and QuickPreset CRUD to pass tests)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.3](requirements.md#4.3), [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)
  - References: design.md#Views

- [ ] 10. Replace IntakeView.swift wholesale and wire quick-add grid + recent-entries list <!-- id:yh454um -->
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

- [ ] 11. Register new files in project.pbxproj and build <!-- id:yh454un -->
  - Register IntakeEvent.swift, CarbEntryModel.swift, CarbEntrySheet.swift, QuickPresetEditSheet.swift, IntakeModel.swift, IntakeEventTests.swift, QuickPresetTests.swift in MeData.xcodeproj/project.pbxproj (four-section checklist per docs/agent-notes/ui-capture-flow.md)
  - Run make build and make test; report both XCTest and swift-testing totals
  - Run make spell
  - Blocked-by: yh454uh (Extend TrendsModel to fold .intake events into carbBars), yh454ui (Add RecordRow.intakeIntakeRecord case and wire RecordsModel/delete), yh454uj (Build CarbEntryModel and CarbEntrySheet new + edit), yh454uk (Build QuickPresetEditSheet and save-as-preset action), yh454ul (Build IntakeModel), yh454um (Replace IntakeView.swift wholesale and wire quick-add grid + recent-entries list)
  - Stream: 1
  - References: docs/agent-notes/ui-capture-flow.md, docs/agent-notes/device-build-and-test.md
