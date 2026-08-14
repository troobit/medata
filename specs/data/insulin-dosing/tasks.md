---
references:
    - specs/data/insulin-dosing/requirements.md
    - specs/data/insulin-dosing/design.md
    - specs/data/insulin-dosing/decision_log.md
metadata:
    ledger_note: |-
        Iteration 1 is phases 1-5. Phases 6 and 7 are tracked but unstartable: every task in
        them names the evidence that must exist before it may begin, and none of that
        evidence exists yet. A pending task in those phases is NOT actionable now — treat
        the BLOCKED-ON EVIDENCE bullet as the real gate, not the empty checkbox.

        Tasks whose title contains STOP need a physical iPhone 16 Pro, an export of the live
        database, or a human verdict. They are never run autonomously.

        Test gate: MedataCore maths gets tests (DosingTests, PersistenceTests). No app-target
        test scaffolding is written — MeData/Tests/ and MeData/UITests/ are documentation
        contracts, not an executable suite, and no committed target runs them.
---
# Tasks: Insulin Dosing

## Phase 1 — Pure calculator (macOS-testable, agent-executable)

- [ ] 1. Add the Dosing SwiftPM target and DosingTests to Package.swift <!-- id:idz0001 -->
  - Zero dependencies, Foundation only; the dependency list MUST stay empty
  - Persistence does not import Dosing and Dosing does not import Persistence — the firewall is structural, so no dump-package graph test is written
  - Stream: 1
  - Requirements: [10.2](requirements.md#10.2), [10.3](requirements.md#10.3)
  - References: design.md#Module layout and the firewall (Req 10.3)

- [ ] 2. CarbRatio and CarbRatioTable — one direction, named in the type <!-- id:idz0002 -->
  - CarbRatio holds gramsPerUnit only; the reciprocal exists solely as the display-derivation unitsPerTenGrams
  - Failable init rejecting anything outside 1.0...60.0 and any non-finite value
  - CarbRatioTable.seed = overnight 10.0, breakfast 5.0, lunch 10.0, dinner 10.0 g/U; ratio(for:) reports whether the seed or a configured value applied
  - Blocked-by: idz0001 (Add the Dosing SwiftPM target and DosingTests to Package.swift)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [9.5](requirements.md#9.5)
  - References: design.md#The ratio: one direction, named in the type (Req 1)
  - [ ] 2.1. Tests: init rejects 0.9, 60.1, NaN and infinity; accepts both interval endpoints; unitsPerTenGrams renders 2.0 for 5.0 g/U; an unconfigured band falls back to its seed and reports isSeed <!-- id:idz0003 -->
    - Stream: 1
    - Requirements: [1.5](requirements.md#1.5), [1.6](requirements.md#1.6)

- [ ] 3. DoseBand classifier over medreg's boundary hours in local time <!-- id:idz0004 -->
  - overnight 0..<6, breakfast 6..<11, lunch 11..<16, dinner 16..<24; the boundary hour opens the band it starts
  - band(at:calendar:) takes the Calendar (and therefore the time zone) as a parameter and never reaches for a global
  - Expose the local hour, the UTC hour and the UTC offset in seconds derived from the same instant, so the local-versus-UTC disagreement is a recordable quantity
  - Blocked-by: idz0001 (Add the Dosing SwiftPM target and DosingTests to Package.swift)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [10.2](requirements.md#10.2)
  - References: design.md#Bands: medreg's boundaries, the device's clock (Req 2)
  - [ ] 3.1. Tests: boundaries at 00:00, 05:59, 06:00, 10:59, 11:00, 15:59, 16:00, 23:59; a daylight-saving transition day; a non-UTC zone asserting local hour and UTC hour differ and the offset matches <!-- id:idz0005 -->
    - Stream: 1
    - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5)

- [ ] 4. InsulinActivityModel and insulinOnBoard — medreg's curve transcribed <!-- id:idz0006 -->
  - Exponential oref0/LoopKit form with medreg's rapidActing preset: peak 75 min, duration 360 min; derived tau 101.785714, a 0.565476, S 2.082955
  - remainingFraction is 1.0 at or before delivery and 0.0 at or beyond the duration of action
  - insulinOnBoard sums units times remaining fraction over prior boluses only; basal excluded; empty history yields zero and is not an error
  - Blocked-by: idz0001 (Add the Dosing SwiftPM target and DosingTests to Package.swift)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [9.8](requirements.md#9.8)
  - References: design.md#Insulin-on-board: medreg's curve, transcribed (Req 4)
  - [ ] 4.1. Tests: the shared fixture table at 0/30/75/120/180/240/300/360 minutes to 1e-4, well inside the 0.01 U cross-repository tolerance; basal excluded from the sum; a dose at exactly 360 minutes contributes zero <!-- id:idz0007 -->
    - Stream: 1
    - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.6](requirements.md#4.6), [9.8](requirements.md#9.8)

- [ ] 5. DoseSuggester: DoseInputs, DoseOutcome, SuggestedDose, SuppressionReason <!-- id:idz0008 -->
  - The seven ordered steps of design.md, in that order: absent carbs suppresses; band and ratio; exact = max(0, carbs / gramsPerUnit - iob); the 0.5 U test on the UNROUNDED value; rounding half away from zero applied ONCE to the final value; the control-minimum suppression; the seed with its clamp flag
  - SuggestionContext carries band, hours, offset, ratio and insulin-on-board even on a suppression, because a suppressed suggestion is recorded as fully as a made one
  - DosableIncrement accepts 0.5 and 1.0 only; ruleID "cr-v0", ruleVersion 1
  - No fat, correction, confidence or activity term enters the arithmetic
  - Blocked-by: idz0002 (CarbRatio and CarbRatioTable — one direction, named in the type), idz0004 (DoseBand classifier over medreg's boundary hours in local time), idz0006 (InsulinActivityModel and insulinOnBoard — medreg's curve transcribed)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [10.2](requirements.md#10.2)
  - References: design.md#The suggester (Req 3, 5)
  - [ ] 5.1. Tests: exact 0.49 suppressed and 0.50 suggested; a 3 g quick-add at 10 g/U suppressed rather than clamped up; rounding half away from zero at both increments; a case where rounding the carb term and the insulin-on-board term separately would differ, proving rounding is applied once; the 0.5 U increment case that rounds below the control floor; clamping above 60 U preserving exactUnits; determinism on repeated identical inputs <!-- id:idz0009 -->
    - Stream: 1
    - Requirements: [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)

## Phase 2 — Ledger persistence (macOS-testable, agent-executable)

- [x] 6. dose_suggestions table and DoseSuggestionRecord <!-- id:idz000a -->
  - CREATE TABLE IF NOT EXISTS retrofitted into the existing createSchema DDL block, schema_version stamped 7 to 8, plus the timestamp index
  - All columns of design.md including exact_units, cr_g_per_u, cr_source, cr_fit_ref, band, local_hour, utc_hour, utc_offset_s, iob_u, sigma_meal, start_bg_mmol, start_bg_age_s, fat_g, protein_g, fpu, fat_stale, rule_id, rule_version, fat_rule_id, fat_rule_version, row_version, build_stamp
  - fpu = (fat_g x 9 + protein_g x 4) / 100 computed at write time and stored, never derived on read
  - No eviction bound — unlike estimation_outcomes, the longitudinal series is the product
  - DoseSuggestionRecord lives in Persistence, not in Dosing, so the firewall holds
  - Blocked-by: idz0008 (DoseSuggester: DoseInputs, DoseOutcome, SuggestedDose, SuppressionReason)
  - Stream: 1
  - Requirements: [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.6](requirements.md#7.6), [7.8](requirements.md#7.8), [7.9](requirements.md#7.9), [8.1](requirements.md#8.1), [8.3](requirements.md#8.3), [10.5](requirements.md#10.5)
  - References: design.md#The ledger (Req 7)

- [x] 7. saveDoseSuggestion, linkDose and doseSuggestions on PersistenceStore <!-- id:idz000b -->
  - INSERT OR REPLACE by id so a review-screen correction rewrites the same row rather than appending one per keystroke
  - linkDose is an UPDATE on the side table only; the insulin event's metadata JSON is written exactly as today — kind, insulin_type, schema_version, note — and no key is added
  - None of the three notifies eventsDidChange
  - Blocked-by: idz000a (dose_suggestions table and DoseSuggestionRecord)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [9.7](requirements.md#9.7), [10.5](requirements.md#10.5)
  - References: design.md#The ledger (Req 7)
  - [x] 7.1. Tests: round-trip save then read newest-first; a second save with the same id replaces rather than appends; linkDose fills given_units and insulin_event_id; neither write fires eventsDidChange; an upgrade from a schema-7 database keeps every existing event <!-- id:idz000c -->
    - Stream: 1
    - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [10.5](requirements.md#10.5)

## Phase 3 — Settings plumbing

- [ ] 8. Seven SettingsKeys constants for the ratios, increment and provenance <!-- id:idz000d -->
  - Four per-band ratio keys in GRAMS PER UNIT, the pen increment, the ratio source, and the free-text medreg fit reference
  - Flat keys of the same kind as insulinTypeBolus — no structured or array-valued setting is introduced
  - An absent per-band key means the seed default is in force and the suggestion row records that
  - Blocked-by: idz0002 (CarbRatio and CarbRatioTable — one direction, named in the type)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)
  - References: design.md#Settings: seven flat keys, no new shape (Req 1.3, 6.9, 9.4)

- [ ] 9. Settings rows in the existing Insulin section <!-- id:idz000e -->
  - Four LabeledContent rows in band order, each a trailing decimal field suffixed g/U with the reciprocal rendered beneath as read-only secondary text
  - Pen increment picker (0.5 or 1 U), ratio source picker (Chosen or medreg), medreg fit free-text field
  - Validation is CarbRatio.init? and DosableIncrement.init?: a rejected entry reverts on commit with no error copy
  - No new screen
  - Blocked-by: idz000d (Seven SettingsKeys constants for the ratios, increment and provenance)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [5.6](requirements.md#5.6), [6.8](requirements.md#6.8), [6.9](requirements.md#6.9), [9.3](requirements.md#9.3)
  - References: design.md#Settings: seven flat keys, no new shape (Req 1.3, 6.9, 9.4)

## Phase 4 — App wiring

- [ ] 10. DoseSubject and DoseSuggestionModel <!-- id:idz000f -->
  - MainActor Observable, owned by AppRoot so a seed armed inside the Capture cover survives that cover's dismissal
  - refresh(for:) reads Settings, queries the 360-minute bolus window and the last glucose reading, calls the pure suggester, publishes the readout and writes the ledger row in a detached task so a persistence failure never blocks or delays recording
  - The starting glucose is RECORDED ONLY — no correction term consumes it in iteration 1
  - arm(from:) sets a seed with a 45-minute lifetime; takeSeed() returns nil once it lapses
  - Producing a suggestion never writes an insulin event
  - Blocked-by: idz0008 (DoseSuggester: DoseInputs, DoseOutcome, SuggestedDose, SuppressionReason), idz000b (saveDoseSuggestion, linkDose and doseSuggestions on PersistenceStore), idz000d (Seven SettingsKeys constants for the ratios, increment and provenance)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.7](requirements.md#3.7), [4.5](requirements.md#4.5), [4.7](requirements.md#4.7), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.7](requirements.md#7.7), [8.1](requirements.md#8.1), [8.3](requirements.md#8.3), [10.1](requirements.md#10.1)
  - References: design.md#Data flow: estimate to suggestion to seed

- [ ] 11. Meal review readout on the existing mass line <!-- id:idz000g -->
  - Append a middle-dot segment to the second line of totalRow at the same subheadline monospacedDigit and captureChromeText opacity, as an HStack of two Texts so the line height is unchanged and the scale control stays above the scroll boundary
  - New accessibility identifier review.doseSuggestion beside the retained review.massLine
  - numericText transition and smooth animation, both gated on reduceMotion, exactly as the other animated numerals on that screen
  - No accent colour, no banner card, no second primary control, and no disclaimer, warning or confidence copy anywhere
  - A suppressed suggestion is an absent segment, not explanatory text
  - Blocked-by: idz000f (DoseSubject and DoseSuggestionModel)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8)
  - References: design.md#Presentation (Req 6)

- [ ] 12. Manual intake path — same readout, same arming <!-- id:idz000h -->
  - CarbEntrySheet shows the same middle-dot segment in its existing secondary line
  - A quick-add preset tap shows nothing, arms the seed and writes its ledger row — the suggestion reaches the developer one tap later as the sheet's opening value
  - The suggestion is not silently absent for carbohydrates that did not arrive through the camera
  - Blocked-by: idz000f (DoseSubject and DoseSuggestionModel)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7)
  - References: design.md#Presentation (Req 6)

- [ ] 13. Seed the dose sheet through one optional initialiser parameter <!-- id:idz000i -->
  - InsulinDoseModel.init(store:seed:) and InsulinDoseSheet.init(store:seed:), both defaulted nil, at the single construction site in AppRoot
  - A nil seed opens at 10 U exactly as today, so the home Dose control and the insulin add deep link are behaviourally unchanged and both two-tap paths survive
  - No sheet is presented from inside the Capture cover, so the pendingDeepLink sequencing is untouched
  - The seeded amount stays freely adjustable and the amount actually saved is recorded unmodified; on save call linkDose
  - Blocked-by: idz000f (DoseSubject and DoseSuggestionModel), idz000b (saveDoseSuggestion, linkDose and doseSuggestions on PersistenceStore)
  - Stream: 1
  - Requirements: [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [7.5](requirements.md#7.5), [9.7](requirements.md#9.7)
  - References: design.md#The seam: where 10 U becomes a suggestion (Req 6.3, 6.4)

## Phase 5 — Verify

- [ ] 14. make test green, make build, make spell <!-- id:idz000j -->
  - Report BOTH totals from make test — XCTest and swift-testing
  - Blocked-by: idz000g (Meal review readout on the existing mass line), idz000h (Manual intake path — same readout, same arming), idz000i (Seed the dose sheet through one optional initialiser parameter), idz000c (Tests: round-trip save then read newest-first)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.3](requirements.md#10.3)

- [ ] 15. STOP — on-device verification on the iPhone 16 Pro <!-- id:idz000k -->
  - Capture a meal and confirm the dose figure appears on the mass line with the plate-scale control still visible without scrolling
  - Confirm the dose sheet opens seeded after recording, and opens at 10 U from the home control and the deep link when nothing is armed
  - Confirm a quick-add preset arms a seed and shows nothing on the preset button
  - Match the launch build stamp before trusting anything the device reports
  - Read back the dose_suggestions rows from the device database and confirm the exact unrounded units, band, hours, offset, insulin-on-board, fat, protein and fpu are all populated
  - Human verdict; never run autonomously
  - Blocked-by: idz000j (make test green, make build, make spell)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.2](requirements.md#7.2)

## Phase 6 — Evidence gate before any scoring (BLOCKED — no evidence exists yet)

- [ ] 16. STOP — retrospective measurement over an exported live database <!-- id:idz000l -->
  - BLOCKED-ON EVIDENCE: needs a human-produced export of the real device database; there is no synthetic substitute and no agent may fabricate one
  - tools/dosing/retrospective.py emitting compact key=value lines, no narration
  - Reports the sigma_meal distribution; the fpu distribution across recorded meals; meal-or-intake to bolus pairing yield inside 45 minutes; glucose coverage across the 6 hours after each such dose; the rate at which a further bolus lands inside that window; and the combined surviving fraction under all the confounding filters
  - The surviving fraction is the single number that decides whether an outcome scorer is viable at all
  - The filters are NOT loosened to raise that number
  - Blocked-by: idz000k (STOP — on-device verification on the iPhone 16 Pro)
  - Stream: 1
  - Requirements: [11.2](requirements.md#11.2), [11.4](requirements.md#11.4)
  - References: design.md#The evidence gate before any scoring (Req 11)

- [ ] 17. STOP — record the scoring verdict from task 16 <!-- id:idz000m -->
  - BLOCKED-ON EVIDENCE: task 16's surviving fraction
  - IF too few unconfounded windows survive to distinguish one ratio from another, outcome scoring is NOT built and the ratios stay configured values for longer — that is an acceptable result recorded as a decision, not a failure
  - Only a positive verdict opens the scoring work, and any ratio adjustment ever proposed from outcomes is applied by an explicit user tap, never automatically, with rows either side of the change distinguishable so no comparison pools them
  - Human verdict; never run autonomously
  - Blocked-by: idz000l (STOP — retrospective measurement over an exported live database)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1), [11.3](requirements.md#11.3), [11.5](requirements.md#11.5)

## Phase 7 — Fat programme (BLOCKED — staged, each stage names its precondition)

- [ ] 18. F1 — user corrections carry corrected fat and protein <!-- id:idz000n -->
  - PbUserCorrection gains corrected_fat_g and corrected_protein_g, written from Macros.reDerive, which already computes both
  - The cheapest gate to clear and independent of every other fat stage: without it the fat figure is least trustworthy on exactly the meals that got the most human attention
  - Until this lands, fat_stale flags those rows and any fat rule refuses them
  - Blocked-by: idz000j (make test green, make build, make spell)
  - Stream: 2
  - Requirements: [8.3](requirements.md#8.3), [8.8](requirements.md#8.8)
  - References: design.md#Fat: the staged plan (Req 8)

- [ ] 19. STOP — weigh one reference meal against the pipeline's fat estimate <!-- id:idz000o -->
  - BLOCKED-ON EVIDENCE: needs a physically weighed and reference-counted meal; benchmark_meals holds truth_carbs_g and nothing else, so the fat figure has no ground truth anywhere in this repository
  - clinicalTotals.fat_g is computed and persisted but read by no app surface — it has never been checked against anything
  - Human execution and human verdict; never run autonomously
  - Blocked-by: idz000k (STOP — on-device verification on the iPhone 16 Pro)
  - Stream: 2
  - Requirements: [8.7](requirements.md#8.7), [8.8](requirements.md#8.8)

- [ ] 20. STOP — establish whether a delayed rise follows high fat-protein units for this user <!-- id:idz000p -->
  - BLOCKED-ON EVIDENCE: needs the recorded fpu column populated over months of real meals plus the glucose coverage measured in task 16
  - The materiality threshold is set at the knee of THIS user's own recorded distribution, never adopted from a published constant
  - The gate is disjunctive — high fpu OR high protein alone — because the conjunctive published rule is silent on the 50 g fat, 20 g protein pizza that motivated this work
  - IF no late rise is visible, the fat programme stops here and that is a result
  - Human verdict; never run autonomously
  - Blocked-by: idz000l (STOP — retrospective measurement over an exported live database)
  - Stream: 2
  - Requirements: [8.6](requirements.md#8.6), [8.7](requirements.md#8.7), [8.8](requirements.md#8.8)

- [ ] 21. F2 — implement exactly one fat rule, default off <!-- id:idz000q -->
  - BLOCKED-ON EVIDENCE: all three of task 18, task 19 and task 20 must have cleared; no fat strategy changes a suggested number before then
  - One rule only, chosen by what task 20 showed, from the four enumerated candidates: fat-uplift-v1, fat-split-v1, fat-protein-v1, fat-fpu-v1
  - Stamped by fat_rule_id and fat_rule_version on every row it produces so outcomes are never pooled across rules
  - Ships disabled by default and refuses to run on rows flagged fat_stale
  - Blocked-by: idz000n (F1 — user corrections carry corrected fat and protein), idz000o (STOP — weigh one reference meal against the pipeline's fat estimate), idz000p (STOP — establish whether a delayed rise follows high fat-protein units for this user)
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [7.9](requirements.md#7.9)
  - References: design.md#Fat: the staged plan (Req 8)

- [ ] 22. F3 — delayed follow-up suggestion and the notification surface it needs <!-- id:idz000r -->
  - BLOCKED-ON EVIDENCE: task 21 must first show its rule actually moves the late excursion
  - Also blocked on machinery that does not exist: the app has no notification, timer or scheduling surface at all today
  - Records the ACTUAL elapsed time at which the follow-up dose was given, not merely that one was given — otherwise a dose given at 4 h scores as if it were given at 2.5 h
  - Blocked-by: idz000q (F2 — implement exactly one fat rule, default off)
  - Stream: 2
  - Requirements: [8.9](requirements.md#8.9), [8.5](requirements.md#8.5)

- [ ] 23. F4 — a second fat rule, arbitrated against the first <!-- id:idz000s -->
  - BLOCKED-ON EVIDENCE: task 22 must be producing follow-ups that are actually taken
  - Stratified by fat-protein-unit band with n reported per cell
  - Deterministic alternation is not randomisation: a rule landing systematically on the same weekday meal is a live confound the ledger will not flag by itself
  - Blocked-by: idz000r (F3 — delayed follow-up suggestion and the notification surface it needs)
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [7.9](requirements.md#7.9)

## Phase 8 — Spec reconciliation (unblocked; do first)

- [ ] 24. Annotate the superseded non-goal in the shipped PRD — do not rewrite it <!-- id:idz000t -->
  - Discharges the first clause of Decision 1's Impact section, which reads: "specs/regression-suggestion-integration/prd.md (one cross-reference line), specs/OVERVIEW.md, and everything in this spec." The third clause is this spec; the first two had no task until now, so the repo contradicts itself in a way no ledger surfaced. Neither this task nor task 25 depends on any code
  - `specs/regression-suggestion-integration/prd.md` currently states, under `## Non-goals`: "No dose suggestion, insulin-on-board, or regression maths in the app — medreg owns all modelling, off-device, against exported data." That is now false in part and nothing on the page says so
  - Add ONE cross-reference line beneath that bullet pointing at `specs/data/insulin-dosing/decision_log.md` Decision 1, "Reverse the 'no dose suggestion in the app' non-goal, narrowly". Do NOT delete or reword the original bullet: that PRD is marked Done and is a record of what shipped, so editing its text destroys the record, while annotating it preserves both the original intent and the reversal
  - State the scope precisely, because the reversal is narrow: dose-suggestion arithmetic and insulin-on-board move on-device; parameter FITTING does not, and `~/repos/medreg` remains the only place parameters are estimated from history
  - The two neighbouring non-goals survive untouched and must be seen to survive: "No confidence scores, gating, warnings, reassurance, or disclaimer copy (developer-phase copy rule, CLAUDE.md)" and "No changes to the medreg repository"
  - Run `make spell` after the edit
  - Requirements: [10.5](requirements.md#10.5)

- [ ] 25. Regenerate the specs index so it carries this spec and activity-events <!-- id:idz000u -->
  - `/specs-overview` — `specs/OVERVIEW.md` is a generated index and currently lists neither `specs/data/insulin-dosing` nor `specs/data/activity-events`
  - Also confirm the regenerated Segmenter Foundation row no longer contradicts itself: it currently reads both "19 of 22 tasks done" and "ALL 23 tasks done" in the same cell
  - Blocked-by: idz000t (Annotate the superseded non-goal in the shipped PRD — do not rewrite it)
